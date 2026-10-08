--!strict
--[[
	=====================================================================
	ConfiguracaoPadrao  (ModuleScript)
	Local: ReplicatedStorage > Compartilhado > ConfiguracaoPadrao
	=====================================================================

	TODOS os ajustes dos veículos ficam aqui, com o valor PADRÃO e a explicação de cada um.
	Cada veículo continua tendo a SUA Configuracao (Model > Scripts > Configuracao), mas ela
	agora só lista o que é DIFERENTE do padrão. Exemplo (a do Caminhão Monstro):

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Padrao = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("ConfiguracaoPadrao"))
		return Padrao.criar({
			MaxTorque = 55378,
			SpringStiffness = 7680,
		})

	  - Mudou um valor AQUI: muda em TODOS os veículos (menos nos que têm o próprio valor).
	  - Escreveu um nome errado na Configuracao de um veículo? O Output avisa (ex.: "MaxTorqe" não existe).
	  - Um ajuste novo que você criar: coloque aqui (com o valor padrão) e use no script. Pronto: todos
	    os veículos já têm ele, sem precisar copiar para cada Configuracao.

	Dica de iniciante: mude UM valor por vez, aperte Play e compare.
	Ligue o DEBUG_MODE para ver as peças invisíveis e os avisos no Output.

	Unidades usadas aqui:
	  - studs         = a "medida" do Roblox (um bloco padrão tem 4 studs de largura).
	  - studs/s       = velocidade (studs por segundo).
	  - studs/s²      = aceleração (quanto a velocidade muda a cada segundo).
	  - graus         = ângulo (0 a 360).
	Sons e imagens: "rbxassetid://NÚMERO". Vazio ("") = sem som (ou sem imagem).
]]

local RunService = game:GetService("RunService")

local PADRAO = {
	-- =================================================================
	-- 1) MODO DEPURAÇÃO (DEBUG)
	-- =================================================================
	-- true  = pinta as peças invisíveis de neon (meio transparentes),
	--         mostra molas, eixos e attachments e imprime avisos no Output.
	-- false = tudo normal. Use false quando o jogo estiver pronto.
	DEBUG_MODE = false,

	-- =================================================================
	-- 2) MOTOR E VELOCIDADE
	-- =================================================================
	MaxSpeed = 40, -- Velocidade máxima para frente (studs/s).
	ReverseSpeed = 30, -- Velocidade máxima de ré (studs/s).
	Acceleration = 35, -- Quanto a velocidade sobe por segundo (studs/s²).
	BrakeDeceleration = 45, -- Força do freio (studs/s²). Maior = para mais rápido.
	CoastDeceleration = 8, -- "Freio motor" quando você solta o acelerador (studs/s²).
	MaxTorque = 6500, -- Torque máximo de CADA motor de roda: é a "força" para subir rampas e empurrar coisas.
	DriveMode = "4x4", -- Tração: "4x4", "Traseira" ou "Dianteira".

	-- =================================================================
	-- 3) DIREÇÃO
	-- =================================================================
	SteerAngle = 30, -- Ângulo máximo das rodas da frente quando está devagar (graus).
	SteerAngleAtMaxSpeed = 15, -- Ângulo máximo na velocidade máxima (graus). Menor = mais estável em alta.
	SteerSpeed = 250, -- Rapidez com que o guidão gira (graus por segundo).
	SteerTorque = 15000, -- Força do servo da direção. Se as rodas não virarem direito, aumente.
	SteerAngleMinimo = 4, -- (graus) Acima da MaxSpeed, o ângulo da direção continua caindo, mas nunca fica menor que isso.

	-- =================================================================
	-- 4) SUSPENSÃO (SpringConstraint)
	-- =================================================================
	SpringStiffness = 3000, -- Dureza da mola. Maior = afunda menos e fica mais "dura".
	SpringDamping = 320, -- Amortecimento. Maior = quica menos (menor = mais "pula-pula").
	SpringFreeLength = 2, -- Comprimento da mola sem peso nenhum (studs).
	SpringMinLength = 0.45, -- Compressão máxima: a mola nunca fica menor que isso (é o "batente").
	SpringMaxLength = 3, -- Extensão máxima: o quanto a roda pode descer quando está no ar.

	-- Aparência das molas (espirais amarelas).
	SpringVisible = true,
	SpringColor = BrickColor.new("New Yeller"),
	SpringCoils = 8, -- Número de voltas da espiral.
	SpringRadius = 0.25, -- Raio da espiral (studs).
	SpringThickness = 0.06, -- Grossura do "arame" da mola (studs).

	-- =================================================================
	-- 5) PNEUS, MASSA E ADERÊNCIA (CustomPhysicalProperties)
	-- =================================================================
	-- Como o Roblox mistura o atrito de duas superfícies:
	--   atrito final = (atrito1 × peso1 + atrito2 × peso2) / (peso1 + peso2)
	-- O chão (terra, grama, areia) tem peso 1. Com TireFrictionWeight = 100,
	-- quem manda é o pneu: ele gruda igual em qualquer terreno.
	TireFriction = 1.3, -- Atrito do pneu (0 a 2). 1.3 = gruda na terra; abaixo de 0.6 parece sabão.
	TireFrictionWeight = 100, -- Peso do atrito do pneu na mistura (máximo 100).
	TireElasticity = 0, -- Quique do pneu. 0 = não quica (quem absorve o impacto é a mola).
	TireElasticityWeight = 100, -- Peso da elasticidade do pneu na mistura (máximo 100).
	TireDensity = 0.7, -- Densidade da Roda física (massa = densidade × volume).
	KnuckleDensity = 4, -- Densidade das Mangas (a peça entre a mola e a roda).
	ChassisDensity = 2, -- Densidade do Chassi. É ele que dá quase todo o peso do veículo.
	ChassisFriction = 0.3, -- Atrito do Chassi quando raspa no chão (baixo = escorrega em vez de travar).

	-- ESTABILIDADE EM ALTA VELOCIDADE: um peso invisível ("Lastro") soldado embaixo do Chassi.
	LastroFracao = 0.6, -- Quanto do peso do Chassi desce para o Lastro (0 = desliga · 0.6 = 60%). Maior = mais difícil de capotar.
	LastroAbaixoDoEixo = 0, -- (studs) O lastro fica na altura dos eixos das rodas. Para descer mais, coloque 0.5 ou 1.

	-- =================================================================
	-- 6) CONTROLES E EXTRAS
	-- =================================================================
	MasslessDriver = true, -- Personagem sem massa enquanto dirige (não muda o centro de massa).
	ShowSpeedometer = true, -- Mostra "Velocidade: N" na tela.
	MobileSteerButtons = false, -- Celular: true = cria botões ESQ/DIR. false = vira pelo analógico da tela.
	AnalogicoFixoNoCelular = true, -- Celular: true = dirigindo, o analógico fica PARADO no canto de baixo (o clássico).
	--                                false = o analógico que aparece onde você encosta o dedo (o padrão do Roblox).

	-- =================================================================
	-- 7) NITRO, FREIO DE MÃO, BUZINA E CÂMERA
	-- =================================================================
	NitroSpeedBonus = 8, -- Velocidade extra no nitro (studs/s).
	NitroAccelerationMultiplier = 1.6, -- Aceleração no nitro (1.6 = 60% mais forte que Acceleration).
	NitroTorqueMultiplier = 1.5, -- Força extra nas rodas no nitro: é o que ajuda a subir morro íngreme.
	NitroFOVBonus = 8, -- Graus que a câmera "abre" no nitro (sensação de velocidade). 0 = desliga.
	NitroDuration = 2.5, -- Segundos de nitro com o tanque cheio (a barra roxa do HUD).
	NitroRechargeTime = 6, -- Segundos para o tanque encher de novo, do vazio até cheio.
	NitroPancada = 14, -- (studs/s) Ao LIGAR o nitro, o Chassi afunda nas molas este tanto...
	NitroEmpinar = 1.5, -- (rad/s) ...e a frente sobe (a traseira "senta"). 0 nos dois = sem tranco.
	-- Sons: Toolbox > Audio > botão direito no som > Copy Asset ID. Vazio ("") = sem som.
	NitroOnSoundId = "", -- Ao LIGAR o nitro. Ex.: "rbxassetid://123456789"
	NitroOffSoundId = "", -- Ao DESLIGAR o nitro.
	HornSoundId = "rbxassetid://137100035389921", -- Buzina. Prefira um som contínuo: ele repete enquanto você segura H.
	HandbrakeTorqueMultiplier = 2, -- Força do freio de mão (× MaxTorque).
	HandbrakeRearOnly = true, -- true = trava só as traseiras (derrapa, estilo arcade). false = trava as 4 (para seco).
	CameraExtraDistance = 8, -- Câmera "afastada": quantos studs mais longe que a sua câmera normal.
	CameraDescer = 2, -- (studs) Dirigindo (câmeras 1 e 2), a câmera fica este tanto mais baixa.
	HoodCameraOffset = Vector3.new(0, 2.5, -1.5), -- Câmera do capô sem o Attachment "CameraCapo" (Y = altura, Z negativo = frente).
	-- Sensação de VELOCIDADE (bem rápido = a câmera "abre", riscos passam nas bordas e a tela treme de leve):
	EfeitoVelocidadeInicio = 60, -- (studs/s) O efeito começa nesta velocidade.
	EfeitoVelocidadeMaximo = 120, -- (studs/s) Nesta velocidade (ou mais) o efeito fica no máximo.
	EfeitoVelocidadeFOV = 25, -- (graus) Quanto a câmera "abre" no máximo (o NitroFOVBonus soma por cima). 0 = não abre.
	EfeitoVelocidadeRiscos = true, -- Riscos brancos nas bordas da tela. false = sem riscos.
	EfeitoVelocidadeTremida = 0.16, -- (studs) A tremidinha da câmera no máximo. 0 = sem tremida.

	-- =================================================================
	-- 8) GANCHO (mouse: segure o DIREITO e clique o ESQUERDO · L1 no controle · botão GANCHO no celular)
	-- =================================================================
	GanchoAlcance = 150, -- Distância máxima do gancho (studs), medida a partir do Chassi. Vale para o IMPULSO e o BOTÃO.
	GanchoAlcanceSegurar = 100, -- (studs) Alcance do gancho SEGURAR (mais curto).
	GanchoComprimentoMinimo = 3, -- A corda nunca fica mais curta que isso (studs).
	GanchoLarguraCorda = 0.2, -- Grossura da corda desenhada (Beam), em studs.
	GanchoCorCorda = Color3.fromRGB(70, 50, 35), -- Cor da corda do SEGURAR (marrom).
	GanchoEspiralLargura = 1.5, -- (studs) Voando, a corda faz uma espiral até esta largura.
	GanchoForcaPuxao = 40000, -- Força máxima para puxar (ou segurar) um personagem (AlignPosition.MaxForce).
	GanchoVelocidadePuxao = 70, -- Velocidade máxima de quem está sendo puxado (studs/s).
	GanchoDistanciaParada = 7, -- Quem é puxado para a esta distância do veículo (studs).
	GanchoTempoMaxPuxao = 4, -- Segundos máximos puxando alguém; depois solta sozinho (anti-trollagem).
	GanchoCorBotaoLigado = Color3.fromRGB(40, 220, 60), -- BotaoGancho acionado (verde).
	GanchoCorBotaoDesligado = Color3.fromRGB(220, 40, 40), -- BotaoGancho em espera (vermelho).
	GanchoBotaoFicaLigado = false, -- true = o botão continua verde depois que você solta o gancho.

	-- ---------- Recarga, voo e HUD do gancho ----------
	GanchoRecargaImpulso = 10, -- (s) Recarga do gancho de IMPULSO depois de usar (cada tipo tem a sua).
	GanchoRecargaSegurar = 20, -- (s) Recarga do gancho de SEGURAR.
	GanchoRecargaBotao = 2, -- (s) Recarga do gancho de BOTÃO (a mão).
	GanchoVelocidadeVoo = 220, -- (studs/s) Velocidade do gancho voando até o alvo (150 studs ≈ 0,7 s).
	GanchoIconeImpulso = "", -- Ícone do IMPULSO na barra: "rbxassetid://NÚMERO". Vazio ("") = 🚀
	GanchoIconeSegurar = "rbxassetid://10822560238", -- Ícone do SEGURAR. Vazio = ⚓
	GanchoIconeBotao = "", -- Ícone do BOTÃO. Vazio = 👆
	GanchoIconePosicao = UDim2.new(0.5, 0, 1, -16), -- Onde a BARRA de ganchos fica: no centro, embaixo.
	GanchoIconeTamanho = 70, -- Tamanho de cada ícone da barra (pixels).
	GanchoCorPronto = Color3.fromRGB(255, 255, 255), -- Ninguém usando: cores normais.
	GanchoCorNoAr = Color3.fromRGB(55, 55, 62), -- Gancho voando: cinza bem escuro.
	GanchoCorPreso = Color3.fromRGB(80, 255, 120), -- Prendeu em alguma coisa: verde.
	GanchoCorRecarga = Color3.fromRGB(170, 90, 90), -- Recarregando: cinza avermelhado.
	GanchoCorProibido = Color3.fromRGB(235, 45, 45), -- Numa zona sem gancho (ou mirando no que ele não pega): vermelho.

	-- ---------- Câmera de mira e gancho 3D ----------
	GanchoCameraOmbro = Vector3.new(3.2, 1.6, 0), -- Mirando: a câmera vai X studs para a DIREITA e Y para CIMA.
	GanchoCameraDistancia = 10, -- Mirando: a câmera chega até esta distância de você.
	GanchoCorMetal = Color3.fromRGB(165, 165, 175), -- Cor do gancho 3D padrão que voa girando.
	GanchoGiro = 30, -- (rad/s) Quão rápido o gancho gira no ar (30 ≈ 5 voltas por segundo).

	-- ---------- Sons e escalada do gancho ----------
	-- Sons de CADA TIPO de gancho. Vazio ("") = sem som. Exemplo: "rbxassetid://123456789"
	GanchoSomLancarImpulso = "", -- IMPULSO: o gancho SAI.
	GanchoSomPrenderImpulso = "", -- IMPULSO: o gancho PRENDE.
	GanchoSomRecolherImpulso = "", -- IMPULSO: o gancho solta e some.
	GanchoSomRecargaImpulso = "", -- IMPULSO: você tentou usar e ele ainda está recarregando. Só você ouve.
	GanchoSomLancarSegurar = "", -- SEGURAR: sai.
	GanchoSomPrenderSegurar = "", -- SEGURAR: prende.
	GanchoSomRecolherSegurar = "", -- SEGURAR: solta e some.
	GanchoSomRecargaSegurar = "", -- SEGURAR: ainda recarregando.
	GanchoSomLancarBotao = "", -- BOTÃO (a mão): sai.
	GanchoSomPrenderBotao = "", -- BOTÃO: o dedo aperta o botão.
	GanchoSomRecolherBotao = "", -- BOTÃO: solta e some.
	GanchoSomRecargaBotao = "", -- BOTÃO: ainda recarregando.
	GanchoEscalada = true, -- Gancho SEGURAR preso + as 4 rodas numa superfície com a tag "ParedeEscalavel" = o carro gruda e sobe.

	-- ---------- Os 3 tipos de gancho (barra no centro de baixo · troca: 1/2/3, clique/toque, setas ←/→) ----------
	-- IMPULSO: no chão, PUXA o veículo até o ponto. Saiu do chão com o ponto bem acima = vira PÊNDULO.
	-- Chegou perto do ponto, ou clicou de novo, = ESTILINGUE (impulso para frente e para cima).
	GanchoImpulsoForca = 150, -- (studs/s²) Força máxima do puxão. Maior = arranca e corrige a direção mais forte.
	GanchoImpulsoVelocidade = 85, -- (studs/s) Velocidade máxima do puxão.
	GanchoImpulsoChegada = 12, -- (studs) Chegou a essa distância do ponto: solta sozinho, com o estilingue.
	GanchoImpulsoTempoMaximo = 3, -- (s) Puxando há esse tempo sem chegar (travou em algo): solta sem impulso.
	GanchoImpulsoSoltar = 0.5, -- ESTILINGUE: ganha mais 50% da velocidade que tinha. 0 = sem estilingue.
	GanchoImpulsoMaximo = 45, -- (studs/s) O estilingue nunca dá mais que isso de velocidade extra.
	GanchoImpulsoSubida = 0.5, -- Quanto o estilingue aponta para CIMA (0 = reto; 1 = bem mais para cima).
	GanchoCorCordaImpulso = Color3.fromRGB(255, 140, 30), -- Cor da corda e do gancho de IMPULSO (laranja).
	-- SEGURAR: no cenário é a corda de sempre (salvar de queda e escalada). Em OUTRO jogador:
	GanchoSegurarJogador = "Prender", -- "Prender" = ele (ou o veículo dele) fica parado no lugar · "Puxar" = traz até você.
	GanchoTempoSegurar = 3, -- (s) Quanto tempo o outro jogador fica preso. A força é a GanchoForcaPuxao.
	-- BOTÃO: a mão com o dedo apontando. Só aperta os BotaoGancho.
	GanchoCorCordaBotao = Color3.fromRGB(90, 180, 255), -- Cor da corda da mão (azul).

	-- ---------- O BALANÇO (pendurado na corda: SEGURAR no ar, ou o IMPULSO no modo pêndulo) ----------
	BalancoGravidade = 55, -- (studs/s²) Menor = balança mais devagar (a gravidade de verdade é 196).
	BalancoForca = 42, -- (studs/s²) Quanto W/A/S/D empurram o balanço.
	BalancoVelocidadeMaxima = 55, -- (studs/s) O mais rápido que ele balança.
	BalancoAmortecimento = 0.35, -- (por segundo) Sem tecla, o balanço diminui devagar.
	BalancoInclinacao = 25, -- (graus) O nariz fica levantado enquanto está pendurado.
	BalancoCordaMinima = 8, -- (studs) Tamanho mínimo da corda no balanço.
	BalancoCordaMaxima = 60, -- (studs) Tamanho máximo da corda no balanço.
	BalancoEmbalo = 1.6, -- Lá EMBAIXO o empurrão das teclas vale até 1.6× (1 = desliga).
	BalancoFlutuar = 0.4, -- Lá no ALTO o balanço fica em câmera lenta (0 = desliga · máximo 0.9).
	BalancoInclinarLado = 22, -- (graus) Indo de lado, ele deita para aquele lado (0 = desliga).
	BalancoPerfeito = 0.7, -- PERFEITO = soltar SUBINDO com mais de 70% da velocidade máxima.
	BalancoBonusPerfeito = 1.3, -- No PERFEITO ele sai 30% mais rápido...
	BalancoPuloPerfeito = 18, -- ...e com esse tanto (studs/s) a mais para cima.
	BalancoElastico = 0.07, -- No puxão mais forte a corda estica até 7% e volta, como elástico (0 = desliga).
	BalancoSoltura = 0.6, -- Quanto o corpo deita junto com a corda (0 = sempre reto · 1 = todo na direção da corda).
	BalancoMolaDoCorpo = 25, -- A "mola" que faz o corpo balançar atrás da corda (maior = mais firme).
	BalancoQuique = 0.3, -- Quanto ele quica ao bater numa parede (0 = não quica · 0.6 = bola de borracha).
	BalancoChuteParede = 25, -- (studs/s) Encostado numa parede, empurrar para longe dela dá um chute (0 = desliga).

	-- =================================================================
	-- 9) DESVIRAR, FREIO DE MÃO E LADEIRA
	-- =================================================================
	TempoParaDesvirar = 2.5, -- (s) Tombado por este tempo seguido, aí sim dá para desvirar (R ou botão).
	DesvirarAlturaExtra = 4, -- (studs) Ao desvirar, o veículo sobe mais este tanto (e a tela treme quando ele cai).
	FreioDeMaoAtrito = 0.35, -- Atrito das rodas travadas DEVAGAR (quase parando). Maior = termina de parar mais seco.
	FreioDeMaoAtritoRapido = 0.08, -- Atrito das rodas travadas MUITO RÁPIDO. Menor = desliza mais longe antes de parar.
	FreioDeMaoVelocidadeRapida = 90, -- (studs/s) Desta velocidade para cima vale o atrito "rápido".
	FreioDeMaoAderenciaFrente = 0.5, -- Muito rápido, as rodas SOLTAS ficam com 50% da aderência. 1 = desliga.
	FreioDeMaoEscorregar = 0.6, -- Multiplica o atrito da derrapada (menor = desliza mais e demora a parar).
	FreioDeMaoGiroMaximo = 70, -- (graus/s) Derrapando, o veículo gira no máximo isso (na FreioDeMaoVelocidadeRapida).
	FreioDeMaoVelocidadeEstacionar = 6, -- (studs/s) Puxou o freio de mão mais devagar que isso = ESTACIONA (não derrapa).
	FreioDeMaoSomId = "", -- Som de pneu derrapando (só toca com o carro andando). Ex.: "rbxassetid://..."
	FreioDeMaoEfeitos = true, -- Fumaça e estrelinhas nas rodas enquanto derrapa.
	FreioDeMaoTexturaFumaca = "", -- (opcional) O ID de uma imagem de nuvem para a fumaça. Vazio = a fumaça padrão.
	GanhoLadeira = 40, -- Descendo: a velocidade máxima sobe (inclinação × este valor) por segundo.
	PerdaLadeira = 15, -- Fora da descida: a velocidade extra cai este tanto por segundo.
	VelocidadeMaximaTotal = 130, -- Limite de tudo (ladeira + nitro). O velocímetro mostra até aqui.
	LadeiraForcaSegurar = 2, -- Parado (ou passando do limite da ré) na ladeira: as 4 rodas seguram com esta força (× MaxTorque).

	-- =================================================================
	-- 10) PANCADA (bater MUITO rápido em outro veículo)
	-- =================================================================
	-- Você passou de BaterVelocidadeMinima e bateu num veículo com OUTRO jogador dirigindo: o dele leva
	-- um tranco (empurrão, pulinho e giro). Valem os números do veículo de QUEM BATE.
	BaterVelocidadeMinima = 80, -- (studs/s) A partir desta velocidade, a batida dá a pancada.
	BaterEmpurrao = 40, -- (studs/s) Quanto o outro veículo é empurrado.
	BaterSubida = 20, -- (studs/s) O pulinho para cima. 0 = sem pulinho.
	BaterGiro = 2.5, -- (rad/s) O giro que ele leva quando a batida pega de lado. 0 = sem giro.
	BaterSomId = "", -- Som da batida (quem estiver perto ouve). Vazio = sem som.

	-- =================================================================
	-- 11) MOUSE TRAVADO (estilo Shift-Lock) — só para quem joga com mouse
	-- =================================================================
	MouseTravadoAoSentar = true, -- true = ao sentar, o mouse já trava no meio da tela e a câmera segue o mouse. LeftAlt alterna.
	MouseCameraClassica = true, -- true = câmera clássica do Roblox (segue o mouse). false = câmera de veículo padrão.
	MouseAvisoPosicao = UDim2.new(1, -16, 0, 12), -- Onde fica o aviso do mouse: canto de cima, à direita.
	MouseAvisoTempo = 2, -- (s) Quanto tempo o balão do aviso do mouse fica aberto (0 = não fecha).
}

export type Config = typeof(PADRAO)

local ConfiguracaoPadrao = {}

local avisados: { [string]: boolean } = {} -- (cada aviso aparece uma vez só, mesmo com vários veículos iguais)

-- Avisa no Output (só no servidor: assim o mesmo aviso não aparece duas vezes no Studio).
local function avisar(mensagem: string)
	if avisados[mensagem] or not RunService:IsServer() then
		return
	end
	avisados[mensagem] = true
	warn(mensagem)
end

-- "rbxassetid://" sem o número (ou só com espaços) vira "" = sem som/sem imagem.
-- (Sem isso, o Roblox tenta carregar um som que não existe e enche o Output de erros.)
local function limparTextos(config: { [string]: any })
	for chave, valor in config do
		if typeof(valor) == "string" then
			local limpo = string.match(valor, "^%s*(.-)%s*$") or valor -- tira os espaços das pontas
			config[chave] = if string.match(limpo, "^rbx%w*://$") then "" else limpo
		end
	end
end

-- Cria a Configuracao de um veículo: o PADRÃO + as mudanças dele.
-- Nome que não existe ou valor do tipo errado (ex.: texto no lugar de número) = aviso no Output.
function ConfiguracaoPadrao.criar(mudancas: { [string]: any }?): Config
	local padroes = PADRAO :: { [string]: any }
	local config = table.clone(padroes)
	if mudancas then
		local origem = debug.info(2, "s") or "Configuracao" -- (qual Configuracao chamou: aparece no aviso)
		for chave, valor in mudancas do
			local padrao = padroes[chave]
			if padrao == nil then
				avisar(`[Configuracao] {origem}: "{chave}" não existe (erro de digitação?). Os nomes certos estão em ReplicatedStorage > Compartilhado > ConfiguracaoPadrao.`)
			elseif typeof(valor) ~= typeof(padrao) then
				avisar(`[Configuracao] {origem}: "{chave}" deveria ser {typeof(padrao)}, mas é {typeof(valor)}. Ficou o padrão ({tostring(padrao)}).`)
			else
				config[chave] = valor
			end
		end
	end
	limparTextos(config)
	return config :: any
end

-- Completa uma Configuracao ANTIGA (a lista inteira, do jeito de antes): o que faltar nela vem do
-- padrão. Os scripts dos veículos chamam isto sozinhos; você não precisa usar.
function ConfiguracaoPadrao.completar(config: unknown): Config
	if typeof(config) ~= "table" then
		return ConfiguracaoPadrao.criar(nil)
	end
	local tabela = config :: { [string]: any }
	for chave, valor in PADRAO :: { [string]: any } do
		if tabela[chave] == nil then
			tabela[chave] = valor
		end
	end
	limparTextos(tabela)
	return tabela :: any
end

return ConfiguracaoPadrao
