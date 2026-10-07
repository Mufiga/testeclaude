--!strict
--[[
	=====================================================================
	Configuracao  (ModuleScript)
	Local: ReplicatedStorage > Quadriciclos > CaminhaoMonstro > Scripts > Configuracao
	=====================================================================

	Os ajustes do CAMINHÃO MONSTRO. Aqui fica só o que é DIFERENTE do padrão.
	A lista completa (com a explicação de cada valor) está em:
	    ReplicatedStorage > Compartilhado > ConfiguracaoPadrao

	O caminhão é bem mais pesado que o quadriciclo: por isso o motor, a direção e as molas são mais fortes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Padrao = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("ConfiguracaoPadrao"))

return Padrao.criar({
	MaxTorque = 55378, -- (padrão 6500) a "força" de cada roda
	SteerTorque = 127795, -- (padrão 15000) a força da direção
	SpringStiffness = 7680, -- (padrão 3000) molas mais duras
	SpringDamping = 1036, -- (padrão 320)
	SpringFreeLength = 3.2, -- (padrão 2)
	SpringMinLength = 0.72, -- (padrão 0.45)
	SpringMaxLength = 4.8, -- (padrão 3)
})
