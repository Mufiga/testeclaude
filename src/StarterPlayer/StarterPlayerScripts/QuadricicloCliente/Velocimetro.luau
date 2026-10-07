--!strict
--[[
	=====================================================================
	Velocimetro  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Velocimetro
	=====================================================================

	O seu HUD "HUDQuadriciclo" (do StarterGui) enquanto você dirige:
	velocidade, barra colorida, menu de teclas (só com teclado) e o botão
	de desvirar (aparece quando já dá para desvirar).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
type Quadriciclo = Veiculo.Quadriciclo

local Velocimetro = {}

local jogadorLocal = Players.LocalPlayer :: Player

local VELOCIDADE_BARRA_CHEIA = 30 -- nesta velocidade a barra fica cheia (Scale X = 1)
local TEMPO_TOMBADO_PARA_BOTAO = 0.75 -- (s) tombado há esse tempo → aparece o botão R (não pisca em pulos)
local CORES_BARRA: { { velocidade: number, cor: Color3 } } = {
	{ velocidade = 0, cor = Color3.fromRGB(50, 220, 70) }, -- verde
	{ velocidade = 9, cor = Color3.fromRGB(50, 220, 70) }, -- verde (de 0 a 9 não muda)
	{ velocidade = 16, cor = Color3.fromRGB(170, 230, 40) }, -- verde-amarelado
	{ velocidade = 28, cor = Color3.fromRGB(255, 140, 0) }, -- laranja
	{ velocidade = 35, cor = Color3.fromRGB(235, 35, 35) }, -- vermelho (e acima disso)
	{ velocidade = 80, cor = Color3.fromRGB(235, 35, 35) }, -- vermelho (e acima disso)
	{ velocidade = 100, cor = Color3.fromRGB(37, 255, 219) }, -- Azul
}

local textoVelocimetro: TextLabel? = nil
local barraVelocimetro: Frame? = nil
local botaoDesvirar: GuiButton? = nil
local conexaoBotaoDesvirar: RBXScriptConnection? = nil

-- Cada vez que alguém começa a dirigir, este número muda. Assim, um laço
-- antigo do velocímetro sabe que precisa parar.
local sessaoDoLaco = 0

local function corDaBarra(velocidade: number): Color3
	for i = 2, #CORES_BARRA do
		local anterior, proximo = CORES_BARRA[i - 1], CORES_BARRA[i]
		if velocidade <= proximo.velocidade then
			local t = (velocidade - anterior.velocidade) / (proximo.velocidade - anterior.velocidade)
			return anterior.cor:Lerp(proximo.cor, math.clamp(t, 0, 1))
		end
	end
	return CORES_BARRA[#CORES_BARRA].cor
end

local function criarVelocimetro(quad: Quadriciclo)
	local playerGui = jogadorLocal:FindFirstChildOfClass("PlayerGui")
	local tela = if playerGui then playerGui:FindFirstChild("HUDQuadriciclo") else nil
	if not (tela and tela:IsA("ScreenGui")) then
		warn('[Quadriciclo] Não achei a ScreenGui "HUDQuadriciclo" (ela fica no StarterGui).')
		return
	end
	local texto = tela:FindFirstChild("TextoVelocidade", true)
	local barra = tela:FindFirstChild("BarraVelocidade", true)
	local menu = tela:FindFirstChild("Controles", true)
	local botao = tela:FindFirstChild("BotaoDesvirar", true)
	textoVelocimetro = if texto and texto:IsA("TextLabel") then texto else nil
	barraVelocimetro = if barra and barra:IsA("Frame") then barra else nil
	if menu and menu:IsA("GuiObject") then
		menu.Visible = UserInputService.KeyboardEnabled -- o menu de teclas só aparece para quem tem teclado
	end
	if botao and botao:IsA("GuiButton") then
		botao.Visible = false -- só aparece quando o quadriciclo tomba (veja atualizarVelocimetro)
		botaoDesvirar = botao
		conexaoBotaoDesvirar = botao.Activated:Connect(function()
			Veiculo.desvirar(quad) -- clique ou toque faz o mesmo que a tecla R
		end)
	end
	quad.tela = tela
	tela.Enabled = true
end

local function destruirVelocimetro(quad: Quadriciclo)
	local tela = quad.tela
	if tela then
		tela.Enabled = false -- só esconde (a ScreenGui é a sua, do StarterGui)
	end
	local conexao = conexaoBotaoDesvirar
	if conexao then
		conexao:Disconnect()
	end
	local botao = botaoDesvirar
	if botao then
		botao.Visible = false
	end
	quad.tela = nil
	textoVelocimetro = nil
	barraVelocimetro = nil
	botaoDesvirar = nil
	conexaoBotaoDesvirar = nil
end

-- Roda em paralelo (task.spawn) e atualiza o HUD a cada frame.
local function atualizarVelocimetro(quad: Quadriciclo, sessao: number)
	local exibida = 0 -- velocidade suavizada: a barra desliza em vez de tremer com a suspensão
	local dt = 0
	while sessaoDoLaco == sessao do
		-- Velocidade ao longo do chão embaixo do carro (na ladeira conta a descida inteira).
		local velocidade = quad.chassi.AssemblyLinearVelocity
		local cima = Veiculo.referencia(quad).UpVector
		local noChao = (velocidade - cima * velocidade:Dot(cima)).Magnitude
		exibida += (noChao - exibida) * math.min(dt * 12, 1)
		local texto, barra = textoVelocimetro, barraVelocimetro
		if texto then
			-- O número vai até Config.VelocidadeMaximaTotal (ladeira + nitro).
			texto.Text = `Velocidade: {math.min(math.floor(exibida + 0.5), quad.Config.VelocidadeMaximaTotal)}`
		end
		if barra then
			barra.Size = UDim2.fromScale(math.clamp(exibida / VELOCIDADE_BARRA_CHEIA, 0, 1), 1) -- 0 a 30 → 0 a 1
			barra.BackgroundColor3 = corDaBarra(exibida)
		end
		local botao = botaoDesvirar
		if botao then
			-- Aparece quando já dá para desvirar (tombado há Config.TempoParaDesvirar segundos).
			botao.Visible = quad.tombadoHaQuanto >= math.max(TEMPO_TOMBADO_PARA_BOTAO, quad.Config.TempoParaDesvirar)
		end
		dt = task.wait() -- espera 1 frame
	end
end

-- Sentou: mostra o HUD (se Config.ShowSpeedometer) e começa o laço.
function Velocimetro.ligar(quad: Quadriciclo)
	sessaoDoLaco += 1
	if quad.Config.ShowSpeedometer then
		criarVelocimetro(quad)
		task.spawn(atualizarVelocimetro, quad, sessaoDoLaco) -- laço paralelo do velocímetro
	end
end

-- Levantou: esconde o HUD e encerra o laço.
function Velocimetro.desligar(quad: Quadriciclo)
	sessaoDoLaco += 1
	destruirVelocimetro(quad)
end


-- O HUD INTEIRO só aparece enquanto você dirige. Toda cópia do HUDQuadriciclo que chega no seu
-- PlayerGui (no começo do jogo e, com ResetOnSpawn, cada vez que você renasce) começa escondida.
-- Quem mostra é o criarVelocimetro, quando você senta num quadriciclo.
local function esconderHud(objeto: Instance)
	if objeto.Name == "HUDQuadriciclo" and objeto:IsA("ScreenGui") then
		objeto.Enabled = false
	end
end
task.spawn(function()
	local playerGui = jogadorLocal:WaitForChild("PlayerGui")
	playerGui.ChildAdded:Connect(esconderHud)
	for _, objeto in playerGui:GetChildren() do
		esconderHud(objeto)
	end
end)

return Velocimetro

