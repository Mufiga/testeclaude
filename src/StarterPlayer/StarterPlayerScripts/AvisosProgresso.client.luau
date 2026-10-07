--!strict
--[[
	=====================================================================
	AvisosProgresso  (LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > AvisosProgresso
	=====================================================================

	A parte da TELA do sistema de progresso (quem manda os avisos é o script Progresso, no servidor):
	  - "CHECKPOINT 3!" e "+10 $" quando você chega num checkpoint novo;
	  - "+1 $" e um brilho dourado quando você pega uma moeda. A moeda some SÓ para você e volta
	    depois (os outros jogadores continuam vendo e podem pegar a deles);
	  - os checkpoints que você já passou ficam verdes (só na sua tela);
	  - as moedas ficam girando e flutuando.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local jogador = Players.LocalPlayer :: Player
local aviso = ReplicatedStorage:WaitForChild("AvisoProgresso") :: RemoteEvent

-- =====================================================================
-- AJUSTES
-- =====================================================================
local TAG_CHECKPOINT = "Checkpoint"
local TAG_MOEDA = "Moeda"
local COR_CHECKPOINT = Color3.fromRGB(80, 255, 120) -- verde
local COR_DINHEIRO = Color3.fromRGB(255, 215, 70) -- dourado
local COR_ERRO = Color3.fromRGB(255, 90, 90) -- vermelho
local SOM_MOEDA = "" -- (opcional) "rbxassetid://..." de um som de moeda
local SOM_CHECKPOINT = "" -- (opcional) "rbxassetid://..." de um som de conquista
local GIRO_DA_MOEDA = 2 -- (radianos/s) velocidade do giro das moedas
local DISTANCIA_DAS_MOEDAS = 300 -- (studs) só as moedas perto da câmera giram (as longe ficam paradas: economiza)

-- =====================================================================
-- MENSAGENS NA TELA
-- =====================================================================
local tela = Instance.new("ScreenGui")
tela.Name = "AvisosProgresso"
tela.ResetOnSpawn = false
tela.DisplayOrder = 20 -- por cima dos outros HUDs
tela.Parent = jogador:WaitForChild("PlayerGui")

-- Um texto que "pula" no meio de cima da tela, sobe um pouquinho e some.
-- altura = a distância do topo da tela (assim dois avisos não ficam um em cima do outro).
local function mostrarTexto(texto: string, cor: Color3, tamanho: number, altura: number)
	local etiqueta = Instance.new("TextLabel")
	etiqueta.AnchorPoint = Vector2.new(0.5, 0)
	etiqueta.Position = UDim2.new(0.5, 0, 0, altura)
	etiqueta.Size = UDim2.fromOffset(0, tamanho)
	etiqueta.AutomaticSize = Enum.AutomaticSize.X -- a largura vem do texto
	etiqueta.BackgroundTransparency = 1
	etiqueta.Font = Enum.Font.GothamBlack
	etiqueta.Text = texto
	etiqueta.TextSize = tamanho
	etiqueta.TextColor3 = cor
	etiqueta.TextStrokeTransparency = 0.25 -- contorno escuro: dá para ler em qualquer fundo
	local escala = Instance.new("UIScale")
	escala.Scale = 0.3 -- começa pequeno...
	escala.Parent = etiqueta
	etiqueta.Parent = tela
	TweenService:Create(escala, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play() -- ...e "pula"
	task.delay(1.3, function()
		local sumir = TweenService:Create(etiqueta, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, altura - 30), -- sobe enquanto some
		})
		sumir:Play()
		sumir.Completed:Wait()
		etiqueta:Destroy()
	end)
end

-- Toca um som (se você colocou o ID dele nos AJUSTES).
local function tocar(id: string)
	if id == "" then
		return
	end
	local som = Instance.new("Sound")
	som.SoundId = id
	som.Volume = 0.6
	som.Parent = tela
	som:Play()
	som.Ended:Once(function()
		som:Destroy()
	end)
end

-- =====================================================================
-- CHECKPOINTS JÁ PASSADOS FICAM VERDES (só na sua tela)
-- =====================================================================
local coresOriginais: { [BasePart]: Color3 } = setmetatable({}, { __mode = "k" }) :: any

-- Um número (também aceita número escrito como TEXTO, ex.: "1"), ou nil.
local function comoNumero(valor: unknown): number?
	if typeof(valor) == "number" then
		return valor
	elseif typeof(valor) == "string" then
		return tonumber(valor)
	end
	return nil
end

local function pintarCheckpoints()
	local passado = comoNumero(jogador:GetAttribute("Checkpoint")) or 0 -- (o servidor guarda aqui o seu último checkpoint)
	for _, objeto in CollectionService:GetTagged(TAG_CHECKPOINT) do
		if objeto:IsA("BasePart") then
			local original = coresOriginais[objeto] or objeto.Color
			coresOriginais[objeto] = original
			local numeroDele = comoNumero(objeto:GetAttribute("Numero"))
			objeto.Color = if numeroDele and numeroDele <= passado then COR_CHECKPOINT else original
		end
	end
end
jogador:GetAttributeChangedSignal("Checkpoint"):Connect(pintarCheckpoints)
CollectionService:GetInstanceAddedSignal(TAG_CHECKPOINT):Connect(pintarCheckpoints) -- (checkpoints que chegam depois)
pintarCheckpoints()

-- =====================================================================
-- MOEDAS: girando e flutuando, e somem (só para você) quando você pega
-- =====================================================================
local lugarDasMoedas: { [BasePart]: CFrame } = {} -- o lugar "parado" de cada moeda
local escondidas: { [BasePart]: boolean } = {}

local function verMoeda(objeto: Instance)
	if objeto:IsA("BasePart") and objeto.Anchored then
		lugarDasMoedas[objeto] = objeto.CFrame
	end
end
for _, objeto in CollectionService:GetTagged(TAG_MOEDA) do
	verMoeda(objeto)
end
CollectionService:GetInstanceAddedSignal(TAG_MOEDA):Connect(verMoeda)
CollectionService:GetInstanceRemovedSignal(TAG_MOEDA):Connect(function(objeto: Instance)
	if objeto:IsA("BasePart") then
		lugarDasMoedas[objeto] = nil
	end
end)

-- A cada frame: cada moeda gira em volta do "de pé" e sobe e desce um pouquinho.
-- (OTIMIZADO) Só as moedas perto da câmera (e que não estão escondidas), e todas de uma vez só
-- (workspace:BulkMoveTo é bem mais rápido que mudar o CFrame de uma por uma).
local moedasParaMover: { BasePart } = {}
local lugaresNovos: { CFrame } = {}
RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local daCamera = camera.CFrame.Position
	local agora = os.clock()
	local flutuar = Vector3.new(0, math.sin(agora * 2) * 0.3, 0)
	local giro = CFrame.Angles(0, agora * GIRO_DA_MOEDA, 0)
	local quantas = 0
	for moeda, lugar in lugarDasMoedas do
		if not escondidas[moeda] and (lugar.Position - daCamera).Magnitude <= DISTANCIA_DAS_MOEDAS then
			quantas += 1
			moedasParaMover[quantas] = moeda
			lugaresNovos[quantas] = CFrame.new(lugar.Position + flutuar) * giro * lugar.Rotation
		end
	end
	for i = #moedasParaMover, quantas + 1, -1 do -- (tira as sobras da vez passada)
		moedasParaMover[i] = nil
		lugaresNovos[i] = nil
	end
	if quantas > 0 then
		workspace:BulkMoveTo(moedasParaMover, lugaresNovos, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)

-- Pegou a moeda: um brilho dourado no lugar e ela some SÓ para você, por "segundos".
local function esconderMoeda(moeda: BasePart, segundos: number)
	if escondidas[moeda] then
		return
	end
	escondidas[moeda] = true
	-- O brilho: estrelinhas douradas espirrando para todo lado.
	local anexo = Instance.new("Attachment")
	anexo.Parent = workspace.Terrain
	anexo.WorldPosition = moeda.Position
	local brilho = Instance.new("ParticleEmitter")
	brilho.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	brilho.Color = ColorSequence.new(COR_DINHEIRO)
	brilho.LightEmission = 1
	brilho.Size = NumberSequence.new(0.7, 0)
	brilho.Lifetime = NumberRange.new(0.3, 0.6)
	brilho.Speed = NumberRange.new(6, 12)
	brilho.SpreadAngle = Vector2.new(180, 180)
	brilho.Enabled = false
	brilho.Parent = anexo
	brilho:Emit(14)
	task.delay(1, function()
		anexo:Destroy()
	end)
	-- Some só na sua tela (LocalTransparencyModifier = transparência que só você vê).
	moeda.LocalTransparencyModifier = 1
	local emissores: { ParticleEmitter } = {}
	local luzes: { Light } = {}
	for _, filho in moeda:GetDescendants() do
		if filho:IsA("ParticleEmitter") and filho.Enabled then
			filho.Enabled = false
			table.insert(emissores, filho)
		elseif filho:IsA("Light") and filho.Enabled then
			filho.Enabled = false
			table.insert(luzes, filho)
		end
	end
	task.delay(segundos, function()
		escondidas[moeda] = nil
		moeda.LocalTransparencyModifier = 0 -- voltou!
		for _, emissor in emissores do
			emissor.Enabled = true
		end
		for _, luz in luzes do
			luz.Enabled = true
		end
	end)
end

-- =====================================================================
-- OS AVISOS QUE O SERVIDOR MANDA
-- =====================================================================
aviso.OnClientEvent:Connect(function(tipo: unknown, a: unknown, b: unknown, c: unknown)
	if tipo == "Checkpoint" and typeof(a) == "number" then
		mostrarTexto(`CHECKPOINT {a}!`, COR_CHECKPOINT, 34, 70)
		if typeof(b) == "number" and b > 0 then
			mostrarTexto(`+{b} $`, COR_DINHEIRO, 24, 112)
		end
		tocar(SOM_CHECKPOINT)
	elseif tipo == "Moeda" and typeof(a) == "Instance" and a:IsA("BasePart") then
		local valor = if typeof(b) == "number" then b else 1
		local segundos = if typeof(c) == "number" then c else 60
		esconderMoeda(a, segundos)
		mostrarTexto(`+{valor} $`, COR_DINHEIRO, 24, 112)
		tocar(SOM_MOEDA)
	elseif tipo == "Erro" and typeof(a) == "string" then
		mostrarTexto(a, COR_ERRO, 18, 150)
	end
end)

