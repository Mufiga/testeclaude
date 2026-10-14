--[[
	ScenarioCasas  —  casas de cenário (estilo set de cinema) para Roblox
	-------------------------------------------------------------------
	A ideia é a mesma de um backlot de estúdio: o que o jogador vê é
	volume de verdade (tem profundidade, pega luz, projeta silhueta),
	mas é casca. Nada de interior, nada de porta que abre, nada de
	MeshPart. Só caixas e cunhas, montadas em três faixas de distância:

	  VOLUME  (perto)  casa com casca de meia-profundidade, janelas,
	                   porta, chaminé. ~9 a 12 partes.
	  CAIXA   (meio)   mesma silhueta, sem detalhe, profundidade menor
	                   e cor já puxada pra névoa. ~4 a 6 partes.
	  PLACA   (longe)  recorte de cenário: 3 partes finas viradas pro
	                   ponto de foco. Lê como prédio, custa quase nada.

	Os dois truques que fazem isso parecer caro:

	  1. Perspectiva aérea. Toda peça tem a cor interpolada na direção
	     da cor da atmosfera conforme a distância do foco. É o que o
	     olho usa pra julgar profundidade — mais do que polígono.
	  2. Perspectiva forçada. As camadas distantes são construídas
	     menores do que seriam de verdade e todas apontam pro ponto de
	     onde o jogador olha. O vale parece ter o dobro do tamanho.

	Tudo é Anchored, CastShadow=false, CanQuery=false, CanTouch=false,
	SmoothPlastic, e cada casa tem no máximo UM collider (invisível) em
	vez de nove partes colidíveis.

	USO
	---
	ServerScriptService
	  └ ScenarioCasas      (ModuleScript — este arquivo)
	  └ MontarCenario      (Script — veja ExemploUso.server.lua)

		local Cenario = require(script.Parent.ScenarioCasas)
		Cenario.Construir({
			Foco = Vector3.new(0, 25, 0),       -- de onde o jogador olha
			Direcao = Vector3.new(0, 0, -1),    -- pra onde o cenário se abre
		})
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

--- Constrói o cenário inteiro. Devolve o Model raiz.
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

ScenarioCasas.PALETA = PALETA
ScenarioCasas.PADRAO = PADRAO

return ScenarioCasas
