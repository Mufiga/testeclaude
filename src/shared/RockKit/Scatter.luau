--[[
	Scatter — espalha cópias de um conjunto de rochas sobre o terreno.

	Trabalha por clonagem: recebe um punhado de variações já prontas e replica
	elas. Isso importa — 200 MeshParts clonados da mesma malha são muito mais
	baratos para o engine (e para o streaming) do que 200 malhas únicas.

	Cada ponto sai de um raycast de cima para baixo; o que não encostar no chão,
	cair em ladeira forte demais, cair abaixo do nível da água ou encostar numa
	pedra já colocada é descartado e sorteado de novo.
]]

local Scatter = {}

export type Variant = {
	instance: Instance,
	size: Vector3,
	bury: number,
}

export type ScatterOptions = {
	variants: { Variant },
	center: Vector3,
	areaSize: Vector3,
	count: number,
	seed: number?,
	-- distância mínima absoluta entre centros, em studs
	minSpacing: number?,
	-- 1.0 = pedras nunca se tocam; 0.7 = encostam um pouco; 0.4 = amontoadas
	packing: number?,
	-- inclinação máxima do chão, em graus
	maxSlope: number?,
	-- 0 = sempre em pé; 1 = totalmente alinhada à normal do chão
	alignToNormal: number?,
	-- descarta pontos abaixo desta altura (use o nível da sua água)
	waterLevel: number?,
	-- variação de escala aplicada a cada cópia
	scaleJitter: { number }?,
	-- só aceita pontos que caírem no Terrain
	terrainOnly: boolean?,
	parent: Instance?,
	ignore: { Instance }?,
}

local function orientationFromUp(up: Vector3, yaw: number): CFrame
	local forward = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local right = forward:Cross(up)
	if right.Magnitude < 1e-3 then
		-- chão perfeitamente vertical alinhado com o yaw sorteado
		right = Vector3.xAxis:Cross(up)
		if right.Magnitude < 1e-3 then
			right = Vector3.zAxis:Cross(up)
		end
	end
	-- fromMatrix com dois eixos calcula o terceiro: a base sai sempre ortonormal
	return CFrame.fromMatrix(Vector3.zero, right.Unit, up)
end

function Scatter.populate(options: ScatterOptions): { Instance }
	local variants = options.variants
	assert(variants and #variants > 0, "[RockKit] Scatter precisa de pelo menos uma variação.")

	local rng = Random.new(options.seed or os.time())
	local parent = options.parent or workspace
	local count = math.max(math.floor(options.count), 0)
	local half = options.areaSize * 0.5
	local maxSlope = options.maxSlope or 42
	local align = math.clamp(options.alignToNormal or 0.55, 0, 1)
	local packing = options.packing or 0.7
	local minSpacing = options.minSpacing or 0
	local waterLevel = options.waterLevel or -math.huge
	local jitter = options.scaleJitter or { 0.85, 1.25 }

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = table.clone(options.ignore or {})
	-- As pedras já colocadas ficam de fora do raycast para não empilharem umas
	-- nas outras. Só que ignorar `parent` quando ele é o próprio workspace
	-- apagaria o mundo inteiro do raycast — aí nada encontraria chão.
	if parent ~= workspace then
		table.insert(ignore, parent)
	end
	for _, variant in variants do
		table.insert(ignore, variant.instance)
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true

	-- Grade espacial simples: só comparamos contra as pedras das células vizinhas.
	local cell = math.max(minSpacing, 4)
	local grid: { [string]: { { position: Vector3, radius: number } } } = {}

	local function cellKey(x: number, z: number): string
		return string.format("%d:%d", math.floor(x / cell), math.floor(z / cell))
	end

	local function overlaps(position: Vector3, radius: number): boolean
		local cx, cz = math.floor(position.X / cell), math.floor(position.Z / cell)
		for dx = -1, 1 do
			for dz = -1, 1 do
				local bucket = grid[string.format("%d:%d", cx + dx, cz + dz)]
				if not bucket then
					continue
				end
				for _, placed in bucket do
					local delta = position - placed.position
					local distance = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
					if distance < math.max((radius + placed.radius) * packing, minSpacing) then
						return true
					end
				end
			end
		end
		return false
	end

	local placed: { Instance } = {}
	local attempts = 0
	local maxAttempts = count * 15 + 50

	while #placed < count and attempts < maxAttempts do
		attempts += 1

		local x = options.center.X + rng:NextNumber(-half.X, half.X)
		local z = options.center.Z + rng:NextNumber(-half.Z, half.Z)
		local origin = Vector3.new(x, options.center.Y + half.Y, z)

		local hit = workspace:Raycast(origin, Vector3.new(0, -options.areaSize.Y, 0), params)
		if not hit then
			continue
		end
		if hit.Position.Y < waterLevel then
			continue
		end
		if options.terrainOnly and not hit.Instance:IsA("Terrain") then
			continue
		end

		local slope = math.deg(math.acos(math.clamp(hit.Normal:Dot(Vector3.yAxis), -1, 1)))
		if slope > maxSlope then
			continue
		end

		local variant = variants[rng:NextInteger(1, #variants)]
		local scale = rng:NextNumber(jitter[1], jitter[2])
		local size = variant.size * scale
		local radius = math.max(size.X, size.Z) * 0.5

		if overlaps(hit.Position, radius) then
			continue
		end

		local clone = variant.instance:Clone()
		if clone:IsA("BasePart") then
			clone.Size = variant.size * scale
		elseif clone:IsA("Model") then
			clone:ScaleTo(scale)
		end

		local up = Vector3.yAxis:Lerp(hit.Normal, align)
		if up.Magnitude < 1e-3 then
			up = Vector3.yAxis
		end
		up = up.Unit

		local lift = size.Y * (0.5 - variant.bury)
		local cframe = orientationFromUp(up, rng:NextNumber(0, math.pi * 2)) + (hit.Position + up * lift)
		clone:PivotTo(cframe)
		clone.Parent = parent

		local key = cellKey(hit.Position.X, hit.Position.Z)
		local bucket = grid[key]
		if not bucket then
			bucket = {}
			grid[key] = bucket
		end
		table.insert(bucket, { position = hit.Position, radius = radius })
		table.insert(placed, clone)

		if #placed % 25 == 0 then
			task.wait()
		end
	end

	if #placed < count then
		warn(("[RockKit] espalhou %d de %d pedras (a área ficou sem espaço livre)."):format(#placed, count))
	end

	return placed
end

return Scatter
