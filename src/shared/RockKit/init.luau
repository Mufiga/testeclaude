--[[
	RockKit — rochas procedurais que combinam com o Terrain do Roblox.

	    local RockKit = require(game.ReplicatedStorage.RockKit)

	    -- uma pedra
	    RockKit.create({ preset = "Spire", biome = "Canyon", parent = workspace })

	    -- biblioteca de variações para arrastar na mão
	    RockKit.buildLibrary({ variants = 6, parent = game.ReplicatedStorage })

	    -- campo de pedras no terreno
	    RockKit.scatter({ center = Vector3.new(0, 0, 0), areaSize = Vector3.new(400, 500, 400), count = 150 })

	Presets simples: Pebble, Stone, Boulder, Slab, Shard, Spire, Cliff.
	Formações:       Peak, Cluster, Scree.
	Biomas:          Canyon, Mountain, Forest, Snow, Volcanic.

	Toda rocha é determinística: `seed` igual devolve geometria e cor iguais.
]]

local Palette = require(script.Palette)
local PartBuilder = require(script.PartBuilder)
local Presets = require(script.Presets)
local Scatter = require(script.Scatter)
local Shape = require(script.Shape)
local MeshBuilder = require(script.MeshBuilder)

local RockKit = {}

RockKit.Palette = Palette
RockKit.Presets = Presets
RockKit.Shape = Shape

local MAX_SEED = 2 ^ 31 - 2

export type CreateOptions = {
	preset: string?,
	seed: number?,
	biome: string?,
	-- altura alvo em studs; sem isso sorteia dentro da faixa do preset
	height: number?,
	scale: number?,
	material: Enum.Material?,
	color: Color3?,
	-- true (padrão) puxa a cor do Terrain do lugar em vez da paleta do bioma
	matchTerrain: boolean?,
	collisionFidelity: Enum.CollisionFidelity?,
	-- studs cobertos por um ladrilho da textura do material
	textureScale: number?,
	castShadow: boolean?,
	canCollide: boolean?,
	-- desligado por padrão: cenário não precisa disparar Touched
	canTouch: boolean?,
	-- força o modo de blocos mesmo com EditableMesh disponível
	useParts: boolean?,
	cframe: CFrame?,
	parent: Instance?,
	name: string?,
}

local function sizeOf(instance: Instance): Vector3
	if instance:IsA("BasePart") then
		return instance.Size
	elseif instance:IsA("Model") then
		return instance:GetExtentsSize()
	end
	return Vector3.one
end

local function nextSeed(rng: Random): number
	return rng:NextInteger(1, MAX_SEED)
end

local function buildLook(biome: Palette.Biome, rng: Random, options: CreateOptions): PartBuilder.Look
	local material = options.material or Palette.pickMaterial(biome, rng)
	return {
		material = material,
		color = options.color or Palette.colorFor(biome, material, rng, options.matchTerrain),
		castShadow = options.castShadow ~= false,
		canCollide = options.canCollide ~= false,
		canTouch = options.canTouch == true,
	}
end

local function createSingle(
	presetName: string,
	seed: number,
	rng: Random,
	biome: Palette.Biome,
	options: CreateOptions
): Instance
	local params = Presets.resolve(presetName, seed, rng, options :: any)
	local look = buildLook(biome, rng, options)

	local instance: Instance? = nil
	if options.useParts ~= true and MeshBuilder.isSupported() then
		local meshPart = MeshBuilder.build(Shape.generate(params), {
			collisionFidelity = options.collisionFidelity or params.definition.collisionFidelity,
			textureScale = options.textureScale,
		})
		if meshPart then
			meshPart.Anchored = true
			meshPart.Material = look.material
			meshPart.Color = look.color
			meshPart.CastShadow = look.castShadow
			meshPart.CanCollide = look.canCollide
			meshPart.CanTouch = look.canTouch
			instance = meshPart
		end
	end

	if not instance then
		instance = PartBuilder.build(params, look)
	end

	local rock = instance :: Instance
	rock:SetAttribute("RockKitBury", params.definition.bury)
	return rock
end

local function createComposite(name: string, rng: Random, options: CreateOptions): Instance
	local definition = Presets.composites[name]
	local model = Instance.new("Model")

	local target = options.height or rng:NextNumber(definition.height[1], definition.height[2])
	target *= options.scale or 1

	local members = rng:NextInteger(definition.members[1], definition.members[2])
	local radius = target * definition.spread
	local baseAngle = rng:NextNumber(0, math.pi * 2)

	local function place(child: Instance, offset: Vector3, sink: number)
		local size = sizeOf(child)
		local position = offset + Vector3.new(0, size.Y * (0.5 - sink), 0)
		child:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	end

	for index = 1, members do
		local t = (index - 1) / math.max(members - 1, 1)
		-- o primeiro membro é o mais alto; os outros descem até `falloff`
		local factor = 1 - (1 - definition.falloff) * t * rng:NextNumber(0.6, 1.25)
		local angle = baseAngle + t * math.pi * 2 * rng:NextNumber(0.55, 1.45)
		local distance = radius * rng:NextNumber(0.1, 1.0) * (if index == 1 then 0.25 else 1)

		local child = RockKit.create({
			preset = Presets.pickWeighted(definition.memberPresets, rng),
			seed = nextSeed(rng),
			biome = options.biome,
			height = math.max(target * factor, 0.1),
			material = options.material,
			color = options.color,
			matchTerrain = options.matchTerrain,
			collisionFidelity = options.collisionFidelity,
			textureScale = options.textureScale,
			castShadow = options.castShadow,
			canCollide = options.canCollide,
			canTouch = options.canTouch,
			useParts = options.useParts,
			parent = model,
		})

		place(child, Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance), rng:NextNumber(0, 0.12))
	end

	-- entulho no pé da formação, para a transição com o chão não ficar seca
	local groundCount = rng:NextInteger(definition.groundCount[1], definition.groundCount[2])
	for _ = 1, groundCount do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = radius * rng:NextNumber(0.7, 1.8) + target * 0.05

		local child = RockKit.create({
			preset = Presets.pickWeighted(definition.groundPresets, rng),
			seed = nextSeed(rng),
			biome = options.biome,
			scale = math.clamp(target / 14, 0.45, 2.2),
			material = options.material,
			color = options.color,
			matchTerrain = options.matchTerrain,
			collisionFidelity = options.collisionFidelity,
			textureScale = options.textureScale,
			castShadow = options.castShadow,
			canCollide = options.canCollide,
			canTouch = options.canTouch,
			useParts = options.useParts,
			parent = model,
		})

		place(child, Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance), rng:NextNumber(0.1, 0.35))
	end

	-- Pivô no centro da bounding box, igual ao de uma rocha única, para
	-- `PivotTo` e o posicionamento do Scatter funcionarem do mesmo jeito.
	local box = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(box.Position)
	model:SetAttribute("RockKitBury", definition.bury)

	return model
end

--[[
	Cria uma rocha. Sem `preset`, sorteia entre os presets simples.
	Devolve um MeshPart (quando EditableMesh está disponível) ou um Model.
	Em ambos os casos o pivô fica no centro da bounding box e os atributos
	RockKitPreset / RockKitSeed / RockKitBiome / RockKitSize / RockKitBury
	ficam gravados na instância.
]]
function RockKit.create(options: CreateOptions?): Instance
	local opts: CreateOptions = options or {}
	local seed = opts.seed or Random.new():NextInteger(1, MAX_SEED)
	local rng = Random.new(seed)
	local biomeName = opts.biome or Palette.defaultBiome
	local biome = Palette.get(biomeName)

	local presetName = opts.preset
	if presetName == nil then
		local names = Presets.names()
		presetName = names[rng:NextInteger(1, #names)]
	end

	local rock: Instance
	if Presets.isComposite(presetName) then
		rock = createComposite(presetName, rng, opts)
	else
		rock = createSingle(presetName, seed, rng, biome, opts)
	end

	rock.Name = opts.name or ("Rock_" .. presetName)
	rock:SetAttribute("RockKitPreset", presetName)
	rock:SetAttribute("RockKitSeed", seed)
	rock:SetAttribute("RockKitBiome", biomeName)
	rock:SetAttribute("RockKitSize", sizeOf(rock))

	if opts.cframe then
		rock:PivotTo(opts.cframe)
	end
	rock.Parent = opts.parent

	return rock
end

export type LibraryOptions = {
	presets: { string }?,
	variants: number?,
	seed: number?,
	biome: string?,
	matchTerrain: boolean?,
	useParts: boolean?,
	parent: Instance?,
	name: string?,
}

--[[
	Gera uma Folder com N variações de cada preset, uma subpasta por preset.
	É o que você quer guardar em ReplicatedStorage para arrastar na mão ou
	clonar em runtime, em vez de gerar malha nova para cada pedra do mapa.
]]
function RockKit.buildLibrary(options: LibraryOptions?): Folder
	local opts: LibraryOptions = options or {}
	local presetNames = opts.presets or Presets.names()
	local variants = math.max(opts.variants or 4, 1)
	local rng = Random.new(opts.seed or 20251008)

	local folder = Instance.new("Folder")
	folder.Name = opts.name or "RockLibrary"

	local made = 0
	for _, presetName in presetNames do
		local group = Instance.new("Folder")
		group.Name = presetName
		group.Parent = folder

		for index = 1, variants do
			RockKit.create({
				preset = presetName,
				seed = nextSeed(rng),
				biome = opts.biome,
				matchTerrain = opts.matchTerrain,
				useParts = opts.useParts,
				parent = group,
				name = string.format("%s_%02d", presetName, index),
			})

			made += 1
			if made % 8 == 0 then
				task.wait()
			end
		end
	end

	folder.Parent = opts.parent
	return folder
end

export type ScatterOptions = {
	center: Vector3,
	areaSize: Vector3,
	count: number,
	presets: { string }?,
	variants: number?,
	seed: number?,
	biome: string?,
	matchTerrain: boolean?,
	useParts: boolean?,
	minSpacing: number?,
	packing: number?,
	maxSlope: number?,
	alignToNormal: number?,
	waterLevel: number?,
	scaleJitter: { number }?,
	terrainOnly: boolean?,
	parent: Instance?,
	ignore: { Instance }?,
	-- reaproveita uma Folder já criada por buildLibrary em vez de gerar outra
	library: Folder?,
}

--[[
	Espalha rochas sobre o terreno dentro de uma área.
	`areaSize.X/Z` é a área varrida; `areaSize.Y` é a altura do raycast —
	ela precisa cobrir do ponto mais alto ao mais baixo do terreno ali.
]]
function RockKit.scatter(options: ScatterOptions): { Instance }
	local rng = Random.new(options.seed or os.time())

	local library = options.library
	local temporary = false
	if not library then
		library = RockKit.buildLibrary({
			presets = options.presets,
			variants = options.variants or 5,
			seed = nextSeed(rng),
			biome = options.biome,
			matchTerrain = options.matchTerrain,
			useParts = options.useParts,
		})
		temporary = true
	end

	-- Só os filhos diretos das subpastas: as pedras de dentro de uma formação
	-- (Peak, Cluster, Scree) também carregam os atributos do RockKit, e varrer
	-- por descendentes acabaria espalhando os pedaços delas soltos pelo mapa.
	local variants: { Scatter.Variant } = {}
	for _, group in (library :: Folder):GetChildren() do
		for _, rock in group:GetChildren() do
			if rock:GetAttribute("RockKitPreset") == nil then
				continue
			end
			table.insert(variants, {
				instance = rock,
				size = rock:GetAttribute("RockKitSize") or sizeOf(rock),
				bury = rock:GetAttribute("RockKitBury") or 0.15,
			})
		end
	end

	assert(#variants > 0, "[RockKit] scatter: a biblioteca não tem nenhuma pedra utilizável.")

	local placed = Scatter.populate({
		variants = variants,
		center = options.center,
		areaSize = options.areaSize,
		count = options.count,
		seed = nextSeed(rng),
		minSpacing = options.minSpacing,
		packing = options.packing,
		maxSlope = options.maxSlope,
		alignToNormal = options.alignToNormal,
		waterLevel = options.waterLevel,
		scaleJitter = options.scaleJitter,
		terrainOnly = options.terrainOnly,
		parent = options.parent,
		ignore = options.ignore,
	})

	if temporary then
		(library :: Folder):Destroy()
	end

	return placed
end

-- true quando as rochas saem como MeshPart facetado; false quando saem em blocos.
function RockKit.usesMeshes(): boolean
	return MeshBuilder.isSupported()
end

return RockKit
