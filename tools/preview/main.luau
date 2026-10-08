--[[
	Verifica a geometria do RockKit fora do Roblox e despeja as malhas em OBJ
	na saída padrão, para o run.py renderizar a prévia.

	Rode com:  python3 tools/preview/run.py
]]

local Shape = __require("Shape")
local Presets = __require("Presets")

local failures = 0

local function check(condition: any, message: string)
	if not condition then
		failures += 1
		print("FALHA: " .. message)
	end
end

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function validate(label: string, params: any, geometry: any)
	check(#geometry.triangles > 0, label .. ": geometria vazia")

	local min, max = nil, nil
	for index, tri in geometry.triangles do
		for _, point in { tri.a, tri.b, tri.c, tri.normal } do
			check(
				finite(point.X) and finite(point.Y) and finite(point.Z),
				("%s: coordenada inválida no triângulo %d"):format(label, index)
			)
		end

		check(
			math.abs(tri.normal.Magnitude - 1) < 1e-3,
			("%s: normal não unitária no triângulo %d"):format(label, index)
		)

		-- a ordem dos vértices precisa produzir a normal armazenada
		local cross = (tri.b - tri.a):Cross(tri.c - tri.a)
		check(cross:Dot(tri.normal) > 0, ("%s: winding invertido no triângulo %d"):format(label, index))

		-- malha estrelada em relação à origem: toda face olha para fora
		local centroid = (tri.a + tri.b + tri.c) / 3
		check(
			tri.normal:Dot(centroid) >= -1e-9,
			("%s: normal apontando para dentro no triângulo %d"):format(label, index)
		)

		for _, point in { tri.a, tri.b, tri.c } do
			min = if min then min:Min(point) else point
			max = if max then max:Max(point) else point
		end
	end

	local size = max - min
	check(size.X > 0 and size.Y > 0 and size.Z > 0, label .. ": bounding box degenerada")

	-- base plana: tem que existir um conjunto de vértices no mesmo Y mínimo
	if params.flatBase then
		local onFloor = 0
		local epsilon = (max.Y - min.Y) * 1e-3
		for _, tri in geometry.triangles do
			for _, point in { tri.a, tri.b, tri.c } do
				if point.Y <= min.Y + epsilon then
					onFloor += 1
				end
			end
		end
		check(onFloor >= 3, ("%s: base não ficou plana (%d vértices no piso)"):format(label, onFloor))
	end

	local center = (min + max) * 0.5
	local tolerance = 1e-4 * math.max(size.X, size.Y, size.Z)
	check(
		math.abs(center.X) <= tolerance and math.abs(center.Y) <= tolerance and math.abs(center.Z) <= tolerance,
		("%s: bounding box fora do centro (%s)"):format(label, tostring(center))
	)

	-- sem inclinação, a caixa precisa bater exatamente com o tamanho pedido
	if params.tilt == 0 then
		for _, axis in { "X", "Y", "Z" } do
			local wanted, got = (params.size :: any)[axis], (size :: any)[axis]
			check(
				math.abs(wanted - got) <= wanted * 0.002,
				("%s: eixo %s saiu %.3f, esperado %.3f"):format(label, axis, got, wanted)
			)
		end
	end

	return size
end

local function emitObj(name: string, geometry: any)
	local lines = { "#OBJ " .. name }
	local count = 0
	for _, tri in geometry.triangles do
		table.insert(lines, ("v %.5f %.5f %.5f"):format(tri.a.X, tri.a.Y, tri.a.Z))
		table.insert(lines, ("v %.5f %.5f %.5f"):format(tri.b.X, tri.b.Y, tri.b.Z))
		table.insert(lines, ("v %.5f %.5f %.5f"):format(tri.c.X, tri.c.Y, tri.c.Z))
		table.insert(lines, ("f %d %d %d"):format(count + 1, count + 2, count + 3))
		count += 3
	end
	table.insert(lines, "#ENDOBJ")
	print(table.concat(lines, "\n"))
end

-- 1. um exemplar de cada preset simples
for _, name in Presets.names() do
	local seed = 20251008
	local params = Presets.resolve(name, seed, Random.new(seed))
	local geometry = Shape.generate(params)
	local size = validate(name, params, geometry)
	print(("#INFO %s triangulos=%d tamanho=%.2fx%.2fx%.2f"):format(
		name, #geometry.triangles, size.X, size.Y, size.Z
	))
	emitObj(name, geometry)
end

-- 2. variedade: mesma preset, seeds diferentes
for index = 1, 4 do
	local seed = 1000 + index * 37
	local params = Presets.resolve("Spire", seed, Random.new(seed))
	local geometry = Shape.generate(params)
	validate("Spire#" .. index, params, geometry)
	emitObj("Spire_seed" .. seed, geometry)
end

-- 3. determinismo: mesmo seed, mesma malha
do
	local params = Presets.resolve("Boulder", 777, Random.new(777))
	local a = Shape.generate(params)
	local b = Shape.generate(params)
	check(#a.triangles == #b.triangles, "determinismo: contagem de triângulos mudou")
	local identical = true
	for index, tri in a.triangles do
		local other = b.triangles[index]
		if (tri.a - other.a).Magnitude > 1e-9 or (tri.b - other.b).Magnitude > 1e-9 then
			identical = false
			break
		end
	end
	check(identical, "determinismo: mesmo seed gerou vértices diferentes")
end

-- 4. tamanhos extremos não quebram
for _, height in { 0.05, 0.4, 120 } do
	local params = Presets.resolve("Stone", 42, Random.new(42), { height = height })
	validate(("Stone@%.2f"):format(height), params, Shape.generate(params))
end

-- 5. o afinamento da agulha realmente afina
do
	local params = Presets.resolve("Spire", 99, Random.new(99), { height = 30 })
	local geometry = Shape.generate(params)
	local topWidth, bottomWidth = 0, 0
	for _, tri in geometry.triangles do
		for _, point in { tri.a, tri.b, tri.c } do
			local radius = math.sqrt(point.X * point.X + point.Z * point.Z)
			if point.Y > params.size.Y * 0.35 then
				topWidth = math.max(topWidth, radius)
			elseif point.Y < -params.size.Y * 0.35 then
				bottomWidth = math.max(bottomWidth, radius)
			end
		end
	end
	check(topWidth < bottomWidth * 0.6, ("agulha não afinou: topo %.2f vs base %.2f"):format(topWidth, bottomWidth))
end

if failures == 0 then
	print("#RESULT ok")
else
	print(("#RESULT %d falha(s)"):format(failures))
end
