--[[
	ExemploUso  —  Script (server) ao lado do ModuleScript ScenarioCasas.

	ServerScriptService
	  ├ ScenarioCasas   (ModuleScript)
	  └ ExemploUso      (Script)  <- este arquivo

	O cenário é estático: monta uma vez quando o servidor sobe e fica lá.
	Não há loop, não há RemoteEvent, não custa nada em runtime.
]]

local ScenarioCasas = require(script.Parent:WaitForChild("ScenarioCasas"))

----------------------------------------------------------------------
-- 1. De onde o jogador olha?
--    O cenário inteiro é construído em volta deste ponto. Pelo print,
--    é mais ou menos onde fica o pórtico de largada, olhando pro fundo
--    do vale (na direção do letreiro PLAY).
--
--    Jeito prático: coloque uma Part no lugar exato onde a câmera do
--    jogador fica, chame ela de "PontoDeVista", marque Anchored e
--    Transparency = 1. O script usa ela se existir.
----------------------------------------------------------------------
local FOCO = Vector3.new(0, 25, 0)
local DIRECAO = Vector3.new(0, 0, -1)   -- pro fundo do vale

local marcador = workspace:FindFirstChild("PontoDeVista")
if marcador and marcador:IsA("BasePart") then
	FOCO = marcador.Position
	DIRECAO = marcador.CFrame.LookVector    -- a Part aponta pro fundo
end

----------------------------------------------------------------------
-- 2. A névoa do jogo e a cor das casas têm que ser a mesma coisa.
--    É isso que faz o fundo "afundar" em vez de parecer adesivo colado.
----------------------------------------------------------------------
local COR_ATMOSFERA = Color3.fromRGB(162, 196, 214)   -- azul-esverdeado do vale

ScenarioCasas.AplicarAtmosfera({
	Cor = Color3.fromRGB(199, 220, 232),
	Decaimento = Color3.fromRGB(106, 143, 166),
	Densidade = 0.33,
	Bruma = 1.9,
})

----------------------------------------------------------------------
-- 3. Monta.
----------------------------------------------------------------------
ScenarioCasas.Construir({
	Nome = "CenarioVila",
	Foco = FOCO,
	Direcao = DIRECAO,
	Semente = 20261014,          -- troque o número até gostar do desenho
	CorAtmosfera = COR_ATMOSFERA,

	Camadas = {
		-- Perto: casas de verdade, nas ombreiras do vale. Essas o jogador
		-- chega perto, então têm janela, porta, chaminé e colisão.
		{
			Nome = "Vila", Tipo = "VOLUME",
			Quantidade = 9,
			Distancia = 240, Espalhamento = 150, Abertura = 120,
			AlturaBase = 4, VariacaoAltura = 6,
			Escala = 1.0, Profundidade = 0.55,
			Colidir = true, Detalhe = true, Arvores = 7,
			Arquetipos = { "Chale", "Chale", "Sobrado", "Celeiro", "Capela" },
		},

		-- Meio: trepadas na encosta. Sem detalhe, mais rasas, já puxando
		-- pro azul. Daqui pra trás ninguém chega perto o bastante pra ver.
		{
			Nome = "Encosta", Tipo = "CAIXA",
			Quantidade = 14,
			Distancia = 580, Espalhamento = 260, Abertura = 150,
			AlturaBase = 55, VariacaoAltura = 45,
			Escala = 0.80, Profundidade = 0.38,
			Colidir = false, Detalhe = false, Arvores = 12,
		},

		-- Longe: recorte puro de backlot. 3 peças finas viradas pro foco.
		-- A escala 0.55 é perspectiva forçada de propósito: o vale passa
		-- a parecer bem mais fundo do que é.
		{
			Nome = "Horizonte", Tipo = "PLACA",
			Quantidade = 22,
			Distancia = 1150, Espalhamento = 420, Abertura = 175,
			AlturaBase = 150, VariacaoAltura = 90,
			Escala = 0.55, Profundidade = 0.035,
			Colidir = false, Detalhe = true, Arvores = 0,
			Encaixar = false,          -- flutua no alto da encosta, de propósito
			GiroAleatorio = 6,         -- placa quase não pode girar
		},
	},
})

----------------------------------------------------------------------
-- 4. Precisa de uma casa solta em algum canto específico? Assim:
--
--    ScenarioCasas.CasaAvulsa(
--        CFrame.lookAt(Vector3.new(120, 18, -80), FOCO),
--        { Arquetipo = "Capela", Escala = 1.2, Colidir = true, Nevoa = 0.2 }
--    )
----------------------------------------------------------------------
