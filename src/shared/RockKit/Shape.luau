--[[
	Shape — gera a geometria facetada de uma rocha.

	Pipeline:
	  1. icosaedro (opcionalmente subdividido) como esfera base;
	  2. deslocamento radial por ruído fractal  -> massa irregular;
	  3. afinamento (taper) em direção ao topo   -> agulhas e picos;
	  4. planos de clivagem                      -> faces chatas de granito quebrado;
	  5. base achatada                           -> a pedra "senta" no chão;
	  6. escala anisotrópica + inclinação        -> proporções do preset;
	  7. triangulação com normal por face        -> visual low poly facetado.

	Tudo é determinístico: o mesmo seed devolve exatamente a mesma rocha.
]]

local Noise = require(script.Parent.Noise)

local Shape = {}

local PHI = (1 + math.sqrt(5)) / 2

-- Icosaedro regular (12 vértices, 20 faces).
local ICOSAHEDRON_VERTICES: { Vector3 } = {
	Vector3.new(-1, PHI, 0),
	Vector3.new(1, PHI, 0),
	Vector3.new(-1, -PHI, 0),
	Vector3.new(1, -PHI, 0),
	Vector3.new(0, -1, PHI),
	Vector3.new(0, 1, PHI),
	Vector3.new(0, -1, -PHI),
	Vector3.new(0, 1, -PHI),
	Vector3.new(PHI, 0, -1),
	Vector3.new(PHI, 0, 1),
	Vector3.new(-PHI, 0, -1),
	Vector3.new(-PHI, 0, 1),
}

local ICOSAHEDRON_FACES: { { number } } = {
	{ 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 },
	{ 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 }, { 11, 8, 7 }, { 8, 2, 9 },
	{ 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 },
	{ 5, 10, 6 }, { 3, 5, 12 }, { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 },
}

-- Normaliza a base uma única vez, no carregamento do módulo.
for index, vertex in ICOSAHEDRON_VERTICES do
	ICOSAHEDRON_VERTICES[index] = vertex.Unit
end

export type Triangle = {
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
}

export type Geometry = {
	triangles: { Triangle },
	size: Vector3,
}

export type ShapeParams = {
	seed: number,
	size: Vector3,
	subdivisions: number,
	amplitude: number,
	frequency: number,
	octaves: number,
	cleaves: number,
	cleaveDepth: { number },
	cleaveVertical: number,
	cleaveFamilies: number,
	cleaveJitter: number,
	taperTop: number,
	taperCurve: number,
	tilt: number,
	flatBase: boolean,
	flatBaseDepth: number,
}

-- Divide cada triângulo em quatro e reprojeta os pontos novos na esfera.
local function subdivide(vertices: { Vector3 }, faces: { { number } }): ({ Vector3 }, { { number } })
	local cache: { [number]: number } = {}
	local result = table.create(#faces * 4)

	local function midpoint(i: number, j: number): number
		local low, high = math.min(i, j), math.max(i, j)
		local key = low * 1048576 + high
		local cached = cache[key]
		if cached then
			return cached
		end

		local point = (vertices[low] + vertices[high])
		-- Vértices antípodas somariam zero; nesse caso qualquer ponto do meio serve.
		point = if point.Magnitude > 1e-6 then point.Unit else vertices[low]

		table.insert(vertices, point)
		local id = #vertices
		cache[key] = id
		return id
	end

	for _, face in faces do
		local a, b, c = face[1], face[2], face[3]
		local ab, bc, ca = midpoint(a, b), midpoint(b, c), midpoint(c, a)
		table.insert(result, { a, ab, ca })
		table.insert(result, { b, bc, ab })
		table.insert(result, { c, ca, bc })
		table.insert(result, { ab, bc, ca })
	end

	return vertices, result
end

local function bounds(points: { Vector3 }): (Vector3, Vector3)
	local min, max = points[1], points[1]
	for _, point in points do
		min = min:Min(point)
		max = max:Max(point)
	end
	return min, max
end

function Shape.generate(params: ShapeParams): Geometry
	local rng = Random.new(params.seed)
	local offset = Noise.offsetFromSeed(params.seed)

	-- 1. esfera base
	local points = table.clone(ICOSAHEDRON_VERTICES)
	local faces = ICOSAHEDRON_FACES
	for _ = 1, math.max(params.subdivisions, 0) do
		points, faces = subdivide(points, faces)
	end

	-- 2 + 3. ruído radial e afinamento
	for index, direction in points do
		local n = Noise.fbm(direction * params.frequency + offset, params.octaves, 2.07, 0.5)
		local radius = 1 + n * 2 * params.amplitude
		local point = direction * radius

		local height = math.clamp((direction.Y + 1) * 0.5, 0, 1)
		local shrink = 1 + (params.taperTop - 1) * height ^ params.taperCurve
		points[index] = Vector3.new(point.X * shrink, point.Y, point.Z * shrink)
	end

	-- 4. planos de clivagem: tudo que passa do plano é projetado sobre ele,
	-- criando uma face chata sem mexer na topologia.
	--
	-- Os planos não são sorteados soltos: eles saem de um punhado de direções
	-- "família", com jitter pequeno e sinal alternado. É assim que rocha real
	-- quebra — ao longo de juntas mais ou menos paralelas — e é o que dá as
	-- faces longas e paralelas das agulhas da referência. Planos independentes
	-- demais devolvem uma batata lixada.
	local function direction(verticalWeight: number): Vector3
		local vector = Vector3.new(
			rng:NextNumber(-1, 1),
			rng:NextNumber(-verticalWeight, verticalWeight),
			rng:NextNumber(-1, 1)
		)
		if vector.Magnitude < 1e-3 then
			return Vector3.xAxis
		end
		return vector.Unit
	end

	local familyCount = math.max(params.cleaveFamilies, 1)
	local families = table.create(familyCount)
	for index = 1, familyCount do
		families[index] = direction(params.cleaveVertical)
	end

	for index = 1, params.cleaves do
		local base = families[(index - 1) % familyCount + 1]
		if rng:NextNumber() < 0.5 then
			base = -base
		end

		local normal = base + direction(1) * params.cleaveJitter
		if normal.Magnitude < 1e-3 then
			continue
		end
		normal = normal.Unit

		local distance = rng:NextNumber(params.cleaveDepth[1], params.cleaveDepth[2])
		for pointIndex, point in points do
			local overshoot = point:Dot(normal) - distance
			if overshoot > 0 then
				points[pointIndex] = point - normal * overshoot
			end
		end
	end

	-- 5. base plana.
	-- O corte é medido a partir da altura real da pedra, não do raio nominal da
	-- esfera: os planos de clivagem já encolheram a massa, então um limite fixo
	-- em -1 passaria longe e não cortaria nada.
	if params.flatBase then
		local low, high = bounds(points)
		local floor = low.Y + (high.Y - low.Y) * params.flatBaseDepth
		for index, point in points do
			if point.Y < floor then
				points[index] = Vector3.new(point.X, floor, point.Z)
			end
		end
	end

	-- 6. escala para o tamanho pedido e inclinação
	local min, max = bounds(points)
	local extent = max - min
	local center = (min + max) * 0.5
	local scale = Vector3.new(
		params.size.X / math.max(extent.X, 1e-3),
		params.size.Y / math.max(extent.Y, 1e-3),
		params.size.Z / math.max(extent.Z, 1e-3)
	)
	for index, point in points do
		points[index] = (point - center) * scale
	end

	if params.tilt > 1e-4 then
		local axis = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		if axis.Magnitude > 1e-3 then
			local rotation = CFrame.fromAxisAngle(axis.Unit, params.tilt)
			for index, point in points do
				points[index] = rotation * point
			end
		end
	end

	-- O pivô de um MeshPart fica no centro da bounding box, então recentramos
	-- aqui para que Size e posição batam com o que a geometria realmente ocupa.
	min, max = bounds(points)
	center = (min + max) * 0.5
	for index, point in points do
		points[index] = point - center
	end

	-- 7. triangulação facetada
	local triangles: { Triangle } = table.create(#faces)
	for _, face in faces do
		local a, b, c = points[face[1]], points[face[2]], points[face[3]]
		local cross = (b - a):Cross(c - a)
		if cross.Magnitude < 1e-7 then
			-- triângulo degenerado (colapsou num plano de clivagem)
			continue
		end

		local normal = cross.Unit
		local centroid = (a + b + c) / 3
		-- A malha é estrelada em relação ao centro, então o centroide aponta
		-- para fora: se a normal discorda, a ordem dos vértices está invertida.
		if normal:Dot(centroid) < 0 then
			b, c = c, b
			normal = -normal
		end

		table.insert(triangles, { a = a, b = b, c = c, normal = normal })
	end

	return {
		triangles = triangles,
		size = max - min,
	}
end

return Shape
