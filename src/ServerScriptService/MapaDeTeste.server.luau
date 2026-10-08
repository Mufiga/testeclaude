--!strict
--[[
	=====================================================================
	MapaDeTeste  (Script normal)
	Local: ServerScriptService > MapaDeTeste
	=====================================================================

	Um MAPA DE TESTE pequeno, montado sozinho quando você dá Play no Studio, longe do seu mapa.
	Você já nasce nele, do lado de um spawner (chegue perto e aperte E para escolher o veículo).

	O QUE TEM (cada área tem uma placa flutuando em cima):
	  FAIXAS DE CHÃO .. 12 faixas, cada uma de um chão: grama, terra, lama, areia, neve, gelo, pedra e
	                    asfalto (Terrain) + madeira, metal, plástico e tijolo (Parts). Acelere, freie e
	                    derrape em cada uma: a poeira, as faíscas e as marcas mudam com o chão.
	  PULINHOS ........ degraus de 1 stud, uma lombada e uma rampinha (o "puf" dos pousos pequenos).
	  RAMPA ........... boost pad + rampa (tag Rampa) + mesa + descida: pule e caia na descida.
	  LOOP ............ boost pad + loop (tag Pista360). Só o CAMINHÃO MONSTRO gruda no loop.
	  FOSSO ........... água rasa (entre pelas rampas dos lados) e uma ponte de tábuas que caem.
	  GANCHO .......... pilares (impulso e segurar), zona sem gancho, zona sem impulso, um botão que
	                    abre um portão e uma parede escalável com uma ladeira.
	Caiu para fora do mapa? Você volta para a praça.

	SEM CHECKPOINTS E SEM MOEDAS, DE PROPÓSITO: o Progresso salvaria o checkpoint e o dinheiro do teste
	no seu progresso de verdade. Pelo mesmo motivo, o mapa fica BEM abaixo do "0 metro" do Progresso:
	assim o seu recorde de METROS também não muda testando.

	NADA FICA NO SEU JOGO: o mapa é montado a cada Play e some quando você para.
	Para voltar a nascer no seu mapa: desligue este script (Properties > Enabled) ou apague ele.
	E com SO_NO_STUDIO ligado, ele nunca roda no jogo publicado (mesmo se você esquecer ele aqui).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

-- =====================================================================
-- AJUSTES
-- =====================================================================
local SO_NO_STUDIO = true -- true = só monta o mapa no Studio (nunca no jogo publicado)
local CENTRO_X = 4000 -- (studs) onde fica o meio do mapa de teste: bem longe do seu mapa
local CENTRO_Z = 4000
local DESCER = 300 -- (studs) quanto o mapa fica ABAIXO do "0 metro" do Progresso
local PORTAO_ABERTO = 6 -- (s) quanto tempo o portão fica aberto depois que o botão é acionado
local MOSTRAR_PLACAS = true -- false = sem as placas com o nome de cada área

if SO_NO_STUDIO and not RunService:IsStudio() then
	return -- (jogo publicado: não monta nada)
end

-- Espera um instante: assim os outros scripts começam antes. (O Progresso mede o "0 metro" com o
-- SpawnLocation do SEU mapa, e não com o do mapa de teste.)
task.wait()
if workspace:FindFirstChild("MapaDeTeste") then
	warn("[MapaDeTeste] Já existe um MapaDeTeste no Workspace (tem dois scripts iguais?).")
	return
end

-- =====================================================================
-- ONDE O MAPA FICA
-- =====================================================================
local LARGURA = 224 -- (studs) o tamanho do mapa de teste: de um lado ao outro (X)...
local COMPRIMENTO = 272 -- ...e de trás para a frente (Z)

-- O "0 metro" do Progresso (a mesma conta que ele faz): a Part "MarcoZero" ou o SpawnLocation.
local function alturaDoZero(): number
	local marco = workspace:FindFirstChild("MarcoZero", true)
	if marco and marco:IsA("BasePart") then
		return marco.Position.Y
	end
	local nascerDoMapa = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if nascerDoMapa then
		return nascerDoMapa.Position.Y
	end
	return 0
end

-- O Terrain é feito de "cubinhos" de 4 studs: com tudo alinhado neles, o chão fica retinho.
local function alinhar(valor: number): number
	return math.floor(valor / 4 + 0.5) * 4
end

local zero = alturaDoZero()
-- (nunca perto demais da altura em que o Roblox apaga o que cai: workspace.FallenPartsDestroyHeight)
local alturaDoChao = alinhar(math.max(zero - DESCER, workspace.FallenPartsDestroyHeight + 150))
if alturaDoChao > zero - 150 then
	warn("[MapaDeTeste] O mapa ficou perto do 0 metro (o FallenPartsDestroyHeight não deixou descer mais): o recorde de METROS pode mudar no teste.")
end
local origem = Vector3.new(alinhar(CENTRO_X), alturaDoChao, alinhar(CENTRO_Z))
local base = CFrame.new(origem) -- tudo daqui para baixo é contado a partir do meio do mapa, com o chão em Y = 0

-- Tem coisa do seu mapa nesse lugar? Só avisa (o mapa de teste é montado mesmo assim).
do
	local filtro = OverlapParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	filtro.FilterDescendantsInstances = { workspace.Terrain :: Terrain }
	local achadas = workspace:GetPartBoundsInBox(base * CFrame.new(0, 40, 0), Vector3.new(LARGURA + 40, 120, COMPRIMENTO + 40), filtro)
	if #achadas > 0 then
		warn(`[MapaDeTeste] Tem peças do seu mapa no lugar do mapa de teste (ex.: "{achadas[1]:GetFullName()}"). Mude CENTRO_X e CENTRO_Z nos AJUSTES.`)
	end
end

-- =====================================================================
-- AS CORES
-- =====================================================================
local COR = {
	praca = Color3.fromRGB(150, 150, 156),
	nascer = Color3.fromRGB(80, 200, 120),
	azul = Color3.fromRGB(70, 160, 255),
	ciano = Color3.fromRGB(90, 230, 255),
	terra = Color3.fromRGB(122, 90, 62),
	areia = Color3.fromRGB(206, 186, 140),
	madeira = Color3.fromRGB(150, 105, 62),
	pista = Color3.fromRGB(62, 64, 70),
	loop = Color3.fromRGB(240, 125, 40),
	ferro = Color3.fromRGB(70, 75, 86),
	pilar = Color3.fromRGB(172, 172, 180),
	pedra = Color3.fromRGB(105, 108, 118),
	mureta = Color3.fromRGB(205, 205, 212),
	amarelo = Color3.fromRGB(255, 215, 60),
	vermelho = Color3.fromRGB(235, 55, 55),
	laranja = Color3.fromRGB(255, 150, 40),
	branco = Color3.fromRGB(255, 255, 255),
}

-- =====================================================================
-- AS FERRAMENTAS DE MONTAR
-- =====================================================================
local pasta = Instance.new("Folder") -- tudo do mapa fica aqui dentro (vai para o Workspace no fim)
pasta.Name = "MapaDeTeste"
local terreno = workspace.Terrain :: Terrain -- (o "::" só confirma para o Studio que o Terrain existe: no Workspace, ele sempre existe)

-- Uma Part ancorada. "onde" é contado a partir do meio do mapa (o chão fica em Y = 0).
local function peca(nome: string, tamanho: Vector3, onde: CFrame, material: Enum.Material, cor: Color3, pai: Instance?): Part
	local parte = Instance.new("Part")
	parte.Name = nome
	parte.Anchored = true
	parte.Size = tamanho
	parte.CFrame = base * onde
	parte.Material = material
	parte.Color = cor
	parte.TopSurface = Enum.SurfaceType.Smooth
	parte.BottomSurface = Enum.SurfaceType.Smooth
	parte.Parent = pai or pasta
	return parte
end

-- Uma rampa (WedgePart). "meioDaBase" = o meio dela no chão; ela SOBE indo para "subindoPara".
local function rampa(nome: string, largura: number, altura: number, comprimento: number, meioDaBase: Vector3,
	subindoPara: Vector3, material: Enum.Material, cor: Color3): WedgePart
	local cunha = Instance.new("WedgePart")
	cunha.Name = nome
	cunha.Anchored = true
	cunha.Size = Vector3.new(largura, altura, comprimento)
	local meio = meioDaBase + Vector3.new(0, altura / 2, 0)
	-- (a WedgePart é alta atrás e baixa na frente: então a "frente" dela aponta para o lado que DESCE)
	cunha.CFrame = base * CFrame.lookAt(meio, meio - subindoPara)
	cunha.Material = material
	cunha.Color = cor
	cunha.BottomSurface = Enum.SurfaceType.Smooth
	cunha.Parent = pasta
	return cunha
end

-- Deixa uma peça "fantasma": não bate, ninguém encosta e os raios passam direto (para enfeites).
local function fantasma(parte: BasePart)
	parte.CanCollide = false
	parte.CanTouch = false
	parte.CanQuery = false
	parte.CastShadow = false
end

-- Uma placa flutuando (sempre virada para a câmera), com o nome da área e uma dica embaixo.
local function placa(titulo: string, dica: string, onde: Vector3, cor: Color3)
	if not MOSTRAR_PLACAS then
		return
	end
	local ancora = peca("Placa", Vector3.one, CFrame.new(onde), Enum.Material.SmoothPlastic, cor)
	ancora.Transparency = 1
	fantasma(ancora)
	-- A largura vem do tamanho dos textos (em studs: de longe a placa fica menor, como uma de verdade).
	local largura = math.max((utf8.len(titulo) or #titulo) * 1.15, (utf8.len(dica) or #dica) * 0.58) + 2
	local quadro = Instance.new("BillboardGui")
	quadro.Size = UDim2.fromScale(math.clamp(largura, 8, 26), 3.6)
	quadro.LightInfluence = 0
	quadro.MaxDistance = 170
	quadro.Parent = ancora
	local fundo = Instance.new("Frame")
	fundo.Size = UDim2.fromScale(1, 1)
	fundo.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	fundo.BackgroundTransparency = 0.2
	fundo.BorderSizePixel = 0
	fundo.Parent = quadro
	local canto = Instance.new("UICorner")
	canto.CornerRadius = UDim.new(0.2, 0)
	canto.Parent = fundo
	local borda = Instance.new("UIStroke")
	borda.Color = cor
	borda.Thickness = 3
	borda.Parent = fundo
	local nome = Instance.new("TextLabel")
	nome.BackgroundTransparency = 1
	nome.Position = UDim2.fromScale(0.05, 0.08)
	nome.Size = UDim2.fromScale(0.9, 0.5)
	nome.Font = Enum.Font.GothamBlack
	nome.TextScaled = true
	nome.TextColor3 = cor
	nome.Text = titulo
	nome.Parent = fundo
	local texto = Instance.new("TextLabel")
	texto.BackgroundTransparency = 1
	texto.Position = UDim2.fromScale(0.05, 0.6)
	texto.Size = UDim2.fromScale(0.9, 0.3)
	texto.Font = Enum.Font.GothamMedium
	texto.TextScaled = true
	texto.TextColor3 = COR.branco
	texto.Text = dica
	texto.Parent = fundo
end

-- Um BOOST PAD (no esquema do módulo BoostPads): a Part "Pad" com a tag e, no mesmo Model, as setas
-- "Seta1", "Seta2" e "Seta3" (de trás para a frente), que piscam em sequência.
-- "onde" = o meio do pad, com a frente virada para onde ele empurra.
local function boostPad(onde: CFrame, forca: number)
	local modelo = Instance.new("Model")
	modelo.Name = "BoostPad"
	modelo.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- (com StreamingEnabled, o pad e as setas chegam juntos)
	for numero, ponta in { 1.3, -1.2, -3.7 } do -- onde fica a ponta de cada seta (+ = atrás · - = na frente)
		for _, lado in { -1, 1 } do
			local direcao = Vector3.new(lado, 0, 1).Unit -- da ponta para trás, abrindo para um lado: forma um "^"
			local meio = Vector3.new(0, 0.25, ponta) + direcao * 1.8
			local barra = peca(`Seta{numero}`, Vector3.new(0.7, 0.1, 3.6), onde * CFrame.lookAt(meio, meio + direcao), Enum.Material.Neon, COR.ciano, modelo)
			fantasma(barra) -- (as rodas enxergam o pad embaixo, e não a setinha)
		end
	end
	local pad = peca("Pad", Vector3.new(12, 0.4, 8), onde, Enum.Material.SmoothPlastic, Color3.fromRGB(28, 36, 64), modelo)
	pad:AddTag("BoostPad")
	pad:SetAttribute("Forca", forca)
	pad:SetAttribute("Duracao", 1.5)
	modelo.Parent = pasta
end

-- As peças do LOOP: um círculo em pé que vai andando de lado enquanto dá a volta (como uma mola),
-- para a saída ficar do lado da entrada. "entrada" = o pé do loop, virado para onde o veículo vai.
-- Devolve as peças (onde fica cada uma e o tamanho) e a "saida" (o pé do outro lado, virado igual).
type PecaDoLoop = { onde: CFrame, tamanho: Vector3 }
local function pecasDoLoop(entrada: CFrame, raio: number, largura: number, espessura: number, quantas: number, desvio: number): ({ PecaDoLoop }, CFrame)
	local lado = desvio / (2 * math.pi) -- quanto ele anda de lado a cada radiano da volta
	-- O loop fica um pouquinho girado: assim quem entra reto acompanha a "mola" sem mexer no volante.
	local giro = entrada * CFrame.Angles(0, math.atan2(lado, raio), 0)
	local passo = 2 * math.pi / quantas
	local caminhoPorRadiano = math.sqrt(lado * lado + raio * raio)
	local comprimento = 2 * caminhoPorRadiano * math.tan(passo / 2) + 0.05 -- (uma pontinha a mais: sem frestas)
	local pecas: { PecaDoLoop } = {}
	for i = 0, quantas - 1 do
		local angulo = (i + 0.5) * passo -- o meio desta peça na volta (0 = embaixo · pi = lá em cima)
		local ponto = Vector3.new(lado * angulo, raio - raio * math.cos(angulo), -raio * math.sin(angulo))
		local frente = Vector3.new(lado, raio * math.sin(angulo), -raio * math.cos(angulo)).Unit
		local cima = Vector3.new(0, math.cos(angulo), math.sin(angulo)) -- (aponta para o meio do loop)
		local meio = ponto - cima * (espessura / 2) -- (a face de dentro da peça fica bem no círculo)
		table.insert(pecas, {
			onde = giro * CFrame.lookAt(meio, meio + frente, cima),
			tamanho = Vector3.new(largura, espessura, comprimento),
		})
	end
	local fim = giro:PointToWorldSpace(Vector3.new(desvio, 0, 0))
	return pecas, CFrame.new(fim) * entrada.Rotation
end

-- =====================================================================
-- 1) O CHÃO E AS MURETAS
-- =====================================================================
-- Limpa o lugar (se tinha Terrain do seu mapa aqui, ele some SÓ durante o teste) e faz o chão de grama.
terreno:FillBlock(base * CFrame.new(0, 42, 0), Vector3.new(LARGURA + 16, 116, COMPRIMENTO + 16), Enum.Material.Air)
terreno:FillBlock(base * CFrame.new(0, -6, 0), Vector3.new(LARGURA, 12, COMPRIMENTO), Enum.Material.Grass)
-- Muretas em volta (para ninguém cair do mapa sem querer).
peca("Mureta", Vector3.new(LARGURA + 4, 18, 2), CFrame.new(0, -3, COMPRIMENTO / 2 + 1), Enum.Material.Concrete, COR.mureta)
peca("Mureta", Vector3.new(LARGURA + 4, 18, 2), CFrame.new(0, -3, -COMPRIMENTO / 2 - 1), Enum.Material.Concrete, COR.mureta)
peca("Mureta", Vector3.new(2, 18, COMPRIMENTO), CFrame.new(LARGURA / 2 + 1, -3, 0), Enum.Material.Concrete, COR.mureta)
peca("Mureta", Vector3.new(2, 18, COMPRIMENTO), CFrame.new(-LARGURA / 2 - 1, -3, 0), Enum.Material.Concrete, COR.mureta)

-- =====================================================================
-- 2) A PRAÇA: onde você nasce, com o spawner
-- =====================================================================
peca("Praca", Vector3.new(64, 1, 40), CFrame.new(0, -0.3, -112), Enum.Material.Concrete, COR.praca)

local nascer = Instance.new("SpawnLocation")
nascer.Name = "NascerNoTeste"
nascer.Anchored = true
nascer.Size = Vector3.new(10, 0.4, 10)
nascer.CFrame = base * CFrame.new(0, 0.4, -124) * CFrame.Angles(0, math.pi, 0) -- (virado para o mapa)
nascer.Material = Enum.Material.SmoothPlastic
nascer.Color = COR.nascer
nascer.TopSurface = Enum.SurfaceType.Smooth
nascer.Neutral = true
nascer.Duration = 0 -- sem campo de força
nascer.Parent = pasta

-- O SPAWNER (o esquema do script Spawner): um Model com a tag "SpawnerQuadriciclo", a Part
-- "PontoDeSpawn" (o veículo aparece em cima dela, virado para a frente dela) e a Part "Painel"
-- (onde aparece o "E  Garagem").
local spawner = Instance.new("Model")
spawner.Name = "SpawnerDeTeste"
spawner.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
local ponto = peca("PontoDeSpawn", Vector3.new(12, 0.2, 16), CFrame.new(0, 0.3, -104) * CFrame.Angles(0, math.pi, 0), Enum.Material.Neon, COR.azul, spawner)
ponto.Transparency = 0.6
fantasma(ponto) -- (os veículos passam por cima, e as rodas enxergam a praça embaixo)
peca("Painel", Vector3.new(2, 6, 2), CFrame.new(-8, 3.2, -116), Enum.Material.Metal, COR.ferro, spawner)
peca("Luz", Vector3.new(2.4, 0.6, 2.4), CFrame.new(-8, 6.5, -116), Enum.Material.Neon, COR.azul, spawner)
spawner:AddTag("SpawnerQuadriciclo")
spawner.Parent = pasta

placa("MAPA DE TESTE", "para sair: desligue o script MapaDeTeste", Vector3.new(0, 14, -100), COR.nascer)
placa("GARAGEM", "chegue perto e aperte E", Vector3.new(-8, 10, -116), COR.azul)

-- =====================================================================
-- 3) AS FAIXAS DE CHÃO (a poeira, as faíscas e as marcas de cada chão)
-- =====================================================================
type Faixa = { nome: string, dica: string, material: Enum.Material, cor: Color3? } -- (sem cor = Terrain)
local FAIXAS: { Faixa } = {
	{ nome = "GRAMA", dica = "grama e terra", material = Enum.Material.Grass },
	{ nome = "TERRA", dica = "terra solta", material = Enum.Material.Ground },
	{ nome = "LAMA", dica = "segura muito", material = Enum.Material.Mud },
	{ nome = "AREIA", dica = "segura um pouco", material = Enum.Material.Sand },
	{ nome = "NEVE", dica = "neve fofa", material = Enum.Material.Snow },
	{ nome = "GELO", dica = "brilhinhos", material = Enum.Material.Ice },
	{ nome = "PEDRA", dica = "pedrinhas", material = Enum.Material.Rock },
	{ nome = "ASFALTO", dica = "fumaça de pneu", material = Enum.Material.Asphalt },
	{ nome = "MADEIRA", dica = "Part: lascas", material = Enum.Material.WoodPlanks, cor = Color3.fromRGB(165, 120, 75) },
	{ nome = "METAL", dica = "Part: faíscas!", material = Enum.Material.DiamondPlate, cor = Color3.fromRGB(150, 155, 165) },
	{ nome = "PLÁSTICO", dica = "Part: lisa", material = Enum.Material.SmoothPlastic, cor = Color3.fromRGB(60, 140, 230) },
	{ nome = "TIJOLO", dica = "Part: pedrinhas", material = Enum.Material.Brick, cor = Color3.fromRGB(165, 85, 60) },
}
local LARGURA_DA_FAIXA = 16
for i, faixa in FAIXAS do
	local x = (i - 0.5 - #FAIXAS / 2) * LARGURA_DA_FAIXA -- (lado a lado, com o meio do mapa no meio delas)
	local cor = faixa.cor
	if cor then
		peca(`Faixa{faixa.nome}`, Vector3.new(LARGURA_DA_FAIXA, 1, 80), CFrame.new(x, -0.3, -48), faixa.material, cor)
	else
		terreno:FillBlock(base * CFrame.new(x, -6, -48), Vector3.new(LARGURA_DA_FAIXA, 12, 80), faixa.material)
	end
	local corDaPlaca = (cor or terreno:GetMaterialColor(faixa.material)):Lerp(COR.branco, 0.45) -- (mais clara: dá para ler)
	placa(faixa.nome, faixa.dica, Vector3.new(x, 7, -84), corDaPlaca)
end
placa("FAIXAS DE CHÃO", "acelere, freie e derrape em cada uma", Vector3.new(0, 15, -84), COR.amarelo)

-- =====================================================================
-- 4) OS PULINHOS (degraus de 1 stud, lombada e rampinha: o "puf" dos pousos pequenos)
-- =====================================================================
terreno:FillBlock(base * CFrame.new(74, -6, -112), Vector3.new(68, 12, 16), Enum.Material.Ground)
peca("Degrau", Vector3.new(8, 2, 16), CFrame.new(52, 0, -112), Enum.Material.Ground, COR.terra)
local lombada = peca("Lombada", Vector3.new(16, 3, 3), CFrame.new(66, -0.5, -112) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Concrete, COR.amarelo)
lombada.Shape = Enum.PartType.Cylinder -- (o cilindro fica deitado de um lado ao outro da pista: sobra 1 stud acima do chão)
rampa("Rampinha", 16, 2, 8, Vector3.new(78, 0, -112), Vector3.xAxis, Enum.Material.Ground, COR.terra)
peca("Degrau", Vector3.new(10, 2, 16), CFrame.new(95, 0, -112), Enum.Material.Ground, COR.terra)
placa("PULINHOS", "degraus de 1 stud, lombada e rampinha", Vector3.new(42, 8, -112), COR.amarelo)

-- =====================================================================
-- 5) A RAMPA: boost pad + rampa (tag Rampa) + mesa + descida
-- =====================================================================
local X_RAMPA = -28
boostPad(CFrame.new(X_RAMPA, -0.1, 6) * CFrame.Angles(0, math.pi, 0), 40) -- (empurra para o norte, para a rampa)
local subida = rampa("Rampa", 18, 8, 18, Vector3.new(X_RAMPA, 0, 27), Vector3.zAxis, Enum.Material.Ground, COR.terra)
subida:AddTag("Rampa") -- (o caminhão monstro ganha um empurrão extra quando sai dela)
subida:SetAttribute("Impulso", 30)
-- A mesa é 2 studs mais baixa que o alto da rampa: assim o veículo sempre "decola" no fim da rampa.
peca("Mesa", Vector3.new(18, 6, 14), CFrame.new(X_RAMPA, 3, 43), Enum.Material.Ground, COR.terra)
rampa("Descida", 18, 6, 36, Vector3.new(X_RAMPA, 0, 68), -Vector3.zAxis, Enum.Material.Ground, COR.terra)
placa("RAMPA", "pule e caia na descida", Vector3.new(X_RAMPA, 8, -2), COR.laranja)

-- =====================================================================
-- 6) O LOOP (tag Pista360: só o caminhão monstro gruda nele)
-- =====================================================================
local X_LOOP = -64
local entrada = CFrame.lookAt(Vector3.new(X_LOOP, 0.2, 64), Vector3.new(X_LOOP, 0.2, 65)) -- o pé do loop, virado para o norte
local pecas, saida = pecasDoLoop(entrada, 20, 20, 1.5, 40, 30)
local loop = Instance.new("Model")
loop.Name = "Loop"
for i, info in pecas do
	local parte = peca(`Loop{i}`, info.tamanho, info.onde, Enum.Material.Concrete, COR.loop, loop)
	parte:AddTag("Pista360")
end
loop.Parent = pasta
-- A pista até o loop (com um boost pad: precisa chegar rápido) e a pista depois dele.
peca("PistaDoLoop", Vector3.new(20, 1, 68), entrada * CFrame.new(0, -0.5, 34), Enum.Material.Asphalt, COR.pista)
boostPad(entrada * CFrame.new(0, -0.1, 40), 50)
peca("SaidaDoLoop", Vector3.new(20, 1, 56), saida * CFrame.new(0, -0.5, -28), Enum.Material.Asphalt, COR.pista)
placa("LOOP 360", "só o Caminhão Monstro gruda", Vector3.new(X_LOOP, 8, -2), COR.loop)

-- =====================================================================
-- 7) O FOSSO: água rasa e uma ponte de tábuas que caem
-- =====================================================================
-- O buraco (64 x 20, fundo a 5,5 studs) com água até 4 studs abaixo do chão (1,5 stud de água).
terreno:FillBlock(base * CFrame.new(16, -4, 50), Vector3.new(64, 8, 20), Enum.Material.Air)
terreno:FillBlock(base * CFrame.new(16, -6, 50), Vector3.new(64, 4, 20), Enum.Material.Water)
peca("FundoDoFosso", Vector3.new(64, 2.5, 20), CFrame.new(16, -6.75, 50), Enum.Material.Sand, COR.areia)
rampa("RampaDoFosso", 20, 5.5, 22, Vector3.new(-5, -5.5, 50), -Vector3.xAxis, Enum.Material.Sand, COR.areia)
rampa("RampaDoFosso", 20, 5.5, 22, Vector3.new(37, -5.5, 50), Vector3.xAxis, Enum.Material.Sand, COR.areia)
-- A ponte: 10 tábuas de um lado ao outro do fosso (tag TabuaQueCai: o script TabuasQueCaem cuida delas).
local ponte = Instance.new("Model")
ponte.Name = "PonteQueCai"
for i = 1, 10 do
	local tabua = peca(`Tabua{i}`, Vector3.new(16, 0.8, 1.8), CFrame.new(16, -0.2, 39 + 2 * i), Enum.Material.WoodPlanks, COR.madeira, ponte)
	tabua:AddTag("TabuaQueCai")
	tabua:SetAttribute("Espera", 0.6) -- (s) treme isso antes de cair
	tabua:SetAttribute("Volta", 5) -- (s) volta depois disso
end
ponte.Parent = pasta
placa("TÁBUAS QUE CAEM", "passe rápido!", Vector3.new(16, 8, 36), COR.madeira:Lerp(COR.branco, 0.4))
placa("ÁGUA RASA", "desça pela rampa do lado", Vector3.new(54, 8, 50), COR.azul)

-- =====================================================================
-- 8) O GANCHO: pilares, zonas, botão com portão e parede escalável com ladeira
-- =====================================================================
-- Pilares (cenário preso no mundo: servem para o IMPULSO e para o SEGURAR). A ponta brilha: mire nela.
local function pilar(nome: string, x: number, z: number, corDaPonta: Color3)
	peca(nome, Vector3.new(6, 40, 6), CFrame.new(x, 20, z), Enum.Material.Concrete, COR.pilar)
	peca(`{nome}Ponta`, Vector3.new(6.6, 1.2, 6.6), CFrame.new(x, 40.6, z), Enum.Material.Neon, corDaPonta)
end
pilar("Pilar", 64, 12, COR.amarelo)
pilar("PilarSemGancho", 100, 12, COR.vermelho)
pilar("PilarSemImpulso", 100, 52, COR.laranja)

-- As zonas (o script Zonas deixa elas sem colisão; com o atributo "Visivel", continuam aparecendo).
local function zona(tag: string, centro: Vector3, tamanho: Vector3, cor: Color3)
	local caixa = peca(tag, tamanho, CFrame.new(centro), Enum.Material.ForceField, cor)
	fantasma(caixa)
	caixa:SetAttribute("Visivel", true)
	caixa:AddTag(tag)
end
zona("ZonaSemGancho", Vector3.new(100, 22, 12), Vector3.new(22, 44, 22), COR.vermelho)
zona("ZonaSemImpulso", Vector3.new(100, 22, 52), Vector3.new(22, 44, 22), COR.laranja)

-- O portão com o BOTÃO em cima (acerte o botão com o gancho de BOTÃO, a mão: o portão abre).
local portaoModelo = Instance.new("Model")
portaoModelo.Name = "PortaoDoBotao"
peca("Poste", Vector3.new(2, 18, 2), CFrame.new(54, 9, 80), Enum.Material.Metal, COR.ferro, portaoModelo)
peca("Poste", Vector3.new(2, 18, 2), CFrame.new(78, 9, 80), Enum.Material.Metal, COR.ferro, portaoModelo)
peca("Viga", Vector3.new(26, 3, 2), CFrame.new(66, 16.5, 80), Enum.Material.Metal, COR.ferro, portaoModelo)
local portao = peca("Portao", Vector3.new(22, 15, 1), CFrame.new(66, 7.5, 80), Enum.Material.DiamondPlate, Color3.fromRGB(120, 125, 135), portaoModelo)
local botao = peca("BotaoGancho", Vector3.new(4, 2.4, 0.6), CFrame.new(66, 16.5, 78.7), Enum.Material.Neon, COR.vermelho, portaoModelo)
botao:AddTag("BotaoGancho")
portaoModelo.Parent = pasta

-- A parede escalável (tag ParedeEscalavel: gancho SEGURAR preso + as 4 rodas nela = o veículo sobe)
-- e, do outro lado, uma ladeira comprida para descer (descendo, a velocidade máxima sobe).
local parede = peca("ParedeEscalavel", Vector3.new(32, 30, 32), CFrame.new(88, 15, 116), Enum.Material.Slate, COR.pedra)
parede:AddTag("ParedeEscalavel")
rampa("Ladeira", 20, 30, 96, Vector3.new(24, 0, 116), Vector3.xAxis, Enum.Material.Asphalt, COR.pista)

placa("PILAR", "gancho de IMPULSO ou SEGURAR", Vector3.new(64, 8, 2), COR.amarelo)
placa("ZONA SEM GANCHO", "nenhum gancho funciona aqui", Vector3.new(100, 8, -4), COR.vermelho)
placa("ZONA SEM IMPULSO", "só o IMPULSO não funciona", Vector3.new(84, 8, 52), COR.laranja)
placa("BOTÃO", "acerte com o gancho de BOTÃO", Vector3.new(66, 23, 80), COR.vermelho)
placa("PAREDE ESCALÁVEL", "gancho SEGURAR na parede", Vector3.new(88, 8, 96), COR.pilar)
placa("LADEIRA", "descendo, a velocidade sobe", Vector3.new(-30, 8, 116), COR.pilar)

-- Pronto: o mapa inteiro aparece de uma vez.
pasta.Parent = workspace

-- =====================================================================
-- O PORTÃO: o botão abre, e ele fecha sozinho depois de PORTAO_ABERTO segundos
-- =====================================================================
-- O mesmo aviso que o Gancho do servidor dispara: ServerStorage > BotaoGanchoAtivado.
local function eventoDosBotoes(): BindableEvent
	local existente = ServerStorage:FindFirstChild("BotaoGanchoAtivado")
	if existente and existente:IsA("BindableEvent") then
		return existente
	end
	local novo = Instance.new("BindableEvent")
	novo.Name = "BotaoGanchoAtivado"
	novo.Parent = ServerStorage
	return novo
end

local fechado = portao.CFrame
local aberto = fechado - Vector3.new(0, 15.2, 0) -- (desce para dentro do chão)
local MOVER_PORTAO = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fecharEm = 0
local portaoAberto = false
eventoDosBotoes().Event:Connect(function(qual: unknown, ligado: unknown)
	if typeof(qual) ~= "Instance" or qual ~= botao or ligado ~= true then
		return -- (outro botão, ou o botão voltando a ficar vermelho)
	end
	fecharEm = os.clock() + PORTAO_ABERTO -- (acertou de novo com ele aberto: fica aberto mais um pouco)
	if portaoAberto then
		return
	end
	portaoAberto = true
	TweenService:Create(portao, MOVER_PORTAO, { CFrame = aberto }):Play()
	task.spawn(function()
		while os.clock() < fecharEm do
			task.wait(0.25)
		end
		TweenService:Create(portao, MOVER_PORTAO, { CFrame = fechado }):Play()
		portaoAberto = false
	end)
end)

-- =====================================================================
-- TODO MUNDO NASCE NO MAPA DE TESTE
-- =====================================================================
-- Está dentro do mapa de teste? (Fora dele, ou caindo no vazio, não.)
local function dentroDoMapa(posicao: Vector3): boolean
	local relativo = posicao - origem
	return math.abs(relativo.X) < LARGURA / 2 + 8 and math.abs(relativo.Z) < COMPRIMENTO / 2 + 8 and relativo.Y > -60
end

-- Leva o personagem para a praça (com StreamingEnabled, pede para o mapa carregar antes).
local function levarParaAPraca(jogador: Player, personagem: Model)
	pcall(function()
		jogador:RequestStreamAroundAsync(nascer.Position, 5)
	end)
	if personagem.Parent ~= nil then
		personagem:PivotTo(nascer.CFrame + Vector3.new(0, 4, 0))
	end
end

-- Enquanto o personagem existir: se ele for parar fora do mapa, volta para a praça. Isso acontece
-- quando o Progresso leva quem tem checkpoint salvo para o checkpoint (no SEU mapa), ou quando ele
-- cai para fora. (Sentado num veículo ou já morto, não mexe.)
local function vigiar(jogador: Player, personagem: Model)
	local raiz = personagem:WaitForChild("HumanoidRootPart", 10)
	if not (raiz and raiz:IsA("BasePart")) then
		return
	end
	while personagem.Parent ~= nil do
		local humanoide = personagem:FindFirstChildOfClass("Humanoid")
		local podeLevar = humanoide ~= nil and humanoide.Health > 0 and humanoide.SeatPart == nil
		if podeLevar and not dentroDoMapa(raiz.Position) then
			levarParaAPraca(jogador, personagem)
		end
		task.wait(0.2)
	end
end

local function prepararJogador(jogador: Player)
	jogador.RespawnLocation = nascer -- renasce na praça do mapa de teste
	jogador.CharacterAdded:Connect(function(personagem: Model)
		vigiar(jogador, personagem)
	end)
	local personagem = jogador.Character
	if personagem then
		task.spawn(vigiar, jogador, personagem) -- (ele já tinha nascido antes do mapa ficar pronto)
	end
end

Players.PlayerAdded:Connect(prepararJogador)
for _, jogador in Players:GetPlayers() do
	task.spawn(prepararJogador, jogador)
end
