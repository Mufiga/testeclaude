# Combo de estilo: o que prende o jogador

São 2 scripts **novos** (você só cria e cola) e 6 mudanças pequenas em scripts que já existem. Mais 2 mudanças opcionais na Pista.
Antes de mudar qualquer coisa, salve uma cópia do jogo (File › Save to File As...).

---

## ETAPA 1 — Diagnóstico (o que o vídeo mostra)

Os "brinquedos" do seu jogo já são bons:
- derrapada com marcas de pneu;
- nitro com chama;
- gancho de impulso;
- voo de ponto em ponto com **PERFEITO!**.

O problema é que **nada disso vale nada**. O jogador faz uma corrente de voo perfeita, pousa... e o jogo não reage. O dinheiro só vem de moeda e checkpoint, e o nitro enche sozinho com o tempo, então não existe motivo para arriscar uma manobra.

Os jogos que "viciam" pela jogabilidade (Tony Hawk, Forza Horizon, Burnout, Trials) usam o mesmo ciclo:

1. **Resposta na hora**: toda manobra faz barulho, mostra pontos e sobe um número.
2. **Tensão que cresce**: quanto mais você emenda, maior o multiplicador e maior o medo de errar.
3. **Alívio com prêmio**: o combo fecha com um número grande, um nível ("INSANO!") e dinheiro.
4. **Progresso**: o recorde pessoal, que você quer bater.
5. **Comparação**: os outros jogadores veem o seu combo enorme.

Hoje o seu jogo só tem um pedaço do item 1 (o PERFEITO!). Esta atualização coloca os 5.

---

## ETAPA 2 — Solução: o COMBO DE ESTILO

### O ciclo
```
manobra → PONTOS na tela + NITRO enche → mais velocidade → mais manobras → MULTIPLICADOR sobe (x2...x10)
       → a barrinha corre (se parar, o combo FECHA) → FECHOU: "+34.524 INCRÍVEL!" + 34 $ + recorde
                                                   → CAPOTOU/BATEU antes: "COMBO PERDIDO -34.524"
```

### O que vale ponto
| Dirigindo | Voando |
|---|---|
| **DERRAPADA**: de lado no chão, por segundo | **VOO!**: pegou um ponto de voo (500) |
| **VELOCIDADE**: acima de 65, por segundo (o nitro te leva lá) | **VOO x2, x3...**: cada ponto emendado sem tocar o chão vale mais (1000, 1500...) |
| **RASPANDO**: rápido e colado numa parede, por segundo | **VOANDO**: pendurado num ponto de voo, por segundo |
| **BOOST!**: passou num boost pad | **PERFEITO!**: o seu, do gancho (1000) |
| **NO AR**: as rodas fora do chão, por segundo | **GIRO 360**: solte o gancho e segure A/D no ar até dar a volta |
| **MORTAL / ROLAMENTO** (o monstro; a 2ª volta vale o triplo) | **POUSO LIMPO**: caiu retinho de um pulo grande (400) |

Cada manobra (ou cada atividade que durou o mínimo) **sobe o multiplicador**. Os pontos são somados e, quando o combo fecha, multiplicados.

### Por que isso prende
- **Os pontos enchem o nitro** (3000 pontos = tanque cheio). Fazer manobra dá nitro, nitro dá velocidade e velocidade dá mais manobra. Para esse ciclo valer, o nitro passa a encher **sozinho** mais devagar (6 → 10 s).
- **O risco**: o combo só VALE quando FECHA (2,5 s sem fazer nada). Capotou ou bateu antes, perde tudo. A barrinha fica **vermelha e piscando** quando está acabando.
- **A sensação de "pegar fogo"**: do x4 para cima, as bordas da tela brilham na cor do multiplicador. O "plim" de cada manobra fica mais agudo a cada multiplicador.
- **NOVO RECORDE!** aparece NA HORA em que você passa do recorde, no meio do combo, e aí ninguém quer perder.
- **Níveis**: BOM! (2.000), ÓTIMO! (6.000), INCRÍVEL! (15.000), INSANO! (35.000), LENDÁRIO! (75.000).
- **Social**: um combo INSANO (ou um recorde acima de 15.000) aparece na tela de todo mundo do servidor. O recorde vira a coluna **"Combo"** no TAB.
- Tudo vem de **habilidade**, nada de sorte: o jogador sente que ele melhorou, e não que o jogo deu.

### Exemplos (com os números padrão)
- **Só dirigindo**: derrapada 2 s + nitro 2 s + raspando 1 s = 850 pontos × **x4** = **3.400 (BOM!)**, +3 $, e o nitro enche 28%.
- **Corrente de voo com 2 pontos**:
  - VOO! + VOANDO + PERFEITO! + NO AR + VOO x2! + VOANDO + NO AR + POUSO LIMPO = 3.836 pontos;
  - × **x9** = **34.524 (INCRÍVEL!)**, +34 $ e o tanque de nitro cheio.
  - Com 3 pontos, passa de 35.000 (INSANO!) e o servidor inteiro fica sabendo.

### Segurança (multiplayer)
- O combo é contado no **cliente** de quem dirige: a física é dele, e assim não há atraso.
- Quem **paga** é o servidor (EstiloServidor). Cada jogador tem um "cofrinho" de pontos que só enche **enquanto ele dirige** (2.500 por segundo).
- Um combo nunca vale mais do que o cofrinho tem. Um trapaceiro que manda "fiz 1 milhão" ganha, no máximo, o que um jogador muito bom ganharia dirigindo o mesmo tempo.
- O dinheiro vai para o mesmo `leaderstats.Dinheiro`, e quem salva é o seu script Progresso (não mexi nele).
- O recorde fica num DataStore separado, e o salvamento sempre guarda o **maior** valor: um recorde nunca diminui, nem se o carregar falhar.

---

## ETAPA 3 — Implementação

### 3.1 — NOVO ModuleScript `Estilo`
**Onde:** StarterPlayer › StarterPlayerScripts › QuadricicloCliente › (botão direito) › Insert Object › **ModuleScript**. Renomeie para **`Estilo`** (sem acento). Ele fica junto com Veiculo, Camera, Gancho...
**O quê:** apague o que vier dentro e cole tudo:

```lua
--!strict
--[[
	=====================================================================
	Estilo  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Estilo
	       (DENTRO do QuadricicloCliente, junto com Veiculo, Camera, Gancho...)
	=====================================================================

	O COMBO DE ESTILO: tudo de legal que você faz dirigindo ou voando vale PONTOS, e cada manobra
	emendada na outra sobe o MULTIPLICADOR (x2, x3... até x10).
	  DERRAPADA ......... de lado no chão (com ou sem o freio de mão)
	  NO AR ............. as rodas fora do chão (pulinho de lombada não conta)
	  VOANDO / VOO x2 ... pendurado num ponto de voo; cada ponto emendado SEM tocar o chão vale mais
	  VELOCIDADE ........ acima de VELOCIDADE_MINIMA (o nitro te leva lá)
	  RASPANDO .......... passando rápido colado numa parede (ou num carro)
	  MORTAL / GIRO / ROLAMENTO ... dando volta no ar e caindo de rodas (a 2ª volta vale o triplo!)
	  POUSO LIMPO ....... caiu de um pulo grande retinho
	  BOOST! ............ passou num boost pad
	  e o que os outros módulos avisam com Estilo.acao: PERFEITO! (Gancho) e LOOP 360! (Pista)

	O RISCO: o combo só VALE quando ele FECHA (você fica JANELA segundos sem fazer nada: a barrinha
	mostra). Se você CAPOTAR ou BATER forte antes disso, perde TUDO. Combo grande = frio na barriga.
	O PRÊMIO: os pontos enchem o NITRO na hora. Ao fechar, o servidor (script EstiloServidor) dá
	DINHEIRO e guarda o seu RECORDE. Passou do recorde no meio do combo? "NOVO RECORDE!" na hora.
	Combo enorme de outro jogador aparece na sua tela (e o seu na dele).

	O QuadricicloCliente chama Estilo.atualizar(...) a cada frame e Estilo.desligar() ao sair do banco.
	Os números de cada coisa ficam nos AJUSTES aqui embaixo (vale para todos os veículos).
	Tudo aqui roda só no SEU computador; quem confere e paga é o servidor.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Veiculo = require(script.Parent:WaitForChild("Veiculo")) -- (a "frente" e o "cima" do veículo)
local CameraModulo = require(script.Parent:WaitForChild("Camera")) -- (o tranco na tela: Camera.tremer)
local Tela = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Tela")) -- (no celular, o HUD fica menor)
type Quadriciclo = Veiculo.Quadriciclo

local Estilo = {}

local jogadorLocal = Players.LocalPlayer :: Player

-- =====================================================================
-- AJUSTES
-- =====================================================================
-- O COMBO
local JANELA = 2.5 -- (s) sem fazer NADA por esse tempo, o combo FECHA e vale. Menor = mais difícil.
local MULTIPLICADOR_MAXIMO = 10
local NITRO_POR_PONTO = 1 / 3000 -- cada ponto enche um pouco o nitro: 3000 pontos = o tanque inteiro (0 = desliga)
local PONTOS_MINIMOS = 100 -- combo menor que isso fecha quietinho, sem aparecer
-- OS PONTOS de cada coisa (as "atividades" valem por SEGUNDO; as manobras, de uma vez)
local PONTOS_DERRAPADA = 80 -- (por segundo) + 6 para cada stud/s que ele escorrega de lado
local PONTOS_NO_AR = 180 -- (por segundo)
local PONTOS_VOANDO = 150 -- (por segundo) pendurado num ponto de voo
local PONTOS_VELOCIDADE = 60 -- (por segundo) + 4 para cada stud/s acima da VELOCIDADE_MINIMA
local PONTOS_RASPANDO = 350 -- (por segundo)
local PONTOS_MORTAL = 1200 -- 1 volta = 1200 · 2 voltas = 3600 · 3 voltas = 7200 (cada volta a mais vale mais)
local PONTOS_ROLAMENTO = 1000 -- (volta de lado; mesma conta do mortal)
local PONTOS_GIRO = 800 -- (360° em volta do "de pé", no ar; mesma conta)
local PONTOS_POUSO_LIMPO = 400
local PONTOS_VOO = 500 -- cada ponto de voo emendado: VOO! = 500 · VOO x2 = 1000 · VOO x3 = 1500...
local PONTOS_BOOST = 250
-- QUANDO CONTA
local DERRAPADA_DE_LADO = 10 -- (studs/s) escorregando de lado mais que isso...
local DERRAPADA_VELOCIDADE = 18 -- (studs/s) ...e andando pelo menos isso
local NO_AR_DEPOIS_DE = 0.4 -- (s) no ar há menos que isso não conta (lombada)
local VELOCIDADE_MINIMA = 65 -- (studs/s) para frente
local RASPANDO_VELOCIDADE = 45 -- (studs/s)
local RASPANDO_DISTANCIA = 3 -- (studs) da lateral do veículo até a parede
local POUSO_LIMPO_NO_AR = 1 -- (s) no ar pelo menos isso para valer o POUSO LIMPO
local PAUSA_TOLERADA = 0.25 -- (s) uma atividade que para menos que isso continua sendo a mesma
-- PERDER O COMBO
local CAPOTOU_DEPOIS_DE = 0.35 -- (s) de lado ou de cabeça para baixo no chão = CAPOTOU
local BATIDA_PERDA = 40 -- (studs/s) perdeu essa velocidade de uma vez (bateu numa parede) = BATEU
-- SONS ("" = sem som). Pode trocar por um som do Creator Store: "rbxassetid://123456"
local SOM_MANOBRA = "rbxasset://sounds/electronicpingshort.wav" -- o "plim" (fica mais agudo a cada multiplicador)
local SOM_PERDEU = "rbxasset://sounds/clickfast.wav" -- (tocado bem grave)
local VOLUME = 0.55
-- A TELA
local POSICAO = UDim2.new(1, -16, 0, 74) -- canto de cima, à DIREITA (abaixo do aviso do mouse)
local LARGURA = 300 -- (pixels)
local DURACAO_DA_LINHA = 3 -- (s) cada manobra fica na lista esse tempo
local MAXIMO_DE_LINHAS = 4
local BRILHO_A_PARTIR_DE = 4 -- a partir deste multiplicador, as bordas da tela brilham ("pegando fogo")
local TAG_VOAR_GANCHO = "Voar_Gancho" -- (a mesma tag do gancho de voo)

-- Os NÍVEIS do combo fechado (do maior para o menor). O servidor usa os mesmos números para avisar todo mundo.
type Nivel = { minimo: number, nome: string, cor: Color3 }
local NIVEIS: { Nivel } = {
	{ minimo = 75000, nome = "LENDÁRIO!", cor = Color3.fromRGB(240, 80, 255) },
	{ minimo = 35000, nome = "INSANO!", cor = Color3.fromRGB(255, 70, 90) },
	{ minimo = 15000, nome = "INCRÍVEL!", cor = Color3.fromRGB(255, 140, 40) },
	{ minimo = 6000, nome = "ÓTIMO!", cor = Color3.fromRGB(255, 205, 60) },
	{ minimo = 2000, nome = "BOM!", cor = Color3.fromRGB(120, 255, 160) },
}
-- A cor do multiplicador: branco no x1, dourado no meio, rosa no x10.
local CORES_DO_MULTIPLICADOR: { Color3 } = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 245, 170),
	Color3.fromRGB(255, 230, 110),
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(255, 180, 40),
	Color3.fromRGB(255, 150, 40),
	Color3.fromRGB(255, 115, 45),
	Color3.fromRGB(255, 80, 60),
	Color3.fromRGB(255, 70, 130),
	Color3.fromRGB(240, 80, 255),
}
local COR_PONTOS = Color3.fromRGB(255, 255, 255)
local COR_FRACA = Color3.fromRGB(200, 205, 220)
local COR_RECORDE = Color3.fromRGB(255, 215, 70)
local COR_PERDEU = Color3.fromRGB(255, 70, 70)
local COR_DINHEIRO = Color3.fromRGB(90, 230, 120)
local COR_CONTORNO = Color3.fromRGB(25, 15, 35)

-- =====================================================================
-- CONTAS PEQUENAS
-- =====================================================================
-- 12350 vira "12.350".
local function formatar(numero: number): string
	local invertido = string.reverse(tostring(math.floor(numero + 0.5)))
	local comPontos = string.reverse((string.gsub(invertido, "(%d%d%d)", "%1.")))
	if string.sub(comPontos, 1, 1) == "." then
		comPontos = string.sub(comPontos, 2)
	end
	return comPontos
end

-- 1.84 vira "1,8".
local function segundos(tempo: number): string
	return (string.gsub(string.format("%.1f", tempo), "%.", ","))
end

local function nivelDe(pontos: number): Nivel?
	for _, nivel in NIVEIS do
		if pontos >= nivel.minimo then
			return nivel
		end
	end
	return nil
end

local function corDoMultiplicador(multiplicador: number): Color3
	return CORES_DO_MULTIPLICADOR[math.clamp(multiplicador, 1, #CORES_DO_MULTIPLICADOR)]
end

-- "MORTAL" com 2 voltas vira "MORTAL DUPLO".
local function comVezes(nome: string, vezes: number): string
	if vezes == 2 then
		return nome .. " DUPLO"
	elseif vezes == 3 then
		return nome .. " TRIPLO"
	elseif vezes > 3 then
		return `{nome} x{vezes}`
	end
	return nome
end

-- O recorde que o servidor guardou (atributo "RecordeCombo" no seu Player).
local function recordeDoServidor(): number
	local valor = jogadorLocal:GetAttribute("RecordeCombo")
	return if typeof(valor) == "number" then valor else 0
end

-- =====================================================================
-- A TELA DO COMBO (criada na primeira vez que precisa)
-- =====================================================================
type Hud = {
	tela: ScreenGui,
	linhasDoCombo: { GuiObject }, -- o que aparece DURANTE o combo (some quando ele fecha)
	multiplicador: TextLabel,
	escalaMultiplicador: UIScale,
	total: TextLabel,
	fundoBarra: Frame,
	barra: Frame,
	vivas: Frame, -- as atividades acontecendo agora
	lista: Frame, -- as últimas manobras
	recorde: TextLabel,
	fim: Frame, -- o que aparece quando o combo FECHA (ou é perdido)
	resultado: TextLabel,
	escalaResultado: UIScale,
	nivel: TextLabel,
	dinheiro: TextLabel,
	somA: Sound,
	somB: Sound,
	somPerdeu: Sound,
	bordas: { Frame }, -- o brilho nas bordas da tela
	clarao: Frame, -- o "flash" da tela inteira
}
local hud: Hud? = nil

local function novoTexto(pai: Instance, ordem: number, altura: number, tamanho: number, cor: Color3, fonte: Enum.Font): TextLabel
	local rotulo = Instance.new("TextLabel")
	rotulo.LayoutOrder = ordem
	rotulo.Size = UDim2.new(1, 0, 0, altura)
	rotulo.BackgroundTransparency = 1
	rotulo.Font = fonte
	rotulo.TextSize = tamanho
	rotulo.TextColor3 = cor
	rotulo.TextStrokeColor3 = COR_CONTORNO
	rotulo.TextStrokeTransparency = 0.25
	rotulo.TextXAlignment = Enum.TextXAlignment.Right
	rotulo.RichText = true
	rotulo.Text = ""
	rotulo.Parent = pai
	return rotulo
end

local function novaPilha(pai: Instance, espaco: number)
	local pilha = Instance.new("UIListLayout")
	pilha.SortOrder = Enum.SortOrder.LayoutOrder
	pilha.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pilha.Padding = UDim.new(0, espaco)
	pilha.Parent = pai
end

local function novoQuadro(pai: Instance, ordem: number): Frame
	local quadro = Instance.new("Frame")
	quadro.LayoutOrder = ordem
	quadro.Size = UDim2.new(1, 0, 0, 0)
	quadro.AutomaticSize = Enum.AutomaticSize.Y
	quadro.BackgroundTransparency = 1
	quadro.Parent = pai
	return quadro
end

local function novoSom(pai: Instance, id: string): Sound
	local som = Instance.new("Sound")
	som.SoundId = id
	som.Volume = VOLUME
	som.Parent = pai -- (dentro da tela: só você ouve, sem depender de distância)
	return som
end

local function criarHud(): Hud?
	local playerGui = jogadorLocal:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local tela = Instance.new("ScreenGui")
	tela.Name = "HUDEstilo"
	tela.ResetOnSpawn = false
	tela.DisplayOrder = 8
	tela.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- (no celular, fora do entalhe da câmera)
	tela.Enabled = false

	local painel = Instance.new("Frame")
	painel.Name = "Combo"
	painel.AnchorPoint = Vector2.new(1, 0) -- (preso pelo canto de cima, à direita)
	painel.Position = POSICAO
	painel.Size = UDim2.fromOffset(LARGURA, 0)
	painel.AutomaticSize = Enum.AutomaticSize.Y
	painel.BackgroundTransparency = 1
	painel.Parent = tela
	Tela.encolher(painel) -- (no celular, menor)
	novaPilha(painel, 0)

	-- 1) "COMBO x4" (o x4 dá um pulo cada vez que sobe)
	local caixaDoMultiplicador = Instance.new("Frame")
	caixaDoMultiplicador.LayoutOrder = 1
	caixaDoMultiplicador.Size = UDim2.new(1, 0, 0, 52)
	caixaDoMultiplicador.BackgroundTransparency = 1
	caixaDoMultiplicador.Parent = painel
	local multiplicador = novoTexto(caixaDoMultiplicador, 0, 52, 50, COR_PONTOS, Enum.Font.FredokaOne)
	multiplicador.AnchorPoint = Vector2.new(1, 0.5) -- (o pulo cresce a partir da ponta direita)
	multiplicador.Position = UDim2.fromScale(1, 0.5)
	local escalaMultiplicador = Instance.new("UIScale")
	escalaMultiplicador.Parent = multiplicador
	-- 2) os pontos (sobem "rolando")
	local total = novoTexto(painel, 2, 34, 32, COR_PONTOS, Enum.Font.GothamBlack)
	-- 3) a barrinha da JANELA (quando ela acaba, o combo fecha)
	local fundoBarra = Instance.new("Frame")
	fundoBarra.LayoutOrder = 3
	fundoBarra.Size = UDim2.fromOffset(170, 7)
	fundoBarra.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	fundoBarra.BorderSizePixel = 0
	fundoBarra.Parent = painel
	local cantoBarra = Instance.new("UICorner")
	cantoBarra.CornerRadius = UDim.new(1, 0)
	cantoBarra.Parent = fundoBarra
	local barra = Instance.new("Frame")
	barra.AnchorPoint = Vector2.new(1, 0) -- (esvazia da esquerda para a direita, na direção do número)
	barra.Position = UDim2.fromScale(1, 0)
	barra.Size = UDim2.fromScale(1, 1)
	barra.BorderSizePixel = 0
	barra.Parent = fundoBarra
	cantoBarra:Clone().Parent = barra
	-- 4) as atividades de agora e 5) as últimas manobras
	local vivas = novoQuadro(painel, 4)
	novaPilha(vivas, 0)
	local lista = novoQuadro(painel, 5)
	novaPilha(lista, 0)
	-- 6) o recorde
	local recorde = novoTexto(painel, 6, 18, 14, COR_FRACA, Enum.Font.GothamBold)
	-- 7) O FIM: "+12.400" · "ÓTIMO!" · "+12 $"
	local fim = novoQuadro(painel, 7)
	fim.Visible = false
	novaPilha(fim, 0)
	local caixaDoResultado = Instance.new("Frame")
	caixaDoResultado.LayoutOrder = 1
	caixaDoResultado.Size = UDim2.new(1, 0, 0, 50)
	caixaDoResultado.BackgroundTransparency = 1
	caixaDoResultado.Parent = fim
	local resultado = novoTexto(caixaDoResultado, 0, 50, 46, COR_PONTOS, Enum.Font.FredokaOne)
	resultado.AnchorPoint = Vector2.new(1, 0.5) -- (o pulo cresce a partir da ponta direita)
	resultado.Position = UDim2.fromScale(1, 0.5)
	local escalaResultado = Instance.new("UIScale")
	escalaResultado.Parent = resultado
	local nivel = novoTexto(fim, 2, 28, 26, COR_PONTOS, Enum.Font.FredokaOne)
	local dinheiro = novoTexto(fim, 3, 24, 20, COR_DINHEIRO, Enum.Font.GothamBlack)

	-- O BRILHO NAS BORDAS e o FLASH (numa tela separada, ATRÁS dos outros HUDs)
	local telaDoBrilho = Instance.new("ScreenGui")
	telaDoBrilho.Name = "BrilhoDoCombo"
	telaDoBrilho.ResetOnSpawn = false
	telaDoBrilho.ScreenInsets = Enum.ScreenInsets.None -- (a tela INTEIRA, até atrás da barra do Roblox)
	telaDoBrilho.DisplayOrder = -1
	local bordas: { Frame } = {}
	-- giro do degradê: 0 = da esquerda para a direita · 90 = de cima para baixo...
	type Lado = { tamanho: UDim2, posicao: UDim2, giro: number }
	local lados: { Lado } = {
		{ tamanho = UDim2.fromScale(0.14, 1), posicao = UDim2.fromScale(0, 0), giro = 0 }, -- esquerda
		{ tamanho = UDim2.fromScale(0.14, 1), posicao = UDim2.fromScale(0.86, 0), giro = 180 }, -- direita
		{ tamanho = UDim2.fromScale(1, 0.18), posicao = UDim2.fromScale(0, 0), giro = 90 }, -- em cima
		{ tamanho = UDim2.fromScale(1, 0.18), posicao = UDim2.fromScale(0, 0.82), giro = 270 }, -- embaixo
	}
	for _, lado in lados do
		local borda = Instance.new("Frame")
		borda.Size = lado.tamanho
		borda.Position = lado.posicao
		borda.BackgroundTransparency = 1
		borda.BorderSizePixel = 0
		local degrade = Instance.new("UIGradient") -- forte na beirada, some indo para o meio da tela
		degrade.Rotation = lado.giro
		degrade.Transparency = NumberSequence.new(0, 1)
		degrade.Parent = borda
		borda.Parent = telaDoBrilho
		table.insert(bordas, borda)
	end
	local clarao = Instance.new("Frame")
	clarao.Size = UDim2.fromScale(1, 1)
	clarao.BackgroundTransparency = 1
	clarao.BorderSizePixel = 0
	clarao.Parent = telaDoBrilho

	telaDoBrilho.Parent = playerGui
	tela.Parent = playerGui
	return {
		tela = tela,
		linhasDoCombo = { caixaDoMultiplicador, total, fundoBarra, vivas, lista, recorde },
		multiplicador = multiplicador,
		escalaMultiplicador = escalaMultiplicador,
		total = total,
		fundoBarra = fundoBarra,
		barra = barra,
		vivas = vivas,
		lista = lista,
		recorde = recorde,
		fim = fim,
		resultado = resultado,
		escalaResultado = escalaResultado,
		nivel = nivel,
		dinheiro = dinheiro,
		somA = novoSom(tela, SOM_MANOBRA),
		somB = novoSom(tela, SOM_MANOBRA),
		somPerdeu = novoSom(tela, SOM_PERDEU),
		bordas = bordas,
		clarao = clarao,
	}
end

local function pegarHud(): Hud?
	local atual = hud
	if atual and atual.tela.Parent ~= nil then
		return atual
	end
	hud = criarHud()
	return hud
end

local function tocar(som: Sound, velocidade: number, volume: number?)
	if som.SoundId == "" then
		return
	end
	som.PlaybackSpeed = velocidade
	som.Volume = VOLUME * (volume or 1)
	som:Play()
end

-- O "flash" da tela inteira (forca: 0 = nada · 1 = tela toda da cor).
local function clarao(cor: Color3, forca: number)
	local atual = pegarHud()
	if atual == nil then
		return
	end
	atual.clarao.BackgroundColor3 = cor
	atual.clarao.BackgroundTransparency = 1 - forca
	TweenService:Create(atual.clarao, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- =====================================================================
-- O COMBO
-- =====================================================================
type Atividade = {
	nome: string, -- o que aparece na tela
	minimo: number, -- (s) durou pelo menos isso = conta como manobra (sobe o multiplicador)
	ativa: boolean,
	tempo: number, -- (s) há quanto tempo está acontecendo
	valor: number, -- os pontos que ela já deu
	parada: number, -- (s) há quanto tempo parou (uma pausa curtinha não acaba com ela)
	rotulo: TextLabel?, -- a linha dela na tela
}
local function novaAtividade(nome: string, minimo: number): Atividade
	return { nome = nome, minimo = minimo, ativa = false, tempo = 0, valor = 0, parada = 0, rotulo = nil }
end
local atividades = {
	Voando = novaAtividade("VOANDO", 0.5),
	NoAr = novaAtividade("NO AR", 0.6),
	Derrapada = novaAtividade("DERRAPADA", 0.6),
	Raspando = novaAtividade("RASPANDO", 0.3),
	Velocidade = novaAtividade("VELOCIDADE", 1),
}
local ORDEM_DAS_ATIVIDADES: { Atividade } = { atividades.Voando, atividades.NoAr, atividades.Derrapada, atividades.Raspando, atividades.Velocidade }

local comboAtivo = false
local pontos = 0 -- os pontos do combo (antes de multiplicar)
local multiplicador = 1
local janelaAte = 0 -- (os.clock) quando o combo fecha, se você não fizer mais nada
local bateuRecorde = false -- já passou do recorde neste combo?
local recordeLocal = 0 -- o seu recorde (o do servidor, ou o último combo seu, se for maior)
local mostrado = 0 -- o número que está na tela (sobe "rolando" até o de verdade)
local fimAte = 0 -- (os.clock) até quando o "+12.400" (ou o "COMBO PERDIDO") fica na tela
local bloqueadoAte = 0 -- (os.clock) depois de PERDER, um combo novo só começa depois disso
local visivelCombo = 0 -- 0 = o combo sumido · 1 = aparecendo inteiro (vai suave de um para o outro)
local vezDoFim = 0 -- (conta os "fins": um combo novo cancela a animação do anterior)
local carregaNitro: Quadriciclo? = nil -- o veículo que ganha o nitro dos pontos (o que você está dirigindo)

type Linha = { rotulo: TextLabel, nasceu: number }
local linhas: { Linha } = {} -- as últimas manobras (a mais nova em cima)
local ordemDasLinhas = 0

local ligarDesenho: () -> () -- (a função vem lá embaixo; aqui só avisamos que ela existe)

local function totalAgora(): number
	return math.floor(pontos * multiplicador)
end

local function recordeAtual(): number
	return math.max(recordeLocal, recordeDoServidor())
end

local function adicionarLinha(texto: string)
	local atual = pegarHud()
	if atual == nil then
		return
	end
	ordemDasLinhas += 1
	local rotulo = novoTexto(atual.lista, -ordemDasLinhas, 22, 19, COR_PONTOS, Enum.Font.GothamBlack) -- (a mais nova em cima)
	rotulo.Text = texto
	rotulo.TextTransparency = 1
	table.insert(linhas, { rotulo = rotulo, nasceu = os.clock() })
	while #linhas > MAXIMO_DE_LINHAS do
		local velha = table.remove(linhas, 1)
		if velha then
			velha.rotulo:Destroy()
		end
	end
end

local function limparLinhas()
	for _, linha in linhas do
		linha.rotulo:Destroy()
	end
	table.clear(linhas)
end

-- Começa um combo novo (se ainda não tem um rolando). Devolve se tem um combo rolando agora.
-- (O "+12.400" do combo anterior continua aparecendo embaixo até o tempo dele acabar.)
local function comecarCombo(): boolean
	if comboAtivo then
		return true
	end
	if os.clock() < bloqueadoAte then
		return false -- (acabou de perder: deixa o "BATEU!" aparecer um pouquinho)
	end
	comboAtivo = true
	pontos = 0
	multiplicador = 1
	bateuRecorde = false
	mostrado = 0
	visivelCombo = 0
	janelaAte = os.clock() + JANELA
	limparLinhas()
	local atual = pegarHud()
	if atual then
		for _, objeto in atual.linhasDoCombo do
			objeto.Visible = true
		end
	end
	ligarDesenho()
	return true
end

-- Soma pontos ao combo (sem mexer no multiplicador). Os pontos enchem o nitro na hora.
local function somar(ganho: number)
	pontos += ganho
	local quad = carregaNitro
	if quad and NITRO_POR_PONTO > 0 then
		quad.cargaNitro = math.min(quad.cargaNitro + ganho * NITRO_POR_PONTO, 1)
	end
	-- Passou do recorde no meio do combo? Avisa NA HORA (agora é não perder!).
	local recorde = recordeAtual()
	if not bateuRecorde and recorde >= 1000 and totalAgora() > recorde then
		bateuRecorde = true
		adicionarLinha(`<font color="#FFD746">NOVO RECORDE!</font>`)
		clarao(COR_RECORDE, 0.35)
		local atual = pegarHud()
		if atual then
			tocar(atual.somA, 1.2)
			task.delay(0.1, tocar, atual.somB, 1.6)
		end
	end
end

local function subirMultiplicador()
	multiplicador = math.min(multiplicador + 1, MULTIPLICADOR_MAXIMO)
	janelaAte = os.clock() + JANELA
	local atual = pegarHud()
	if atual then
		atual.escalaMultiplicador.Scale = 1.6 -- o x4 "pula"...
		TweenService:Create(atual.escalaMultiplicador, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		tocar(atual.somA, 0.8 + 0.09 * (multiplicador - 1)) -- ...e o "plim" fica mais agudo a cada multiplicador
	end
end

-- Uma MANOBRA: soma os pontos, sobe o multiplicador e aparece na lista.
local function manobra(nome: string, base: number)
	if not comecarCombo() then
		return
	end
	somar(base)
	subirMultiplicador()
	adicionarLinha(`{nome}  <font color="#FFE066">+{formatar(base)}</font>`)
	if base >= 1000 then
		clarao(Color3.new(1, 1, 1), 0.18) -- manobra grande: um flash rapidinho
	end
end

-- Acaba com as atividades (sem contar como manobra).
local function zerarAtividades()
	for _, atividade in ORDEM_DAS_ATIVIDADES do
		atividade.ativa = false
		atividade.tempo = 0
		atividade.valor = 0
		local rotulo = atividade.rotulo
		if rotulo then
			rotulo.Visible = false
		end
	end
end

-- Uma atividade acabou: se durou o mínimo, vira manobra (sobe o multiplicador).
local function terminar(atividade: Atividade)
	atividade.ativa = false
	local rotulo = atividade.rotulo
	if rotulo then
		rotulo.Visible = false
	end
	if comboAtivo and atividade.tempo >= atividade.minimo then
		subirMultiplicador()
		adicionarLinha(`{atividade.nome} {segundos(atividade.tempo)}s  <font color="#FFE066">+{formatar(atividade.valor)}</font>`)
	end
end

-- A cada frame, para cada atividade: está acontecendo? Soma os pontos dela.
local function acompanhar(atividade: Atividade, acontecendo: boolean, porSegundo: number, dt: number)
	if acontecendo then
		if not atividade.ativa then
			if not comecarCombo() then
				return -- (acabou de perder um combo: espera um pouquinho)
			end
			atividade.ativa = true
			atividade.tempo = 0
			atividade.valor = 0
		end
		atividade.parada = 0
		atividade.tempo += dt
		local ganho = porSegundo * dt
		atividade.valor += ganho
		somar(ganho)
	elseif atividade.ativa then
		atividade.parada += dt
		if atividade.parada > PAUSA_TOLERADA then
			terminar(atividade)
		end
	end
end

-- Manda o combo fechado para o servidor (ele confere, paga e guarda o recorde).
local avisouSemServidor = false
local function enviar(total: number)
	local remoto = ReplicatedStorage:FindFirstChild("EstiloCombo")
	if remoto and remoto:IsA("RemoteEvent") then
		remoto:FireServer("Combo", total)
	elseif not avisouSemServidor then
		avisouSemServidor = true
		warn('[Estilo] Não achei o RemoteEvent "EstiloCombo": coloque o script EstiloServidor no ServerScriptService'
			.. " (sem ele o combo funciona, mas não dá dinheiro nem salva o recorde).")
	end
end

-- Mostra o "fim" do combo (resultado grande, nível e o dinheiro, que chega depois).
local function mostrarFim(texto: string, cor: Color3, embaixo: string, corEmbaixo: Color3, duracao: number): number
	vezDoFim += 1
	fimAte = os.clock() + duracao
	local atual = pegarHud()
	if atual then
		for _, objeto in atual.linhasDoCombo do
			objeto.Visible = false
		end
		atual.fim.Visible = true
		atual.fim.Rotation = 0
		atual.resultado.Text = texto
		atual.resultado.TextColor3 = cor
		atual.nivel.Text = embaixo
		atual.nivel.TextColor3 = corEmbaixo
		atual.dinheiro.Text = ""
		atual.escalaResultado.Scale = 0.4 -- "pula" para o tamanho certo
		TweenService:Create(atual.escalaResultado, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	ligarDesenho()
	return vezDoFim
end

-- O combo FECHOU: vale! Mostra, toca e manda para o servidor.
local function fechar()
	if not comboAtivo then
		return
	end
	comboAtivo = false
	zerarAtividades()
	limparLinhas()
	local total = totalAgora()
	if total < PONTOS_MINIMOS then
		return -- (combo pequenininho: some quieto)
	end
	local nivel = nivelDe(total)
	mostrarFim(`+{formatar(total)}`, if nivel then nivel.cor else COR_PONTOS,
		if nivel then nivel.nome else `COMBO x{multiplicador}`, if nivel then nivel.cor else COR_FRACA, 2.4)
	local atual = pegarHud()
	if atual then
		-- "plim-plim!" subindo (e uma terceira nota se foi recorde)
		tocar(atual.somA, 1, 1.2)
		task.delay(0.09, tocar, atual.somB, 1.35, 1.2)
		if bateuRecorde then
			task.delay(0.18, tocar, atual.somA, 1.7, 1.2)
		end
	end
	if nivel and total >= 15000 then
		clarao(nivel.cor, 0.3)
		CameraModulo.tremer(0.15)
	end
	recordeLocal = math.max(recordeLocal, total) -- (o servidor confirma logo depois)
	enviar(total)
end

-- PERDEU o combo (capotou ou bateu antes de ele fechar).
local function perder(motivo: string)
	if not comboAtivo then
		return
	end
	comboAtivo = false
	bloqueadoAte = os.clock() + 1 -- (1 segundo sem combo novo: o "BATEU!" pesa)
	zerarAtividades()
	limparLinhas()
	local total = totalAgora()
	if total < PONTOS_MINIMOS then
		return
	end
	local minhaVez = mostrarFim(motivo, COR_PERDEU, `COMBO PERDIDO  <font color="#FF9A9A">-{formatar(total)}</font>`, COR_PERDEU, 1.8)
	CameraModulo.tremer(0.18)
	clarao(COR_PERDEU, 0.22)
	local atual = pegarHud()
	if atual then
		tocar(atual.somPerdeu, 0.45, 1.3)
		-- o "não" com a cabeça: balança para os lados
		task.spawn(function()
			for _, angulo in { -7, 7, -5, 5, -3, 3, 0 } do
				if vezDoFim ~= minhaVez then
					return
				end
				atual.fim.Rotation = angulo
				task.wait(0.04)
			end
		end)
	end
end

-- =====================================================================
-- O QUE ACONTECE COM O VEÍCULO (só enquanto você dirige)
-- =====================================================================
type Estado = {
	quad: Quadriciclo,
	filtro: RaycastParams, -- os raios ignoram o veículo e você
	meiaLargura: number, -- (studs) do meio do veículo até a lateral (rodas inclusas)
	tempoNoAr: number,
	giroFrente: number, -- (radianos) quanto girou no ar: mortal (+ = para trás)...
	giroLado: number, -- ...rolamento...
	giroPiao: number, -- ...e em volta do "de pé"
	tombadoHa: number,
	rapidezRecente: number, -- a maior velocidade dos últimos instantes (vai caindo devagar)
	semGanchoHa: number, -- (s) há quanto tempo o gancho não está no ar nem preso
	alvoVisto: Instance?, -- o alvo do gancho que já foi conferido...
	alvoEhVoo: boolean, -- ...e se ele é um ponto de voo
	alvoContado: Instance?, -- o último ponto de voo que já valeu o "VOO!"
	cadeiaDeVoo: number, -- quantos pontos de voo seguidos sem tocar o chão
	noChaoHa: number,
	boostAntes: boolean,
}
local estado: Estado? = nil
local ultimaAtualizacao = 0
local vigia: RBXScriptConnection? = nil

-- O Attachment onde o gancho deste veículo está (o "GanchoAlvo" que o servidor publica).
local function alvoDoGancho(modelo: Model): Instance?
	local valor = modelo:FindFirstChild("GanchoAlvo")
	return if valor and valor:IsA("ObjectValue") then valor.Value else nil
end

-- Esse Attachment está num ponto de voo (um Model com a tag "Voar_Gancho")?
local function ehPontoDeVoo(alvo: Instance): boolean
	local atual: Instance? = alvo.Parent
	while atual and atual ~= workspace do
		if CollectionService:HasTag(atual, TAG_VOAR_GANCHO) then
			return true
		end
		atual = atual.Parent
	end
	return false
end

-- Tem uma parede colada na lateral (direita ou esquerda)?
local function paredeDoLado(atual: Estado, chassi: BasePart, direita: Vector3): boolean
	local alcance = direita * (atual.meiaLargura + RASPANDO_DISTANCIA)
	local acerto = workspace:Raycast(chassi.Position, alcance, atual.filtro)
		or workspace:Raycast(chassi.Position, -alcance, atual.filtro)
	return acerto ~= nil and math.abs(acerto.Normal.Y) < 0.5 -- (só parede de verdade: rampa e chão não contam)
end

-- O chão está logo embaixo do veículo? (para saber se ele está CAÍDO, e não girando no ar)
local function chaoPerto(atual: Estado, chassi: BasePart): boolean
	return workspace:Raycast(chassi.Position, Vector3.new(0, -(atual.meiaLargura + 6), 0), atual.filtro) ~= nil
end

-- Caiu de rodas no chão depois de um tempo no ar: fez mortal, giro, pouso limpo?
local function pousou(atual: Estado, chassi: BasePart, rodasNoChao: number)
	local volta = 2 * math.pi
	local function voltas(angulo: number): number
		return math.floor((math.abs(angulo) + 0.6) / volta) -- (0,6 rad de folga: ~35°)
	end
	local mortais, rolamentos, giros = voltas(atual.giroFrente), voltas(atual.giroLado), voltas(atual.giroPiao)
	if mortais > 0 then
		local nome = if atual.giroFrente < 0 then "MORTAL PRA FRENTE" else "MORTAL PRA TRÁS"
		manobra(comVezes(nome, mortais) .. "!", PONTOS_MORTAL * mortais * (mortais + 1) / 2)
	end
	if rolamentos > 0 then
		manobra(comVezes("ROLAMENTO", rolamentos) .. "!", PONTOS_ROLAMENTO * rolamentos * (rolamentos + 1) / 2)
	end
	if giros > 0 then
		manobra(comVezes("GIRO 360", giros) .. "!", PONTOS_GIRO * giros * (giros + 1) / 2)
	end
	if atual.tempoNoAr >= POUSO_LIMPO_NO_AR and rodasNoChao >= 2 and chassi.AssemblyAngularVelocity.Magnitude < 3 then
		manobra("POUSO LIMPO", PONTOS_POUSO_LIMPO)
	end
end

local function desligar()
	if comboAtivo then
		fechar() -- (saiu do banco no meio do combo: ele fecha e vale)
	end
	estado = nil
	carregaNitro = nil
	local conexao = vigia
	if conexao then
		conexao:Disconnect()
	end
	vigia = nil
end

local function ligar(quad: Quadriciclo): Estado
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar: { Instance } = { quad.modelo }
	local personagem = jogadorLocal.Character
	if personagem then
		table.insert(ignorar, personagem)
	end
	filtro.FilterDescendantsInstances = ignorar
	filtro.IgnoreWater = true
	local meiaLargura = quad.chassi.Size.X / 2
	for _, info in quad.rodas do
		meiaLargura = math.max(meiaLargura, math.abs(info.posicao.X) + info.roda.Size.X / 2)
	end
	recordeLocal = math.max(recordeLocal, recordeDoServidor())
	carregaNitro = quad
	if vigia == nil then
		-- Rede de segurança: se o QuadricicloCliente parar de chamar o atualizar (1 s), desliga.
		vigia = RunService.Heartbeat:Connect(function()
			if estado and os.clock() - ultimaAtualizacao > 1 then
				desligar()
			end
		end)
	end
	return {
		quad = quad,
		filtro = filtro,
		meiaLargura = meiaLargura,
		tempoNoAr = 0,
		giroFrente = 0,
		giroLado = 0,
		giroPiao = 0,
		tombadoHa = 0,
		rapidezRecente = 0,
		semGanchoHa = 0,
		alvoVisto = nil,
		alvoEhVoo = false,
		alvoContado = nil,
		cadeiaDeVoo = 0,
		noChaoHa = 0,
		boostAntes = false,
	}
end

-- =====================================================================
-- A CADA FRAME (o QuadricicloCliente chama isto enquanto você dirige)
-- =====================================================================
--   pedal: de -1 a 1 (o mesmo do QuadricicloCliente) · noBoost: true = o empurrão de um boost pad está valendo
function Estilo.atualizar(quad: Quadriciclo, dt: number, _pedal: number, noBoost: boolean?)
	ultimaAtualizacao = os.clock()
	local velho = estado
	if velho and (velho.quad ~= quad or velho.quad.chassi.Parent == nil) then
		desligar()
	end
	local atual = estado or ligar(quad)
	estado = atual
	local agora = os.clock()
	local chassi = quad.chassi
	local referencia = Veiculo.referencia(quad)
	local cima, frente, direita = referencia.UpVector, referencia.LookVector, referencia.RightVector
	local velocidade = chassi.AssemblyLinearVelocity
	local deitada = Vector3.new(velocidade.X, 0, velocidade.Z).Magnitude -- (a velocidade sem o sobe e desce)
	local paraFrente = velocidade:Dot(frente)
	local deLado = math.abs(velocidade:Dot(direita))

	-- 1) QUANTAS RODAS ESTÃO NO CHÃO? (um raio para "baixo" do veículo, saindo de cada roda)
	local rodasNoChao = 0
	for _, info in quad.rodas do
		if workspace:Raycast(info.roda.Position, -cima * (info.raio + 0.8), atual.filtro) then
			rodasNoChao += 1
		end
	end
	local noAr = rodasNoChao == 0

	-- 2) O GANCHO: preso num ponto de voo? Cada ponto NOVO emendado sem tocar o chão = VOO x2, x3...
	local modelo = quad.modelo
	local estadoGancho = modelo:GetAttribute("GanchoEstado")
	local alvo = if estadoGancho ~= nil then alvoDoGancho(modelo) else nil
	if alvo ~= atual.alvoVisto then
		atual.alvoVisto = alvo
		atual.alvoEhVoo = alvo ~= nil and ehPontoDeVoo(alvo)
	end
	local noVoo = estadoGancho == "Preso" and atual.alvoEhVoo and modelo:GetAttribute("GanchoTipo") == "Segurar"
	if noVoo and alvo ~= atual.alvoContado then
		atual.alvoContado = alvo
		atual.cadeiaDeVoo += 1
		local vezes = atual.cadeiaDeVoo
		manobra(if vezes > 1 then `VOO x{vezes}!` else "VOO!", PONTOS_VOO * vezes)
	end
	atual.semGanchoHa = if estadoGancho ~= nil then 0 else atual.semGanchoHa + dt
	atual.noChaoHa = if rodasNoChao >= 2 and estadoGancho == nil then atual.noChaoHa + dt else 0
	if atual.noChaoHa > 0.3 then
		atual.cadeiaDeVoo = 0 -- tocou o chão: a corrente de voo recomeça
	end

	-- 3) PERDEU? (CAPOTOU: de lado ou de cabeça para baixo, parado no chão · BATEU: freou de uma vez numa parede)
	local caido = false
	if cima.Y < 0.35 and noAr and math.abs(velocidade.Y) < 15 and chaoPerto(atual, chassi) then
		caido = true
		atual.tombadoHa += dt
		atual.tempoNoAr = 0 -- (caído não é "no ar": ao desvirar, não vale mortal nem pouso)
		atual.giroFrente, atual.giroLado, atual.giroPiao = 0, 0, 0
		if atual.tombadoHa > CAPOTOU_DEPOIS_DE then
			perder("CAPOTOU!")
		end
	else
		atual.tombadoHa = 0
	end
	atual.rapidezRecente = math.max(atual.rapidezRecente - 120 * dt, deitada)
	if atual.semGanchoHa > 0.6 and atual.rapidezRecente > 45 and deitada < atual.rapidezRecente - BATIDA_PERDA then
		perder("BATEU!")
		atual.rapidezRecente = deitada
	end

	-- 4) NO AR: conta as voltas. Caiu de rodas? Vê se fez mortal, giro ou pouso limpo.
	if noAr then
		atual.tempoNoAr += dt
		if estadoGancho == nil then -- (pendurado, quem gira é o pêndulo: não conta)
			local giro = chassi.AssemblyAngularVelocity
			atual.giroFrente += giro:Dot(direita) * dt
			atual.giroLado += giro:Dot(frente) * dt
			atual.giroPiao += giro:Dot(cima) * dt
		end
	else
		if atual.tempoNoAr >= NO_AR_DEPOIS_DE then
			pousou(atual, chassi, rodasNoChao)
		end
		atual.tempoNoAr = 0
		atual.giroFrente, atual.giroLado, atual.giroPiao = 0, 0, 0
	end

	-- 5) AS ATIVIDADES (valem por segundo enquanto acontecem)
	local derrapada = atividades.Derrapada
	local deLadoMinimo = if derrapada.ativa then DERRAPADA_DE_LADO * 0.6 else DERRAPADA_DE_LADO -- (para não piscar)
	acompanhar(derrapada, not caido and rodasNoChao >= 2 and deitada >= DERRAPADA_VELOCIDADE and deLado >= deLadoMinimo,
		PONTOS_DERRAPADA + 6 * deLado, dt)
	acompanhar(atividades.NoAr, noAr and not caido and not noVoo and atual.tempoNoAr >= NO_AR_DEPOIS_DE, PONTOS_NO_AR, dt)
	acompanhar(atividades.Voando, noAr and noVoo, PONTOS_VOANDO, dt)
	local veloz = atividades.Velocidade
	local minima = if veloz.ativa then VELOCIDADE_MINIMA - 7 else VELOCIDADE_MINIMA
	acompanhar(veloz, not caido and paraFrente >= minima,
		PONTOS_VELOCIDADE + 4 * math.max(paraFrente - VELOCIDADE_MINIMA, 0), dt)
	acompanhar(atividades.Raspando, not caido and deitada >= RASPANDO_VELOCIDADE and paredeDoLado(atual, chassi, direita),
		PONTOS_RASPANDO, dt)

	-- 6) BOOST PAD (só no instante em que pega)
	local boost = noBoost == true
	if boost and not atual.boostAntes then
		manobra("BOOST!", PONTOS_BOOST)
	end
	atual.boostAntes = boost

	-- 7) A JANELA: fazendo alguma coisa (ou pendurado andando), o combo não fecha.
	if comboAtivo then
		local fazendo = estadoGancho ~= nil and deitada > 15
		for _, atividade in ORDEM_DAS_ATIVIDADES do
			fazendo = fazendo or atividade.ativa
		end
		if fazendo then
			janelaAte = agora + JANELA
		elseif agora > janelaAte then
			fechar()
		end
	end
end

-- Para os OUTROS módulos: aconteceu uma manobra que só eles sabem (ex.: Estilo.acao("PERFEITO!", 1000)).
-- Só vale enquanto você está dirigindo.
function Estilo.acao(nome: string, base: number)
	if estado == nil or base ~= base then
		return
	end
	manobra(nome, base)
end

-- Saiu do banco (o QuadricicloCliente chama): o combo que estava rolando FECHA e vale.
function Estilo.desligar()
	desligar()
end

-- =====================================================================
-- O DESENHO (a cada frame, só enquanto tem algo na tela)
-- =====================================================================
local conexaoDesenho: RBXScriptConnection? = nil
local brilho = 0 -- 0 = bordas apagadas · 1 = no máximo

local function pintar(rotulo: TextLabel, alfa: number)
	rotulo.TextTransparency = 1 - alfa
	rotulo.TextStrokeTransparency = 1 - alfa * 0.75
end

-- Troca o texto só quando ele MUDA (montar texto com cores e tamanhos dá trabalho para a tela).
local function escrever(rotulo: TextLabel, texto: string)
	if rotulo.Text ~= texto then
		rotulo.Text = texto
	end
end

local function desenhar(dt: number)
	local atual = pegarHud()
	if atual == nil then
		return
	end
	local agora = os.clock()
	visivelCombo += ((if comboAtivo then 1 else 0) - visivelCombo) * math.min(dt * 14, 1)
	local visivel = visivelCombo
	local alfaFim = math.clamp((fimAte - agora) / 0.4, 0, 1) -- (o "+12.400" some devagar nos últimos 0,4 s)
	local alvoDoBrilho = if comboAtivo then math.clamp((multiplicador - BRILHO_A_PARTIR_DE + 1) / (MULTIPLICADOR_MAXIMO - BRILHO_A_PARTIR_DE + 1), 0, 1) else 0
	brilho += (alvoDoBrilho - brilho) * math.min(dt * 3, 1)

	-- NADA NA TELA: para de desenhar até o próximo combo.
	if not comboAtivo and alfaFim <= 0 and brilho < 0.01 then
		atual.tela.Enabled = false
		atual.fim.Visible = false
		visivelCombo = 0
		for _, borda in atual.bordas do
			borda.BackgroundTransparency = 1
		end
		limparLinhas()
		local conexao = conexaoDesenho
		if conexao then
			conexao:Disconnect()
		end
		conexaoDesenho = nil
		return
	end
	atual.tela.Enabled = true
	if alfaFim <= 0 and atual.fim.Visible then
		atual.fim.Visible = false
	end

	-- 1) "COMBO x4" e os pontos rolando
	local cor = corDoMultiplicador(multiplicador)
	escrever(atual.multiplicador, `<font size="20">COMBO </font>x{multiplicador}`)
	atual.multiplicador.TextColor3 = cor
	pintar(atual.multiplicador, visivel)
	local alvo = totalAgora()
	mostrado += (alvo - mostrado) * math.min(dt * 10, 1)
	if math.abs(alvo - mostrado) < 1 then
		mostrado = alvo
	end
	escrever(atual.total, formatar(mostrado))
	pintar(atual.total, visivel)

	-- 2) a barrinha da janela (vermelha e piscando quando está acabando: corre!)
	local resta = math.clamp((janelaAte - agora) / JANELA, 0, 1)
	atual.barra.Size = UDim2.fromScale(resta, 1)
	local acabando = resta < 0.35
	atual.barra.BackgroundColor3 = if acabando then COR_PERDEU else cor
	local piscar = if acabando then 0.5 + 0.5 * math.sin(agora * 25) else 1
	atual.barra.BackgroundTransparency = 1 - visivel * piscar
	atual.fundoBarra.BackgroundTransparency = 1 - visivel * 0.55

	-- 3) as atividades acontecendo agora
	for i, atividade in ORDEM_DAS_ATIVIDADES do
		local rotulo = atividade.rotulo
		if atividade.ativa and rotulo == nil then
			rotulo = novoTexto(atual.vivas, i, 22, 18, Color3.fromRGB(255, 225, 120), Enum.Font.GothamBlack)
			atividade.rotulo = rotulo
		end
		if rotulo then
			rotulo.Visible = atividade.ativa
			if atividade.ativa then
				escrever(rotulo, `{atividade.nome}  +{formatar(atividade.valor)}`)
				pintar(rotulo, visivel)
			end
		end
	end

	-- 4) as últimas manobras (cada uma aparece rápido e some devagar)
	for i = #linhas, 1, -1 do
		local linha = linhas[i]
		local idade = agora - linha.nasceu
		if idade > DURACAO_DA_LINHA then
			linha.rotulo:Destroy()
			table.remove(linhas, i)
		else
			local alfa = math.min(idade / 0.1, 1, (DURACAO_DA_LINHA - idade) / 0.5)
			pintar(linha.rotulo, alfa * visivel)
		end
	end

	-- 5) o recorde (ou "NOVO RECORDE!" piscando)
	local recorde = recordeAtual()
	if bateuRecorde then
		escrever(atual.recorde, "NOVO RECORDE!")
		atual.recorde.TextColor3 = COR_RECORDE
		pintar(atual.recorde, visivel * (0.6 + 0.4 * math.sin(agora * 10)))
	else
		escrever(atual.recorde, if recorde > 0 then `RECORDE {formatar(recorde)}` else "")
		atual.recorde.TextColor3 = COR_FRACA
		pintar(atual.recorde, visivel * 0.8)
	end

	-- 6) o fim ("+12.400 ÓTIMO!" ou "COMBO PERDIDO")
	pintar(atual.resultado, alfaFim)
	pintar(atual.nivel, alfaFim)
	pintar(atual.dinheiro, alfaFim)

	-- 7) as BORDAS brilhando com a cor do multiplicador (a partir do x4: "pegando fogo")
	local pulso = 0.75 + 0.25 * math.sin(agora * 6)
	for _, borda in atual.bordas do
		borda.BackgroundColor3 = cor
		borda.BackgroundTransparency = 1 - brilho * 0.4 * pulso
	end
end

ligarDesenho = function()
	if conexaoDesenho == nil then
		conexaoDesenho = RunService.PreRender:Connect(desenhar)
	end
end

-- =====================================================================
-- AS RESPOSTAS DO SERVIDOR (script EstiloServidor)
-- =====================================================================
-- Os avisos dos combos ENORMES dos outros jogadores (no meio de cima da tela).
local telaDeNoticias: ScreenGui? = nil
local function mostrarNoticia(texto: string, cor: Color3)
	local tela = telaDeNoticias
	if tela == nil or tela.Parent == nil then
		local playerGui = jogadorLocal:FindFirstChildOfClass("PlayerGui")
		if playerGui == nil then
			return
		end
		local nova = Instance.new("ScreenGui")
		nova.Name = "NoticiasDeCombo"
		nova.ResetOnSpawn = false
		nova.DisplayOrder = 7
		nova.Parent = playerGui
		telaDeNoticias = nova
		tela = nova
	end
	if tela == nil then
		return
	end
	local velha = tela:FindFirstChild("Noticia")
	if velha then
		velha:Destroy()
	end
	local caixa = Instance.new("TextLabel")
	caixa.Name = "Noticia"
	caixa.AnchorPoint = Vector2.new(0.5, 0)
	caixa.Position = UDim2.new(0.5, 0, 0, 8)
	caixa.Size = UDim2.fromOffset(0, Tela.tamanho(30))
	caixa.AutomaticSize = Enum.AutomaticSize.X
	caixa.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
	caixa.BackgroundTransparency = 0.25
	caixa.Font = Enum.Font.GothamBlack
	caixa.TextSize = Tela.tamanho(16)
	caixa.TextColor3 = cor
	caixa.Text = texto
	local canto = Instance.new("UICorner")
	canto.CornerRadius = UDim.new(0, 10)
	canto.Parent = caixa
	local margem = Instance.new("UIPadding")
	margem.PaddingLeft = UDim.new(0, 14)
	margem.PaddingRight = UDim.new(0, 14)
	margem.Parent = caixa
	local escala = Instance.new("UIScale")
	escala.Scale = 0.5
	escala.Parent = caixa
	caixa.Parent = tela
	TweenService:Create(escala, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(4, function()
		if caixa.Parent == nil then
			return
		end
		local sumir = TweenInfo.new(0.5)
		TweenService:Create(caixa, sumir, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.delay(0.55, function()
			caixa:Destroy()
		end)
	end)
end

task.spawn(function()
	local remoto = ReplicatedStorage:WaitForChild("EstiloCombo", 60) -- (sem o EstiloServidor, desiste em silêncio)
	if not (remoto and remoto:IsA("RemoteEvent")) then
		return
	end
	remoto.OnClientEvent:Connect(function(acao: unknown, a: unknown, b: unknown, c: unknown)
		if acao == "Ganhou" and typeof(a) == "number" and typeof(b) == "number" then
			-- O SEU combo: o servidor pagou. Aparece embaixo do "+12.400" (se ele ainda estiver na tela).
			local atual = hud
			if atual and atual.fim.Visible and os.clock() < fimAte then
				local partes: { string } = {}
				if b > 0 then
					table.insert(partes, `+{formatar(b)} $`)
				end
				if c == true then
					table.insert(partes, `<font color="#FFD746">NOVO RECORDE!</font>`)
				end
				atual.dinheiro.Text = table.concat(partes, "  ·  ")
				fimAte = math.max(fimAte, os.clock() + 1.2)
			end
			if c == true then
				recordeLocal = math.max(recordeLocal, a)
			end
		elseif acao == "Noticia" and typeof(a) == "string" and typeof(b) == "number" then
			-- O combo ENORME de outro jogador.
			local nivel = nivelDe(b)
			local nome = if nivel then nivel.nome else "GRANDE"
			local recorde = if c == true then "  NOVO RECORDE!" else ""
			mostrarNoticia(`{a}: combo {nome} de {formatar(b)}!{recorde}`, if nivel then nivel.cor else COR_PONTOS)
		end
	end)
end)

return Estilo
```
**Por quê:** é o coração. Detecta as manobras sozinho (pela física e pelos atributos que o servidor já publica), desenha o combo no canto de cima à direita, enche o nitro e manda o combo fechado para o servidor.

### 3.2 — NOVO Script `EstiloServidor`
**Onde:** ServerScriptService › (botão direito) › Insert Object › **Script** (o normal, não o LocalScript). Renomeie para **`EstiloServidor`**.
**O quê:** apague o que vier dentro e cole tudo:

```lua
--!strict
--[[
	=====================================================================
	EstiloServidor  (Script normal)
	Local: ServerScriptService > EstiloServidor
	=====================================================================

	O lado do SERVIDOR do COMBO DE ESTILO (quem conta o combo e mostra na tela é o módulo
	Estilo, dentro do QuadricicloCliente):
	  - Quando um combo FECHA, o cliente avisa ("Combo", pontos). Aqui conferimos (nunca confie no
	    cliente!) e o jogador ganha DINHEIRO em leaderstats.Dinheiro (quem SALVA é o script Progresso).
	  - Guarda o RECORDE de combo de cada jogador (num DataStore só dele) e mostra na tabela do TAB
	    (coluna "Combo") e no atributo "RecordeCombo" do Player (o HUD do combo lê dali).
	  - Combo ENORME (ou um recorde grande) aparece na tela de TODO MUNDO do servidor.

	ANTI-TRAPAÇA: cada jogador tem um "cofrinho" de pontos que só enche enquanto ele está DIRIGINDO
	(PONTOS_POR_SEGUNDO por segundo, até CREDITO_MAXIMO). Um combo nunca vale mais do que o cofrinho.
	Assim, um trapaceiro que manda "fiz 1 milhão de pontos" ganha, no máximo, o mesmo que um jogador
	muito bom ganharia dirigindo esse tempo todo.

	No Studio, para SALVAR o recorde: Home > Game Settings > Security >
	"Enable Studio Access to API Services" (o mesmo do Progresso). Sem isso, tudo funciona, mas não salva.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- =====================================================================
-- AJUSTES
-- =====================================================================
local PONTOS_POR_DINHEIRO = 1000 -- cada 1000 pontos de combo = 1 de dinheiro (um checkpoint dá 10)
local DINHEIRO_MAXIMO_POR_COMBO = 150 -- nenhum combo sozinho dá mais que isso
local PONTOS_POR_SEGUNDO = 2500 -- o cofrinho enche isso por segundo, enquanto o jogador DIRIGE
local CREDITO_MAXIMO = 250000 -- o máximo que cabe no cofrinho
local CREDITO_INICIAL = 20000 -- o cofrinho já começa com isso (o 1º combo grande, logo ao entrar, não fica "cortado")
local ESPERA_ENTRE_COMBOS = 0.5 -- (s) dois combos não fecham mais rápido que isso
local AVISAR_TODOS_A_PARTIR_DE = 35000 -- combo deste tamanho (INSANO!) aparece para todo mundo...
local AVISAR_RECORDE_A_PARTIR_DE = 15000 -- ...e um RECORDE pessoal a partir deste tamanho também
local SALVAR_A_CADA = 60 -- (s) salva os recordes novos (e quando o jogador sai)
local NOME_DO_COFRE = "RecordeDeCombo_v1" -- nome do DataStore (trocar = todo mundo recomeça do zero)
local TAG_QUADRICICLO = "Quadriciclo" -- (o QuadricicloServidor coloca esta tag nos veículos prontos)

-- O "fio" entre o módulo Estilo (cliente) e este script.
local remoto: RemoteEvent
local existente = ReplicatedStorage:FindFirstChild("EstiloCombo")
if existente and existente:IsA("RemoteEvent") then
	remoto = existente
else
	remoto = Instance.new("RemoteEvent")
	remoto.Name = "EstiloCombo"
	remoto.Parent = ReplicatedStorage
end

-- =====================================================================
-- CADA JOGADOR
-- =====================================================================
type Estado = {
	credito: number, -- o cofrinho de pontos
	ultimoCombo: number, -- (os.clock) quando o último combo foi aceito
	recorde: number, -- o maior combo dele
	salvar: boolean, -- o recorde mudou e ainda não foi salvo
	pendente: number, -- dinheiro ganho antes do leaderstats existir (é entregue assim que ele aparecer)
	coluna: IntValue?, -- a coluna "Combo" da tabela do TAB
}
local estados: { [Player]: Estado } = {}
local cofre = DataStoreService:GetDataStore(NOME_DO_COFRE)

local function chave(jogador: Player): string
	return "J_" .. jogador.UserId
end

-- Está dirigindo um veículo do jogo agora? (sentado no Banco de um Model com a tag "Quadriciclo")
local function dirigindo(jogador: Player): boolean
	local personagem = jogador.Character
	local humanoide = if personagem then personagem:FindFirstChildOfClass("Humanoid") else nil
	local banco = if humanoide then humanoide.SeatPart else nil
	if banco == nil or not banco:IsA("VehicleSeat") then
		return false
	end
	local modelo = banco.Parent
	return modelo ~= nil and CollectionService:HasTag(modelo, TAG_QUADRICICLO)
end

-- Põe dinheiro no leaderstats (o Progresso salva). Ainda não existe? Guarda para entregar depois.
local function entregar(jogador: Player, estado: Estado, quanto: number)
	local pasta = jogador:FindFirstChild("leaderstats")
	local dinheiro = if pasta then pasta:FindFirstChild("Dinheiro") else nil
	if dinheiro and dinheiro:IsA("IntValue") then
		dinheiro.Value += quanto + estado.pendente
		estado.pendente = 0
	else
		estado.pendente += quanto
	end
end

-- =====================================================================
-- CARREGAR E SALVAR O RECORDE
-- =====================================================================
local function carregar(jogador: Player): number
	for tentativa = 1, 3 do
		local ok, salvo = pcall(function()
			return cofre:GetAsync(chave(jogador))
		end)
		if ok then
			return if typeof(salvo) == "number" then salvo else 0 -- (jogador novo = 0)
		end
		warn(`[EstiloServidor] Não deu para carregar o recorde de {jogador.Name} (tentativa {tentativa}): {salvo}`)
		if tentativa < 3 then
			task.wait(2)
		end
	end
	return 0
end

-- Salva só se o recorde mudou. O UpdateAsync fica com o MAIOR (o salvo ou o novo): assim um recorde
-- nunca diminui, nem se o carregar tiver falhado.
local function salvar(jogador: Player)
	local estado = estados[jogador]
	if estado == nil or not estado.salvar then
		return
	end
	estado.salvar = false
	local recorde = estado.recorde
	local ok, erro = pcall(function()
		cofre:UpdateAsync(chave(jogador), function(antigo: unknown): number
			return math.max(if typeof(antigo) == "number" then antigo else 0, recorde)
		end)
	end)
	if not ok then
		estado.salvar = true -- (tenta de novo no próximo salvamento)
		warn(`[EstiloServidor] Não deu para salvar o recorde de {jogador.Name}: {erro}`)
	end
end

-- =====================================================================
-- ENTROU / SAIU
-- =====================================================================
local function aoEntrar(jogador: Player)
	local estado: Estado = { credito = CREDITO_INICIAL, ultimoCombo = 0, recorde = 0, salvar = false, pendente = 0, coluna = nil }
	estados[jogador] = estado
	local salvo = carregar(jogador)
	if estados[jogador] ~= estado then
		return -- (saiu enquanto carregava)
	end
	estado.recorde = math.max(estado.recorde, salvo) -- (pode ter feito um combo enquanto carregava)
	jogador:SetAttribute("RecordeCombo", estado.recorde)
	-- A coluna "Combo" na tabela do TAB (o leaderstats é criado pelo Progresso, quando ele termina de carregar).
	local pasta = jogador:WaitForChild("leaderstats", 60)
	if pasta and estados[jogador] == estado then
		local coluna = Instance.new("IntValue")
		coluna.Name = "Combo"
		coluna.Value = estado.recorde
		coluna.Parent = pasta
		estado.coluna = coluna
	end
end

Players.PlayerAdded:Connect(aoEntrar)
for _, jogador in Players:GetPlayers() do
	task.spawn(aoEntrar, jogador) -- (quem entrou antes deste script rodar)
end

Players.PlayerRemoving:Connect(function(jogador: Player)
	salvar(jogador)
	estados[jogador] = nil
end)

-- =====================================================================
-- UM COMBO FECHOU (o módulo Estilo do cliente avisa)
-- =====================================================================
remoto.OnServerEvent:Connect(function(jogador: Player, acao: unknown, valor: unknown)
	local estado = estados[jogador]
	-- Confere tudo: um trapaceiro pode mandar qualquer coisa (até "não é um número", que é diferente de si mesmo).
	if estado == nil or acao ~= "Combo" or typeof(valor) ~= "number" or valor ~= valor then
		return
	end
	local agora = os.clock()
	if agora - estado.ultimoCombo < ESPERA_ENTRE_COMBOS then
		return
	end
	estado.ultimoCombo = agora
	-- Nunca mais do que o cofrinho tem.
	local pontos = math.floor(math.clamp(valor, 0, estado.credito))
	if pontos <= 0 then
		return
	end
	estado.credito -= pontos
	-- DINHEIRO
	local dinheiro = math.min(math.floor(pontos / PONTOS_POR_DINHEIRO), DINHEIRO_MAXIMO_POR_COMBO)
	if dinheiro > 0 then
		entregar(jogador, estado, dinheiro)
	end
	-- RECORDE
	local ehRecorde = pontos > estado.recorde
	if ehRecorde then
		estado.recorde = pontos
		estado.salvar = true
		jogador:SetAttribute("RecordeCombo", pontos)
		local coluna = estado.coluna
		if coluna then
			coluna.Value = pontos
		end
	end
	remoto:FireClient(jogador, "Ganhou", pontos, dinheiro, ehRecorde)
	-- Combo ENORME (ou recorde grande): todo mundo do servidor fica sabendo.
	if pontos >= AVISAR_TODOS_A_PARTIR_DE or (ehRecorde and pontos >= AVISAR_RECORDE_A_PARTIR_DE) then
		for _, outro in Players:GetPlayers() do
			if outro ~= jogador then
				remoto:FireClient(outro, "Noticia", jogador.DisplayName, pontos, ehRecorde)
			end
		end
	end
end)

-- =====================================================================
-- A CADA MEIO SEGUNDO: o cofrinho de quem dirige enche (e o dinheiro guardado é entregue)
-- =====================================================================
task.spawn(function()
	while true do
		task.wait(0.5)
		for jogador, estado in estados do
			if dirigindo(jogador) then
				estado.credito = math.min(estado.credito + PONTOS_POR_SEGUNDO * 0.5, CREDITO_MAXIMO)
			end
			if estado.pendente > 0 then
				entregar(jogador, estado, 0)
			end
		end
	end
end)

-- =====================================================================
-- SALVAR: a cada minuto (quem bateu recorde) e quando o servidor fecha
-- =====================================================================
task.spawn(function()
	while true do
		task.wait(SALVAR_A_CADA)
		for jogador, estado in estados do
			if estado.salvar then
				task.spawn(salvar, jogador)
			end
		end
	end
end)

game:BindToClose(function()
	local faltam = 0
	for jogador in estados do
		faltam += 1
		task.spawn(function()
			salvar(jogador)
			faltam -= 1
		end)
	end
	local limite = os.clock() + 25 -- (o Roblox espera no máximo 30 s)
	while faltam > 0 and os.clock() < limite do
		task.wait(0.1)
	end
end)
```
**Por quê:** confere o combo (anti-trapaça), paga o dinheiro, salva o recorde, cria a coluna "Combo" no TAB e avisa todo mundo dos combos enormes.

### 3.3 — `QuadricicloCliente` (3 linhas novas)
**Script:** StarterPlayer › StarterPlayerScripts › **QuadricicloCliente** (o LocalScript).

**a)** Localize esta linha (perto do começo):
```lua
local Guidao = require(script:WaitForChild("Guidao")) -- (NOVO) o guidão/volante gira e o piloto segura nele
```
Adicione **logo abaixo** dela:
```lua
local Estilo = require(script:WaitForChild("Estilo")) -- (NOVO) o combo de estilo: pontos, multiplicador, nitro e dinheiro
```
*Por quê:* carrega o módulo novo.

**b)** Localize esta linha (no fim da função `atualizar`):
```lua
	procurarPancada(quad, dt) -- (NOVO) bateu muito rápido em outro quadriciclo? O Servidor manda o tranco nele
```
Adicione **logo abaixo** dela:
```lua
	Estilo.atualizar(quad, dt, pedal, extraDoBoost > 0) -- (NOVO) o combo de estilo: derrapada, ar, voo, mortal...
```
*Por quê:* o combo é conferido a cada frame, depois de todo o resto (assim ele já vê o boost pad, o gancho e o nitro deste frame).

**c)** Localize esta linha (na função `pararDeDirigir`):
```lua
	PoeiraDoChao.desligar()
```
Adicione **logo abaixo** dela:
```lua
	Estilo.desligar() -- (NOVO) o combo que estava rolando fecha (e vale)
```
*Por quê:* saiu do banco no meio do combo? Ele fecha e vale (em vez de sumir).

### 3.4 — `Gancho` do cliente (2 linhas novas)
**Script:** StarterPlayer › StarterPlayerScripts › QuadricicloCliente › **Gancho** (o ModuleScript do cliente, **não** o do ServerScriptService).

**a)** Localize esta linha (perto do começo):
```lua
local Tela = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Tela")) -- (NOVO) HUD menor no celular
```
Adicione **logo abaixo** dela:
```lua
local Estilo = require(script.Parent:WaitForChild("Estilo")) -- (NOVO) o PERFEITO! vale pontos no combo de estilo
```

**b)** Use Ctrl+F para achar `local function comemorarPerfeito`. Você vai ver:
```lua
local function comemorarPerfeito(quad: Quadriciclo)
	-- 1) O TRANCO na tela (0.3 já é bem forte).
```
Adicione esta linha **entre** as duas (logo abaixo da linha do `function`):
```lua
	Estilo.acao("PERFEITO!", 1000) -- (NOVO) vale 1000 pontos no combo e sobe o multiplicador
```
*Por quê:* o PERFEITO! é o melhor momento do voo e agora ele também vale ponto e multiplicador. (O módulo Estilo não usa o Gancho, então um não "trava" esperando o outro.)

### 3.5 — `ConfiguracaoPadrao` (1 linha trocada)
**Script:** ReplicatedStorage › Compartilhado › **ConfiguracaoPadrao**.
Localize esta linha (na parte 7, NITRO):
```lua
	NitroRechargeTime = 6, -- Segundos para o tanque encher de novo, do vazio até cheio.
```
Troque **essa linha** por esta:
```lua
	NitroRechargeTime = 10, -- (MUDOU: era 6) Segundos para o tanque encher SOZINHO, do vazio até cheio. As manobras do combo (módulo Estilo) enchem bem mais rápido.
```
*Por quê:* com o nitro enchendo rápido sozinho, ninguém precisa fazer manobra. Agora quem joga bem tem nitro quase sem parar.

### 3.6 — (OPCIONAL) `Pista`: o 360 no loop vale ponto
**Script:** StarterPlayer › StarterPlayerScripts › QuadricicloCliente › **Pista**. Só faz diferença no caminhão monstro, nos loops e tubos.

**a)** Localize (perto do começo):
```lua
local CameraModulo = require(script.Parent:WaitForChild("Camera")) -- (o tranco na tela: Camera.tremer)
```
Adicione **logo abaixo**:
```lua
local Estilo = require(script.Parent:WaitForChild("Estilo")) -- (NOVO) o 360 no loop vale pontos no combo de estilo
```
**b)** Use Ctrl+F para achar `anunciar(nomes[atual.voltas]`. Localize a linha:
```lua
			anunciar(nomes[atual.voltas] or `360 x{atual.voltas}!`, Color3.fromRGB(255, 205, 60))
```
Adicione **logo abaixo** (mesmo recuo):
```lua
			Estilo.acao("LOOP 360!", 1500 * atual.voltas) -- (NOVO) cada volta seguida vale mais
```

---

## ETAPA 4 — Configuração (ajuste fino)

Os números ficam no topo dos dois scripts novos, na parte **AJUSTES**. Mude **um por vez** e teste.

**No módulo `Estilo`:**
| Ajuste | Padrão | Mexa se... |
|---|---|---|
| `JANELA` | 2.5 | O combo fecha rápido demais: **3.5**. Quer mais desafio: **1.8**. |
| `NITRO_POR_PONTO` | 1/3000 | O nitro enche demais: **1/5000**. Quer nitro "infinito" para quem joga bem: **1/1500**. |
| `MULTIPLICADOR_MAXIMO` | 10 | Combos gigantes demais: **6**. |
| `PONTOS_VOO` | 500 | Quer que o voo seja **o** jeito de fazer combo grande: **800**. |
| `BATIDA_PERDA` | 40 | Perdendo combo em batidinha à toa: **55**. |
| `CAPOTOU_DEPOIS_DE` | 0.35 | Perdendo o combo ao raspar de lado numa rampa: **0.6**. |
| `VELOCIDADE_MINIMA` | 65 | Se você mudar o `NitroSpeedBonus`, deixe isto um pouco **abaixo** de 40 + bônus. |
| `BRILHO_A_PARTIR_DE` | 4 | As bordas brilhando incomodam: **8** (só no fim). |
| `SOM_MANOBRA` / `SOM_PERDEU` | sons do Roblox | Troque por sons do Creator Store (um "plim" de moeda fica ótimo). |
| `POSICAO` | canto de cima, à direita | Se bater em algum HUD seu. |

**No `EstiloServidor`:**
| Ajuste | Padrão | O que faz |
|---|---|---|
| `PONTOS_POR_DINHEIRO` | 1000 | 34.524 pontos = 34 $. Para dar menos dinheiro: **2000**. |
| `PONTOS_POR_SEGUNDO` | 2500 | O teto do anti-trapaça. Se jogadores muito bons tiverem o combo "cortado", aumente. |
| `AVISAR_TODOS_A_PARTIR_DE` | 35000 | Avisa todo mundo a partir do INSANO!. |

**Na `ConfiguracaoPadrao`:** `NitroRechargeTime` (10). Se o nitro ficar raro demais para quem está aprendendo: **8**.

---

## ETAPA 5 — Testes

Antes: Home › Game Settings › Security › **Enable Studio Access to API Services** ligado (para o recorde salvar, igual ao Progresso).

1. **Derrapada**: dirija a 30+ e puxe o freio de mão virando. No canto de cima, à direita, aparecem "COMBO x1", os pontos subindo e "DERRAPADA +...". Solte e espere: a barrinha esvazia (fica vermelha no fim) e aparece "+NNN" com um "plim-plim".
2. **Nitro ganho**: gaste o nitro todo, faça 2 ou 3 derrapadas e veja a barra roxa do nitro encher bem mais rápido que sozinha.
3. **Voo**: pegue um ponto de voo ("VOO!"), solte com o PERFEITO! e pegue o próximo sem tocar no chão ("VOO x2!"). O multiplicador sobe a cada coisa e as bordas da tela começam a brilhar a partir do x4.
4. **Perder**: com um combo rolando, bata de frente numa parede rápido. Deve aparecer "BATEU! / COMBO PERDIDO" em vermelho, balançando, e a tela treme. Capotar parado faz o mesmo ("CAPOTOU!").
5. **Dinheiro e recorde**: feche um combo de 1.000 ou mais. Embaixo do "+..." aparece "+1 $" e, no primeiro, "NOVO RECORDE!". Aperte TAB: a coluna **Combo** mostra o recorde e o Dinheiro subiu. Saia, entre de novo: o recorde continua lá.
6. **Recorde no meio**: com recorde de 1.000 ou mais, faça um combo maior. "NOVO RECORDE!" aparece na hora em que você passa dele.
7. **Outro jogador**: Test › Clients and Servers › 2 jogadores. Faça um combo de 35.000+ (corrente de 3 pontos de voo). O outro jogador vê o aviso no meio de cima da tela.
8. **Celular**: Test › Device (um celular). O combo fica menor e não fica embaixo dos botões. Rode o DiagnosticoDaTela e veja o Output.
9. **Sem erro no Output**: nada vermelho com "[Estilo]" ou "[EstiloServidor]".
   - O carro não anda e o Output diz *"Infinite yield possible on ... :WaitForChild("Estilo")"*? O ModuleScript está com o nome errado ou no lugar errado. Tem que ser **Estilo** (E maiúsculo, sem acento), dentro do QuadricicloCliente.
   - Aparece *"[Estilo] Não achei o RemoteEvent EstiloCombo"*? Falta o Script **EstiloServidor** no ServerScriptService. Sem ele o combo aparece, mas não dá dinheiro nem salva o recorde.

Testei os 2 scripts novos e as 8 mudanças numa cópia exata dos seus 36 scripts: o verificador `--!strict` do Luau não acusou nenhum erro nem aviso. O que **não** dá para testar fora do Studio é o "sentir": o tamanho certo da JANELA e quanto cada manobra vale. Por isso os números ficam todos nos AJUSTES.
