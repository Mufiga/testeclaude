--[[
	ExemploUso  —  Script (server) ao lado do ModuleScript ScenarioCasas.

	ServerScriptService
	  ├ ScenarioCasas   (ModuleScript)
	  └ MontarCenario   (Script)  <- este arquivo

	ANTES DE RODAR: marque o caminho offroad. Na Command Bar do Studio,
	voe a câmera seguindo a trilha e vá repetindo (seta pra cima + Enter):

	    require(game.ServerScriptService.ScenarioCasas).MarcarPonto()

	Cada Enter larga uma bolinha laranja onde a câmera está olhando, na
	pasta workspace.CaminhoPista. Uns 6 a 15 pontos já dão conta de uma
	trilha inteira — a curva passa em cima deles, então não precisa de
	muitos. Depois é só dar Play.

	O cenário é estático: monta uma vez quando o servidor sobe e fica lá.
	Sem loop, sem RemoteEvent, custo zero em runtime.
]]

local ScenarioCasas = require(script.Parent:WaitForChild("ScenarioCasas"))

local CAMINHO = workspace:FindFirstChild("CaminhoPista")
if not CAMINHO then
	warn("[MontarCenario] Marque a trilha primeiro com ScenarioCasas.MarcarPonto() na Command Bar.")
	return
end

----------------------------------------------------------------------
-- A névoa do jogo e a cor das casas têm que ser a mesma coisa. É isso
-- que faz o fundo afundar em vez de parecer adesivo colado no barranco.
----------------------------------------------------------------------
local COR_ATMOSFERA = Color3.fromRGB(162, 196, 214)   -- azul-esverdeado do vale

ScenarioCasas.AplicarAtmosfera({
	Cor = Color3.fromRGB(199, 220, 232),
	Decaimento = Color3.fromRGB(106, 143, 166),
	Densidade = 0.33,
	Bruma = 1.9,
})

----------------------------------------------------------------------
-- O cenário segue a trilha. Cada FAIXA é uma distância lateral dela.
----------------------------------------------------------------------
ScenarioCasas.AoLongoDaPista({
	Nome = "CenarioPista",
	Caminho = CAMINHO,
	Fechado = false,              -- true se a trilha for circuito fechado
	Semente = 20261014,           -- troque o número até gostar do desenho
	CorAtmosfera = COR_ATMOSFERA,

	Faixas = {
		-- BEIRA DA TRILHA. O jogador passa raspando, então aqui tem
		-- janela, porta, chaminé e colisão. Densidade 0.5 deixa metade
		-- dos lugares vazios de propósito: vila é em grupinho, não é
		-- muro de casa. O resto vira pinheiro e buraco.
		{
			Nome = "Beira", Tipo = "VOLUME",
			Recuo = 55, VariacaoRecuo = 26,     -- 42 a 68 studs do eixo
			Espacamento = 85,                   -- um lugar a cada 85 studs
			Densidade = 0.50, ChanceArvore = 0.35,
			Lados = "ambos",
			Escala = 1.0, Profundidade = 0.55,
			Colidir = true, Detalhe = true,
			DistanciaMinima = 30,
		},

		-- ENCOSTA. Trepadas no barranco, sem detalhe, mais rasas e já
		-- puxando pro azul. Daqui pra trás ninguém chega perto o bastante
		-- pra reparar que é casca.
		{
			Nome = "Encosta", Tipo = "CAIXA",
			Recuo = 190, VariacaoRecuo = 85,
			Espacamento = 70,
			Densidade = 0.60, ChanceArvore = 0.30,
			Altura = 12, VariacaoAltura = 25,   -- sobe um pouco o barranco
			Escala = 0.85, Profundidade = 0.38,
			Detalhe = false,
			DistanciaMinima = 24,
		},

		-- HORIZONTE. Recorte puro de backlot lá em cima, acima da borda
		-- do cânion. Escala 0.6 é perspectiva forçada de propósito: o
		-- vale passa a parecer bem mais fundo do que é.
		{
			Nome = "Horizonte", Tipo = "PLACA",
			Recuo = 650, VariacaoRecuo = 230,
			Espacamento = 95,
			Densidade = 0.80, ChanceArvore = 0,
			Altura = 130, VariacaoAltura = 70,
			Escala = 0.60, Profundidade = 0.035,
			Encaixar = false,                   -- flutua no alto, de propósito
			GiroAleatorio = 6,                  -- placa quase não pode girar
			DistanciaMinima = 14,
		},
	},
})

----------------------------------------------------------------------
-- DEPOIS, pra ajustar na mão (Command Bar, com o jogo parado):
--
--   local C = require(game.ServerScriptService.ScenarioCasas)
--   C.DefinirPista(workspace.CaminhoPista)   -- pra tudo virar pra trilha
--   C.Aqui()                                 -- casa onde a câmera olha
--   C.Aqui({ Arquetipo = "Capela", Escala = 1.3, Colidir = true })
--   C.NaSelecao({ Arquetipo = "Celeiro" })   -- uma em cada Part selecionada
--
-- Ou o jeito não-destrutivo: crie workspace.MarcadoresCasas, jogue umas
-- Parts invisíveis onde você quer cada construção, e rode
--
--   C.Marcadores(workspace.MarcadoresCasas)
--
-- Dá pra mexer os marcadores e rodar de novo quantas vezes quiser.
-- Atributos por marcador: Arquetipo, Tipo, Escala, Nevoa, Colidir,
-- Detalhe, Semente, Virar.
----------------------------------------------------------------------
