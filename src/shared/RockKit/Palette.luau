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

export type Biome = {
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
