--!strict
--[[
	=====================================================================
	Buzina  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Buzina
	=====================================================================

	Para TODO MUNDO (criarEfeitos): o som da buzina (Config.HornSoundId),
	que repete enquanto o motorista segura.
	Para QUEM DIRIGE (ligar/desligar): tecla H / seta para cima do controle /
	botão BUZINA no celular.
]]


local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
local BotoesDoCelular = require(script.Parent:WaitForChild("BotoesDoCelular")) -- (NOVO) os botões da tela no celular
type Quadriciclo = Veiculo.Quadriciclo

local Buzina = {}

local ACAO_BUZINA = "QuadricicloBuzina"

-- Chamado uma vez para cada quadriciclo que aparece no seu jogo.
function Buzina.criarEfeitos(quad: Quadriciclo)
	local somBuzina = Veiculo.criarSom(quad, "SomBuzina", quad.Config.HornSoundId, true)
	quad.tocarBuzina = function(ligada: boolean)
		if ligada and not somBuzina.IsPlaying then
			somBuzina:Play()
		elseif not ligada then
			somBuzina:Stop()
		end
	end

	-- Os OUTROS jogadores seguem o que o Servidor marcou no modelo.
	local function aoMudarAtributo()
		if not quad.dirigindo then
			quad.tocarBuzina(quad.modelo:GetAttribute("Buzina") == true)
		end
	end
	Veiculo.guardarConexao(quad, quad.modelo:GetAttributeChangedSignal("Buzina"):Connect(aoMudarAtributo))
	aoMudarAtributo() -- quem entra no meio de uma buzinada já ouve
end

-- Sentou: liga a tecla da buzina.
function Buzina.ligar(quad: Quadriciclo)
	BotoesDoCelular.ligar(ACAO_BUZINA, "BUZINA", function(_nomeAcao: string, estado: Enum.UserInputState, _entrada: InputObject): Enum.ContextActionResult?
		local ligada = Veiculo.segurando(estado)
		if ligada ~= quad.buzinaLigada then
			quad.buzinaLigada = ligada
			quad.tocarBuzina(ligada) -- você ouve na hora...
			Veiculo.avisarServidor(quad, "Buzina", ligada) -- ...e os outros também
		end
		return Enum.ContextActionResult.Sink
	end, Veiculo.PRIORIDADE, Enum.KeyCode.H, Enum.KeyCode.DPadUp)
end

-- Levantou: para a buzina.
function Buzina.desligar(quad: Quadriciclo)
	BotoesDoCelular.desligar(ACAO_BUZINA)
	if quad.buzinaLigada then
		quad.buzinaLigada = false
		quad.tocarBuzina(false)
	end
end

return Buzina

