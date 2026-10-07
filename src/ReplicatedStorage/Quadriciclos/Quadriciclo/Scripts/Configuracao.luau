--!strict
--[[
	=====================================================================
	Configuracao  (ModuleScript)
	Local: ReplicatedStorage > Quadriciclos > Quadriciclo > Scripts > Configuracao
	=====================================================================

	Os ajustes do QUADRICICLO. Aqui fica só o que é DIFERENTE do padrão.
	A lista completa (com a explicação de cada valor) está em:
	    ReplicatedStorage > Compartilhado > ConfiguracaoPadrao

	O quadriciclo usa os valores padrão. Para mudar algo SÓ nele, escreva aqui dentro.
	Exemplos (tire o "--" do começo da linha para valer):
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Padrao = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("ConfiguracaoPadrao"))

return Padrao.criar({
	-- MaxSpeed = 45,
	-- DEBUG_MODE = true,
})
