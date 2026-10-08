--[[
	Cole na Barra de Comandos do Studio.

	Espalha pedras sobre o terreno numa área quadrada centrada em CENTRO.
	Rode de novo com outro SEED até gostar do resultado — a pasta é recriada
	a cada execução, então nada acumula.

	Pré-requisito: o módulo RockKit já em ReplicatedStorage, e terreno embaixo
	da área (sem chão, o raycast não acha onde pousar e nada aparece).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local moduloRockKit = ReplicatedStorage:FindFirstChild("RockKit")
assert(moduloRockKit, "RockKit não encontrado em ReplicatedStorage. Sincronize com o Rojo ou cole build/RockKit.standalone.luau num ModuleScript chamado RockKit.")

local RockKit = require(moduloRockKit)

local CENTRO = Vector3.new(0, 0, 0)
local AREA = 400 -- studs de lado
local ALTURA_BUSCA = 800 -- precisa cobrir do ponto mais alto ao mais baixo do terreno
local QUANTIDADE = 180
local BIOMA = "Canyon"
local SEED = 1
local PRESETS = { "Pebble", "Stone", "Boulder", "Slab", "Shard", "Scree" }

pcall(function()
	ChangeHistoryService:SetWaypoint("RockKit: antes de espalhar")
end)

local pasta = workspace:FindFirstChild("RochasEspalhadas")
if pasta then
	pasta:Destroy()
end
pasta = Instance.new("Folder")
pasta.Name = "RochasEspalhadas"
pasta.Parent = workspace

local colocadas = RockKit.scatter({
	center = CENTRO,
	areaSize = Vector3.new(AREA, ALTURA_BUSCA, AREA),
	count = QUANTIDADE,
	seed = SEED,
	biome = BIOMA,
	presets = PRESETS,
	variants = 5,
	maxSlope = 40,
	alignToNormal = 0.55,
	packing = 0.75,
	terrainOnly = true,
	parent = pasta,
})

pcall(function()
	ChangeHistoryService:SetWaypoint("RockKit: pedras espalhadas")
end)

print(("[RockKit] %d pedras colocadas em workspace.RochasEspalhadas."):format(#colocadas))
