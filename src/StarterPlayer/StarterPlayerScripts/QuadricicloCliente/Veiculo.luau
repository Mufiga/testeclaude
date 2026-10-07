--!strict
--[[
	=====================================================================
	Veiculo  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Veiculo
	=====================================================================

	O "quadriciclo" que todos os outros módulos recebem:
	  - as peças dele e a Configuracao DELE (cada quadriciclo tem a sua);
	  - o que está acontecendo agora (freio de mão puxado, nitro ligado...);
	  - funções que quase todo mundo usa: onde é a frente, criar um som,
	    avisar o Servidor;
	  - a física das rodas que só o motorista usa: ler as rodas, diferencial,
	    estacionar, desvirar e os avisos do DEBUG_MODE.
]]

local Veiculo = {}

-- Constantes que vários módulos usam.
Veiculo.PRIORIDADE = Enum.ContextActionPriority.High.Value -- nossos controles vêm antes dos padrões
Veiculo.PARADO = 1.5 -- (studs/s) abaixo disso o quadriciclo conta como parado

local TEMPO_ESPERA = 10 -- (s) com StreamingEnabled as peças podem demorar um pouco para chegar
local INTERVALO_AVISOS = 1.5 -- (s) tempo mínimo entre dois avisos iguais no DEBUG

-- =====================================================================
-- FORMATOS (types) que os outros módulos usam
-- =====================================================================
-- Tudo que o Cliente precisa saber de cada roda (lido quando você senta).
export type Roda = {
	nome: string,
	manga: BasePart,
	roda: BasePart,
	suspensao: SlidingBallConstraint,
	direcao: CylindricalConstraint?, -- só existe nas rodas que viram (frente)
	mola: SpringConstraint,
	motor: HingeConstraint,
	dianteira: boolean,
	tracao: boolean, -- recebe força do motor?
	raio: number, -- raio da roda física (studs)
	sinalMotor: number, -- +1 ou -1: sentido de giro que leva o quadriciclo PARA FRENTE
	sinalDirecao: number, -- +1 ou -1: sentido do servo que vira para a DIREITA
	posicao: Vector3, -- posição do eixo da roda em relação ao centro do quadriciclo
	-- Memória do modo debug:
	tempoNoBatente: number,
	tempoMotorForcado: number,
	tempoServoForcado: number,
	ultimoAviso: { [string]: number },
}

export type Quadriciclo = {
	-- PEÇAS (achadas quando o quadriciclo aparece no seu jogo)
	modelo: Model,
	pastaScripts: Instance, -- a pasta "Scripts" (Configuracao, Servidor e o RemoteEvent)
	chassi: BasePart,
	assento: VehicleSeat,
	pastaRodas: Instance,
	Config: any, -- a Configuracao DESTE quadriciclo (lida na hora em que ele aparece)

	-- EFEITOS que todo mundo vê e ouve (cada módulo coloca os seus aqui, em criarEfeitos)
	mostrarNitro: (ligado: boolean) -> (),
	tocarBuzina: (ligada: boolean) -> (),
	mostrarDerrapagem: (ligado: boolean, volume: number?) -> (),
	limpezas: { () -> () }, -- o que desfazer quando o quadriciclo some do seu jogo

	-- DIRIGINDO (só mudam enquanto VOCÊ dirige este quadriciclo)
	dirigindo: boolean, -- você está dirigindo ESTE quadriciclo agora?
	rodas: { Roda },
	pecasFisicas: { BasePart },
	zTraseiro: number, -- posição do eixo traseiro (frente = Z negativo)
	centroX: number, -- meio do quadriciclo, de lado a lado
	entreEixos: number, -- distância entre o eixo da frente e o de trás
	tela: ScreenGui?, -- o seu HUDQuadriciclo (velocímetro, menu "Controles", barra do nitro)
	nitroPedido: boolean, -- Shift (ou botão do nitro) apertado agora
	nitroAtivo: boolean, -- nitro funcionando de verdade (decidido no "atualizar")
	freioDeMao: boolean, -- Espaço (ou botão do freio de mão) apertado agora
	buzinaLigada: boolean,
	mirandoGancho: boolean, -- Q apertado: mirando (o gancho sai quando você SOLTA o Q)
	modoCamera: number, -- 1 = padrão · 2 = afastada · 3 = capô

	-- MEMÓRIA deste quadriciclo neste computador (continua quando você sai e volta)
	tombadoHaQuanto: number, -- (s) há quanto tempo está tombado
	ultimoDesvirar: number,
	cargaNitro: number, -- tanque do nitro: 0 = vazio, 1 = cheio (enche mesmo parado)
	nitroTravado: boolean, -- o tanque esvaziou: só volta depois de soltar o Shift
	relogioNitro: number,
	extraLadeira: number, -- (studs/s) velocidade extra ganha na descida
}

-- =====================================================================
-- ACHAR AS PEÇAS
-- =====================================================================
local function nadaAFazer() end

-- Lê as peças e a Configuracao de um quadriciclo. Devolve nil (com um aviso) se faltar algo.
-- Pode demorar: espera as peças chegarem (StreamingEnabled).
function Veiculo.novo(modelo: Model): Quadriciclo?
	local chassi = modelo:WaitForChild("Chassi", TEMPO_ESPERA)
	local assento = modelo:WaitForChild("Banco", TEMPO_ESPERA)
	local pastaRodas = modelo:WaitForChild("Rodas", TEMPO_ESPERA)
	local pastaScripts = modelo:WaitForChild("Scripts", TEMPO_ESPERA)
	local moduloConfig = if pastaScripts then pastaScripts:WaitForChild("Configuracao", TEMPO_ESPERA) else nil
	if
		not (chassi and chassi:IsA("BasePart"))
		or not (assento and assento:IsA("VehicleSeat"))
		or pastaRodas == nil
		or pastaScripts == nil
		or not (moduloConfig and moduloConfig:IsA("ModuleScript"))
	then
		warn(`[Quadriciclo] "{modelo:GetFullName()}" precisa ter Chassi, Banco (VehicleSeat), Rodas e Scripts > Configuracao. Ignorei ele.`)
		return nil
	end

	-- O script "Cliente" antigo (o que ficava dentro de cada quadriciclo) ainda está aqui?
	-- Os dois juntos brigariam pelos controles. Então este fica com o antigo até você apagar ele.
	local antigo = pastaScripts:FindFirstChild("Cliente")
	if antigo and antigo:IsA("BaseScript") and antigo.Enabled then
		warn(`[Quadriciclo] Apague o script "Cliente" de dentro de "{modelo:GetFullName()}". Agora quem controla`
			.. " os quadriciclos é o QuadricicloCliente (StarterPlayerScripts). Enquanto ele existir, este quadriciclo usa o antigo.")
		return nil
	end

	-- pcall: um erro na Configuracao avisa no Output em vez de parar o script inteiro.
	local carregou, Config = pcall(require, moduloConfig)
	if not carregou then
		warn(`[Quadriciclo] A Configuracao de "{modelo:GetFullName()}" deu erro: {Config}`)
		return nil
	end

	return {
		modelo = modelo,
		pastaScripts = pastaScripts,
		chassi = chassi,
		assento = assento,
		pastaRodas = pastaRodas,
		Config = Config,

		mostrarNitro = nadaAFazer,
		tocarBuzina = nadaAFazer,
		mostrarDerrapagem = nadaAFazer,
		limpezas = {},

		dirigindo = false,
		rodas = {},
		pecasFisicas = {},
		zTraseiro = 0,
		centroX = 0,
		entreEixos = 0,
		tela = nil,
		nitroPedido = false,
		nitroAtivo = false,
		freioDeMao = false,
		buzinaLigada = false,
		mirandoGancho = false,
		modoCamera = 1,

		tombadoHaQuanto = 0,
		ultimoDesvirar = 0,
		cargaNitro = 1,
		nitroTravado = false,
		relogioNitro = os.clock(),
		extraLadeira = 0,
	}
end

-- Guarda uma peça criada por um módulo: ela some junto quando o quadriciclo sai do seu jogo.
function Veiculo.guardar(quad: Quadriciclo, objeto: Instance)
	table.insert(quad.limpezas, function()
		objeto:Destroy()
	end)
end

-- Guarda uma conexão: ela é desligada quando o quadriciclo sai do seu jogo.
function Veiculo.guardarConexao(quad: Quadriciclo, conexao: RBXScriptConnection)
	table.insert(quad.limpezas, function()
		conexao:Disconnect()
	end)
end

-- O quadriciclo saiu do seu jogo (foi apagado, saiu do Workspace ou o StreamingEnabled tirou ele).
function Veiculo.destruir(quad: Quadriciclo)
	for _, desfazer in quad.limpezas do
		desfazer()
	end
	table.clear(quad.limpezas)
end

-- =====================================================================
-- FUNÇÕES QUE TODO MÓDULO USA
-- =====================================================================
-- Sistema de coordenadas do veículo: centro no Chassi, orientação do Banco
-- (LookVector = frente, RightVector = direita, UpVector = cima).
function Veiculo.referencia(quad: Quadriciclo): CFrame
	return CFrame.new(quad.chassi.Position) * quad.assento.CFrame.Rotation
end

-- Cada jogador cria os seus sons, dentro do Chassi.
function Veiculo.criarSom(quad: Quadriciclo, nome: string, id: string, repetir: boolean): Sound
	local som = Instance.new("Sound")
	som.Name = nome
	som.SoundId = id
	som.Looped = repetir
	som.Volume = 0.8
	som.RollOffMaxDistance = 150 -- (studs) mais longe que isso, ninguém ouve
	som.Parent = quad.chassi
	Veiculo.guardar(quad, som)
	return som
end

-- Manda uma ação pelo RemoteEvent "AcaoQuadriciclo" deste quadriciclo.
-- O Servidor confere se você é o motorista e repassa para os outros jogadores.
function Veiculo.avisarServidor(quad: Quadriciclo, acao: string, ...: any)
	local evento = quad.pastaScripts:FindFirstChild("AcaoQuadriciclo")
	if evento and evento:IsA("RemoteEvent") then
		evento:FireServer(acao, ...)
	end
end

-- A câmera do jogador. O Studio trata CurrentCamera como "talvez nil"; no jogo ela sempre existe.
function Veiculo.cameraAtual(): Camera
	return workspace.CurrentCamera :: Camera
end

-- Botão apertado (ou analógico mexendo) agora?
function Veiculo.segurando(estado: Enum.UserInputState): boolean
	return estado == Enum.UserInputState.Begin or estado == Enum.UserInputState.Change
end

-- =====================================================================
-- RODAS (lidas toda vez que você senta)
-- =====================================================================
-- Qual roda recebe força do motor, de acordo com Config.DriveMode.
local function temTracao(quad: Quadriciclo, dianteira: boolean): boolean
	if quad.Config.DriveMode == "Traseira" then
		return not dianteira
	elseif quad.Config.DriveMode == "Dianteira" then
		return dianteira
	end
	return true -- "4x4"
end

-- Lê as pastas de rodas e calcula tudo que não muda enquanto dirige.
function Veiculo.prepararRodas(quad: Quadriciclo): boolean
	local rodas, pecasFisicas = quad.rodas, quad.pecasFisicas
	table.clear(rodas)
	table.clear(pecasFisicas)
	table.insert(pecasFisicas, quad.chassi)

	local referencia = Veiculo.referencia(quad)
	local direita = referencia.RightVector
	local cima = referencia.UpVector

	for _, pasta in quad.pastaRodas:GetChildren() do
		local manga = pasta:FindFirstChild("Manga")
		local roda = pasta:FindFirstChild("Roda")
		local suspensao = pasta:FindFirstChild("Suspensao")
		local mola = pasta:FindFirstChild("Mola")
		local motor = pasta:FindFirstChild("Motor")
		if
			not (manga and manga:IsA("BasePart"))
			or not (roda and roda:IsA("BasePart"))
			or not (suspensao and suspensao:IsA("SlidingBallConstraint"))
			or not (mola and mola:IsA("SpringConstraint"))
			or not (motor and motor:IsA("HingeConstraint"))
		then
			continue -- pasta incompleta (o Servidor já avisa no Output)
		end

		local eixoMotor = motor.Attachment0
		local eixoSuspensao = suspensao.Attachment0
		if eixoMotor == nil or eixoSuspensao == nil then
			continue
		end

		local sinalMotor = if eixoMotor.WorldAxis:Dot(direita) < 0 then 1 else -1
		if eixoMotor.Parent == roda then
			sinalMotor = -sinalMotor
		end

		local direcao: CylindricalConstraint? = if suspensao:IsA("CylindricalConstraint") then suspensao else nil
		local sinalDirecao = if eixoSuspensao.WorldAxis:Dot(cima) < 0 then 1 else -1
		if eixoSuspensao.Parent == manga then
			sinalDirecao = -sinalDirecao -- Attachment0 na Manga (montado ao contrário)
		end

		local posicao = referencia:PointToObjectSpace(eixoMotor.WorldPosition)
		local dianteira = posicao.Z < 0 -- no Roblox, a frente é o Z negativo

		local info: Roda = {
			nome = pasta.Name,
			manga = manga,
			roda = roda,
			suspensao = suspensao,
			direcao = direcao,
			mola = mola,
			motor = motor,
			dianteira = dianteira,
			tracao = temTracao(quad, dianteira),
			raio = math.max(math.min(roda.Size.Y, roda.Size.Z) / 2, 0.1),
			sinalMotor = sinalMotor,
			sinalDirecao = sinalDirecao,
			posicao = posicao,
			tempoNoBatente = 0,
			tempoMotorForcado = 0,
			tempoServoForcado = 0,
			ultimoAviso = {},
		}
		table.insert(rodas, info)
		table.insert(pecasFisicas, manga)
		table.insert(pecasFisicas, roda)
	end

	if #rodas == 0 then
		warn("[Quadriciclo] Nenhuma roda válida encontrada na pasta Rodas.")
		return false
	end

	local somaZFrente, quantasFrente = 0, 0
	local somaZTras, quantasTras = 0, 0
	local somaX = 0
	for _, info in rodas do
		somaX += info.posicao.X
		if info.dianteira then
			somaZFrente += info.posicao.Z
			quantasFrente += 1
		else
			somaZTras += info.posicao.Z
			quantasTras += 1
		end
	end
	quad.centroX = somaX / #rodas
	if quantasFrente > 0 and quantasTras > 0 then
		quad.zTraseiro = somaZTras / quantasTras
		quad.entreEixos = quad.zTraseiro - somaZFrente / quantasFrente
	else
		quad.entreEixos = 0 -- sem eixo dianteiro e traseiro não dá para calcular: desliga o diferencial
	end
	return true
end

-- =====================================================================
-- DIFERENCIAL: na curva, a roda de fora anda mais que a de dentro
-- =====================================================================
function Veiculo.anguloDaDirecao(quad: Quadriciclo): number
	local soma, quantas = 0, 0
	for _, info in quad.rodas do
		local direcao = info.direcao
		if direcao then
			soma += direcao.CurrentAngle * info.sinalDirecao
			quantas += 1
		end
	end
	return if quantas > 0 then soma / quantas else 0
end

function Veiculo.fatorDiferencial(quad: Quadriciclo, info: Roda, anguloGraus: number): number
	if quad.entreEixos < 0.5 or math.abs(anguloGraus) < 0.5 then
		return 1 -- reta: todas iguais
	end
	local raioCurva = quad.entreEixos / math.tan(math.rad(math.abs(anguloGraus))) -- raio no meio do eixo traseiro
	local lado = if anguloGraus > 0 then 1 else -1 -- +1 = curva para a direita
	local centroDaCurvaX = quad.centroX + lado * raioCurva
	local dx = info.posicao.X - centroDaCurvaX
	local dz = info.posicao.Z - quad.zTraseiro
	return math.sqrt(dx * dx + dz * dz) / raioCurva
end

-- Deixa as rodas seguras e o guidão reto (igual ao "estacionar" do Servidor).
function Veiculo.estacionar(quad: Quadriciclo)
	for _, info in quad.rodas do
		info.motor.AngularVelocity = 0
		info.motor.MotorMaxTorque = quad.Config.MaxTorque
		local direcao = info.direcao
		if direcao then
			direcao.TargetAngle = 0
		end
	end
end

-- =====================================================================
-- DESVIRAR: só depois de Config.TempoParaDesvirar segundos SEGUIDOS tombado
-- =====================================================================
-- Chamado a cada frame pelo "atualizar": de cabeça para baixo ou de lado (mais de 60°) conta tempo.
function Veiculo.acompanharTombado(quad: Quadriciclo, dt: number)
	quad.tombadoHaQuanto = if Veiculo.referencia(quad).UpVector.Y <= 0.5 then quad.tombadoHaQuanto + dt else 0
end

-- Se o quadriciclo tombou, levanta ele 4 studs e coloca em pé (tecla R ou o BotaoDesvirar do HUD).
function Veiculo.desvirar(quad: Quadriciclo)
	local agora = os.clock()
	local referencia = Veiculo.referencia(quad)
	if agora - quad.ultimoDesvirar < 2 or referencia.UpVector.Y > 0.5 or quad.tombadoHaQuanto < quad.Config.TempoParaDesvirar then
		return -- acabou de desvirar, está de pé, ou ainda não deu o tempo
	end
	quad.ultimoDesvirar = agora
	quad.tombadoHaQuanto = 0

	-- Nova orientação: em pé, olhando para a mesma direção (só no plano do chão).
	local frente = Vector3.new(referencia.LookVector.X, 0, referencia.LookVector.Z)
	if frente.Magnitude < 0.1 then
		frente = Vector3.new(0, 0, -1)
	end
	local chassi = quad.chassi
	local novaPosicao = chassi.Position + Vector3.new(0, 4, 0)
	local novaReferencia = CFrame.lookAt(novaPosicao, novaPosicao + frente.Unit)

	-- Chassi na nova posição (mantendo o giro dele em relação ao Banco)...
	local novoChassi = novaReferencia * referencia:ToObjectSpace(chassi.CFrame)
	-- ...e o modelo inteiro vai junto, sem desmontar as constraints.
	quad.modelo:PivotTo(novoChassi * chassi.CFrame:ToObjectSpace(quad.modelo:GetPivot()))

	-- Zera as velocidades para não sair voando.
	for _, parte in quad.pecasFisicas do
		parte.AssemblyLinearVelocity = Vector3.zero
		parte.AssemblyAngularVelocity = Vector3.zero
	end
end

-- =====================================================================
-- MODO DEBUG: avisos de física no Output
-- =====================================================================
local function avisar(info: Roda, tipo: string, mensagem: string)
	local agora = os.clock()
	local ultimo = info.ultimoAviso[tipo]
	if ultimo == nil or agora - ultimo > INTERVALO_AVISOS then
		info.ultimoAviso[tipo] = agora
		warn(`[Quadriciclo DEBUG] {info.nome}: {mensagem}`)
	end
end

function Veiculo.verificarFisica(info: Roda, dt: number)
	local mola = info.mola
	if mola.CurrentLength <= mola.MinLength + 0.03 then
		info.tempoNoBatente += dt
		avisar(info, "batente", `a mola chegou na compressão máxima ({string.format("%.2f", mola.CurrentLength)} studs).`)
		if info.tempoNoBatente > 1 then
			avisar(info, "apoiada", "a mola está no batente há mais de 1 s: aumente SpringStiffness ou SpringFreeLength.")
		end
	else
		info.tempoNoBatente = 0
	end

	local a0, a1 = info.motor.Attachment0, info.motor.Attachment1
	if a0 and a1 then
		local separacao = (a0.WorldPosition - a1.WorldPosition).Magnitude
		if separacao > 0.3 then
			avisar(info, "junta", `a HingeConstraint está sendo esticada ({string.format("%.2f", separacao)} studs): força excessiva! Confira Collision Groups e massas.`)
		end
	end

	if a0 and info.motor.MotorMaxTorque > 0 then
		local giroReal = (info.roda.AssemblyAngularVelocity - info.manga.AssemblyAngularVelocity):Dot(a0.WorldAxis)
		if a0.Parent == info.roda then
			giroReal = -giroReal -- montado ao contrário (Attachment0 na Roda)
		end
		if math.abs(info.motor.AngularVelocity - giroReal) > 2.5 then
			info.tempoMotorForcado += dt
			if info.tempoMotorForcado > 0.75 then
				avisar(info, "torque", "o motor está no torque máximo sem conseguir girar a roda (roda presa, subida íngreme ou MaxTorque baixo).")
			end
		else
			info.tempoMotorForcado = 0
		end
	end

	local s0, s1 = info.suspensao.Attachment0, info.suspensao.Attachment1
	if s0 and s1 then
		local distancia = s1.WorldPosition - s0.WorldPosition
		local eixo = s0.WorldAxis
		local desvioLateral = (distancia - eixo * distancia:Dot(eixo)).Magnitude
		if desvioLateral > 0.3 then
			avisar(info, "trilho", `a suspensão está sendo empurrada para o lado ({string.format("%.2f", desvioLateral)} studs): força excessiva.`)
		end
	end

	local direcao = info.direcao
	if direcao then
		if math.abs(direcao.TargetAngle - direcao.CurrentAngle) > 8 then
			info.tempoServoForcado += dt
			if info.tempoServoForcado > 0.5 then
				avisar(info, "servo", "a direção não alcança o ângulo pedido: aumente SteerTorque.")
			end
		else
			info.tempoServoForcado = 0
		end
	end
end

return Veiculo

