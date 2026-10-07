--!strict
--[[
	=====================================================================
	Ladeira  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Ladeira
	=====================================================================

	Descendo, a velocidade máxima vai subindo: quanto mais inclinada e quanto
	mais tempo descendo, maior (Config.GanhoLadeira). Fora da descida, o extra
	vai caindo (Config.PerdaLadeira). Nunca passa de Config.VelocidadeMaximaTotal
	(nem com nitro).
]]

local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
type Quadriciclo = Veiculo.Quadriciclo

local Ladeira = {}

-- Chamado a cada frame pelo "atualizar". Devolve (velocidade máxima de agora, inclinação da descida).
function Ladeira.velocidadeMaximaAgora(quad: Quadriciclo, referencia: CFrame, velocidadeFrente: number, dt: number): (number, number)
	local Config = quad.Config
	local descida = -referencia.LookVector.Y -- 0 = plano, 0.5 = 30° de descida (é o seno do ângulo)
	local limiteExtra = math.max(Config.VelocidadeMaximaTotal - Config.MaxSpeed, 0)
	if descida > 0.08 and velocidadeFrente > Veiculo.PARADO then -- descendo de frente (mais de ~5°)
		quad.extraLadeira = math.min(quad.extraLadeira + descida * Config.GanhoLadeira * dt, limiteExtra)
	else
		quad.extraLadeira = math.max(quad.extraLadeira - Config.PerdaLadeira * dt, 0)
	end
	return math.min(Config.MaxSpeed + quad.extraLadeira, Config.VelocidadeMaximaTotal), descida
end

return Ladeira

