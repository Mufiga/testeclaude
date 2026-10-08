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
	  - NADA FICA CORTADO:
	      · os botões ficam dentro da "área segura" (sem o entalhe do celular e sem a barra do Roblox);
	      · o tamanho segue o módulo Tela, mas nunca passa de PARTE_MAXIMA_DA_LARGURA/ALTURA da tela;
	      · o texto de cada botão é medido para caber numa linha só. (O "TextScaled" do Roblox quebra
	        a palavra no meio quando acha que assim a letra fica maior: era o "BUZIN A".)
	  - BotoesDoCelular.desvioDoMeio() diz quanto os HUDs do meio de baixo (a barra de ganchos e a do
	    super pulo) devem ir para o lado, para ficarem no espaço livre entre o analógico e os botões.

	Quer mudar um botão de lugar, de tamanho ou de cor? É só mexer na tabela BOTOES aqui embaixo.
	(As teclas do computador e os botões do controle continuam iguais: este módulo só cuida da tela.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")

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
local MARGEM = 12 -- (pixels) distância do quadro até a borda da área segura da tela
-- O quadro nunca passa desta parte da tela (0.46 = 46% da largura). Em tela pequena ou com o
-- celular em pé, os botões diminuem um pouco mais para caber.
local PARTE_MAXIMA_DA_LARGURA = 0.46
local PARTE_MAXIMA_DA_ALTURA = 0.75

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
local FONTE = Enum.Font.GothamBlack
local LETRA_MAXIMA = 0.26 -- a letra tem no máximo 26% do tamanho do botão...
local LARGURA_DO_TEXTO = 0.78 -- ...e o texto ocupa no máximo 78% da largura dele (sempre numa linha só)

-- Até onde vai o analógico do Roblox (parado no canto de baixo, à esquerda), da borda esquerda.
local ANALOGICO_NO_CELULAR = 100 -- (pixels) celular (o lado menor da tela tem até 500 pixels)
local ANALOGICO_NO_TABLET = 185 -- (pixels) tablet

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
local quadros: { Frame } = {} -- o da direita e o da esquerda
local escalasDosQuadros: { UIScale } = {}
local dirigindo = false

-- O tamanho dos botões agora: o mesmo dos outros HUDs (Tela.escala), mas sem passar da
-- PARTE_MAXIMA da área segura da tela.
local function fatorDosBotoes(): number
	local atual = tela
	local area = if atual then atual.AbsoluteSize else Vector2.zero
	if area.X <= 0 or area.Y <= 0 then
		local camera = workspace.CurrentCamera -- (a tela dos botões ainda não existe: usa a tela inteira)
		area = if camera then camera.ViewportSize else Vector2.zero
	end
	local fator = Tela.escala()
	if area.X > 0 and area.Y > 0 then
		fator = math.min(fator, area.X * PARTE_MAXIMA_DA_LARGURA / LARGURA, area.Y * PARTE_MAXIMA_DA_ALTURA / ALTURA)
	end
	return fator
end

local function acertarTamanho()
	local fator = fatorDosBotoes()
	for _, escala in escalasDosQuadros do
		if math.abs(escala.Scale - fator) > 0.001 then
			escala.Scale = fator
		end
	end
end

-- O maior tamanho de letra em que o título cabe numa linha só, dentro do botão.
local function tamanhoDaLetra(titulo: string, tamanho: number): number
	local largura = tamanho * LARGURA_DO_TEXTO
	local semLimite = Vector2.new(10000, 10000)
	for letra = math.floor(tamanho * LETRA_MAXIMA), 8, -1 do
		if TextService:GetTextSize(titulo, letra, FONTE, semLimite).X <= largura then
			return letra
		end
	end
	return 8
end

local function novoQuadro(pai: ScreenGui, nome: string, ancora: Vector2, posicao: UDim2): Frame
	local quadro = Instance.new("Frame")
	quadro.Name = nome
	quadro.AnchorPoint = ancora
	quadro.Position = posicao
	quadro.Size = UDim2.fromOffset(LARGURA, ALTURA)
	quadro.BackgroundTransparency = 1
	quadro.Visible = false
	quadro.Parent = pai
	local escala = Instance.new("UIScale") -- (encolhe em volta do canto de baixo: o AnchorPoint)
	escala.Name = "TamanhoDaTela"
	escala.Parent = quadro
	table.insert(quadros, quadro)
	table.insert(escalasDosQuadros, escala)
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
	titulo.Size = UDim2.fromScale(1, 1)
	titulo.Font = FONTE
	titulo.Text = desenho.titulo
	-- Tamanho FIXO, medido para caber numa linha (sem TextScaled e sem quebrar linha: nunca "BUZIN A").
	titulo.TextScaled = false
	titulo.TextWrapped = false
	titulo.TextSize = tamanhoDaLetra(desenho.titulo, desenho.tamanho)
	titulo.TextColor3 = Color3.new(1, 1, 1)
	titulo.TextStrokeTransparency = 0.4
	titulo.Parent = objeto
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
	nova.DisplayOrder = 5
	-- Só a ÁREA SEGURA: sem o entalhe/câmera do celular, sem a barrinha de baixo do iPhone e sem a
	-- barra do Roblox em cima. (Os quadros aparecem e somem; a tela fica sempre ligada para medir.)
	nova.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local direita = novoQuadro(nova, "Direita", Vector2.new(1, 1), UDim2.new(1, -MARGEM, 1, -MARGEM))
	local esquerda = novoQuadro(nova, "Esquerda", Vector2.new(0, 1), UDim2.new(0, ESQUERDA_X, 1, -MARGEM))
	for id, desenho in BOTOES do
		botoes[id] = criarBotao(id, desenho, if desenho.lado == "Esquerda" then esquerda else direita)
	end
	nova:GetPropertyChangedSignal("AbsoluteSize"):Connect(acertarTamanho) -- (girou o celular, etc.)
	nova.Parent = playerGui
	tela = nova
	acertarTamanho()
	return nova
end
Tela.aoMudar(acertarTamanho)

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
local function noCelularAgora(): boolean
	return Tela.noToque() and GuiService.TouchControlsEnabled
end

local function atualizar()
	local mostrar = dirigindo and noCelularAgora()
	if mostrar and tela == nil then
		criarTela()
	end
	for _, quadro in quadros do
		quadro.Visible = mostrar
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
		criarTela()
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

-- Para os HUDs do MEIO de baixo (a barra de ganchos e a do super pulo): quantos pixels eles devem ir
-- para o lado para ficarem no meio do espaço LIVRE entre o analógico (esquerda) e os botões
-- (direita). Negativo = para a esquerda. Fora do celular: 0.
function BotoesDoCelular.desvioDoMeio(): number
	if not noCelularAgora() then
		return 0
	end
	local camera = workspace.CurrentCamera
	local tamanho = if camera then camera.ViewportSize else Vector2.zero
	local analogico = if math.min(tamanho.X, tamanho.Y) <= 500 then ANALOGICO_NO_CELULAR else ANALOGICO_NO_TABLET
	local botoesDaDireita = MARGEM + LARGURA * fatorDosBotoes()
	return math.floor((analogico - botoesDaDireita) / 2)
end

return BotoesDoCelular
