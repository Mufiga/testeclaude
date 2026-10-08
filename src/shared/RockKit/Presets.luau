--[[
	Presets — os formatos e tamanhos de rocha.

	Campos de cada preset:
	  height          faixa de altura em studs (o tamanho sai daqui)
	  aspectXZ        largura / altura
	  flatten         profundidade / largura (achata a pedra num eixo)
	  subdivisions    0..2 — quantidade de facetas (custo de triângulos)
	  amplitude       força do ruído radial (0.2 anguloso, 0.35 bem irregular)
	  frequency       escala do ruído: alto = detalhe miúdo
	  cleaves         quantos planos de corte aplicar
	  cleaveDepth     distância dos planos ao centro (menor = corte mais fundo)
	  cleaveVertical  peso do eixo Y na normal dos planos.
	                  alto  -> faces horizontais (lajes, degraus)
	                  baixo -> paredes verticais (agulhas, paredões)
	  cleaveFamilies  quantas direções-base de junta. poucas = faces paralelas
	  cleaveJitter    o quanto cada plano desvia da sua família (0 = paralelo)
	  taperTop        largura no topo em relação à base (0.16 = agulha)
	  taperCurve      >1 concentra o afinamento perto do topo
	  tilt            inclinação em graus
	  flatBase/Depth  achata a base; Depth é a fração da altura que some
	  bury            fração da altura enterrada ao posicionar no terreno
	  shards          faixa de peças no modo PartBuilder
]]

local Presets = {}

export type Preset = {
	displayName: string,
	height: { number },
	aspectXZ: { number },
	flatten: { number },
	subdivisions: number,
	amplitude: number,
	frequency: number,
	octaves: number,
	cleaves: { number },
	cleaveDepth: { number },
	cleaveVertical: number,
	cleaveFamilies: number,
	cleaveJitter: number,
	taperTop: number,
	taperCurve: number,
	tilt: { number },
	flatBase: boolean,
	flatBaseDepth: number,
	bury: number,
	collisionFidelity: Enum.CollisionFidelity,
	shards: { number },
}

local presets: { [string]: Preset } = {
	-- Seixo: cabe na mão, bom para espalhar aos montes em trilhas e margens.
	Pebble = {
		displayName = "Seixo",
		height = { 0.35, 1.2 },
		aspectXZ = { 1.1, 2.0 },
		flatten = { 0.7, 1.2 },
		subdivisions = 1,
		amplitude = 0.32,
		frequency = 1.9,
		octaves = 3,
		cleaves = { 5, 9 },
		cleaveDepth = { 0.45, 0.80 },
		cleaveVertical = 0.9,
		cleaveFamilies = 3,
		cleaveJitter = 0.50,
		taperTop = 0.90,
		taperCurve = 1.0,
		tilt = { 0, 35 },
		flatBase = true,
		flatBaseDepth = 0.10,
		bury = 0.30,
		collisionFidelity = Enum.CollisionFidelity.Box,
		shards = { 2, 3 },
	},

	-- Pedra solta: altura de joelho, o tamanho mais usado em cenário.
	Stone = {
		displayName = "Pedra",
		height = { 1.3, 3.6 },
		aspectXZ = { 0.9, 1.6 },
		flatten = { 0.75, 1.15 },
		subdivisions = 1,
		amplitude = 0.30,
		frequency = 1.7,
		octaves = 3,
		cleaves = { 7, 11 },
		cleaveDepth = { 0.45, 0.78 },
		cleaveVertical = 0.85,
		cleaveFamilies = 3,
		cleaveJitter = 0.42,
		taperTop = 0.80,
		taperCurve = 1.1,
		tilt = { 0, 22 },
		flatBase = true,
		flatBaseDepth = 0.10,
		bury = 0.22,
		collisionFidelity = Enum.CollisionFidelity.Box,
		shards = { 2, 4 },
	},

	-- Matacão: bloco redondo grande, dá para subir em cima.
	Boulder = {
		displayName = "Matacão",
		height = { 4, 11 },
		aspectXZ = { 1.0, 1.7 },
		flatten = { 0.8, 1.2 },
		subdivisions = 2,
		amplitude = 0.26,
		frequency = 1.5,
		octaves = 4,
		cleaves = { 10, 16 },
		cleaveDepth = { 0.50, 0.82 },
		cleaveVertical = 0.80,
		cleaveFamilies = 4,
		cleaveJitter = 0.38,
		taperTop = 0.78,
		taperCurve = 1.2,
		tilt = { 0, 14 },
		flatBase = true,
		flatBaseDepth = 0.12,
		bury = 0.18,
		collisionFidelity = Enum.CollisionFidelity.Hull,
		shards = { 3, 5 },
	},

	-- Laje: placa chata e larga, boa para degrau e plataforma.
	Slab = {
		displayName = "Laje",
		height = { 1.2, 4 },
		aspectXZ = { 2.0, 3.6 },
		flatten = { 0.6, 1.0 },
		subdivisions = 1,
		amplitude = 0.20,
		frequency = 1.4,
		octaves = 3,
		cleaves = { 6, 10 },
		cleaveDepth = { 0.45, 0.78 },
		cleaveVertical = 2.20,
		cleaveFamilies = 3,
		cleaveJitter = 0.30,
		taperTop = 0.90,
		taperCurve = 1.0,
		tilt = { 0, 12 },
		flatBase = true,
		flatBaseDepth = 0.16,
		bury = 0.30,
		collisionFidelity = Enum.CollisionFidelity.Box,
		shards = { 2, 4 },
	},

	-- Lasca: fatia fina fincada no chão em ângulo.
	Shard = {
		displayName = "Lasca",
		height = { 3.5, 13 },
		aspectXZ = { 0.28, 0.55 },
		flatten = { 0.4, 0.8 },
		subdivisions = 1,
		amplitude = 0.18,
		frequency = 1.6,
		octaves = 3,
		cleaves = { 7, 12 },
		cleaveDepth = { 0.42, 0.78 },
		cleaveVertical = 0.30,
		cleaveFamilies = 3,
		cleaveJitter = 0.26,
		taperTop = 0.35,
		taperCurve = 0.9,
		tilt = { 8, 34 },
		flatBase = true,
		flatBaseDepth = 0.06,
		bury = 0.20,
		collisionFidelity = Enum.CollisionFidelity.Box,
		shards = { 2, 4 },
	},

	-- Agulha: a torre pontuda da referência.
	Spire = {
		displayName = "Agulha",
		height = { 10, 32 },
		aspectXZ = { 0.28, 0.55 },
		flatten = { 0.45, 1.00 },
		subdivisions = 2,
		amplitude = 0.22,
		frequency = 1.5,
		octaves = 4,
		cleaves = { 12, 18 },
		cleaveDepth = { 0.40, 0.80 },
		cleaveVertical = 0.35,
		cleaveFamilies = 4,
		cleaveJitter = 0.28,
		taperTop = 0.22,
		taperCurve = 1.00,
		tilt = { 0, 9 },
		flatBase = true,
		flatBaseDepth = 0.08,
		bury = 0.12,
		collisionFidelity = Enum.CollisionFidelity.Hull,
		shards = { 3, 6 },
	},

	-- Paredão: massa de rocha para fechar o fundo do cenário.
	Cliff = {
		displayName = "Paredão",
		height = { 12, 34 },
		aspectXZ = { 0.70, 1.40 },
		flatten = { 0.35, 0.70 },
		subdivisions = 1,
		amplitude = 0.24,
		frequency = 1.3,
		octaves = 4,
		cleaves = { 8, 13 },
		cleaveDepth = { 0.42, 0.75 },
		cleaveVertical = 0.45,
		cleaveFamilies = 4,
		cleaveJitter = 0.26,
		taperTop = 0.55,
		taperCurve = 1.15,
		tilt = { 0, 8 },
		flatBase = true,
		flatBaseDepth = 0.14,
		bury = 0.15,
		collisionFidelity = Enum.CollisionFidelity.Hull,
		shards = { 4, 7 },
	},
}

export type Composite = {
	displayName: string,
	height: { number },
	members: { number },
	memberPresets: { [string]: number },
	-- raio de espalhamento, em frações da altura alvo
	spread: number,
	-- altura relativa do membro mais baixo em relação ao mais alto
	falloff: number,
	groundCount: { number },
	groundPresets: { [string]: number },
	bury: number,
}

-- Formações montadas a partir dos presets simples.
local composites: { [string]: Composite } = {
	-- Pico: várias agulhas de alturas diferentes saindo da mesma base,
	-- com pedras menores no pé. É o conjunto da imagem de referência.
	Peak = {
		displayName = "Pico",
		height = { 16, 40 },
		members = { 3, 6 },
		memberPresets = { Spire = 5, Shard = 2, Cliff = 1, Boulder = 2 },
		spread = 0.30,
		falloff = 0.35,
		groundCount = { 2, 5 },
		groundPresets = { Boulder = 2, Stone = 3, Pebble = 2 },
		bury = 0.10,
	},

	-- Aglomerado: grupo de pedras médias encostadas, bom para quebrar
	-- um campo aberto sem virar obstáculo.
	Cluster = {
		displayName = "Aglomerado",
		height = { 3, 9 },
		members = { 3, 6 },
		memberPresets = { Boulder = 3, Stone = 4, Slab = 2, Shard = 1 },
		spread = 0.70,
		falloff = 0.45,
		groundCount = { 2, 4 },
		groundPresets = { Pebble = 4, Stone = 2 },
		bury = 0.22,
	},

	-- Pedregulho: mancha rasa de pedras pequenas, tipo encosta desmoronada.
	Scree = {
		displayName = "Pedregulho",
		height = { 0.8, 2.2 },
		members = { 5, 10 },
		memberPresets = { Pebble = 6, Stone = 2, Slab = 1 },
		spread = 2.4,
		falloff = 0.40,
		groundCount = { 3, 7 },
		groundPresets = { Pebble = 1 },
		bury = 0.35,
	},
}

Presets.list = presets
Presets.composites = composites

function Presets.isComposite(name: string): boolean
	return composites[name] ~= nil
end

function Presets.names(): { string }
	local result = {}
	for name in presets do
		table.insert(result, name)
	end
	table.sort(result)
	return result
end

function Presets.compositeNames(): { string }
	local result = {}
	for name in composites do
		table.insert(result, name)
	end
	table.sort(result)
	return result
end

function Presets.allNames(): { string }
	local result = Presets.names()
	for _, name in Presets.compositeNames() do
		table.insert(result, name)
	end
	return result
end

--[[
	Sorteio ponderado numa tabela { Nome = peso }.

	As chaves são ordenadas antes do sorteio de propósito: a ordem de iteração
	de um dicionário em Lua não é garantida, e sem isso o mesmo seed poderia
	devolver materiais diferentes entre execuções.
]]
function Presets.pickWeighted(weights: { [string]: number }, rng: Random): string
	local names = {}
	local total = 0
	for name, weight in weights do
		table.insert(names, name)
		total += weight
	end
	table.sort(names)

	local roll = rng:NextNumber(0, math.max(total, 1e-6))
	for _, name in names do
		roll -= weights[name]
		if roll <= 0 then
			return name
		end
	end
	return names[#names] or "Stone"
end

export type ResolvedParams = {
	preset: string,
	definition: Preset,
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
	shards: { number },
}

--[[
	Transforma um preset (faixas) em parâmetros concretos (números).
	`overrides.height` força a altura em studs; `overrides.scale` multiplica
	a altura sorteada.
]]
function Presets.resolve(name: string, seed: number, rng: Random, overrides: { [string]: any }?): ResolvedParams
	local definition = presets[name]
	assert(definition, ("[RockKit] preset desconhecido: %s"):format(tostring(name)))
	local opts = overrides or {}

	local height = opts.height or rng:NextNumber(definition.height[1], definition.height[2])
	height *= opts.scale or 1
	height = math.max(height, 0.05)

	local width = height * rng:NextNumber(definition.aspectXZ[1], definition.aspectXZ[2])
	local depth = width * rng:NextNumber(definition.flatten[1], definition.flatten[2])

	return {
		preset = name,
		definition = definition,
		seed = seed,
		size = Vector3.new(width, height, depth),
		subdivisions = definition.subdivisions,
		amplitude = definition.amplitude,
		frequency = definition.frequency,
		octaves = definition.octaves,
		cleaves = rng:NextInteger(definition.cleaves[1], definition.cleaves[2]),
		cleaveDepth = definition.cleaveDepth,
		cleaveVertical = definition.cleaveVertical,
		cleaveFamilies = definition.cleaveFamilies,
		cleaveJitter = definition.cleaveJitter,
		taperTop = definition.taperTop,
		taperCurve = definition.taperCurve,
		tilt = math.rad(rng:NextNumber(definition.tilt[1], definition.tilt[2])),
		flatBase = definition.flatBase,
		flatBaseDepth = definition.flatBaseDepth,
		shards = definition.shards,
	}
end

return Presets
