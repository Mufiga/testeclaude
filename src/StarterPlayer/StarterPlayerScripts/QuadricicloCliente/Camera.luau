--!strict
--[[
	=====================================================================
	Camera  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Camera
	=====================================================================

	Câmera cíclica (tecla C / botão Y / botão CÂMERA no celular):
	  1 = a câmera normal do Roblox
	  2 = afastada (Config.CameraExtraDistance studs mais longe)
	  3 = capô (no Attachment "CameraCapo" do quadriciclo, se existir)
	A câmera de MIRA do gancho (ombro direito e olhar em volta no capô)
	fica no módulo Gancho.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService") -- (NOVO) para travar o mouse
local TweenService = game:GetService("TweenService") -- (NOVO) anima o aviso do mouse (aparecer e sumir)

local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
local BotoesDoCelular = require(script.Parent:WaitForChild("BotoesDoCelular")) -- (NOVO) os botões da tela no celular
type Quadriciclo = Veiculo.Quadriciclo

local Camera = {}

local jogadorLocal = Players.LocalPlayer :: Player

local ACAO_CAMERA = "QuadricicloCamera"
local CAMERA_CAPO = "QuadricicloCameraCapo" -- nome da tarefa da câmera do capô (BindToRenderStep)

local distanciaPadrao = 12.5 -- o zoom que você usava (medido quando sai do modo 1)
local zoomMinimo, zoomMaximo = 0.5, 400 -- seus limites de zoom (salvos ao sentar)
local anexoCapo: Attachment? = nil -- Attachment opcional "CameraCapo": posição da câmera do capô
local rotacaoCapo = CFrame.identity

local function definirLimitesZoom(minimo: number, maximo: number)
	if minimo > jogadorLocal.CameraMaxZoomDistance then
		jogadorLocal.CameraMaxZoomDistance = maximo
		jogadorLocal.CameraMinZoomDistance = minimo
	else
		jogadorLocal.CameraMinZoomDistance = minimo
		jogadorLocal.CameraMaxZoomDistance = maximo
	end
end

local function levarZoomPara(distancia: number)
	definirLimitesZoom(distancia, distancia)
	task.delay(0.1, definirLimitesZoom, zoomMinimo, zoomMaximo)
end

local function atualizarCameraCapo(quad: Quadriciclo, dt: number)
	local referencia = Veiculo.referencia(quad)
	local anexo = anexoCapo
	local posicao = if anexo then anexo.WorldPosition else referencia * quad.Config.HoodCameraOffset
	rotacaoCapo = rotacaoCapo:Lerp(referencia.Rotation, math.min(dt * 12, 1)) -- suaviza os trancos da suspensão
	Veiculo.cameraAtual().CFrame = CFrame.new(posicao) * rotacaoCapo
end

-- (NOVO) O tipo da câmera "normal" (modos 1 e 2) enquanto você dirige.
-- Com mouse (e Config.MouseCameraClassica ligado) usamos a "Track": é a câmera CLÁSSICA do Roblox,
-- que segue o mouse travado. A câmera de veículo padrão ("Custom") puxa sozinha para trás do
-- quadriciclo enquanto ele anda, e isso atrapalha quem quer olhar em volta com o mouse.
local function tipoDaCameraDirigindo(quad: Quadriciclo): Enum.CameraType
	if UserInputService.MouseEnabled and quad.Config.MouseCameraClassica ~= false then
		return Enum.CameraType.Track
	end
	return Enum.CameraType.Custom
end

local function aplicarModoCamera(quad: Quadriciclo, modo: number)
	local camera = Veiculo.cameraAtual()
	RunService:UnbindFromRenderStep(CAMERA_CAPO)
	if modo == 3 then
		rotacaoCapo = Veiculo.referencia(quad).Rotation
		camera.CameraType = Enum.CameraType.Scriptable -- agora quem move a câmera somos nós
		RunService:BindToRenderStep(CAMERA_CAPO, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			atualizarCameraCapo(quad, dt)
		end)
	else
		camera.CameraType = tipoDaCameraDirigindo(quad) -- (NOVO) a câmera do Roblox que segue o mouse
		levarZoomPara(if modo == 2 then distanciaPadrao + quad.Config.CameraExtraDistance else distanciaPadrao)
	end
end

local function trocarCamera(quad: Quadriciclo)
	if quad.modoCamera == 1 then
		local camera = Veiculo.cameraAtual()
		distanciaPadrao = (camera.CFrame.Position - camera.Focus.Position).Magnitude -- lembra o seu zoom
	end
	quad.modoCamera = quad.modoCamera % 3 + 1 -- 1 → 2 → 3 → 1...
	aplicarModoCamera(quad, quad.modoCamera)
end

-- =====================================================================
-- (NOVO) SENSAÇÃO DE VELOCIDADE (só para quem dirige)
-- =====================================================================
-- Bem rápido (impulso do gancho, descida longa...): a câmera "abre" (o campo de visão aumenta), riscos
-- brancos passam voando nas bordas da tela e a câmera treme de leve. Começa em
-- Config.EfeitoVelocidadeInicio e chega no máximo em Config.EfeitoVelocidadeMaximo. O "abrir" do
-- NITRO (Config.NitroFOVBonus) também é feito aqui, junto, para os dois não brigarem pela câmera.
local EFEITO_VELOCIDADE = "QuadricicloEfeitoVelocidade" -- nome da tarefa (BindToRenderStep)
local QUANTOS_RISCOS = 28
local fovNormal = 70 -- o campo de visão de antes de sentar (volta para ele quando você levanta)
local fovAgora = 70 -- o campo de visão de agora (vai suave até o alvo)
local forcaVelocidade = 0 -- 0 = sem efeito · 1 = efeito máximo (vai suave de um para o outro)
local tempoDosRiscos = 0 -- (s) os riscos trocam de lugar 25 vezes por segundo
local telaDosRiscos: ScreenGui? = nil
local riscos: { Frame } = {}
local sorteio = Random.new()
-- (NOVO) TREMOR DE IMPACTO: outro script pede um tremor rápido na tela (ex.: o quadriciclo caiu no chão
-- depois de desvirar). forca = quantos studs a câmera chacoalha no começo (0.3 já é bem forte).
local tremorImpacto = 0
function Camera.tremer(forca: number)
	tremorImpacto = math.max(tremorImpacto, forca)
end

-- Um número da Configuracao (ou o padrão, se a Configuracao não tiver esse valor).
local function numeroDaConfig(valor: unknown, padrao: number): number
	return if typeof(valor) == "number" then valor else padrao
end

-- Cria os riscos (ainda escondidos): retângulos brancos e finos, transparentes na ponta de dentro.
local function criarRiscos()
	local playerGui = jogadorLocal:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local tela = Instance.new("ScreenGui")
	tela.Name = "EfeitoVelocidade"
	tela.ResetOnSpawn = false
	tela.IgnoreGuiInset = true -- cobre a tela inteira (até a faixa de cima do Roblox)
	tela.DisplayOrder = -1 -- fica ATRÁS dos outros HUDs (velocímetro, barra de ganchos)
	tela.Enabled = false
	table.clear(riscos)
	for _ = 1, QUANTOS_RISCOS do
		local risco = Instance.new("Frame")
		risco.AnchorPoint = Vector2.new(0.5, 0.5)
		risco.BackgroundColor3 = Color3.new(1, 1, 1)
		risco.BorderSizePixel = 0
		risco.Parent = tela
		local degrade = Instance.new("UIGradient") -- some aos poucos na ponta que aponta para o meio da tela
		degrade.Transparency = NumberSequence.new(1, 0)
		degrade.Parent = risco
		table.insert(riscos, risco)
	end
	tela.Parent = playerGui
	telaDosRiscos = tela
end

-- Sorteia o lugar de cada risco: em volta da tela, deitado na direção do meio, só perto das bordas (o
-- meio fica livre para você ver o caminho e mirar). Quanto mais rápido, mais riscos e mais compridos.
-- "meio" = o meio da tela, em pixels.
local function sortearRiscos(forca: number, meio: Vector2)
	for i, risco in riscos do
		if sorteio:NextNumber() > 0.3 + forca * 0.6 then
			risco.Visible = false -- este risco "pisca" (fica apagado neste sorteio)
			continue
		end
		-- Cada risco tem a sua "fatia" da volta, com um pouco de sorte para não ficar certinho.
		local angulo = (i + sorteio:NextNumber(-0.45, 0.45)) / #riscos * math.pi * 2
		local direcao = Vector2.new(math.cos(angulo), math.sin(angulo))
		-- Distância do meio da tela até a borda, nesta direção:
		local borda = math.min(meio.X / math.max(math.abs(direcao.X), 0.001), meio.Y / math.max(math.abs(direcao.Y), 0.001))
		local dentro = borda * (0.85 - 0.35 * forca * sorteio:NextNumber(0.5, 1)) -- a ponta de dentro
		local fora = borda * 1.05 -- a ponta de fora (passa um pouco da borda)
		local centro = meio + direcao * (dentro + fora) / 2
		risco.Visible = true
		risco.Position = UDim2.fromOffset(centro.X, centro.Y)
		risco.Size = UDim2.fromOffset(fora - dentro, sorteio:NextNumber(1.5, 3.5))
		risco.Rotation = math.deg(angulo) -- deitado na direção do meio da tela
	end
end

local function atualizarEfeitoVelocidade(quad: Quadriciclo, dt: number)
	local Config = quad.Config
	local camera = Veiculo.cameraAtual()
	-- 0) (NOVO) CÂMERA MAIS BAIXA (modos 1 e 2): desce a câmera e o ponto que ela olha
	--    Config.CameraDescer studs (padrão 2). Roda logo depois da câmera do Roblox, a cada frame.
	if quad.modoCamera ~= 3 then
		local descer = Veiculo.referencia(quad).UpVector * numeroDaConfig(Config.CameraDescer, 2)
		camera.CFrame -= descer
		camera.Focus -= descer
	end
	-- 0b) (NOVO) TREMOR DE IMPACTO (Camera.tremer): forte no começo e some em menos de meio segundo.
	if tremorImpacto > 0.01 then
		local forca = tremorImpacto
		camera.CFrame *= CFrame.new(sorteio:NextNumber(-1, 1) * forca, sorteio:NextNumber(-1, 1) * forca, 0)
			* CFrame.Angles(0, 0, math.rad(sorteio:NextNumber(-1, 1) * forca * 3)) -- e entorta de leve
		tremorImpacto = forca * math.exp(-dt * 7) -- vai diminuindo sozinho
	else
		tremorImpacto = 0
	end
	-- 1) Quão rápido, de 0 a 1 (entre o "início" e o "máximo" da Configuracao), mudando suave.
	local inicio = numeroDaConfig(Config.EfeitoVelocidadeInicio, 45)
	local maximo = math.max(numeroDaConfig(Config.EfeitoVelocidadeMaximo, 100), inicio + 1)
	local rapidez = quad.chassi.AssemblyLinearVelocity.Magnitude
	local alvo = math.clamp((rapidez - inicio) / (maximo - inicio), 0, 1)
	forcaVelocidade += (alvo - forcaVelocidade) * math.min(dt * 4, 1)

	-- 2) A câmera ABRE: um pouco no nitro e mais ainda com a velocidade.
	local nitro = if quad.nitroAtivo then numeroDaConfig(Config.NitroFOVBonus, 0) else 0
	local fovAlvo = fovNormal + nitro + forcaVelocidade * numeroDaConfig(Config.EfeitoVelocidadeFOV, 20)
	fovAgora += (fovAlvo - fovAgora) * math.min(dt * 6, 1)
	camera.FieldOfView = math.clamp(fovAgora, 1, 120)

	-- 3) Os RISCOS nas bordas.
	local tela = telaDosRiscos
	if tela then
		local ligados = Config.EfeitoVelocidadeRiscos ~= false and forcaVelocidade > 0.03
		tela.Enabled = ligados
		if ligados then
			for _, risco in riscos do
				risco.BackgroundTransparency = 1 - forcaVelocidade * 0.6 -- mais rápido = mais forte
			end
			tempoDosRiscos += dt
			if tempoDosRiscos >= 0.04 then
				tempoDosRiscos = 0
				sortearRiscos(forcaVelocidade, camera.ViewportSize / 2)
			end
		end
	end

	-- 4) A TREMIDINHA: mexe a câmera um tiquinho para os lados (só o lugar, não para onde ela olha).
	local tremida = numeroDaConfig(Config.EfeitoVelocidadeTremida, 0.12) * forcaVelocidade
	if tremida > 0.001 then
		camera.CFrame *= CFrame.new(sorteio:NextNumber(-1, 1) * tremida, sorteio:NextNumber(-1, 1) * tremida, 0)
	end
end

local function ligarEfeitoVelocidade(quad: Quadriciclo)
	fovNormal = Veiculo.cameraAtual().FieldOfView
	fovAgora = fovNormal
	forcaVelocidade = 0
	criarRiscos()
	-- Roda DEPOIS da câmera do Roblox, da câmera do capô (+1) e da câmera de mira do gancho (+2).
	RunService:BindToRenderStep(EFEITO_VELOCIDADE, Enum.RenderPriority.Camera.Value + 3, function(dt: number)
		atualizarEfeitoVelocidade(quad, dt)
	end)
end

local function desligarEfeitoVelocidade()
	RunService:UnbindFromRenderStep(EFEITO_VELOCIDADE)
	Veiculo.cameraAtual().FieldOfView = fovNormal -- volta o campo de visão de antes
	local tela = telaDosRiscos
	if tela then
		tela:Destroy()
	end
	telaDosRiscos = nil
	table.clear(riscos)
end


-- =====================================================================
-- (NOVO) MOUSE TRAVADO (estilo Shift-Lock) — só para quem joga com mouse
-- =====================================================================
-- Dirigindo, o mouse fica PRESO no meio da tela e escondido: mexer o mouse já gira a câmera, sem
-- clicar e arrastar. A tecla LeftAlt alterna entre "mouse travado" e "mouse livre" (para clicar em
-- botões da tela). Mirando o gancho (botão direito), o mouse fica travado mesmo no modo livre.
-- No canto de cima, à direita, um aviso grande com o desenho de um mouse mostra como ele está.
local ACAO_TRAVAR_MOUSE = "QuadricicloTravarMouse" -- a tecla LeftAlt
local TRAVA_DO_MOUSE = "QuadricicloTravaDoMouse" -- nome da tarefa (BindToRenderStep)
local COR_MOUSE_TRAVADO = Color3.fromRGB(80, 255, 120) -- verde: a câmera segue o mouse
local COR_MOUSE_LIVRE = Color3.fromRGB(255, 200, 60) -- amarelo: o cursor está livre
local COR_RISCO_DO_MOUSE = Color3.fromRGB(235, 45, 45) -- o risco vermelho de "desativado" no desenho
local mouseTravado = true -- true = preso no meio (a câmera segue o mouse) · false = cursor livre
local mouseAplicado = false -- o que o laço já aplicou no último frame (true = estava travado)

-- As peças do aviso (criadas por código quando você senta; somem quando você levanta).
-- As peças do aviso (criadas por código quando você senta; somem quando você levanta).
type AvisoDoMouse = {
	tela: ScreenGui,
	contornos: { UIStroke }, -- as bordas que mudam de cor (ícone, desenho do mouse e balão)
	pecas: { Frame }, -- os traços de dentro do desenho do mouse (botões e rodinha)
	risco: Frame, -- o risco vermelho de "desligado" (só aparece com o mouse livre)
	alt: TextLabel, -- o "ALT" embaixo do desenho
	escalaIcone: UIScale, -- o ícone dá um pulinho quando muda
	balao: Frame, -- a mensagem que sai do ícone
	contornoBalao: UIStroke, -- a borda do balão (some junto com ele)
	escalaBalao: UIScale, -- o balão cresce saindo do ícone
	titulo: TextLabel, -- "MOUSE TRAVADO" ou "MOUSE LIVRE"
	dica: TextLabel, -- "câmera no mouse: LIGADA" ou "DESLIGADA"
	aberto: NumberValue, -- 0 = balão fechado · 1 = aberto (o TweenService anima este número)
	tempo: number, -- quantos segundos o balão fica aberto (0 = não fecha)
}
local avisoDoMouse: AvisoDoMouse? = nil

-- Um pedaço do desenho: um retângulo branco centralizado na posição (com cantos redondos, se pedir).
local function pedacoDoAviso(pai: Instance, tamanho: UDim2, posicao: UDim2, arredondar: number?): Frame
	local pedaco = Instance.new("Frame")
	pedaco.AnchorPoint = Vector2.new(0.5, 0.5)
	pedaco.Size = tamanho
	pedaco.Position = posicao
	pedaco.BorderSizePixel = 0
	pedaco.BackgroundColor3 = Color3.new(1, 1, 1)
	if arredondar then
		local canto = Instance.new("UICorner")
		canto.CornerRadius = UDim.new(0, arredondar)
		canto.Parent = pedaco
	end
	pedaco.Parent = pai
	return pedaco
end

-- Deixa o balão mais ou menos aberto: 0 = fechado (sumido) · 1 = aberto (inteiro).
local function aplicarBalao(aviso: AvisoDoMouse)
	local s = aviso.aberto.Value
	local t = 1 - math.clamp(s, 0, 1) -- transparência: 0 = inteiro · 1 = sumido
	aviso.balao.Visible = s > 0.01
	aviso.escalaBalao.Scale = math.max(s, 0.01) -- cresce saindo do ícone (passa um pouquinho de 1: efeito "pop")
	aviso.balao.BackgroundTransparency = 0.15 + 0.85 * t
	aviso.contornoBalao.Transparency = t
	aviso.titulo.TextTransparency = t
	aviso.titulo.TextStrokeTransparency = 0.5 + 0.5 * t
	aviso.dica.TextTransparency = t
end

-- O ícone dá um pulinho, o balão SAI dele, espera "tempo" segundos e VOLTA para dentro.
local vezDoBalao = 0 -- conta as vezes que o balão abriu (assim um "fechar" velho não fecha o balão novo)
local function mostrarBalao()
	local aviso = avisoDoMouse
	if aviso == nil then
		return
	end
	vezDoBalao += 1
	local minhaVez = vezDoBalao
	aviso.escalaIcone.Scale = 1.25 -- pulinho do ícone...
	TweenService:Create(aviso.escalaIcone, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if aviso.aberto.Value > 0.6 then
		aviso.aberto.Value = 0.6 -- (já estava aberto: encolhe um pouco para dar o "pop" de novo)
	end
	TweenService:Create(aviso.aberto, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
	if aviso.tempo > 0 then
		task.delay(aviso.tempo, function()
			if vezDoBalao == minhaVez and avisoDoMouse == aviso then -- (ninguém abriu de novo nesse meio tempo)
				TweenService:Create(aviso.aberto, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0 }):Play()
			end
		end)
	end
end

-- Cria o ícone no canto de cima, à direita (Config.MouseAvisoPosicao), com o balão escondido do lado.
local function criarAvisoDoMouse(quad: Quadriciclo)
	local playerGui = jogadorLocal:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local escuro = Color3.fromRGB(20, 22, 28)
	local tela = Instance.new("ScreenGui")
	tela.Name = "AvisoDoMouse"
	tela.ResetOnSpawn = false
	tela.DisplayOrder = 10 -- por cima do HUDQuadriciclo
	tela.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- O ÍCONE: um quadradinho escuro com o desenho do mouse e "ALT" embaixo.
	local icone = Instance.new("Frame")
	icone.Name = "Icone"
	icone.AnchorPoint = Vector2.new(1, 0) -- o "ponto de apoio" é o canto de cima à direita
	icone.Position = quad.Config.MouseAvisoPosicao or UDim2.new(1, -12, 0, 8)
	icone.Size = UDim2.fromOffset(40, 52)
	icone.BackgroundColor3 = escuro
	icone.BackgroundTransparency = 0.25
	icone.Parent = tela
	local cantoIcone = Instance.new("UICorner")
	cantoIcone.CornerRadius = UDim.new(0, 10)
	cantoIcone.Parent = icone
	local contornoIcone = Instance.new("UIStroke")
	contornoIcone.Thickness = 2
	contornoIcone.Parent = icone
	local escalaIcone = Instance.new("UIScale")
	escalaIcone.Parent = icone
	-- O desenho do mouse: o corpo (só a borda), a linha dos botões, a divisão e a rodinha.
	local corpo = pedacoDoAviso(icone, UDim2.fromOffset(18, 26), UDim2.new(0.5, 0, 0, 19), 9)
	corpo.BackgroundTransparency = 1 -- só a borda aparece
	local contornoDoMouse = Instance.new("UIStroke")
	contornoDoMouse.Thickness = 2
	contornoDoMouse.Parent = corpo
	local pecas = {
		pedacoDoAviso(corpo, UDim2.new(1, 0, 0, 2), UDim2.new(0.5, 0, 0, 10)), -- a linha embaixo dos botões
		pedacoDoAviso(corpo, UDim2.fromOffset(2, 10), UDim2.new(0.5, 0, 0, 5)), -- a divisão entre os botões
		pedacoDoAviso(corpo, UDim2.fromOffset(4, 6), UDim2.new(0.5, 0, 0, 6), 2), -- a rodinha
	}
	local risco = pedacoDoAviso(icone, UDim2.fromOffset(3, 34), UDim2.new(0.5, 0, 0, 19), 2)
	risco.Rotation = -40 -- "\" de desligado, por cima do desenho
	risco.BackgroundColor3 = COR_RISCO_DO_MOUSE
	risco.ZIndex = 2
	local alt = Instance.new("TextLabel") -- a tecla que trava e solta o mouse
	alt.AnchorPoint = Vector2.new(0.5, 1)
	alt.Position = UDim2.new(0.5, 0, 1, -3)
	alt.Size = UDim2.new(1, 0, 0, 11)
	alt.BackgroundTransparency = 1
	alt.Font = Enum.Font.GothamBlack
	alt.Text = "ALT"
	alt.TextSize = 11
	alt.Parent = icone

	-- O BALÃO: preso na borda esquerda do ícone. Ele cresce para a esquerda, como se saísse do ícone.
	local balao = Instance.new("Frame")
	balao.Name = "Balao"
	balao.AnchorPoint = Vector2.new(1, 0.5)
	balao.Position = UDim2.new(0, -6, 0.5, 0)
	balao.Size = UDim2.fromOffset(0, 38)
	balao.AutomaticSize = Enum.AutomaticSize.X -- a largura vem do texto
	balao.BackgroundColor3 = escuro
	balao.Parent = icone
	local cantoBalao = Instance.new("UICorner")
	cantoBalao.CornerRadius = UDim.new(0, 8)
	cantoBalao.Parent = balao
	local contornoBalao = Instance.new("UIStroke")
	contornoBalao.Thickness = 2
	contornoBalao.Parent = balao
	local escalaBalao = Instance.new("UIScale")
	escalaBalao.Parent = balao
	local margem = Instance.new("UIPadding")
	margem.PaddingLeft = UDim.new(0, 10)
	margem.PaddingRight = UDim.new(0, 10)
	margem.Parent = balao
	local titulo = Instance.new("TextLabel")
	titulo.Position = UDim2.fromOffset(0, 4)
	titulo.Size = UDim2.fromOffset(0, 16)
	titulo.AutomaticSize = Enum.AutomaticSize.X
	titulo.BackgroundTransparency = 1
	titulo.Font = Enum.Font.GothamBlack
	titulo.TextSize = 15
	titulo.TextXAlignment = Enum.TextXAlignment.Left
	titulo.Parent = balao
	local dica = Instance.new("TextLabel")
	dica.Position = UDim2.fromOffset(0, 21)
	dica.Size = UDim2.fromOffset(0, 12)
	dica.AutomaticSize = Enum.AutomaticSize.X
	dica.BackgroundTransparency = 1
	dica.Font = Enum.Font.GothamBold
	dica.TextSize = 11
	dica.TextColor3 = Color3.fromRGB(230, 230, 230)
	dica.TextXAlignment = Enum.TextXAlignment.Left
	dica.Parent = balao

	local aberto = Instance.new("NumberValue") -- 0 = balão fechado · 1 = aberto
	aberto.Name = "BalaoAberto"
	aberto.Parent = tela
	local aviso: AvisoDoMouse = {
		tela = tela, contornos = { contornoIcone, contornoDoMouse, contornoBalao }, pecas = pecas,
		risco = risco, alt = alt, escalaIcone = escalaIcone, balao = balao, contornoBalao = contornoBalao,
		escalaBalao = escalaBalao, titulo = titulo, dica = dica, aberto = aberto,
		tempo = numeroDaConfig(quad.Config.MouseAvisoTempo, 2),
	}
	aberto.Changed:Connect(function()
		aplicarBalao(aviso) -- cada mudança do número abre ou fecha um pouco o balão
	end)
	aplicarBalao(aviso) -- começa fechado
	tela.Parent = playerGui
	avisoDoMouse = aviso
end

-- Pinta o ícone com o estado de agora (verde = travado · amarelo com risco = livre) e abre o balão.
local function atualizarAvisoDoMouse()
	local aviso = avisoDoMouse
	if aviso == nil then
		return
	end
	local cor = if mouseTravado then COR_MOUSE_TRAVADO else COR_MOUSE_LIVRE
	for _, contorno in aviso.contornos do
		contorno.Color = cor
	end
	for _, peca in aviso.pecas do
		peca.BackgroundColor3 = cor
	end
	aviso.risco.Visible = not mouseTravado
	aviso.alt.TextColor3 = cor
	aviso.titulo.TextColor3 = cor
	aviso.titulo.Text = if mouseTravado then "MOUSE TRAVADO" else "MOUSE LIVRE"
	aviso.dica.Text = if mouseTravado then "câmera no mouse: LIGADA" else "câmera no mouse: DESLIGADA"
	mostrarBalao()
end
-- Roda a cada frame, DEPOIS de todas as câmeras: trava (ou solta) o mouse.
local function atualizarTravaDoMouse(quad: Quadriciclo)
	local travar = mouseTravado or quad.mirandoGancho -- mirando o gancho, trava sempre
	if travar then
		-- (refeito todo frame: a câmera do Roblox às vezes solta o mouse sozinha)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter -- preso no meio: a câmera segue o mouse
		UserInputService.MouseIconEnabled = false -- some a setinha (mirando, a mira faz o papel dela)
	elseif mouseAplicado then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default -- acabou de soltar: o cursor volta
		UserInputService.MouseIconEnabled = true
	end
	mouseAplicado = travar
end

-- Sentou: começa travado (Config.MouseTravadoAoSentar), cria o aviso e liga a tecla LeftAlt.
local function ligarTravaDoMouse(quad: Quadriciclo)
	if not UserInputService.MouseEnabled then
		return -- celular e videogame não têm mouse: sem trava e sem aviso
	end
	mouseTravado = quad.Config.MouseTravadoAoSentar ~= false
	mouseAplicado = false
	criarAvisoDoMouse(quad)
	atualizarAvisoDoMouse()
	ContextActionService:BindActionAtPriority(ACAO_TRAVAR_MOUSE, function(_nomeAcao: string, estado: Enum.UserInputState, _entrada: InputObject): Enum.ContextActionResult?
		if estado == Enum.UserInputState.Begin then
			mouseTravado = not mouseTravado -- alterna: travado ↔ livre
			atualizarAvisoDoMouse()
		end
		return Enum.ContextActionResult.Sink
	end, false, Veiculo.PRIORIDADE, Enum.KeyCode.LeftAlt)
	-- Depois da câmera do Roblox (+0), do capô (+1), da mira do gancho (+2) e da velocidade (+3).
	RunService:BindToRenderStep(TRAVA_DO_MOUSE, Enum.RenderPriority.Camera.Value + 4, function(_dt: number)
		atualizarTravaDoMouse(quad)
	end)
end

-- Levantou: desliga a tecla, solta o mouse e apaga o aviso.
local function desligarTravaDoMouse()
	ContextActionService:UnbindAction(ACAO_TRAVAR_MOUSE)
	RunService:UnbindFromRenderStep(TRAVA_DO_MOUSE)
	if mouseAplicado then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default -- o mouse volta ao normal
		UserInputService.MouseIconEnabled = true
	end
	mouseAplicado = false
	local aviso = avisoDoMouse
	if aviso then
		aviso.tela:Destroy()
	end
	avisoDoMouse = nil
end

-- Sentou: guarda os seus limites de zoom e liga a tecla da câmera.
function Camera.ligar(quad: Quadriciclo)
	zoomMinimo, zoomMaximo = jogadorLocal.CameraMinZoomDistance, jogadorLocal.CameraMaxZoomDistance
	local achado = quad.modelo:FindFirstChild("CameraCapo", true)
	anexoCapo = if achado and achado:IsA("Attachment") then achado else nil
	BotoesDoCelular.ligar(ACAO_CAMERA, "CAMERA", function(_nomeAcao: string, estado: Enum.UserInputState, _entrada: InputObject): Enum.ContextActionResult?
		if estado == Enum.UserInputState.Begin then
			trocarCamera(quad)
		end
		return Enum.ContextActionResult.Sink
	end, Veiculo.PRIORIDADE, Enum.KeyCode.C, Enum.KeyCode.ButtonY)
	ligarEfeitoVelocidade(quad) -- (NOVO) sensação de velocidade: a câmera abre, riscos e tremidinha
	-- (NOVO) A câmera do Roblox que segue o mouse (no capô, a câmera é nossa) e o mouse travado.
	if quad.modoCamera ~= 3 then
		Veiculo.cameraAtual().CameraType = tipoDaCameraDirigindo(quad)
	end
	ligarTravaDoMouse(quad)
end

-- Levantou: desliga a tecla e volta para a câmera normal.
function Camera.desligar(quad: Quadriciclo)
	BotoesDoCelular.desligar(ACAO_CAMERA)
	desligarEfeitoVelocidade()
	desligarTravaDoMouse() -- (NOVO) o mouse volta ao normal e o aviso some
	if quad.modoCamera ~= 1 then
		quad.modoCamera = 1
		aplicarModoCamera(quad, 1)
	end
	Veiculo.cameraAtual().CameraType = Enum.CameraType.Custom -- (NOVO) a câmera de andar a pé, de sempre
end

return Camera

