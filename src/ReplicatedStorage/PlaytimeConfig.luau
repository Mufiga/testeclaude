--!optimize 2
--[[
	PlaytimeConfig
	--------------
	ModuleScript -> ReplicatedStorage  (nome exato: PlaytimeConfig)

	Este e o UNICO arquivo que voce precisa mexer.
	Tudo aqui e lido pelo servidor e pelo cliente.
]]

local Config = {}

-- =========================================================
--  1. ONDE A PLACA FICA
-- =========================================================

-- true  = o script constroi a placa de madeira sozinho (posts + telhadinho).
-- false = voce faz a sua propria placa e so marca a parte da frente com a
--         Tag abaixo (Studio: aba Modelo > Avancado > Editor de Tags).
Config.AutoBuildBoard = true

-- Tag usada para achar a placa. Se voce usar a sua propria parte,
-- marque-a com essa tag e deixe AutoBuildBoard = false.
Config.BoardTag = "PlaytimeBoard"

-- Posicao do CENTRO do painel.
--   nil  = o script coloca a placa sozinho, perto do seu SpawnLocation.
--   Para escolher: clique numa Part no Studio, olhe "Position" nas
--   Propriedades e copie os tres numeros aqui.
-- Exemplo: Config.BoardPosition = Vector3.new(-24, 14, 87)
Config.BoardPosition = nil

-- Quantos graus a placa gira (0, 90, 180, 270...). A placa olha pra frente.
Config.BoardRotationY = 0

-- Tamanho do painel em studs (largura x altura).
Config.BoardWidth = 12
Config.BoardHeight = 9

-- Pernas de madeira embaixo da placa.
Config.ShowPosts = true
Config.PostHeight = 6

-- A placa bloqueia o jogador? (false = atravessa)
Config.BoardCollide = true
Config.BoardCastShadow = true

-- =========================================================
--  2. CONTEUDO DA PLACA
-- =========================================================

Config.Title = "TEMPO DE JOGO"
Config.Subtitle = "Top %d jogadores"      -- %d vira o numero de linhas
Config.YourTimeLabel = "SEU TEMPO"
Config.EmptyText = "---"

-- Quantas linhas o ranking mostra (1 a 25 fica bonito).
Config.TopCount = 8

-- Mostrar a fotinha do rosto de cada jogador.
Config.ShowAvatars = true

-- Mostrar a barra verde "SEU TEMPO" no rodape.
Config.ShowYourTime = true

-- Mostra o tempo tambem na lista de jogadores (canto superior direito).
-- Coloque false se voce ja tem outro sistema de leaderstats.
Config.Leaderstats = true
Config.LeaderstatsName = "Tempo"

-- =========================================================
--  3. PERFORMANCE  (os padroes ja sao leves, mexa so se precisar)
-- =========================================================

-- De quanto em quanto tempo o ranking global e lido/atualizado (segundos).
Config.RefreshInterval = 60

-- De quanto em quanto tempo o tempo de cada jogador e salvo (segundos).
Config.AutosaveInterval = 120

-- Pausa entre o save de um jogador e o do proximo (espalha as chamadas).
Config.SaveSpacing = 1

-- Distancia (studs) em que a tela da placa para de ser desenhada.
-- Esse e o ajuste que mais economiza FPS. 0 = sempre desenhar (nao recomendo).
Config.MaxRenderDistance = 90

-- Resolucao da tela da placa. Menor = mais leve, maior = mais nitido.
Config.PixelsPerStud = 42

-- 0 = a placa tem brilho proprio e sempre da pra ler.
-- 0.3 ~ 0.5 = a placa escurece junto com a iluminacao do mapa.
Config.LightInfluence = 0

-- =========================================================
--  4. SALVAMENTO
-- =========================================================

-- Mudar esse nome ZERA o ranking (util pra testar e depois publicar).
Config.DataStoreName = "PlaytimeV1"
Config.KeyPrefix = "p_"

-- =========================================================
--  5. CORES E FONTES  (combinando com cenario de floresta/pedra)
-- =========================================================

Config.Palette = {
	Panel    = Color3.fromRGB(243, 231, 203),  -- pergaminho claro (fundo)
	PanelAlt = Color3.fromRGB(230, 214, 178),  -- faixa das linhas pares
	WoodDark = Color3.fromRGB(74, 48, 33),     -- moldura / topo
	WoodMid  = Color3.fromRGB(120, 80, 48),    -- pernas / telhado
	Ink      = Color3.fromRGB(58, 40, 28),     -- texto principal
	InkSoft  = Color3.fromRGB(141, 117, 92),   -- texto apagado
	Leaf     = Color3.fromRGB(94, 166, 62),    -- verde da grama
	LeafDark = Color3.fromRGB(56, 112, 42),
	Gold     = Color3.fromRGB(233, 180, 61),   -- 1 lugar
	Silver   = Color3.fromRGB(186, 194, 203),  -- 2 lugar
	Bronze   = Color3.fromRGB(190, 124, 72),   -- 3 lugar
	Rank     = Color3.fromRGB(150, 128, 104),  -- 4 lugar em diante
	YouTint  = Color3.fromRGB(205, 232, 186),  -- fundo da SUA linha
}

Config.TitleFont = Enum.Font.FredokaOne
Config.NameFont = Enum.Font.GothamBold
Config.TimeFont = Enum.Font.FredokaOne

-- =========================================================
--  6. FORMATO DO TEMPO  (nao precisa mexer)
-- =========================================================

-- "2h 15m" / "3d 4h" / "45m"  -> usado no ranking
function Config.FormatShort(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	if d > 0 then
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	return string.format("%dm", m)
end

-- "02h 15m 09s" -> usado no "SEU TEMPO", pra ver o relogio andando
function Config.FormatLong(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if d > 0 then
		return string.format("%dd %02dh %02dm", d, h, m)
	elseif h > 0 then
		return string.format("%02dh %02dm %02ds", h, m, s)
	end
	return string.format("%02dm %02ds", m, s)
end

return Config
