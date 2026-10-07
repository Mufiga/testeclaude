--!strict
--[[
	=====================================================================
	Monstro  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Monstro
	       (DENTRO do QuadricicloCliente, junto com Veiculo, Camera, Gancho, Sensacao...)
	=====================================================================

	As mecânicas do CAMINHÃO MONSTRO (o Model com o atributo "Monstro" = true; o arquivo 38 coloca):
	  SUPER PULO .... segure J (controle: Y · celular: o botão PULO). Enquanto carrega, ele AGACHA nas molas.
	                  Solte: ele pula! (mais carga = mais alto)
	  MORTAIS ....... no ar, W/S dão MORTAL para frente/trás e A/D dão GIRO DE LADO. No ar ele fica mais
	                  "leve", para dar tempo de girar.
	  CAIR DE PÉ .... depois de um mortal: "MORTAL!" na tela, um tranco, estrelinhas e um TURBO para frente.
	                  Caiu de cabeça para baixo? "CAPOTOU!"
	  ESCAPAMENTO ... solta mais fumaça preta quando você acelera ou carrega o pulo.
	  CÂMERA ........ fica mais longe (o caminhão é grande).
	O QuadricicloCliente chama Monstro.atualizar(quad, dt, pedal, volante) a cada frame. Saiu do banco?
	Tudo desliga sozinho.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Veiculo = require(script.Parent:WaitForChild("Veiculo")) -- (a "frente" e o "cima" do veículo)
local CameraModulo = require(script.Parent:WaitForChild("Camera")) -- (o tranco na tela: Camera.tremer)

local Monstro = {}

-- =====================================================================
-- AJUSTES
-- =====================================================================
local SO_NO_MONSTRO = true -- true = só o caminhão monstro · false = o quadriciclo também pula e dá mortal
local TECLA_DO_PULO = Enum.KeyCode.J
local BOTAO_DO_CONTROLE = Enum.KeyCode.ButtonY
local PULO_MINIMO = 35 -- (studs/s) a força do pulo soltando logo
local PULO_MAXIMO = 85 -- (studs/s) a força do pulo com a carga cheia (85 ≈ uns 28 studs de altura)
local TEMPO_DE_CARGA = 0.9 -- (s) quanto tempo segurando até a carga encher
local AGACHAR = 120 -- quanto ele afunda nas molas enquanto carrega (0 = não afunda)
local LEVEZA_NO_AR = 0.35 -- no ar, a gravidade fica 35% mais fraca (0 = desliga)
local GIRO_NO_AR = 6 -- (rad/s) a rapidez do mortal (6 = mais ou menos uma volta por segundo)
local TURBO_POR_MORTAL = 25 -- (studs/s) o empurrão para frente por mortal certo
local ZOOM_MINIMO = 22 -- (studs) a câmera fica pelo menos isso longe
local SOM_DO_MORTAL = "" -- (opcional) o id de um som de comemoração, ex.: "rbxassetid://1234567"

-- =====================================================================
-- O QUE O MÓDULO GUARDA
-- =====================================================================
type Roda = { roda: BasePart, raio: number }
type Estado = {
	quad: any, -- o caminhão que está sendo dirigido
	chassi: BasePart,
	rodas: { Roda },
	pecas: { BasePart }, -- as peças com física (chassi, mangas e rodas): giram juntas no mortal
	forca: VectorForce, -- a força que deixa ele "leve" no ar e agachado carregando o pulo
	anexoDaForca: Attachment,
	filtro: RaycastParams, -- (os raios que procuram o chão ignoram o caminhão e o seu boneco)
	massaTotal: number,
	massaDoChassi: number,
	rodasNoChao: number,
	carregando: boolean,
	inicioDaCarga: number,
	carga: number, -- 0 a 1
	puloPronto: number, -- (os.clock) quando pode pular de novo
	tempoNoAr: number,
	giroFrente: number, -- (radianos) quanto girou para frente (negativo) ou para trás (positivo) no ar
	giroLado: number, -- (radianos) quanto girou de lado no ar
	mexeuNoAr: boolean, -- apertou alguma tecla de girar neste pulo?
	zoomAntes: number?, -- o zoom da câmera antes (para voltar no fim)
	barra: ScreenGui?, -- a barrinha da carga do pulo
	enchimento: Frame?,
	fumacas: { ParticleEmitter }, -- a fumaça dos escapamentos
}

local estado: Estado? = nil
local ultimaAtualizacao = 0

-- Devolve o valor como uma Instance (ou nil, se ele não for uma).
local function comoInstancia(valor: any): Instance?
	return if typeof(valor) == "Instance" then (valor :: Instance) else nil
end

-- =====================================================================
-- EFEITOS: poeira, estrelinhas e o texto na tela
-- =====================================================================

-- Uma nuvem de poeira solta no mundo (some sozinha).
local function poeirada(posicao: Vector3, quantas: number)
	local ponto = Instance.new("Attachment")
	ponto.Parent = workspace.Terrain
	ponto.WorldPosition = posicao
	local poeira = Instance.new("ParticleEmitter")
	poeira.Texture = "rbxasset://textures/particles/smoke_main.dds"
	poeira.Color = ColorSequence.new(Color3.fromRGB(236, 228, 210))
	poeira.LightInfluence = 0.6
	poeira.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 3), -- incha rápido ("puf!")
		NumberSequenceKeypoint.new(1, 4),
	})
	poeira.Transparency = NumberSequence.new(0.3, 1)
	poeira.Lifetime = NumberRange.new(0.5, 0.9)
	poeira.Speed = NumberRange.new(6, 14)
	poeira.SpreadAngle = Vector2.new(80, 80)
	poeira.Drag = 4
	poeira.Rotation = NumberRange.new(0, 360)
	poeira.Enabled = false -- (só a rajada do Emit)
	poeira.Parent = ponto
	poeira:Emit(quantas)
	task.delay(1.5, function()
		ponto:Destroy()
	end)
end

-- Estrelinhas douradas saindo do caminhão.
local function estrelinhas(chassi: BasePart)
	local estrelas = Instance.new("ParticleEmitter")
	estrelas.Enabled = false
	estrelas.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
	estrelas.LightEmission = 1
	estrelas.Size = NumberSequence.new(2, 0)
	estrelas.Lifetime = NumberRange.new(0.5, 0.9)
	estrelas.Speed = NumberRange.new(20, 35)
	estrelas.SpreadAngle = Vector2.new(180, 180)
	estrelas.Drag = 3
	estrelas.Parent = chassi
	estrelas:Emit(45)
	task.delay(1.2, function()
		estrelas:Destroy()
	end)
end

-- O TEXTO pulando na tela ("MORTAL!", "CAPOTOU!"...).
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
		nova.Name = "AvisoMonstro"
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
	texto.Position = UDim2.fromScale(0.5, 0.3)
	texto.Size = UDim2.fromOffset(700, 80)
	texto.BackgroundTransparency = 1
	texto.Font = Enum.Font.FredokaOne
	texto.Text = mensagem
	texto.TextSize = 46
	texto.TextColor3 = cor
	texto.Rotation = math.random(-5, 5)
	local contorno = Instance.new("UIStroke")
	contorno.Thickness = 3
	contorno.Color = Color3.fromRGB(40, 20, 60)
	contorno.Parent = texto
	local escala = Instance.new("UIScale")
	escala.Scale = 0.3
	escala.Parent = texto
	texto.Parent = tela
	TweenService:Create(escala, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1, function()
		local sumir = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(texto, sumir, { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.24) }):Play()
		TweenService:Create(contorno, sumir, { Transparency = 1 }):Play()
		task.delay(0.45, function()
			texto:Destroy()
		end)
	end)
	if SOM_DO_MORTAL ~= "" then
		local som = Instance.new("Sound")
		som.SoundId = SOM_DO_MORTAL
		som.Volume = 0.7
		som.Parent = game:GetService("SoundService")
		som:Play()
		task.delay(4, function()
			som:Destroy()
		end)
	end
end

-- "DUPLO", "TRIPLO"...
local function vezes(quantas: number): string
	if quantas == 2 then
		return " DUPLO"
	elseif quantas == 3 then
		return " TRIPLO"
	elseif quantas > 3 then
		return ` x{quantas}`
	end
	return ""
end

-- =====================================================================
-- O PULO E O GIRO
-- =====================================================================

-- Muda a velocidade de TODAS as peças juntas (o caminhão inteiro, como um bloco).
local function empurrar(atual: Estado, velocidade: Vector3)
	for _, parte in atual.pecas do
		parte.AssemblyLinearVelocity += velocidade
	end
end

-- Gira o caminhão INTEIRO em volta de um eixo, chegando aos poucos na rapidez "alvo" (rad/s).
local function girarNoAr(atual: Estado, eixo: Vector3, alvo: number, dt: number)
	local chassi = atual.chassi
	local agora = chassi.AssemblyAngularVelocity:Dot(eixo)
	local mudar = (alvo - agora) * math.min(dt * 5, 1)
	if math.abs(mudar) < 0.0001 then
		return
	end
	local delta = eixo * mudar
	local centro = chassi.AssemblyCenterOfMass
	for _, parte in atual.pecas do
		parte.AssemblyAngularVelocity += delta
		parte.AssemblyLinearVelocity += delta:Cross(parte.AssemblyCenterOfMass - centro) -- (gira em volta do meio)
	end
end

-- Soltou o botão do pulo: se está no chão, PULA (mais carga = mais alto).
local function soltarPulo(atual: Estado)
	local carga = atual.carga
	atual.carga = 0
	if atual.rodasNoChao < 3 or os.clock() < atual.puloPronto or carga < 0.05 then
		return
	end
	atual.puloPronto = os.clock() + 0.6
	local referencia: CFrame = Veiculo.referencia(atual.quad)
	local cima = referencia.UpVector
	local direcao = if cima.Y > 0.2 then (cima + Vector3.yAxis).Unit else cima -- (meio a meio entre o "cima" dele e o cima do mundo; (NOVO) de lado ou de cabeça para baixo no loop: pula para longe da pista)
	local forca = PULO_MINIMO + (PULO_MAXIMO - PULO_MINIMO) * carga
	local frente = Vector3.new(referencia.LookVector.X, 0, referencia.LookVector.Z)
	local paraFrente = if frente.Magnitude > 0.01 then frente.Unit * forca * 0.12 else Vector3.zero
	empurrar(atual, direcao * forca + paraFrente)
	CameraModulo.tremer(0.08 + 0.15 * carga)
	for _, roda in atual.rodas do
		poeirada(roda.roda.Position - cima * roda.raio, math.floor(6 + 10 * carga))
	end
end

-- Desliga o "endireitador" do pouso do gancho (se estiver ligado): no ar, quem manda é você.
local function soltarEndireitador(chassi: BasePart)
	for _, objeto in chassi:GetChildren() do
		if objeto:IsA("AlignOrientation") and objeto.Enabled then
			objeto.Enabled = false
		end
	end
end

-- Encostou no chão depois de um tempo no ar: fez mortal? Caiu de pé?
local function aterrissou(atual: Estado, referencia: CFrame)
	local volta = 2 * math.pi
	local voltasFrente = math.floor((math.abs(atual.giroFrente) + 0.6) / volta) -- (0,6 rad de folga: ~35°)
	local voltasLado = math.floor((math.abs(atual.giroLado) + 0.6) / volta)
	if voltasFrente + voltasLado == 0 then
		return
	end
	if referencia.UpVector.Y < 0.6 then
		anunciar("CAPOTOU!", Color3.fromRGB(255, 90, 90))
		return
	end
	local partes: { string } = {}
	if voltasFrente > 0 then
		local nome = if atual.giroFrente < 0 then "MORTAL PRA FRENTE" else "MORTAL PRA TRÁS"
		table.insert(partes, nome .. vezes(voltasFrente))
	end
	if voltasLado > 0 then
		table.insert(partes, "GIRO DE LADO" .. vezes(voltasLado))
	end
	anunciar(table.concat(partes, " + ") .. "!", Color3.fromRGB(255, 225, 90))
	-- PRÊMIO: um turbo para frente, um tranco e estrelinhas
	local frente = Vector3.new(referencia.LookVector.X, 0, referencia.LookVector.Z)
	if frente.Magnitude > 0.01 then
		empurrar(atual, frente.Unit * math.min(TURBO_POR_MORTAL * (voltasFrente + voltasLado), 60))
	end
	CameraModulo.tremer(0.2)
	estrelinhas(atual.chassi)
end

-- =====================================================================
-- LIGAR E DESLIGAR
-- =====================================================================
local function acaoDoPulo(_nome: string, estadoDoBotao: Enum.UserInputState, _botao: InputObject): Enum.ContextActionResult
	local atual = estado
	if atual == nil then
		return Enum.ContextActionResult.Pass
	end
	if estadoDoBotao == Enum.UserInputState.Begin then
		atual.carregando = true
		atual.inicioDaCarga = os.clock()
	elseif estadoDoBotao == Enum.UserInputState.End or estadoDoBotao == Enum.UserInputState.Cancel then
		if atual.carregando then
			atual.carregando = false
			soltarPulo(atual)
		end
	end
	return Enum.ContextActionResult.Sink
end

-- A barrinha da carga do pulo (aparece só enquanto carrega).
local function criarBarra(): (ScreenGui?, Frame?)
	local jogador = Players.LocalPlayer
	local playerGui = if jogador then jogador:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil then
		return nil, nil
	end
	local tela = Instance.new("ScreenGui")
	tela.Name = "PuloDoMonstro"
	tela.ResetOnSpawn = false
	tela.Enabled = false
	tela.Parent = playerGui
	local fundo = Instance.new("Frame")
	fundo.AnchorPoint = Vector2.new(0.5, 1)
	fundo.Position = UDim2.new(0.5, 0, 1, -130)
	fundo.Size = UDim2.fromOffset(240, 16)
	fundo.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	fundo.BackgroundTransparency = 0.25
	fundo.Parent = tela
	local redondo = Instance.new("UICorner")
	redondo.CornerRadius = UDim.new(1, 0)
	redondo.Parent = fundo
	local enchimento = Instance.new("Frame")
	enchimento.Size = UDim2.fromScale(0, 1)
	enchimento.BackgroundColor3 = Color3.fromRGB(150, 70, 255)
	enchimento.Parent = fundo
	redondo:Clone().Parent = enchimento
	local rotulo = Instance.new("TextLabel")
	rotulo.AnchorPoint = Vector2.new(0.5, 1)
	rotulo.Position = UDim2.new(0.5, 0, 0, -2)
	rotulo.Size = UDim2.fromOffset(240, 22)
	rotulo.BackgroundTransparency = 1
	rotulo.Font = Enum.Font.FredokaOne
	rotulo.Text = "SUPER PULO"
	rotulo.TextSize = 18
	rotulo.TextColor3 = Color3.new(1, 1, 1)
	rotulo.TextStrokeTransparency = 0.4
	rotulo.Parent = fundo
	return tela, enchimento
end

-- Começou a dirigir o caminhão: prepara a força, a barrinha, o botão e a câmera.
local function ligar(quad: any): Estado?
	local chassi = comoInstancia(quad.chassi)
	if chassi == nil or not chassi:IsA("BasePart") then
		return nil
	end
	local rodas: { Roda } = {}
	if typeof(quad.rodas) == "table" then
		for _, info in quad.rodas do
			local roda = comoInstancia(info.roda)
			if roda and roda:IsA("BasePart") then
				table.insert(rodas, { roda = roda, raio = if typeof(info.raio) == "number" then info.raio else roda.Size.Y / 2 })
			end
		end
	end
	-- as peças com física e o peso de todas juntas (cada "bloco" contado uma vez só)
	local pecas: { BasePart } = {}
	local massaTotal = 0
	local blocosVistos: { [BasePart]: boolean } = {}
	if typeof(quad.pecasFisicas) == "table" then
		for _, item in quad.pecasFisicas do
			local parte = comoInstancia(item)
			if parte and parte:IsA("BasePart") then
				table.insert(pecas, parte)
				local raiz = parte.AssemblyRootPart
				if raiz and not blocosVistos[raiz] then
					blocosVistos[raiz] = true
					massaTotal += parte.AssemblyMass
				end
			end
		end
	end
	if #pecas == 0 then
		table.insert(pecas, chassi)
		massaTotal = chassi.AssemblyMass
	end
	-- a força (leveza no ar + agachar carregando), presa no Chassi
	local anexo = Instance.new("Attachment")
	anexo.Name = "MonstroForca"
	anexo.Parent = chassi
	local forca = Instance.new("VectorForce")
	forca.Name = "MonstroForca"
	forca.Attachment0 = anexo
	forca.RelativeTo = Enum.ActuatorRelativeTo.World
	forca.ApplyAtCenterOfMass = true
	forca.Force = Vector3.zero
	forca.Parent = chassi
	-- os raios do chão ignoram o caminhão e o seu boneco
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
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
	filtro.FilterDescendantsInstances = ignorar
	-- a fumaça dos escapamentos (as peças que o arquivo 38 criou)
	local fumacas: { ParticleEmitter } = {}
	if modelo then
		for _, objeto in modelo:GetDescendants() do
			if objeto:IsA("ParticleEmitter") and objeto.Name == "MonstroFumaca" then
				table.insert(fumacas, objeto)
			end
		end
	end
	-- a câmera mais longe
	local zoomAntes: number? = nil
	if jogador then
		zoomAntes = jogador.CameraMinZoomDistance
		jogador.CameraMinZoomDistance = math.max(ZOOM_MINIMO, jogador.CameraMinZoomDistance)
	end
	-- o botão do pulo (no celular aparece um botão na tela)
	ContextActionService:BindAction("MonstroPulo", acaoDoPulo, true, TECLA_DO_PULO, BOTAO_DO_CONTROLE)
	ContextActionService:SetTitle("MonstroPulo", "PULO")
	local barra, enchimento = criarBarra()
	return {
		quad = quad,
		chassi = chassi,
		rodas = rodas,
		pecas = pecas,
		forca = forca,
		anexoDaForca = anexo,
		filtro = filtro,
		massaTotal = massaTotal,
		massaDoChassi = chassi.AssemblyMass,
		rodasNoChao = 0,
		carregando = false,
		inicioDaCarga = 0,
		carga = 0,
		puloPronto = 0,
		tempoNoAr = 0,
		giroFrente = 0,
		giroLado = 0,
		mexeuNoAr = false,
		zoomAntes = zoomAntes,
		barra = barra,
		enchimento = enchimento,
		fumacas = fumacas,
	}
end

-- Parou de dirigir: tira a força, o botão e a barrinha, e a câmera volta ao normal.
local function desligar()
	local atual = estado
	estado = nil
	if atual == nil then
		return
	end
	ContextActionService:UnbindAction("MonstroPulo")
	atual.forca:Destroy()
	atual.anexoDaForca:Destroy()
	local barra = atual.barra
	if barra then
		barra:Destroy()
	end
	for _, fumaca in atual.fumacas do
		fumaca.Rate = 4 -- (a fumacinha de sempre)
	end
	local jogador = Players.LocalPlayer
	local zoomAntes = atual.zoomAntes
	if jogador and zoomAntes then
		jogador.CameraMinZoomDistance = zoomAntes
	end
end

-- =====================================================================
-- A CADA FRAME (o QuadricicloCliente chama isto enquanto você dirige)
-- =====================================================================
-- (NOVO) No ar, a tecla que você já segurava no chão não dá mortal: solte e aperte de novo.
local soltouFrente = false -- já soltou o W/S neste pulo?
local soltouLado = false -- já soltou o A/D neste pulo?
local ultimoFrameNoAr = 0 -- (os.clock) a última vez que ele estava no ar
function Monstro.atualizar(quad: any, dt: number, pedal: number?, volante: number?)
	ultimaAtualizacao = os.clock()
	local modelo = comoInstancia(quad.modelo)
	local ativo = modelo ~= nil and (not SO_NO_MONSTRO or modelo:GetAttribute("Monstro") == true)
	-- Trocou de veículo (ou ele sumiu)? Desliga o velho.
	local velho = estado
	if velho and (not ativo or velho.quad ~= quad or velho.chassi.Parent == nil) then
		desligar()
	end
	if not ativo then
		return
	end
	if estado == nil then
		estado = ligar(quad)
	end
	local atual = estado
	if atual == nil then
		return
	end
	local acelerador = pedal or 0
	local virar = volante or 0
	local chassi = atual.chassi
	local referencia: CFrame = Veiculo.referencia(quad)
	local cima = referencia.UpVector

	-- 1) QUANTAS RODAS ESTÃO NO CHÃO? (um raio curto para "baixo", saindo do meio de cada roda)
	local noChao = 0
	for _, roda in atual.rodas do
		if workspace:Raycast(roda.roda.Position, -cima * (roda.raio + 0.8), atual.filtro) then
			noChao += 1
		end
	end
	atual.rodasNoChao = noChao
	-- Pendurado no gancho? (aí o balanço é quem manda)
	local puxador = chassi:FindFirstChild("BalancoGancho")
	local pendurado = puxador ~= nil and puxador:IsA("AlignPosition") and puxador.Enabled

	-- 2) CARREGANDO O PULO: a carga sobe e ele AGACHA nas molas
	local agachar = Vector3.zero
	if atual.carregando then
		atual.carga = math.clamp((os.clock() - atual.inicioDaCarga) / TEMPO_DE_CARGA, 0, 1)
		if noChao >= 3 then
			agachar = -cima * (atual.massaDoChassi * AGACHAR * atual.carga)
		end
	end
	local barra, enchimento = atual.barra, atual.enchimento
	if barra and enchimento then
		barra.Enabled = atual.carregando
		enchimento.Size = UDim2.fromScale(atual.carga, 1)
		enchimento.BackgroundColor3 = if atual.carga >= 1 then Color3.fromRGB(255, 210, 60) else Color3.fromRGB(150, 70, 255)
	end

	-- 3) NO AR: mais leve, e as teclas dão mortal
	local leveza = Vector3.zero
	if noChao == 0 and not pendurado then
		atual.tempoNoAr += dt
		if LEVEZA_NO_AR > 0 then
			leveza = Vector3.new(0, atual.massaTotal * workspace.Gravity * LEVEZA_NO_AR, 0)
		end
		if atual.tempoNoAr > 0.15 then
			-- (NOVO) começou um pulo agora? As teclas que já estavam apertadas só valem depois de soltar
			if os.clock() - ultimoFrameNoAr > 0.1 then
				soltouFrente = false
				soltouLado = false
			end
			ultimoFrameNoAr = os.clock()
			if math.abs(acelerador) < 0.1 then
				soltouFrente = true
			end
			if math.abs(virar) < 0.1 then
				soltouLado = true
			end
			local girarFrente = soltouFrente and math.abs(acelerador) > 0.1
			local girarLado = soltouLado and math.abs(virar) > 0.1
			if girarFrente or girarLado then
				atual.mexeuNoAr = true
				soltarEndireitador(chassi)
			end
			if girarFrente then
				girarNoAr(atual, referencia.RightVector, -acelerador * GIRO_NO_AR, dt) -- W = mortal para frente
			end
			if girarLado then
				girarNoAr(atual, referencia.LookVector, virar * GIRO_NO_AR, dt) -- D = giro para a direita
			end
		end
		-- conta quanto ele já girou neste pulo
		local giro = chassi.AssemblyAngularVelocity
		atual.giroFrente += giro:Dot(referencia.RightVector) * dt
		atual.giroLado += giro:Dot(referencia.LookVector) * dt
	elseif noChao > 0 then
		if atual.tempoNoAr > 0.35 and atual.mexeuNoAr then
			aterrissou(atual, referencia)
		end
		atual.tempoNoAr = 0
		atual.giroFrente = 0
		atual.giroLado = 0
		atual.mexeuNoAr = false
	end
	atual.forca.Force = leveza + agachar

	-- 4) ESCAPAMENTO: mais fumaça acelerando (e carregando o pulo)
	local fumacaAgora = 4 + 30 * math.max(acelerador, 0) + (if atual.carregando then 20 else 0)
	for _, fumaca in atual.fumacas do
		fumaca.Rate = fumacaAgora
	end
end

-- Se o QuadricicloCliente parou de chamar o atualizar (saiu do banco), desliga tudo.
RunService.Heartbeat:Connect(function()
	if estado and os.clock() - ultimaAtualizacao > 1 then
		desligar()
	end
end)

return Monstro

