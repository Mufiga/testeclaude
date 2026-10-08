--[[
	Cole na Barra de Comandos do Studio (View > Command Bar).

	Gera ReplicatedStorage.RockLibrary com N variações de cada preset e espalha
	uma cópia de cada numa grade no Workspace, para você olhar e arrastar a que
	quiser. Apague a pasta "RockLibrary_Preview" quando terminar.

	Pré-requisito: o módulo RockKit já em ReplicatedStorage.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local moduloRockKit = ReplicatedStorage:FindFirstChild("RockKit")
assert(moduloRockKit, "RockKit não encontrado em ReplicatedStorage. Sincronize com o Rojo ou cole build/RockKit.standalone.luau num ModuleScript chamado RockKit.")

local RockKit = require(moduloRockKit)

local VARIACOES = 6
local BIOMA = "Canyon"
local ESPACAMENTO = 14

pcall(function()
	ChangeHistoryService:SetWaypoint("RockKit: antes de gerar")
end)

local antiga = ReplicatedStorage:FindFirstChild("RockLibrary")
if antiga then
	antiga:Destroy()
end
local previaAntiga = workspace:FindFirstChild("RockLibrary_Preview")
if previaAntiga then
	previaAntiga:Destroy()
end

local biblioteca = RockKit.buildLibrary({
	variants = VARIACOES,
	biome = BIOMA,
	presets = RockKit.Presets.allNames(),
	parent = ReplicatedStorage,
})

local previa = Instance.new("Folder")
previa.Name = "RockLibrary_Preview"
previa.Parent = workspace

-- Uma linha por preset. O avanço usa a largura real de cada pedra, senão os
-- paredões e as agulhas grandes atravessam os vizinhos.
local z = 0
for _, grupo in biblioteca:GetChildren() do
	local x = 0
	local profundidadeMaxima = 0

	for _, rocha in grupo:GetChildren() do
		local copia = rocha:Clone()
		local tamanho = rocha:GetAttribute("RockKitSize") :: Vector3
		local enterrado = rocha:GetAttribute("RockKitBury") :: number

		x += tamanho.X * 0.5 + ESPACAMENTO
		copia:PivotTo(CFrame.new(x, tamanho.Y * (0.5 - enterrado), z))
		copia.Parent = previa
		x += tamanho.X * 0.5

		profundidadeMaxima = math.max(profundidadeMaxima, tamanho.Z)
	end

	z += profundidadeMaxima + ESPACAMENTO
end

pcall(function()
	ChangeHistoryService:SetWaypoint("RockKit: biblioteca gerada")
end)

print(("[RockKit] %d presets x %d variações em ReplicatedStorage.RockLibrary (prévia no Workspace).")
	:format(#biblioteca:GetChildren(), VARIACOES))
