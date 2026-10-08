--[[
	Cole na Barra de Comandos do Studio.

	ATENÇÃO: isto ALTERA as cores dos materiais do Terrain do seu lugar.
	Use quando quiser puxar o terreno para o tom do bioma — normalmente é o
	contrário que você quer (as rochas já leem a cor do terreno sozinhas, com
	`matchTerrain`, que vem ligado por padrão).

	O script imprime as cores antigas, para você conseguir voltar atrás.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local moduloRockKit = ReplicatedStorage:FindFirstChild("RockKit")
assert(moduloRockKit, "RockKit não encontrado em ReplicatedStorage. Sincronize com o Rojo ou cole build/RockKit.standalone.luau num ModuleScript chamado RockKit.")

local RockKit = require(moduloRockKit)

local BIOMA = "Canyon"

local anteriores = RockKit.Palette.syncTerrain(BIOMA)

print(("[RockKit] Terrain ajustado para o bioma '%s'. Cores anteriores:"):format(BIOMA))
for material, cor in anteriores do
	print(("  %s = Color3.fromRGB(%d, %d, %d)"):format(
		material,
		math.round(cor.R * 255),
		math.round(cor.G * 255),
		math.round(cor.B * 255)
	))
end
