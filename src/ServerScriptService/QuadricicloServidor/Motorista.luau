--!strict
--[[
	=====================================================================
	Motorista  (ModuleScript)
	Local: ServerScriptService > QuadricicloServidor > Motorista
	=====================================================================

	O BANCO de cada veículo:
	  - Quando alguém senta, passa a física (Network Ownership) para esse jogador: o controle
	    responde na hora, sem esperar a internet. Quando ele levanta, devolve para o servidor.
	  - O piloto fica sem massa (não muda o centro de massa) e não enrosca nas rodas.
	  - No celular, dirigindo, o analógico fica PARADO no canto (Configuracao: AnalogicoFixoNoCelular).
	  - As ações do motorista que todo mundo precisa ver/ouvir: buzina, nitro e derrapagem
	    (viram Attributes no Model, que chegam em todos os jogadores) e "sair do banco".
	Quem ACELERA e VIRA é o QuadricicloCliente, no computador do jogador.
]]

local Players = game:GetService("Players")

local Montagem = require(script.Parent:WaitForChild("Montagem"))
type Veiculo = Montagem.Veiculo

local Motorista = {}

-- =====================================================================
-- O PILOTO (como o personagem era antes de sentar, para devolver igualzinho depois)
-- =====================================================================
type EstadoOriginal = { massless: boolean, grupo: string }
-- Como cada peça do personagem era ANTES de sentar. Guardado uma vez só: se o veículo some com
-- você dentro e você senta em outro, o "antes" continua sendo o de verdade (e não o de piloto).
local estadoOriginal: { [BasePart]: EstadoOriginal } = setmetatable({}, { __mode = "k" }) :: any
-- Qual veículo está usando cada peça do personagem agora.
local donoDaPeca: { [BasePart]: Model } = setmetatable({}, { __mode = "k" }) :: any
-- As peças do piloto de cada veículo.
local pecasDoPiloto: { [Model]: { BasePart } } = {}

-- =====================================================================
-- (NOVO) O ANALÓGICO DO CELULAR
-- =====================================================================
-- O analógico padrão do Roblox no celular (o "DynamicThumbstick") aparece onde você encosta o dedo, em
-- quase meia tela: dirigindo, isso atrapalha. Então, enquanto a pessoa dirige, ele vira o analógico
-- CLÁSSICO, parado no canto de baixo. Quando ela sai do veículo, volta a ser o que era.
-- (Quem decide qual analógico aparece é o Player.DevTouchMovementMode; mudar ele no servidor é o jeito
-- que o Roblox recomenda. Em computador e videogame isso não muda nada.)
local analogicoAntes: { [Player]: Enum.DevTouchMovementMode } = {} -- o modo de antes de sentar
local veiculoDoJogador: { [Player]: Model } = {} -- em qual veículo o analógico está travado agora

local function travarAnalogico(v: Veiculo, jogador: Player)
	veiculoDoJogador[jogador] = v.modelo
	if not v.Config.AnalogicoFixoNoCelular then
		return
	end
	if analogicoAntes[jogador] == nil then
		analogicoAntes[jogador] = jogador.DevTouchMovementMode
	end
	jogador.DevTouchMovementMode = Enum.DevTouchMovementMode.Thumbstick -- o clássico, parado no canto
end

-- Saiu deste veículo (ou ele sumiu): o analógico volta a ser o de antes.
-- (Se a pessoa já está em OUTRO veículo, não mexe: aquele cuida dela.)
local function soltarAnalogico(v: Veiculo)
	for jogador, modelo in veiculoDoJogador do
		if modelo == v.modelo then
			veiculoDoJogador[jogador] = nil
			local antes = analogicoAntes[jogador]
			analogicoAntes[jogador] = nil
			if antes and jogador.Parent ~= nil then
				jogador.DevTouchMovementMode = antes
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(jogador: Player)
	analogicoAntes[jogador] = nil
	veiculoDoJogador[jogador] = nil
end)

-- Quem mandou a ação é mesmo quem está dirigindo ESTE veículo?
function Motorista.ehOMotorista(v: Veiculo, jogador: Player): boolean
	local humanoide = v.assento.Occupant
	return humanoide ~= nil and humanoide.Parent == jogador.Character
end

local function definirDonoDaFisica(v: Veiculo, jogador: Player?)
	local podeMudar, motivo = v.chassi:CanSetNetworkOwnership()
	if not podeMudar then
		warn(`[Quadriciclo] Não dá para mudar o dono da física de "{v.modelo.Name}": {motivo}`)
		return
	end
	-- Basta chamar no Chassi: Mangas e Rodas estão ligadas a ele por constraints,
	-- formam um "mecanismo" e recebem o mesmo dono automaticamente.
	v.chassi:SetNetworkOwner(jogador)
	Montagem.debugPrint(v, `Dono da física agora: {if jogador then jogador.Name else "SERVIDOR"}`)
end

-- O piloto levantou (ou o veículo sumiu): o personagem volta a ser como era.
local function restaurarPiloto(v: Veiculo)
	local pecas = pecasDoPiloto[v.modelo]
	pecasDoPiloto[v.modelo] = nil
	if pecas == nil then
		return
	end
	for _, parte in pecas do
		if donoDaPeca[parte] ~= v.modelo then
			continue -- (esta peça já está sendo usada por OUTRO veículo: ele cuida dela)
		end
		local estado = estadoOriginal[parte]
		estadoOriginal[parte] = nil
		donoDaPeca[parte] = nil
		if estado and parte.Parent ~= nil then -- o personagem pode ter sido destruído (morreu/saiu)
			parte.Massless = estado.massless
			parte.CollisionGroup = estado.grupo
		end
	end
end

local function prepararPiloto(v: Veiculo, personagem: Model)
	restaurarPiloto(v) -- (por garantia: um piloto antigo deste veículo volta ao normal)
	local pecas: { BasePart } = {}
	for _, objeto in personagem:GetDescendants() do
		if objeto:IsA("BasePart") then
			if estadoOriginal[objeto] == nil then
				estadoOriginal[objeto] = { massless = objeto.Massless, grupo = objeto.CollisionGroup }
			end
			donoDaPeca[objeto] = v.modelo
			table.insert(pecas, objeto)
			objeto.CollisionGroup = Montagem.GRUPO_PILOTO -- pernas não enroscam nas rodas
			if v.Config.MasslessDriver then
				objeto.Massless = true -- o piloto não muda o centro de massa
			end
		end
	end
	pecasDoPiloto[v.modelo] = pecas
end

-- Deixa o veículo "estacionado": rodas seguras e guidão reto.
local function estacionar(v: Veiculo)
	for _, info in v.rodas do
		info.motor.AngularVelocity = 0
		info.motor.MotorMaxTorque = v.Config.MaxTorque
		local suspensao = info.suspensao
		if suspensao:IsA("CylindricalConstraint") then
			suspensao.TargetAngle = 0
		end
	end
end

-- Alguém sentou ou levantou (o QuadricicloServidor chama; também uma vez quando o veículo aparece).
-- (Pode esperar 1 frame.)
function Motorista.aoMudarOcupante(v: Veiculo)
	local humanoide = v.assento.Occupant
	if humanoide then
		-- Alguém sentou. É um jogador de verdade (e não um NPC)?
		local personagem = humanoide.Parent
		if personagem and personagem:IsA("Model") then
			local jogador = Players:GetPlayerFromCharacter(personagem)
			if jogador then
				prepararPiloto(v, personagem)
				travarAnalogico(v, jogador) -- (NOVO) no celular: analógico parado no canto
				-- OBRIGATÓRIO: a física passa a ser calculada no computador do jogador.
				-- Assim o controle responde na hora, sem esperar a internet.
				definirDonoDaFisica(v, jogador)
			end
		end
	else
		-- O motorista levantou (pulou, morreu ou saiu do jogo).
		restaurarPiloto(v)
		soltarAnalogico(v) -- (NOVO) o analógico do celular volta a ser o de antes
		estacionar(v)
		-- Espera 1 frame: o Roblox ainda está desfazendo a solda do banco (SeatWeld).
		-- Se devolvêssemos a física antes, o personagem seria levado junto para o servidor.
		task.wait()
		if v.assento.Occupant == nil and v.modelo:IsDescendantOf(workspace) then
			definirDonoDaFisica(v, nil) -- nil = o SERVIDOR volta a ser o dono
		end
	end
end

-- Banco vazio (saiu, pulou, morreu): desliga a buzina, o nitro e a derrapagem para todo mundo.
function Motorista.limparAtributos(v: Veiculo)
	v.modelo:SetAttribute("Buzina", false)
	v.modelo:SetAttribute("Nitro", false)
	v.modelo:SetAttribute("Derrapando", false)
end

-- =====================================================================
-- AÇÕES DO MOTORISTA: buzina, nitro, derrapagem e sair do banco
-- =====================================================================
-- O QuadricicloCliente pede pelo RemoteEvent; aqui marcamos um Attribute no modelo. Attributes
-- chegam em TODOS os jogadores: é assim que os outros ouvem a buzina e veem o fogo roxo.
-- (Quem chama, o QuadricicloServidor, já conferiu que o jogador é o motorista.)
function Motorista.aoAcao(v: Veiculo, acao: string, ligado: unknown)
	if typeof(ligado) ~= "boolean" then
		return -- (um trapaceiro pode mandar qualquer coisa)
	end
	if acao == "Buzina" or acao == "Nitro" or acao == "Derrapando" then
		if v.modelo:GetAttribute(acao) ~= ligado then -- (só quando muda: menos coisa pela internet)
			v.modelo:SetAttribute(acao, ligado)
		end
	elseif acao == "Sair" then
		local solda = v.assento:FindFirstChild("SeatWeld") -- a solda que prende o jogador no banco
		if solda then
			solda:Destroy() -- sem ela, o jogador sai do banco
		end
	end
end

-- O veículo apareceu: quando ele sumir (apagado, caiu do mapa), o piloto volta ao normal.
-- (Antes, com o script dentro do veículo, o personagem continuava "sem peso" e atravessando
-- os veículos até renascer.)
function Motorista.ligar(v: Veiculo)
	table.insert(v.limpezas, function()
		restaurarPiloto(v)
		soltarAnalogico(v)
	end)
end

return Motorista
