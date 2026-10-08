--!strict
--[[
	=====================================================================
	Sensacao  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Sensacao
	       (DENTRO do QuadricicloCliente, junto com Veiculo, Camera, Gancho...)
	=====================================================================

	Deixa dirigir mais GOSTOSO sem mudar o jeito de dirigir. É tudo "enfeite" em cima do que já existe:
	  MOLAS ..... balançam um pouquinho mais ("boing") depois de buracos, freadas e pulos.
	  PESO ...... acelerando, a frente sobe; freando, ela abaixa; na curva, ele deita para fora (nas molas).
	  CÂMERA .... inclina um pouquinho para dentro da curva.
	  MARCAS .... derrapando, freando forte ou numa curva forte, os pneus deixam marcas escuras no chão.
	  POUSO ..... caiu de um pulo? Um tranco na tela.
	(A POEIRA e os pedaços do chão que as rodas jogam ficam no módulo PoeiraDoChao, com a cor do chão.)

	Cada efeito tem um liga/desliga em AJUSTES (logo abaixo): dá para testar um de cada vez.
	O QuadricicloCliente só precisa chamar Sensacao.atualizar(quad, dt) a cada frame.
	Saiu do banco? Tudo desliga sozinho e as molas voltam a ser como eram.
	Tudo acontece só no seu computador (quem dirige é quem calcula a física do quadriciclo).
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Veiculo = require(script.Parent:WaitForChild("Veiculo")) -- (a "frente" e o "cima" do quadriciclo)
local CameraModulo = require(script.Parent:WaitForChild("Camera")) -- (o tranco na tela: Camera.tremer)

local Sensacao = {}

-- =====================================================================
-- AJUSTES (true = ligado · false = desligado)
-- =====================================================================
local MOLAS_LIGADAS = true
local MOLA_BALANCO = 0.45 -- quanto as molas balançam: 1 = nada · 0.45 = um "boing" · 0.25 = gelatina

local PESO_LIGADO = true
local PESO_FRENTE = 1.5 -- acelerando a frente sobe, freando ela abaixa (0 = desliga · 2.5 = bastante)
local PESO_CURVA = 1 -- na curva ele deita para fora (0 = desliga · 2 = bastante)
local PESO_LIMITE = 70 -- (studs/s²) trancos maiores que isso (batidas) contam só como este tanto

local CAMERA_LIGADA = true
local CAMERA_INCLINACAO = 3 -- (graus) o máximo que a câmera inclina para dentro da curva

local MARCAS_LIGADAS = true
local MARCAS_DURACAO = 3 -- (s) quanto tempo a marca fica no chão
local MARCAS_DE_LADO = 9 -- (studs/s) a roda escorregando de lado mais rápido que isso deixa marca
local MARCAS_GIRANDO = 14 -- (studs/s) a roda patinando (ou travada) mais que isso deixa marca

local POUSO_LIGADO = true

-- =====================================================================
-- O QUE O MÓDULO GUARDA
-- =====================================================================
type Roda = {
	roda: BasePart, -- a roda (ela gira)
	raio: number, -- o raio da roda
	eixo: Attachment?, -- o Attachment do motor da roda (o eixo X dele = para onde aponta o eixo da roda)
	marca: Trail, -- a marca do pneu no chão
	tocando: boolean, -- a roda está encostando no chão agora?
	marcando: boolean, -- está deixando marca agora?
}

type Mola = {
	mola: SpringConstraint,
	amortecimento: number, -- o amortecimento ORIGINAL (para voltar ao normal no fim)
}

type Estado = {
	quad: any, -- o quadriciclo que está sendo dirigido
	chassi: BasePart,
	rodas: { Roda },
	molas: { Mola },
	criados: { Instance }, -- tudo que este módulo criou (para apagar no fim)
	torque: Torque?, -- a força que faz o "peso" (deitar, empinar, abaixar)
	filtro: RaycastParams, -- (os raios que procuram o chão ignoram o quadriciclo e o seu boneco)
	velocidadeAntes: Vector3, -- a velocidade no frame passado (para medir a aceleração)
	aceleracao: Vector3, -- a aceleração medida (suavizada, para não tremer)
	tempoNoAr: number, -- (s) há quanto tempo nenhuma roda encosta no chão
	quedaAntes: number, -- (studs/s) a velocidade de queda no último frame no ar
}

local estado: Estado? = nil -- nil = ninguém dirigindo agora
local ligarCamera: () -> () -- (a função vem lá embaixo, junto com a câmera; aqui só avisamos que ela existe)
local ultimaAtualizacao = 0 -- (os.clock) a última vez que o QuadricicloCliente chamou o atualizar
local aceleracaoNaCurva = Vector3.zero -- a aceleração "deitada" (a câmera usa para inclinar)
local inclinacaoCamera = 0 -- (radianos) quanto a câmera está inclinada agora
local modoCameraCapo = false -- true = câmera no capô (modo 3): aí a câmera não inclina

-- =====================================================================
-- PREPARAR (quando começa a dirigir)
-- =====================================================================

-- Devolve o valor como uma Instance (ou nil, se ele não for uma).
local function comoInstancia(valor: any): Instance?
	return if typeof(valor) == "Instance" then (valor :: Instance) else nil
end

-- Acha a peça que NÃO gira junto com a roda (a "manga", onde o motor da roda está preso).
-- A marca fica presa nela: assim acompanha a roda (a mola e a direção) sem girar junto.
local function pecaQueNaoGira(roda: BasePart, motor: any, chassi: BasePart): (BasePart, Attachment?)
	local dobradica = comoInstancia(motor) -- (o motor da roda é uma HingeConstraint)
	if dobradica and dobradica:IsA("HingeConstraint") then
		for _, anexo in { dobradica.Attachment0, dobradica.Attachment1 } do
			local pai = if anexo then anexo.Parent else nil
			if anexo and pai and pai ~= roda and pai:IsA("BasePart") then
				return pai, anexo
			end
		end
	end
	return chassi, nil -- (não achou: usa o Chassi mesmo)
end

-- Cria a marca do pneu de UMA roda.
local function prepararRoda(info: any, chassi: BasePart, referencia: CFrame, criados: { Instance }): Roda?
	local roda = comoInstancia(info.roda)
	if roda == nil or not roda:IsA("BasePart") then
		return nil
	end
	local raio: number = if typeof(info.raio) == "number" then info.raio else roda.Size.Y / 2
	local base, eixo = pecaQueNaoGira(roda, info.motor, chassi)
	local cima = referencia.UpVector
	local lado = if eixo then eixo.WorldAxis else referencia.RightVector -- a direção do eixo da roda
	local frente = lado:Cross(cima) -- a direção em que a roda rola
	frente = if frente.Magnitude > 0.01 then frente.Unit else referencia.LookVector
	local ponto = roda.Position - cima * (raio - 0.06) -- onde o pneu encosta no chão (um tiquinho acima)
	local meiaLargura = math.min(roda.Size.X, roda.Size.Y, roda.Size.Z) * 0.4 -- metade da largura da marca

	-- Um ponto (Attachment) preso na peça que não gira, virado para "frente" e com o "cima" do quadriciclo.
	local function pontoNaBase(posicao: Vector3, nome: string): Attachment
		local anexo = Instance.new("Attachment")
		anexo.Name = nome
		anexo.Parent = base
		anexo.WorldCFrame = CFrame.lookAt(posicao, posicao + frente, cima)
		table.insert(criados, anexo)
		return anexo
	end
	local beiradaA = pontoNaBase(ponto + lado * meiaLargura, "SensacaoMarcaA") -- as 2 beiradas da marca
	local beiradaB = pontoNaBase(ponto - lado * meiaLargura, "SensacaoMarcaB")

	-- A MARCA DO PNEU: uma fita escura deitada no chão, que vai sumindo.
	local marca = Instance.new("Trail")
	marca.Name = "SensacaoMarca"
	marca.Attachment0 = beiradaA
	marca.Attachment1 = beiradaB
	marca.FaceCamera = false -- deitada no chão (não vira para a câmera)
	marca.Lifetime = MARCAS_DURACAO
	marca.MinLength = 0.2
	marca.Color = ColorSequence.new(Color3.fromRGB(25, 25, 28)) -- borracha queimada
	marca.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3), -- (0 = a parte nova, perto do pneu)
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1), -- (1 = a parte velha: some)
	})
	marca.LightInfluence = 1
	marca.Enabled = false -- (só liga quando a roda escorrega)
	marca.Parent = base
	table.insert(criados, marca)

	return {
		roda = roda,
		raio = raio,
		eixo = eixo,
		marca = marca,
		tocando = false,
		marcando = false,
	}
end

-- MOLAS MAIS VIVAS: deixa o amortecimento de cada mola no ponto do "boing" (MOLA_BALANCO).
-- Só deixa MAIS solta: se a mola já balança mais que isso, não mexe. Guarda o valor original.
local function prepararMolas(quad: any, chassi: BasePart, lista: { Mola })
	local molas: { SpringConstraint } = {}
	for _, objeto in (quad.modelo :: Instance):GetDescendants() do
		if objeto:IsA("SpringConstraint") then
			table.insert(molas, objeto)
		end
	end
	if #molas == 0 then
		return
	end
	local pesoPorMola = chassi.AssemblyMass / #molas -- o peso que cada mola segura
	local antes, depois = 0, 0
	for _, mola in molas do
		table.insert(lista, { mola = mola, amortecimento = mola.Damping })
		-- "critico" = o amortecimento em que a mola para sem balançar nada (depende da força dela e do peso)
		local critico = 2 * math.sqrt(math.max(mola.Stiffness, 0) * pesoPorMola)
		if critico > 0 then
			antes = mola.Damping / critico
			mola.Damping = math.min(mola.Damping, MOLA_BALANCO * critico)
			depois = mola.Damping / critico
		end
	end
	if quad.Config and quad.Config.DEBUG_MODE then -- (só no modo DEBUG, para não encher o Output)
		print(string.format("[Sensacao] %d molas · balanço (1 = nada) antes %.2f, agora %.2f", #molas, antes, depois))
	end
end

-- Começou a dirigir: prepara as rodas, as molas e a força do "peso".
local function ligar(quad: any): Estado?
	local chassi = comoInstancia(quad.chassi)
	if chassi == nil or not chassi:IsA("BasePart") then
		return nil
	end
	local referencia: CFrame = Veiculo.referencia(quad)
	local criados: { Instance } = {}
	local rodas: { Roda } = {}
	if typeof(quad.rodas) == "table" then
		for _, info in quad.rodas do
			local roda = prepararRoda(info, chassi, referencia, criados)
			if roda then
				table.insert(rodas, roda)
			end
		end
	end
	local molas: { Mola } = {}
	if MOLAS_LIGADAS then
		prepararMolas(quad, chassi, molas)
	end
	-- O PESO: uma força de girar (Torque) no Chassi. Ela é calculada a cada frame no atualizar.
	local torque: Torque? = nil
	if PESO_LIGADO then
		local anexo = Instance.new("Attachment")
		anexo.Name = "SensacaoPeso"
		anexo.Parent = chassi
		table.insert(criados, anexo)
		local novo = Instance.new("Torque")
		novo.Name = "SensacaoPeso"
		novo.Attachment0 = anexo
		novo.RelativeTo = Enum.ActuatorRelativeTo.World -- (a direção é a do mundo)
		novo.Torque = Vector3.zero
		novo.Parent = chassi
		table.insert(criados, novo)
		torque = novo
	end
	-- Os raios que procuram o chão ignoram o próprio quadriciclo e o seu boneco.
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar: { Instance } = { quad.modelo }
	local jogador = Players.LocalPlayer -- (você)
	local personagem = if jogador then jogador.Character else nil -- (o seu boneco, se ele existir)
	if personagem then
		table.insert(ignorar, personagem)
	end
	filtro.FilterDescendantsInstances = ignorar
	return {
		quad = quad,
		chassi = chassi,
		rodas = rodas,
		molas = molas,
		criados = criados,
		torque = torque,
		filtro = filtro,
		velocidadeAntes = chassi.AssemblyLinearVelocity,
		aceleracao = Vector3.zero,
		tempoNoAr = 0,
		quedaAntes = 0,
	}
end

-- Parou de dirigir: as molas voltam ao normal, o "peso" desliga e as marcas somem sozinhas.
local function desligar()
	local atual = estado
	estado = nil
	aceleracaoNaCurva = Vector3.zero
	if atual == nil then
		return
	end
	for _, item in atual.molas do
		item.mola.Damping = item.amortecimento -- a mola volta a ser como era
	end
	local torque = atual.torque
	if torque then
		torque.Enabled = false
	end
	for _, roda in atual.rodas do
		roda.marca.Enabled = false -- (a marca que já está no chão some sozinha)
	end
	-- Espera as marcas sumirem e apaga tudo que o módulo criou.
	local criados = atual.criados
	task.delay(MARCAS_DURACAO + 0.5, function()
		for _, objeto in criados do
			objeto:Destroy()
		end
	end)
end

-- =====================================================================
-- A CADA FRAME (o QuadricicloCliente chama isto enquanto você dirige)
-- =====================================================================
function Sensacao.atualizar(quad: any, dt: number)
	ultimaAtualizacao = os.clock()
	modoCameraCapo = quad.modoCamera == 3
	-- Trocou de quadriciclo (ou ele sumiu)? Desliga o velho e prepara o novo.
	local velho = estado
	if velho and (velho.quad ~= quad or velho.chassi.Parent == nil) then
		desligar()
	end
	if estado == nil then
		estado = ligar(quad)
		if estado then
			ligarCamera() -- (a inclinação da câmera só roda enquanto alguém dirige)
		end
	end
	local agora = estado
	if agora == nil then
		return
	end
	local chassi = agora.chassi
	local referencia: CFrame = Veiculo.referencia(quad)
	local cima = referencia.UpVector
	local passo = math.max(dt, 1 / 240)

	-- 1) QUAIS RODAS ESTÃO NO CHÃO? (um raio curto para "baixo", saindo do meio de cada roda)
	local rodasNoChao = 0
	local normalDoChao = Vector3.zero -- (para saber se o chão está inclinado)
	for _, roda in agora.rodas do
		local acerto = workspace:Raycast(roda.roda.Position, -cima * (roda.raio + 0.7), agora.filtro)
		roda.tocando = acerto ~= nil
		if acerto then
			rodasNoChao += 1
			normalDoChao += acerto.Normal
		end
	end

	-- 2) A ACELERAÇÃO: quanto a velocidade mudou desde o frame passado (suavizada, para não tremer).
	local velocidade = chassi.AssemblyLinearVelocity
	local bruta = (velocidade - agora.velocidadeAntes) / passo
	agora.velocidadeAntes = velocidade
	if bruta.Magnitude > PESO_LIMITE * 4 then
		bruta = bruta.Unit * PESO_LIMITE * 4 -- (batida forte: não exagera)
	end
	agora.aceleracao = agora.aceleracao:Lerp(bruta, math.min(dt * 10, 1))
	-- Só a parte "deitada" (frente/trás e lados): a de subir e descer não conta.
	local deitada = agora.aceleracao - cima * agora.aceleracao:Dot(cima)
	if deitada.Magnitude > PESO_LIMITE then
		deitada = deitada.Unit * PESO_LIMITE
	end
	aceleracaoNaCurva = if rodasNoChao >= 3 then deitada else Vector3.zero

	-- 3) O PESO: é como se o centro de peso do quadriciclo fosse mais alto. Acelerando, a frente sobe;
	--    freando, ela abaixa; na curva, ele deita para fora. Quem segura são as molas (por isso balança).
	local torque = agora.torque
	if torque then
		local fator = 0
		if rodasNoChao >= 3 and cima.Y > 0.5 then -- (no chão e de pé: nada de girar no ar ou na parede)
			-- Já está bem deitado em relação ao chão (> uns 10°)? Vai soltando: assim ele não capota.
			local alinhado = cima:Dot(normalDoChao.Unit) -- 1 = reto em relação ao chão
			fator = math.clamp((alinhado - 0.94) / 0.045, 0, 1)
		end
		local frenteTras = referencia.LookVector * deitada:Dot(referencia.LookVector)
		local deLado = referencia.RightVector * deitada:Dot(referencia.RightVector)
		local girar = (frenteTras * PESO_FRENTE + deLado * PESO_CURVA):Cross(cima)
		torque.Torque = girar * (chassi.AssemblyMass * fator)
	end

	-- 4) AS RODAS: escorregando de lado ou patinando? Marca no chão.
	for _, roda in agora.rodas do
		local escorrega = 0 -- (studs/s) quão rápido o pneu escorrega de lado
		local patina = 0 -- (studs/s) quanto o pneu gira diferente do chão (patinando ou travado)
		if roda.tocando then
			local eixo = roda.eixo
			local lado = if eixo then eixo.WorldAxis else referencia.RightVector
			local rolar = lado:Cross(cima) -- a direção em que a roda rola
			local vel = roda.roda.AssemblyLinearVelocity
			escorrega = math.abs(vel:Dot(lado))
			if rolar.Magnitude > 0.01 then
				local pneu = math.abs(roda.roda.AssemblyAngularVelocity:Dot(lado)) * roda.raio -- a "velocidade" do pneu
				patina = math.abs(pneu - math.abs(vel:Dot(rolar.Unit)))
			end
		end
		-- MARCA: liga acima do limite e só desliga bem abaixo dele (assim não fica piscando).
		local folga = if roda.marcando then 0.65 else 1
		local marcar = MARCAS_LIGADAS
			and roda.tocando
			and (escorrega > MARCAS_DE_LADO * folga or patina > MARCAS_GIRANDO * folga)
		if marcar ~= roda.marcando then
			roda.marcando = marcar
			roda.marca.Enabled = marcar
		end
	end

	-- 5) O POUSO: estava no ar e uma roda encostou? Tranco na tela (mais forte se caiu rápido).
	--    (O "puf" de poeira de cada roda é do módulo PoeiraDoChao.)
	if rodasNoChao == 0 then
		agora.tempoNoAr += dt
		agora.quedaAntes = velocidade.Y
	else
		if POUSO_LIGADO and agora.tempoNoAr > 0.35 then
			local queda = -agora.quedaAntes -- (studs/s) quão rápido estava caindo
			if queda > 15 then
				CameraModulo.tremer(math.clamp(queda / 250, 0.05, 0.3))
			end
		end
		agora.tempoNoAr = 0
	end
end

-- =====================================================================
-- A CÂMERA (roda todo frame, depois de todas as câmeras): inclina para dentro da curva.
-- Só fica ligada enquanto alguém dirige (e até a câmera voltar ao normal depois).
-- =====================================================================
local CAMERA_DA_SENSACAO = "SensacaoCamera" -- nome da tarefa (BindToRenderStep)
local cameraRodando = false

local function passoDaCamera(dt: number)
	if estado and os.clock() - ultimaAtualizacao > 1 then
		desligar() -- (rede de segurança: 1 s sem ser chamado = saiu do banco)
	end
	local camera = workspace.CurrentCamera
	if camera == nil then
		return -- (ainda não tem câmera: tenta de novo no próximo frame)
	end
	local alvo = 0
	if CAMERA_LIGADA and estado and not modoCameraCapo then
		-- Para que lado da TELA ele está sendo "jogado" na curva (negativo = curva para a esquerda)
		local deLado = aceleracaoNaCurva:Dot(camera.CFrame.RightVector)
		alvo = math.clamp(-deLado / 60, -1, 1) * math.rad(CAMERA_INCLINACAO)
	end
	inclinacaoCamera += (alvo - inclinacaoCamera) * math.min(dt * 4, 1) -- vai e volta suave
	if math.abs(inclinacaoCamera) > 0.0005 then
		camera.CFrame *= CFrame.Angles(0, 0, inclinacaoCamera) -- gira a câmera em volta de onde ela olha
	elseif estado == nil then
		-- Ninguém dirigindo e a câmera já voltou ao normal: para de rodar a cada frame.
		inclinacaoCamera = 0
		cameraRodando = false
		RunService:UnbindFromRenderStep(CAMERA_DA_SENSACAO)
	end
end

ligarCamera = function()
	if not cameraRodando then
		cameraRodando = true
		RunService:BindToRenderStep(CAMERA_DA_SENSACAO, Enum.RenderPriority.Last.Value, passoDaCamera)
	end
end

-- Parou de dirigir (o QuadricicloCliente chama): desliga tudo NA HORA.
function Sensacao.desligar()
	desligar()
end

return Sensacao

