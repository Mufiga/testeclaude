--!strict
--[[
	=====================================================================
	Pancada  (ModuleScript)
	Local: ServerScriptService > QuadricicloServidor > Pancada
	=====================================================================

	PANCADA: um veículo bateu MUITO rápido em OUTRO veículo.
	O cliente de quem dirige avisa "Bater" + o veículo atingido. A física de cada veículo é calculada
	no computador do SEU motorista, então a batida normal quase não mexe no outro. Aqui conferimos
	tudo, calculamos o TRANCO (empurrão, pulinho e giro) e mandamos o computador de quem dirige o
	outro aplicar ("Pancada", pelo RemoteEvent do veículo DELE).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Montagem = require(script.Parent:WaitForChild("Montagem"))
type Veiculo = Montagem.Veiculo

local Pancada = {}

local TAG_QUADRICICLO = "Quadriciclo" -- (a tag dos veículos prontos)
local DISTANCIA_PANCADA = 30 -- (studs) folga: o servidor vê os dois veículos um pouco atrasados
local ESPERA_PANCADA = 1 -- (s) o mesmo veículo só leva outra pancada deste depois disso

type Estado = {
	v: Veiculo,
	-- A maior velocidade dos últimos instantes (ela vai caindo devagar). Quando o aviso "Bater" chega,
	-- a batida já pode ter freado este veículo: vale a velocidade de logo antes dela.
	rapidezRecente: number,
	velocidadeRecente: Vector3,
	ultimaPancada: { [Model]: number }, -- quando (os.clock) cada veículo levou a última pancada deste
}
local estados: { [Model]: Estado } = {}
local comMotorista: { [Model]: Estado } = {} -- só estes têm a velocidade acompanhada (economiza)

RunService.Heartbeat:Connect(function(dt: number)
	for _, estado in comMotorista do
		local agora = estado.v.chassi.AssemblyLinearVelocity
		estado.rapidezRecente -= 60 * dt -- (cai 60 studs/s a cada segundo)
		if agora.Magnitude >= estado.rapidezRecente then
			estado.rapidezRecente = agora.Magnitude
			estado.velocidadeRecente = agora
		end
	end
end)

-- Só a parte "deitada" (sem o sobe e desce) de uma direção, com tamanho 1. Quase toda vertical = zero.
local function noPlano(vetor: Vector3): Vector3
	local plano = Vector3.new(vetor.X, 0, vetor.Z)
	return if plano.Magnitude > 0.1 then plano.Unit else Vector3.zero
end

local function darPancada(estado: Estado, alvo: Model, chassiDoAlvo: BasePart, motorista: Player)
	local v = estado.v
	local Config = v.Config
	-- PARA ONDE: para onde você ia, mais um pouco "para longe de você" (batida de lado empurra de lado).
	local paraOAlvo = chassiDoAlvo.Position - v.chassi.Position
	local direcao = noPlano(noPlano(estado.velocidadeRecente) + noPlano(paraOAlvo))
	local mudanca = direcao * Config.BaterEmpurrao + Vector3.yAxis * Config.BaterSubida -- (studs/s)
	-- GIRO: a batida pegou mais de lado? Ele roda. (O sinal diz para qual lado.)
	local lado = noPlano(paraOAlvo):Cross(direcao).Y -- perto de 0 = batida bem no meio (sem giro)
	local giro = if math.abs(lado) > 0.1 then -lado * Config.BaterGiro else 0
	-- Quem calcula a física do outro veículo é o computador do motorista DELE: mandamos para lá.
	local pastaDoAlvo = alvo:FindFirstChild("Scripts")
	local eventoDoAlvo = if pastaDoAlvo then pastaDoAlvo:FindFirstChild("AcaoQuadriciclo") else nil
	if eventoDoAlvo and eventoDoAlvo:IsA("RemoteEvent") then
		eventoDoAlvo:FireClient(motorista, "Pancada", mudanca, giro)
	end
	-- SOM da batida (tocado aqui no servidor: todo mundo perto ouve).
	if Config.BaterSomId ~= "" then
		local som = Instance.new("Sound")
		som.Name = "SomPancada"
		som.SoundId = Config.BaterSomId
		som.Volume = 1
		som.RollOffMaxDistance = 200
		som.Parent = chassiDoAlvo
		som:Play()
		Debris:AddItem(som, 5)
	end
end

-- =====================================================================
-- PARA O QuadricicloServidor
-- =====================================================================
function Pancada.ligar(v: Veiculo)
	local estado: Estado = {
		v = v,
		rapidezRecente = 0,
		velocidadeRecente = Vector3.zero,
		ultimaPancada = setmetatable({}, { __mode = "k" }) :: any, -- (veículos apagados somem daqui sozinhos)
	}
	estados[v.modelo] = estado
	table.insert(v.limpezas, function()
		if estados[v.modelo] == estado then
			estados[v.modelo] = nil
			comMotorista[v.modelo] = nil
		end
	end)
end

-- Alguém sentou ou levantou: só acompanha a velocidade de quem tem motorista.
function Pancada.aoMudarOcupante(v: Veiculo)
	local estado = estados[v.modelo]
	if estado == nil then
		return
	end
	if v.assento.Occupant then
		if comMotorista[v.modelo] == nil then
			estado.rapidezRecente = 0
			estado.velocidadeRecente = Vector3.zero
			comMotorista[v.modelo] = estado
		end
	else
		comMotorista[v.modelo] = nil
	end
end

-- "Bater" + o veículo atingido. (Quem chama, o QuadricicloServidor, já conferiu que o jogador é o motorista.)
function Pancada.aoBater(v: Veiculo, jogador: Player, alvo: unknown)
	local estado = estados[v.modelo]
	if estado == nil then
		return
	end
	-- Confere tudo: quem manda é o cliente, e um trapaceiro pode mandar qualquer coisa.
	if typeof(alvo) ~= "Instance" or not alvo:IsA("Model") or alvo == v.modelo or not alvo:IsDescendantOf(workspace) then
		return
	end
	if not CollectionService:HasTag(alvo, TAG_QUADRICICLO) then
		return -- só vale bater em veículo
	end
	local chassiDoAlvo = alvo:FindFirstChild("Chassi")
	local bancoDoAlvo = alvo:FindFirstChild("Banco")
	if not (chassiDoAlvo and chassiDoAlvo:IsA("BasePart")) or not (bancoDoAlvo and bancoDoAlvo:IsA("VehicleSeat")) then
		return
	end
	-- Precisa ter OUTRO JOGADOR dirigindo ele.
	local outroPiloto = bancoDoAlvo.Occupant
	local personagem = if outroPiloto then outroPiloto.Parent else nil
	local motorista = if personagem and personagem:IsA("Model") then Players:GetPlayerFromCharacter(personagem) else nil
	if motorista == nil or motorista == jogador then
		return
	end
	-- Estava rápido de verdade e está perto? (com folga: o servidor vê tudo um pouquinho atrasado)
	if estado.rapidezRecente < v.Config.BaterVelocidadeMinima * 0.7 then
		return
	end
	if (chassiDoAlvo.Position - v.chassi.Position).Magnitude > DISTANCIA_PANCADA then
		return
	end
	local agora = os.clock()
	if agora - (estado.ultimaPancada[alvo] or 0) < ESPERA_PANCADA then
		return
	end
	estado.ultimaPancada[alvo] = agora
	darPancada(estado, alvo, chassiDoAlvo, motorista)
	Montagem.debugPrint(v, `Pancada de {jogador.Name} em "{alvo:GetFullName()}"`)
end

return Pancada
