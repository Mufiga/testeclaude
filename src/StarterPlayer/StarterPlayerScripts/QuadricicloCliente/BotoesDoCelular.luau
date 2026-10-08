--!strict
--[[
	=====================================================================
	BotoesDoCelular  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > BotoesDoCelular
	=====================================================================

	Os BOTÕES DA TELA enquanto você dirige no celular/tablet: GÁS, FREIO, GANCHO, NITRO, F. MÃO,
	BUZINA, CÂMERA, SAIR e PULO (no caminhão monstro).

	Por que não os botões automáticos do Roblox (ContextActionService)? Eles ficam amontoados em cima
	do botão de pulo, o texto não cabe ("BUZIN A") e o Roblox mostra no máximo 7: o SAIR e o PULO do
	caminhão monstro ficavam de fora. Aqui cada botão tem o seu lugar, o seu tamanho e a sua cor.

	  - O GÁS fica no canto (é o que o dedo mais aperta) e é o maior.
	  - Se o dedo escorregar para fora do botão, ele continua apertado até você tirar o dedo da tela.
	  - Enquanto você dirige, o botão de PULO do Roblox some (ele tirava você do veículo sem querer).
	    Para sair, use o botão SAIR.
	  - Tudo encolhe junto com os outros HUDs (módulo Tela).

	Quer mudar um botão de lugar, de tamanho ou de cor? É só mexer na tabela BOTOES aqui embaixo.
	(As teclas do computador e os botões do controle continuam iguais: este módulo só cuida da tela.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

-- O tamanho dos HUDs em cada tela e se o jogador está jogando pelo toque.
local Tela = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Tela"))

local BotoesDoCelular = {}

-- A mesma função que o ContextActionService chama (as teclas e o controle chamam a mesma).
export type Funcao = (nome: string, estado: Enum.UserInputState, entrada: InputObject) -> Enum.ContextActionResult?

-- =====================================================================
-- AJUSTES: onde fica cada botão
-- =====================================================================
-- Os botões ficam num quadro no canto de baixo, à DIREITA, de LARGURA × ALTURA pixels.
-- x e y = o CENTRO do botão dentro desse quadro (x = 0 é a esquerda dele, y = 0 é o topo dele).
-- tamanho = a largura do botão (ele é redondo). Os números são do computador: no celular, tudo
-- encolhe junto (no módulo Tela, TAMANHO_TELA_PEQUENA).
local LARGURA, ALTURA = 330, 300
local MARGEM = 12 -- (pixels) distância do quadro até a borda da tela

type Desenho = { titulo: string, x: number, y: number, tamanho: number, cor: Color3, lado: "Direita" | "Esquerda" }
local BOTOES: { [string]: Desenho } = {
	GAS = { titulo = "GÁS", x = 270, y = 240, tamanho = 110, cor = Color3.fromRGB(70, 220, 100), lado = "Direita" },
	FREIO = { titulo = "FREIO", x = 148, y = 252, tamanho = 88, cor = Color3.fromRGB(240, 70, 70), lado = "Direita" },
	NITRO = { titulo = "NITRO", x = 272, y = 126, tamanho = 80, cor = Color3.fromRGB(170, 90, 255), lado = "Direita" },
	GANCHO = { titulo = "GANCHO", x = 168, y = 140, tamanho = 88, cor = Color3.fromRGB(255, 190, 40), lado = "Direita" },
	FREIO_DE_MAO = { titulo = "F. MÃO", x = 42, y = 258, tamanho = 70, cor = Color3.fromRGB(255, 130, 50), lado = "Direita" },
	PULO = { titulo = "PULO", x = 56, y = 152, tamanho = 80, cor = Color3.fromRGB(60, 200, 255), lado = "Direita" },
	SAIR = { titulo = "SAIR", x = 110, y = 36, tamanho = 68, cor = Color3.fromRGB(230, 230, 230), lado = "Direita" },
	BUZINA = { titulo = "BUZINA", x = 210, y = 36, tamanho = 68, cor = Color3.fromRGB(255, 230, 80), lado = "Direita" },
	CAMERA = { titulo = "CÂMERA", x = 296, y = 36, tamanho = 68, cor = Color3.fromRGB(230, 230, 230), lado = "Direita" },
	-- ESQ e DIR só aparecem com Configuracao.MobileSteerButtons = true (no canto de baixo, à ESQUERDA,
	-- do lado do analógico).
	ESQ = { titulo = "◀", x = 46, y = 254, tamanho = 84, cor = Color3.fromRGB(230, 230, 230), lado = "Esquerda" },
	DIR = { titulo = "▶", x = 146, y = 254, tamanho = 84, cor = Color3.fromRGB(230, 230, 230), lado = "Esquerda" },
}
local ESQUERDA_X = 110 -- (pixels) o quadro da esquerda começa aqui (para não ficar em cima do analógico)

local TRANSPARENCIA_SOLTO = 0.45 -- o fundo do botão solto (0 = sólido, 1 = invisível)
local TRANSPARENCIA_APERTADO = 0.15
local ENCOLHER_APERTADO = 0.92 -- apertado, o botão fica um pouquinho menor

-- =====================================================================
-- A TELA DOS BOTÕES (criada uma vez só)
-- =====================================================================
local jogadorLocal = Players.LocalPlayer :: Player

type Botao = {
	desenho: Desenho,
	objeto: TextButton,
	borda: UIStroke,
	escala: UIScale,
	acao: string?, -- a ação ligada agora (nil = botão escondido)
	funcao: Funcao?,
	dedo: InputObject?, -- o dedo que está apertando agora (nil = solto)
}
local botoes: { [string]: Botao } = {}
local porAcao: { [string]: Botao } = {}
local tela: ScreenGui? = nil
local dirigindo = false

local function novoQuadro(pai: ScreenGui, nome: string, ancora: Vector2, posicao: UDim2): Frame
	local quadro = Instance.new("Frame")
	quadro.Name = nome
	quadro.AnchorPoint = ancora
	quadro.Position = posicao
	quadro.Size = UDim2.fromOffset(LARGURA, ALTURA)
	quadro.BackgroundTransparency = 1
	quadro.Parent = pai
	Tela.encolher(quadro) -- (encolhe em volta do canto de baixo)
	return quadro
end

local function pintar(botao: Botao)
	local apertado = botao.dedo ~= nil
	botao.objeto.BackgroundColor3 = if apertado then botao.desenho.cor else Color3.new(0, 0, 0)
	botao.objeto.BackgroundTransparency = if apertado then TRANSPARENCIA_APERTADO else TRANSPARENCIA_SOLTO
	botao.borda.Transparency = if apertado then 0 else 0.25
	botao.escala.Scale = if apertado then ENCOLHER_APERTADO else 1
end

-- Solta o botão. avisar = true: a ação fica sabendo (como se o dedo tivesse saído da tela).
local function soltar(botao: Botao, estado: Enum.UserInputState, avisar: boolean)
	local dedo = botao.dedo
	if dedo == nil then
		return
	end
	botao.dedo = nil
	pintar(botao)
	local acao, funcao = botao.acao, botao.funcao
	if avisar and acao and funcao then
		funcao(acao, estado, dedo)
	end
end

local function apertar(botao: Botao, dedo: InputObject)
	local acao, funcao = botao.acao, botao.funcao
	if botao.dedo ~= nil or acao == nil or funcao == nil then
		return
	end
	botao.dedo = dedo
	pintar(botao)
	funcao(acao, Enum.UserInputState.Begin, dedo)
end

local function criarBotao(id: string, desenho: Desenho, quadro: Frame): Botao
	local objeto = Instance.new("TextButton")
	objeto.Name = id
	objeto.Text = ""
	objeto.AutoButtonColor = false
	objeto.Active = true
	objeto.Selectable = false
	objeto.AnchorPoint = Vector2.new(0.5, 0.5)
	objeto.Position = UDim2.fromOffset(desenho.x, desenho.y)
	objeto.Size = UDim2.fromOffset(desenho.tamanho, desenho.tamanho)
	objeto.Visible = false
	local canto = Instance.new("UICorner")
	canto.CornerRadius = UDim.new(1, 0) -- redondo
	canto.Parent = objeto
	local borda = Instance.new("UIStroke")
	borda.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	borda.Thickness = 3
	borda.Color = desenho.cor
	borda.Parent = objeto
	local escala = Instance.new("UIScale")
	escala.Parent = objeto
	local titulo = Instance.new("TextLabel")
	titulo.Name = "Titulo"
	titulo.BackgroundTransparency = 1
	titulo.AnchorPoint = Vector2.new(0.5, 0.5)
	titulo.Position = UDim2.fromScale(0.5, 0.5)
	titulo.Size = UDim2.fromScale(0.84, 0.5) -- o texto cabe numa linha só (encolhe se precisar)
	titulo.Font = Enum.Font.GothamBlack
	titulo.Text = desenho.titulo
	titulo.TextColor3 = Color3.new(1, 1, 1)
	titulo.TextStrokeTransparency = 0.4
	titulo.TextScaled = true
	titulo.Parent = objeto
	local limite = Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = math.floor(desenho.tamanho * 0.24)
	limite.Parent = titulo
	objeto.Parent = quadro

	local botao: Botao = { desenho = desenho, objeto = objeto, borda = borda, escala = escala, acao = nil, funcao = nil, dedo = nil }
	pintar(botao)
	objeto.InputBegan:Connect(function(entrada: InputObject)
		local tipo = entrada.UserInputType
		if (tipo == Enum.UserInputType.Touch or tipo == Enum.UserInputType.MouseButton1)
			and entrada.UserInputState == Enum.UserInputState.Begin then
			apertar(botao, entrada)
		end
	end)
	return botao
end

local function criarTela(): ScreenGui?
	local playerGui = jogadorLocal:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local nova = Instance.new("ScreenGui")
	nova.Name = "BotoesDoCelular"
	nova.ResetOnSpawn = false
	nova.Enabled = false
	nova.DisplayOrder = 5
	local direita = novoQuadro(nova, "Direita", Vector2.new(1, 1), UDim2.new(1, -MARGEM, 1, -MARGEM))
	local esquerda = novoQuadro(nova, "Esquerda", Vector2.new(0, 1), UDim2.new(0, ESQUERDA_X, 1, -MARGEM))
	for id, desenho in BOTOES do
		botoes[id] = criarBotao(id, desenho, if desenho.lado == "Esquerda" then esquerda else direita)
	end
	nova.Parent = playerGui
	return nova
end

-- O dedo saiu da tela: solta o botão que ele apertava (mesmo se ele escorregou para fora do botão).
UserInputService.InputEnded:Connect(function(entrada: InputObject)
	for _, botao in botoes do
		if botao.dedo == entrada then
			soltar(botao, Enum.UserInputState.End, true)
		end
	end
end)

-- =====================================================================
-- O BOTÃO DE PULO DO ROBLOX (some enquanto você dirige pelo toque)
-- =====================================================================
-- O botão de pulo do Roblox só aparece quando o boneco PODE pular; desligando o pulo enquanto você
-- dirige, ele some. (Dirigindo, pular = sair do veículo: era fácil apertar sem querer perto do GÁS.)
local puloDesligadoEm: Humanoid? = nil

local function desligarPulo(desligar: boolean)
	local antes = puloDesligadoEm
	if antes and (not desligar or antes.Parent == nil) then
		puloDesligadoEm = nil
		if antes.Parent ~= nil then
			antes:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		end
	end
	if desligar and puloDesligadoEm == nil then
		local personagem = jogadorLocal.Character
		local humanoide = if personagem then personagem:FindFirstChildOfClass("Humanoid") else nil
		if humanoide and humanoide:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			humanoide:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			puloDesligadoEm = humanoide
		end
	end
end

-- =====================================================================
-- MOSTRAR / ESCONDER
-- =====================================================================
local function atualizar()
	local mostrar = dirigindo and Tela.noToque() and GuiService.TouchControlsEnabled
	if mostrar and tela == nil then
		tela = criarTela()
	end
	local atual = tela
	if atual then
		atual.Enabled = mostrar
	end
	if not mostrar then
		for _, botao in botoes do
			soltar(botao, Enum.UserInputState.Cancel, true) -- (sumiu com o dedo em cima: não conta)
		end
	end
	desligarPulo(mostrar)
end
UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(atualizar)
GuiService:GetPropertyChangedSignal("TouchControlsEnabled"):Connect(atualizar)

-- =====================================================================
-- O QUE OS OUTROS MÓDULOS USAM
-- =====================================================================
-- Liga uma ação do veículo: as teclas e os botões do controle (ContextActionService, como antes) e,
-- no celular, o botão "id" da tabela BOTOES (nil = sem botão na tela).
function BotoesDoCelular.ligar(acao: string, id: string?, funcao: Funcao, prioridade: number, ...: Enum.KeyCode)
	ContextActionService:BindActionAtPriority(acao, funcao, false, prioridade, ...)
	if id == nil then
		return
	end
	if tela == nil then
		tela = criarTela()
	end
	local botao = botoes[id]
	if botao == nil then
		if tela ~= nil then
			warn(`[Quadriciclo] BotoesDoCelular: não existe o botão "{id}" na tabela BOTOES.`)
		end
		return
	end
	local antiga = botao.acao
	if antiga and antiga ~= acao then
		porAcao[antiga] = nil
	end
	soltar(botao, Enum.UserInputState.Cancel, false)
	botao.acao = acao
	botao.funcao = funcao
	botao.objeto.Visible = true
	porAcao[acao] = botao
end

-- Desliga a ação (teclas, controle e o botão da tela).
function BotoesDoCelular.desligar(acao: string)
	ContextActionService:UnbindAction(acao)
	local botao = porAcao[acao]
	if botao == nil then
		return
	end
	porAcao[acao] = nil
	soltar(botao, Enum.UserInputState.Cancel, false) -- (quem desliga já arruma o resto)
	botao.acao = nil
	botao.funcao = nil
	botao.objeto.Visible = false
end

-- Sentou (true) ou levantou (false): mostra/esconde os botões e o botão de pulo do Roblox.
function BotoesDoCelular.dirigindo(ligado: boolean)
	dirigindo = ligado
	atualizar()
end

return BotoesDoCelular
