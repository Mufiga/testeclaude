--!strict
--[[
	=====================================================================
	GaragemCliente  (LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > GaragemCliente
	=====================================================================

	A TELA DA GARAGEM: abre quando você aperta E num spawner (quem manda abrir é o script Spawner).
	  - Cada quadriciclo da pasta ReplicatedStorage > Quadriciclos vira um CARTÃO com o modelo 3D
	    dele girando (ViewportFrame: é o próprio modelo, não precisa subir imagem nenhuma).
	  - Clique num cartão para escolher e em SPAWNAR: ele aparece no spawner e você já senta.
	  - Fecha no X ou quando você se afasta do spawner.
	  - Dirigindo, o aviso "E  Garagem" fica escondido (no quadriciclo, o E serve para sair do banco).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local jogador = Players.LocalPlayer :: Player
local remoto = ReplicatedStorage:WaitForChild("Garagem") :: RemoteEvent
local moldes = ReplicatedStorage:WaitForChild("Quadriciclos")

-- =====================================================================
-- AJUSTES
-- =====================================================================
local COR_FUNDO = Color3.fromRGB(18, 19, 26) -- o painel
local COR_CARTAO = Color3.fromRGB(32, 34, 46) -- cada cartão
local COR_BORDA = Color3.fromRGB(60, 63, 80) -- borda do cartão não escolhido
local COR_DESTAQUE = Color3.fromRGB(170, 90, 255) -- roxo: borda do painel e do cartão escolhido
local COR_BOTAO = Color3.fromRGB(90, 225, 125) -- o botão SPAWNAR
local COR_TEXTO_FRACO = Color3.fromRGB(170, 175, 190)
local DISTANCIA_PARA_FECHAR = 30 -- (studs) se afastou disso do spawner, a garagem fecha
local GIRO_DA_VITRINE = 0.6 -- (radianos/s) velocidade do giro dos quadriciclos nos cartões

-- =====================================================================
-- FERRAMENTAS (deixam o código da tela mais curto)
-- =====================================================================
local function numero(valor: unknown, padrao: number): number
	return if typeof(valor) == "number" then valor else padrao
end

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

-- O nome que aparece no cartão: o atributo "NomeExibido" do molde (ou o nome do Model).
local function nomeBonito(molde: Instance): string
	local nome = molde:GetAttribute("NomeExibido")
	return if typeof(nome) == "string" and nome ~= "" then nome else molde.Name
end

-- =====================================================================
-- A TELA (criada uma vez; fica escondida até abrir)
-- =====================================================================
local tela = Instance.new("ScreenGui")
tela.Name = "Garagem"
tela.ResetOnSpawn = false
tela.IgnoreGuiInset = true -- cobre a tela inteira
tela.DisplayOrder = 30 -- por cima dos outros HUDs
tela.Enabled = false
tela.Parent = jogador:WaitForChild("PlayerGui")

local escurecer = Instance.new("Frame") -- deixa o jogo atrás mais escuro
escurecer.Size = UDim2.fromScale(1, 1)
escurecer.BackgroundColor3 = Color3.new(0, 0, 0)
escurecer.BackgroundTransparency = 0.45
escurecer.BorderSizePixel = 0
escurecer.Parent = tela

local painel = Instance.new("Frame")
painel.AnchorPoint = Vector2.new(0.5, 0.5)
painel.Position = UDim2.fromScale(0.5, 0.5)
painel.Size = UDim2.fromScale(0.72, 0.64)
painel.BackgroundColor3 = COR_FUNDO
painel.BorderSizePixel = 0
painel.Parent = tela
arredondar(painel, 18)
contornar(painel, COR_DESTAQUE, 2)
local limites = Instance.new("UISizeConstraint") -- nem pequeno demais (celular) nem enorme (monitor grande)
limites.MinSize = Vector2.new(330, 300)
limites.MaxSize = Vector2.new(920, 540)
limites.Parent = painel
local escalaDoPainel = Instance.new("UIScale") -- (para a animação de abrir)
escalaDoPainel.Parent = painel

local titulo = novoTexto(painel, "GARAGEM", 30, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
titulo.Position = UDim2.fromOffset(22, 14)
titulo.Size = UDim2.new(1, -100, 0, 36)
local subtitulo = novoTexto(painel, "Escolha seu quadriciclo", 15, COR_TEXTO_FRACO, Enum.Font.GothamMedium)
subtitulo.Position = UDim2.fromOffset(22, 50)
subtitulo.Size = UDim2.new(1, -100, 0, 20)

local botaoFechar = Instance.new("TextButton")
botaoFechar.AnchorPoint = Vector2.new(1, 0)
botaoFechar.Position = UDim2.new(1, -14, 0, 14)
botaoFechar.Size = UDim2.fromOffset(40, 40)
botaoFechar.BackgroundColor3 = COR_CARTAO
botaoFechar.Text = "X"
botaoFechar.TextSize = 20
botaoFechar.Font = Enum.Font.GothamBlack
botaoFechar.TextColor3 = Color3.new(1, 1, 1)
botaoFechar.Modal = true -- solta o mouse (até em primeira pessoa) enquanto a garagem está aberta
botaoFechar.Parent = painel
arredondar(botaoFechar, 10)

-- A fila de cartões (rola para o lado quando tem muitos quadriciclos).
local lista = Instance.new("ScrollingFrame")
lista.Position = UDim2.fromOffset(16, 82)
lista.Size = UDim2.new(1, -32, 1, -164)
lista.BackgroundTransparency = 1
lista.BorderSizePixel = 0
lista.ScrollingDirection = Enum.ScrollingDirection.X
lista.AutomaticCanvasSize = Enum.AutomaticSize.X -- a largura cresce com os cartões
lista.CanvasSize = UDim2.fromScale(0, 1) -- a altura é a da própria lista
lista.ScrollBarThickness = 6
lista.ScrollBarImageColor3 = COR_DESTAQUE
lista.Parent = painel
local fila = Instance.new("UIListLayout")
fila.FillDirection = Enum.FillDirection.Horizontal
fila.SortOrder = Enum.SortOrder.LayoutOrder
fila.VerticalAlignment = Enum.VerticalAlignment.Center
fila.Padding = UDim.new(0, 16)
fila.Parent = lista
local respiro = Instance.new("UIPadding")
respiro.PaddingLeft = UDim.new(0, 6)
respiro.PaddingRight = UDim.new(0, 6)
respiro.Parent = lista

local botaoSpawnar = Instance.new("TextButton")
botaoSpawnar.AnchorPoint = Vector2.new(1, 1)
botaoSpawnar.Position = UDim2.new(1, -20, 1, -18)
botaoSpawnar.Size = UDim2.fromOffset(220, 52)
botaoSpawnar.BackgroundColor3 = COR_BOTAO
botaoSpawnar.Text = "SPAWNAR"
botaoSpawnar.TextSize = 24
botaoSpawnar.Font = Enum.Font.GothamBlack
botaoSpawnar.TextColor3 = Color3.fromRGB(15, 30, 20)
botaoSpawnar.Parent = painel
arredondar(botaoSpawnar, 14)
local brilhoDoBotao = Instance.new("UIGradient") -- mais claro em cima, mais escuro embaixo
brilhoDoBotao.Rotation = 90
brilhoDoBotao.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
brilhoDoBotao.Parent = botaoSpawnar

local estado = novoTexto(painel, "", 15, COR_TEXTO_FRACO, Enum.Font.GothamMedium) -- "Selecionado: ..." e avisos
estado.AnchorPoint = Vector2.new(0, 1)
estado.Position = UDim2.new(0, 22, 1, -18)
estado.Size = UDim2.new(1, -270, 0, 52)
estado.TextWrapped = true

-- =====================================================================
-- OS CARTÕES
-- =====================================================================
type Vitrine = { camera: Camera, inicio: CFrame }
type Cartao = { contorno: UIStroke, escala: UIScale }
local vitrines: { Vitrine } = {} -- as câmeras dos cartões (giram em volta dos quadriciclos)
local cartoes: { [string]: Cartao } = {}
local escolhido: string? = nil -- o nome do molde escolhido
local precisaMontar = true -- true = refazer os cartões na próxima vez que abrir

-- Coloca uma CÓPIA do quadriciclo dentro do ViewportFrame, com uma câmera olhando para ele.
local function montarVitrine(viewport: ViewportFrame, molde: Model)
	local copia = molde:Clone() :: Model -- (o "::" só confirma para o Studio que a cópia é um Model)
	for _, coisa in copia:GetDescendants() do
		if coisa:IsA("BaseScript") or coisa:IsA("ModuleScript") or coisa:IsA("Sound") then
			coisa:Destroy() -- a vitrine é só para ver: sem scripts e sem sons
		end
	end
	local caixa, tamanho = copia:GetBoundingBox() -- a "caixa" que cabe o quadriciclo inteiro
	copia:PivotTo(copia:GetPivot() - caixa.Position) -- o meio dele fica no ponto (0, 0, 0)
	copia.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distancia = tamanho.Magnitude * 1.15 -- quadriciclo maior = câmera mais longe
	local inicio = CFrame.lookAt(Vector3.new(distancia * 0.72, distancia * 0.38, distancia * 0.72), Vector3.zero)
	camera.CFrame = inicio
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	table.insert(vitrines, { camera = camera, inicio = inicio })
end

-- Marca o cartão escolhido (borda roxa e um pouquinho maior).
local function selecionar(nome: string)
	escolhido = nome
	for nomeDoCartao, cartao in cartoes do
		local este = nomeDoCartao == nome
		cartao.contorno.Color = if este then COR_DESTAQUE else COR_BORDA
		cartao.contorno.Thickness = if este then 4 else 2
		TweenService:Create(cartao.escala, TweenInfo.new(0.15), { Scale = if este then 1.04 else 1 }):Play()
	end
	local molde = moldes:FindFirstChild(nome)
	estado.Text = if molde then `Selecionado: {nomeBonito(molde)}` else ""
end

local function criarCartao(molde: Model, ordem: number)
	local cartao = Instance.new("Frame")
	cartao.Name = molde.Name
	cartao.LayoutOrder = ordem
	cartao.Size = UDim2.new(0, 0, 1, -12)
	cartao.BackgroundColor3 = COR_CARTAO
	cartao.BorderSizePixel = 0
	cartao.Parent = lista
	arredondar(cartao, 14)
	local proporcao = Instance.new("UIAspectRatioConstraint") -- a largura acompanha a altura
	proporcao.AspectRatio = 0.78
	proporcao.DominantAxis = Enum.DominantAxis.Height
	proporcao.Parent = cartao
	local contorno = contornar(cartao, COR_BORDA, 2)
	local escala = Instance.new("UIScale")
	escala.Parent = cartao

	-- A VITRINE: um fundo com degradê e, por cima, o quadriciclo 3D.
	local fundo = Instance.new("Frame")
	fundo.Position = UDim2.fromOffset(8, 8)
	fundo.Size = UDim2.new(1, -16, 0.7, -8)
	fundo.BackgroundColor3 = Color3.fromRGB(70, 66, 96)
	fundo.BorderSizePixel = 0
	fundo.Parent = cartao
	arredondar(fundo, 10)
	local degrade = Instance.new("UIGradient")
	degrade.Rotation = 90
	degrade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(110, 100, 140))
	degrade.Parent = fundo
	local vitrine = Instance.new("ViewportFrame")
	vitrine.Size = UDim2.fromScale(1, 1)
	vitrine.BackgroundTransparency = 1
	vitrine.Ambient = Color3.fromRGB(150, 150, 165)
	vitrine.LightColor = Color3.new(1, 1, 1)
	vitrine.LightDirection = Vector3.new(-1, -1, -0.6)
	vitrine.Parent = fundo
	montarVitrine(vitrine, molde)

	local nome = novoTexto(cartao, nomeBonito(molde), 18, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	nome.Position = UDim2.new(0, 12, 0.7, 6)
	nome.Size = UDim2.new(1, -24, 0, 22)
	nome.TextTruncate = Enum.TextTruncate.AtEnd
	local textoDaDescricao = molde:GetAttribute("Descricao")
	local descricao = novoTexto(cartao, if typeof(textoDaDescricao) == "string" then textoDaDescricao else "", 13, COR_TEXTO_FRACO, Enum.Font.GothamMedium)
	descricao.Position = UDim2.new(0, 12, 0.7, 30)
	descricao.Size = UDim2.new(1, -24, 0.3, -38)
	descricao.TextWrapped = true
	descricao.TextYAlignment = Enum.TextYAlignment.Top

	local clicar = Instance.new("TextButton") -- invisível, por cima de tudo: clicar escolhe este
	clicar.Size = UDim2.fromScale(1, 1)
	clicar.BackgroundTransparency = 1
	clicar.Text = ""
	clicar.ZIndex = 5
	clicar.Parent = cartao
	clicar.Activated:Connect(function()
		selecionar(molde.Name)
	end)
	cartoes[molde.Name] = { contorno = contorno, escala = escala }
end

-- (Re)faz todos os cartões, na ordem do atributo "Ordem" (e depois pelo nome).
local function montarCartoes()
	precisaMontar = false
	table.clear(vitrines)
	table.clear(cartoes)
	for _, filho in lista:GetChildren() do
		if filho:IsA("Frame") then
			filho:Destroy()
		end
	end
	local ordenados: { Model } = {}
	for _, molde in moldes:GetChildren() do
		if molde:IsA("Model") then
			table.insert(ordenados, molde)
		end
	end
	table.sort(ordenados, function(a: Model, b: Model): boolean
		local ordemA, ordemB = numero(a:GetAttribute("Ordem"), 999), numero(b:GetAttribute("Ordem"), 999)
		if ordemA ~= ordemB then
			return ordemA < ordemB
		end
		return a.Name < b.Name
	end)
	for i, molde in ordenados do
		criarCartao(molde, i)
	end
	local atual = escolhido
	if atual == nil or cartoes[atual] == nil then
		escolhido = if ordenados[1] then ordenados[1].Name else nil -- começa com o primeiro escolhido
	end
end
moldes.ChildAdded:Connect(function()
	precisaMontar = true
end)
moldes.ChildRemoved:Connect(function()
	precisaMontar = true
end)

-- =====================================================================
-- ABRIR E FECHAR
-- =====================================================================
local spawnerAtual: Instance? = nil -- o spawner em que você apertou E
local conexaoDaTela: RBXScriptConnection? = nil -- o "a cada frame" enquanto a garagem está aberta

local function pontoDoSpawner(spawner: Instance): BasePart?
	local achada = spawner:FindFirstChild("PontoDeSpawn", true)
	if achada and achada:IsA("BasePart") then
		return achada
	end
	return if spawner:IsA("BasePart") then spawner else nil
end

local function fecharGaragem()
	spawnerAtual = nil
	tela.Enabled = false
	local conexao = conexaoDaTela
	if conexao then
		conexao:Disconnect()
	end
	conexaoDaTela = nil
end

local function abrirGaragem(spawner: Instance)
	spawnerAtual = spawner
	if precisaMontar then
		montarCartoes()
	end
	local atual = escolhido
	if atual then
		selecionar(atual)
	else
		estado.Text = "Nenhum quadriciclo na pasta ReplicatedStorage > Quadriciclos."
	end
	tela.Enabled = true
	escalaDoPainel.Scale = 0.85 -- abre "pulando"
	TweenService:Create(escalaDoPainel, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if conexaoDaTela == nil then
		conexaoDaTela = RunService.RenderStepped:Connect(function()
			-- Os quadriciclos dos cartões giram (quem gira é a câmera, em volta deles: é mais leve).
			local giro = CFrame.Angles(0, os.clock() * GIRO_DA_VITRINE, 0)
			for _, vitrine in vitrines do
				vitrine.camera.CFrame = giro * vitrine.inicio
			end
			-- Se afastou do spawner? Fecha.
			local personagem = jogador.Character
			local raiz = if personagem then personagem:FindFirstChild("HumanoidRootPart") else nil
			local spawnerAgora = spawnerAtual
			local ponto = if spawnerAgora then pontoDoSpawner(spawnerAgora) else nil
			if raiz and raiz:IsA("BasePart") and ponto and (raiz.Position - ponto.Position).Magnitude > DISTANCIA_PARA_FECHAR then
				fecharGaragem()
			end
		end)
	end
end

botaoFechar.Activated:Connect(fecharGaragem)
botaoSpawnar.Activated:Connect(function()
	local spawner = spawnerAtual
	local nome = escolhido
	if spawner == nil or nome == nil then
		return
	end
	estado.Text = "Chamando o quadriciclo..."
	remoto:FireServer("Spawnar", spawner, nome) -- o servidor confere e responde "Pronto" ou um "Aviso"
end)

remoto.OnClientEvent:Connect(function(acao: unknown, dado: unknown)
	if acao == "Abrir" and typeof(dado) == "Instance" then
		abrirGaragem(dado)
	elseif acao == "Pronto" then
		fecharGaragem() -- o quadriciclo apareceu: fecha a garagem
	elseif acao == "Aviso" and typeof(dado) == "string" then
		estado.Text = dado
	end
end)

-- =====================================================================
-- DIRIGINDO: sem "E  Garagem" (o E sai do banco). Renasceu: a garagem fecha.
-- =====================================================================
local function vigiarPersonagem(personagem: Model)
	fecharGaragem()
	ProximityPromptService.Enabled = true
	local humanoide = personagem:WaitForChild("Humanoid", 10)
	if humanoide and humanoide:IsA("Humanoid") then
		humanoide.Seated:Connect(function(sentado: boolean, banco: BasePart?)
			ProximityPromptService.Enabled = not (sentado and banco ~= nil and banco:IsA("VehicleSeat"))
		end)
	end
end
jogador.CharacterAdded:Connect(vigiarPersonagem)
local personagemAgora = jogador.Character
if personagemAgora then
	task.spawn(vigiarPersonagem, personagemAgora)
end

