--!strict
--[[
	=====================================================================
	QuadricicloCliente  (LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente
	=====================================================================

	UM script só, para TODOS os quadriciclos do mapa. Roda no computador ou
	celular de cada jogador e:
	  - Acha cada quadriciclo (o QuadricicloServidor marca o Model com a tag
	    "Quadriciclo" quando ele fica pronto) e liga os efeitos que todo mundo
	    vê e ouve: fogo do nitro, buzina, fumaça do freio de mão e o gancho voando.
	  - Quando VOCÊ senta no banco de um deles, liga os controles, o HUD e a
	    câmera. A cada frame calcula aceleração, freio e direção e aplica nos
	    motores (HingeConstraint) e na direção (CylindricalConstraint).
	  - Quando você levanta, desliga tudo e deixa o quadriciclo estacionado.

	Por que aqui e não no servidor? Porque o QuadricicloServidor passa a física
	(Network Ownership) para quem senta. Mudar os motores AQUI tem efeito
	imediato, sem esperar a internet: zero lag no controle.

	Cada assunto fica num ModuleScript aqui dentro: Veiculo, Velocimetro,
	Camera, Nitro, Buzina, FreioDeMao, Ladeira, Gancho, TeclasMenu, BoostPads,
	Sensacao, Monstro, Pista, BotoesDoCelular e PoeiraDoChao.
	Os valores de ajuste ficam na Configuracao de cada quadriciclo (e na
	ReplicatedStorage > Compartilhado > ConfiguracaoPadrao).

	Controles:
	  PC ........ W/↑ acelera · S/↓ freia e dá ré · A/D ou ←/→ vira · R desvira
	              Shift nitro · H buzina · Espaço freio de mão · C câmera
	              Q gancho (segure para mirar, solte para lançar) · E sai do banco
	  Controle .. RT acelera · LT freia/ré · analógico esquerdo vira · seta ↓ desvira
	              R1 nitro · seta ↑ buzina · B freio de mão · Y câmera · L1 gancho · X sai
	              A super pulo (no caminhão monstro) · a pé, as setas mexem no HUD de veículos
	  Celular ... botões GÁS, FREIO, GANCHO, NITRO, F. MÃO, BUZINA, CÂMERA, SAIR (e PULO no monstro)
	              · o analógico da tela vira (o módulo BotoesDoCelular cuida desses botões)
]]

-- =====================================================================
-- SERVIÇOS E MÓDULOS
-- =====================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")

-- Antes de tudo, confere se os 15 ModuleScripts estão aqui dentro (com o nome certinho).
for _, nome in { "Veiculo", "Velocimetro", "Camera", "Nitro", "Buzina", "FreioDeMao", "Ladeira", "Gancho", "TeclasMenu", "BoostPads", "Sensacao", "Monstro", "Pista", "BotoesDoCelular", "PoeiraDoChao" } do
	if script:WaitForChild(nome, 5) == nil then
		warn(`[Quadriciclo] Falta o ModuleScript "{nome}" dentro do QuadricicloCliente (StarterPlayerScripts).`
			.. " Confira o nome: maiúsculas e minúsculas contam, e não tem acento.")
	end
end

local Veiculo = require(script:WaitForChild("Veiculo"))
local Velocimetro = require(script:WaitForChild("Velocimetro"))
local Camera = require(script:WaitForChild("Camera"))
local Nitro = require(script:WaitForChild("Nitro"))
local Buzina = require(script:WaitForChild("Buzina"))
local FreioDeMao = require(script:WaitForChild("FreioDeMao"))
local Ladeira = require(script:WaitForChild("Ladeira"))
local Gancho = require(script:WaitForChild("Gancho"))
local TeclasMenu = require(script:WaitForChild("TeclasMenu"))
local BoostPads = require(script:WaitForChild("BoostPads")) -- (NOVO) pads de boost
BoostPads.iniciar() -- (NOVO) acha os pads do mapa e liga a animação das setas
local Sensacao = require(script:WaitForChild("Sensacao")) -- (NOVO) molas, peso, marcas, poeira e câmera mais gostosos
local Monstro = require(script:WaitForChild("Monstro")) -- (NOVO) super pulo e mortais do caminhão monstro
local Pista = require(script:WaitForChild("Pista")) -- (NOVO) loops, tubos, rampas e terreno
local BotoesDoCelular = require(script:WaitForChild("BotoesDoCelular")) -- (NOVO) os botões da tela no celular
local PoeiraDoChao = require(script:WaitForChild("PoeiraDoChao")) -- (NOVO) as rodas jogam o chão (da cor dele)
type Quadriciclo = Veiculo.Quadriciclo

-- O Studio trata LocalPlayer como "talvez nil" (no servidor ele não existe).
-- Aqui é sempre o cliente, então avisamos ao verificador de tipos com "::".
local jogadorLocal = Players.LocalPlayer :: Player

-- =====================================================================
-- CONSTANTES INTERNAS (normalmente não precisa mexer)
-- =====================================================================
local TAG_QUADRICICLO = "Quadriciclo" -- o QuadricicloServidor coloca esta tag no Model quando ele fica pronto

local ACAO_ACELERAR = "QuadricicloAcelerar"
local ACAO_FREAR = "QuadricicloFrear"
local ACAO_ESQUERDA = "QuadricicloEsquerda"
local ACAO_DIREITA = "QuadricicloDireita"
local ACAO_ANALOGICO = "QuadricicloAnalogico"
local ACAO_DESVIRAR = "QuadricicloDesvirar"
local ACAO_SAIR = "QuadricicloSair"
local TODAS_AS_ACOES = { ACAO_ACELERAR, ACAO_FREAR, ACAO_ESQUERDA, ACAO_DIREITA, ACAO_ANALOGICO, ACAO_DESVIRAR, ACAO_SAIR }

local ZONA_MORTA = 0.1 -- ignora toques muito leves no pedal/analógico
local FOLGA_VELOCIDADE = 4 -- (studs/s) o alvo nunca se afasta mais que isso da velocidade real
local VELOCIDADE_TROCA_SENTIDO = 1.5 -- (studs/s) abaixo disso, "S" vira ré em vez de freio

-- =====================================================================
-- CONTROLES (ContextActionService)
-- =====================================================================
local entradas: { [string]: { [string]: number } } = {
	Acelerar = {},
	Frear = {},
	Esquerda = {},
	Direita = {},
}
local volanteAnalogico = 0 -- analógico esquerdo do controle (-1 a 1)
local saidaPedida = false -- apertou E: quando sair do banco, dá o pulo

local function maiorValor(tabela: { [string]: number }): number
	local maior = 0
	for _, valor in tabela do
		if valor > maior then
			maior = valor
		end
	end
	return maior
end

local function criarManipulador(tabela: { [string]: number })
	return function(_nomeAcao: string, estado: Enum.UserInputState, entrada: InputObject): Enum.ContextActionResult?
		local chave = if entrada.UserInputType == Enum.UserInputType.Touch then "Touch" else entrada.KeyCode.Name
		if estado == Enum.UserInputState.Begin or estado == Enum.UserInputState.Change then
			local intensidade = 1
			if entrada.KeyCode == Enum.KeyCode.ButtonR2 or entrada.KeyCode == Enum.KeyCode.ButtonL2 then
				intensidade = entrada.Position.Z -- gatilhos do controle são analógicos (0 a 1)
			end
			if intensidade > ZONA_MORTA then
				tabela[chave] = intensidade
			else
				tabela[chave] = nil
			end
		else
			tabela[chave] = nil -- End ou Cancel = soltou
		end
		-- (NOVO) As setas ←/→ só viram o quadriciclo. Sem isto, a câmera clássica do Roblox também
		-- giraria com elas (a câmera de veículo padrão ignorava as setas; a clássica não).
		if entrada.KeyCode == Enum.KeyCode.Left or entrada.KeyCode == Enum.KeyCode.Right then
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
end

local function aoMoverAnalogico(_nomeAcao: string, estado: Enum.UserInputState, entrada: InputObject): Enum.ContextActionResult?
	if estado == Enum.UserInputState.End or estado == Enum.UserInputState.Cancel then
		volanteAnalogico = 0
	else
		local x = entrada.Position.X
		volanteAnalogico = if math.abs(x) > ZONA_MORTA then x else 0
	end
	return Enum.ContextActionResult.Pass
end

-- Pedal, volante e desvirar. (No celular, os botões GÁS e FREIO, e ESQ/DIR se MobileSteerButtons = true:
-- o lugar de cada um fica no módulo BotoesDoCelular.)
local function ligarControles(quad: Quadriciclo)
	local Config = quad.Config
	local PRIORIDADE = Veiculo.PRIORIDADE
	BotoesDoCelular.ligar(ACAO_ACELERAR, "GAS", criarManipulador(entradas.Acelerar), PRIORIDADE,
		Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.ButtonR2)
	BotoesDoCelular.ligar(ACAO_FREAR, "FREIO", criarManipulador(entradas.Frear), PRIORIDADE, -- segurando, freia e depois dá ré
		Enum.KeyCode.S, Enum.KeyCode.Down, Enum.KeyCode.ButtonL2)
	BotoesDoCelular.ligar(ACAO_ESQUERDA, if Config.MobileSteerButtons then "ESQ" else nil, criarManipulador(entradas.Esquerda), PRIORIDADE,
		Enum.KeyCode.A, Enum.KeyCode.Left)
	BotoesDoCelular.ligar(ACAO_DIREITA, if Config.MobileSteerButtons then "DIR" else nil, criarManipulador(entradas.Direita), PRIORIDADE,
		Enum.KeyCode.D, Enum.KeyCode.Right)
	ContextActionService:BindActionAtPriority(ACAO_ANALOGICO, aoMoverAnalogico, false, PRIORIDADE,
		Enum.KeyCode.Thumbstick1)
	-- false = sem botão VIRAR no celular (o seu BotaoDesvirar do HUD já faz isso).
	ContextActionService:BindActionAtPriority(ACAO_DESVIRAR, function(_nomeAcao: string, estado: Enum.UserInputState, _entrada: InputObject): Enum.ContextActionResult?
		if estado == Enum.UserInputState.Begin then
			Veiculo.desvirar(quad)
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORIDADE, Enum.KeyCode.R, Enum.KeyCode.DPadDown)
end

-- E / botão X / botão SAIR: o Servidor desfaz a solda do banco.
local function ligarSaida(quad: Quadriciclo)
	BotoesDoCelular.ligar(ACAO_SAIR, "SAIR", function(_nomeAcao: string, estado: Enum.UserInputState, _entrada: InputObject): Enum.ContextActionResult?
		if estado == Enum.UserInputState.Begin then
			saidaPedida = true
			Veiculo.avisarServidor(quad, "Sair", true)
		end
		return Enum.ContextActionResult.Sink
	end, Veiculo.PRIORIDADE, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
end

local function desligarControles()
	for _, nome in TODAS_AS_ACOES do
		BotoesDoCelular.desligar(nome) -- (a tecla, o botão do controle e o botão da tela)
	end
	for _, tabela in entradas do
		table.clear(tabela)
	end
	volanteAnalogico = 0
end

local function lerControles(quad: Quadriciclo): (number, number)
	local pedal = maiorValor(entradas.Acelerar) - maiorValor(entradas.Frear)
	local volante = maiorValor(entradas.Direita) - maiorValor(entradas.Esquerda)
	if math.abs(volanteAnalogico) > math.abs(volante) then
		volante = volanteAnalogico
	end
	if math.abs(quad.assento.ThrottleFloat) > math.abs(pedal) then
		pedal = quad.assento.ThrottleFloat
	end
	if math.abs(quad.assento.SteerFloat) > math.abs(volante) then
		volante = quad.assento.SteerFloat
	end
	return math.clamp(pedal, -1, 1), math.clamp(volante, -1, 1)
end

-- =====================================================================
-- DIRIGIR: o coração do script (roda a cada frame)
-- =====================================================================
local velocidadeAlvo = 0 -- velocidade que queremos nas rodas agora (studs/s; negativo = ré)

local function aproximar(atual: number, alvo: number, passo: number): number
	if atual < alvo then
		return math.min(atual + passo, alvo)
	end
	return math.max(atual - passo, alvo)
end

-- (NOVO) PANCADA: bater MUITO rápido em outro quadriciclo. A física de cada quadriciclo é calculada no
-- computador do SEU motorista, então a batida normal quase não mexe no outro. Quando você passa de
-- Config.BaterVelocidadeMinima e encosta num quadriciclo com OUTRO jogador dirigindo, indo de encontro
-- a ele, este script avisa o Servidor ("Bater"). O Servidor confere e manda o computador de quem dirige
-- o outro aplicar o tranco ("Pancada"): lá é onde a física dele é calculada.
local APROXIMACAO_MINIMA = 20 -- (studs/s) precisa ir DE ENCONTRO a ele (encostar andando junto não conta)
local ESPERA_PANCADA = 1 -- (s) o mesmo quadriciclo só leva outra pancada sua depois disso
local ultimaPancada: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- (veículos apagados somem daqui sozinhos)
local velocidadeAnterior = Vector3.zero -- a sua velocidade no frame passado...
local quandoAnterior = 0 -- ...e quando ela foi medida (os.clock)
local conexaoPancada: RBXScriptConnection? = nil
local filtroPancada: OverlapParams? = nil -- (criado uma vez quando você senta: ignora o seu veículo e você)

-- O quadriciclo (Model com a tag "Quadriciclo") de quem esta peça faz parte, ou nil.
local function quadricicloDaPeca(peca: Instance): Model?
	local atual = peca.Parent
	while atual and atual ~= workspace do
		if atual:IsA("Model") and CollectionService:HasTag(atual, TAG_QUADRICICLO) then
			return atual
		end
		atual = atual.Parent
	end
	return nil
end

-- Roda a cada frame (no "atualizar"): você está rápido e encostou em outro quadriciclo?
local function procurarPancada(quad: Quadriciclo, dt: number)
	-- A batida pode já ter freado você neste frame: vale a MAIOR entre a velocidade de agora e a de antes.
	local agora = os.clock()
	local atual = quad.chassi.AssemblyLinearVelocity
	local antes = if agora - quandoAnterior < 0.2 then velocidadeAnterior else Vector3.zero
	velocidadeAnterior, quandoAnterior = atual, agora
	local velocidade = if antes.Magnitude > atual.Magnitude then antes else atual
	local minima = quad.Config.BaterVelocidadeMinima
	local cima = Veiculo.referencia(quad).UpVector
	local noVelocimetro = (velocidade - cima * velocidade:Dot(cima)).Magnitude -- (a mesma conta do velocímetro)
	local filtro = filtroPancada
	if typeof(minima) ~= "number" or noVelocimetro < minima or filtro == nil then
		return -- devagar (ou uma Configuracao sem a parte da PANCADA)
	end
	-- Uma caixa um pouco maior que o Chassi (mais rápido = um pouco maior): o que estiver encostando aparece aqui.
	local folga = 3 + velocidade.Magnitude * dt
	local encostando = workspace:GetPartBoundsInBox(quad.chassi.CFrame, quad.chassi.Size + Vector3.new(folga, folga, folga), filtro)
	for _, peca in encostando do
		local outro = quadricicloDaPeca(peca)
		if outro == nil or agora - (ultimaPancada[outro] or 0) < ESPERA_PANCADA then
			continue
		end
		local banco = outro:FindFirstChild("Banco")
		local chassiDoOutro = outro:FindFirstChild("Chassi")
		if not (banco and banco:IsA("VehicleSeat") and banco.Occupant) or not (chassiDoOutro and chassiDoOutro:IsA("BasePart")) then
			continue -- ninguém dirigindo ele (ou falta peça)
		end
		local paraEle = chassiDoOutro.Position - quad.chassi.Position
		if paraEle.Magnitude < 0.1 then
			continue
		end
		-- Quão rápido você está chegando NELE (a velocidade dele conta: se ele foge, a batida é mais fraca).
		local aproximacao = (velocidade - chassiDoOutro.AssemblyLinearVelocity):Dot(paraEle.Unit)
		if aproximacao >= APROXIMACAO_MINIMA then
			ultimaPancada[outro] = agora
			Veiculo.avisarServidor(quad, "Bater", outro)
		end
	end
end

-- Você LEVOU uma pancada: o Servidor manda a mudança de velocidade e o giro. A física do seu
-- quadriciclo é calculada aqui, então aplicamos na hora, em todas as peças (ele vai inteiro).
local function levarPancada(quad: Quadriciclo, mudanca: Vector3, giro: number)
	local centro = quad.chassi.Position
	local girar = Vector3.new(0, giro, 0) -- gira só em volta do eixo "de pé": não capota
	for _, parte in quad.pecasFisicas do
		parte.AssemblyLinearVelocity += mudanca + girar:Cross(parte.Position - centro)
		parte.AssemblyAngularVelocity += girar
	end
end

-- Sentou: passa a ouvir as pancadas que o Servidor manda para ESTE quadriciclo.
local function ligarPancada(quad: Quadriciclo)
	-- O "filtro" da procura por outros veículos: o seu quadriciclo e você não contam.
	local filtro = OverlapParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar: { Instance } = { quad.modelo }
	local personagem = jogadorLocal.Character
	if personagem then
		table.insert(ignorar, personagem)
	end
	filtro.FilterDescendantsInstances = ignorar
	filtroPancada = filtro
	local evento = quad.pastaScripts:FindFirstChild("AcaoQuadriciclo")
	if evento and evento:IsA("RemoteEvent") then
		conexaoPancada = evento.OnClientEvent:Connect(function(acao: unknown, mudanca: unknown, giro: unknown)
			if acao == "Pancada" and typeof(mudanca) == "Vector3" and typeof(giro) == "number" then
				levarPancada(quad, mudanca, giro)
			end
		end)
	end
end

-- Levantou: para de ouvir.
local function desligarPancada()
	local conexao = conexaoPancada
	if conexao then
		conexao:Disconnect()
	end
	conexaoPancada = nil
	filtroPancada = nil
end

-- (NOVO) DESVIRAR MAIS ALTO + TREMOR NO POUSO
-- O desvirar coloca o quadriciclo de pé, um pouco acima do chão, de uma vez só. Este pedaço percebe isso
-- e levanta MAIS Config.DesvirarAlturaExtra studs. Quando ele cai de volta no chão, a tela treme.
local ultimaReferencia: CFrame? = nil -- como o quadriciclo estava no frame passado...
local quandoUltimaReferencia = 0 -- ...e quando foi isso (os.clock)
local esperandoPouso = false -- desvirou e ainda não chegou no chão?
local esperarPousoAte = 0 -- (os.clock) desiste de esperar o pouso depois disso
local quedaAnterior = 0 -- (studs/s) a velocidade "para cima" no frame passado (negativa = caindo)

local function acompanharDesvirar(quad: Quadriciclo)
	local agora = os.clock()
	local referencia = Veiculo.referencia(quad)
	local antes = if agora - quandoUltimaReferencia < 0.2 then ultimaReferencia else nil -- (frame velho não conta)
	ultimaReferencia, quandoUltimaReferencia = referencia, agora
	-- 1) Desvirou AGORA? (no frame passado estava tombado; agora está de pé e mais alto)
	if antes and antes.UpVector.Y < 0.5 and referencia.UpVector.Y > 0.9 and referencia.Position.Y > antes.Position.Y + 0.5 then
		local extra = if typeof(quad.Config.DesvirarAlturaExtra) == "number" then quad.Config.DesvirarAlturaExtra else 4
		quad.modelo:PivotTo(quad.modelo:GetPivot() + Vector3.new(0, extra, 0)) -- levanta mais um pouco
		ultimaReferencia = Veiculo.referencia(quad)
		esperandoPouso = true
		esperarPousoAte = agora + 4
		quedaAnterior = 0
		return
	end
	-- 2) Caindo depois de desvirar: quando a queda "para de repente", ele bateu no chão. Treme!
	if esperandoPouso then
		local subida = quad.chassi.AssemblyLinearVelocity.Y
		if quedaAnterior < -8 and subida > quedaAnterior + 6 then
			esperandoPouso = false
			Camera.tremer(math.clamp(-quedaAnterior / 80, 0.15, 0.5)) -- caiu mais rápido = treme mais
		elseif agora > esperarPousoAte then
			esperandoPouso = false -- demorou demais: desiste
		end
		quedaAnterior = subida
	end
end

-- (NOVO) PANCADA DO NITRO: quando o nitro LIGA, o Chassi afunda nas molas e a frente sobe um pouco
-- (a traseira "senta"), como se o motor fizesse uma força enorme de uma vez. As molas voltam sozinhas.
-- (No máximo 1 pancada a cada 0,6 s, para não ficar tremendo se o nitro piscar.)
local ultimaPancadaNitro = 0
local function pancadaDoNitro(quad: Quadriciclo)
	local agora = os.clock()
	if agora - ultimaPancadaNitro < 0.6 then
		return
	end
	ultimaPancadaNitro = agora
	local Config = quad.Config
	local referencia = Veiculo.referencia(quad)
	local afundar = if typeof(Config.NitroPancada) == "number" then Config.NitroPancada else 14 -- (studs/s para baixo)
	local empinar = if typeof(Config.NitroEmpinar) == "number" then Config.NitroEmpinar else 1.5 -- (rad/s: a frente sobe)
	quad.chassi.AssemblyLinearVelocity -= referencia.UpVector * afundar -- só o Chassi: as molas afundam
	quad.chassi.AssemblyAngularVelocity += referencia.RightVector * empinar -- a frente sobe, a traseira senta
	Camera.tremer(0.12) -- tranco na câmera
end
local function atualizar(quad: Quadriciclo, dt: number)
	local Config = quad.Config
	local rodas = quad.rodas

	-- 1) CONTROLES
	local pedal, volante = lerControles(quad)

	-- 2) VELOCIDADE ATUAL para frente (negativa = indo de ré)
	local referencia = Veiculo.referencia(quad)
	local velocidade = quad.chassi.AssemblyLinearVelocity
	local velocidadeFrente = velocidade:Dot(referencia.LookVector)
	Veiculo.acompanharTombado(quad, dt) -- conta o tempo de cabeça para baixo (para poder desvirar)
	acompanharDesvirar(quad) -- (NOVO) desvirou? levanta mais e, ao cair no chão, a tela treme
	Sensacao.atualizar(quad, dt) -- (NOVO) peso nas molas, marcas de pneu, câmera e pouso
	-- LADEIRA: descendo, a velocidade máxima vai subindo (até Config.VelocidadeMaximaTotal)
	local maximaAgora, descida = Ladeira.velocidadeMaximaAgora(quad, referencia, velocidadeFrente, dt)

	-- 3) DECIDIR o que fazer: acelerar, dar ré, frear ou deixar rolar
	local desejada = 0 -- velocidade que queremos atingir
	local ritmo = Config.CoastDeceleration -- quão rápido mudamos até lá (studs/s²)
	local freando = false
	-- (NOVO) SEGURAR NA LADEIRA: true = as 4 rodas seguram o quadriciclo, com força extra
	-- (Config.LadeiraForcaSegurar vezes o MaxTorque; se a Configuracao não tiver, vale 2).
	local segurarNaLadeira = false
	local forcaLadeira = if typeof(Config.LadeiraForcaSegurar) == "number" then Config.LadeiraForcaSegurar else 2
	if pedal > ZONA_MORTA then
		if velocidadeFrente < -VELOCIDADE_TROCA_SENTIDO then
			freando = true -- ainda está de ré: primeiro freia
			segurarNaLadeira = true -- (NOVO) com as 4 rodas e força extra (a gravidade pode estar puxando)
			ritmo = Config.BrakeDeceleration
		else
			desejada = pedal * maximaAgora
			ritmo = Config.Acceleration
		end
	elseif pedal < -ZONA_MORTA then
		if velocidadeFrente > VELOCIDADE_TROCA_SENTIDO then
			freando = true -- está indo para frente: "S" é freio
			ritmo = Config.BrakeDeceleration
		else
			desejada = pedal * Config.ReverseSpeed -- parado ou devagar: "S" é ré
			ritmo = Config.Acceleration
			-- (NOVO) De costas na ladeira, a gravidade empurra a ré além do limite (Config.ReverseSpeed).
			-- Passou do limite? As 4 rodas SEGURAM e a velocidade volta para o limite da ré.
			if velocidadeFrente < desejada - VELOCIDADE_TROCA_SENTIDO then
				segurarNaLadeira = true
				ritmo = Config.BrakeDeceleration
			end
		end
	elseif descida > 0.08 and velocidadeFrente > VELOCIDADE_TROCA_SENTIDO then
		-- Sem pedal na descida: a gravidade puxa (quanto mais inclinado, mais rápido).
		desejada = maximaAgora * math.min(descida * 3, 1)
		ritmo = Config.Acceleration
	elseif velocidadeFrente < VELOCIDADE_TROCA_SENTIDO then
		-- (NOVO) Sem pedal, parado ou escorregando de ré: as 4 rodas seguram (ele para aos poucos e fica parado).
		segurarNaLadeira = true
	end

	-- NITRO: vale como acelerador no máximo, com um pouco mais de velocidade e aceleração.
	-- Não funciona dando ré, freando, com o freio de mão puxado ou com o tanque vazio.
	-- (Nitro.disponivel vem primeiro: ela gasta/recarrega o tanque e mexe na barra a cada frame.)
	local nitroAgora = Nitro.disponivel(quad)
		and not quad.freioDeMao
		and pedal > -ZONA_MORTA
		and velocidadeFrente > -VELOCIDADE_TROCA_SENTIDO
	if nitroAgora then
		desejada = math.min(maximaAgora + Config.NitroSpeedBonus, Config.VelocidadeMaximaTotal)
		ritmo = Config.Acceleration * Config.NitroAccelerationMultiplier
	end
	if nitroAgora ~= quad.nitroAtivo then
		Nitro.mudar(quad, nitroAgora) -- fogo, som e aviso ao Servidor: só quando liga ou desliga
		if nitroAgora then
			pancadaDoNitro(quad) -- (NOVO) ligou: a traseira afunda nas molas e a câmera dá um tranco
		end
	end
	-- (NOVO) BOOST PAD: passou por cima de um, ganhou um empurrão e, por um tempinho, pode passar da
	-- velocidade máxima (os motores ajudam em vez de frear). Não vale freando nem de ré.
	local extraDoBoost = BoostPads.atualizar(quad)
	if extraDoBoost > 0 and pedal > -ZONA_MORTA and velocidadeFrente > -VELOCIDADE_TROCA_SENTIDO then
		desejada = math.max(desejada, maximaAgora + extraDoBoost)
		ritmo = math.max(ritmo, Config.Acceleration * 2)
	end

	-- A RAMPA: a velocidade-alvo muda no máximo "ritmo × dt" por frame (aceleração suave).
	-- O "clamp" mantém o alvo perto da velocidade real (depois de pulos e batidas).
	velocidadeAlvo = math.clamp(velocidadeAlvo, velocidadeFrente - FOLGA_VELOCIDADE, velocidadeFrente + FOLGA_VELOCIDADE)
	velocidadeAlvo = aproximar(velocidadeAlvo, desejada, ritmo * dt)


	-- 4) DIREÇÃO: em alta velocidade o ângulo máximo diminui (estilo arcade, não capota)
	local fracaoVelocidade = math.clamp(math.abs(velocidadeFrente) / math.max(Config.MaxSpeed, 1), 0, 1)
	local anguloMaximo = Config.SteerAngle + (Config.SteerAngleAtMaxSpeed - Config.SteerAngle) * fracaoVelocidade
	-- (NOVO) Acima da velocidade máxima (ladeira, nitro, impulso), o ângulo continua caindo:
	-- o dobro da velocidade = metade do ângulo. Nunca fica menor que Config.SteerAngleMinimo.
	local rapidezAgora = math.abs(velocidadeFrente)
	if rapidezAgora > Config.MaxSpeed and rapidezAgora > 1 then
		local minimo = if typeof(Config.SteerAngleMinimo) == "number" then Config.SteerAngleMinimo else 4
		anguloMaximo = math.max(Config.SteerAngleAtMaxSpeed * Config.MaxSpeed / rapidezAgora, math.min(minimo, anguloMaximo))
	end
	local anguloAlvo = volante * anguloMaximo
	for _, info in rodas do
		local direcao = info.direcao
		if direcao then
			direcao.TargetAngle = anguloAlvo * info.sinalDirecao
		end
	end

	-- 5) MOTORES: cada roda gira na velocidade certa para o seu caminho na curva
	local anguloAtual = Veiculo.anguloDaDirecao(quad)
	for _, info in rodas do
		local velocidadeDaRoda = velocidadeAlvo * Veiculo.fatorDiferencial(quad, info, anguloAtual) -- studs/s no chão
		info.motor.AngularVelocity = (velocidadeDaRoda / info.raio) * info.sinalMotor -- radianos/s
		-- Rodas sem tração ficam soltas, mas TODAS freiam.
		-- (NOVO) Segurando na ladeira (e sem nitro), as 4 rodas seguram com força extra.
		if segurarNaLadeira and not nitroAgora then
			info.motor.MotorMaxTorque = Config.MaxTorque * forcaLadeira
		else
			info.motor.MotorMaxTorque = if info.tracao or freando then Config.MaxTorque else 0
		end
	end

	-- 5b) FREIO DE MÃO trava as rodas; NITRO dá mais força às rodas com tração.
	for _, info in rodas do
		if quad.freioDeMao then
			local trava = not Config.HandbrakeRearOnly or not info.dianteira
			info.motor.AngularVelocity = 0
			info.motor.MotorMaxTorque = if trava then Config.MaxTorque * Config.HandbrakeTorqueMultiplier else 0
		elseif quad.nitroAtivo and info.tracao then
			info.motor.MotorMaxTorque = Config.MaxTorque * Config.NitroTorqueMultiplier
		end
	end
	if quad.freioDeMao then
		velocidadeAlvo = 0 -- ao soltar, a rampa recomeça da velocidade real
	end
	FreioDeMao.atualizar(quad, volante) -- (NOVO) com o volante: derrapando, ele só gira para onde você virar
	Gancho.atualizarImpulso(quad, pedal, dt, volante) -- gancho de IMPULSO + (NOVO) o volante gira o quadriciclo pendurado
	Monstro.atualizar(quad, dt, pedal, volante) -- (NOVO) super pulo e mortais (só no caminhão monstro)
	Pista.atualizar(quad, dt) -- (NOVO) loops, tubos, rampas, pouso perfeito e terreno (só no caminhão monstro)
	-- (NOVO) as rodas jogam o chão: arrancada, freada, turbo (nitro ou boost pad), derrapagem e pouso.
	-- (Depois do Nitro.mudar: assim ele já sabe, neste mesmo frame, se o nitro acabou de ligar.)
	PoeiraDoChao.atualizar(quad, dt, pedal, extraDoBoost > 0)
	procurarPancada(quad, dt) -- (NOVO) bateu muito rápido em outro quadriciclo? O Servidor manda o tranco nele
	-- 6) DEBUG (o velocímetro é atualizado pelo módulo Velocimetro)
	if Config.DEBUG_MODE then
		for _, info in rodas do
			Veiculo.verificarFisica(info, dt)
		end
	end
end

-- =====================================================================
-- LIGAR / DESLIGAR quando você senta ou levanta
-- =====================================================================
local quadAtual: Quadriciclo? = nil -- o quadriciclo que VOCÊ está dirigindo agora
local conexaoFisica: RBXScriptConnection? = nil

local function comecarADirigir(quad: Quadriciclo)
	if quadAtual ~= nil or not Veiculo.prepararRodas(quad) then
		return
	end
	quadAtual = quad
	quad.dirigindo = true
	saidaPedida = false
	velocidadeAlvo = quad.chassi.AssemblyLinearVelocity:Dot(Veiculo.referencia(quad).LookVector)
	ligarControles(quad)
	Gancho.ligar(quad)
	Nitro.ligar(quad)
	Buzina.ligar(quad)
	FreioDeMao.ligar(quad)
	Camera.ligar(quad)
	ligarSaida(quad)
	BotoesDoCelular.dirigindo(true) -- (NOVO) no celular: aparecem os botões e some o pulo do Roblox
	Velocimetro.ligar(quad)
	TeclasMenu.ligar(quad)
	ligarPancada(quad) -- (CORRIGIDO) passa a ouvir as pancadas que você levar: UMA vez, ao sentar
	conexaoFisica = RunService.PreSimulation:Connect(function(dt: number)
		atualizar(quad, dt)
	end)
	if quad.Config.DEBUG_MODE then
		print(`[Quadriciclo] Dirigindo! {#quad.rodas} rodas | entre-eixos {string.format("%.2f", quad.entreEixos)} studs`)
	end
end

local function pararDeDirigir()
	local quad = quadAtual
	if quad == nil then
		return
	end
	quadAtual = nil
	local conexao = conexaoFisica
	if conexao then
		conexao:Disconnect()
	end
	conexaoFisica = nil
	desligarControles()
	quad.dirigindo = false
	Gancho.desligar(quad) -- saiu com o gancho preso: solta
	FreioDeMao.desligar(quad)
	Nitro.desligar(quad)
	Buzina.desligar(quad)
	Camera.desligar(quad) -- volta a câmera normal
	TeclasMenu.desligar()
	Velocimetro.desligar(quad)
	Veiculo.estacionar(quad)
	desligarPancada() -- (NOVO) para de ouvir as pancadas
	-- Desliga NA HORA as forças e efeitos da sensação, do monstro e da pista. (Antes eles só
	-- percebiam 1 segundo depois, e nesse meio tempo a "leveza no ar" e o "grudar no loop" continuavam.)
	Sensacao.desligar()
	Monstro.desligar()
	Pista.desligar()
	PoeiraDoChao.desligar()
	BotoesDoCelular.dirigindo(false) -- (NOVO) os botões somem e o pulo volta (antes do pulo aqui embaixo)
	velocidadeAlvo = 0
	if saidaPedida then -- saiu pelo E: dá o pulo para fora do quadriciclo
		saidaPedida = false
		local personagem = jogadorLocal.Character
		local humanoide = if personagem then personagem:FindFirstChildOfClass("Humanoid") else nil
		if humanoide then
			humanoide:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end

-- Alguém sentou ou levantou do banco deste quadriciclo: é você?
local function conferirMotorista(quad: Quadriciclo)
	local humanoide = quad.assento.Occupant
	local souEu = humanoide ~= nil and humanoide.Parent == jogadorLocal.Character
	if souEu then
		if quadAtual ~= quad then
			pararDeDirigir() -- (por garantia: nunca dirige dois ao mesmo tempo)
			comecarADirigir(quad)
		end
	elseif quadAtual == quad then
		pararDeDirigir()
	end
end

-- =====================================================================
-- ACHAR OS QUADRICICLOS (tag "Quadriciclo", que o QuadricicloServidor coloca)
-- =====================================================================
local quadriciclos: { [Model]: Quadriciclo } = {} -- os que já estão funcionando no seu jogo
local preparando: { [Model]: boolean } = {} -- esperando as peças chegarem
local vigiados: { [Model]: RBXScriptConnection } = {}

-- O quadriciclo saiu do seu jogo: desliga tudo dele.
local function esquecer(modelo: Model)
	local quad = quadriciclos[modelo]
	if quad == nil then
		return
	end
	quadriciclos[modelo] = nil
	if quadAtual == quad then
		pararDeDirigir()
	end
	Veiculo.destruir(quad)
end

-- O quadriciclo apareceu no Workspace: lê as peças e liga os efeitos que todo mundo vê.
local function adotar(modelo: Model)
	if quadriciclos[modelo] or preparando[modelo] or not modelo:IsDescendantOf(workspace) then
		return
	end
	preparando[modelo] = true
	local quad = Veiculo.novo(modelo) -- espera as peças chegarem (pode demorar um pouco)
	preparando[modelo] = nil
	-- Enquanto esperava, o modelo pode ter sumido, saído do Workspace ou perdido a tag.
	if quad == nil or not modelo:IsDescendantOf(workspace) or not CollectionService:HasTag(modelo, TAG_QUADRICICLO) then
		return
	end
	quadriciclos[modelo] = quad
	Nitro.criarEfeitos(quad)
	Buzina.criarEfeitos(quad)
	FreioDeMao.criarEfeitos(quad)
	Gancho.criarVisual(quad)
	Veiculo.guardarConexao(quad, quad.assento:GetPropertyChangedSignal("Occupant"):Connect(function()
		conferirMotorista(quad)
	end))
	conferirMotorista(quad) -- (você pode já estar sentado nele)
end

local function aoGanharTag(objeto: Instance)
	if not objeto:IsA("Model") or vigiados[objeto] then
		return
	end
	local modelo = objeto
	-- Um quadriciclo guardado fora do Workspace (ex.: molde no ReplicatedStorage) fica parado;
	-- quando ele vai para o Workspace, liga. Quando sai, desliga.
	vigiados[modelo] = modelo.AncestryChanged:Connect(function()
		if modelo:IsDescendantOf(workspace) then
			adotar(modelo)
		else
			esquecer(modelo)
		end
	end)
	adotar(modelo)
end

local function aoPerderTag(objeto: Instance)
	if not objeto:IsA("Model") then
		return
	end
	local conexao = vigiados[objeto]
	if conexao then
		conexao:Disconnect()
	end
	vigiados[objeto] = nil
	esquecer(objeto)
end

CollectionService:GetInstanceAddedSignal(TAG_QUADRICICLO):Connect(aoGanharTag)
CollectionService:GetInstanceRemovedSignal(TAG_QUADRICICLO):Connect(aoPerderTag)
for _, objeto in CollectionService:GetTagged(TAG_QUADRICICLO) do
	task.spawn(aoGanharTag, objeto) -- cada um no seu ritmo (um não espera o outro)
end

-- Sentou num quadriciclo sem a tag? Sem ela este script não acha o quadriciclo, então avisa no Output.
local function aoSentar(sentou: boolean, banco: BasePart?)
	if not sentou or banco == nil or not banco:IsA("VehicleSeat") then
		return
	end
	local modelo = banco.Parent
	if not (modelo and modelo:IsA("Model")) or CollectionService:HasTag(modelo, TAG_QUADRICICLO) then
		return
	end
	local pastaScripts = modelo:FindFirstChild("Scripts")
	local antigo = if pastaScripts then pastaScripts:FindFirstChild("Cliente") else nil
	local antigoLigado = antigo ~= nil and antigo:IsA("BaseScript") and antigo.Enabled
	if pastaScripts and pastaScripts:FindFirstChild("Configuracao") and not antigoLigado then
		warn(`[Quadriciclo] "{modelo:GetFullName()}" está sem a tag "{TAG_QUADRICICLO}", então ninguém controla ele.`
			.. " Confira se o script QuadricicloServidor está no ServerScriptService e o Output do servidor"
			.. " (em vermelho, ele explica o que está montado errado).")
	end
end

local function vigiarPersonagem(personagem: Model)
	local humanoide = personagem:WaitForChild("Humanoid", 10)
	if humanoide and humanoide:IsA("Humanoid") then
		humanoide.Seated:Connect(aoSentar)
	end
end
jogadorLocal.CharacterAdded:Connect(vigiarPersonagem)
local personagemAgora = jogadorLocal.Character
if personagemAgora then
	task.spawn(vigiarPersonagem, personagemAgora)
end

