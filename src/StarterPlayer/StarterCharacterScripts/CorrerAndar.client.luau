--!strict
--[[
	=====================================================================
	CorrerAndar  (LocalScript)
	Local: StarterPlayer > StarterCharacterScripts > CorrerAndar
	=====================================================================

	A PÉ, o personagem ANDA (animação de andar, mais devagar) e, segurando o SHIFT, CORRE (animação de
	correr, mais rápido). A troca é suave: a velocidade vai subindo e a animação acompanha os pés.
	  - Computador ... segure SHIFT para correr.
	  - Controle ..... aperte o analógico esquerdo (L3) para correr. Parou de andar, volta a andar.
	  - Celular ...... botão CORRER (em cima do botão de pulo): liga e desliga. Parou, desliga sozinho.
	  - Dirigindo, nada disso vale (no veículo, o Shift é o nitro).
	  - A "trava do mouse" do Roblox (Shift Lock) passa para o CTRL, para não brigar com o correr.
	As animações são as do PRÓPRIO personagem (as do Roblox ou o pacote de animações do jogador). Quer
	outras? Coloque os IDs nos AJUSTES. Por ficar no StarterCharacterScripts, este script recomeça
	sozinho toda vez que o personagem renasce.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- (o mesmo módulo dos HUDs: diz se o jogador está jogando pelo toque)
local Tela = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Tela"))

-- =====================================================================
-- AJUSTES
-- =====================================================================
local VELOCIDADE_ANDANDO = 10 -- (studs/s) andando, sem o Shift (o padrão do Roblox é 16)
local VELOCIDADE_CORRENDO = 24 -- (studs/s) correndo, com o Shift
local ACELERACAO = 60 -- (studs/s²) quão rápido passa de andar para correr (e de volta)
local TRAVA_DO_MOUSE_NO_CTRL = true -- true = o Shift Lock do Roblox passa para o Ctrl
local PARADO_DESLIGA = 0.6 -- (s) no controle e no celular: parado esse tempo, o correr desliga sozinho
-- As animações. "" = a do próprio personagem. Quer a sua? Cole o ID ("rbxassetid://123..."): a
-- animação precisa ser sua, do seu grupo ou do Roblox (senão o Roblox não deixa tocar).
local ANIMACAO_ANDAR = ""
local ANIMACAO_CORRER = ""
-- O "ritmo" = em que velocidade (studs/s) os pés da animação acompanham o chão. Andando mais rápido,
-- a animação acelera na mesma proporção (assim os pés não escorregam). Animação sua com os pés
-- escorregando? Mude o ritmo dela até encaixar.
local RITMO_ANDAR_R15 = 6.4 -- (o mesmo que o script "Animate" do Roblox usa)
local RITMO_CORRER_R15 = 12.8
local RITMO_R6 = 14.5 -- (o R6 do Roblox tem uma animação só, de andar: correndo, ela só fica mais rápida)

-- =====================================================================
-- O PERSONAGEM E AS ANIMAÇÕES
-- =====================================================================
local jogador = Players.LocalPlayer :: Player
-- (no Explorer o script fica no StarterCharacterScripts; jogando, o Roblox copia ele para DENTRO do
-- personagem. O "::any" avisa isso ao verificador de tipos do Studio, que só vê o lugar do Explorer.)
local personagem = (script.Parent :: any) :: Model
local humanoide = personagem:WaitForChild("Humanoid") :: Humanoid
local raiz = personagem:WaitForChild("HumanoidRootPart") :: BasePart
local animador = humanoide:WaitForChild("Animator") :: Animator

local ehR6 = humanoide.RigType == Enum.HumanoidRigType.R6
-- (personagem maior = passos maiores: o ritmo cresce junto, como no "Animate" do Roblox)
local escalaDaAltura = if not ehR6 and humanoide.AutomaticScalingEnabled then math.max(humanoide.HipHeight / 2, 0.1) else 1

-- A Animation do próprio personagem (dentro do script "Animate": walk › WalkAnim, run › RunAnim...).
local function animacaoDoPersonagem(nome: string): Animation?
	local animate = personagem:WaitForChild("Animate", 5)
	local pasta = if animate then animate:WaitForChild(nome, 5) else nil
	return if pasta then pasta:FindFirstChildOfClass("Animation") else nil
end
local andarDoPersonagem = animacaoDoPersonagem("walk")
local correrDoPersonagem = if ehR6 then nil else animacaoDoPersonagem("run")

local trilhaAndar: AnimationTrack? = nil
local trilhaCorrer: AnimationTrack? = nil
local trilhaAtual: AnimationTrack? = nil

local function carregar(id: string): AnimationTrack?
	if id == "" then
		return nil
	end
	local animacao = Instance.new("Animation")
	animacao.AnimationId = id
	local trilha = animador:LoadAnimation(animacao)
	trilha.Priority = Enum.AnimationPriority.Movement -- (por cima das animações padrão, que são "Core")
	trilha.Looped = true
	return trilha
end

-- (Re)carrega as duas animações. Roda de novo se o Roblox trocar as do personagem depois (pacote de
-- animações do jogador chegando um pouco depois de ele nascer).
local function recarregar()
	for _, trilha in { trilhaAndar, trilhaCorrer } do
		if trilha then
			trilha:Stop(0)
			trilha:Destroy()
		end
	end
	trilhaAtual = nil
	local andar = if ANIMACAO_ANDAR ~= "" then ANIMACAO_ANDAR
		elseif andarDoPersonagem then andarDoPersonagem.AnimationId
		else ""
	local correr = if ANIMACAO_CORRER ~= "" then ANIMACAO_CORRER
		elseif correrDoPersonagem then correrDoPersonagem.AnimationId
		else andar -- (sem animação de correr: usa a de andar, mais rápida)
	trilhaAndar = carregar(andar)
	trilhaCorrer = carregar(correr)
end
recarregar()
for _, animacao in { andarDoPersonagem, correrDoPersonagem } do
	if animacao then
		animacao:GetPropertyChangedSignal("AnimationId"):Connect(recarregar)
	end
end

-- Troca a animação que está tocando (nil = nenhuma: o "Animate" do Roblox mostra a dele, parado).
local function tocar(trilha: AnimationTrack?)
	if trilha == trilhaAtual then
		return
	end
	local antes = trilhaAtual
	if antes then
		antes:Stop(0.25)
	end
	if trilha then
		trilha:Play(0.25)
	end
	trilhaAtual = trilha
end

-- =====================================================================
-- OS BOTÕES: Shift (segurar), L3 do controle e o botão do celular (ligar/desligar)
-- =====================================================================
local shiftSegurado = false
local modoCorrida = false -- (controle e celular: liga e desliga apertando)
local paradoHa = 0 -- (s) há quanto tempo está parado

-- Prioridade: acima da trava do mouse do Roblox (Medium) e abaixo das teclas do veículo (High).
local PRIORIDADE = Enum.ContextActionPriority.High.Value - 1
-- (um nome por personagem: o do personagem novo não é desligado pelo velho, que some depois)
local ACAO_CORRER = "CorrerAPe" .. string.format("%.4f", os.clock())
ContextActionService:BindActionAtPriority(ACAO_CORRER, function(_nome: string, estado: Enum.UserInputState, entrada: InputObject): Enum.ContextActionResult?
	if humanoide.Sit then
		return Enum.ContextActionResult.Pass -- (sentado no veículo: o Shift é do nitro)
	end
	if entrada.KeyCode == Enum.KeyCode.ButtonL3 then
		if estado == Enum.UserInputState.Begin then
			modoCorrida = not modoCorrida
		end
	else
		shiftSegurado = estado == Enum.UserInputState.Begin
	end
	return Enum.ContextActionResult.Sink
end, false, PRIORIDADE, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)

-- O Shift Lock do Roblox vai para o Ctrl (é o jeito que o próprio Roblox deixa trocar a tecla dele).
if TRAVA_DO_MOUSE_NO_CTRL then
	task.spawn(function()
		local modulo = jogador:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		local camera = if modulo then modulo:WaitForChild("CameraModule", 10) else nil
		local trava = if camera then camera:WaitForChild("MouseLockController", 10) else nil
		local teclas = if trava then trava:WaitForChild("BoundKeys", 10) else nil
		if teclas and teclas:IsA("StringValue") then
			teclas.Value = "LeftControl,RightControl"
		end
	end)
end

-- CELULAR: o botão CORRER, em cima do botão de pulo do Roblox (só a pé e só jogando pelo toque).
local playerGui = jogador:WaitForChild("PlayerGui") :: PlayerGui
local telaDoBotao = Instance.new("ScreenGui")
telaDoBotao.Name = "BotaoCorrer"
telaDoBotao.ResetOnSpawn = true -- (some quando o personagem renasce: o novo cria o dele)
telaDoBotao.Parent = playerGui
local botao = Instance.new("TextButton")
botao.Name = "Correr"
botao.AnchorPoint = Vector2.new(0.5, 1)
botao.Position = UDim2.new(1, -60, 1, -110) -- (até achar o botão de pulo)
botao.Size = UDim2.fromOffset(56, 56)
botao.BackgroundColor3 = Color3.new(0, 0, 0)
botao.BackgroundTransparency = 0.45
botao.AutoButtonColor = false
botao.Font = Enum.Font.GothamBlack
botao.Text = "CORRER"
botao.TextSize = 11 -- (tamanho fixo: cabe numa linha, sem quebrar a palavra)
botao.TextColor3 = Color3.new(1, 1, 1)
botao.Visible = false
botao.Parent = telaDoBotao
local canto = Instance.new("UICorner")
canto.CornerRadius = UDim.new(1, 0)
canto.Parent = botao
local borda = Instance.new("UIStroke")
borda.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
borda.Thickness = 2
borda.Color = Color3.new(1, 1, 1)
borda.Transparency = 0.3
borda.Parent = botao
botao.Activated:Connect(function()
	modoCorrida = not modoCorrida
end)

local botaoAceso = false -- (o botão está pintado de "ligado"?)
local botaoDePulo: GuiObject? = nil
local function posicionarBotao()
	local pulo = botaoDePulo
	if pulo == nil or pulo.Parent == nil then
		local toque = playerGui:FindFirstChild("TouchGui")
		local achado = if toque then toque:FindFirstChild("JumpButton", true) else nil
		pulo = if achado and achado:IsA("GuiObject") then achado else nil
		botaoDePulo = pulo
	end
	if pulo and pulo.AbsoluteSize.X > 0 then
		local origem = telaDoBotao.AbsolutePosition
		local posicao = UDim2.fromOffset(
			math.floor(pulo.AbsolutePosition.X + pulo.AbsoluteSize.X / 2 - origem.X),
			math.floor(pulo.AbsolutePosition.Y - 10 - origem.Y)
		)
		if botao.Position ~= posicao then
			botao.Position = posicao
		end
	end
end

-- =====================================================================
-- A CADA FRAME: a velocidade, a animação e o botão do celular
-- =====================================================================
local conexao = RunService.Heartbeat:Connect(function(dt: number)
	local sentado = humanoide.Sit
	if sentado then
		shiftSegurado = false -- (entrou no veículo segurando o Shift: ao sair, só corre se apertar de novo)
		modoCorrida = false
	elseif shiftSegurado and not (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then
		shiftSegurado = false -- (soltou o Shift sem a gente ver: por exemplo, com a janela fora de foco)
	end

	-- 1) ANDANDO? (no chão, querendo andar e andando de verdade)
	local estado = humanoide:GetState()
	local noChao = estado == Enum.HumanoidStateType.Running or estado == Enum.HumanoidStateType.RunningNoPhysics
	local movimento = raiz.AssemblyLinearVelocity
	local velocidade = Vector3.new(movimento.X, 0, movimento.Z).Magnitude
	local andando = not sentado and noChao and humanoide.MoveDirection.Magnitude > 0.05 and velocidade > 0.5
	if andando then
		paradoHa = 0
	else
		paradoHa += dt
		if paradoHa > PARADO_DESLIGA then
			modoCorrida = false
		end
	end

	-- 2) A VELOCIDADE vai subindo (ou descendo) até a de andar ou a de correr
	if not sentado then
		local alvo = if shiftSegurado or modoCorrida then VELOCIDADE_CORRENDO else VELOCIDADE_ANDANDO
		local atual = humanoide.WalkSpeed
		if atual ~= alvo then
			local passo = ACELERACAO * dt
			humanoide.WalkSpeed = if math.abs(alvo - atual) <= passo then alvo else atual + math.sign(alvo - atual) * passo
		end
	end

	-- 3) A ANIMAÇÃO: a de correr acima da metade do caminho entre andar e correr; a velocidade dela
	--    acompanha a do personagem (analógico pela metade = mais devagar).
	local meio = (VELOCIDADE_ANDANDO + VELOCIDADE_CORRENDO) / 2
	local trilha = if not andando then nil elseif velocidade > meio then trilhaCorrer else trilhaAndar
	tocar(trilha)
	if trilha then
		local ritmo = if ehR6 then RITMO_R6 elseif trilha == trilhaCorrer then RITMO_CORRER_R15 else RITMO_ANDAR_R15
		trilha:AdjustSpeed(velocidade / (ritmo * escalaDaAltura))
	end

	-- 4) O BOTÃO DO CELULAR
	local mostrar = not sentado and humanoide.Health > 0 and Tela.noToque() and GuiService.TouchControlsEnabled
	if botao.Visible ~= mostrar then
		botao.Visible = mostrar
	end
	if mostrar then
		posicionarBotao()
		if botaoAceso ~= modoCorrida then -- (ligado = verde)
			botaoAceso = modoCorrida
			botao.BackgroundColor3 = if modoCorrida then Color3.fromRGB(70, 200, 110) else Color3.new(0, 0, 0)
			botao.BackgroundTransparency = if modoCorrida then 0.15 else 0.45
		end
	end
end)

-- O personagem sumiu (morreu e renasceu, saiu do jogo): desliga tudo deste personagem.
script.Destroying:Connect(function()
	conexao:Disconnect()
	ContextActionService:UnbindAction(ACAO_CORRER)
	telaDoBotao:Destroy()
end)
