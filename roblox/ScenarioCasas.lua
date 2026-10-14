--[[
	ScenarioCasas  —  casas de cenário (estilo set de cinema) para Roblox
	-------------------------------------------------------------------
	A ideia é a mesma de um backlot de estúdio: o que o jogador vê é
	volume de verdade (tem profundidade, pega luz, projeta silhueta),
	mas é casca. Nada de interior, nada de porta que abre, nada de
	MeshPart. Só caixas e cunhas.

	O cenário ACOMPANHA A PISTA: você marca o caminho offroad com uns
	pontos e as casas nascem ao longo dele, dos dois lados, sempre
	viradas pra trilha. Cada faixa é uma distância lateral do caminho:

	  VOLUME  (beira da pista)  casa com casca de meia-profundidade,
	                   janelas, porta, chaminé. ~9 a 12 partes.
	  CAIXA   (encosta)  mesma silhueta, sem detalhe, profundidade
	                   menor e cor já puxada pra névoa. ~4 a 6 partes.
	  PLACA   (horizonte)  recorte de cenário: 3 partes finas viradas
	                   pra pista. Lê como prédio, custa quase nada.

	Os dois truques que fazem isso parecer caro:

	  1. Perspectiva aérea. Toda peça tem a cor interpolada na direção
	     da cor da atmosfera conforme a distância do foco. É o que o
	     olho usa pra julgar profundidade — mais do que polígono.
	  2. Perspectiva forçada. As faixas distantes são construídas
	     menores do que seriam de verdade e todas apontam pra pista.
	     O vale parece ter o dobro do tamanho.

	Tudo é Anchored, CastShadow=false, CanQuery=false, CanTouch=false,
	SmoothPlastic, e cada casa tem no máximo UM collider (invisível) em
	vez de nove partes colidíveis.

	USO — 3 passos na Command Bar do Studio
	---------------------------------------
	1) Marque a trilha: voe a câmera seguindo o caminho offroad e vá
	   repetindo (seta pra cima + Enter):

	     require(game.ServerScriptService.ScenarioCasas).MarcarPonto()

	2) Construa o cenário inteiro em volta dela:

	     require(game.ServerScriptService.ScenarioCasas).AoLongoDaPista()

	3) Ajuste na mão onde quiser. Mira a câmera e:

	     require(game.ServerScriptService.ScenarioCasas).Aqui()

	Rodar o passo 2 de novo apaga e refaz. Trocar a Semente muda a vila
	inteira. Veja ExemploUso.server.lua pro arquivo que roda sozinho.
]]

local ScenarioCasas = {}

local C = Color3.fromRGB

-- A WedgePart do Roblox tem a face vertical no +Z (Back) e a rampa
-- descendo pro -Z (Front). Todo telhado daqui depende disso. Se por
-- algum motivo os telhados sairem em V (vale) em vez de A (duas águas),
-- vire esta chave pra true e tudo se resolve.
local CUNHA_INVERTIDA = false

local function giroCunha(yaw)
	if CUNHA_INVERTIDA then
		yaw = yaw + math.pi
	end
	return CFrame.Angles(0, yaw, 0)
end

----------------------------------------------------------------------
-- 1. PALETA
--    Afinada com o print: rocha azul-acinzentada, verde dessaturado,
--    terra clara. As casas puxam pro quente (terracota, osso, madeira)
--    pra abrir contraste com o fundo frio sem brigar com ele — e o
--    telhado terracota rima com os cones laranja da pista.
----------------------------------------------------------------------
local PALETA = {
	paredes = {
		C(236, 230, 214),  -- osso
		C(214, 198, 168),  -- areia
		C(198, 208, 188),  -- sálvia
		C(176, 192, 198),  -- azul lavado
		C(208, 174, 150),  -- reboco quente
		C(226, 212, 188),  -- creme
	},
	telhados = {
		C(176,  92,  62),  -- terracota
		C(150,  74,  52),  -- ferrugem
		C( 78,  92, 104),  -- ardósia
		C( 92, 106,  78),  -- musgo
		C( 60,  72,  86),  -- grafite azulado
		C(164, 110,  74),  -- telha velha
	},
	madeira = { C(104, 78, 58), C(140, 122, 102), C(86, 66, 50) },
	pedra   = { C(126, 138, 142), C(106, 120, 128), C(146, 152, 150) },
	vidro   = { C(44, 60, 70), C(52, 74, 82) },
	luzJanela = C(252, 214, 148),
	folhas  = { C(74, 118, 72), C(92, 136, 80), C(60, 100, 68) },
}

----------------------------------------------------------------------
-- 2. CONFIGURAÇÃO PADRÃO
----------------------------------------------------------------------
local PADRAO = {
	Nome = "CenarioVila",
	Pai = nil,                            -- default: workspace
	Foco = Vector3.new(0, 20, 0),         -- ponto de onde o jogador olha
	Direcao = Vector3.new(0, 0, -1),      -- pra onde o cenário se espalha
	Semente = 20261014,                   -- mesma semente = mesma vila

	-- perspectiva aérea
	CorAtmosfera = C(162, 196, 214),
	NevoaInicio = 160,                    -- antes disso, cor pura
	NevoaFim = 1500,                      -- a partir daqui, névoa máxima
	NevoaMaxima = 0.88,                   -- 1 = some no fundo
	NevoaCurva = 0.75,                    -- <1 deixa a névoa pegar mais cedo

	EncaixarNoTerreno = true,             -- raycast pra pousar no chão
	AlturaDoRaio = 600,
	ChanceJanelaAcesa = 0.16,
	Vegetacao = true,
	Relatorio = true,                     -- print do custo no output

	Camadas = {
		{
			Nome = "Vila", Tipo = "VOLUME",
			Quantidade = 9, Distancia = 240, Espalhamento = 150, Abertura = 120,
			AlturaBase = 4, VariacaoAltura = 6,
			Escala = 1.00, Profundidade = 0.55,
			Colidir = true, Detalhe = true, Arvores = 7,
		},
		{
			Nome = "Encosta", Tipo = "CAIXA",
			Quantidade = 14, Distancia = 580, Espalhamento = 260, Abertura = 150,
			AlturaBase = 55, VariacaoAltura = 45,
			Escala = 0.80, Profundidade = 0.38,
			Colidir = false, Detalhe = false, Arvores = 12, Encaixar = true,
		},
		{
			Nome = "Horizonte", Tipo = "PLACA",
			Quantidade = 22, Distancia = 1150, Espalhamento = 420, Abertura = 175,
			AlturaBase = 150, VariacaoAltura = 90,
			Escala = 0.60, Profundidade = 0.035,
			Colidir = false, Detalhe = true, Arvores = 0, Encaixar = false,
			GiroAleatorio = 6,
		},
	},
}

local CAMADA_PADRAO = {
	Nome = "Camada",
	Tipo = "VOLUME",                      -- VOLUME | CAIXA | PLACA
	Quantidade = 8,
	Distancia = 300,                      -- raio a partir do foco
	Espalhamento = 120,                   -- variação do raio
	Abertura = 90,                        -- leque, em graus
	AnguloBase = 0,                       -- gira o leque inteiro
	AlturaBase = 0,
	VariacaoAltura = 0,
	Escala = 1,
	VariacaoEscala = 0.18,
	Profundidade = 0.55,                  -- 1 = casa real / 0.03 = placa
	GiroAleatorio = 16,                   -- graus de desalinho (quebra o leque)
	Detalhe = true,
	Colidir = false,
	Encaixar = true,
	Sombra = false,
	Arvores = 0,
	Material = Enum.Material.SmoothPlastic,
	Arquetipos = { "Chale", "Sobrado", "Celeiro", "Capela" },
}

----------------------------------------------------------------------
-- 3. UTILIDADES
----------------------------------------------------------------------
local function mesclar(padrao, extra)
	local saida = {}
	for k, v in pairs(padrao) do saida[k] = v end
	if extra then
		for k, v in pairs(extra) do saida[k] = v end
	end
	return saida
end

local function escolher(rng, lista)
	return lista[rng:NextInteger(1, #lista)]
end

local function definirSeguro(inst, prop, valor)
	-- propriedades novas do engine: não quebra em versões antigas
	pcall(function() inst[prop] = valor end)
end

-- Perspectiva aérea: quanto a cor desta casa já virou atmosfera.
local function nivelDeNevoa(distancia, cfg)
	local faixa = math.max(1, cfg.NevoaFim - cfg.NevoaInicio)
	local t = math.clamp((distancia - cfg.NevoaInicio) / faixa, 0, 1)
	return (t ^ cfg.NevoaCurva) * cfg.NevoaMaxima
end

----------------------------------------------------------------------
-- 4. FÁBRICA DE PEÇAS
--    Toda peça do cenário nasce daqui, já com as flags de performance
--    ligadas. ctx.base é o CFrame da casa no mundo; as peças são
--    descritas em espaço local (origem no chão, no centro da casa,
--    fachada apontando pro -Z = pro foco).
----------------------------------------------------------------------
local function peca(ctx, classe, tamanho, cfLocal, cor, material, mistura)
	local p = Instance.new(classe)
	p.Size = tamanho
	p.CFrame = ctx.base * cfLocal
	p.Color = cor:Lerp(ctx.cfg.CorAtmosfera, ctx.nevoa * (mistura or 1))
	p.Material = material or ctx.material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = ctx.sombra
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.modelo
	ctx.pecas = ctx.pecas + 1
	ctx.tris = ctx.tris + (classe == "WedgePart" and 8 or 12)
	return p
end

-- Telhado de duas águas com 2 cunhas (16 triângulos no total).
-- cumeeiraEmX = true  -> o jogador vê a água do telhado descendo até ele
-- cumeeiraEmX = false -> o jogador vê a empena (o triângulo) de frente
local function telhado(ctx, largura, profundidade, altura, baseY, cor, cumeeiraEmX, beiral)
	beiral = beiral or (0.8 * ctx.escala)
	local giro = cumeeiraEmX and CFrame.new() or CFrame.Angles(0, math.pi * 0.5, 0)
	local a = (cumeeiraEmX and largura or profundidade) + beiral * 2
	local b = (cumeeiraEmX and profundidade or largura) + beiral * 2
	local y = baseY + altura * 0.5
	local tam = Vector3.new(a, altura, b * 0.5)
	peca(ctx, "WedgePart", tam, giro * CFrame.new(0, y, -b * 0.25) * giroCunha(0), cor)
	peca(ctx, "WedgePart", tam, giro * CFrame.new(0, y, b * 0.25) * giroCunha(math.pi), cor)
	return baseY + altura
end

-- Janela: vidro + moldura, só na fachada que olha pro foco.
local function janela(ctx, x, y, largura, altura, profundidade)
	local frente = -profundidade * 0.5
	local acesa = ctx.rng:NextNumber() < ctx.cfg.ChanceJanelaAcesa
	peca(ctx, "Part", Vector3.new(largura + 0.6 * ctx.escala, altura + 0.6 * ctx.escala, 0.22),
		CFrame.new(x, y, frente - 0.11), escolher(ctx.rng, PALETA.madeira))
	if acesa then
		-- a luz quente não entra na névoa: é ela que dá o "alguém mora ali"
		peca(ctx, "Part", Vector3.new(largura, altura, 0.18),
			CFrame.new(x, y, frente - 0.20), PALETA.luzJanela, Enum.Material.Neon, 0.25)
	else
		peca(ctx, "Part", Vector3.new(largura, altura, 0.18),
			CFrame.new(x, y, frente - 0.20), escolher(ctx.rng, PALETA.vidro))
	end
end

----------------------------------------------------------------------
-- 5. ARQUÉTIPOS
--    Cada um preenche ctx.modelo e devolve o tamanho da "caixa" da
--    casa (usado depois pra montar o collider único).
----------------------------------------------------------------------
local ARQ = {}

-- Chalé: casa baixa, base de pedra, telhado largo. O cavalo de batalha.
function ARQ.Chale(ctx)
	local rng, e = ctx.rng, ctx.escala
	local larg = rng:NextNumber(13, 19) * e
	local alt = rng:NextNumber(8.5, 11) * e
	local prof = larg * ctx.profundidade
	local baseAlt = 2.0 * e
	local corParede = escolher(rng, PALETA.paredes)
	local corTelha = escolher(rng, PALETA.telhados)

	peca(ctx, "Part", Vector3.new(larg + 1.2 * e, baseAlt, prof + 1.2 * e),
		CFrame.new(0, baseAlt * 0.5, 0), escolher(rng, PALETA.pedra))
	peca(ctx, "Part", Vector3.new(larg, alt, prof),
		CFrame.new(0, baseAlt + alt * 0.5, 0), corParede)

	local altTelha = alt * rng:NextNumber(0.45, 0.62)
	local topo = telhado(ctx, larg, prof, altTelha, baseAlt + alt, corTelha, true)

	if ctx.detalhe then
		local portaAlt = 5.0 * e
		peca(ctx, "Part", Vector3.new(3.0 * e, portaAlt, 0.24),
			CFrame.new(-larg * 0.26, baseAlt + portaAlt * 0.5, -prof * 0.5 - 0.12),
			escolher(rng, PALETA.madeira))
		janela(ctx, larg * 0.14, baseAlt + alt * 0.58, 2.6 * e, 3.0 * e, prof)
		janela(ctx, larg * 0.36, baseAlt + alt * 0.58, 2.6 * e, 3.0 * e, prof)
		-- chaminé: furar a linha do telhado dá leitura de volume de graça
		local chAlt = altTelha + 1.8 * e
		peca(ctx, "Part", Vector3.new(1.7 * e, chAlt, 1.7 * e),
			CFrame.new(larg * 0.3, baseAlt + alt + chAlt * 0.5, prof * 0.1),
			escolher(rng, PALETA.pedra))
	end

	return Vector3.new(larg, topo, prof)
end

-- Sobrado: dois andares, cornija no meio. Dá verticalidade à vila.
function ARQ.Sobrado(ctx)
	local rng, e = ctx.rng, ctx.escala
	local larg = rng:NextNumber(10, 14) * e
	local alt = rng:NextNumber(15, 19) * e
	local prof = larg * ctx.profundidade
	local corParede = escolher(rng, PALETA.paredes)
	local corTelha = escolher(rng, PALETA.telhados)

	peca(ctx, "Part", Vector3.new(larg, alt, prof), CFrame.new(0, alt * 0.5, 0), corParede)
	peca(ctx, "Part", Vector3.new(larg + 0.9 * e, 0.8 * e, prof + 0.9 * e),
		CFrame.new(0, alt * 0.52, 0), escolher(rng, PALETA.madeira))

	local altTelha = alt * rng:NextNumber(0.26, 0.36)
	local topo = telhado(ctx, larg, prof, altTelha, alt, corTelha, true)

	if ctx.detalhe then
		local portaAlt = 5.0 * e
		peca(ctx, "Part", Vector3.new(2.8 * e, portaAlt, 0.24),
			CFrame.new(0, portaAlt * 0.5, -prof * 0.5 - 0.12), escolher(rng, PALETA.madeira))
		local jx = larg * 0.26
		janela(ctx, -jx, alt * 0.30, 2.4 * e, 3.0 * e, prof)
		janela(ctx, jx, alt * 0.30, 2.4 * e, 3.0 * e, prof)
		janela(ctx, -jx, alt * 0.74, 2.4 * e, 3.0 * e, prof)
		janela(ctx, jx, alt * 0.74, 2.4 * e, 3.0 * e, prof)
	end

	return Vector3.new(larg, topo, prof)
end

-- Celeiro: largo e baixo, empena virada pro jogador. Quebra o ritmo.
function ARQ.Celeiro(ctx)
	local rng, e = ctx.rng, ctx.escala
	local larg = rng:NextNumber(20, 26) * e
	local alt = rng:NextNumber(8, 11) * e
	local prof = larg * ctx.profundidade * 0.85
	local corParede = PALETA.telhados[rng:NextInteger(1, 2)]  -- vermelho de celeiro
	local corTelha = escolher(rng, PALETA.pedra)

	peca(ctx, "Part", Vector3.new(larg, alt, prof), CFrame.new(0, alt * 0.5, 0), corParede)
	-- a empena fica virada pro jogador: silhueta clássica de celeiro
	local altTelha = alt * rng:NextNumber(0.6, 0.8)
	local topo = telhado(ctx, larg, prof, altTelha, alt, corTelha, false)

	if ctx.detalhe then
		local portaAlt = alt * 0.62
		peca(ctx, "Part", Vector3.new(larg * 0.34, portaAlt, 0.24),
			CFrame.new(0, portaAlt * 0.5, -prof * 0.5 - 0.12), C(236, 230, 214))
		peca(ctx, "Part", Vector3.new(larg + 0.5 * e, 0.7 * e, prof + 0.5 * e),
			CFrame.new(0, alt - 0.35 * e, 0), C(236, 230, 214))
	end

	return Vector3.new(larg, topo, prof)
end

-- Capela: torre fina com flecha. Uma por vila já segura o skyline.
function ARQ.Capela(ctx)
	local rng, e = ctx.rng, ctx.escala
	local larg = rng:NextNumber(9, 12) * e
	local alt = rng:NextNumber(10, 13) * e
	local prof = larg * ctx.profundidade
	local corParede = PALETA.paredes[1]
	local corTelha = escolher(rng, PALETA.telhados)

	peca(ctx, "Part", Vector3.new(larg, alt, prof), CFrame.new(0, alt * 0.5, 0), corParede)
	local altTelha = alt * 0.55
	telhado(ctx, larg, prof, altTelha, alt, corTelha, true)

	local torreLarg = math.min(larg * 0.38, prof * 1.1)
	local torreAlt = alt * rng:NextNumber(1.5, 1.9)
	local torreX = larg * 0.5 - torreLarg * 0.55
	peca(ctx, "Part", Vector3.new(torreLarg, torreAlt, torreLarg),
		CFrame.new(torreX, torreAlt * 0.5, -prof * 0.1), corParede)
	local flecha = alt * 0.9
	telhado(ctx, torreLarg, torreLarg, flecha, torreAlt, corTelha, true, 0.25 * e)

	if ctx.detalhe then
		janela(ctx, -larg * 0.2, alt * 0.55, 2.2 * e, 3.4 * e, prof)
		peca(ctx, "Part", Vector3.new(torreLarg * 0.45, torreLarg * 0.45, 0.2),
			CFrame.new(torreX, torreAlt * 0.86, -torreLarg * 0.5 - 0.1), PALETA.luzJanela,
			Enum.Material.Neon, 0.3)
	end

	return Vector3.new(larg, torreAlt + flecha, prof)
end

-- Placa: o recorte de backlot. 3 peças finas, sempre de frente pro foco.
function ARQ.Placa(ctx)
	local rng, e = ctx.rng, ctx.escala
	local larg = rng:NextNumber(12, 26) * e
	local alt = rng:NextNumber(9, 24) * e
	local esp = math.max(0.5, larg * ctx.profundidade)
	local corParede = escolher(rng, PALETA.paredes)
	local corTelha = escolher(rng, PALETA.telhados)

	peca(ctx, "Part", Vector3.new(larg, alt, esp), CFrame.new(0, alt * 0.5, 0), corParede)

	-- empena: duas cunhas finas giradas 90°, triângulo virado pro jogador
	local gh = alt * rng:NextNumber(0.28, 0.5)
	local y = alt + gh * 0.5
	local tam = Vector3.new(esp, gh, larg * 0.5)
	peca(ctx, "WedgePart", tam, CFrame.new(-larg * 0.25, y, 0) * giroCunha(math.pi * 0.5), corTelha)
	peca(ctx, "WedgePart", tam, CFrame.new(larg * 0.25, y, 0) * giroCunha(-math.pi * 0.5), corTelha)

	if ctx.detalhe then
		-- faixa única de janelas: 1 peça resolve o que 8 resolveriam
		peca(ctx, "Part", Vector3.new(larg * 0.72, alt * 0.14, esp * 0.8),
			CFrame.new(0, alt * 0.62, -esp * 0.55), escolher(rng, PALETA.vidro), nil, 0.8)
	end

	return Vector3.new(larg, alt + gh, esp)
end

----------------------------------------------------------------------
-- 6. VEGETAÇÃO (opcional)
--    Pinheiro estilizado: tronco + 3 caixas giradas. 4 peças, 48 tris.
--    Serve pra "costurar" as casas na encosta e esconder a base delas.
----------------------------------------------------------------------
local function construirArvore(ctx)
	local rng, e = ctx.rng, ctx.escala
	local corFolha = escolher(rng, PALETA.folhas)
	peca(ctx, "Part", Vector3.new(1.3 * e, 6 * e, 1.3 * e), CFrame.new(0, 3 * e, 0),
		escolher(rng, PALETA.madeira))
	peca(ctx, "Part", Vector3.new(7.5 * e, 5.5 * e, 7.5 * e),
		CFrame.new(0, 7 * e, 0) * CFrame.Angles(0, math.rad(45), 0), corFolha)
	peca(ctx, "Part", Vector3.new(5.6 * e, 4.6 * e, 5.6 * e),
		CFrame.new(0, 11 * e, 0) * CFrame.Angles(0, math.rad(20), 0), corFolha)
	peca(ctx, "Part", Vector3.new(3.4 * e, 4.0 * e, 3.4 * e),
		CFrame.new(0, 14.4 * e, 0) * CFrame.Angles(0, math.rad(62), 0), corFolha)
	return Vector3.new(7.5 * e, 16.4 * e, 7.5 * e)
end

----------------------------------------------------------------------
-- 7. MONTAGEM
----------------------------------------------------------------------
local function novoContexto(cfg, camada, base, nevoa, rng, escala)
	return {
		modelo = Instance.new("Model"),
		base = base,
		rng = rng,
		cfg = cfg,
		escala = escala,
		nevoa = nevoa,
		detalhe = camada.Detalhe,
		profundidade = camada.Profundidade,
		material = camada.Material,
		sombra = camada.Sombra,
		pecas = 0,
		tris = 0,
	}
end

local function montarCorpo(ctx, nomeArquetipo, camada, pai)
	local caixa = ARQ[nomeArquetipo](ctx)
	ctx.modelo.Name = nomeArquetipo

	-- UM collider por casa, não um por peça.
	if camada.Colidir and caixa then
		local col = Instance.new("Part")
		col.Name = "Colisao"
		col.Size = caixa
		col.CFrame = ctx.base * CFrame.new(0, caixa.Y * 0.5, 0)
		col.Transparency = 1
		col.Anchored = true
		col.CanCollide = true
		col.CanQuery = false
		col.CanTouch = false
		col.CastShadow = false
		col.Parent = ctx.modelo
		ctx.pecas = ctx.pecas + 1
	end

	definirSeguro(ctx.modelo, "LevelOfDetail", Enum.ModelLevelOfDetail.Disabled)
	ctx.modelo.Parent = pai
	return ctx.pecas, ctx.tris
end

-- Posição no leque da camada + encaixe no terreno + giro pro foco.
local function posicionar(cfg, camada, rng, indice, direcao, filtro)
	local t = (camada.Quantidade <= 1) and 0.5 or (indice - 0.5) / camada.Quantidade
	local passo = camada.Abertura / math.max(1, camada.Quantidade)
	local ang = camada.AnguloBase + (t - 0.5) * camada.Abertura
		+ rng:NextNumber(-1, 1) * passo * 0.35
	local dist = camada.Distancia + rng:NextNumber(-0.5, 0.5) * camada.Espalhamento
	local deslocamento = (CFrame.Angles(0, math.rad(ang), 0) * CFrame.new(direcao * dist)).Position
	local altura = camada.AlturaBase + rng:NextNumber(-0.5, 0.5) * camada.VariacaoAltura
	local pos = cfg.Foco + deslocamento + Vector3.new(0, altura, 0)

	if cfg.EncaixarNoTerreno and camada.Encaixar then
		local acima = pos + Vector3.new(0, cfg.AlturaDoRaio, 0)
		local hit = workspace:Raycast(acima, Vector3.new(0, -cfg.AlturaDoRaio * 3, 0), filtro)
		if hit then
			pos = Vector3.new(pos.X, hit.Position.Y - 0.6, pos.Z)
		end
	end

	-- gira pro foco mantendo a casa em pé, depois desalinha um pouco
	local alvo = Vector3.new(cfg.Foco.X, pos.Y, cfg.Foco.Z)
	local cf
	if (alvo - pos).Magnitude > 0.25 then
		cf = CFrame.lookAt(pos, alvo)
	else
		cf = CFrame.new(pos)
	end
	return cf * CFrame.Angles(0, math.rad(rng:NextNumber(-1, 1) * camada.GiroAleatorio), 0),
		(pos - cfg.Foco).Magnitude
end

--- MODO SECUNDÁRIO (leque): espalha em volta de um ponto de vista só,
--  sem pista nenhuma. Serve pra lobby, menu, fundo de tela. Pra cenário
--  de pista use AoLongoDaPista(). Devolve o Model raiz.
function ScenarioCasas.Construir(opcoes)
	local cfg = mesclar(PADRAO, opcoes)
	local pai = cfg.Pai or workspace

	local antigo = pai:FindFirstChild(cfg.Nome)
	if antigo then antigo:Destroy() end

	local raiz = Instance.new("Model")
	raiz.Name = cfg.Nome
	-- cenário de fundo nunca pode piscar: fica sempre carregado no cliente
	definirSeguro(raiz, "ModelStreamingMode", Enum.ModelStreamingMode.Persistent)
	definirSeguro(raiz, "LevelOfDetail", Enum.ModelLevelOfDetail.Disabled)

	local rng = Random.new(cfg.Semente)

	local dir = Vector3.new(cfg.Direcao.X, 0, cfg.Direcao.Z)
	dir = (dir.Magnitude > 0.001) and dir.Unit or Vector3.new(0, 0, -1)

	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	filtro.FilterDescendantsInstances = { raiz }
	filtro.IgnoreWater = true

	local totalPecas, totalTris, totalCasas = 0, 0, 0

	for _, camadaBruta in ipairs(cfg.Camadas) do
		local camada = mesclar(CAMADA_PADRAO, camadaBruta)
		local pasta = Instance.new("Folder")
		pasta.Name = camada.Nome

		for i = 1, camada.Quantidade do
			local base, distReal = posicionar(cfg, camada, rng, i, dir, filtro)
			local nevoa = nivelDeNevoa(distReal, cfg)
			local escala = camada.Escala * (1 + rng:NextNumber(-1, 1) * camada.VariacaoEscala)
			local ctx = novoContexto(cfg, camada, base, nevoa, rng, escala)

			local nome
			if camada.Tipo == "PLACA" then
				nome = "Placa"
			else
				nome = escolher(rng, camada.Arquetipos)
			end

			local p, tr = montarCorpo(ctx, nome, camada, pasta)
			totalPecas = totalPecas + p
			totalTris = totalTris + tr
			totalCasas = totalCasas + 1
		end

		if cfg.Vegetacao and camada.Arvores > 0 then
			for i = 1, camada.Arvores do
				local camadaArvore = mesclar(camada, {
					Quantidade = camada.Arvores,
					Abertura = camada.Abertura * 1.15,
					Espalhamento = camada.Espalhamento * 1.4,
					GiroAleatorio = 180,
				})
				local base, distReal = posicionar(cfg, camadaArvore, rng, i, dir, filtro)
				local nevoa = nivelDeNevoa(distReal, cfg)
				local escala = camada.Escala * rng:NextNumber(0.7, 1.25)
				local ctx = novoContexto(cfg, camada, base, nevoa, rng, escala)
				construirArvore(ctx)
				ctx.modelo.Name = "Pinheiro"
				definirSeguro(ctx.modelo, "LevelOfDetail", Enum.ModelLevelOfDetail.Disabled)
				ctx.modelo.Parent = pasta
				totalPecas = totalPecas + ctx.pecas
				totalTris = totalTris + ctx.tris
			end
		end

		pasta.Parent = raiz
	end

	raiz.Parent = pai

	if cfg.Relatorio then
		print(string.format(
			"[ScenarioCasas] %s: %d construções, %d partes, ~%d triângulos.",
			cfg.Nome, totalCasas, totalPecas, totalTris))
	end

	return raiz
end

--- Uma casa solta, onde você quiser. Útil pra compor à mão.
-- @param cf CFrame do chão da casa (o -Z é a fachada)
function ScenarioCasas.CasaAvulsa(cf, opcoes)
	opcoes = opcoes or {}
	local cfg = mesclar(PADRAO, opcoes.Config)
	local camada = mesclar(CAMADA_PADRAO, opcoes)
	local rng = Random.new(opcoes.Semente or math.floor(os.clock() * 1e6))
	local nevoa = opcoes.Nevoa or 0
	local ctx = novoContexto(cfg, camada, cf, nevoa, rng, camada.Escala)
	local nome = opcoes.Arquetipo or escolher(rng, camada.Arquetipos)
	montarCorpo(ctx, nome, camada, opcoes.Pai or workspace)
	return ctx.modelo
end

--- Remove um cenário construído antes.
function ScenarioCasas.Limpar(nome, pai)
	local alvo = (pai or workspace):FindFirstChild(nome or PADRAO.Nome)
	if alvo then alvo:Destroy() end
end

--- Opcional: alinha a névoa do jogo com a cor usada nas casas.
--  Sem isso o truque da perspectiva aérea funciona pela metade.
function ScenarioCasas.AplicarAtmosfera(opcoes)
	opcoes = opcoes or {}
	local Lighting = game:GetService("Lighting")
	local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atm.Density = opcoes.Densidade or 0.33
	atm.Offset = 0.08
	atm.Color = opcoes.Cor or C(199, 220, 232)
	atm.Decay = opcoes.Decaimento or C(106, 143, 166)
	atm.Glare = 0.1
	atm.Haze = opcoes.Bruma or 1.9
	atm.Parent = Lighting
	Lighting.FogEnd = opcoes.FimDaNevoa or 4000
	return atm
end

----------------------------------------------------------------------
-- 8. PISTA — o modo principal
--    Em vez de espalhar em leque, o cenário segue o caminho offroad.
--    Cada FAIXA é uma distância lateral da pista; as casas nascem de
--    tantos em tantos studs ao longo dela, sempre viradas pro caminho.
--    A névoa passa a ser medida pela distância lateral: casa na beira
--    sai com a cor cheia, casa a 700 studs sai quase só silhueta.
----------------------------------------------------------------------
local FAIXA_PADRAO = {
	Nome = "Faixa",
	Tipo = "VOLUME",              -- VOLUME | CAIXA | PLACA
	Recuo = 60,                   -- distância do eixo da pista
	VariacaoRecuo = 25,
	Espacamento = 90,             -- a cada quantos studs de pista nasce um lugar
	Densidade = 0.55,             -- chance desse lugar virar casa
	ChanceArvore = 0.30,          -- chance de virar árvore (nos lugares que sobraram)
	Lados = "ambos",              -- "ambos" | "esquerda" | "direita"
	Altura = 0,                   -- offset vertical depois de pousar
	VariacaoAltura = 0,
	Escala = 1,
	VariacaoEscala = 0.18,
	Profundidade = 0.55,          -- 1 = casa real / 0.035 = placa
	GiroAleatorio = 22,           -- graus de desalinho
	DistanciaMinima = 26,         -- não deixa duas construções se encavalarem
	Detalhe = true,
	Colidir = false,
	Encaixar = true,              -- raycast pra pousar no terreno
	Sombra = false,
	Material = Enum.Material.SmoothPlastic,
	Arquetipos = { "Chale", "Sobrado", "Celeiro", "Capela" },
}

local FAIXAS_PADRAO = {
	-- beira da trilha: o jogador passa raspando, então tem detalhe e colisão
	{
		Nome = "Beira", Tipo = "VOLUME",
		Recuo = 55, VariacaoRecuo = 26, Espacamento = 85,
		Densidade = 0.50, ChanceArvore = 0.35,
		Escala = 1.0, Profundidade = 0.55,
		Colidir = true, Detalhe = true, DistanciaMinima = 30,
	},
	-- encosta: trepadas no barranco, sem detalhe, já puxando pro azul
	{
		Nome = "Encosta", Tipo = "CAIXA",
		Recuo = 190, VariacaoRecuo = 85, Espacamento = 70,
		Densidade = 0.60, ChanceArvore = 0.30,
		Altura = 12, VariacaoAltura = 25,
		Escala = 0.85, Profundidade = 0.38,
		Detalhe = false, DistanciaMinima = 24,
	},
	-- horizonte: recorte de backlot no alto, flutuando acima do barranco
	{
		Nome = "Horizonte", Tipo = "PLACA",
		Recuo = 650, VariacaoRecuo = 230, Espacamento = 95,
		Densidade = 0.80, ChanceArvore = 0,
		Altura = 130, VariacaoAltura = 70,
		Escala = 0.60, Profundidade = 0.035,
		Encaixar = false, GiroAleatorio = 6, DistanciaMinima = 14,
	},
}

local function numeroNoNome(nome)
	local n = string.match(nome, "%d+")
	if n then return tonumber(n) end
	return nil
end

-- Aceita: Folder/Model de Parts, lista de Vector3, lista de Parts, lista de CFrames.
local function coletarPontos(origem)
	local pontos = {}
	if typeof(origem) == "Instance" then
		local partes = {}
		for _, filho in ipairs(origem:GetDescendants()) do
			if filho:IsA("BasePart") then
				table.insert(partes, filho)
			end
		end
		-- ordem pelo número no nome (001, 002, ...), senão alfabética
		table.sort(partes, function(a, b)
			local na, nb = numeroNoNome(a.Name), numeroNoNome(b.Name)
			if na and nb and na ~= nb then
				return na < nb
			end
			return a.Name < b.Name
		end)
		for _, parte in ipairs(partes) do
			table.insert(pontos, parte.Position)
		end
	elseif type(origem) == "table" then
		for _, item in ipairs(origem) do
			if typeof(item) == "Vector3" then
				table.insert(pontos, item)
			elseif typeof(item) == "CFrame" then
				table.insert(pontos, item.Position)
			elseif typeof(item) == "Instance" and item:IsA("BasePart") then
				table.insert(pontos, item.Position)
			end
		end
	end
	return pontos
end

-- Catmull-Rom: a curva passa EM CIMA dos pontos que você marcou.
local function catmull(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return (p1 * 2
		+ (p2 - p0) * t
		+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
		+ (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

-- Devolve a pista picada em amostras, cada uma com posição, tangente
-- horizontal e distância acumulada desde o começo.
local function amostrarCaminho(pontos, fechado, subdivisoes)
	subdivisoes = math.max(2, subdivisoes or 8)
	local n = #pontos
	local caminho = {}
	if n < 2 then return caminho end

	local bruto = {}
	local ultimo = fechado and n or (n - 1)
	for i = 1, ultimo do
		local p0, p1, p2, p3
		if fechado then
			p0 = pontos[((i - 2) % n) + 1]
			p1 = pontos[i]
			p2 = pontos[(i % n) + 1]
			p3 = pontos[((i + 1) % n) + 1]
		else
			p0 = pontos[math.max(1, i - 1)]
			p1 = pontos[i]
			p2 = pontos[math.min(n, i + 1)]
			p3 = pontos[math.min(n, i + 2)]
		end
		for s = 0, subdivisoes - 1 do
			table.insert(bruto, catmull(p0, p1, p2, p3, s / subdivisoes))
		end
	end
	if not fechado then
		table.insert(bruto, pontos[n])
	end

	local total = #bruto
	for i, p in ipairs(bruto) do
		local anterior = bruto[i - 1]
		local proximo = bruto[i + 1]
		if not anterior then
			anterior = fechado and bruto[total] or p
		end
		if not proximo then
			proximo = fechado and bruto[1] or p
		end
		local tang = proximo - anterior
		tang = Vector3.new(tang.X, 0, tang.Z)      -- o lado é sempre horizontal
		if tang.Magnitude > 0.001 then
			tang = tang.Unit
		else
			tang = Vector3.new(0, 0, -1)
		end
		local s = 0
		if i > 1 then
			s = caminho[i - 1].s + (p - bruto[i - 1]).Magnitude
		end
		caminho[i] = { p = p, t = tang, s = s }
	end
	return caminho
end

-- A pista em uso. Quem define: DefinirPista() ou AoLongoDaPista().
-- É ela que faz as casas soltas virarem pro caminho sozinhas.
local pistaAtual = nil

local function maisProximoNaPista(pos)
	if not pistaAtual then return nil, nil end
	local melhor, melhorDist
	local plano = Vector3.new(pos.X, 0, pos.Z)
	for _, amostra in ipairs(pistaAtual) do
		local d = (Vector3.new(amostra.p.X, 0, amostra.p.Z) - plano).Magnitude
		if (not melhorDist) or d < melhorDist then
			melhor, melhorDist = amostra, d
		end
	end
	return melhor, melhorDist
end

local function ladoDireito(tangente)
	local lado = tangente:Cross(Vector3.new(0, 1, 0))
	if lado.Magnitude > 0.001 then
		return lado.Unit
	end
	return Vector3.new(1, 0, 0)
end

local function pousar(pos, alturaDaPista, encaixar, cfg, filtro)
	if encaixar then
		local hit = workspace:Raycast(
			pos + Vector3.new(0, cfg.AlturaDoRaio, 0),
			Vector3.new(0, -cfg.AlturaDoRaio * 3, 0),
			filtro)
		if hit then
			return Vector3.new(pos.X, hit.Position.Y - 0.6, pos.Z)
		end
	end
	return Vector3.new(pos.X, alturaDaPista, pos.Z)
end

--- Registra a pista sem construir nada. Depois disso, qualquer casa
--  solta que você colocar já nasce virada pro caminho e com a névoa
--  certa pra distância dela.
function ScenarioCasas.DefinirPista(origem, fechado, subdivisoes)
	local pontos = coletarPontos(origem)
	if #pontos < 2 then
		warn("[ScenarioCasas] A pista precisa de pelo menos 2 pontos; achei " .. #pontos .. ".")
		pistaAtual = nil
		return 0
	end
	pistaAtual = amostrarCaminho(pontos, fechado, subdivisoes)
	return #pontos
end

--- Monta o cenário inteiro acompanhando a pista. Devolve o Model raiz.
function ScenarioCasas.AoLongoDaPista(opcoes)
	opcoes = opcoes or {}
	local cfg = mesclar(PADRAO, opcoes)
	-- distância lateral é bem menor que a radial do modo em leque:
	-- a névoa tem que começar e saturar muito mais cedo
	if opcoes.NevoaInicio == nil then cfg.NevoaInicio = 60 end
	if opcoes.NevoaFim == nil then cfg.NevoaFim = 900 end

	local origemCaminho = opcoes.Caminho or workspace:FindFirstChild("CaminhoPista")
	local pontos = coletarPontos(origemCaminho)
	if #pontos < 2 then
		warn("[ScenarioCasas] A pista precisa de pelo menos 2 pontos; achei " .. #pontos ..
			". Marque o caminho com ScenarioCasas.MarcarPonto().")
		return nil
	end
	local caminho = amostrarCaminho(pontos, opcoes.Fechado, opcoes.Subdivisoes)
	pistaAtual = caminho

	local pai = cfg.Pai or workspace
	local antigo = pai:FindFirstChild(cfg.Nome)
	if antigo then antigo:Destroy() end

	local raiz = Instance.new("Model")
	raiz.Name = cfg.Nome
	definirSeguro(raiz, "ModelStreamingMode", Enum.ModelStreamingMode.Persistent)
	definirSeguro(raiz, "LevelOfDetail", Enum.ModelLevelOfDetail.Disabled)

	local rng = Random.new(cfg.Semente)
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	-- os marcadores da pista não podem servir de chão pro raycast
	local ignorar = { raiz }
	if typeof(origemCaminho) == "Instance" then
		table.insert(ignorar, origemCaminho)
	end
	for _, extra in ipairs(opcoes.Ignorar or {}) do
		table.insert(ignorar, extra)
	end
	filtro.FilterDescendantsInstances = ignorar
	filtro.IgnoreWater = true

	local colocadas = {}
	local totalPecas, totalTris, totalCasas, totalArvores = 0, 0, 0, 0

	for _, faixaBruta in ipairs(opcoes.Faixas or FAIXAS_PADRAO) do
		local faixa = mesclar(FAIXA_PADRAO, faixaBruta)
		local espacamento = math.max(8, faixa.Espacamento)
		local pasta = Instance.new("Folder")
		pasta.Name = faixa.Nome

		local lados
		if faixa.Lados == "esquerda" then
			lados = { -1 }
		elseif faixa.Lados == "direita" then
			lados = { 1 }
		else
			lados = { -1, 1 }
		end

		local percorrido = espacamento
		for i = 2, #caminho do
			percorrido = percorrido + (caminho[i].p - caminho[i - 1].p).Magnitude
			if percorrido >= espacamento then
				percorrido = 0
				local amostra = caminho[i]
				local direita = ladoDireito(amostra.t)

				for _, lado in ipairs(lados) do
					local sorteio = rng:NextNumber()
					local ehCasa = sorteio < faixa.Densidade
					local ehArvore = (not ehCasa) and sorteio < (faixa.Densidade + faixa.ChanceArvore)

					if ehCasa or ehArvore then
						local recuo = faixa.Recuo + rng:NextNumber(-0.5, 0.5) * faixa.VariacaoRecuo
						-- empurra também ao longo da pista, senão vira fileira
						local desvio = rng:NextNumber(-0.5, 0.5) * espacamento * 0.6
						local pos = amostra.p + direita * (recuo * lado) + amostra.t * desvio

						pos = pousar(pos, amostra.p.Y, faixa.Encaixar, cfg, filtro)
						pos = pos + Vector3.new(0,
							faixa.Altura + rng:NextNumber(-0.5, 0.5) * faixa.VariacaoAltura, 0)

						local livre = true
						for _, outra in ipairs(colocadas) do
							if (outra - pos).Magnitude < faixa.DistanciaMinima then
								livre = false
							end
						end

						if livre then
							local alvo = Vector3.new(amostra.p.X, pos.Y, amostra.p.Z)
							local base
							if (alvo - pos).Magnitude > 0.25 then
								base = CFrame.lookAt(pos, alvo)
							else
								base = CFrame.new(pos)
							end
							base = base * CFrame.Angles(0,
								math.rad(rng:NextNumber(-1, 1) * faixa.GiroAleatorio), 0)

							local nevoa = nivelDeNevoa(math.abs(recuo), cfg)
							local escala = faixa.Escala *
								(1 + rng:NextNumber(-1, 1) * faixa.VariacaoEscala)
							local ctx = novoContexto(cfg, faixa, base, nevoa, rng, escala)

							if ehCasa then
								local nome
								if faixa.Tipo == "PLACA" then
									nome = "Placa"
								else
									nome = escolher(rng, faixa.Arquetipos)
								end
								local p, tr = montarCorpo(ctx, nome, faixa, pasta)
								totalPecas = totalPecas + p
								totalTris = totalTris + tr
								totalCasas = totalCasas + 1
							else
								construirArvore(ctx)
								ctx.modelo.Name = "Pinheiro"
								definirSeguro(ctx.modelo, "LevelOfDetail", Enum.ModelLevelOfDetail.Disabled)
								ctx.modelo.Parent = pasta
								totalPecas = totalPecas + ctx.pecas
								totalTris = totalTris + ctx.tris
								totalArvores = totalArvores + 1
							end
							table.insert(colocadas, pos)
						end
					end
				end
			end
		end

		pasta.Parent = raiz
	end

	raiz.Parent = pai

	if cfg.Relatorio then
		print(string.format(
			"[ScenarioCasas] %s: %d construções + %d árvores ao longo de %d pontos de pista | %d partes, ~%d triângulos.",
			cfg.Nome, totalCasas, totalArvores, #pontos, totalPecas, totalTris))
	end

	return raiz
end

----------------------------------------------------------------------
-- 9. COLOCAR NA MÃO — pra ir montando aos poucos
----------------------------------------------------------------------

-- GetAttribute devolvendo false tem que vencer o padrão, e `or` não faz isso
local function atributoOu(instancia, chave, padrao)
	local valor = instancia:GetAttribute(chave)
	if valor == nil then
		return padrao
	end
	return valor
end

local function destinoAvulso(opcoes)
	if opcoes.Pai then return opcoes.Pai end
	local nome = opcoes.Nome or "CenarioAvulso"
	local existente = workspace:FindFirstChild(nome)
	if existente then return existente end
	local modelo = Instance.new("Model")
	modelo.Name = nome
	definirSeguro(modelo, "ModelStreamingMode", Enum.ModelStreamingMode.Persistent)
	modelo.Parent = workspace
	return modelo
end

--- Uma construção em um lugar específico.
--  @param onde Vector3 (chão da casa) ou CFrame
--  @param opcoes campos de FAIXA_PADRAO + Arquetipo, Semente, Nevoa,
--         VirarPara (Vector3), Virar ("pista" | "marcador")
function ScenarioCasas.ColocarEm(onde, opcoes)
	opcoes = opcoes or {}
	local pos, rotacao
	if typeof(onde) == "CFrame" then
		pos, rotacao = onde.Position, onde.Rotation
	else
		pos = onde
	end

	local cfg = mesclar(PADRAO, opcoes.Config)
	if (opcoes.Config == nil) or (opcoes.Config.NevoaInicio == nil) then
		cfg.NevoaInicio = 60
	end
	if (opcoes.Config == nil) or (opcoes.Config.NevoaFim == nil) then
		cfg.NevoaFim = 900
	end

	local faixa = mesclar(FAIXA_PADRAO, opcoes)
	local rng = Random.new(opcoes.Semente or math.floor(os.clock() * 1e6))

	local amostra, distLateral = maisProximoNaPista(pos)
	local base
	if opcoes.VirarPara then
		local alvo = Vector3.new(opcoes.VirarPara.X, pos.Y, opcoes.VirarPara.Z)
		if (alvo - pos).Magnitude > 0.25 then
			base = CFrame.lookAt(pos, alvo)
		end
	end
	if (not base) and opcoes.Virar ~= "marcador" and amostra then
		local alvo = Vector3.new(amostra.p.X, pos.Y, amostra.p.Z)
		if (alvo - pos).Magnitude > 0.25 then
			base = CFrame.lookAt(pos, alvo)
		end
	end
	if (not base) and rotacao then
		base = CFrame.new(pos) * rotacao
	end
	if not base then
		base = CFrame.new(pos)
	end
	-- na mão, o giro é seu: só desalinha se você pedir
	local giro = opcoes.GiroAleatorio or 0
	if giro > 0 then
		base = base * CFrame.Angles(0, math.rad(rng:NextNumber(-1, 1) * giro), 0)
	end

	local nevoa = opcoes.Nevoa
	if nevoa == nil then
		if distLateral then
			nevoa = nivelDeNevoa(distLateral, cfg)
		else
			nevoa = 0
		end
	end

	local ctx = novoContexto(cfg, faixa, base, nevoa, rng, faixa.Escala)
	local nome = opcoes.Arquetipo
	if not nome then
		if faixa.Tipo == "PLACA" then
			nome = "Placa"
		else
			nome = escolher(rng, faixa.Arquetipos)
		end
	end
	montarCorpo(ctx, nome, faixa, destinoAvulso(opcoes))
	return ctx.modelo
end

--- Command Bar: põe uma construção onde a câmera do Studio está olhando.
--  Voa até o ponto, roda, nasce a casa. Seta pra cima + Enter repete.
function ScenarioCasas.Aqui(opcoes)
	opcoes = opcoes or {}
	local cam = workspace.CurrentCamera
	if not cam then
		warn("[ScenarioCasas] Sem CurrentCamera — isso é pra rodar na Command Bar do Studio.")
		return nil
	end
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	filtro.FilterDescendantsInstances = opcoes.Ignorar or {}
	filtro.IgnoreWater = true

	local alcance = opcoes.Alcance or 3000
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * alcance, filtro)
	local pos
	if hit then
		pos = hit.Position
	else
		pos = cam.CFrame.Position + cam.CFrame.LookVector * 120
	end

	local op = mesclar(opcoes, {})
	if (op.VirarPara == nil) and (pistaAtual == nil) then
		op.VirarPara = cam.CFrame.Position     -- sem pista definida, encara a câmera
	end
	local modelo = ScenarioCasas.ColocarEm(pos, op)
	print(string.format("[ScenarioCasas] %s em %.0f, %.0f, %.0f",
		modelo.Name, pos.X, pos.Y, pos.Z))
	return modelo
end

--- Command Bar: uma construção em cima de cada Part selecionada.
function ScenarioCasas.NaSelecao(opcoes)
	opcoes = opcoes or {}
	local ok, Selection = pcall(function() return game:GetService("Selection") end)
	if (not ok) or (not Selection) then
		warn("[ScenarioCasas] NaSelecao só roda na Command Bar do Studio.")
		return {}
	end
	local feitas = {}
	for _, item in ipairs(Selection:Get()) do
		if item:IsA("BasePart") then
			table.insert(feitas, ScenarioCasas.ColocarEm(item.CFrame, opcoes))
		end
	end
	print(string.format("[ScenarioCasas] %d construções colocadas na seleção.", #feitas))
	return feitas
end

--- Constrói a partir de uma pasta de marcadores que você posicionou.
--  O jeito não-destrutivo de trabalhar: mexe no marcador, roda de novo.
--  Atributos aceitos em cada marcador: Arquetipo, Tipo, Escala, Nevoa,
--  Semente, Colidir, Detalhe, Virar ("pista" | "marcador").
function ScenarioCasas.Marcadores(origem, opcoes)
	opcoes = opcoes or {}
	origem = origem or workspace:FindFirstChild("MarcadoresCasas")
	if not origem then
		warn("[ScenarioCasas] Não achei a pasta de marcadores.")
		return nil
	end

	local pai = opcoes.Pai or workspace
	local nome = opcoes.Nome or "CenarioMarcadores"
	local antigo = pai:FindFirstChild(nome)
	if antigo then antigo:Destroy() end

	local raiz = Instance.new("Model")
	raiz.Name = nome
	definirSeguro(raiz, "ModelStreamingMode", Enum.ModelStreamingMode.Persistent)

	local total = 0
	for _, marcador in ipairs(origem:GetDescendants()) do
		if marcador:IsA("BasePart") then
			local semente = marcador:GetAttribute("Semente")
			if not semente then
				-- mesma posição = mesma casa toda vez que reconstruir
				semente = math.floor(math.abs(marcador.Position.X) * 7
					+ math.abs(marcador.Position.Y) * 13
					+ math.abs(marcador.Position.Z) * 17) + #marcador.Name
			end
			local op = mesclar(opcoes, {
				Pai = raiz,
				Semente = semente,
				Arquetipo = atributoOu(marcador, "Arquetipo", opcoes.Arquetipo),
				Tipo = atributoOu(marcador, "Tipo", opcoes.Tipo),
				Escala = atributoOu(marcador, "Escala", opcoes.Escala),
				Nevoa = atributoOu(marcador, "Nevoa", opcoes.Nevoa),
				Colidir = atributoOu(marcador, "Colidir", opcoes.Colidir),
				Detalhe = atributoOu(marcador, "Detalhe", opcoes.Detalhe),
				Virar = atributoOu(marcador, "Virar", opcoes.Virar),
			})
			ScenarioCasas.ColocarEm(marcador.CFrame, op)
			total = total + 1
		end
	end

	raiz.Parent = pai
	print(string.format("[ScenarioCasas] %d marcadores construídos em %s.", total, nome))
	return raiz
end

--- Command Bar: larga o próximo ponto da pista onde a câmera olha.
--  Voa seguindo a trilha, Enter, Enter, Enter... e pronto: o caminho.
function ScenarioCasas.MarcarPonto(nomePasta)
	nomePasta = nomePasta or "CaminhoPista"
	local pasta = workspace:FindFirstChild(nomePasta)
	if not pasta then
		pasta = Instance.new("Folder")
		pasta.Name = nomePasta
		pasta.Parent = workspace
	end

	local cam = workspace.CurrentCamera
	if not cam then
		warn("[ScenarioCasas] Sem CurrentCamera — isso é pra rodar na Command Bar do Studio.")
		return nil
	end

	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	filtro.FilterDescendantsInstances = { pasta }
	filtro.IgnoreWater = true
	local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * 3000, filtro)
	local pos
	if hit then
		pos = hit.Position + Vector3.new(0, 2, 0)
	else
		pos = cam.CFrame.Position + cam.CFrame.LookVector * 80
	end

	local quantos = 0
	for _, filho in ipairs(pasta:GetChildren()) do
		if filho:IsA("BasePart") then
			quantos = quantos + 1
		end
	end

	local ponto = Instance.new("Part")
	ponto.Name = string.format("%03d", quantos + 1)
	ponto.Shape = Enum.PartType.Ball
	ponto.Size = Vector3.new(6, 6, 6)
	ponto.Position = pos
	ponto.Anchored = true
	ponto.CanCollide = false
	ponto.CanQuery = false
	ponto.CanTouch = false
	ponto.CastShadow = false
	ponto.Transparency = 0.4
	ponto.Color = Color3.fromRGB(255, 170, 40)
	ponto.Material = Enum.Material.Neon
	ponto.Parent = pasta

	print(string.format("[ScenarioCasas] ponto %s da pista (%d no total).", ponto.Name, quantos + 1))
	return ponto
end

ScenarioCasas.FAIXA_PADRAO = FAIXA_PADRAO
ScenarioCasas.FAIXAS_PADRAO = FAIXAS_PADRAO

ScenarioCasas.PALETA = PALETA
ScenarioCasas.PADRAO = PADRAO

return ScenarioCasas
