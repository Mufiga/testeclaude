--!nocheck
--!nolint
--[[
	RockKit — versao de arquivo unico, gerada por tools/bundle.py.
	NAO EDITE AQUI: mexa em src/shared/RockKit/ e rode o bundler de novo.

	Como usar sem Rojo:
	  1. Em ReplicatedStorage, crie um ModuleScript chamado "RockKit".
	  2. Cole todo o conteudo deste arquivo dentro dele.
	  3. require(game.ReplicatedStorage.RockKit)
]]

local __modules: { [string]: () -> any } = {}
local __loaded: { [string]: any } = {}

local function __require(name: string): any
	local cached = __loaded[name]
	if cached ~= nil then
		return cached
	end
	local factory = __modules[name]
	if not factory then
		error("[RockKit] modulo nao encontrado no bundle: " .. name, 2)
	end
	local result = factory()
	__loaded[name] = result
	return result
end

__modules["MeshBuilder"] = function()
	--[[
		MeshBuilder — transforma a geometria num MeshPart de verdade, via EditableMesh.

		Cada triângulo recebe três vértices próprios e uma única normal compartilhada
		entre eles: é isso que produz a aresta dura do visual low poly facetado
		(vértices compartilhados dariam sombreamento suave, e a pedra viraria uma
		batata lisa).

		A API de EditableMesh não existe em todas as versões do engine, então todo o
		caminho é protegido: se falhar, o RockKit cai no PartBuilder sozinho.
	]]

	local AssetService = game:GetService("AssetService")

	local Shape = __require("Shape")

	local MeshBuilder = {}

	local supported: boolean? = nil

	type MeshOptions = {
		collisionFidelity: Enum.CollisionFidelity?,
		-- quantos studs cobre um "ladrilho" da textura do material
		textureScale: number?,
	}

	-- Projeção planar pelo eixo dominante da normal (triplanar simplificado):
	-- mantém a textura do material no mesmo tamanho real em todas as faces.
	local function planarUV(point: Vector3, normal: Vector3): Vector2
		local ax, ay, az = math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z)
		if ay >= ax and ay >= az then
			return Vector2.new(point.X, point.Z)
		elseif ax >= az then
			return Vector2.new(point.Z, point.Y)
		end
		return Vector2.new(point.X, point.Y)
	end

	function MeshBuilder.isSupported(): boolean
		if supported == nil then
			supported = (pcall(function()
				local probe = AssetService:CreateEditableMesh()
				local _ = (Content :: any).fromObject(probe)
				pcall(function()
					probe:Destroy()
				end)
			end))
		end
		return supported :: boolean
	end

	function MeshBuilder.build(geometry: Shape.Geometry, options: MeshOptions): MeshPart?
		local fidelity = options.collisionFidelity or Enum.CollisionFidelity.Box
		local uvScale = 1 / math.max(options.textureScale or 8, 0.01)

		local ok, result = pcall(function()
			local mesh = AssetService:CreateEditableMesh()

			for _, triangle in geometry.triangles do
				local normal = triangle.normal
				local normalId = mesh:AddNormal(normal)

				local a = mesh:AddVertex(triangle.a)
				local b = mesh:AddVertex(triangle.b)
				local c = mesh:AddVertex(triangle.c)
				local face = mesh:AddTriangle(a, b, c)

				mesh:SetFaceNormals(face, { normalId, normalId, normalId })
				mesh:SetFaceUVs(face, {
					mesh:AddUV(planarUV(triangle.a, normal) * uvScale),
					mesh:AddUV(planarUV(triangle.b, normal) * uvScale),
					mesh:AddUV(planarUV(triangle.c, normal) * uvScale),
				})
			end

			local content = (Content :: any).fromObject(mesh)

			-- A tabela de opções é recente; se o engine não aceitar, tenta sem ela.
			local built: MeshPart
			local withOptions, part = pcall(function()
				return AssetService:CreateMeshPartAsync(content, { CollisionFidelity = fidelity })
			end)
			if withOptions then
				built = part
			else
				built = AssetService:CreateMeshPartAsync(content)
				built.CollisionFidelity = fidelity
			end

			pcall(function()
				mesh:Destroy()
			end)
			return built
		end)

		if not ok then
			supported = false
			return nil
		end
		return result
	end

	return MeshBuilder
end

__modules["Noise"] = function()
	--[[
		Noise — ruído determinístico usado para deformar as rochas.

		`math.noise` (Perlin) da Roblox devolve algo em torno de [-0.5, 0.5] e vale
		exatamente 0 nos pontos inteiros da grade. Por isso toda amostra é deslocada
		por um offset fracionário derivado do seed: sem isso, rochas geradas em
		posições "redondas" sairiam lisas demais.
	]]

	local Noise = {}

	-- Soma de oitavas (fractal brownian motion). Devolve ~[-0.5, 0.5].
	function Noise.fbm(point: Vector3, octaves: number, lacunarity: number, gain: number): number
		local amplitude = 1
		local frequency = 1
		local total = 0
		local normalization = 0

		for _ = 1, octaves do
			total += amplitude * math.noise(point.X * frequency, point.Y * frequency, point.Z * frequency)
			normalization += amplitude
			amplitude *= gain
			frequency *= lacunarity
		end

		if normalization <= 0 then
			return 0
		end
		return total / normalization
	end

	-- Offset fracionário estável para um seed.
	function Noise.offsetFromSeed(seed: number): Vector3
		local rng = Random.new(seed)
		return Vector3.new(rng:NextNumber(-512, 512), rng:NextNumber(-512, 512), rng:NextNumber(-512, 512))
	end

	return Noise
end

__modules["Palette"] = function()
	--[[
		Palette — casa a cor das rochas com o Terrain do lugar.

		A ideia central: uma Part com `Material = Enum.Material.Rock` usa a mesma
		textura PBR que o Terrain usa no material Rock. Se além disso a cor da Part
		for exatamente `Terrain:GetMaterialColor(Enum.Material.Rock)`, a pedra
		encosta no terreno sem emenda visível.

		Por isso `matchTerrain` é o padrão: lemos a cor que o lugar já usa em vez de
		chutar uma. As paletas abaixo só entram como reserva (e para quem quiser
		usar `Palette.syncTerrain` e puxar o terreno para o tom do bioma).
	]]

	local Terrain = workspace.Terrain

	local Palette = {}

	type Biome = {
		displayName: string,
		-- peso relativo de cada material nas rochas do bioma
		materials: { [string]: number },
		-- cor de reserva por material, usada quando matchTerrain está desligado
		colors: { [string]: Color3 },
		-- variação de brilho entre pedras (0.06 = sutil, 0.2 = bem contrastado)
		variation: number,
	}

	local biomes: { [string]: Biome } = {
		-- Canyon avermelhado: o visual da referência (granito rosado + arenito).
		Canyon = {
			displayName = "Canyon / deserto",
			materials = { Rock = 6, Sandstone = 4, Slate = 2, Limestone = 1 },
			colors = {
				Rock = Color3.fromRGB(150, 112, 99),
				Sandstone = Color3.fromRGB(178, 137, 110),
				Slate = Color3.fromRGB(123, 95, 88),
				Limestone = Color3.fromRGB(186, 158, 128),
				Ground = Color3.fromRGB(139, 105, 85),
				Grass = Color3.fromRGB(124, 142, 72),
				LeafyGrass = Color3.fromRGB(116, 135, 66),
			},
			variation = 0.09,
		},

		Mountain = {
			displayName = "Montanha / rocha cinza",
			materials = { Rock = 6, Slate = 4, Limestone = 2, Basalt = 1 },
			colors = {
				Rock = Color3.fromRGB(122, 124, 128),
				Slate = Color3.fromRGB(96, 100, 106),
				Limestone = Color3.fromRGB(158, 156, 146),
				Basalt = Color3.fromRGB(78, 78, 82),
				Ground = Color3.fromRGB(104, 98, 86),
				Grass = Color3.fromRGB(104, 124, 76),
			},
			variation = 0.10,
		},

		Forest = {
			displayName = "Floresta",
			materials = { Rock = 6, Slate = 3, Ground = 1 },
			colors = {
				Rock = Color3.fromRGB(112, 116, 106),
				Slate = Color3.fromRGB(92, 96, 92),
				Ground = Color3.fromRGB(88, 76, 60),
				LeafyGrass = Color3.fromRGB(84, 110, 58),
				Grass = Color3.fromRGB(96, 122, 62),
			},
			variation = 0.08,
		},

		Snow = {
			displayName = "Neve / geleira",
			materials = { Rock = 5, Slate = 3, Glacier = 2, Snow = 1 },
			colors = {
				Rock = Color3.fromRGB(150, 158, 168),
				Slate = Color3.fromRGB(118, 126, 138),
				Glacier = Color3.fromRGB(200, 215, 225),
				Snow = Color3.fromRGB(235, 240, 245),
				Ground = Color3.fromRGB(118, 118, 120),
			},
			variation = 0.07,
		},

		Volcanic = {
			displayName = "Vulcânico",
			materials = { Basalt = 6, Rock = 3, Slate = 2 },
			colors = {
				Basalt = Color3.fromRGB(58, 56, 58),
				Rock = Color3.fromRGB(74, 70, 70),
				Slate = Color3.fromRGB(52, 50, 52),
				Ground = Color3.fromRGB(62, 54, 50),
			},
			variation = 0.12,
		},
	}

	Palette.biomes = biomes
	Palette.defaultBiome = "Canyon"

	function Palette.get(name: string?): Biome
		local biome = Palette.biomes[name or Palette.defaultBiome]
		if not biome then
			warn(("[RockKit] bioma desconhecido '%s', usando '%s'."):format(tostring(name), Palette.defaultBiome))
			biome = Palette.biomes[Palette.defaultBiome]
		end
		return biome
	end

	function Palette.listBiomes(): { string }
		local names = {}
		for name in Palette.biomes do
			table.insert(names, name)
		end
		table.sort(names)
		return names
	end

	-- Sorteio ponderado entre os materiais do bioma.
	-- Chaves ordenadas: ver a nota em Presets.pickWeighted.
	function Palette.pickMaterial(biome: Biome, rng: Random): Enum.Material
		local names = {}
		local total = 0
		for name, weight in biome.materials do
			table.insert(names, name)
			total += weight
		end
		table.sort(names)

		local roll = rng:NextNumber(0, math.max(total, 1e-6))
		for _, name in names do
			roll -= biome.materials[name]
			if roll <= 0 then
				local material = (Enum.Material :: any)[name]
				if material then
					return material
				end
				break
			end
		end
		return Enum.Material.Rock
	end

	-- Cor do Terrain para esse material, se o material existir no Terrain.
	function Palette.terrainColor(material: Enum.Material): Color3?
		local ok, color = pcall(function()
			return Terrain:GetMaterialColor(material)
		end)
		if ok and typeof(color) == "Color3" then
			return color
		end
		return nil
	end

	--[[
		Cor final de uma rocha.

		`matchTerrain = true` (padrão) parte da cor que o Terrain do lugar já usa
		nesse material; caso contrário usa a paleta do bioma. Em cima disso entra
		uma variação pequena de saturação/brilho para as pedras não ficarem todas
		iguais — mas pequena o bastante para continuarem lendo como a mesma rocha.
	]]
	function Palette.colorFor(biome: Biome, material: Enum.Material, rng: Random, matchTerrain: boolean?): Color3
		local base: Color3? = nil
		if matchTerrain ~= false then
			base = Palette.terrainColor(material)
		end
		base = base or biome.colors[material.Name] or Color3.fromRGB(128, 128, 128)

		local shift = rng:NextNumber(-biome.variation, biome.variation)
		local h, s, v = base:ToHSV()
		return Color3.fromHSV(h, math.clamp(s + shift * 0.3, 0, 1), math.clamp(v + shift, 0.02, 1))
	end

	--[[
		Opcional e destrutivo: puxa as cores do Terrain para a paleta do bioma.
		Só chame se quiser que o terreno acompanhe as rochas (e não o contrário).
		Devolve a tabela de cores antigas para você conseguir desfazer.
	]]
	function Palette.syncTerrain(name: string?): { [string]: Color3 }
		local biome = Palette.get(name)
		local previous: { [string]: Color3 } = {}

		for materialName, color in biome.colors do
			local material = (Enum.Material :: any)[materialName]
			if not material then
				continue
			end
			local old = Palette.terrainColor(material)
			if old then
				previous[materialName] = old
				pcall(function()
					Terrain:SetMaterialColor(material, color)
				end)
			end
		end

		return previous
	end

	return Palette
end

__modules["PartBuilder"] = function()
	--[[
		PartBuilder — reserva para quando EditableMesh não está disponível.

		Monta a pedra empilhando blocos girados em ângulos quebrados (mais cunhas no
		topo nos presets pontudos). Não fica tão limpo quanto a malha facetada, mas
		usa só Part/WedgePart: roda em qualquer versão do engine e em qualquer lugar.
	]]

	local PartBuilder = {}

	type Look = {
		material: Enum.Material,
		color: Color3,
		castShadow: boolean,
		canCollide: boolean,
		canTouch: boolean,
	}

	type BuildParams = {
		seed: number,
		size: Vector3,
		taperTop: number,
		taperCurve: number,
		tilt: number,
		shards: { number },
	}

	local function newPart(className: string, size: Vector3, cframe: CFrame, look: Look, parent: Instance): BasePart
		local part = Instance.new(className) :: BasePart
		part.Size = size
		part.CFrame = cframe
		part.Anchored = true
		part.Material = look.material
		part.Color = look.color
		part.CastShadow = look.castShadow
		part.CanCollide = look.canCollide
		part.CanTouch = look.canTouch
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = parent
		return part
	end

	function PartBuilder.build(params: BuildParams, look: Look): Model
		local rng = Random.new(params.seed + 7919)
		local model = Instance.new("Model")
		local size = params.size

		local count = rng:NextInteger(params.shards[1], params.shards[2])
		local layer = size.Y / count

		for index = 1, count do
			local t = if count > 1 then (index - 1) / (count - 1) else 0
			local shrink = 1 + (params.taperTop - 1) * t ^ params.taperCurve
			local width = size.X * shrink * rng:NextNumber(0.55, 1.0)
			local depth = size.Z * shrink * rng:NextNumber(0.55, 1.0)
			local height = layer * rng:NextNumber(0.9, 1.6)
			local jitter = size.X * shrink * 0.18

			local cframe = CFrame.new(
				rng:NextNumber(-jitter, jitter),
				-size.Y * 0.5 + layer * (index - 0.5),
				rng:NextNumber(-jitter, jitter)
			) * CFrame.Angles(
				math.rad(rng:NextNumber(-9, 9)),
				rng:NextNumber(0, math.pi * 2),
				math.rad(rng:NextNumber(-9, 9))
			)

			newPart("Part", Vector3.new(width, height, depth), cframe, look, model)
		end

		-- Presets afilados (agulha, lasca) ganham cunhas no topo para fechar a ponta.
		if params.taperTop < 0.6 then
			for _ = 1, rng:NextInteger(1, 2) do
				local width = math.max(size.X * params.taperTop * rng:NextNumber(0.8, 1.6), 0.1)
				local depth = math.max(size.Z * params.taperTop * rng:NextNumber(0.8, 1.6), 0.1)
				local height = size.Y * rng:NextNumber(0.12, 0.26)

				local cframe = CFrame.new(
					rng:NextNumber(-width, width) * 0.4,
					size.Y * 0.5 - height * 0.35,
					rng:NextNumber(-depth, depth) * 0.4
				) * CFrame.Angles(
					math.rad(rng:NextNumber(-12, 12)),
					rng:NextNumber(0, math.pi * 2),
					math.rad(rng:NextNumber(-12, 12))
				)

				newPart("WedgePart", Vector3.new(width, height, depth), cframe, look, model)
			end
		end

		if params.tilt > 1e-4 then
			local axis = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
			if axis.Magnitude > 1e-3 then
				local rotation = CFrame.fromAxisAngle(axis.Unit, params.tilt)
				for _, child in model:GetChildren() do
					if child:IsA("BasePart") then
						child.CFrame = rotation * child.CFrame
					end
				end
			end
		end

		-- Recentra a bounding box na origem para o modelo se comportar como o
		-- MeshPart equivalente (pivô no centro, não na primeira peça criada).
		local boxCFrame, boxSize = model:GetBoundingBox()
		local offset = boxCFrame.Position
		if offset.Magnitude > 1e-5 then
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") then
					child.CFrame = child.CFrame - offset
				end
			end
		end

		-- Sem PrimaryPart de propósito: assim `PivotTo` usa o WorldPivot que
		-- acabamos de centralizar, em vez do centro de uma peça qualquer.
		model.WorldPivot = CFrame.identity
		model:SetAttribute("RockKitSize", boxSize)

		return model
	end

	return PartBuilder
end

__modules["Presets"] = function()
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

	type Preset = {
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

	type Composite = {
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

	type ResolvedParams = {
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
end

__modules["Scatter"] = function()
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

	type Variant = {
		instance: Instance,
		size: Vector3,
		bury: number,
	}

	type ScatterOptions = {
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
end

__modules["Shape"] = function()
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

	local Noise = __require("Noise")

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

	type Triangle = {
		a: Vector3,
		b: Vector3,
		c: Vector3,
		normal: Vector3,
	}

	type Geometry = {
		triangles: { Triangle },
		size: Vector3,
	}

	type ShapeParams = {
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
end

__modules["RockKit"] = function()
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

	local Palette = __require("Palette")
	local PartBuilder = __require("PartBuilder")
	local Presets = __require("Presets")
	local Scatter = __require("Scatter")
	local Shape = __require("Shape")
	local MeshBuilder = __require("MeshBuilder")

	local RockKit = {}

	RockKit.Palette = Palette
	RockKit.Presets = Presets
	RockKit.Shape = Shape

	local MAX_SEED = 2 ^ 31 - 2

	type CreateOptions = {
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

	type LibraryOptions = {
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

	type ScatterOptions = {
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
end

return __require("RockKit")
