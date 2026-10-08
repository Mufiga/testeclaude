--!strict
--[[
	=====================================================================
	SeletorDeVeiculo  (LocalScript) — versão 2
	Local: StarterPlayer > StarterPlayerScripts > SeletorDeVeiculo
	=====================================================================

	O HUD DE VEÍCULOS (canto esquerdo da tela):
	  - Cada veículo da pasta ReplicatedStorage > Quadriciclos vira um cartão com o modelo 3D.
	    Passe o mouse: o cartão acende e o veículo gira. Clique: ele fica ESCOLHIDO (borda dourada e ✓).
	  - O BOTÃO GRANDE muda sozinho:
	      CHAMAR (verde, pulsando) ..... perto de um spawner: o escolhido aparece nele e você já senta
	      MOSTRAR CAMINHO (dourado) .... longe: liga a SETA 3D em cima de você e a COLUNA DE LUZ no spawner
	      ESCONDER CAMINHO ............. desliga a seta (ela também some sozinha quando você chega)
	  - A bússola embaixo aponta para o spawner mais perto e mostra a distância.
	  - "EM USO" marca o veículo que você está usando. O botão "–" (ou o título) encolhe o HUD.
	  - CONTROLE (videogame), andando a pé: ◀ ▶ escolhem o veículo · ▲ aperta o botão grande
	    (CHAMAR / MOSTRAR CAMINHO) · ▼ encolhe ou abre o HUD. (Dirigindo, essas setas são do veículo.)
	  - No CELULAR o HUD fica menor e no canto de cima (longe do analógico). Se a tela for baixa,
	    a lista mostra menos cartões (e rola), para o HUD inteiro caber na tela.
	A seta e a coluna de luz só existem no SEU computador (os outros jogadores não veem).
	Usa o mesmo "fio" do script Spawner (o RemoteEvent "Garagem"): quem confere tudo continua sendo o
	servidor. O "E  Garagem" dos spawners não muda.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local jogador = Players.LocalPlayer :: Player
local remoto = ReplicatedStorage:WaitForChild("Garagem") :: RemoteEvent -- (criado pelo script Spawner)
local moldes = ReplicatedStorage:WaitForChild("Quadriciclos")
-- A lista dos veículos, o nome/descrição e o veículo 3D dos cartões (o mesmo da GaragemCliente).
local Vitrine = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Vitrine"))
-- O tamanho dos HUDs em cada tela (no celular, menor) e se o jogador está no toque ou no controle.
local Tela = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Tela"))

-- =====================================================================
-- AJUSTES
-- =====================================================================
local TAG_SPAWNER = "SpawnerQuadriciclo" -- (a mesma do script Spawner)
local DISTANCIA_PARA_CHAMAR = 38 -- (studs) perto assim de um spawner, o CHAMAR acende (o servidor aceita até 40)
local POSICAO = UDim2.new(0, 12, 0.5, 0) -- onde o HUD fica: canto esquerdo, no meio da altura
local ANCORA = Vector2.new(0, 0.5) -- que ponto do HUD fica na POSICAO (0, 0.5 = o meio da borda esquerda)
local POSICAO_NO_CELULAR = UDim2.new(0, 12, 0, 8) -- no celular: canto de CIMA, à esquerda (longe do analógico)
local ANCORA_NO_CELULAR = Vector2.new(0, 0) -- (0, 0 = o canto de cima à esquerda do HUD)
local LARGURA = 264 -- (pixels) a largura do HUD
local MAXIMO_DE_CARTOES = 4 -- mais veículos que isso: a lista rola (em tela baixa, mostra menos)
local ENCOLHIDO_NO_CELULAR = true -- no celular, o HUD começa encolhido (só o título)
local GIRO_DA_VITRINE = 1.2 -- (radianos/s) o giro do veículo no cartão (com o mouse em cima, e o escolhido)
local GIRO_DO_ESCOLHIDO_POR_SEGUNDO = 30 -- quantas vezes por segundo o veículo ESCOLHIDO é redesenhado girando
--                                          (com o mouse em cima: todo frame). Menos = mais leve para o computador.
-- AS CORES: azul-escuro no fundo, DOURADO para o escolhido e para o caminho, VERDE para chamar
local COR_PAINEL = Color3.fromRGB(16, 21, 32)
local COR_CARTAO = Color3.fromRGB(29, 37, 53)
local COR_CARTAO_ACESO = Color3.fromRGB(42, 54, 77) -- (com o mouse em cima)
local COR_BORDA = Color3.fromRGB(54, 67, 92)
local COR_DOURADO = Color3.fromRGB(255, 190, 40)
local COR_VERDE = Color3.fromRGB(80, 220, 120)
local COR_APAGADO = Color3.fromRGB(50, 58, 76) -- (botão sem ação)
local COR_TEXTO = Color3.fromRGB(255, 255, 255)
local COR_TEXTO_FRACO = Color3.fromRGB(165, 180, 205)
local COR_TEXTO_ESCURO = Color3.fromRGB(14, 26, 20) -- (texto em cima do verde e do dourado)
local COR_CEU_EM_CIMA = Color3.fromRGB(110, 185, 255) -- o fundo das vitrines é um "céu"
local COR_CEU_EMBAIXO = Color3.fromRGB(225, 240, 255)
-- A SETA 3D e a COLUNA DE LUZ
local ALTURA_DA_SETA = 4 -- (studs) acima da sua cabeça (dirigindo: acima do veículo)
local ALTURA_DA_COLUNA = 70 -- (studs) a coluna de luz no spawner
-- OS SONS ("" = sem som). Pode trocar por um som do Creator Store: "rbxassetid://123456"
local SOM_CLIQUE = "rbxasset://sounds/clickfast.wav"
local SOM_PRONTO = "rbxasset://sounds/electronicpingshort.wav"
local VOLUME = 0.5

-- =====================================================================
-- FERRAMENTAS (deixam o código da tela mais curto)
-- =====================================================================
local function arredondar(objeto: GuiObject, raio: number)
	local canto = Instance.new("UICorner")
	canto.CornerRadius = UDim.new(0, raio)
	canto.Parent = objeto
end

local function contornar(objeto: GuiObject, cor: Color3, grossura: number): UIStroke
	local contorno = Instance.new("UIStroke")
	contorno.Color = cor
	contorno.Thickness = grossura
	contorno.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- (em botões: contorna a caixa, não o texto)
	contorno.Parent = objeto
	return contorno
end

local function novoTexto(pai: Instance, texto: string, tamanho: number, cor: Color3, fonte: Enum.Font): TextLabel
	local etiqueta = Instance.new("TextLabel")
	etiqueta.BackgroundTransparency = 1
	etiqueta.Text = texto
	etiqueta.TextSize = tamanho
	etiqueta.TextColor3 = cor
	etiqueta.Font = fonte
	etiqueta.TextXAlignment = Enum.TextXAlignment.Left
	etiqueta.Parent = pai
	return etiqueta
end

-- Texto que diminui sozinho para caber (até "maximo" de tamanho).
local function caber(etiqueta: TextLabel, maximo: number)
	etiqueta.TextScaled = true
	local limite = Instance.new("UITextSizeConstraint")
	limite.MaxTextSize = maximo
	limite.Parent = etiqueta
end

-- Uma animação suave (Tween) de algumas propriedades.
local function animar(objeto: Instance, segundos: number, metas: { [string]: any }, estilo: Enum.EasingStyle?)
	TweenService:Create(objeto, TweenInfo.new(segundos, estilo or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), metas):Play()
end

-- =====================================================================
-- A TELA
-- =====================================================================
local tela = Instance.new("ScreenGui")
tela.Name = "SeletorDeVeiculo"
tela.ResetOnSpawn = false -- (não some quando você renasce)
tela.DisplayOrder = 5 -- (a garagem do "E", que é 30, abre por cima)
tela.Parent = jogador:WaitForChild("PlayerGui")

-- OS SONS (ficam na tela: só você ouve)
local function novoSom(id: string, velocidade: number): Sound?
	if id == "" then
		return nil
	end
	local som = Instance.new("Sound")
	som.SoundId = id
	som.PlaybackSpeed = velocidade
	som.Volume = VOLUME
	som.Parent = tela
	return som
end
local somPassar = novoSom(SOM_CLIQUE, 1.7) -- (mouse em cima de um cartão: bem baixinho)
local somEscolher = novoSom(SOM_CLIQUE, 1)
local somErro = novoSom(SOM_CLIQUE, 0.55) -- (mais grave)
local somPronto = novoSom(SOM_PRONTO, 1)
local function tocar(som: Sound?, volume: number?)
	if som then
		som.Volume = VOLUME * (volume or 1)
		som:Play()
	end
end

-- O "suporte" posiciona o HUD e diminui ele em telas pequenas; o "hud" é o painel de verdade.
-- (No celular ele fica no canto de cima: embaixo, à esquerda, fica o analógico.)
local noCelular = Tela.noToque()
local posicaoDoHud = if noCelular then POSICAO_NO_CELULAR else POSICAO
local suporte = Instance.new("Frame")
suporte.Name = "Suporte"
suporte.AnchorPoint = if noCelular then ANCORA_NO_CELULAR else ANCORA
suporte.Position = posicaoDoHud
suporte.Size = UDim2.fromOffset(LARGURA, 0)
suporte.AutomaticSize = Enum.AutomaticSize.Y
suporte.BackgroundTransparency = 1
suporte.Parent = tela
local escalaDoHud = Tela.encolher(suporte) -- em telas pequenas (celular), o HUD diminui (e acerta sozinho se a tela girar)

-- Trocou o jeito de jogar (ex.: o Studio começa no mouse e depois passa para o toque do celular):
-- o HUD vai para o canto certo.
UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
	local agora = Tela.noToque()
	if agora ~= noCelular then
		noCelular = agora
		posicaoDoHud = if agora then POSICAO_NO_CELULAR else POSICAO
		suporte.AnchorPoint = if agora then ANCORA_NO_CELULAR else ANCORA
		suporte.Position = posicaoDoHud
	end
end)

local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.Size = UDim2.new(1, 0, 0, 0)
hud.AutomaticSize = Enum.AutomaticSize.Y -- a altura acompanha o que tem dentro
hud.BackgroundColor3 = COR_PAINEL
hud.BackgroundTransparency = 0.06
hud.BorderSizePixel = 0
hud.Active = true -- (clicar no fundo do HUD não "atravessa" para o jogo)
hud.Parent = suporte
arredondar(hud, 16)
local bordaDoHud = contornar(hud, Color3.new(1, 1, 1), 1)
bordaDoHud.Transparency = 0.86 -- (uma borda clarinha, quase invisível: parece vidro)
local brilhoDoFundo = Instance.new("UIGradient") -- (um pouquinho mais claro em cima)
brilhoDoFundo.Rotation = 90
brilhoDoFundo.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 195, 205))
brilhoDoFundo.Parent = hud
local pulinho = Instance.new("UIScale") -- (os "pulinhos" das animações)
pulinho.Parent = hud
local margem = Instance.new("UIPadding")
margem.PaddingTop = UDim.new(0, 10)
margem.PaddingBottom = UDim.new(0, 10)
margem.PaddingLeft = UDim.new(0, 10)
margem.PaddingRight = UDim.new(0, 10)
margem.Parent = hud
local pilha = Instance.new("UIListLayout") -- um embaixo do outro: título, cartões, botão e bússola
pilha.SortOrder = Enum.SortOrder.LayoutOrder
pilha.Padding = UDim.new(0, 8)
pilha.Parent = hud

-- 1) O TÍTULO (clicar nele também encolhe/abre), com a luzinha de estado
local cabecalho = Instance.new("TextButton")
cabecalho.LayoutOrder = 1
cabecalho.Size = UDim2.new(1, 0, 0, 28)
cabecalho.BackgroundTransparency = 1
cabecalho.Text = ""
cabecalho.AutoButtonColor = false
cabecalho.Parent = hud
local luzinha = Instance.new("Frame") -- verde = spawner perto · dourada = seguindo a seta · cinza = longe
luzinha.AnchorPoint = Vector2.new(0, 0.5)
luzinha.Position = UDim2.new(0, 2, 0.5, 0)
luzinha.Size = UDim2.fromOffset(10, 10)
luzinha.BackgroundColor3 = COR_APAGADO
luzinha.BorderSizePixel = 0
luzinha.Parent = cabecalho
arredondar(luzinha, 5)
local titulo = novoTexto(cabecalho, "VEÍCULOS", 18, COR_TEXTO, Enum.Font.GothamBlack)
titulo.Position = UDim2.fromOffset(20, 0)
titulo.Size = UDim2.new(1, -56, 1, 0)
local botaoEncolher = Instance.new("TextButton")
botaoEncolher.AnchorPoint = Vector2.new(1, 0.5)
botaoEncolher.Position = UDim2.fromScale(1, 0.5)
botaoEncolher.Size = UDim2.fromOffset(28, 28)
botaoEncolher.BackgroundColor3 = COR_CARTAO
botaoEncolher.Text = "–"
botaoEncolher.TextSize = 18
botaoEncolher.Font = Enum.Font.GothamBlack
botaoEncolher.TextColor3 = COR_TEXTO
botaoEncolher.Parent = cabecalho
arredondar(botaoEncolher, 8)

-- 2) OS CARTÕES (a lista rola se tiver muitos veículos)
local lista = Instance.new("ScrollingFrame")
lista.LayoutOrder = 2
lista.Size = UDim2.new(1, 0, 0, 0) -- (a altura é acertada quando os cartões são montados)
lista.BackgroundTransparency = 1
lista.BorderSizePixel = 0
lista.ScrollingDirection = Enum.ScrollingDirection.Y
lista.AutomaticCanvasSize = Enum.AutomaticSize.Y
lista.CanvasSize = UDim2.new()
lista.ScrollBarThickness = 4
lista.ScrollBarImageColor3 = COR_DOURADO
lista.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar -- (a barrinha não fica em cima dos cartões)
lista.Parent = hud
local filaDosCartoes = Instance.new("UIListLayout")
filaDosCartoes.SortOrder = Enum.SortOrder.LayoutOrder
filaDosCartoes.Padding = UDim.new(0, 7)
filaDosCartoes.Parent = lista
local respiroDaLista = Instance.new("UIPadding") -- (espaço para o cartão crescer quando o mouse passa)
respiroDaLista.PaddingTop = UDim.new(0, 5)
respiroDaLista.PaddingBottom = UDim.new(0, 5)
respiroDaLista.PaddingLeft = UDim.new(0, 6)
respiroDaLista.PaddingRight = UDim.new(0, 6)
respiroDaLista.Parent = lista

-- 3) O BOTÃO GRANDE (CHAMAR / MOSTRAR CAMINHO / ESCONDER CAMINHO)
local botao = Instance.new("TextButton")
botao.LayoutOrder = 3
botao.Size = UDim2.new(1, 0, 0, 46)
botao.BackgroundColor3 = COR_APAGADO
botao.AutoButtonColor = false -- (o efeito do mouse é feito aqui embaixo)
botao.Text = ""
botao.Font = Enum.Font.GothamBlack
botao.TextColor3 = COR_TEXTO_FRACO
botao.Parent = hud
arredondar(botao, 12)
botao.TextScaled = true -- (texto comprido diminui para caber)
local limiteDoBotao = Instance.new("UITextSizeConstraint")
limiteDoBotao.MaxTextSize = 18
limiteDoBotao.Parent = botao
local margemDoBotao = Instance.new("UIPadding")
margemDoBotao.PaddingLeft = UDim.new(0, 10)
margemDoBotao.PaddingRight = UDim.new(0, 10)
margemDoBotao.PaddingTop = UDim.new(0, 12)
margemDoBotao.PaddingBottom = UDim.new(0, 12)
margemDoBotao.Parent = botao
local auraDoBotao = contornar(botao, COR_VERDE, 0) -- (a "aura" que pulsa em volta do CHAMAR)
local escalaDoBotao = Instance.new("UIScale")
escalaDoBotao.Parent = botao

-- 4) A BÚSSOLA (uma setinha desenhada que aponta para o spawner) e o aviso do lado
local linha = Instance.new("Frame")
linha.LayoutOrder = 4
linha.Size = UDim2.new(1, 0, 0, 0)
linha.AutomaticSize = Enum.AutomaticSize.Y
linha.BackgroundTransparency = 1
linha.Parent = hud
local bussola = Instance.new("Frame")
bussola.Size = UDim2.fromOffset(28, 28)
bussola.BackgroundColor3 = COR_CARTAO
bussola.BorderSizePixel = 0
bussola.Visible = false
bussola.Parent = linha
arredondar(bussola, 14)
-- a setinha é feita de 3 pedaços (a haste e as 2 pontas); para girar, cada pedaço muda de lugar
type Pedaco = { quadro: Frame, x: number, y: number, giro: number }
local pedacosDaSeta: { Pedaco } = {}
local function pedacoDaSeta(largura: number, altura: number, x: number, y: number, giro: number)
	local quadro = Instance.new("Frame")
	quadro.AnchorPoint = Vector2.new(0.5, 0.5)
	quadro.Size = UDim2.fromOffset(largura, altura)
	quadro.BackgroundColor3 = COR_DOURADO
	quadro.BorderSizePixel = 0
	quadro.Parent = bussola
	arredondar(quadro, 2)
	table.insert(pedacosDaSeta, { quadro = quadro, x = x, y = y, giro = giro })
end
pedacoDaSeta(3, 15, 0, 0.5, 0) -- a haste (em pé: a seta "parada" aponta para cima)
pedacoDaSeta(3, 9, -2.6, -4.9, 40) -- a ponta da esquerda
pedacoDaSeta(3, 9, 2.6, -4.9, -40) -- a ponta da direita
local function girarBussola(angulo: number) -- (angulo em radianos, no sentido do relógio)
	local cosseno, seno = math.cos(angulo), math.sin(angulo)
	for _, pedaco in pedacosDaSeta do
		local x = pedaco.x * cosseno - pedaco.y * seno
		local y = pedaco.x * seno + pedaco.y * cosseno
		pedaco.quadro.Position = UDim2.fromScale(0.5 + x / 28, 0.5 + y / 28)
		pedaco.quadro.Rotation = math.deg(angulo) + pedaco.giro
	end
end
girarBussola(0)
local aviso = novoTexto(linha, "", 13, COR_TEXTO_FRACO, Enum.Font.GothamMedium)
aviso.Size = UDim2.new(1, 0, 0, 0)
aviso.AutomaticSize = Enum.AutomaticSize.Y -- (texto comprido: quebra a linha e o HUD cresce)
aviso.TextWrapped = true

-- 5) A DICA DO CONTROLE: só aparece para quem está jogando com controle (videogame)
local dicaDoControle = novoTexto(hud, "", 12, COR_DOURADO, Enum.Font.GothamBold)
dicaDoControle.LayoutOrder = 5
dicaDoControle.Size = UDim2.new(1, 0, 0, 0)
dicaDoControle.AutomaticSize = Enum.AutomaticSize.Y
dicaDoControle.TextWrapped = true
dicaDoControle.Visible = false

-- =====================================================================
-- OS CARTÕES
-- =====================================================================
type Cartao = {
	molde: Model,
	quadro: Frame,
	contorno: UIStroke,
	escala: UIScale,
	emUso: TextLabel, -- a etiqueta "EM USO"
	marca: Frame, -- o ✓ dourado do escolhido
	escalaDaMarca: UIScale,
	camera: Camera, -- a câmera da vitrine (gira em volta do veículo)
	inicio: CFrame,
	angulo: number,
	aceso: boolean, -- o mouse está em cima?
}
local cartoes: { [string]: Cartao } = {}
local ordemDosCartoes: { string } = {} -- os nomes dos moldes, na ordem dos cartões (para as setas do controle)
local escolhido: string? = nil -- o nome do molde escolhido
local precisaMontar = true -- true = refazer os cartões
local temMouse = UserInputService.MouseEnabled -- (no celular não tem "mouse em cima")

-- Pinta o cartão do jeito certo: escolhido (dourado), aceso (mouse em cima) ou normal.
local function pintarCartao(cartao: Cartao)
	local esteEscolhido = escolhido == cartao.molde.Name
	animar(cartao.quadro, 0.12, { BackgroundColor3 = if cartao.aceso then COR_CARTAO_ACESO else COR_CARTAO })
	cartao.contorno.Color = if esteEscolhido then COR_DOURADO elseif cartao.aceso then COR_TEXTO_FRACO else COR_BORDA
	cartao.contorno.Thickness = if esteEscolhido then 2.5 else 1
	animar(cartao.escala, 0.15, { Scale = if cartao.aceso then 1.03 else 1 })
	cartao.marca.Visible = esteEscolhido
end

local function selecionar(nome: string)
	local antes = escolhido
	escolhido = nome
	for _, cartao in cartoes do
		pintarCartao(cartao)
	end
	local cartao = cartoes[nome]
	if cartao and antes ~= nome then
		cartao.escalaDaMarca.Scale = 0.2 -- o ✓ aparece "pulando"
		animar(cartao.escalaDaMarca, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

local escolherCartao: (Cartao) -> () -- (a função vem mais embaixo; aqui só avisamos que ela existe)

local function criarCartao(molde: Model, ordem: number)
	local quadro = Instance.new("Frame")
	quadro.Name = molde.Name
	quadro.LayoutOrder = ordem
	quadro.Size = UDim2.new(1, 0, 0, 72)
	quadro.BackgroundColor3 = COR_CARTAO
	quadro.BorderSizePixel = 0
	quadro.Parent = lista
	arredondar(quadro, 12)
	local contorno = contornar(quadro, COR_BORDA, 1)
	local escala = Instance.new("UIScale")
	escala.Parent = quadro

	-- a VITRINE (o veículo 3D num "céu"), à esquerda
	local fundo = Instance.new("Frame")
	fundo.Position = UDim2.fromOffset(6, 6)
	fundo.Size = UDim2.fromOffset(80, 60)
	fundo.BackgroundColor3 = Color3.new(1, 1, 1)
	fundo.BorderSizePixel = 0
	fundo.ClipsDescendants = true
	fundo.Parent = quadro
	arredondar(fundo, 9)
	local ceu = Instance.new("UIGradient")
	ceu.Rotation = 90
	ceu.Color = ColorSequence.new(COR_CEU_EM_CIMA, COR_CEU_EMBAIXO)
	ceu.Parent = fundo
	local vitrine = Instance.new("ViewportFrame")
	vitrine.Size = UDim2.fromScale(1, 1)
	vitrine.BackgroundTransparency = 1
	vitrine.Ambient = Color3.fromRGB(170, 170, 180)
	vitrine.LightColor = Color3.new(1, 1, 1)
	vitrine.LightDirection = Vector3.new(-1, -1, -0.6)
	vitrine.Parent = fundo
	local camera, inicio = Vitrine.montar(vitrine, molde, 1.05) -- (a CÓPIA do veículo, com uma câmera olhando para ele)

	-- a etiqueta "EM USO" (em cima da vitrine)
	local emUso = novoTexto(quadro, "EM USO", 10, COR_TEXTO_ESCURO, Enum.Font.GothamBlack)
	emUso.Position = UDim2.fromOffset(10, 10)
	emUso.Size = UDim2.fromOffset(46, 16)
	emUso.TextXAlignment = Enum.TextXAlignment.Center
	emUso.BackgroundTransparency = 0
	emUso.BackgroundColor3 = COR_VERDE
	emUso.ZIndex = 3
	emUso.Visible = false
	arredondar(emUso, 5)

	-- o ✓ dourado do escolhido (no canto de cima da vitrine, à direita)
	local marca = Instance.new("Frame")
	marca.Position = UDim2.fromOffset(64, 9)
	marca.Size = UDim2.fromOffset(20, 20)
	marca.BackgroundColor3 = COR_DOURADO
	marca.BorderSizePixel = 0
	marca.ZIndex = 3
	marca.Visible = false
	marca.Parent = quadro
	arredondar(marca, 10)
	local escalaDaMarca = Instance.new("UIScale")
	escalaDaMarca.Parent = marca
	local visto = novoTexto(marca, "✓", 14, COR_TEXTO_ESCURO, Enum.Font.GothamBlack)
	visto.Size = UDim2.fromScale(1, 1)
	visto.TextXAlignment = Enum.TextXAlignment.Center
	visto.ZIndex = 4

	-- o NOME e a DESCRIÇÃO, à direita
	local nome = novoTexto(quadro, Vitrine.nomeBonito(molde), 15, COR_TEXTO, Enum.Font.GothamBlack)
	nome.Position = UDim2.fromOffset(94, 9)
	nome.Size = UDim2.new(1, -100, 0, 18)
	caber(nome, 15)
	local sobre = novoTexto(quadro, Vitrine.descricao(molde), 12, COR_TEXTO_FRACO, Enum.Font.GothamMedium)
	sobre.Position = UDim2.fromOffset(94, 30)
	sobre.Size = UDim2.new(1, -100, 0, 34)
	sobre.TextWrapped = true
	sobre.TextYAlignment = Enum.TextYAlignment.Top
	sobre.TextTruncate = Enum.TextTruncate.AtEnd

	local cartao: Cartao = {
		molde = molde,
		quadro = quadro,
		contorno = contorno,
		escala = escala,
		emUso = emUso,
		marca = marca,
		escalaDaMarca = escalaDaMarca,
		camera = camera,
		inicio = inicio,
		angulo = 0,
		aceso = false,
	}
	cartoes[molde.Name] = cartao

	-- o mouse e o clique (um botão invisível por cima de tudo)
	local clicar = Instance.new("TextButton")
	clicar.Size = UDim2.fromScale(1, 1)
	clicar.BackgroundTransparency = 1
	clicar.Text = ""
	clicar.ZIndex = 5
	clicar.Parent = quadro
	clicar.MouseEnter:Connect(function()
		if temMouse then
			cartao.aceso = true -- acende e o veículo começa a girar
			pintarCartao(cartao)
			tocar(somPassar, 0.25)
		end
	end)
	clicar.MouseLeave:Connect(function()
		cartao.aceso = false
		pintarCartao(cartao)
	end)
	clicar.MouseButton1Down:Connect(function()
		animar(cartao.escala, 0.08, { Scale = 0.96 }) -- "afunda" ao apertar
	end)
	clicar.Activated:Connect(function()
		escolherCartao(cartao)
	end)
end

-- QUANTOS CARTÕES APARECEM: até MAXIMO_DE_CARTOES, mas numa tela baixa (celular) menos, para o HUD
-- inteiro caber na tela (os outros a lista rola). Cada cartão ocupa 79 (72 + 7 de espaço).
local ALTURA_DO_RESTO = 160 -- (pixels, sem encolher) o título, o botão grande, a bússola e as margens
local ALTURA_DA_DICA = 40 -- (pixels) a dica do controle, quando aparece
local cartoesVisiveis = MAXIMO_DE_CARTOES
local function ajustarAlturaDaLista()
	local maximo = MAXIMO_DE_CARTOES
	local alturaDaTela = tela.AbsoluteSize.Y -- (só a área segura: sem a barra do Roblox e o entalhe)
	local escala = escalaDoHud.Scale
	if alturaDaTela > 0 and escala > 0 then
		local cabe = alturaDaTela / escala - 16 - ALTURA_DO_RESTO - (if dicaDoControle.Visible then ALTURA_DA_DICA else 0)
		maximo = math.clamp(math.floor((cabe + 7 - 10) / 79), 1, MAXIMO_DE_CARTOES)
	end
	cartoesVisiveis = math.min(#ordemDosCartoes, maximo)
	-- a lista mostra cartoesVisiveis cartões (72 + 7 de espaço cada, + 10 de margem); o resto rola
	lista.Size = UDim2.new(1, 0, 0, math.max(cartoesVisiveis * 79 - 7 + 10, 0))
end
tela:GetPropertyChangedSignal("AbsoluteSize"):Connect(ajustarAlturaDaLista) -- (girou a tela, mudou a janela...)
Tela.aoMudar(ajustarAlturaDaLista)

-- (Re)faz todos os cartões: pelo atributo "Ordem"; empatou, o quadriciclo vem antes do monstro; depois, pelo nome.
local function montarCartoes()
	precisaMontar = false
	table.clear(cartoes)
	for _, filho in lista:GetChildren() do
		if filho:IsA("Frame") then
			filho:Destroy()
		end
	end
	local ordenados = Vitrine.ordenar(moldes)
	table.clear(ordemDosCartoes)
	for i, molde in ordenados do
		criarCartao(molde, i)
		table.insert(ordemDosCartoes, molde.Name)
	end
	ajustarAlturaDaLista()
	local atual = escolhido
	if atual == nil or cartoes[atual] == nil then
		escolhido = if ordenados[1] then ordenados[1].Name else nil -- começa com o primeiro escolhido
	end
	local agora = escolhido
	if agora then
		selecionar(agora)
	end
end
moldes.ChildAdded:Connect(function()
	precisaMontar = true
end)
moldes.ChildRemoved:Connect(function()
	precisaMontar = true
end)

-- =====================================================================
-- O SPAWNER MAIS PERTO e O SEU VEÍCULO
-- =====================================================================
local pontosGuardados: { [Instance]: BasePart } = {} -- o "PontoDeSpawn" de cada spawner (para não procurar toda hora)

local function pontoDoSpawner(spawner: Instance): BasePart?
	local guardado = pontosGuardados[spawner]
	if guardado and guardado.Parent then
		return guardado
	end
	local achada = spawner:FindFirstChild("PontoDeSpawn", true)
	local ponto: BasePart? = nil
	if achada and achada:IsA("BasePart") then
		ponto = achada
	elseif spawner:IsA("BasePart") then
		ponto = spawner -- (spawner de uma Part só)
	end
	if ponto then
		pontosGuardados[spawner] = ponto
	end
	return ponto
end
CollectionService:GetInstanceRemovedSignal(TAG_SPAWNER):Connect(function(spawner: Instance)
	pontosGuardados[spawner] = nil
end)

-- Devolve o spawner mais perto de "deOnde", onde fica o PontoDeSpawn dele e a distância.
local function spawnerMaisPerto(deOnde: Vector3): (Instance?, Vector3?, number)
	local melhor: Instance? = nil
	local ondeFica: Vector3? = nil
	local menor = math.huge
	for _, spawner in CollectionService:GetTagged(TAG_SPAWNER) do
		if spawner:IsDescendantOf(workspace) then
			local ponto = pontoDoSpawner(spawner)
			if ponto then
				local distancia = (ponto.Position - deOnde).Magnitude
				if distancia < menor then
					melhor, ondeFica, menor = spawner, ponto.Position, distancia
				end
			end
		end
	end
	return melhor, ondeFica, menor
end

-- O veículo que é SEU agora (o script Spawner marca o dono com o atributo "Dono").
local function meuVeiculo(): Model?
	local pasta = workspace:FindFirstChild("QuadriciclosDosJogadores")
	if pasta == nil then
		return nil
	end
	for _, veiculo in pasta:GetChildren() do
		if veiculo:IsA("Model") and veiculo:GetAttribute("Dono") == jogador.UserId then
			return veiculo
		end
	end
	return nil
end

-- Onde o seu boneco está (nil = ainda sem boneco).
local function posicaoDoJogador(): Vector3?
	local personagem = jogador.Character
	local raiz = if personagem then personagem:FindFirstChild("HumanoidRootPart") else nil
	return if raiz and raiz:IsA("BasePart") then raiz.Position else nil
end

-- =====================================================================
-- O CAMINHO 3D: a SETA dourada em cima de você e a COLUNA DE LUZ no spawner
-- =====================================================================
local pastaDoCaminho = Instance.new("Folder") -- (fica fora do jogo até você ligar o caminho)
pastaDoCaminho.Name = "CaminhoAteOSpawner"

-- Uma peça do caminho: neon dourada, ancorada, sem colisão e invisível para os raios (do veículo e da câmera).
local function pecaDoCaminho(peca: BasePart, pai: Instance, transparencia: number): BasePart
	peca.Color = COR_DOURADO
	peca.Material = Enum.Material.Neon
	peca.Transparency = transparencia
	peca.Anchored = true
	peca.CanCollide = false
	peca.CanQuery = false
	peca.CanTouch = false
	peca.CastShadow = false
	peca.Parent = pai
	return peca
end

-- A SETA: uma haste e uma ponta triangular (2 cunhas, uma de cada lado), deitada e apontando para o spawner.
local seta = Instance.new("Model")
seta.Name = "Seta"
seta.Parent = pastaDoCaminho
local haste = pecaDoCaminho(Instance.new("Part"), seta, 0.05)
local pontaDireita = pecaDoCaminho(Instance.new("WedgePart"), seta, 0.05)
local pontaEsquerda = pecaDoCaminho(Instance.new("WedgePart"), seta, 0.05)
local contornoDaSeta = Instance.new("Highlight") -- contorno branco e aparece até atrás das coisas
contornoDaSeta.FillColor = COR_DOURADO
contornoDaSeta.FillTransparency = 0.6
contornoDaSeta.OutlineColor = Color3.new(1, 1, 1)
contornoDaSeta.OutlineTransparency = 0.1
contornoDaSeta.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
contornoDaSeta.Parent = seta
local escalaDaSeta = 0
local lugarDaHaste, lugarDaDireita, lugarDaEsquerda = CFrame.identity, CFrame.identity, CFrame.identity
-- Acerta o tamanho da seta (1 = normal · 2 = o dobro, para veículos grandes).
local function ajustarSeta(escala: number)
	if math.abs(escala - escalaDaSeta) < 0.05 then
		return
	end
	escalaDaSeta = escala
	local comprimento, larguraDaHaste = 3 * escala, 0.9 * escala
	local comprimentoDaPonta, larguraDaPonta = 2.2 * escala, 3 * escala
	local grossura = 0.5 * escala
	haste.Size = Vector3.new(larguraDaHaste, grossura, comprimento)
	pontaDireita.Size = Vector3.new(grossura, larguraDaPonta / 2, comprimentoDaPonta)
	pontaEsquerda.Size = Vector3.new(grossura, larguraDaPonta / 2, comprimentoDaPonta)
	-- (onde cada pedaço fica em relação ao meio da seta; a "frente" da seta é o -Z)
	lugarDaHaste = CFrame.new(0, 0, comprimentoDaPonta / 2)
	lugarDaDireita = CFrame.fromMatrix(Vector3.new(larguraDaPonta / 4, 0, -comprimento / 2), -Vector3.yAxis, Vector3.xAxis)
	lugarDaEsquerda = CFrame.fromMatrix(Vector3.new(-larguraDaPonta / 4, 0, -comprimento / 2), Vector3.yAxis, -Vector3.xAxis)
end
ajustarSeta(1)

-- A COLUNA DE LUZ no spawner, com a placa "GARAGEM" e a distância (aparece até atrás dos morros)
local coluna = Instance.new("Part")
coluna.Name = "ColunaDeLuz"
coluna.Shape = Enum.PartType.Cylinder -- (o cilindro fica deitado no X: lá embaixo ele é girado para ficar em pé)
coluna.Size = Vector3.new(ALTURA_DA_COLUNA, 2.5, 2.5)
pecaDoCaminho(coluna, pastaDoCaminho, 0.55)
local placa = Instance.new("BillboardGui")
placa.Name = "PlacaDaGaragem"
placa.Size = UDim2.fromOffset(150, 52)
placa.AlwaysOnTop = true
placa.LightInfluence = 0
placa.StudsOffsetWorldSpace = Vector3.new(0, -ALTURA_DA_COLUNA / 2 + 10, 0) -- (10 studs acima do spawner)
placa.Adornee = coluna
placa.Parent = coluna
local fundoDaPlaca = Instance.new("Frame")
fundoDaPlaca.Size = UDim2.fromScale(1, 1)
fundoDaPlaca.BackgroundColor3 = COR_PAINEL
fundoDaPlaca.BackgroundTransparency = 0.1
fundoDaPlaca.BorderSizePixel = 0
fundoDaPlaca.Parent = placa
arredondar(fundoDaPlaca, 12)
contornar(fundoDaPlaca, COR_DOURADO, 2)
local tituloDaPlaca = novoTexto(fundoDaPlaca, "GARAGEM", 18, COR_DOURADO, Enum.Font.GothamBlack)
tituloDaPlaca.Position = UDim2.fromScale(0, 0.08)
tituloDaPlaca.Size = UDim2.fromScale(1, 0.5)
tituloDaPlaca.TextXAlignment = Enum.TextXAlignment.Center
local distanciaDaPlaca = novoTexto(fundoDaPlaca, "", 14, COR_TEXTO, Enum.Font.GothamBold)
distanciaDaPlaca.Position = UDim2.fromScale(0, 0.52)
distanciaDaPlaca.Size = UDim2.fromScale(1, 0.4)
distanciaDaPlaca.TextXAlignment = Enum.TextXAlignment.Center

local direcaoDaSeta = Vector3.new(0, 0, -1) -- (vira devagarinho para o spawner)
local alturaDaSeta = ALTURA_DA_SETA

-- =====================================================================
-- O ESTADO DO HUD
-- =====================================================================
local spawnerAlvo: Instance? = nil -- o spawner mais perto
local pontoAlvo: Vector3? = nil -- onde ele fica
local distanciaAlvo = math.huge
local estaPerto = false -- perto o bastante para CHAMAR?
local nomeEmUso: string? = nil -- o molde do veículo que você está usando
local dirigindo = false
local veiculoMedido: Model? = nil -- (o veículo que já foi medido para a seta ficar acima dele)
local guiando = false -- o caminho (seta 3D + coluna) está ligado?
local estadoDoBotao = "semSpawner" -- "chamar" · "mostrar" · "esconder" · "semSpawner" · "semVeiculo"
local mensagem = "" -- um aviso que fica uns segundos ("Pronto!", "Espere um pouquinho"...)
local corDaMensagem = COR_TEXTO_FRACO
local mensagemAte = 0 -- (os.clock) até quando o aviso fica
local esperandoAte = 0 -- (os.clock) pediu o veículo: espera a resposta do servidor até aqui
local prontoAte = 0 -- (os.clock) mostra "PRONTO!" no botão até aqui
local encolhido = ENCOLHIDO_NO_CELULAR and Tela.noToque()
local botaoAceso = false -- mouse em cima do botão grande?
local botaoApertado = false
local escalaDoBotaoAgora = 1

local function avisar(texto: string, cor: Color3, segundos: number)
	mensagem = texto
	corDaMensagem = cor
	mensagemAte = os.clock() + segundos
end

-- A dica do controle: muda com o HUD aberto ou encolhido (e some sem controle).
local function atualizarDica()
	local comControle = Tela.noControle()
	if dicaDoControle.Visible ~= comControle then
		dicaDoControle.Visible = comControle
		task.defer(ajustarAlturaDaLista) -- (a dica ocupa espaço: a lista se ajusta)
	end
	if comControle then
		dicaDoControle.Text = if encolhido
			then "Controle: ▼ abre os veículos"
			else "Controle: ◀ ▶ escolhe · ▲ aperta o botão · ▼ esconde"
	end
end
UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(atualizarDica)

local function aplicarEncolhido()
	lista.Visible = not encolhido
	botao.Visible = not encolhido
	linha.Visible = not encolhido
	botaoEncolher.Text = if encolhido then "+" else "–"
	atualizarDica()
end

-- Põe a seta em cima de você, apontando (devagarinho) para o spawner. Roda a cada frame.
local function posicionarSeta(dt: number)
	local alvo = pontoAlvo
	local ondeEstou = posicaoDoJogador()
	if alvo == nil or ondeEstou == nil then
		return
	end
	local deitada = Vector3.new(alvo.X - ondeEstou.X, 0, alvo.Z - ondeEstou.Z)
	if deitada.Magnitude > 1 then
		local nova = direcaoDaSeta:Lerp(deitada.Unit, math.min(dt * 8, 1))
		if nova.Magnitude > 0.01 then
			direcaoDaSeta = nova.Unit
		end
	end
	local balanco = math.sin(os.clock() * 3) * 0.35 * escalaDaSeta -- (sobe e desce, como se flutuasse)
	local meio = ondeEstou + Vector3.new(0, alturaDaSeta + balanco, 0)
	local virada = CFrame.lookAt(meio, meio + direcaoDaSeta)
	haste.CFrame = virada * lugarDaHaste
	pontaDireita.CFrame = virada * lugarDaDireita
	pontaEsquerda.CFrame = virada * lugarDaEsquerda
end

-- Pinta o botão grande de acordo com o estado (e com o mouse em cima).
local function pintarBotao()
	local agora = os.clock()
	local cor, corDoTexto, texto = COR_APAGADO, COR_TEXTO_FRACO, ""
	if estadoDoBotao == "chamar" then
		cor, corDoTexto = COR_VERDE, COR_TEXTO_ESCURO
		if agora < prontoAte then
			texto = "PRONTO!"
		elseif agora < esperandoAte then
			texto = "CHAMANDO" .. string.rep(".", math.floor(agora * 3) % 4) -- (os pontinhos andam)
		else
			texto = "CHAMAR"
		end
	elseif estadoDoBotao == "mostrar" then
		cor, corDoTexto, texto = COR_DOURADO, COR_TEXTO_ESCURO, "MOSTRAR CAMINHO"
	elseif estadoDoBotao == "esconder" then
		cor, corDoTexto, texto = COR_CARTAO, COR_DOURADO, "ESCONDER CAMINHO"
	elseif estadoDoBotao == "semVeiculo" then
		texto = "SEM VEÍCULOS"
	else
		texto = "SEM SPAWNER NO MAPA"
	end
	local temAcao = estadoDoBotao == "chamar" or estadoDoBotao == "mostrar" or estadoDoBotao == "esconder"
	if botaoAceso and temAcao then
		cor = cor:Lerp(Color3.new(1, 1, 1), 0.15) -- mouse em cima: clareia
	end
	botao.BackgroundColor3 = cor
	botao.TextColor3 = corDoTexto
	botao.Text = texto
end

local function atualizarHud()
	if precisaMontar then
		montarCartoes()
	end
	local agora = os.clock()
	-- 1) (o tamanho do HUD em telas pequenas agora é o módulo Tela que acerta, lá no começo)
	-- 2) o seu veículo (EM USO) e se você está dirigindo
	local veiculo = meuVeiculo()
	nomeEmUso = if veiculo then veiculo.Name else nil
	for nome, cartao in cartoes do
		cartao.emUso.Visible = nome == nomeEmUso
	end
	local personagem = jogador.Character
	local humanoide = if personagem then personagem:FindFirstChildOfClass("Humanoid") else nil
	local banco = if humanoide then humanoide.SeatPart else nil
	dirigindo = banco ~= nil and banco:IsA("VehicleSeat")
	-- 3) o spawner mais perto
	local ondeEstou = posicaoDoJogador()
	spawnerAlvo, pontoAlvo, distanciaAlvo = nil, nil, math.huge
	if ondeEstou then
		spawnerAlvo, pontoAlvo, distanciaAlvo = spawnerMaisPerto(ondeEstou)
	end
	local antesPerto = estaPerto
	estaPerto = spawnerAlvo ~= nil and distanciaAlvo <= DISTANCIA_PARA_CHAMAR
	-- 4) o caminho: chegou? Desliga sozinho (e avisa). Sem spawner? Desliga também.
	if guiando and estaPerto then
		guiando = false
		if not antesPerto then
			avisar("Você chegou! Agora é só CHAMAR.", COR_VERDE, 3)
			tocar(somPronto)
		end
	elseif pontoAlvo == nil then
		guiando = false
	end
	-- 5) o botão grande
	if escolhido == nil then
		estadoDoBotao = "semVeiculo"
	elseif estaPerto then
		estadoDoBotao = "chamar"
	elseif pontoAlvo then
		estadoDoBotao = if guiando then "esconder" else "mostrar"
	else
		estadoDoBotao = "semSpawner"
	end
	pintarBotao()
	-- 6) a luzinha do título
	luzinha.BackgroundColor3 = if estaPerto then COR_VERDE elseif guiando then COR_DOURADO else COR_APAGADO
	-- 7) a linha de aviso e a bússola
	local comBussola = pontoAlvo ~= nil and not estaPerto
	bussola.Visible = comBussola
	bussola.BackgroundColor3 = if guiando then COR_DOURADO else COR_CARTAO
	for _, pedaco in pedacosDaSeta do
		pedaco.quadro.BackgroundColor3 = if guiando then COR_PAINEL else COR_DOURADO
	end
	local texto, cor = "", COR_TEXTO_FRACO
	if agora < mensagemAte then
		texto, cor = mensagem, corDaMensagem
	elseif escolhido == nil then
		texto = "Nenhum veículo na pasta ReplicatedStorage > Quadriciclos."
	elseif estaPerto then
		texto, cor = "Spawner aqui! CHAMAR traz o escolhido (o antigo some).", COR_VERDE
	elseif pontoAlvo then
		texto = `Spawner a {math.floor(distanciaAlvo)} studs`
		if guiando then
			texto ..= " · siga a seta dourada"
			cor = COR_DOURADO
		end
	else
		texto = "Nenhum spawner no mapa (ou ele ainda está carregando)."
	end
	aviso.Text = texto
	aviso.TextColor3 = cor
	aviso.Position = UDim2.fromOffset(if comBussola then 36 else 0, if comBussola then 6 else 0)
	aviso.Size = UDim2.new(1, if comBussola then -36 else 0, 0, 0)
	-- 8) a seta 3D e a coluna de luz (só seguindo o caminho)
	local ponto = pontoAlvo
	if guiando and ponto and ondeEstou then
		-- dirigindo, a seta fica acima do veículo (e maior, se o veículo for grande)
		if dirigindo and veiculo then
			if veiculo ~= veiculoMedido then
				veiculoMedido = veiculo
				local caixa, tamanho = veiculo:GetBoundingBox()
				local topo = caixa.Position.Y + tamanho.Y / 2
				alturaDaSeta = math.max(topo - ondeEstou.Y, 2) + ALTURA_DA_SETA * 0.6
				ajustarSeta(math.clamp(math.max(tamanho.X, tamanho.Z) / 10, 1, 2))
			end
		else
			veiculoMedido = nil
			alturaDaSeta = ALTURA_DA_SETA
			ajustarSeta(1)
		end
		coluna.CFrame = CFrame.new(ponto + Vector3.new(0, ALTURA_DA_COLUNA / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		distanciaDaPlaca.Text = `{math.floor(distanciaAlvo)} studs`
		if pastaDoCaminho.Parent == nil then
			posicionarSeta(1) -- (já no lugar certo antes de aparecer)
			pastaDoCaminho.Parent = workspace
		end
	elseif pastaDoCaminho.Parent ~= nil then
		pastaDoCaminho.Parent = nil
	end
end

-- =====================================================================
-- CLIQUES E RESPOSTAS DO SERVIDOR
-- =====================================================================
escolherCartao = function(cartao: Cartao)
	local nome = cartao.molde.Name
	selecionar(nome)
	pintarCartao(cartao)
	tocar(somEscolher)
	-- longe do spawner e escolheu um veículo diferente do seu? Já liga o caminho até o spawner.
	if not estaPerto and pontoAlvo ~= nil and nome ~= nomeEmUso and not guiando then
		guiando = true
		avisar("Siga a seta dourada até o spawner!", COR_DOURADO, 3)
	end
	atualizarHud()
end

local function encolherOuAbrir()
	encolhido = not encolhido
	aplicarEncolhido()
	tocar(somEscolher, 0.6)
	pulinho.Scale = 0.96
	animar(pulinho, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end
botaoEncolher.Activated:Connect(encolherOuAbrir)
cabecalho.Activated:Connect(encolherOuAbrir)

local function chamar()
	local nome = escolhido
	local ondeEstou = posicaoDoJogador()
	if nome == nil or ondeEstou == nil or os.clock() < esperandoAte then
		return
	end
	local spawner, _, distancia = spawnerMaisPerto(ondeEstou)
	if spawner == nil or distancia > DISTANCIA_PARA_CHAMAR then
		avisar("Chegue perto de um spawner para chamar o veículo.", COR_DOURADO, 2.5)
		tocar(somErro)
		return
	end
	esperandoAte = os.clock() + 2.5 -- (se o servidor não responder, libera o botão depois de 2,5 s)
	tocar(somEscolher)
	remoto:FireServer("Spawnar", spawner, nome) -- o mesmo pedido da garagem: o servidor confere e responde
end

-- O botão grande: CHAMAR, MOSTRAR CAMINHO ou ESCONDER CAMINHO (o clique e o controle usam esta função).
local function apertarBotaoGrande()
	if estadoDoBotao == "chamar" then
		chamar()
	elseif estadoDoBotao == "mostrar" then
		guiando = true
		tocar(somEscolher)
		avisar("Siga a seta dourada até o spawner!", COR_DOURADO, 3)
	elseif estadoDoBotao == "esconder" then
		guiando = false
		tocar(somEscolher, 0.6)
	else
		tocar(somErro)
	end
	atualizarHud()
end
botao.Activated:Connect(apertarBotaoGrande)

-- =====================================================================
-- (NOVO) CONTROLE (videogame): as setas do direcional, andando a pé
-- =====================================================================
--   ◀ ▶ = escolhe o veículo anterior/seguinte · ▲ = aperta o botão grande · ▼ = encolhe/abre o HUD
-- Dirigindo, essas setas são do veículo (buzina, desvirar e trocar o gancho): as teclas do veículo têm
-- prioridade maior, então aqui elas só funcionam a pé.
local ACAO_DO_CONTROLE = "SeletorDeVeiculoControle"
local PRIORIDADE_DO_CONTROLE = Enum.ContextActionPriority.Medium.Value -- (abaixo das teclas do veículo)

-- Escolhe o veículo do lado (passo = -1 o anterior, 1 o seguinte; depois do último, volta ao primeiro).
local function escolherOutro(passo: number)
	if encolhido then
		encolherOuAbrir() -- (primeiro abre o HUD, para você ver os veículos)
		return
	end
	local total = #ordemDosCartoes
	if total == 0 then
		tocar(somErro)
		return
	end
	local atual = table.find(ordemDosCartoes, escolhido or "") or 0
	local proximo = if atual == 0 then 1 else (atual - 1 + passo) % total + 1
	local cartao = cartoes[ordemDosCartoes[proximo]]
	if cartao then
		escolherCartao(cartao)
		-- a lista rola até ele (quando tem mais veículos do que cabem)
		lista.CanvasPosition = Vector2.new(0, math.max(0, (proximo - math.max(cartoesVisiveis, 1)) * 79))
	end
end

local function acaoDoControle(_nome: string, estadoDaEntrada: Enum.UserInputState, entrada: InputObject): Enum.ContextActionResult?
	if GuiService.SelectedObject ~= nil then
		return Enum.ContextActionResult.Pass -- (navegando numa tela, como a Garagem: as setas são dela)
	end
	if estadoDaEntrada ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local tecla = entrada.KeyCode
	if tecla == Enum.KeyCode.DPadLeft then
		escolherOutro(-1)
	elseif tecla == Enum.KeyCode.DPadRight then
		escolherOutro(1)
	elseif tecla == Enum.KeyCode.DPadUp then
		if encolhido then
			encolherOuAbrir() -- (abre, para você ver o que aconteceu)
		end
		botaoApertado = true -- o botão "afunda" um instante, como num clique
		task.delay(0.15, function()
			botaoApertado = false
		end)
		apertarBotaoGrande()
	elseif tecla == Enum.KeyCode.DPadDown then
		encolherOuAbrir()
	end
	return Enum.ContextActionResult.Sink
end
ContextActionService:BindActionAtPriority(ACAO_DO_CONTROLE, acaoDoControle, false, PRIORIDADE_DO_CONTROLE,
	Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown)
botao.MouseEnter:Connect(function()
	botaoAceso = temMouse
	pintarBotao()
end)
botao.MouseLeave:Connect(function()
	botaoAceso = false
	botaoApertado = false
	pintarBotao()
end)
botao.MouseButton1Down:Connect(function()
	botaoApertado = true
end)
botao.MouseButton1Up:Connect(function()
	botaoApertado = false
end)

remoto.OnClientEvent:Connect(function(acao: unknown, dado: unknown)
	if acao == "Pronto" then
		esperandoAte = 0
		prontoAte = os.clock() + 1.2
		guiando = false
		avisar("Pronto! Boa viagem.", COR_VERDE, 2.5)
		tocar(somPronto)
		pulinho.Scale = 1.05 -- o HUD dá um pulinho de comemoração
		animar(pulinho, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	elseif acao == "Aviso" and typeof(dado) == "string" then
		esperandoAte = 0
		avisar(dado, COR_DOURADO, 3) -- ex.: "Espere um pouquinho para pegar outro quadriciclo."
		tocar(somErro)
	else
		return -- ("Abrir" é da tela da garagem: não é com o HUD)
	end
	atualizarHud()
end)

-- =====================================================================
-- A CADA FRAME: os veículos dos cartões giram, o botão pulsa, a bússola e a seta 3D apontam
-- =====================================================================
local tempoDoGiro = 0 -- (s) desde a última vez que o veículo escolhido foi redesenhado
RunService.RenderStepped:Connect(function(dt: number)
	if not encolhido then
		-- 1) gira o veículo do cartão com o mouse em cima, e o escolhido (dirigindo, só o do mouse: economiza)
		--    (OTIMIZADO) O escolhido é redesenhado GIRO_DO_ESCOLHIDO_POR_SEGUNDO vezes por segundo, e não
		--    todo frame: cada redesenho da vitrine desenha o veículo inteiro de novo (o caminhão tem 100+ peças).
		tempoDoGiro += dt
		local redesenharEscolhido = tempoDoGiro >= 1 / GIRO_DO_ESCOLHIDO_POR_SEGUNDO
		if redesenharEscolhido then
			tempoDoGiro = 0
		end
		for nome, cartao in cartoes do
			if cartao.aceso or (nome == escolhido and not dirigindo) then
				cartao.angulo += dt * GIRO_DA_VITRINE -- (a velocidade do giro continua a mesma)
				if cartao.aceso or redesenharEscolhido then
					cartao.camera.CFrame = CFrame.Angles(0, cartao.angulo, 0) * cartao.inicio
				end
			end
		end
		-- 2) o botão: cresce com o mouse, afunda ao apertar e o CHAMAR "respira" com uma aura verde
		local alvo = if botaoApertado then 0.95 elseif botaoAceso then 1.03 else 1
		escalaDoBotaoAgora += (alvo - escalaDoBotaoAgora) * math.min(dt * 18, 1)
		local respirar = if estadoDoBotao == "chamar" then (math.sin(os.clock() * 4) + 1) / 2 else 0
		escalaDoBotao.Scale = escalaDoBotaoAgora + 0.025 * respirar
		if estadoDoBotao == "chamar" then
			auraDoBotao.Color = COR_VERDE
			auraDoBotao.Thickness = 1 + 3 * respirar
			auraDoBotao.Transparency = 0.2 + 0.6 * respirar
		elseif estadoDoBotao == "esconder" then
			auraDoBotao.Color = COR_DOURADO
			auraDoBotao.Thickness = 1.5
			auraDoBotao.Transparency = 0
		else
			auraDoBotao.Thickness = 0
		end
		-- 3) a bússola: "para cima" = para onde a câmera olha; gira para o lado do spawner
		local alvoDaBussola = pontoAlvo
		local camera = workspace.CurrentCamera
		local ondeEstou = posicaoDoJogador()
		if bussola.Visible and alvoDaBussola and camera and ondeEstou then
			local direcao = alvoDaBussola - ondeEstou
			local olhar = camera.CFrame.LookVector
			girarBussola(math.atan2(direcao.X, -direcao.Z) - math.atan2(olhar.X, -olhar.Z))
		end
	end
	-- 4) a seta 3D (funciona até com o HUD encolhido)
	if pastaDoCaminho.Parent ~= nil then
		posicionarSeta(dt)
	end
end)

-- =====================================================================
-- COMEÇA! (o HUD entra deslizando da esquerda)
-- =====================================================================
aplicarEncolhido()
suporte.Position = posicaoDoHud - UDim2.fromOffset(LARGURA + 40, 0)
animar(suporte, 0.6, { Position = posicaoDoHud }, Enum.EasingStyle.Back)
task.spawn(function()
	while true do
		-- (xpcall: se der algum erro, ele aparece no Output, mas o HUD continua funcionando)
		xpcall(atualizarHud, function(erro: unknown)
			warn("[SeletorDeVeiculo] " .. tostring(erro))
		end)
		task.wait(0.2)
	end
end)
