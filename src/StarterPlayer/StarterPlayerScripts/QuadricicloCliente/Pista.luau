--!strict
--[[
	=====================================================================
	Pista  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Pista
	       (DENTRO do QuadricicloCliente, junto com Veiculo, Camera, Monstro...)
	=====================================================================

	Deixa o CAMINHÃO MONSTRO mais divertido com o chão e com as pistas:
	  LOOPS E TUBOS ... nas peças com a tag "Pista360" ele GRUDA: a pista vira o "chão" (sobe na parede,
	                    dá a volta no tubo e passa de cabeça para baixo no loop). Mas de cabeça para
	                    baixo precisa de VELOCIDADE: devagar demais, ele despenca!
	  360! ............ deu uma volta inteira grudado na pista? "360!" + turbo (2 voltas = "360 DUPLO!").
	  CÂMERA .......... de lado ou de cabeça para baixo na pista, a câmera gira junto com o veículo.
	  RAMPAS .......... saiu de uma peça com a tag "Rampa"? Ganha um empurrão extra (atributo "Impulso").
	  POUSO PERFEITO .. caiu numa DESCIDA do jeitinho dela (rodas retinhas e sem "pancada")?
	                    "POUSO PERFEITO!" + turbo. Pulos bem longos mostram o tempo no ar.
	  PANCADA ......... caiu com muita força? Sai uma onda de poeira em volta (da cor do chão).
	  MARCAS .......... na grama, na terra, na lama, na areia e na neve ficam as marcas dos pneus.
	  ATOLAR .......... areia, lama, neve e água seguram um pouquinho (lama segura mais).
	As pistas com as tags são feitas pelo arquivo 42 (ConstruirPista). Você também pode colocar as tags
	nas suas próprias peças (Properties > Tags).
	(A TERRA VOANDO das rodas agora é do módulo PoeiraDoChao, que vale para os dois veículos.)
	O QuadricicloCliente chama Pista.atualizar(quad, dt) a cada frame. Saiu do banco? Tudo desliga sozinho.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Veiculo = require(script.Parent:WaitForChild("Veiculo")) -- (a "frente" e o "cima" do veículo)
local CameraModulo = require(script.Parent:WaitForChild("Camera")) -- (o tranco na tela: Camera.tremer)
local Tela = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Tela")) -- (no celular, textos menores)
local PoeiraDoChao = require(script.Parent:WaitForChild("PoeiraDoChao")) -- (a cor da poeira de cada chão)

local Pista = {}

-- =====================================================================
-- AJUSTES
-- =====================================================================
local SO_NO_MONSTRO = true -- true = só o caminhão monstro · false = o quadriciclo também
local TAG_PISTA_360 = "Pista360"
local TAG_RAMPA = "Rampa"
-- loops e tubos
local GRUDAR = 1 -- (vezes a gravidade) a força que aperta o veículo contra o loop e o tubo
local GRAVIDADE_NA_PISTA = 0.1 -- quanto da gravidade de verdade continua no loop (0 = nada · 1 = toda):
--                                 com um pouquinho, ele sobe mais devagar e desce mais rápido (dá "embalo")
local VELOCIDADE_PARA_GRUDAR = 18 -- (studs/s) de cabeça para baixo, mais devagar que isso ele vai soltando
local TURBO_DO_360 = 15 -- (studs/s) o empurrão de cada volta de 360°
local CAMERA_NA_PISTA = true -- de lado ou de cabeça para baixo na pista, a câmera gira junto (false = desliga)
-- rampas e pulos
local IMPULSO_DA_RAMPA = 30 -- (studs/s) o empurrão de uma rampa sem o atributo "Impulso"
local POUSO_TEMPO_MINIMO = 0.8 -- (s) só vale "POUSO PERFEITO" depois de um pulo de verdade
local POUSO_PERFEITO_GRAUS = 15 -- (graus) o quanto as rodas podem estar tortas em relação ao chão
local POUSO_SUAVE_GRAUS = 25 -- (graus) o quanto a queda pode "bater" no chão (0 = chegar deslizando)
local TURBO_DO_POUSO = 20 -- (studs/s) o empurrão do pouso perfeito
local PANCADA_FORTE = 45 -- (studs/s) caindo contra o chão mais rápido que isso, sai a onda de poeira
-- terreno
local MARCAS_NA_TERRA = true
local DURACAO_DAS_MARCAS = 6 -- (s)
local TERRENO_SEGURA = true -- areia, lama, neve e água seguram um pouquinho

-- =====================================================================
-- OS TIPOS DE CHÃO
-- =====================================================================
type TipoDeChao = {
	marca: Color3?, -- a cor da marca do pneu (nil = não deixa marca)
	segura: number, -- quanto segura (por segundo): 0 = nada
}
local CHAOS: { [string]: TipoDeChao } = {
	Grama = { marca = Color3.fromRGB(70, 85, 45), segura = 0 },
	Terra = { marca = Color3.fromRGB(80, 60, 40), segura = 0 },
	Lama = { marca = Color3.fromRGB(50, 38, 25), segura = 0.35 },
	Areia = { marca = Color3.fromRGB(175, 150, 105), segura = 0.15 },
	Neve = { marca = Color3.fromRGB(170, 185, 210), segura = 0.12 },
	Pedra = { marca = nil, segura = 0 },
	Agua = { marca = nil, segura = 0.2 },
}
-- Que tipo de chão é cada material (os que não estão aqui, como o plástico das pistas, ficam limpinhos)
local MATERIAL_PARA_CHAO: { [Enum.Material]: string } = {
	[Enum.Material.Grass] = "Grama",
	[Enum.Material.LeafyGrass] = "Grama",
	[Enum.Material.Ground] = "Terra",
	[Enum.Material.Mud] = "Lama",
	[Enum.Material.Sand] = "Areia",
	[Enum.Material.Sandstone] = "Areia",
	[Enum.Material.Snow] = "Neve",
	[Enum.Material.Glacier] = "Neve",
	[Enum.Material.Rock] = "Pedra",
	[Enum.Material.Slate] = "Pedra",
	[Enum.Material.Basalt] = "Pedra",
	[Enum.Material.Limestone] = "Pedra",
	[Enum.Material.Asphalt] = "Pedra",
	[Enum.Material.Pavement] = "Pedra",
	[Enum.Material.Cobblestone] = "Pedra",
	[Enum.Material.Concrete] = "Pedra",
	[Enum.Material.Water] = "Agua",
}

-- =====================================================================
-- O QUE O MÓDULO GUARDA
-- =====================================================================
type Roda = {
	roda: BasePart,
	raio: number,
	largura: number,
	bordaA: Attachment, -- as 2 beiradas da marca do pneu
	bordaB: Attachment,
	marca: Trail,
	chao: string?, -- o tipo de chão embaixo dela agora (nil = nenhum dos tipos, ou no ar)
	corDaMarca: string?, -- de que chão é a cor da marca agora (só troca quando muda)
}
-- Um "bloco" = um grupo de peças soldadas que se mexe junto (o chassi, cada manga, cada roda...)
type Bloco = { parte: BasePart, forca: VectorForce }
type Estado = {
	quad: any,
	chassi: BasePart,
	rodas: { Roda },
	blocos: { Bloco },
	criados: { Instance }, -- tudo que o módulo criou (para apagar no fim)
	filtro: RaycastParams, -- os raios do chão: ignoram o veículo, o boneco e a água
	filtroAgua: RaycastParams, -- os raios que procuram água
	distanciaDaCamera: number,
	alturaDaCamera: number,
	tempoNoAr: number,
	velocidadeNoAr: Vector3, -- a velocidade no último frame no ar (para saber se o pouso foi "suave")
	rodasNoChaoAntes: number,
	ultimaRampa: number, -- (os.clock) a última vez que uma roda estava numa rampa
	impulsoDaRampa: number,
	grudado: boolean, -- está grudado num loop ou tubo agora?
	grudadoAte: number, -- (os.clock) continua grudado até aqui (um tiquinho depois de perder a pista)
	normalDaPista: Vector3, -- para onde a pista "aponta" (o "cima" da pista)
	giroFrente: number, -- quanto já girou grudado na pista (radianos), para o "360!"
	giroLado: number,
	passouDeCabeca: boolean, -- já passou de cabeça para baixo nesta volta?
	voltas: number, -- quantos 360 seguidos
}

local estado: Estado? = nil
local ultimaAtualizacao = 0
local ligarExtras: () -> () -- (a câmera da pista e a rede de segurança: as funções vêm lá embaixo)
local desligarExtras: () -> ()

-- Devolve o valor como uma Instance (ou nil, se ele não for uma).
local function comoInstancia(valor: any): Instance?
	return if typeof(valor) == "Instance" then (valor :: Instance) else nil
end

-- A peça (ou o Model dela, até 2 "pais" acima) tem esta tag? Devolve quem tem a tag.
local function temTag(objeto: Instance, tag: string): Instance?
	local atual: Instance? = objeto
	for _ = 1, 3 do
		if atual == nil or atual == workspace then
			return nil
		end
		if CollectionService:HasTag(atual, tag) then
			return atual
		end
		atual = atual.Parent
	end
	return nil
end

-- =====================================================================
-- EFEITOS: estrelinhas, o texto na tela e a onda de poeira
-- =====================================================================
local function estrelinhas(chassi: BasePart)
	local estrelas = Instance.new("ParticleEmitter")
	estrelas.Enabled = false
	estrelas.Color = ColorSequence.new(Color3.fromRGB(120, 255, 200), Color3.fromRGB(255, 230, 90))
	estrelas.LightEmission = 1
	estrelas.Size = NumberSequence.new(1.6, 0)
	estrelas.Lifetime = NumberRange.new(0.5, 0.8)
	estrelas.Speed = NumberRange.new(18, 30)
	estrelas.SpreadAngle = Vector2.new(180, 180)
	estrelas.Drag = 3
	estrelas.Parent = chassi
	estrelas:Emit(35)
	task.delay(1.2, function()
		estrelas:Destroy()
	end)
end

local telaDoAviso: ScreenGui? = nil
local function anunciar(mensagem: string, cor: Color3)
	local tela = telaDoAviso
	if tela == nil or tela.Parent == nil then
		local jogador = Players.LocalPlayer
		local playerGui = if jogador then jogador:FindFirstChildOfClass("PlayerGui") else nil
		if playerGui == nil then
			return
		end
		local nova = Instance.new("ScreenGui")
		nova.Name = "AvisoPista"
		nova.ResetOnSpawn = false
		nova.IgnoreGuiInset = true
		nova.DisplayOrder = 6
		nova.Parent = playerGui
		telaDoAviso = nova
		tela = nova
	end
	if tela == nil then
		return
	end
	local velho = tela:FindFirstChild("Aviso")
	if velho then
		velho:Destroy()
	end
	local texto = Instance.new("TextLabel")
	texto.Name = "Aviso"
	texto.AnchorPoint = Vector2.new(0.5, 0.5)
	texto.Position = UDim2.fromScale(0.5, 0.39) -- (um pouco abaixo do "MORTAL!" do módulo Monstro: os dois combinam)
	texto.Size = UDim2.fromOffset(700, 70)
	texto.BackgroundTransparency = 1
	texto.Font = Enum.Font.FredokaOne
	texto.Text = mensagem
	texto.TextSize = Tela.tamanho(40) -- (no celular, menor)
	texto.TextColor3 = cor
	local contorno = Instance.new("UIStroke")
	contorno.Thickness = 3
	contorno.Color = Color3.fromRGB(20, 50, 40)
	contorno.Parent = texto
	local escala = Instance.new("UIScale")
	escala.Scale = 0.3
	escala.Parent = texto
	texto.Parent = tela
	TweenService:Create(escala, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1, function()
		local sumir = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(texto, sumir, { TextTransparency = 1 }):Play()
		TweenService:Create(contorno, sumir, { Transparency = 1 }):Play()
		task.delay(0.45, function()
			texto:Destroy()
		end)
	end)
end

-- A ONDA DE POEIRA da pancada: 12 jatos de poeira saindo em roda, deitados no chão.
--   forca: 0 = pancada forte · 1 = pancada enorme (mais poeira, mais longe)
local function ondaDePoeira(centro: Vector3, normal: Vector3, cor: ColorSequence, forca: number)
	-- duas direções "deitadas" no chão (as duas perpendiculares à normal)
	local lado = normal:Cross(Vector3.xAxis)
	if lado.Magnitude < 0.1 then
		lado = normal:Cross(Vector3.zAxis)
	end
	lado = lado.Unit
	local outroLado = normal:Cross(lado)
	local pontos: { Attachment } = {}
	local JATOS = 12
	for i = 1, JATOS do
		local angulo = i / JATOS * 2 * math.pi
		local direcao = lado * math.cos(angulo) + outroLado * math.sin(angulo)
		local ponto = Instance.new("Attachment")
		ponto.Name = "PistaPancada"
		ponto.Parent = workspace.Terrain
		ponto.WorldCFrame = CFrame.lookAt(centro + normal * 0.5, centro + normal * 0.5 + direcao, normal)
		local poeira = Instance.new("ParticleEmitter")
		poeira.Enabled = false -- (não solta sozinha: só o "Emit" lá embaixo)
		poeira.Texture = "rbxasset://textures/particles/smoke_main.dds"
		poeira.Color = cor
		poeira.LightInfluence = 0.8
		poeira.Size = NumberSequence.new(1.5, 5 + 3 * forca)
		poeira.Transparency = NumberSequence.new(0.25, 1)
		poeira.Lifetime = NumberRange.new(0.6, 1.1)
		poeira.Speed = NumberRange.new(25 + 25 * forca, 45 + 35 * forca)
		poeira.Drag = 4 -- (sai rápido e freia: parece uma onda)
		poeira.SpreadAngle = Vector2.new(15, 15)
		poeira.Acceleration = normal * 5 -- (sobe um pouquinho)
		poeira.Rotation = NumberRange.new(0, 360)
		poeira.RotSpeed = NumberRange.new(-40, 40)
		poeira.EmissionDirection = Enum.NormalId.Front -- (sai para a "frente" do ponto = a direção do jato)
		poeira.Parent = ponto
		poeira:Emit(math.floor(4 + 6 * forca))
		table.insert(pontos, ponto)
	end
	task.delay(1.6, function()
		for _, ponto in pontos do
			ponto:Destroy()
		end
	end)
end

-- Muda a velocidade do veículo INTEIRO (cada bloco uma vez só).
local function empurrar(atual: Estado, velocidade: Vector3)
	for _, bloco in atual.blocos do
		bloco.parte.AssemblyLinearVelocity += velocidade
	end
end

-- =====================================================================
-- LIGAR E DESLIGAR
-- =====================================================================
local function ligar(quad: any): Estado?
	local chassi = comoInstancia(quad.chassi)
	if chassi == nil or not chassi:IsA("BasePart") then
		return nil
	end
	local criados: { Instance } = {}

	-- 1) OS BLOCOS: cada grupo de peças soldadas ganha a sua própria força (para grudar no loop).
	--    O chassi e as peças dele (e o seu boneco sentado) são um bloco; cada manga e cada roda são outros.
	local blocos: { Bloco } = {}
	local jaTem: { [BasePart]: boolean } = {}
	local function adicionarBloco(parte: BasePart)
		local raiz = parte.AssemblyRootPart or parte -- (a peça "chefe" do bloco)
		if jaTem[raiz] or parte.Anchored then
			return
		end
		jaTem[raiz] = true
		local anexo = Instance.new("Attachment")
		anexo.Name = "PistaForca"
		anexo.Parent = parte
		local forca = Instance.new("VectorForce")
		forca.Name = "PistaForca"
		forca.Attachment0 = anexo
		forca.RelativeTo = Enum.ActuatorRelativeTo.World
		forca.ApplyAtCenterOfMass = true -- (empurra o bloco pelo meio, sem fazer girar)
		forca.Force = Vector3.zero
		forca.Parent = parte
		table.insert(criados, anexo)
		table.insert(criados, forca)
		table.insert(blocos, { parte = parte, forca = forca })
	end
	adicionarBloco(chassi)
	if typeof(quad.pecasFisicas) == "table" then
		for _, item in quad.pecasFisicas do
			local parte = comoInstancia(item)
			if parte and parte:IsA("BasePart") then
				adicionarBloco(parte)
			end
		end
	end

	-- 2) AS RODAS: as marcas (os pontos ficam soltos no mundo e andam junto com a roda)
	local rodas: { Roda } = {}
	local function pontoSolto(nome: string): Attachment
		local anexo = Instance.new("Attachment")
		anexo.Name = nome
		anexo.Parent = workspace.Terrain
		table.insert(criados, anexo)
		return anexo
	end
	if typeof(quad.rodas) == "table" then
		for _, info in quad.rodas do
			local roda = comoInstancia(info.roda)
			if roda and roda:IsA("BasePart") then
				local bordaA = pontoSolto("PistaMarcaA")
				local bordaB = pontoSolto("PistaMarcaB")
				local marca = Instance.new("Trail")
				marca.Name = "PistaMarca"
				marca.Attachment0 = bordaA
				marca.Attachment1 = bordaB
				marca.FaceCamera = false -- deitada no chão
				marca.Lifetime = DURACAO_DAS_MARCAS
				marca.MinLength = 0.3
				marca.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.25),
					NumberSequenceKeypoint.new(0.8, 0.45),
					NumberSequenceKeypoint.new(1, 1),
				})
				marca.LightInfluence = 1
				marca.Enabled = false
				marca.Parent = bordaA
				local medidas = { roda.Size.X, roda.Size.Y, roda.Size.Z }
				table.sort(medidas)
				table.insert(rodas, {
					roda = roda,
					raio = if typeof(info.raio) == "number" then info.raio else medidas[2] / 2,
					largura = medidas[1],
					bordaA = bordaA,
					bordaB = bordaB,
					marca = marca,
					chao = nil,
					corDaMarca = nil,
				})
			end
		end
	end

	-- 3) OS RAIOS ignoram o veículo e o seu boneco (o do chão também ignora a água)
	local ignorar: { Instance } = {}
	local modelo = comoInstancia(quad.modelo)
	if modelo then
		table.insert(ignorar, modelo)
	end
	local jogador = Players.LocalPlayer
	local personagem = if jogador then jogador.Character else nil
	if personagem then
		table.insert(ignorar, personagem)
	end
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	filtro.FilterDescendantsInstances = ignorar
	filtro.IgnoreWater = true
	local filtroAgua = RaycastParams.new()
	filtroAgua.FilterType = Enum.RaycastFilterType.Exclude
	filtroAgua.FilterDescendantsInstances = ignorar
	filtroAgua.IgnoreWater = false

	-- 4) A CÂMERA DA PISTA fica mais longe nos veículos maiores
	local tamanho = if modelo and modelo:IsA("Model") then modelo:GetExtentsSize() else chassi.Size
	local comprimento = math.max(tamanho.X, tamanho.Z)

	return {
		quad = quad,
		chassi = chassi,
		rodas = rodas,
		blocos = blocos,
		criados = criados,
		filtro = filtro,
		filtroAgua = filtroAgua,
		distanciaDaCamera = math.clamp(comprimento * 1.3 + 4, 12, 40),
		alturaDaCamera = math.clamp(comprimento * 0.45 + 2, 4, 16),
		tempoNoAr = 0,
		velocidadeNoAr = Vector3.zero,
		rodasNoChaoAntes = 0,
		ultimaRampa = 0,
		impulsoDaRampa = IMPULSO_DA_RAMPA,
		grudado = false,
		grudadoAte = 0,
		normalDaPista = Vector3.yAxis,
		giroFrente = 0,
		giroLado = 0,
		passouDeCabeca = false,
		voltas = 0,
	}
end

local function desligar()
	desligarExtras()
	local atual = estado
	estado = nil
	if atual == nil then
		return
	end
	for _, bloco in atual.blocos do
		bloco.forca.Enabled = false
	end
	for _, roda in atual.rodas do
		roda.marca.Enabled = false
	end
	-- espera as marcas sumirem e apaga tudo
	local criados = atual.criados
	task.delay(DURACAO_DAS_MARCAS + 0.5, function()
		for _, objeto in criados do
			objeto:Destroy()
		end
	end)
end

-- =====================================================================
-- A CADA FRAME
-- =====================================================================
function Pista.atualizar(quad: any, dt: number)
	ultimaAtualizacao = os.clock()
	local modelo = comoInstancia(quad.modelo)
	local ativo = modelo ~= nil and (not SO_NO_MONSTRO or modelo:GetAttribute("Monstro") == true)
	local velho = estado
	if velho and (not ativo or velho.quad ~= quad or velho.chassi.Parent == nil) then
		desligar()
	end
	if not ativo then
		return
	end
	if estado == nil then
		estado = ligar(quad)
		if estado then
			ligarExtras() -- (a câmera da pista só roda enquanto alguém dirige o caminhão)
		end
	end
	local atual = estado
	if atual == nil then
		return
	end
	local agora = os.clock()
	local chassi = atual.chassi
	local referencia: CFrame = Veiculo.referencia(quad)
	local cima = referencia.UpVector
	local velocidade = chassi.AssemblyLinearVelocity
	local rapidez = velocidade.Magnitude

	-- 1) O QUE TEM EMBAIXO DE CADA RODA (um raio curto para "baixo" do veículo, saindo do meio da roda)
	local rodasNoChao = 0
	local naPista360 = 0
	local somaDasNormais = Vector3.zero
	local somaDosContatos = Vector3.zero
	local naRampa = false
	local segura = 0
	local primeiroAcerto: RaycastResult? = nil -- (o chão de uma das rodas: a cor da onda de poeira)
	for _, roda in atual.rodas do
		roda.chao = nil
		local centro = roda.roda.Position
		local acerto = workspace:Raycast(centro, -cima * (roda.raio + 1.5), atual.filtro)
		if acerto then
			primeiroAcerto = primeiroAcerto or acerto
			rodasNoChao += 1
			somaDasNormais += acerto.Normal
			somaDosContatos += acerto.Position
			if temTag(acerto.Instance, TAG_PISTA_360) then
				naPista360 += 1
			end
			local rampa = temTag(acerto.Instance, TAG_RAMPA)
			if rampa then
				naRampa = true
				local impulso = rampa:GetAttribute("Impulso")
				atual.impulsoDaRampa = if typeof(impulso) == "number" then impulso else IMPULSO_DA_RAMPA
			end
			roda.chao = MATERIAL_PARA_CHAO[acerto.Material]
			-- as 2 beiradas da marca do pneu ficam no chão, embaixo da roda
			local contato = acerto.Position + acerto.Normal * 0.06
			local lado = referencia.RightVector * (roda.largura * 0.45)
			roda.bordaA.WorldPosition = contato + lado
			roda.bordaB.WorldPosition = contato - lado
		end
		-- ÁGUA: um segundo raio (que enxerga a água). Na água, a roda é segurada (e não deixa marca).
		if TERRENO_SEGURA then
			local agua = workspace:Raycast(centro + cima * 2, -cima * (roda.raio + 3.5), atual.filtroAgua)
			if agua and agua.Material == Enum.Material.Water then
				roda.chao = "Agua"
			end
		end
		local chaoDaRoda = roda.chao
		if chaoDaRoda then
			segura += CHAOS[chaoDaRoda].segura
		end
	end
	local normalDoChao = if rodasNoChao > 0 and somaDasNormais.Magnitude > 0.01 then somaDasNormais.Unit else cima

	-- 2) LOOPS E TUBOS: na "Pista360", a pista vira o chão (a gravidade puxa contra ela)
	if naPista360 >= 2 then
		atual.grudadoAte = agora + 0.15 -- (fica grudado mais um tiquinho se perder a pista num solavanco)
		atual.normalDaPista = normalDoChao
	end
	atual.grudado = agora < atual.grudadoAte
	if atual.grudado then
		local normal = atual.normalDaPista
		local forca = 1
		if normal.Y < -0.1 and rapidez < VELOCIDADE_PARA_GRUDAR then
			forca = math.clamp(rapidez / VELOCIDADE_PARA_GRUDAR, 0, 1) -- de cabeça para baixo e devagar: vai soltando
		end
		-- tira (quase toda) a gravidade de verdade e puxa contra a pista, em cada bloco (pelo peso dele)
		local porPeso = (Vector3.yAxis * (1 - GRAVIDADE_NA_PISTA) - normal * GRUDAR) * workspace.Gravity * forca
		for _, bloco in atual.blocos do
			bloco.forca.Force = porPeso * bloco.parte.AssemblyMass
		end
	else
		for _, bloco in atual.blocos do
			bloco.forca.Force = Vector3.zero
		end
	end

	-- 3) 360!: conta quanto ele girou grudado na pista (para frente e de lado). Só vale se passou
	--    de cabeça para baixo (subir e descer a parede do meio-tubo não conta).
	if atual.grudado then
		if cima.Y < -0.5 then
			atual.passouDeCabeca = true
		elseif cima.Y > 0.97 and not atual.passouDeCabeca then
			atual.giroFrente = 0 -- (de pé e ainda sem passar de cabeça para baixo: começa a contar daqui)
			atual.giroLado = 0
		end
		local giro = chassi.AssemblyAngularVelocity
		atual.giroFrente += giro:Dot(referencia.RightVector) * dt
		atual.giroLado += giro:Dot(referencia.LookVector) * dt
		local girou = math.sqrt(atual.giroFrente ^ 2 + atual.giroLado ^ 2)
		if atual.passouDeCabeca and girou >= 2 * math.pi - 0.7 then -- (quase uma volta inteira: ~320°)
			atual.giroFrente = 0
			atual.giroLado = 0
			atual.passouDeCabeca = false
			atual.voltas += 1
			local nomes = { "360!", "360 DUPLO!", "360 TRIPLO!" }
			anunciar(nomes[atual.voltas] or `360 x{atual.voltas}!`, Color3.fromRGB(255, 205, 60))
			if rapidez > 5 then
				empurrar(atual, velocidade.Unit * TURBO_DO_360)
			end
			CameraModulo.tremer(0.12)
			estrelinhas(chassi)
		end
	elseif agora - atual.grudadoAte > 0.6 then
		atual.giroFrente = 0 -- (saiu da pista: zera tudo)
		atual.giroLado = 0
		atual.passouDeCabeca = false
		atual.voltas = 0
	end

	-- 4) RAMPAS: estava numa rampa e acabou de sair do chão? Empurrão!
	if naRampa then
		atual.ultimaRampa = agora
	end
	if rodasNoChao == 0 and atual.rodasNoChaoAntes > 0 and agora - atual.ultimaRampa < 0.25 then
		atual.ultimaRampa = 0 -- (um empurrão por pulo)
		if rapidez > 10 then
			local impulso = atual.impulsoDaRampa
			empurrar(atual, velocidade.Unit * impulso + Vector3.yAxis * impulso * 0.25)
			CameraModulo.tremer(0.1)
		end
	end

	-- 5) NO AR e o POUSO
	if rodasNoChao == 0 then
		atual.tempoNoAr += dt
		atual.velocidadeNoAr = velocidade
	else
		local tempo = atual.tempoNoAr
		if tempo > 0.3 and rodasNoChao >= 2 then
			local vinha = atual.velocidadeNoAr
			local batida = -vinha:Dot(normalDoChao) -- quão rápido ele vinha CONTRA o chão
			-- 5a) PANCADA: caiu com muita força? Onda de poeira (da cor do chão)
			if batida > PANCADA_FORTE and primeiroAcerto then
				local cor = PoeiraDoChao.corDaPoeira(primeiroAcerto) -- (a mesma cor da poeira das rodas)
				ondaDePoeira(somaDosContatos / rodasNoChao, normalDoChao, cor, math.clamp((batida - PANCADA_FORTE) / 60, 0, 1))
			end
			-- 5b) POUSO PERFEITO: rodas alinhadas com o chão E chegando "deslizando" (como numa descida)
			local rapidezNoAr = vinha.Magnitude
			if tempo >= POUSO_TEMPO_MINIMO and rapidezNoAr > 15 then
				local torto = math.deg(math.acos(math.clamp(cima:Dot(normalDoChao), -1, 1)))
				local pancadaEmGraus = math.deg(math.asin(math.clamp(batida / rapidezNoAr, -1, 1)))
				local segundos = (string.gsub(string.format("%.1f", tempo), "%.", ",")) -- ex.: "1,4"
				if torto <= POUSO_PERFEITO_GRAUS and pancadaEmGraus <= POUSO_SUAVE_GRAUS then
					local naDescida = velocidade - normalDoChao * velocidade:Dot(normalDoChao)
					if naDescida.Magnitude > 1 then
						empurrar(atual, naDescida.Unit * TURBO_DO_POUSO)
					end
					anunciar(if tempo >= 1.2 then `POUSO PERFEITO! {segundos}s` else "POUSO PERFEITO!", Color3.fromRGB(120, 255, 190))
					CameraModulo.tremer(0.12)
					estrelinhas(chassi)
				elseif tempo >= 1.2 and torto <= 60 then
					anunciar(`{segundos}s NO AR!`, Color3.fromRGB(255, 255, 255)) -- (pulão, mas sem pouso perfeito)
				end
			end
		end
		atual.tempoNoAr = 0
	end
	atual.rodasNoChaoAntes = rodasNoChao

	-- 6) MARCAS (cada tipo de chão com a sua cor)
	for _, roda in atual.rodas do
		local nomeDoChao = roda.chao
		local chao = if nomeDoChao then CHAOS[nomeDoChao] else nil
		local corDaMarca = if chao then chao.marca else nil
		local marcar = MARCAS_NA_TERRA and corDaMarca ~= nil and rapidez > 2
		if marcar and corDaMarca and roda.corDaMarca ~= nomeDoChao then
			roda.corDaMarca = nomeDoChao
			roda.marca.Color = ColorSequence.new(corDaMarca)
		end
		if roda.marca.Enabled ~= marcar then
			roda.marca.Enabled = marcar
		end
	end

	-- 7) ATOLAR: areia, lama, neve e água seguram um pouquinho (só o andar, não a queda)
	if TERRENO_SEGURA and rodasNoChao >= 2 and segura > 0 and not atual.grudado then
		local mediaQueSegura = segura / rodasNoChao
		local deitada = velocidade - normalDoChao * velocidade:Dot(normalDoChao)
		empurrar(atual, -deitada * math.min(mediaQueSegura * dt, 1))
	end
end

-- =====================================================================
-- A CÂMERA NO LOOP E NO TUBO: de lado ou de cabeça para baixo, ela fica atrás do veículo e gira junto.
-- Roda depois de todas as outras câmeras (e se mistura com elas devagar, para não dar tranco).
-- =====================================================================
local mistura = 0 -- 0 = a câmera normal · 1 = a câmera da pista
local cameraPresa = false
local cimaDaCamera = Vector3.yAxis
local frenteDaCamera = Vector3.new(0, 0, -1)

local CAMERA_DA_PISTA = "PistaCamera" -- nome da tarefa (BindToRenderStep)
local function passoDaCamera(dt: number)
	local camera = workspace.CurrentCamera
	local atual = estado
	if camera == nil or atual == nil or atual.chassi.Parent == nil then
		mistura = 0 -- (sem câmera, fora do caminhão ou o caminhão sumiu: câmera normal)
		cameraPresa = false
		return
	end
	local referencia: CFrame = Veiculo.referencia(atual.quad)
	local cima = referencia.UpVector
	local frente = referencia.LookVector
	-- liga: grudado na pista e bem deitado (mais de ~55°) · desliga: quase de pé de novo, ou saiu da pista
	if not CAMERA_NA_PISTA or not atual.grudado or atual.quad.modoCamera == 3 then
		cameraPresa = false
	elseif cima.Y < 0.6 then
		cameraPresa = true
	elseif cima.Y > 0.8 then
		cameraPresa = false
	end
	local alvo = if cameraPresa then 1 else 0
	if mistura == 0 then
		if alvo == 0 then
			return -- (câmera normal: não mexe em nada)
		end
		cimaDaCamera = cima -- (começando agora: parte do jeito que o veículo está)
		frenteDaCamera = frente
	end
	mistura += (alvo - mistura) * math.min(dt * 5, 1)
	if alvo == 0 and mistura < 0.01 then
		mistura = 0
		return
	end
	-- o "cima" e a "frente" da câmera seguem os do veículo com um atrasinho (fica suave)
	local suave = math.min(dt * 8, 1)
	local novoCima = cimaDaCamera:Lerp(cima, suave)
	cimaDaCamera = if novoCima.Magnitude > 0.01 then novoCima.Unit else cima
	local novaFrente = frenteDaCamera:Lerp(frente, suave)
	novaFrente -= cimaDaCamera * novaFrente:Dot(cimaDaCamera) -- (deixa a frente "deitada" em relação ao cima)
	frenteDaCamera = if novaFrente.Magnitude > 0.01 then novaFrente.Unit else frente
	-- onde a câmera fica: atrás e acima (do jeito do veículo). Se a pista estiver no caminho, chega mais perto.
	local pivo = atual.chassi.Position
	local inicio = pivo + cimaDaCamera * (atual.alturaDaCamera * 0.5)
	local caminho = (pivo - frenteDaCamera * atual.distanciaDaCamera + cimaDaCamera * atual.alturaDaCamera) - inicio
	local distancia = caminho.Magnitude
	local bateu = workspace:Raycast(inicio, caminho, atual.filtro)
	if bateu then
		distancia = math.max(bateu.Distance - 1.5, 2)
	end
	local posicao = inicio + caminho.Unit * distancia
	local perseguir = CFrame.lookAt(posicao, pivo + cimaDaCamera * 2, cimaDaCamera)
	camera.CFrame = camera.CFrame:Lerp(perseguir, mistura)
end

-- A câmera da pista e a rede de segurança só existem enquanto alguém dirige o caminhão.
local extrasLigados = false
local vigia: RBXScriptConnection? = nil

ligarExtras = function()
	if extrasLigados then
		return
	end
	extrasLigados = true
	RunService:BindToRenderStep(CAMERA_DA_PISTA, Enum.RenderPriority.Last.Value + 1, passoDaCamera)
	-- Rede de segurança: se o QuadricicloCliente parar de chamar o atualizar (1 s), desliga tudo.
	vigia = RunService.Heartbeat:Connect(function()
		if estado and os.clock() - ultimaAtualizacao > 1 then
			desligar()
		end
	end)
end

desligarExtras = function()
	if not extrasLigados then
		return
	end
	extrasLigados = false
	RunService:UnbindFromRenderStep(CAMERA_DA_PISTA)
	local conexao = vigia
	if conexao then
		conexao:Disconnect()
	end
	vigia = nil
	mistura = 0 -- (a câmera volta a ser a normal)
	cameraPresa = false
end

-- Parou de dirigir (o QuadricicloCliente chama): desliga tudo NA HORA.
function Pista.desligar()
	desligar()
end

return Pista

