--!strict
--[[
	=====================================================================
	Configuracao  (ModuleScript)
	Local: Quadriciclo > Scripts > Configuracao
	=====================================================================

	Este é o ÚNICO lugar que você precisa editar para mudar o jeito
	que o quadriciclo anda. Os dois outros scripts (Servidor e Cliente)
	leem estes valores quando o jogo começa.

	Dica de iniciante: mude UM valor por vez, aperte Play e compare.
	Ligue o DEBUG_MODE para ver as peças invisíveis e os avisos no Output.

	Unidades usadas aqui:
	  - studs         = a "medida" do Roblox (um bloco padrão tem 4 studs de largura).
	  - studs/s       = velocidade (studs por segundo).
	  - studs/s²      = aceleração (quanto a velocidade muda a cada segundo).
	  - graus         = ângulo (0 a 360).
]]

local Configuracao = {
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
	MaxSpeed = 40, -- Velocidade máxima para frente (studs/s). O vídeo mostra ~30.
	ReverseSpeed = 30, -- Velocidade máxima de ré (studs/s).
	Acceleration = 35, -- Quanto a velocidade sobe por segundo (studs/s²). Vídeo: de 7 para 26 em ~1,25 s.
	BrakeDeceleration = 45, -- Força do freio (studs/s²). Maior = para mais rápido.
	CoastDeceleration = 8, -- "Freio motor" quando você solta o acelerador (studs/s²).
	MaxTorque = 55378, -- Torque máximo de CADA motor de roda: é a "força" para subir rampas e empurrar coisas.
	DriveMode = "4x4", -- Tração: "4x4", "Traseira" ou "Dianteira".

	-- =================================================================
	-- 3) DIREÇÃO
	-- =================================================================
	SteerAngle = 30, -- Ângulo máximo das rodas da frente quando está devagar (graus).
	SteerAngleAtMaxSpeed = 15, -- Ângulo máximo na velocidade máxima (graus). Menor = mais estável em alta.
	SteerSpeed = 250, -- Rapidez com que o guidão gira (graus por segundo).
	SteerTorque = 127795, -- Força do servo da direção. Se as rodas não virarem direito, aumente.

	-- =================================================================
	-- 4) SUSPENSÃO (SpringConstraint)
	-- =================================================================
	SpringStiffness = 7680, -- Dureza da mola. Maior = afunda menos e fica mais "dura".
	SpringDamping = 1036, -- Amortecimento. Maior = quica menos (menor = mais "pula-pula").
	SpringFreeLength = 3.200, -- Comprimento da mola sem peso nenhum (studs).
	SpringMinLength = 0.720, -- Compressão máxima: a mola nunca fica menor que isso (é o "batente").
	SpringMaxLength = 4.800, -- Extensão máxima: o quanto a roda pode descer quando está no ar.

	-- Aparência das molas. No vídeo elas aparecem como espirais amarelas.
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
	ChassisDensity = 2, -- Densidade do Chassi. É ele que dá quase todo o peso do quadriciclo.
	ChassisFriction = 0.3, -- Atrito do Chassi quando raspa no chão (baixo = escorrega em vez de travar).

	-- =================================================================
	-- 6) CONTROLES E EXTRAS
	-- =================================================================
	MasslessDriver = true, -- Personagem sem massa enquanto dirige (não muda o centro de massa).
	ShowSpeedometer = true, -- Mostra "Velocidade: N" na tela, como no vídeo.
	MobileSteerButtons = false, -- Celular: true = cria botões ESQ/DIR. false = vira pelo analógico da tela.
	-- =================================================================
	-- 7) NITRO, FREIO DE MÃO, BUZINA E CÂMERA
	-- =================================================================
	NitroSpeedBonus = 8, -- Velocidade extra no nitro (30 + 5 = 35, o máximo do velocímetro).
	NitroAccelerationMultiplier = 1.6, -- Aceleração no nitro (1.6 = 60% mais forte que Acceleration).
	NitroTorqueMultiplier = 1.5, -- Força extra nas rodas no nitro: é o que ajuda a subir morro íngreme.
	NitroFOVBonus = 8, -- Graus que a câmera "abre" no nitro (sensação de velocidade). 0 = desliga.
	NitroDuration = 2.5, -- Segundos de nitro com o tanque cheio (a barra roxa do HUD).
	NitroRechargeTime = 6, -- Segundos para o tanque encher de novo, do vazio até cheio.
	-- Sons: Toolbox > Audio > botão direito no som > Copy Asset ID. Vazio ("") = sem som.
	NitroOnSoundId = "", -- Ao LIGAR o nitro. Ex.: "rbxassetid://123456789"
	NitroOffSoundId = "", -- Ao DESLIGAR o nitro.
	HornSoundId = "rbxassetid://137100035389921", -- Buzina. Prefira um som contínuo: ele repete enquanto você segura H.
	HandbrakeTorqueMultiplier = 2, -- Força do freio de mão (× MaxTorque).
	HandbrakeRearOnly = true, -- true = trava só as traseiras (derrapa, estilo arcade). false = trava as 4 (para seco).
	CameraExtraDistance = 8, -- Câmera "afastada": quantos studs mais longe que a sua câmera normal.
	HoodCameraOffset = Vector3.new(0, 2.5, -1.5), -- Câmera do capô sem o Attachment "CameraCapo" (Y = altura, Z negativo = frente).
	-- Sensação de VELOCIDADE (bem rápido = a câmera "abre", riscos passam nas bordas e a tela treme de leve):
	EfeitoVelocidadeInicio = 60, -- (studs/s) O efeito começa nesta velocidade (o normal vai até 30; no nitro, 35).
	EfeitoVelocidadeMaximo = 120, -- (studs/s) Nesta velocidade (ou mais) o efeito fica no máximo.
	EfeitoVelocidadeFOV = 25, -- (graus) Quanto a câmera "abre" no máximo (o NitroFOVBonus soma por cima). 0 = não abre.
	EfeitoVelocidadeRiscos = true, -- Riscos brancos nas bordas da tela. false = sem riscos.
	EfeitoVelocidadeTremida = 0.16, -- (studs) A tremidinha da câmera no máximo. 0 = sem tremida.
	-- =================================================================
	-- 8) GANCHO (Q no teclado · LB/L1 no controle · botão GANCHO no celular)
	-- =================================================================
	GanchoAlcance = 150, -- Distância máxima do gancho (studs), medida a partir do Chassi.
	GanchoAlcanceSegurar = 100, -- (studs) Alcance do gancho SEGURAR (mais curto). O GanchoAlcance, acima, vale para o IMPULSO e o BOTÃO.
	GanchoComprimentoMinimo = 3, -- A corda nunca fica mais curta que isso (studs).
	GanchoLarguraCorda = 0.2, -- Grossura da corda desenhada (Beam), em studs.
	GanchoCorCorda = Color3.fromRGB(70, 50, 35), -- Cor da corda (marrom).
	GanchoForcaPuxao = 40000, -- Força máxima para puxar um personagem (AlignPosition.MaxForce).
	GanchoVelocidadePuxao = 70, -- Velocidade máxima de quem está sendo puxado (studs/s).
	GanchoDistanciaParada = 7, -- Quem é puxado para a esta distância do quadriciclo (studs).
	GanchoTempoMaxPuxao = 4, -- Segundos máximos segurando alguém; depois solta sozinho (anti-trollagem).
	GanchoCorBotaoLigado = Color3.fromRGB(40, 220, 60), -- BotaoGancho acionado (verde).
	GanchoCorBotaoDesligado = Color3.fromRGB(220, 40, 40), -- BotaoGancho em espera (vermelho).
	GanchoBotaoFicaLigado = false, -- true = o botão continua verde depois que você solta o gancho.


	-- ---------- Recarga, voo e HUD do gancho ----------

	GanchoRecargaImpulso = 10, -- (s) Recarga do gancho de IMPULSO depois de usar (cada tipo tem a sua).
	GanchoRecargaSegurar = 20, -- (s) Recarga do gancho de SEGURAR.
	GanchoRecargaBotao = 2, -- (s) Recarga do gancho de BOTÃO (a mão).
	GanchoVelocidadeVoo = 220, -- (studs/s) Velocidade do gancho voando até o alvo (150 studs ≈ 0,7 s).
	GanchoIconeImpulso = "", -- Ícone do IMPULSO na barra: "rbxassetid://NÚMERO". Vazio ("") = 🚀
	GanchoIconeSegurar = "rbxassetid://10822560238", -- Ícone do SEGURAR (o seu ícone de gancho). Vazio = ⚓
	GanchoIconeBotao = "", -- Ícone do BOTÃO. Vazio = 👆 (a mão com o dedo apontando)
	GanchoIconePosicao = UDim2.new(0.5, 0, 1, -16), -- Onde a BARRA de ganchos fica: no centro, embaixo (16 pixels acima da borda).
	GanchoIconeTamanho = 70, -- Tamanho de cada ícone da barra (pixels).
	GanchoCorPronto = Color3.fromRGB(255, 255, 255), -- Ninguém usando: cores normais.
	GanchoCorNoAr = Color3.fromRGB(55, 55, 62), -- Gancho voando: cinza bem escuro, quase preto.
	GanchoCorPreso = Color3.fromRGB(80, 255, 120), -- Prendeu em alguma coisa: verde.
	GanchoCorRecarga = Color3.fromRGB(170, 90, 90), -- Recarregando (depois de usar): cinza avermelhado.
	-- ---------- Câmera de mira e gancho 3D ----------
	GanchoCameraOmbro = Vector3.new(3.2, 1.6, 0), -- Segurando Q: a câmera vai X studs para a DIREITA e Y para CIMA.
	GanchoCameraDistancia = 10, -- Segurando Q: a câmera chega até esta distância de você (mira mais de perto).
	GanchoCorMetal = Color3.fromRGB(165, 165, 175), -- Cor do gancho 3D padrão que voa girando.
	GanchoGiro = 30, -- (rad/s) Quão rápido o gancho e a corda giram no ar (30 ≈ 5 voltas por segundo).
	-- ---------- Sons e escalada do gancho ----------
	-- Sons de CADA TIPO de gancho (Toolbox > Audio > botão direito no som > Copy Asset ID).
	-- Vazio ("") = sem som. Exemplo: GanchoSomLancarImpulso = "rbxassetid://123456789",
	GanchoSomLancarImpulso = "rbxassetid://", -- IMPULSO: o gancho SAI (ao soltar o Q).
	GanchoSomPrenderImpulso = "rbxassetid://", -- IMPULSO: o gancho PRENDE.
	GanchoSomRecolherImpulso = "rbxassetid://", -- IMPULSO: o gancho solta e some.
	GanchoSomRecargaImpulso = "rbxassetid://", -- IMPULSO: você tentou usar (ou escolheu) e ele ainda está recarregando. Só você ouve.
	GanchoSomLancarSegurar = "rbxassetid://", -- SEGURAR: sai.
	GanchoSomPrenderSegurar = "rbxassetid://", -- SEGURAR: prende.
	GanchoSomRecolherSegurar = "rbxassetid://", -- SEGURAR: solta e some.
	GanchoSomRecargaSegurar = "rbxassetid://", -- SEGURAR: ainda recarregando.
	GanchoSomLancarBotao = "rbxassetid://", -- BOTÃO (a mão): sai.
	GanchoSomPrenderBotao = "rbxassetid://", -- BOTÃO: o dedo aperta o botão.
	GanchoSomRecolherBotao = "rbxassetid://", -- BOTÃO: solta e some.
	GanchoSomRecargaBotao = "rbxassetid://", -- BOTÃO: ainda recarregando.
	GanchoEscalada = true, -- Gancho preso + as 4 rodas encostadas numa parede/rampa = o carro gruda e sobe.
	-- ---------- Os 3 tipos de gancho (barra no centro de baixo · troca: 1/2/3, clique/toque, setas ←/→) ----------
	-- IMPULSO: no chão, PUXA o quadriciclo até o ponto. Saiu do chão com o ponto bem acima = vira PÊNDULO
	-- (GÁS dá embalo). Chegou perto do ponto, ou apertou Q, = ESTILINGUE (impulso para frente e para cima).
	GanchoImpulsoForca = 150, -- (studs/s²) Força máxima do puxão. Maior = arranca e corrige a direção mais forte.
	GanchoImpulsoVelocidade = 85, -- (studs/s) Velocidade máxima do puxão.
	GanchoImpulsoChegada = 12, -- (studs) Chegou a essa distância do ponto: solta sozinho, com o estilingue.
	GanchoImpulsoTempoMaximo = 3, -- (s) Puxando há esse tempo sem chegar (travou em algo): solta sem impulso.
	GanchoImpulsoSoltar = 0.5, -- ESTILINGUE: ganha mais 50% da velocidade que tinha. 0 = sem estilingue.
	GanchoImpulsoMaximo = 45, -- (studs/s) O estilingue nunca dá mais que isso de velocidade extra.
	GanchoImpulsoSubida = 0.5, -- Quanto o estilingue aponta para CIMA (0 = reto para onde ia; 1 = bem mais para cima).
	GanchoBalancoForca = 50, -- (studs/s²) PÊNDULO: força do embalo segurando GÁS. Maior = balança mais alto.
	GanchoBalancoVelocidadeMaxima = 110, -- (studs/s) PÊNDULO: o embalo para de ajudar nessa velocidade.
	GanchoCorCordaImpulso = Color3.fromRGB(255, 140, 30), -- Cor da corda e do gancho de IMPULSO (laranja).
	-- SEGURAR: no cenário é a corda de sempre (salvar de queda e escalada). Em OUTRO jogador:
	GanchoSegurarJogador = "Prender", -- "Prender" = ele (ou o veículo dele) fica parado no lugar · "Puxar" = traz até você.
	GanchoTempoSegurar = 3, -- (s) Quanto tempo o outro jogador fica preso. A força é a GanchoForcaPuxao.
	-- BOTÃO: a mão com o dedo apontando. Só aperta os BotaoGancho.
	GanchoCorCordaBotao = Color3.fromRGB(90, 180, 255), -- Cor da corda da mão (azul).







	-- =================================================================
	-- 9) DESVIRAR, FREIO DE MÃO E LADEIRA
	-- =================================================================

	TempoParaDesvirar = 2.5, -- (s) Tombado por este tempo seguido, aí sim dá para desvirar (R ou botão).
	FreioDeMaoAtrito = 0.35, -- Atrito das rodas travadas DEVAGAR (quase parando). Maior = termina de parar mais seco.
	FreioDeMaoAtritoRapido = 0.08, -- (NOVO) Atrito das rodas travadas MUITO RÁPIDO. Menor = desliza mais longe antes de parar.
	FreioDeMaoVelocidadeRapida = 90, -- (NOVO) (studs/s) Desta velocidade para cima vale o atrito "rápido". Abaixo, o atrito vai mudando aos poucos.
	FreioDeMaoAderenciaFrente = 0.5, -- (NOVO) Muito rápido, as rodas SOLTAS ficam com 50% da aderência: desliza inteiro, sem rodar de repente. 1 = desliga.
	FreioDeMaoSomId = "rbxassetid://", -- Som de pneu derrapando (só toca com o carro andando). Ex.: "rbxassetid://..."
	FreioDeMaoEfeitos = true, -- Fumaça e faíscas nas rodas enquanto derrapa.
	GanhoLadeira = 40, -- Descendo: a velocidade máxima sobe (inclinação × este valor) por segundo.
	PerdaLadeira = 15, -- Fora da descida: a velocidade extra cai este tanto por segundo.
	VelocidadeMaximaTotal = 130, -- Limite de tudo (ladeira + nitro). O velocímetro mostra até aqui.
	-- =================================================================
	-- 10) PANCADA (bater MUITO rápido em outro quadriciclo)
	-- =================================================================
	-- Você passou de BaterVelocidadeMinima (o número do velocímetro) e bateu num quadriciclo com OUTRO
	-- jogador dirigindo: o dele leva um tranco (empurrão, pulinho e giro). Na prática acontece com o
	-- IMPULSO do gancho ou numa descida bem longa. Valem os números do quadriciclo de QUEM BATE.
	BaterVelocidadeMinima = 80, -- (studs/s) A partir desta velocidade, a batida dá a pancada.
	BaterEmpurrao = 40, -- (studs/s) Quanto o outro quadriciclo é empurrado (para onde você ia e para longe de você).
	BaterSubida = 20, -- (studs/s) O pulinho para cima: uns 1 stud de altura, um tranco e não um voo. 0 = sem pulinho.
	BaterGiro = 2.5, -- (rad/s) O giro que ele leva quando a batida pega de lado (2.5 ≈ 140° por segundo). 0 = sem giro.
	BaterSomId = "", -- Som da batida (quem estiver perto ouve). Ex.: "rbxassetid://123456789". Vazio = sem som.
	-- =================================================================
	-- 11) ESTABILIDADE EM ALTA VELOCIDADE (NOVO)
	-- =================================================================
	LastroFracao = 0.6, -- Quanto do peso do Chassi desce para o "Lastro" invisível (0 = desliga · 0.6 = 60%). Maior = mais difícil de capotar.
	LastroAbaixoDoEixo = 0, -- (studs) O lastro fica na altura dos eixos das rodas. Para descer mais, coloque 0.5 ou 1.
	SteerAngleMinimo = 4, -- (graus) Acima da MaxSpeed, o ângulo da direção continua caindo, mas nunca fica menor que isso.
	-- =================================================================
	-- 12) MOUSE TRAVADO (estilo Shift-Lock) — só para quem joga com mouse (NOVO)
	-- =================================================================
	MouseTravadoAoSentar = true, -- true = ao sentar, o mouse já trava no meio da tela e a câmera segue o mouse. LeftAlt alterna.
	MouseCameraClassica = true, -- true = câmera clássica do Roblox (segue o mouse). false = câmera de veículo padrão (puxa sozinha para trás do quadriciclo).
	MouseAvisoPosicao = UDim2.new(1, -16, 0, 12), -- Onde fica o aviso do mouse: canto de cima, à direita (16 pixels da borda).
}

return Configuracao
