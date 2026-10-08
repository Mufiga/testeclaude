--!strict
--[[
	=====================================================================
	Gancho  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Gancho
	=====================================================================
	Como usar (PC): SEGURE o botão DIREITO do mouse para mirar (aparece a mira e a câmera vai
	para o ombro) e CLIQUE o botão ESQUERDO para o gancho sair. Soltou o direito sem clicar = a
	mira é cancelada. Com o gancho no ar ou preso, clique o ESQUERDO de novo para soltar (começa
	a recarga). Controle: SEGURE L1 para mirar e SOLTE para lançar. Celular: o mesmo, no botão GANCHO.
	(Quem trava o mouse no meio da tela, estilo Shift-Lock, é o módulo Camera: tecla Alt.)
	Para QUEM DIRIGE (ligar/desligar): mira, ícone do gancho no HUD, câmera
	de mira, recarga e escalada (gancho preso + as 4 rodas encostadas = o carro
	gruda na parede e sobe).
	Para TODO MUNDO (criarVisual): o gancho 3D que sai girando, a corda que
	roda no ar e estica quando prende, e os sons.
	ZONAS SEM GANCHO: qualquer Part (ou Model) com a tag "ZonaSemGancho" é uma área onde
	o gancho não funciona (veja "ZONAS SEM GANCHO", mais abaixo).
	Quem confere tudo e prende de verdade é o QuadricicloServidor (módulo Gancho de lá).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService") -- (NOVO) anima o vento sumindo e o "PERFEITO!"

local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
local CameraModulo = require(script.Parent:WaitForChild("Camera")) -- (NOVO) para o tranco na tela (Camera.tremer)
local Tela = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Tela")) -- (NOVO) HUD menor no celular
type Quadriciclo = Veiculo.Quadriciclo

local Gancho = {}

local jogadorLocal = Players.LocalPlayer :: Player

local ACAO_GANCHO = "QuadricicloGancho"
local NOME_CORDA_GANCHO = "CordaGancho" -- mesmo nome que o Servidor dá à RopeConstraint
local ESPERA_RESPOSTA_GANCHO = 1 -- (s) sem resposta do Servidor nesse tempo = ele recusou o alvo
local TAG_ZONA_SEM_GANCHO = "ZonaSemGancho" -- a tag das áreas onde o gancho não funciona
local TAG_ZONA_SEM_IMPULSO = "ZonaSemImpulso" -- (NOVO) a tag das áreas onde SÓ o gancho de IMPULSO não funciona
local TAG_PAREDE_ESCALAVEL = "ParedeEscalavel" -- (NOVO) só superfícies com esta tag deixam o SEGURAR subir parede
local COR_PROIBIDO_PADRAO = Color3.fromRGB(235, 45, 45) -- (se a Configuracao não tiver GanchoCorProibido)

-- =====================================================================
-- QUEM DIRIGE: mira, HUD, recarga e escalada
-- =====================================================================
local enviadoEm: number? = nil -- quando mandamos o "GanchoLiga" (nil = nenhum gancho nosso no ar ou preso)
local recargaPrevista: { [string]: number } = {} -- recarga marcada aqui ao soltar, por TIPO (o Servidor confirma logo depois)
local conexaoCordaGancho: RBXScriptConnection? = nil
local conexaoHudGancho: RBXScriptConnection? = nil

-- ---------- OS TIPOS DE GANCHO (a barra no centro de baixo da tela) ----------
-- Cada tipo tem: o "id" (o nome que o Servidor entende), o nome que aparece embaixo do ícone, a tecla
-- que escolhe ele e um emoji de reserva (usado quando a Configuracao não tem imagem para ele).
-- Para criar um tipo novo depois (Ajuda, PvP...): acrescente uma linha aqui, a tecla dele no
-- Gancho.ligar e ensine o Servidor o que ele faz.
type TipoDeGancho = {
	id: string,
	nome: string,
	tecla: Enum.KeyCode,
	emoji: string,
}
local TIPOS_DE_GANCHO: { TipoDeGancho } = {
	{ id = "Impulso", nome = "IMPULSO", tecla = Enum.KeyCode.One, emoji = "🚀" },
	{ id = "Segurar", nome = "SEGURAR", tecla = Enum.KeyCode.Two, emoji = "⚓" },
	{ id = "Botao", nome = "BOTÃO", tecla = Enum.KeyCode.Three, emoji = "👆" },
}
local ACAO_TROCAR_GANCHO = "QuadricicloTrocarGancho" -- teclas 1, 2, 3 e setas ←/→ do controle
local tipoSelecionado = TIPOS_DE_GANCHO[1].id -- o gancho escolhido na barra (é ele que sai quando você clica)
local tipoAtivo: string? = nil -- o tipo do NOSSO gancho que está voando ou preso agora

-- Passa para o gancho do lado na barra (setas ←/→ do controle). Depois do último, volta ao primeiro.
local function trocarGancho(passo: number)
	local atual = 1
	for posicao, tipo in TIPOS_DE_GANCHO do
		if tipo.id == tipoSelecionado then
			atual = posicao
		end
	end
	local proximo = (atual - 1 + passo) % #TIPOS_DE_GANCHO + 1 -- o "%" faz dar a volta na barra
	tipoSelecionado = TIPOS_DE_GANCHO[proximo].id
end

-- A imagem de cada tipo na Configuracao (GanchoIconeImpulso, GanchoIconeSegurar, GanchoIconeBotao).
-- Vazio = o ícone usa o emoji.
local function imagemDoTipo(quad: Quadriciclo, id: string): string
	local imagem = quad.Config["GanchoIcone" .. id]
	return if typeof(imagem) == "string" then imagem else ""
end

-- Quantos segundos cada tipo recarrega (Configuracao: GanchoRecargaImpulso, GanchoRecargaSegurar...).
local function recargaDoTipo(quad: Quadriciclo, id: string): number
	local segundos = quad.Config["GanchoRecarga" .. id]
	return if typeof(segundos) == "number" then segundos else 20
end

-- (NOVO) O alcance de cada tipo (Configuracao): o SEGURAR é mais curto (GanchoAlcanceSegurar); o
-- IMPULSO e o BOTÃO usam o GanchoAlcance. (O Servidor confere com a mesma regra.)
local function alcanceDoTipo(quad: Quadriciclo, id: string): number
	local Config = quad.Config
	if id == "Segurar" and typeof(Config.GanchoAlcanceSegurar) == "number" then
		return Config.GanchoAlcanceSegurar
	end
	return Config.GanchoAlcance
end

-- (NOVO) O som de um tipo na Configuracao. "momento" = "Lancar", "Prender", "Recolher" ou "Recarga".
-- Ex.: somDoTipo(Config, "Lancar", "Impulso") lê o GanchoSomLancarImpulso. Vazio ("") = sem som.
local function somDoTipo(Config: any, momento: string, id: string): string
	local som = Config["GanchoSom" .. momento .. id]
	return if typeof(som) == "string" then som else ""
end

-- Peças de UM ícone da barra (um para cada tipo de gancho).
type IconeDaBarra = {
	tipo: string, -- qual gancho este ícone representa
	caixa: Frame, -- o ícone inteiro (é ela que treme)
	escala: UIScale, -- o gancho escolhido fica um pouco maior
	icone: CanvasGroup, -- tudo que muda de cor fica aqui dentro (GroupColor3 pinta tudo junto)
	anel: UIStroke, -- contorno redondo do ícone
	sombra: Frame, -- "cortina" escura da recarga (vai descendo até sumir)
	tempo: TextLabel, -- segundos que faltam
	proibido: Frame, -- risco de "proibido": aparece dentro de uma zona onde este gancho não funciona
	nome: TextLabel, -- o nome embaixo do ícone
	cor: Color3, -- cor atual do ícone (vai suave até a cor do estado)
	tremidas: number, -- (NOVO) conta as tremidas: uma tremida nova faz a anterior parar no meio
}

-- Peças do HUD do gancho (criado por código quando você senta; some quando você levanta).
type HudGancho = {
	tela: ScreenGui,
	icones: { IconeDaBarra }, -- a barra de ganchos
	mira: CanvasGroup, -- só aparece enquanto você mira (fica vermelha se não der para prender ali)
	sons: { [string]: Sound }, -- (NOVO) os sons que só você ouve (ex.: "RecargaImpulso")
}
local hudGancho: HudGancho? = nil
local ultimoEscolhido = tipoSelecionado -- (NOVO) para perceber quando você escolhe OUTRO gancho na barra

-- Segundos que faltam para o gancho DESTE TIPO voltar. O Servidor marca no seu Player o horário em que
-- ele volta (Attribute "GanchoRecargaAte" + o tipo, ex.: "GanchoRecargaAteImpulso"); vale em qualquer
-- quadriciclo.
local function recargaRestante(tipo: string): number
	local ate = jogadorLocal:GetAttribute("GanchoRecargaAte" .. tipo)
	local fim = math.max(if typeof(ate) == "number" then ate else 0, recargaPrevista[tipo] or 0)
	return math.max(fim - workspace:GetServerTimeNow(), 0)
end

-- Quem está "dentro" desta peça? Um personagem (funciona até acertando um chapéu) ou o motorista de
-- um VEÍCULO (acertou outro quadriciclo com alguém sentado). Nil = é cenário ou objeto.
local function humanoideDoAlvo(parte: Instance): Humanoid?
	local atual = parte.Parent
	while atual and atual ~= workspace do
		if atual:IsA("Model") then
			local humanoide = atual:FindFirstChildOfClass("Humanoid")
			if humanoide then
				return humanoide
			end
			local banco = atual:FindFirstChildWhichIsA("VehicleSeat")
			if banco and banco:IsA("VehicleSeat") and banco.Occupant then
				return banco.Occupant
			end
		end
		atual = atual.Parent
	end
	return nil
end

-- As mesmas regras do Servidor, para cada TIPO (assim a mira já fica vermelha quando o gancho escolhido
-- não serve para aquilo, e ele nem é disparado):
--   IMPULSO = só cenário preso no mundo · SEGURAR = cenário preso ou outro jogador vivo
--   BOTÃO   = só os BotaoGancho
local function podeEnganchar(parte: Instance, tipo: string): boolean
	if not parte:IsA("BasePart") then
		return false
	end
	local humanoide = humanoideDoAlvo(parte)
	if humanoide then
		return tipo == "Segurar" and humanoide.Health > 0
	end
	if CollectionService:HasTag(parte, "BotaoGancho") or parte.Name == "BotaoGancho" then
		return tipo == "Botao"
	end
	if tipo == "Botao" then
		return false -- a mão só aperta botões
	end
	local raiz = parte.AssemblyRootPart -- pode ser nil
	return parte:IsA("Terrain") or parte.Anchored or (if raiz then raiz.Anchored else false)
end

-- ---------- ZONAS SEM GANCHO e ZONAS SEM IMPULSO (você escolhe onde, montando o mapa) ----------
-- Dois tipos de zona. Cada uma é uma Part com a tag (ou um Model/Folder com a tag: vale cada Part
-- dentro dele):
--   "ZonaSemGancho"  = NENHUM dos 3 ganchos funciona (Impulso, Segurar e Botão)
--   "ZonaSemImpulso" = só o gancho de IMPULSO não funciona (os outros dois funcionam). Use onde o
--                      impulso deixaria o jogador "cortar caminho" e roubar no mapa.
-- Onde uma zona proíbe um gancho, esse gancho:
--   - não prende em nada que esteja lá dentro (nem em quem estiver lá: serve de área segura);
--   - não atravessa a área (não dá para passar por cima dela pendurado);
--   - não sai de dentro dela (o ícone dele fica vermelho, com um risco);
--   - se o quadriciclo ou a corda entrar na zona com ele no ar ou preso, ele solta (sem estilingue).
-- O tamanho, o giro e o lugar da zona são os da Part. Atributo "Ativa" = false desliga a zona sem
-- apagar. (O script Zonas, no ServerScriptService, deixa as zonas invisíveis e sem colisão quando o
-- jogo começa.)

-- A linha de A até B passa por dentro da caixa desta peça? (Vale também se A ou B estiverem dentro.)
local function linhaCruzaPeca(peca: BasePart, a: Vector3, b: Vector3): boolean
	local inicio = peca.CFrame:PointToObjectSpace(a)
	local caminho = peca.CFrame:PointToObjectSpace(b) - inicio
	local meio = peca.Size / 2
	local entra, sai = 0, 1 -- o trecho da linha que fica dentro da caixa (0 = em A, 1 = em B)
	for _, eixo in { { inicio.X, caminho.X, meio.X }, { inicio.Y, caminho.Y, meio.Y }, { inicio.Z, caminho.Z, meio.Z } } do
		local comeco, passo, limite = eixo[1], eixo[2], eixo[3]
		if math.abs(passo) < 1e-6 then
			if math.abs(comeco) > limite then
				return false -- a linha corre do lado de fora, paralela a este lado da caixa
			end
		else
			local t1, t2 = (-limite - comeco) / passo, (limite - comeco) / passo
			entra = math.max(entra, math.min(t1, t2))
			sai = math.min(sai, math.max(t1, t2))
			if entra > sai then
				return false
			end
		end
	end
	return true
end

-- (OTIMIZADO) A LISTA DAS ZONAS fica guardada: antes, a cada frame, o script procurava todas as zonas
-- do mapa e todas as peças de dentro delas de novo (várias vezes por frame). Agora a lista é refeita
-- só quando uma zona aparece ou some, e a cada 2 segundos (para pegar peças que chegaram depois,
-- como acontece com o StreamingEnabled).
type ListaDeZonas = { zonas: { { raiz: Instance, pecas: { BasePart } } }, feitaEm: number }
local listasDeZonas: { [string]: ListaDeZonas } = {}
local REFAZER_ZONAS_A_CADA = 2 -- (s)

local function zonasDaTag(tag: string): ListaDeZonas
	local lista = listasDeZonas[tag]
	if lista and os.clock() - lista.feitaEm < REFAZER_ZONAS_A_CADA then
		return lista
	end
	local nova: ListaDeZonas = { zonas = {}, feitaEm = os.clock() }
	for _, raiz in CollectionService:GetTagged(tag) do
		local pecas: { BasePart } = {}
		if raiz:IsA("BasePart") then
			table.insert(pecas, raiz)
		end
		for _, peca in raiz:GetDescendants() do
			if peca:IsA("BasePart") then
				table.insert(pecas, peca)
			end
		end
		table.insert(nova.zonas, { raiz = raiz, pecas = pecas })
	end
	listasDeZonas[tag] = nova
	return nova
end

-- Uma zona apareceu ou sumiu: a lista daquela tag é refeita na próxima vez que alguém precisar.
for _, tag in { TAG_ZONA_SEM_GANCHO, TAG_ZONA_SEM_IMPULSO } do
	local function esquecerLista()
		listasDeZonas[tag] = nil
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(esquecerLista)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(esquecerLista)
end

-- A linha de A até B encosta em alguma zona ligada COM ESTA TAG? (Com A = B: o ponto está dentro de uma?)
local function linhaEmZona(tag: string, a: Vector3, b: Vector3): boolean
	for _, zona in zonasDaTag(tag).zonas do
		local raiz = zona.raiz
		if raiz:GetAttribute("Ativa") == false or not raiz:IsDescendantOf(workspace) then
			continue
		end
		for _, peca in zona.pecas do
			if peca.Parent ~= nil and linhaCruzaPeca(peca, a, b) then
				return true
			end
		end
	end
	return false
end

-- A linha de A até B passa por uma zona que proíbe ESTE tipo de gancho?
--   ZonaSemGancho vale para os 3 tipos · ZonaSemImpulso só para o IMPULSO.
local function zonaNoCaminho(a: Vector3, b: Vector3, tipo: string): boolean
	if linhaEmZona(TAG_ZONA_SEM_GANCHO, a, b) then
		return true
	end
	return tipo == "Impulso" and linhaEmZona(TAG_ZONA_SEM_IMPULSO, a, b)
end

-- O quadriciclo está dentro de uma zona que proíbe este tipo de gancho?
local function dentroDeZona(quad: Quadriciclo, tipo: string): boolean
	local posicao = quad.chassi.Position
	return zonaNoCaminho(posicao, posicao, tipo)
end

-- (OTIMIZADO) Os FILTROS dos raios (o que eles ignoram: o seu veículo e você) são criados uma vez,
-- quando você senta, e não a cada frame. (Gancho.ligar cria; Gancho.desligar apaga.)
local filtroSemAgua: RaycastParams? = nil -- mira e "roda no chão" (atravessam a água)
local filtroEscalada: RaycastParams? = nil -- escalada (como antes: a água conta)

local function criarFiltro(quad: Quadriciclo, ignorarAgua: boolean): RaycastParams
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar: { Instance } = { quad.modelo } -- nunca acerta o próprio veículo...
	local personagem = jogadorLocal.Character
	if personagem then
		table.insert(ignorar, personagem) -- ...nem você
	end
	filtro.FilterDescendantsInstances = ignorar
	filtro.IgnoreWater = ignorarAgua
	return filtro
end

-- Cor de "proibido" (ícone e mira). Opcional na Configuracao: GanchoCorProibido.
local function corProibida(quad: Quadriciclo): Color3
	return quad.Config.GanchoCorProibido or COR_PROIBIDO_PADRAO
end

-- Dois raios: o 1º sai da CÂMERA passando no meio da mira (descobre para onde você mira);
-- o 2º sai do CHASSI até esse ponto (o gancho sai do quadriciclo: parede no meio bloqueia).
local function mirarGancho(quad: Quadriciclo): RaycastResult?
	local alcance = alcanceDoTipo(quad, tipoSelecionado) -- (NOVO) cada tipo tem o seu alcance (o SEGURAR é mais curto)
	local camera = Veiculo.cameraAtual()
	local filtro = filtroSemAgua or criarFiltro(quad, true) -- (nunca acerta o próprio veículo, nem você)
	local hud = hudGancho
	local raio: Ray
	if hud then
		local centro = hud.mira.AbsolutePosition + hud.mira.AbsoluteSize / 2
		raio = camera:ScreenPointToRay(centro.X, centro.Y)
	else
		local centro = camera.ViewportSize / 2
		raio = camera:ViewportPointToRay(centro.X, centro.Y)
	end
	-- 1º raio: começa na altura do quadriciclo (pula o trecho entre a câmera e ele).
	local origem = quad.chassi.Position
	local inicio = raio.Origin + raio.Direction * math.max((origem - raio.Origin):Dot(raio.Direction), 0)
	local acertoMira = workspace:Raycast(inicio, raio.Direction * alcance, filtro)
	local pontoMirado = if acertoMira then acertoMira.Position else inicio + raio.Direction * alcance
	-- 2º raio: do Chassi até o ponto mirado, no máximo o alcance do gancho escolhido.
	local caminho = pontoMirado - origem
	if caminho.Magnitude < 1 then
		return nil
	end
	return workspace:Raycast(origem, caminho.Unit * math.min(caminho.Magnitude + 0.5, alcance), filtro)
end

-- Dá para prender o gancho neste acerto da mira? Precisa ser uma peça que segura o gancho, sem zona
-- sem gancho no caminho (e com o quadriciclo fora delas).
local function alvoValido(quad: Quadriciclo, acerto: RaycastResult?): boolean
	if acerto == nil or not podeEnganchar(acerto.Instance, tipoSelecionado) then
		return false
	end
	return not zonaNoCaminho(quad.chassi.Position, acerto.Position, tipoSelecionado) -- (zona que proíbe ESTE gancho)
end

-- =====================================================================
-- (NOVO) TRAVA DA CORDA: a corda trava NA HORA em que o gancho chega
-- =====================================================================
-- O problema: o Servidor mede a corda com a posição ATRASADA do quadriciclo, e a corda só chega
-- aqui depois do atraso da internet. Caindo de um precipício, você continuava caindo nesse meio
-- tempo, e a corda nascia do tamanho da distância de QUANDO ELA CHEGAVA (bem maior): parecia que
-- ela "esticava" e demorava a prender.
-- A solução: o gancho também "voa" AQUI, no seu computador, na mesma velocidade do Servidor
-- (Config.GanchoVelocidadeVoo). No frame em que ele chega no ponto, o seu computador cria uma
-- corda LOCAL travada na distância EXATA daquele instante. Como a física do quadriciclo é calculada
-- no seu computador, ela segura você na hora: vira um pêndulo daquele tamanho, sem esticar mais.
-- Quando a corda de verdade (a do Servidor) chega, ela recebe o MESMO tamanho, é ligada, e a
-- local some. (Só no CENÁRIO: IMPULSO e SEGURAR. Em jogador e em botão não existe corda.)
type MeuGancho = {
	parte: BasePart, -- a peça do cenário que o gancho acertou
	ponto: Vector3, -- o ponto do impacto (no mundo)
	percorrido: number, -- quantos studs o gancho já voou aqui no seu computador
	inicio: number, -- os.clock() do disparo
	terminou: boolean, -- o voo daqui já terminou? (a corda travou, ou o alvo sumiu, ou o tempo acabou)
}
local TEMPO_MAX_VOO = 3 -- (s) o mesmo limite do Servidor: se não chegar nesse tempo, errou
local meuGancho: MeuGancho? = nil -- o seu gancho no cenário agora (nil = nenhum)
local cordaLocal: RopeConstraint? = nil -- a corda que o SEU computador travou (até a do Servidor chegar)

-- O Attachment de onde a corda sai: o "SaidaGancho" do quadriciclo (o Servidor cria um, se faltar).
local function saidaDaCorda(quad: Quadriciclo): Attachment?
	local achada = quad.modelo:FindFirstChild("SaidaGancho", true)
	if achada and achada:IsA("Attachment") then
		return achada
	end
	return nil
end

-- Apaga a corda local (e o Attachment que ela usava na peça do cenário).
local function apagarCordaLocal()
	local corda = cordaLocal
	cordaLocal = nil
	if corda then
		local ponta = corda.Attachment1
		corda:Destroy()
		if ponta then
			ponta:Destroy()
		end
	end
end

-- Esquece o seu gancho no cenário (você soltou, ele errou ou o Servidor recusou).
local function esquecerMeuGancho()
	apagarCordaLocal()
	meuGancho = nil
end

-- Chamada a cada frame pelo atualizarGancho: o gancho voa aqui e, quando chega, a corda TRAVA.
local function voarMeuGancho(quad: Quadriciclo, dt: number)
	local gancho = meuGancho
	if gancho == nil or gancho.terminou or enviadoEm == nil then
		return -- nenhum gancho no cenário voando agora
	end
	local saida = saidaDaCorda(quad)
	if saida == nil or not gancho.parte:IsDescendantOf(workspace) or os.clock() - gancho.inicio > TEMPO_MAX_VOO then
		gancho.terminou = true -- o alvo sumiu ou demorou demais: para de voar aqui (o Servidor decide se errou)
		return
	end
	gancho.percorrido += quad.Config.GanchoVelocidadeVoo * dt
	local distancia = (gancho.ponto - saida.WorldPosition).Magnitude
	if gancho.percorrido < distancia then
		return -- ainda voando
	end
	-- CHEGOU: a corda trava AGORA, no tamanho exato desta distância.
	gancho.terminou = true
	local ponta = Instance.new("Attachment")
	ponta.Name = "PontaGanchoLocal"
	ponta.Position = gancho.parte.CFrame:PointToObjectSpace(gancho.ponto) -- "grudado" na peça atingida
	ponta.Parent = gancho.parte
	local corda = Instance.new("RopeConstraint")
	corda.Name = "CordaGanchoLocal" -- (nome diferente da corda do Servidor)
	corda.Attachment0 = saida
	corda.Attachment1 = ponta
	corda.Length = math.max(distancia, quad.Config.GanchoComprimentoMinimo)
	corda.Restitution = 0 -- não quica quando estica
	corda.Visible = false -- (a corda que todo mundo vê é desenhada pelo visual do gancho)
	corda.Parent = quad.chassi
	cordaLocal = corda
end

-- A corda de verdade (a do Servidor) chegou. Ela nasce DESLIGADA: aqui ela recebe o tamanho TRAVADO
-- (o mesmo da corda local) e só então é ligada. Se ela chegar ANTES do voo daqui terminar, trava na
-- distância deste instante. Corda velha (de um gancho que você já soltou) continua desligada.
local function ajustarCordaDoGancho(quad: Quadriciclo, objeto: Instance)
	if not (objeto:IsA("RopeConstraint") and objeto.Name == NOME_CORDA_GANCHO) then
		return
	end
	local limite = os.clock() + 1
	while (objeto.Attachment0 == nil or objeto.Attachment1 == nil) and os.clock() < limite do
		task.wait() -- espera os dois Attachments chegarem pela internet
	end
	local a0, a1 = objeto.Attachment0, objeto.Attachment1
	local gancho = meuGancho
	-- É a corda do gancho que você lançou AGORA? (o mesmo ponto do impacto, com 2 studs de folga)
	if a0 == nil or a1 == nil or gancho == nil or (a1.WorldPosition - gancho.ponto).Magnitude > 2 then
		return
	end
	local travada = cordaLocal
	if travada then
		objeto.Length = travada.Length -- o MESMO tamanho da corda local (o carretel do IMPULSO pode ter encurtado)
	else
		objeto.Length = math.max((a1.WorldPosition - a0.WorldPosition).Magnitude, quad.Config.GanchoComprimentoMinimo)
	end
	gancho.terminou = true -- (se ainda estava voando aqui, para: já travou)
	objeto.Enabled = true -- liga a corda de verdade, já com o tamanho certo (sem tranco)...
	apagarCordaLocal() -- ...e a local some
end

-- Um "pedaço" do desenho: barra de pontas redondas (ou bolinha) centralizada na posição.
local function pedacoGancho(pai: Instance, tamanho: UDim2, posicao: UDim2, rotacao: number?): Frame
	local pedaco = Instance.new("Frame")
	pedaco.AnchorPoint = Vector2.new(0.5, 0.5)
	pedaco.Size = tamanho
	pedaco.Position = posicao
	pedaco.Rotation = rotacao or 0
	pedaco.BackgroundColor3 = Color3.new(1, 1, 1)
	pedaco.BorderSizePixel = 0
	local canto = Instance.new("UICorner")
	canto.CornerRadius = UDim.new(1, 0)
	canto.Parent = pedaco
	pedaco.Parent = pai
	return pedaco
end

local function contornoGancho(pai: Instance, cor: Color3, espessura: number): UIStroke
	local contorno = Instance.new("UIStroke")
	contorno.Color = cor
	contorno.Thickness = espessura
	contorno.Parent = pai
	return contorno
end

-- Cria UM ícone da barra: o círculo com o desenho do gancho, a recarga, a tecla e o nome embaixo.
-- O ícone inteiro é um botão: clicar (ou tocar, no celular) escolhe este gancho.
local function criarIconeDaBarra(quad: Quadriciclo, barra: Frame, tipo: TipoDeGancho, ordem: number): IconeDaBarra
	local Config = quad.Config
	local tamanho = Config.GanchoIconeTamanho
	local branco = Color3.new(1, 1, 1)
	local caixa = Instance.new("Frame") -- o círculo em cima e o nome embaixo
	caixa.Name = "Gancho" .. tipo.id
	caixa.LayoutOrder = ordem -- a posição na barra (1, 2, 3...)
	caixa.Size = UDim2.fromOffset(tamanho, tamanho + 18)
	caixa.BackgroundTransparency = 1
	caixa.Parent = barra
	local escala = Instance.new("UIScale") -- deixa o gancho escolhido um pouco maior
	escala.Parent = caixa
	local icone = Instance.new("CanvasGroup") -- o círculo
	icone.Size = UDim2.fromOffset(tamanho, tamanho)
	icone.BackgroundColor3 = Color3.fromRGB(28, 30, 36)
	icone.BackgroundTransparency = 0.15
	icone.BorderSizePixel = 0
	local redondo = Instance.new("UICorner")
	redondo.CornerRadius = UDim.new(1, 0) -- redondo: corta tudo que está dentro em círculo
	redondo.Parent = icone
	icone.Parent = caixa
	local imagem = imagemDoTipo(quad, tipo.id)
	if imagem ~= "" then
		-- SUA imagem (Configuracao). Prefira uma imagem branca/clara: a cor de cada estado pinta por cima.
		local figura = Instance.new("ImageLabel")
		figura.AnchorPoint = Vector2.new(0.5, 0.5)
		figura.Position = UDim2.fromScale(0.5, 0.5)
		figura.Size = UDim2.fromScale(0.72, 0.72)
		figura.BackgroundTransparency = 1
		figura.Image = imagem
		figura.ScaleType = Enum.ScaleType.Fit
		figura.Parent = icone
	else
		-- Sem imagem: usa o emoji do tipo (🚀, ⚓ ou 👆).
		local desenho = Instance.new("TextLabel")
		desenho.AnchorPoint = Vector2.new(0.5, 0.5)
		desenho.Position = UDim2.fromScale(0.5, 0.5)
		desenho.Size = UDim2.fromScale(0.66, 0.66)
		desenho.BackgroundTransparency = 1
		desenho.Text = tipo.emoji
		desenho.TextScaled = true
		desenho.Parent = icone
	end
	local sombra = Instance.new("Frame") -- cortina escura da recarga
	sombra.AnchorPoint = Vector2.new(0, 1)
	sombra.Position = UDim2.fromScale(0, 1)
	sombra.Size = UDim2.fromScale(1, 0)
	sombra.BackgroundColor3 = Color3.new(0, 0, 0)
	sombra.BackgroundTransparency = 0.45
	sombra.BorderSizePixel = 0
	sombra.Parent = icone
	-- Anel por fora do círculo (fora do CanvasGroup, para ficar com a cor exata do estado).
	local centro = UDim2.fromOffset(tamanho / 2, tamanho / 2)
	local aro = pedacoGancho(caixa, UDim2.fromOffset(tamanho, tamanho), centro)
	aro.BackgroundTransparency = 1
	local anel = contornoGancho(aro, Config.GanchoCorPronto, 2)
	-- Risco de "proibido" por cima do círculo (aparece dentro de uma zona sem gancho).
	local proibido = pedacoGancho(caixa, UDim2.fromOffset(tamanho * 0.11, tamanho * 1.04), centro, -45) -- "\" como na placa
	proibido.Name = "Proibido"
	proibido.BackgroundColor3 = corProibida(quad)
	proibido.Visible = false
	local tempo = Instance.new("TextLabel") -- segundos que faltam da recarga
	tempo.Size = UDim2.fromOffset(tamanho, tamanho)
	tempo.BackgroundTransparency = 1
	tempo.Font = Enum.Font.GothamBlack
	tempo.TextSize = math.floor(tamanho * 0.42)
	tempo.TextColor3 = branco
	tempo.TextStrokeTransparency = 0.2
	tempo.Visible = false
	tempo.Parent = caixa
	local nome = Instance.new("TextLabel") -- o nome embaixo do círculo
	nome.AnchorPoint = Vector2.new(0.5, 1)
	nome.Position = UDim2.fromScale(0.5, 1)
	nome.Size = UDim2.new(1, 24, 0, 16)
	nome.BackgroundTransparency = 1
	nome.Font = Enum.Font.GothamBlack
	nome.Text = tipo.nome
	nome.TextSize = 13
	nome.TextColor3 = branco
	nome.TextStrokeTransparency = 0.3
	nome.Parent = caixa
	if UserInputService.KeyboardEnabled then -- etiqueta com a tecla (1, 2, 3) no canto (só para quem tem teclado)
		local tecla = Instance.new("TextLabel")
		tecla.AnchorPoint = Vector2.new(0.5, 0.5)
		tecla.Position = UDim2.fromOffset(tamanho * 0.14, tamanho * 0.14)
		tecla.Size = UDim2.fromOffset(22, 22)
		tecla.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
		tecla.Font = Enum.Font.GothamBlack
		tecla.Text = tostring(ordem)
		tecla.TextSize = 14
		tecla.TextColor3 = Color3.fromRGB(25, 25, 30)
		local canto = Instance.new("UICorner")
		canto.CornerRadius = UDim.new(0, 6)
		canto.Parent = tecla
		tecla.Parent = caixa
	end
	-- Botão invisível por cima de tudo: clicar ou tocar no ícone escolhe este gancho.
	local botao = Instance.new("TextButton")
	botao.Size = UDim2.fromScale(1, 1)
	botao.BackgroundTransparency = 1
	botao.AutoButtonColor = false
	botao.Text = ""
	botao.ZIndex = 5
	botao.Parent = caixa
	botao.Activated:Connect(function()
		tipoSelecionado = tipo.id
	end)
	return {
		tipo = tipo.id, caixa = caixa, escala = escala, icone = icone, anel = anel, sombra = sombra,
		tempo = tempo, proibido = proibido, nome = nome, cor = Config.GanchoCorPronto, tremidas = 0,
	}
end

local function criarHudGancho(quad: Quadriciclo)
	local Config = quad.Config
	local playerGui = jogadorLocal:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local branco = Color3.new(1, 1, 1)
	local tela = Instance.new("ScreenGui")
	tela.Name = "HUDGancho"
	tela.ResetOnSpawn = false
	tela.DisplayOrder = 10 -- por cima do HUDQuadriciclo
	tela.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- BARRA DE GANCHOS: os ícones lado a lado, no lugar da Configuracao (GanchoIconePosicao).
	local barra = Instance.new("Frame")
	barra.Name = "BarraDeGanchos"
	barra.AnchorPoint = Vector2.new(0.5, 1) -- o "ponto de apoio" é o meio da borda de baixo
	barra.Position = Config.GanchoIconePosicao
	barra.Size = UDim2.fromOffset(0, 0)
	barra.AutomaticSize = Enum.AutomaticSize.XY -- o tamanho vem dos ícones (cresce sozinha)
	barra.BackgroundTransparency = 1
	barra.Parent = tela
	Tela.encolher(barra) -- (NOVO) no celular a barra fica menor (encolhe em volta do meio de baixo)
	local fila = Instance.new("UIListLayout") -- um ícone ao lado do outro, na ordem 1, 2, 3
	fila.FillDirection = Enum.FillDirection.Horizontal
	fila.HorizontalAlignment = Enum.HorizontalAlignment.Center
	fila.VerticalAlignment = Enum.VerticalAlignment.Bottom
	fila.SortOrder = Enum.SortOrder.LayoutOrder
	fila.Padding = UDim.new(0, 14)
	fila.Parent = barra
	local icones: { IconeDaBarra } = {}
	for ordem, tipo in TIPOS_DE_GANCHO do
		table.insert(icones, criarIconeDaBarra(quad, barra, tipo, ordem))
	end
	-- MIRA no meio da tela: só aparece enquanto você mira (o gancho vai bem no centro dela).
	local mira = Instance.new("CanvasGroup") -- (CanvasGroup: o GroupColor3 pinta a mira inteira)
	mira.Name = "MiraGancho"
	mira.AnchorPoint = Vector2.new(0.5, 0.5)
	mira.Position = UDim2.fromScale(0.5, 0.5)
	mira.Size = UDim2.fromOffset(40, 40)
	mira.BackgroundTransparency = 1
	mira.Visible = false
	mira.Parent = tela
	local aroMira = pedacoGancho(mira, UDim2.fromOffset(18, 18), UDim2.fromScale(0.5, 0.5))
	aroMira.BackgroundTransparency = 1
	contornoGancho(aroMira, branco, 2).Transparency = 0.15
	-- ponto do meio + 4 risquinhos: { largura, altura, deslocamento X, deslocamento Y }
	for _, r in { { 4, 4, 0, 0 }, { 3, 9, 0, -15 }, { 3, 9, 0, 15 }, { 9, 3, -15, 0 }, { 9, 3, 15, 0 } } do
		local risco = pedacoGancho(mira, UDim2.fromOffset(r[1], r[2]), UDim2.new(0.5, r[3], 0.5, r[4]))
		contornoGancho(risco, Color3.new(0, 0, 0), 1).Transparency = 0.35 -- contorno escuro: aparece no céu claro
	end
	-- (NOVO) SONS que só você ouve: o de "ainda está recarregando" de cada tipo (GanchoSomRecarga...).
	local sons: { [string]: Sound } = {}
	for _, tipo in TIPOS_DE_GANCHO do
		local som = Instance.new("Sound")
		som.Name = "SomRecarga" .. tipo.id
		som.SoundId = somDoTipo(Config, "Recarga", tipo.id)
		som.Volume = 0.6
		som.Parent = tela -- dentro da tela: toca só para você, sem depender de distância
		sons["Recarga" .. tipo.id] = som
	end
	tela.Parent = playerGui
	hudGancho = { tela = tela, icones = icones, mira = mira, sons = sons }
	ultimoEscolhido = tipoSelecionado -- (acabou de sentar: não conta como "trocou de gancho")
end

local function destruirHudGancho()
	local hud = hudGancho
	if hud then
		hud.tela:Destroy()
	end
	hudGancho = nil
end

-- Toca um dos sons do HUD (só você ouve). Ex.: tocarSomDoHud("RecargaImpulso").
local function tocarSomDoHud(nome: string)
	local hud = hudGancho
	local som = if hud then hud.sons[nome] else nil
	if som and som.SoundId ~= "" then
		som:Play()
	end
end

-- O ícone deste gancho "nega": balança para os lados e pisca na cor de proibido (o atualizarGancho
-- volta para a cor certa sozinho, suave). Acontece quando você tenta usar (ou escolhe) um gancho que
-- ainda está recarregando, numa zona onde ele não funciona, ou mirando no que ele não pega.
local BALANCO_DA_TREMIDA = { -14, 14, -11, 11, -7, 7, -3, 0 } -- (graus) a ida e volta, cada vez menor
local function tremerIconeGancho(quad: Quadriciclo, id: string)
	local hud = hudGancho
	if hud == nil then
		return
	end
	for _, item in hud.icones do
		if item.tipo ~= id then
			continue
		end
		item.cor = corProibida(quad) -- pisca vermelho
		item.tremidas += 1
		local minhaTremida = item.tremidas
		task.spawn(function()
			for _, angulo in BALANCO_DA_TREMIDA do
				if item.tremidas ~= minhaTremida then
					return -- começou outra tremida no meio desta: esta para aqui
				end
				item.caixa.Rotation = angulo
				task.wait(0.035)
			end
		end)
	end
end

-- Este gancho ainda está RECARREGANDO: o ícone dele treme e toca o som de recarga DELE.
local function avisarRecarga(quad: Quadriciclo, id: string)
	tremerIconeGancho(quad, id)
	tocarSomDoHud("Recarga" .. id)
end

-- Solta o gancho que está no ar ou preso (clicou para soltar, apertou L1 de novo, ou saiu do banco).
local function soltarMeuGancho(quad: Quadriciclo)
	esquecerMeuGancho() -- (NOVO) apaga a corda que o seu computador travou (se tiver)
	local tipo = tipoAtivo
	if enviadoEm == nil or tipo == nil then
		return
	end
	local estadoServidor = quad.modelo:GetAttribute("GanchoEstado")
	if estadoServidor == "NoAr" or estadoServidor == "Preso" then
		-- o ícone deste tipo já mostra a recarga (o Servidor confirma logo depois)
		recargaPrevista[tipo] = workspace:GetServerTimeNow() + recargaDoTipo(quad, tipo)
	end
	Veiculo.avisarServidor(quad, "GanchoDesliga")
	enviadoEm = nil
	tipoAtivo = nil
end

-- ---------- ESCALADA: gancho preso + as 4 rodas encostadas = o carro gruda na superfície ----------
-- A "gravidade" passa a puxar para a superfície embaixo das rodas, então dá para subir parede e
-- rampa bem inclinada. Entra com as 4 rodas encostadas e continua com pelo menos 2 (passa por
-- quinas). Funciona melhor quando a parede tem uma curva/rampa na base.
local escalando = false
local forcaEscalada: VectorForce? = nil

local function pegarForcaEscalada(quad: Quadriciclo): VectorForce
	local existente = forcaEscalada
	if existente then
		return existente
	end
	local anexo = Instance.new("Attachment")
	anexo.Name = "EscaladaGancho"
	anexo.Parent = quad.chassi
	local forca = Instance.new("VectorForce") -- só neste computador: a física do quadriciclo é sua
	forca.Name = "EscaladaGancho"
	forca.Attachment0 = anexo
	forca.RelativeTo = Enum.ActuatorRelativeTo.World
	forca.ApplyAtCenterOfMass = true
	forca.Parent = quad.chassi
	forcaEscalada = forca
	return forca
end

local function apagarEscalada()
	local forca = forcaEscalada
	if forca then
		local anexo = forca.Attachment0
		forca:Destroy()
		if anexo then
			anexo:Destroy()
		end
	end
	forcaEscalada = nil
	escalando = false
end

-- (NOVO) Esta peça (ou o Model/Folder onde ela está) tem a tag "ParedeEscalavel"?
local function escalavel(peca: Instance): boolean
	local atual: Instance? = peca
	while atual and atual ~= workspace do
		if CollectionService:HasTag(atual, TAG_PAREDE_ESCALAVEL) then
			return true
		end
		atual = atual.Parent -- sobe para o Model/Folder de cima
	end
	return false
end


local function atualizarEscalada(quad: Quadriciclo, presoAgora: boolean)
	local encostadas, somaNormais = 0, Vector3.zero
	if presoAgora and quad.Config.GanchoEscalada and #quad.rodas > 0 then
		-- Cada roda olha "para baixo" (do ponto de vista do carro): está encostada em alguma coisa?
		local baixo = -Veiculo.referencia(quad).UpVector
		local filtro = filtroEscalada or criarFiltro(quad, false)
		for _, info in quad.rodas do
			local acerto = workspace:Raycast(info.roda.Position, baixo * (info.raio + 0.8), filtro)
			if acerto and escalavel(acerto.Instance) then -- (NOVO) só conta superfície com a tag ParedeEscalavel
				encostadas += 1
				somaNormais += acerto.Normal
			end
		end
	end
	escalando = somaNormais.Magnitude > 0.1 and encostadas >= (if escalando then 2 else #quad.rodas)
	if not escalando then
		local forca = forcaEscalada
		if forca then
			forca.Enabled = false
		end
		return
	end
	local massa = quad.chassi.AssemblyMass
	for _, info in quad.rodas do
		massa += info.manga.AssemblyMass + info.roda.AssemblyMass
	end
	-- Anula a gravidade de verdade e coloca uma igual puxando para a superfície (normal média).
	local forca = pegarForcaEscalada(quad)
	forca.Force = massa * workspace.Gravity * (Vector3.yAxis - somaNormais.Unit)
	forca.Enabled = true
end

-- ---------- GANCHO DE IMPULSO: puxão, pêndulo, estilingue e pouso ----------
-- Vale com o gancho de IMPULSO preso no cenário (é lá que existe a corda de verdade):
--   PUXÃO ........ no chão, o gancho PUXA o quadriciclo até o ponto (as rodas ficam soltas). Se ele sair
--                  do chão com o ponto mais na FRENTE do que em cima, o puxão continua pelo ar, quase
--                  sem gravidade, até chegar.
--   PÊNDULO ...... se sair do chão com o ponto bem ACIMA (ex.: um galho em cima do precipício), vira um
--                  balanço: segurando GÁS o balanço aumenta a cada ida e volta; FREIO faz ele parar.
--   CARRETEL ..... nos dois, a corda recolhe a folga sozinha (fica sempre esticada).
--   ESTILINGUE ... chegou perto do ponto (puxão) ou clicou para soltar = solta com um impulso para onde
--                  estava indo, um pouco para cima. No pêndulo, solte na SUBIDA do balanço para ir mais longe!
--   POUSO ........ depois do estilingue, o quadriciclo se endireita no ar e vira de frente para onde
--                  está indo, para cair de rodas no chão.
-- Os números ficam na Configuracao (GanchoImpulso... e GanchoBalanco...).
local TEMPO_NO_AR = 0.15 -- (s) no ar há pelo menos isso = saiu do chão de verdade (pulinho de lombada não conta)
local CORDA_MINIMA = 10 -- (studs) o carretel nunca deixa a corda menor que isso
local SENO_PENDULO = 0.6 -- saiu do chão com o ponto mais alto que isso (uns 37° para cima) = vira PÊNDULO
local MENOS_GRAVIDADE = 0.85 -- no puxão pelo ar, 85% da gravidade some: o quadriciclo voa quase reto
local MIRA_ACIMA = 5 -- (studs) o puxão mira um pouco ACIMA do ponto, para você chegar por cima da beirada
local RESPOSTA_PUXAO = 5 -- quão rápido o puxão corrige a direção (maior = mais "trilho", menor = mais solto)
local TEMPO_MAXIMO_POUSO = 2 -- (s) o pouso desliga sozinho depois disso, mesmo sem tocar no chão
local modoImpulso: string? = nil -- "Puxao" (no chão), "PuxaoNoAr", "Pendulo" ou nil (o impulso não está preso)
local inicioPuxao = 0 -- (os.clock) quando o gancho de impulso prendeu
local tempoNoAr = 0 -- (s) há quanto tempo nenhuma roda tem chão embaixo
local direcaoDecolagem: Vector3? = nil -- para onde estava o ponto no instante em que você saiu do chão
local forcaImpulso: VectorForce? = nil -- a força do puxão e do embalo (só neste computador: a física é sua)
local alinharPouso: AlignOrientation? = nil -- o "endireitador" do pouso
local pousoAte = 0 -- (os.clock) até quando o pouso fica ligado
-- (NOVO) BALANÇO ARCADE: pendurado, quem move o quadriciclo é um pêndulo simples (não a física de verdade).
-- Os números de verdade ficam na ConfiguracaoPadrao (BalancoGravidade, BalancoForca...): mude lá, ou na
-- Configuracao de um veículo. Os daqui embaixo são só a "reserva" (valem se a Configuracao não tiver).
local BALANCO_GRAVIDADE = 55 -- (BalancoGravidade) studs/s²: menor = balança mais devagar (a de verdade é 196)
local BALANCO_FORCA = 42 -- (BalancoForca) studs/s²: quanto W/A/S/D empurram
local BALANCO_VELOCIDADE_MAXIMA = 55 -- (BalancoVelocidadeMaxima) studs/s: o mais rápido que ele balança
local BALANCO_AMORTECIMENTO = 0.35 -- (BalancoAmortecimento) por segundo: sem tecla, o balanço diminui devagar
local BALANCO_INCLINACAO = 25 -- (BalancoInclinacao) graus: o nariz fica levantado enquanto está pendurado
local BALANCO_ALTURA_LIMITE = -0.15 -- o mais alto que ele sobe (-1 = embaixo do gancho · 0 = na altura dele)
local BALANCO_CORDA_MINIMA, BALANCO_CORDA_MAXIMA = 8, 60 -- (studs) tamanho da corda no balanço
-- (NOVO) BALANÇO MAIS GOSTOSO (mude aqui, ou coloque na Configuracao com o nome entre parênteses):
local BALANCO_EMBALO = 1.6 -- (BalancoEmbalo) lá EMBAIXO o empurrão das teclas vale até 1.6× (1 = desliga)
local BALANCO_FLUTUAR = 0.4 -- (BalancoFlutuar) lá no ALTO o balanço fica em câmera lenta (0 = desliga · máximo 0.9)
local BALANCO_INCLINAR_LADO = 22 -- (BalancoInclinarLado) graus: indo de lado, ele deita para aquele lado (0 = desliga)
local BALANCO_PERFEITO = 0.7 -- (BalancoPerfeito) PERFEITO = soltar SUBINDO com mais de 70% da velocidade máxima
local BALANCO_BONUS_PERFEITO = 1.3 -- (BalancoBonusPerfeito) no PERFEITO ele sai 30% mais rápido...
local BALANCO_PULO_PERFEITO = 18 -- (BalancoPuloPerfeito) ...e com esse tanto (studs/s) a mais para cima
local SOM_DO_VENTO = "rbxasset://sounds/action_falling.mp3" -- o vento (o mesmo de quando o boneco cai de bem alto)
local SOM_DO_PERFEITO = "" -- (opcional) o id de um som de "acerto", por exemplo "rbxassetid://1234567"
local COR_RASTRO = ColorSequence.new(Color3.fromRGB(255, 255, 255)) -- o rastro normal (branco)
local COR_RASTRO_PERFEITO = ColorSequence.new(Color3.fromRGB(255, 205, 60)) -- o rastro na hora do PERFEITO (dourado)
-- (NOVO) BALANÇO MAIS SOLTO E SEM BUG NA PAREDE (mude aqui, ou na Configuracao com o nome entre parênteses):
local BALANCO_ELASTICO = 0.07 -- (BalancoElastico) no puxão mais forte a corda estica até 7% e volta, como elástico (0 = desliga)
local BALANCO_SOLTURA = 0.6 -- (BalancoSoltura) quanto o corpo deita junto com a corda (0 = sempre reto · 1 = todo na direção da corda)
local BALANCO_MOLA_DO_CORPO = 25 -- (BalancoMolaDoCorpo) a "mola" que faz o corpo balançar atrás da corda (maior = mais firme)
local BALANCO_QUIQUE = 0.3 -- (BalancoQuique) quanto ele quica ao bater numa parede (0 = não quica · 0.6 = bola de borracha)
local BALANCO_CHUTE_PAREDE = 25 -- (BalancoChuteParede) (studs/s) encostado numa parede, empurrar para longe dela dá um chute (0 = desliga)

type Balanco = {
	ancora: Vector3, -- onde o gancho prendeu
	bola: Vector3, -- onde a FRENTE do quadriciclo deve estar agora (o "peso" do pêndulo)
	velocidade: Vector3, -- a velocidade do balanço
	comprimento: number, -- o tamanho da corda
	frente: Vector3, -- para onde o quadriciclo está virado (deitado, sem o sobe e desce)
	inclinacaoDeLado: number, -- quanto ele está deitado de lado agora (em radianos)
	naJanela: boolean, -- está na "janela do PERFEITO" agora? (rápido e subindo)
	vento: Sound, -- o som do vento
	rastro: Trail, -- a fita que desenha o arco do balanço
	pontasDoRastro: { Attachment }, -- os 2 pontos de onde a fita sai
	cordas: { Beam }, -- os pedaços da corda desenhada (brilham no PERFEITO)
	larguraDaCorda: number, -- a grossura normal da corda (para voltar ao normal depois)
	massa: number, -- (NOVO) o peso do quadriciclo inteiro
	cimaAtual: Vector3, -- (NOVO) o "cima" do corpo agora (balança atrás da corda, como uma mola)
	cimaVelocidade: Vector3, -- (NOVO) a velocidade dessa mola
	esticar: number, -- (NOVO) quanto a corda está esticada agora (studs)
	esticarVelocidade: number, -- (NOVO) a velocidade desse esticar
	raioDoCorpo: number, -- (NOVO) o tamanho da "bola" que sente as paredes
	filtroParede: RaycastParams, -- (NOVO) quem a bola ignora (o próprio quadriciclo e o seu boneco)
	parede: Vector3?, -- (NOVO) a direção "para fora" da parede encostada (nil = longe de paredes)
	paredeAte: number, -- (NOVO) (os.clock) até quando conta como encostado
	chutePronto: number, -- (NOVO) (os.clock) a partir de quando pode chutar a parede de novo
	ultimaBatida: number, -- (NOVO) (os.clock) a última batida com tranco (para não tremer sem parar)
}
local balanco: Balanco? = nil -- nil = não está balançando
local penduradoAgora = false -- true = balançando neste frame (o balancar marca a cada frame)
local alinharBalanco: AlignPosition? = nil -- leva a frente do quadriciclo até a "bola" do pêndulo


-- Massa do quadriciclo inteiro: Chassi (com o Banco e você) + as Mangas + as Rodas.
local function massaTotal(quad: Quadriciclo): number
	local massa = quad.chassi.AssemblyMass
	for _, info in quad.rodas do
		massa += info.manga.AssemblyMass + info.roda.AssemblyMass
	end
	return massa
end

-- A corda de verdade do gancho: a "CordaGancho" do Servidor, quando ela já chegou e está LIGADA.
-- (NOVO) Enquanto ela não chega, vale a corda que o SEU computador travou na hora (cordaLocal).
local function cordaDoGancho(quad: Quadriciclo): RopeConstraint?
	local achada = quad.chassi:FindFirstChild(NOME_CORDA_GANCHO)
	if achada and achada:IsA("RopeConstraint") and achada.Enabled then
		return achada :: RopeConstraint -- (o "::" só confirma o tipo para o Studio: o IsA já conferiu)
	end
	return cordaLocal
end

-- Alguma roda tem chão logo embaixo dela? (um raio para BAIXO saindo do meio de cada roda)
-- (Não conta o próprio veículo nem você; passar por cima de um rio também vale.)
local function rodaNoChao(quad: Quadriciclo): boolean
	local filtro = filtroSemAgua or criarFiltro(quad, true)
	for _, info in quad.rodas do
		if workspace:Raycast(info.roda.Position, Vector3.new(0, -(info.raio + 1), 0), filtro) then
			return true
		end
	end
	return false
end

-- Cria (só na primeira vez) a força do puxão e do embalo, empurrando pelo centro do quadriciclo.
local function pegarForcaImpulso(quad: Quadriciclo): VectorForce
	local existente = forcaImpulso
	if existente then
		return existente
	end
	local anexo = Instance.new("Attachment")
	anexo.Name = "ImpulsoGancho"
	anexo.Parent = quad.chassi
	local forca = Instance.new("VectorForce")
	forca.Name = "ImpulsoGancho"
	forca.Attachment0 = anexo
	forca.RelativeTo = Enum.ActuatorRelativeTo.World -- a direção é a do mundo (não gira junto com o carro)
	forca.ApplyAtCenterOfMass = true -- empurra pelo centro: não faz o quadriciclo rodopiar
	forca.Enabled = false
	forca.Parent = quad.chassi
	forcaImpulso = forca
	return forca
end

-- Cria (só na primeira vez) o "endireitador" do pouso. O Attachment dele fica virado igual ao Banco,
-- então a "frente" e o "cima" dele são a frente e o teto do quadriciclo.
local function pegarAlinharPouso(quad: Quadriciclo): AlignOrientation
	local existente = alinharPouso
	if existente then
		return existente
	end
	local anexo = Instance.new("Attachment")
	anexo.Name = "PousoGancho"
	anexo.CFrame = quad.chassi.CFrame:ToObjectSpace(Veiculo.referencia(quad)) -- no meio do Chassi, girado igual ao Banco
	anexo.Parent = quad.chassi
	local alinhar = Instance.new("AlignOrientation")
	alinhar.Name = "PousoGancho"
	alinhar.Mode = Enum.OrientationAlignmentMode.OneAttachment -- gira até o CFrame que a gente escolher
	alinhar.AlignType = Enum.AlignType.AllAxes -- acerta tudo: frente, lados e teto
	alinhar.Attachment0 = anexo
	alinhar.MaxTorque = 60000 -- força para girar (sobra: o quadriciclo é leve)
	alinhar.Responsiveness = 12 -- rapidez da virada (maior = vira mais rápido e mais "seco")
	alinhar.Enabled = false
	alinhar.Parent = quad.chassi
	alinharPouso = alinhar
	return alinhar
end

-- Para onde o quadriciclo olha no pouso: em pé (teto para cima) e de frente para onde está indo
-- (sem contar o sobe e desce). Quase parado? Fica com a frente que já tem.
local function direcaoDoPouso(quad: Quadriciclo): CFrame
	local velocidade = quad.chassi.AssemblyLinearVelocity
	local frente = Vector3.new(velocidade.X, 0, velocidade.Z)
	if frente.Magnitude < 1 then
		local olhar = Veiculo.referencia(quad).LookVector
		frente = Vector3.new(olhar.X, 0, olhar.Z)
	end
	if frente.Magnitude < 0.01 then
		frente = Vector3.new(0, 0, -1) -- (caso raro: parado e de nariz bem para cima)
	end
	return CFrame.lookAt(Vector3.zero, frente)
end

-- (NOVO) Saiu do balanço (soltou, encostou no chão, o gancho saiu ou saiu do banco): a física normal volta
-- a mandar, e os efeitos do balanço (vento, rastro e o brilho da corda) somem devagar.
local function sairDoBalanco()
	local estado = balanco
	balanco = nil
	local alinhar = alinharBalanco
	if alinhar then
		alinhar.Enabled = false
	end
	local giro = alinharPouso
	if giro then
		giro.Responsiveness = 12 -- (a rapidez normal do pouso)
		if os.clock() > pousoAte then
			giro.Enabled = false -- (se o pouso não estiver usando ele agora)
		end
	end
	if estado == nil then
		return -- (não estava balançando: não tem efeito para apagar)
	end
	-- O vento abaixa em 0,35 s e a fita para de crescer (o pedaço que já foi desenhado some sozinho).
	TweenService:Create(estado.vento, TweenInfo.new(0.35), { Volume = 0 }):Play()
	estado.rastro.Enabled = false
	-- Meio segundo depois (quando já sumiu tudo), apaga o som, a fita e os 2 pontos dela.
	local vento, rastro, pontas = estado.vento, estado.rastro, estado.pontasDoRastro
	task.delay(0.5, function()
		vento:Destroy()
		rastro:Destroy()
		for _, ponta in pontas do
			ponta:Destroy()
		end
	end)
	-- A corda desenhada volta ao normal (sem brilho e com a grossura de sempre).
	for _, pedaco in estado.cordas do
		pedaco.Width0 = estado.larguraDaCorda
		pedaco.Width1 = estado.larguraDaCorda
		pedaco.LightEmission = 0
	end
end

-- (NOVO) A tela do aviso "PERFEITO!" (criada só na primeira vez que precisa).
local telaDoPerfeito: ScreenGui? = nil
local function pegarTelaDoPerfeito(): ScreenGui?
	local existente = telaDoPerfeito
	if existente and existente.Parent then
		return existente
	end
	local jogador = game:GetService("Players").LocalPlayer
	local playerGui = if jogador then jogador:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil then
		return nil
	end
	local tela = Instance.new("ScreenGui")
	tela.Name = "AvisoPerfeito"
	tela.ResetOnSpawn = false -- (não some quando o personagem renasce)
	tela.IgnoreGuiInset = true
	tela.DisplayOrder = 6 -- por cima do HUD
	tela.Parent = playerGui
	telaDoPerfeito = tela
	return tela
end

-- (NOVO) PERFEITO!: soltou o balanço na hora certa. A tela dá um tranco, estrelinhas douradas estouram,
-- "PERFEITO!" pula na tela e (se você colocou um em SOM_DO_PERFEITO) toca um som.
local function comemorarPerfeito(quad: Quadriciclo)
	-- 1) O TRANCO na tela (0.3 já é bem forte).
	CameraModulo.tremer(0.2)

	-- 2) As ESTRELINHAS: a imagem padrão do ParticleEmitter já é um brilho; aqui ele só solta UMA rajada.
	local estrelas = Instance.new("ParticleEmitter")
	estrelas.Enabled = false -- (não fica soltando sem parar: só a rajada do Emit, logo abaixo)
	estrelas.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90)) -- douradas
	estrelas.LightEmission = 1 -- brilham
	estrelas.Size = NumberSequence.new(1.2, 0) -- nascem grandes e encolhem até sumir
	estrelas.Lifetime = NumberRange.new(0.4, 0.7) -- (s) quanto tempo cada uma dura
	estrelas.Speed = NumberRange.new(12, 22) -- a força com que saem
	estrelas.SpreadAngle = Vector2.new(180, 180) -- para todo lado
	estrelas.Drag = 4 -- freiam no ar
	estrelas.Parent = quad.chassi
	estrelas:Emit(30) -- solta 30 de uma vez
	task.delay(1, function()
		estrelas:Destroy()
	end)

	-- 3) O SOM (só se você colocou um id em SOM_DO_PERFEITO).
	if SOM_DO_PERFEITO ~= "" then
		local som = Instance.new("Sound")
		som.SoundId = SOM_DO_PERFEITO
		som.Volume = 0.7
		som.Parent = game:GetService("SoundService") -- (som "de tela": não depende de onde a câmera está)
		som:Play()
		task.delay(4, function()
			som:Destroy()
		end)
	end

	-- 4) O TEXTO "PERFEITO!" pulando na tela.
	local tela = pegarTelaDoPerfeito()
	if tela == nil then
		return
	end
	local velho = tela:FindFirstChild("Perfeito")
	if velho then
		velho:Destroy() -- (um PERFEITO logo depois do outro: fica só o novo)
	end
	local texto = Instance.new("TextLabel")
	texto.Name = "Perfeito"
	texto.AnchorPoint = Vector2.new(0.5, 0.5)
	texto.Position = UDim2.fromScale(0.5, 0.32) -- no meio, um pouco acima do centro
	texto.Size = UDim2.fromOffset(400, 70)
	texto.BackgroundTransparency = 1
	texto.Font = Enum.Font.FredokaOne -- letra arredondada, estilo desenho
	texto.Text = "PERFEITO!"
	texto.TextSize = Tela.tamanho(44) -- (no celular, menor)
	texto.TextColor3 = Color3.fromRGB(255, 225, 90)
	texto.Rotation = math.random(-6, 6) -- cada vez um pouquinho torto (fica mais divertido)
	local contorno = Instance.new("UIStroke") -- a borda escura em volta das letras
	contorno.Thickness = 3
	contorno.Color = Color3.fromRGB(110, 55, 0)
	contorno.Parent = texto
	local escala = Instance.new("UIScale") -- começa pequeno...
	escala.Scale = 0.3
	escala.Parent = texto
	texto.Parent = tela
	-- ...e "pula" para o tamanho certo (o estilo Back passa um pouco do tamanho e volta, como uma mola).
	TweenService:Create(escala, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- Fica 0,8 s na tela e some subindo.
	task.delay(0.8, function()
		local sumir = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(texto, sumir, { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.26) }):Play()
		TweenService:Create(contorno, sumir, { Transparency = 1 }):Play()
		task.delay(0.45, function()
			texto:Destroy()
		end)
	end)
end

-- Saiu do banco: apaga a força e o endireitador e zera o impulso.
local function apagarImpulso()
	local forca, alinhar = forcaImpulso, alinharPouso
	if forca then
		local anexo = forca.Attachment0
		forca:Destroy()
		if anexo then
			anexo:Destroy()
		end
	end
	if alinhar then
		local anexo = alinhar.Attachment0
		alinhar:Destroy()
		if anexo then
			anexo:Destroy()
		end
	end
	forcaImpulso, alinharPouso = nil, nil
	modoImpulso = nil
	direcaoDecolagem = nil
	tempoNoAr = 0
	pousoAte = 0
	penduradoAgora = false -- (NOVO)
	sairDoBalanco() -- (NOVO) apaga o balanço e os efeitos dele (vento, rastro e o brilho da corda)
	local doBalanco = alinharBalanco
	if doBalanco then
		doBalanco:Destroy()
	end
	alinharBalanco = nil
end

-- (NOVO) Um número da Configuracao (ou o padrão daqui, se ela não tiver).
local function numeroDaConfig(valor: unknown, padrao: number): number
	return if typeof(valor) == "number" then valor else padrao
end

-- (NOVO) O "puxador" do balanço (criado só na primeira vez): leva a FRENTE do quadriciclo (o Attachment de
-- onde a corda sai) até o lugar do pêndulo, suave. Ele segura o peso todo: a gravidade normal não manda.
local function pegarAlinharBalanco(quad: Quadriciclo, saida: Attachment): AlignPosition
	local existente = alinharBalanco
	if existente and existente.Parent then
		existente.Attachment0 = saida
		return existente
	end
	local alinhar = Instance.new("AlignPosition")
	alinhar.Name = "BalancoGancho"
	alinhar.Mode = Enum.PositionAlignmentMode.OneAttachment -- vai até a posição que a gente escolher
	alinhar.Attachment0 = saida
	alinhar.ApplyAtCenterOfMass = true -- empurra pelo centro: não faz ele rodopiar
	alinhar.MaxVelocity = math.huge
	alinhar.MaxForce = massaTotal(quad) * 1500 -- força de sobra (segura o peso e o balanço)
	alinhar.Responsiveness = 40 -- rapidez para chegar no lugar (maior = mais "no trilho")
	alinhar.Enabled = false
	alinhar.Parent = quad.chassi
	alinharBalanco = alinhar
	return alinhar
end



-- ESTILINGUE: o gancho de IMPULSO estava preso? Solta a corda na hora, dá o impulso e liga o pouso.
-- (Não estava? Não faz nada.) Quem avisa o Servidor e começa a recarga é o soltarMeuGancho.
local function estilingue(quad: Quadriciclo)
	local eraImpulso = modoImpulso ~= nil -- o gancho de IMPULSO estava preso?
	local estavaPendurado = penduradoAgora -- (NOVO) estava balançando pendurado (SEGURAR ou IMPULSO)?
	if not eraImpulso and not estavaPendurado then
		return -- nem preso no IMPULSO, nem pendurado: não faz nada
	end
	modoImpulso = nil
	penduradoAgora = false
	local Config = quad.Config
	-- 1) Desliga a corda AQUI, na hora. O Servidor apaga ela logo depois, mas a internet demora um
	--    pouquinho e, nesse meio tempo, a corda esticada "seguraria" o impulso.
	local corda = cordaDoGancho(quad)
	if corda then
		corda.Enabled = false
	end
	local forca = forcaImpulso
	if forca then
		forca.Enabled = false

	end

	-- 1b) (NOVO) Estava no BALANÇO: sai voando com a velocidade do balanço.
	--     PERFEITO: soltou rápido E subindo (rastro dourado)? Sai mais forte, com um pulinho, e comemora!
	local doBalanco = balanco
	if doBalanco then
		local ajustes = quad.Config
		local lancamento = doBalanco.velocidade
		local maximaDoBalanco = numeroDaConfig(ajustes.BalancoVelocidadeMaxima, BALANCO_VELOCIDADE_MAXIMA)
		local fracaoPerfeita = numeroDaConfig(ajustes.BalancoPerfeito, BALANCO_PERFEITO)
		if lancamento.Magnitude >= maximaDoBalanco * fracaoPerfeita and lancamento.Y > 0 then
			local bonus = numeroDaConfig(ajustes.BalancoBonusPerfeito, BALANCO_BONUS_PERFEITO)
			local pulo = numeroDaConfig(ajustes.BalancoPuloPerfeito, BALANCO_PULO_PERFEITO)
			lancamento = lancamento * bonus + Vector3.yAxis * pulo
			comemorarPerfeito(quad)
		end
		for _, parte in quad.pecasFisicas do
			parte.AssemblyLinearVelocity = lancamento
			parte.AssemblyAngularVelocity = Vector3.zero
		end
		sairDoBalanco()
	end

	-- 2) O impulso: uma parte da velocidade de agora, na direção em que ia, puxada um pouco para cima.
	local velocidade = quad.chassi.AssemblyLinearVelocity
	local rapidez = velocidade.Magnitude
	local fracao: number = Config.GanchoImpulsoSoltar
	if eraImpulso and rapidez > 1 and fracao > 0 then -- (NOVO) o impulso extra é só do gancho de IMPULSO
		local direcao = velocidade / rapidez + Vector3.yAxis * Config.GanchoImpulsoSubida
		if direcao.Magnitude > 0.01 then
			local extra = direcao.Unit * math.min(rapidez * fracao, Config.GanchoImpulsoMaximo)
			for _, parte in quad.pecasFisicas do
				parte.AssemblyLinearVelocity += extra -- todas as peças ganham a mesma velocidade: o quadriciclo vai inteiro
			end
		end
	end
	-- 3) POUSO: liga o endireitador (o Gancho.atualizarImpulso desliga quando a roda toca o chão).
	local alinhar = pegarAlinharPouso(quad)
	alinhar.CFrame = direcaoDoPouso(quad)
	alinhar.Enabled = true
	pousoAte = os.clock() + TEMPO_MAXIMO_POUSO
end

-- (NOVO) BALANÇO ARCADE: pendurado na corda (o SEGURAR, ou o IMPULSO no modo pêndulo), quem move o
-- quadriciclo é um PÊNDULO SIMPLES calculado aqui (não a física de verdade). E agora mais gostoso:
--   EMBALO ......... lá embaixo o empurrão das teclas vale mais (como num balanço de parquinho).
--   FLUTUAR ........ lá no alto ele fica em câmera lenta um instante; embaixo passa zunindo.
--   INCLINAR ....... indo de lado, ele deita para aquele lado, como um avião fazendo curva.
--   VENTO e RASTRO . quanto mais rápido, mais forte o vento e mais visível a fita que desenha o arco.
--   PERFEITO ....... rápido E subindo: o rastro fica dourado e a corda brilha. Solte nessa hora!
--   PAREDES ........ (NOVO) ele sente a parede antes de bater: escorrega nela, quica nas batidas fortes e,
--                    encostado, empurrar para longe dela dá um CHUTE na parede.
--   SOLTO .......... (NOVO) o corpo balança atrás da corda como numa mola, e a corda estica um pouco no puxão.
--   W / S / A / D (ou o analógico) empurram o balanço para a frente, trás e lados DA CÂMERA.

-- (NOVO) BATIDA NA PAREDE: um tranco na tela e uma nuvem de poeira saindo de onde bateu.
local function batidaNaParede(posicao: Vector3, normal: Vector3, forca: number)
	CameraModulo.tremer(math.clamp(forca / 180, 0.05, 0.25)) -- (bateu mais forte = treme mais)
	-- Um ponto solto no mundo (dentro do Terrain), com o "cima" dele apontando para fora da parede.
	local lado = normal:Cross(Vector3.yAxis)
	if lado.Magnitude < 0.1 then
		lado = normal:Cross(Vector3.xAxis) -- (parede deitada, tipo chão ou teto)
	end
	local ponto = Instance.new("Attachment")
	ponto.Parent = workspace.Terrain
	ponto.WorldCFrame = CFrame.fromMatrix(posicao, lado.Unit, normal)
	local poeira = Instance.new("ParticleEmitter")
	poeira.Texture = "rbxasset://textures/particles/smoke_main.dds"
	poeira.Color = ColorSequence.new(Color3.fromRGB(236, 228, 210)) -- bege bem clarinho
	poeira.LightInfluence = 0.6
	poeira.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.3, 2), -- incha rápido ("puf!")...
		NumberSequenceKeypoint.new(1, 2.8), -- ...e continua crescendo devagar
	})
	poeira.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	poeira.Lifetime = NumberRange.new(0.5, 0.9)
	poeira.Speed = NumberRange.new(4, 9)
	poeira.SpreadAngle = Vector2.new(60, 60)
	poeira.Drag = 5 -- freia rápido: a nuvem fica boiando perto da parede
	poeira.Rotation = NumberRange.new(0, 360)
	poeira.EmissionDirection = Enum.NormalId.Top -- para fora da parede
	poeira.Enabled = false -- (só a rajada do Emit)
	poeira.Parent = ponto
	poeira:Emit(math.floor(math.clamp(forca / 3, 6, 16)))
	task.delay(1.5, function()
		ponto:Destroy() -- (apaga o ponto e a poeira junto)
	end)
end

-- Começou a balançar: guarda o gancho, o tamanho da corda e a velocidade de agora, e cria os efeitos.
local function comecarBalanco(quad: Quadriciclo, a0: Attachment, a1: Attachment): Balanco
	local Config = quad.Config
	local minima = numeroDaConfig(Config.BalancoCordaMinima, BALANCO_CORDA_MINIMA)
	local maxima = numeroDaConfig(Config.BalancoCordaMaxima, BALANCO_CORDA_MAXIMA)
	local velocidadeMaxima = numeroDaConfig(Config.BalancoVelocidadeMaxima, BALANCO_VELOCIDADE_MAXIMA)
	local ancora = a1.WorldPosition
	local daAncora = a0.WorldPosition - ancora
	local direcao = if daAncora.Magnitude > 0.1 then daAncora.Unit else -Vector3.yAxis
	local comprimento = math.clamp(daAncora.Magnitude, minima, maxima)
	-- A velocidade de agora vira a do balanço (só a parte "de lado" para a corda, e sem exagero).
	local velocidade = quad.chassi.AssemblyLinearVelocity
	velocidade -= direcao * velocidade:Dot(direcao)
	if velocidade.Magnitude > velocidadeMaxima then
		velocidade = velocidade.Unit * velocidadeMaxima
	end
	local referencia = Veiculo.referencia(quad)
	local frente = Vector3.new(referencia.LookVector.X, 0, referencia.LookVector.Z)

	-- a) O VENTO: um som que fica tocando sem parar. Começa mudo (o balancar aumenta com a velocidade).
	local vento = Instance.new("Sound")
	vento.Name = "VentoDoBalanco"
	vento.SoundId = SOM_DO_VENTO
	vento.Looped = true
	vento.Volume = 0
	vento.RollOffMinDistance = 40 -- (até 40 studs de distância ele toca no volume cheio: a câmera fica perto)
	vento.Parent = quad.chassi
	vento:Play()

	-- b) O RASTRO: uma fita que desenha o arco do balanço. Ela nasce entre 2 pontos (Attachments)
	-- no meio do quadriciclo e vai ficando para trás.
	local pontaDeCima = Instance.new("Attachment")
	pontaDeCima.Name = "RastroCima"
	pontaDeCima.Position = Vector3.new(0, 0.6, 0)
	pontaDeCima.Parent = quad.chassi
	local pontaDeBaixo = Instance.new("Attachment")
	pontaDeBaixo.Name = "RastroBaixo"
	pontaDeBaixo.Position = Vector3.new(0, -0.6, 0)
	pontaDeBaixo.Parent = quad.chassi
	local rastro = Instance.new("Trail")
	rastro.Name = "RastroDoBalanco"
	rastro.Attachment0 = pontaDeCima
	rastro.Attachment1 = pontaDeBaixo
	rastro.FaceCamera = true -- a fita fica sempre de frente para a câmera
	rastro.Lifetime = 0.45 -- (s) quanto tempo cada pedaço da fita dura (maior = rastro mais comprido)
	rastro.MinLength = 0.2
	rastro.LightEmission = 0.6 -- brilha um pouco
	rastro.LightInfluence = 0 -- não fica escura na sombra
	rastro.Color = COR_RASTRO
	rastro.Transparency = NumberSequence.new(1) -- começa invisível (o balancar mostra conforme a velocidade)
	rastro.WidthScale = NumberSequence.new(1, 0) -- vai afinando até a ponta (parece um risco de velocidade)
	rastro.Parent = quad.chassi

	-- c) A CORDA DESENHADA: os pedaços (Beams) do "GanchoVisual". Eles brilham na hora do PERFEITO.
	local cordas: { Beam } = {}
	local visual = quad.modelo:FindFirstChild("GanchoVisual", true)
	if visual then
		for _, peca in visual:GetDescendants() do
			if peca:IsA("Beam") then
				table.insert(cordas, peca)
			end
		end
	end

	-- d) (NOVO) AS PAREDES: uma "bola" invisível do tamanho do corpo sente as paredes. Ela ignora o
	-- próprio quadriciclo e o seu boneco.
	local filtroParede = RaycastParams.new()
	filtroParede.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar: { Instance } = { quad.modelo }
	local jogador = game:GetService("Players").LocalPlayer
	local personagem = if jogador then jogador.Character else nil
	if personagem then
		table.insert(ignorar, personagem)
	end
	filtroParede.FilterDescendantsInstances = ignorar
	local medidas = { quad.chassi.Size.X, quad.chassi.Size.Y, quad.chassi.Size.Z }
	table.sort(medidas) -- (do menor para o maior: a do meio é mais ou menos a largura)

	return {
		ancora = ancora,
		bola = ancora + direcao * comprimento,
		velocidade = velocidade,
		comprimento = comprimento,
		frente = if frente.Magnitude > 0.01 then frente.Unit else Vector3.new(0, 0, -1),
		inclinacaoDeLado = 0,
		naJanela = false,
		vento = vento,
		rastro = rastro,
		pontasDoRastro = { pontaDeCima, pontaDeBaixo },
		cordas = cordas,
		larguraDaCorda = if cordas[1] then cordas[1].Width0 else 0.3,
		massa = massaTotal(quad),
		cimaAtual = referencia.UpVector, -- (começa do jeito que ele está: sem tranco)
		cimaVelocidade = Vector3.zero,
		esticar = 0,
		esticarVelocidade = 0,
		raioDoCorpo = math.max(medidas[2] * 0.4, 1),
		filtroParede = filtroParede,
		parede = nil,
		paredeAte = 0,
		chutePronto = 0,
		ultimaBatida = 0,
	}
end

local function balancar(quad: Quadriciclo, pedal: number, volante: number, dt: number, corda: RopeConstraint)
	local a0, a1 = corda.Attachment0, corda.Attachment1
	if a0 == nil or a1 == nil then
		return
	end
	local Config = quad.Config
	local gravidade = numeroDaConfig(Config.BalancoGravidade, BALANCO_GRAVIDADE)
	local forca = numeroDaConfig(Config.BalancoForca, BALANCO_FORCA)
	local velocidadeMaxima = numeroDaConfig(Config.BalancoVelocidadeMaxima, BALANCO_VELOCIDADE_MAXIMA)
	local amortecimento = numeroDaConfig(Config.BalancoAmortecimento, BALANCO_AMORTECIMENTO)
	local inclinacao = numeroDaConfig(Config.BalancoInclinacao, BALANCO_INCLINACAO)
	local embalo = math.max(numeroDaConfig(Config.BalancoEmbalo, BALANCO_EMBALO), 1) -- (menos de 1 = desliga)
	local flutuar = math.clamp(numeroDaConfig(Config.BalancoFlutuar, BALANCO_FLUTUAR), 0, 0.9)
	local inclinarLado = numeroDaConfig(Config.BalancoInclinarLado, BALANCO_INCLINAR_LADO)
	local perfeito = numeroDaConfig(Config.BalancoPerfeito, BALANCO_PERFEITO)
	local elastico = math.clamp(numeroDaConfig(Config.BalancoElastico, BALANCO_ELASTICO), 0, 0.3) -- (NOVO)
	local soltura = math.clamp(numeroDaConfig(Config.BalancoSoltura, BALANCO_SOLTURA), 0, 1) -- (NOVO)
	local molaDoCorpo = math.max(numeroDaConfig(Config.BalancoMolaDoCorpo, BALANCO_MOLA_DO_CORPO), 1) -- (NOVO)
	local quique = math.clamp(numeroDaConfig(Config.BalancoQuique, BALANCO_QUIQUE), 0, 1) -- (NOVO)
	local chute = numeroDaConfig(Config.BalancoChuteParede, BALANCO_CHUTE_PAREDE) -- (NOVO)
	local estado = balanco or comecarBalanco(quad, a0, a1)
	balanco = estado
	penduradoAgora = true
	local agora = os.clock()
	-- a corda de verdade fica do tamanho do balanço, contando o quanto ela está esticada (não briga com ele)
	corda.Length = estado.comprimento + estado.esticar

	-- 1) A "GRAVIDADE" DO BALANÇO: só a parte que puxa de lado (a corda segura o resto).
	local u = (estado.bola - estado.ancora).Unit -- do gancho até a frente do quadriciclo
	local peso = Vector3.new(0, -gravidade, 0)
	local acelera = peso - u * peso:Dot(u)
	-- "fundo": 1 = bem embaixo do gancho · 0 = na altura do gancho.
	local fundo = math.clamp(-u.Y, 0, 1)
	-- FLUTUAR: o "tempo" do balanço. No fundo é o normal; lá no alto passa mais devagar (câmera lenta).
	local tempo = dt * (1 - flutuar * (1 - fundo))

	-- 2) AS SUAS TECLAS: frente/trás/lados da câmera (também só "de lado" para a corda).
	local desejo = Vector3.zero -- (NOVO: guardado aqui fora, o CHUTE NA PAREDE também usa)
	local camera = Veiculo.cameraAtual().CFrame
	local frenteCam = Vector3.new(camera.LookVector.X, 0, camera.LookVector.Z)
	local direitaCam = Vector3.new(camera.RightVector.X, 0, camera.RightVector.Z)
	if frenteCam.Magnitude > 0.01 and direitaCam.Magnitude > 0.01 then
		desejo = frenteCam.Unit * pedal + direitaCam.Unit * volante
		if desejo.Magnitude > 0.1 then
			local deLado = desejo - u * desejo:Dot(u)
			if deLado.Magnitude > 0.01 then
				-- EMBALO: lá embaixo o empurrão vale mais (até "embalo" vezes); lá no alto, o normal.
				local embaloAgora = 1 + (embalo - 1) * fundo * fundo
				acelera += deLado.Unit * forca * math.min(desejo.Magnitude, 1) * embaloAgora
			end
			-- o quadriciclo vira devagar para onde você está mandando
			local mistura = estado.frente:Lerp(desejo.Unit, math.min(dt * 4, 1))
			if mistura.Magnitude > 0.01 then
				estado.frente = mistura.Unit
			end
		end
	end

	-- 3) A VELOCIDADE: soma a aceleração, fica só "de lado" para a corda, freia um pouquinho e tem limite.
	local velocidade = estado.velocidade + acelera * tempo
	velocidade -= u * velocidade:Dot(u)
	velocidade *= 1 - math.min(tempo * amortecimento, 1)
	if velocidade.Magnitude > velocidadeMaxima then
		velocidade = velocidade.Unit * velocidadeMaxima
	end
	if u.Y > BALANCO_ALTURA_LIMITE then
		-- Alto demais: não deixa subir mais (nada de dar a volta completa na corda).
		local subir = Vector3.yAxis - u * u.Y -- a direção "para cima" andando pela corda
		if subir.Magnitude > 0.01 then
			subir = subir.Unit
			local subindo = velocidade:Dot(subir)
			if subindo > 0 then
				velocidade -= subir * subindo
			end
		end
	end

	-- 3b) (NOVO) AS PAREDES: antes o pêndulo atravessava as paredes e puxava o quadriciclo contra elas
	--     (por isso ele "bugava"). Agora ele sente a parede, escorrega nela e quica nas batidas fortes.
	local centro = quad.chassi.AssemblyCenterOfMass -- o meio do quadriciclo de verdade
	local raio = estado.raioDoCorpo
	local filtro = estado.filtroParede
	local frenteDeVerdade = a0.WorldPosition -- onde a frente do quadriciclo está DE VERDADE agora
	-- a) TRAVADO? O quadriciclo de verdade ficou bem para trás do pêndulo (uma quina, uma roda presa...).
	--    Então o pêndulo cede, em vez de puxar com força contra o obstáculo.
	local atraso = estado.bola - frenteDeVerdade
	atraso -= u * atraso:Dot(u) -- (só "de lado" para a corda: a corda esticando não conta)
	local folga = 2.5 + velocidade.Magnitude / 20 -- (um pouco de atraso é normal: quanto mais rápido, mais)
	if atraso.Magnitude > folga then
		local travou = atraso.Unit
		local entra = velocidade:Dot(travou)
		if entra > 0 then
			velocidade -= travou * entra
		end
		estado.parede = -travou
		estado.paredeAte = agora + 0.15
		estado.bola = frenteDeVerdade + travou * folga
	end
	-- b) CHUTE NA PAREDE: encostado e empurrando para longe dela? Sai com tudo (no máximo 2 por segundo).
	local parede = estado.parede
	if parede and agora < estado.paredeAte and chute > 0 and agora > estado.chutePronto and desejo:Dot(parede) > 0.3 then
		velocidade += parede * chute
		estado.chutePronto = agora + 0.5
		batidaNaParede(centro - parede * raio, parede, 20) -- poeirinha e um tranco pequeno
	end
	-- c) VAI BATER? Uma "bola" do tamanho do corpo anda na frente para ver se tem parede no caminho.
	local caminho = velocidade * tempo
	if caminho.Magnitude > 0.001 then
		local acerto = workspace:Spherecast(centro, raio, caminho.Unit * (caminho.Magnitude + 0.5), filtro)
		if acerto then
			local normal = acerto.Normal -- a direção "para fora" da parede
			local entra = velocidade:Dot(-normal) -- quão rápido ia entrar na parede
			if entra > 0 then
				local forte = entra > 12
				velocidade += normal * entra * (if forte then 1 + quique else 1) -- escorrega (e quica, se foi forte)
				if forte and agora - estado.ultimaBatida > 0.25 then
					estado.ultimaBatida = agora
					batidaNaParede(acerto.Position, normal, entra)
				end
			end
			estado.parede = normal
			estado.paredeAte = agora + 0.15
		end
	end
	-- d) ENCOSTADO: enquanto continua encostado, nem o pêndulo nem a velocidade entram na parede.
	parede = estado.parede
	if parede and agora < estado.paredeAte then
		local sonda = workspace:Spherecast(centro, raio, -parede * 0.6, filtro) -- ainda está encostado?
		if sonda then
			parede = sonda.Normal
			estado.parede = parede
			estado.paredeAte = agora + 0.15
		end
		local entra = velocidade:Dot(-parede)
		if entra > 0 then
			velocidade += parede * entra
		end
		local dentro = (frenteDeVerdade - estado.bola):Dot(parede) -- o pêndulo está "dentro" da parede?
		if dentro > 0 then
			estado.bola += parede * dentro
		end
	end
	velocidade -= u * velocidade:Dot(u) -- (continua só "de lado" para a corda)
	estado.velocidade = velocidade

	-- 3c) (NOVO) CORDA ELÁSTICA: quanto mais puxão (embaixo e rápido), mais ela estica; depois volta quicando.
	local puxao = (gravidade * fundo + velocidade.Magnitude ^ 2 / estado.comprimento)
		/ (gravidade + velocidadeMaxima ^ 2 / estado.comprimento)
	local esticarAlvo = estado.comprimento * elastico * math.clamp(puxao, 0, 1)
	estado.esticarVelocidade += ((esticarAlvo - estado.esticar) * 120 - estado.esticarVelocidade * 9) * dt
	estado.esticar += estado.esticarVelocidade * dt
	-- anda e volta para a "esfera" da corda (sempre a mesma distância do gancho, contando o esticado)
	local tamanhoDaCorda = estado.comprimento + estado.esticar
	estado.bola = estado.ancora + (estado.bola + velocidade * tempo - estado.ancora).Unit * tamanhoDaCorda

	-- INCLINAR DE LADO: indo para a direita, ele deita para a direita (e vice-versa), bem suave.
	local direitaDoQuad = estado.frente:Cross(Vector3.yAxis) -- a "direita" de para onde ele está virado
	local deLadoAgora = math.clamp(velocidade:Dot(direitaDoQuad) / velocidadeMaxima, -1, 1)
	local alvoDeLado = -deLadoAgora * math.rad(inclinarLado)
	estado.inclinacaoDeLado += (alvoDeLado - estado.inclinacaoDeLado) * math.min(dt * 5, 1)

	-- 4) MOVE O QUADRICICLO: a frente dele vai até a "bola" do pêndulo...
	local puxador = pegarAlinharBalanco(quad, a0)
	puxador.Position = estado.bola
	puxador.MaxForce = estado.massa * 900 -- (NOVO) força suficiente para balançar, sem esmagar na parede
	puxador.Responsiveness = 30 -- (NOVO) um tiquinho mais solto (era 40)
	puxador.Enabled = true
	-- ...e o corpo fica virado para "frente", com o nariz levantado e deitado de lado.
	-- (NOVO) O "cima" do corpo segue a corda com uma MOLA: atrasa um pouquinho e passa do ponto, como um
	-- peso pendurado de verdade (antes ele ia direto para a posição certa: parecia duro).
	local cimaAlvo = Vector3.yAxis:Lerp(-u, soltura).Unit -- entre "para cima" e "para o gancho"
	local freioDaMola = 2 * 0.3 * math.sqrt(molaDoCorpo) -- (0.3 = balança um pouco antes de parar)
	estado.cimaVelocidade += ((cimaAlvo - estado.cimaAtual) * molaDoCorpo - estado.cimaVelocidade * freioDaMola) * dt
	estado.cimaAtual = (estado.cimaAtual + estado.cimaVelocidade * dt).Unit
	local cima = estado.cimaAtual
	local frente = estado.frente - cima * estado.frente:Dot(cima)
	if frente.Magnitude > 0.01 then
		local giro = pegarAlinharPouso(quad) -- (o mesmo endireitador do pouso)
		giro.Responsiveness = 14 -- (NOVO) segue a mola de perto (quem deixa solto agora é a mola)
		giro.CFrame = CFrame.lookAt(Vector3.zero, frente.Unit, cima)
			* CFrame.Angles(math.rad(inclinacao), 0, estado.inclinacaoDeLado)
		giro.Enabled = true
	end

	-- 5) EFEITOS: quanto mais rápido, mais forte e mais agudo o vento e mais visível o rastro.
	local carga = math.clamp(velocidade.Magnitude / velocidadeMaxima, 0, 1) -- 0 = parado · 1 = no máximo
	estado.vento.Volume = 0.9 * carga * carga -- (devagar quase não se ouve; rápido, zune)
	estado.vento.PlaybackSpeed = 0.8 + 0.5 * carga
	estado.rastro.Transparency = NumberSequence.new(1 - 0.7 * carga, 1)
	-- JANELA DO PERFEITO: rápido E subindo. Soltar agora dá o bônus! O rastro fica dourado e a corda
	-- brilha e engrossa (só muda na hora que entra ou sai da janela).
	local janela = carga >= perfeito and velocidade.Y > 0
	if janela ~= estado.naJanela then
		estado.naJanela = janela
		estado.rastro.Color = if janela then COR_RASTRO_PERFEITO else COR_RASTRO
		local largura = if janela then estado.larguraDaCorda * 1.6 else estado.larguraDaCorda
		for _, pedaco in estado.cordas do
			pedaco.Width0 = largura
			pedaco.Width1 = largura
			pedaco.LightEmission = if janela then 1 else 0
		end
	end
end



-- Chamada pelo QuadricicloCliente ANTES de cada passo da física (no fim do "atualizar").
-- pedal: 1 = GÁS todo apertado · -1 = FREIO todo apertado · 0 = nada.
function Gancho.atualizarImpulso(quad: Quadriciclo, pedal: number, dt: number, volante: number?)
	local Config = quad.Config
	local chassi = quad.chassi
	local noChao = rodaNoChao(quad)
	tempoNoAr = if noChao then 0 else tempoNoAr + dt
	-- 1) POUSO (depois do estilingue): mantém o quadriciclo em pé, de frente para onde está indo.
	local alinhar = alinharPouso
	-- (NOVO) No frame passado ele não estava mais balançando (encostou no chão, soltou...)? Física normal de volta.
	if balanco ~= nil and not penduradoAgora then
		sairDoBalanco()
	end
	penduradoAgora = false -- o BALANÇO, mais abaixo, marca de novo se você estiver pendurado
	if alinhar and alinhar.Enabled and balanco == nil then -- (balançando, quem usa o endireitador é o balanço)
		if noChao or os.clock() > pousoAte then
			alinhar.Enabled = false -- tocou o chão (ou passou do tempo): a física normal volta a mandar
		else
			alinhar.CFrame = direcaoDoPouso(quad)
		end
	end
	-- 2) O gancho de IMPULSO está preso? (gancho NOSSO, deste tipo, com a corda de verdade)
	local forca = forcaImpulso
	if forca then
		forca.Enabled = false -- (liga de novo lá embaixo, se for para empurrar)
	end
	local corda = cordaDoGancho(quad)
	local a0 = if corda then corda.Attachment0 else nil
	local a1 = if corda then corda.Attachment1 else nil
	-- (NOVO) SEGURAR pendurado (rodas fora do chão e sem estar escalando parede): balança solto.
	if enviadoEm ~= nil and tipoAtivo == "Segurar" and corda ~= nil and corda.Enabled
		and tempoNoAr >= TEMPO_NO_AR and not escalando
	then
		balancar(quad, pedal, volante or 0, dt, corda)
	end

	if enviadoEm == nil or tipoAtivo ~= "Impulso" or corda == nil or not corda.Enabled or a0 == nil or a1 == nil then
		modoImpulso = nil -- não está preso (ainda voando, já soltou ou é outro tipo de gancho)
		direcaoDecolagem = nil
		return
	end
	if modoImpulso == nil then
		inicioPuxao = os.clock() -- acabou de prender
	end
	local paraOPonto = a1.WorldPosition - a0.WorldPosition -- da saída da corda até onde o gancho prendeu
	local distancia = paraOPonto.Magnitude
	if distancia < 0.5 then
		return
	end
	local direcaoCorda = paraOPonto / distancia
	-- 3) PUXÃO ou PÊNDULO? No chão é sempre puxão. Quando você sai do chão (ou se prendeu já no ar), olha
	--    para onde o ponto estava NA DECOLAGEM e escolhe UMA vez, até pousar: ponto bem acima = pêndulo;
	--    senão, o puxão continua pelo ar.
	if noChao then
		direcaoDecolagem = nil
	elseif direcaoDecolagem == nil then
		direcaoDecolagem = direcaoCorda -- primeiro instante no ar: guarda a direção
	end
	if tempoNoAr < TEMPO_NO_AR then
		modoImpulso = "Puxao"
	elseif modoImpulso ~= "PuxaoNoAr" and modoImpulso ~= "Pendulo" then
		local decolagem = direcaoDecolagem or direcaoCorda
		modoImpulso = if decolagem.Y >= SENO_PENDULO then "Pendulo" else "PuxaoNoAr"
	end
	-- 4) CARRETEL: chegou mais perto do ponto (a corda afrouxou)? Recolhe a folga.
	if distancia < corda.Length then
		corda.Length = math.max(distancia, math.min(corda.Length, CORDA_MINIMA))
	end
	local massa = massaTotal(quad)
	if modoImpulso ~= "Pendulo" then
		-- 5a) PUXÃO. Chegou perto = solta com o estilingue. Travou em algo (passou do tempo) = solta sem impulso.
		if distancia <= Config.GanchoImpulsoChegada then
			estilingue(quad)
			soltarMeuGancho(quad)
			return
		elseif os.clock() - inicioPuxao > Config.GanchoImpulsoTempoMaximo then
			modoImpulso = nil
			soltarMeuGancho(quad)
			return
		end
		-- Rodas soltas: sem isso, os motores "seguram" o quadriciclo contra o puxão.
		for _, info in quad.rodas do
			info.motor.MotorMaxTorque = 0
		end
		-- O puxão MIRA um pouco acima do ponto e corrige a direção o tempo todo: acelera até
		-- GanchoImpulsoVelocidade (quem já está mais rápido não é freado) e tira o que estiver indo
		-- "de lado" ou "caindo". Assim você vai quase em linha reta até o ponto.
		local mira = a1.WorldPosition + Vector3.new(0, MIRA_ACIMA, 0)
		local direcaoMira = (mira - a0.WorldPosition).Unit
		local velocidade = chassi.AssemblyLinearVelocity
		local rapidezDesejada = math.max(Config.GanchoImpulsoVelocidade, velocidade:Dot(direcaoMira))
		local puxao = (direcaoMira * rapidezDesejada - velocidade) * RESPOSTA_PUXAO
		if puxao.Magnitude > Config.GanchoImpulsoForca then
			puxao = puxao.Unit * Config.GanchoImpulsoForca -- nunca mais forte que a Configuracao
		end
		if modoImpulso == "PuxaoNoAr" then
			puxao += Vector3.yAxis * workspace.Gravity * MENOS_GRAVIDADE -- pelo ar: quase sem gravidade
		end
		local forcaAgora = pegarForcaImpulso(quad)
		forcaAgora.Force = puxao * massa
		forcaAgora.Enabled = true
		return
	end
	-- 5b) (NOVO) PÊNDULO: balança solto, e você escolhe para onde (veja o BALANÇO, mais acima).
	balancar(quad, pedal, volante or 0, dt, corda)
end

-- Roda a cada frame enquanto você dirige: estado do gancho, escalada e a barra de ganchos.
local function atualizarGancho(quad: Quadriciclo, dt: number)
	local Config = quad.Config
	local estadoServidor = quad.modelo:GetAttribute("GanchoEstado")
	local enviado = enviadoEm
	-- O Servidor recusou o alvo ou já soltou sozinho (tempo máximo, alvo sumiu): esquece o pedido.
	if enviado and estadoServidor == nil and os.clock() - enviado > ESPERA_RESPOSTA_GANCHO then
		enviadoEm = nil
		enviado = nil
		tipoAtivo = nil
		esquecerMeuGancho() -- (NOVO) e apaga a corda que o seu computador tinha travado
	end
	voarMeuGancho(quad, dt) -- (NOVO) o gancho voa aqui também: quando chega, a corda TRAVA na hora
	-- Gancho no ar ou preso e o quadriciclo (ou a corda) entrou numa zona que proíbe ESTE gancho: solta.
	local tipo = tipoAtivo
	if enviado and tipo and (estadoServidor == "NoAr" or estadoServidor == "Preso") then
		local valor = quad.modelo:FindFirstChild("GanchoAlvo")
		local alvo = if valor and valor:IsA("ObjectValue") then valor.Value else nil
		if alvo and alvo:IsA("Attachment") and zonaNoCaminho(quad.chassi.Position, alvo.WorldPosition, tipo) then
			local corda = cordaDoGancho(quad)
			if corda then
				corda.Enabled = false -- solta a corda AQUI, na hora (sem estilingue: zona é zona)
			end
			soltarMeuGancho(quad)
			tremerIconeGancho(quad, tipo)
			enviado = nil
		end
	end
	-- ESCALADA: só com o gancho SEGURAR (o de IMPULSO tem o puxão e o pêndulo dele).
	atualizarEscalada(quad, enviado ~= nil and estadoServidor == "Preso" and tipoAtivo == "Segurar")
	-- (NOVO) Você escolheu OUTRO gancho na barra (1/2/3, clique/toque ou setas) e ele ainda está
	-- recarregando? O ícone dele treme e toca o som de recarga dele.
	if tipoSelecionado ~= ultimoEscolhido then
		ultimoEscolhido = tipoSelecionado
		if recargaRestante(tipoSelecionado) > 0 then
			avisarRecarga(quad, tipoSelecionado)
		end
	end
	local hud = hudGancho
	if hud == nil then
		return
	end
	-- Dentro de uma zona? (ZonaSemGancho = os 3 ficam proibidos · ZonaSemImpulso = só o IMPULSO)
	local posicao = quad.chassi.Position
	local semGancho = enviado == nil and linhaEmZona(TAG_ZONA_SEM_GANCHO, posicao, posicao)
	local semImpulso = enviado == nil and linhaEmZona(TAG_ZONA_SEM_IMPULSO, posicao, posicao)
	local suave = math.min(dt * 12, 1) -- as mudanças ficam suaves, sem "piscar"
	for _, item in hud.icones do
		local restante = recargaRestante(item.tipo)
		local ativo = enviado ~= nil and tipoAtivo == item.tipo -- é este o gancho que está voando ou preso?
		local naZona = semGancho or (item.tipo == "Impulso" and semImpulso) -- este gancho é proibido aqui?
		local cor = Config.GanchoCorPronto -- pronto para usar: cores normais
		if ativo and estadoServidor == "Preso" then
			cor = Config.GanchoCorPreso -- prendeu: verde
		elseif ativo then
			cor = Config.GanchoCorNoAr -- voando (ou esperando o Servidor confirmar): cinza bem escuro
		elseif naZona then
			cor = corProibida(quad) -- numa zona onde este gancho não funciona: vermelho, com o risco de "proibido"
		elseif restante > 0 then
			cor = Config.GanchoCorRecarga -- recarregando: cinza avermelhado
		end
		item.cor = item.cor:Lerp(cor, suave)
		item.icone.GroupColor3 = item.cor
		item.anel.Color = item.cor
		item.proibido.Visible = naZona
		item.sombra.Size = UDim2.fromScale(1, math.clamp(restante / math.max(recargaDoTipo(quad, item.tipo), 0.1), 0, 1))
		item.tempo.Visible = restante > 0
		item.tempo.Text = tostring(math.ceil(restante))
		-- O gancho ESCOLHIDO fica maior, com o anel mais grosso e o nome aceso.
		local escolhido = item.tipo == tipoSelecionado
		item.escala.Scale += ((if escolhido then 1.15 else 0.92) - item.escala.Scale) * suave
		item.anel.Thickness = if escolhido then 4 else 2
		item.nome.TextTransparency = if escolhido then 0 else 0.5
	end
	hud.mira.Visible = quad.mirandoGancho
	if quad.mirandoGancho then
		-- A mira fica vermelha quando o gancho escolhido não pode prender no que está no meio dela
		-- (ou quando você trocou para um gancho que ainda está recarregando).
		local pode = recargaRestante(tipoSelecionado) <= 0 and alvoValido(quad, mirarGancho(quad))
		hud.mira.GroupColor3 = if pode then Color3.new(1, 1, 1) else corProibida(quad)
	end
end

-- Lança o gancho ESCOLHIDO NA BARRA no que estiver no meio da mira. (Usado pelo clique esquerdo do
-- mouse e por soltar o L1 / botão GANCHO.) Recarregando, numa zona proibida ou sem nada que este
-- gancho possa prender no meio da mira: não sai, e o ícone dele treme.
local function dispararGancho(quad: Quadriciclo)
	local acerto = mirarGancho(quad) -- (a câmera ainda está na posição de mira neste instante)
	if recargaRestante(tipoSelecionado) > 0 then
		avisarRecarga(quad, tipoSelecionado) -- ainda recarregando: o ícone treme e toca o som de recarga dele
	elseif acerto and alvoValido(quad, acerto) then
		enviadoEm = os.clock()
		tipoAtivo = tipoSelecionado -- o gancho que saiu é o escolhido na barra agora
		esquecerMeuGancho() -- (por garantia: nenhuma corda velha sobrando)
		local parte = acerto.Instance
		-- (NOVO) No CENÁRIO (IMPULSO, ou SEGURAR sem ninguém no alvo), o gancho também voa aqui, para a
		-- corda travar na hora em que ele chegar (veja "TRAVA DA CORDA", lá em cima).
		if parte:IsA("BasePart") and tipoSelecionado ~= "Botao" and humanoideDoAlvo(parte) == nil then
			meuGancho = { parte = parte, ponto = acerto.Position, percorrido = 0, inicio = os.clock(), terminou = false }
		end
		Veiculo.avisarServidor(quad, "GanchoLiga", parte, acerto.Position, tipoSelecionado)
	else
		tremerIconeGancho(quad, tipoSelecionado) -- nada que ESTE gancho possa prender, longe demais ou zona
	end
end

-- CONTROLE (L1) e CELULAR (botão GANCHO): continuam iguais.
--   apertou = MIRA · soltou = o gancho sai · apertou com o gancho no ar ou preso = SOLTA ele
--   (o de IMPULSO preso solta com o estilingue).
local function aoGancho(quad: Quadriciclo, estado: Enum.UserInputState)
	if estado == Enum.UserInputState.Begin then
		if enviadoEm ~= nil then
			estilingue(quad) -- (só faz algo se for o gancho de IMPULSO preso)
			soltarMeuGancho(quad)
		elseif recargaRestante(tipoSelecionado) > 0 then
			avisarRecarga(quad, tipoSelecionado)
		elseif dentroDeZona(quad, tipoSelecionado) then
			tremerIconeGancho(quad, tipoSelecionado) -- numa zona onde este gancho não funciona
		else
			quad.mirandoGancho = true
		end
	elseif estado == Enum.UserInputState.End then
		if quad.mirandoGancho then
			quad.mirandoGancho = false
			dispararGancho(quad)
		end
	elseif estado == Enum.UserInputState.Cancel then
		quad.mirandoGancho = false -- (ex.: saiu do banco segurando o botão): não dispara
	end
end

-- (NOVO) MOUSE:
--   SEGURE o botão DIREITO = MIRA (a mira aparece e a câmera vai para o ombro). Soltou = a mira some.
--   APERTE o botão ESQUERDO mirando = o gancho escolhido na barra SAI.
--   Botão ESQUERDO com um gancho no ar ou preso = SOLTA ele (o de IMPULSO solta com o estilingue).
-- (Aqui usamos o UserInputService, e não o ContextActionService: no ContextActionService, o gatilho
-- direito do controle (R2, que é o acelerador!) também conta como clique esquerdo do mouse.)
local conexoesDoMouse: { RBXScriptConnection } = {}

local function aoApertarMouse(quad: Quadriciclo, entrada: InputObject, processado: boolean)
	if processado then
		return -- o clique foi num botão da tela (ex.: a barra de ganchos) ou você está digitando no chat
	end
	if entrada.UserInputType == Enum.UserInputType.MouseButton2 then
		quad.mirandoGancho = true -- câmera de mira (o gancho só sai com o clique ESQUERDO)
		if recargaRestante(tipoSelecionado) > 0 then
			avisarRecarga(quad, tipoSelecionado) -- avisa que este gancho ainda está recarregando
		end
	elseif entrada.UserInputType == Enum.UserInputType.MouseButton1 then
		if enviadoEm ~= nil then
			estilingue(quad) -- (só faz algo se for o gancho de IMPULSO preso)
			soltarMeuGancho(quad)
		elseif quad.mirandoGancho then
			dispararGancho(quad)
		end
	end
end

local function aoSoltarMouse(quad: Quadriciclo, entrada: InputObject)
	if entrada.UserInputType == Enum.UserInputType.MouseButton2 then
		quad.mirandoGancho = false -- soltou o botão direito: a mira é cancelada (o gancho NÃO sai)
	end
end

-- ---------- CÂMERA DE MIRA ----------
-- Mirando (botão DIREITO do mouse, L1 ou botão GANCHO) nas câmeras 1 e 2: a câmera vai para o ombro
-- direito e chega mais perto (o meio da tela sai de cima do personagem).
-- Na câmera do capô (3): com o mouse TRAVADO no meio da tela (módulo Camera, tecla Alt), mexer o
-- mouse GIRA a câmera para olhar em volta, mirando ou não. Sem mexer por um tempinho (e sem mirar),
-- ela volta sozinha a olhar para a frente. Controle: analógico direito. Celular: arraste a tela
-- enquanto mira. Roda logo DEPOIS da câmera do Roblox e da câmera do capô.
-- (Quem trava e solta o mouse agora é o módulo Camera.)
local CAMERA_OMBRO = "QuadricicloCameraOmbro"
local SENSIBILIDADE_MOUSE = 0.004 -- (radianos por pixel)
local SENSIBILIDADE_TOQUE = 0.006
local GIRO_ANALOGICO = 3 -- (rad/s) analógico direito todo empurrado
local GIRO_MAXIMO = math.rad(150) -- até onde dá para olhar para os lados no capô
local INCLINACAO_MAXIMA = math.rad(70) -- e para cima/baixo
local VOLTAR_PARA_FRENTE = 1.5 -- (s) no capô: sem mexer a câmera esse tempo (e sem mirar), ela volta a olhar para a frente
local misturaOmbro = 0 -- 0 = câmera normal · 1 = no ombro (vai suave de um para o outro)
local olharGiro = 0 -- (rad) câmera do capô: para os lados
local olharInclinacao = 0 -- (rad) câmera do capô: para cima e para baixo
local ultimoOlhar = 0 -- (os.clock) a última vez que você girou a câmera do capô
local analogicoDireito = Vector2.zero
local conexaoOlhar: RBXScriptConnection? = nil

local function atualizarCameraOmbro(quad: Quadriciclo, dt: number)
	local camera = Veiculo.cameraAtual()
	if quad.modoCamera == 3 then
		misturaOmbro = 0
		if analogicoDireito.Magnitude > 0 then
			olharGiro = math.clamp(olharGiro - analogicoDireito.X * GIRO_ANALOGICO * dt, -GIRO_MAXIMO, GIRO_MAXIMO)
			olharInclinacao = math.clamp(olharInclinacao + analogicoDireito.Y * GIRO_ANALOGICO * dt, -INCLINACAO_MAXIMA, INCLINACAO_MAXIMA)
			ultimoOlhar = os.clock()
		end
		if not quad.mirandoGancho and os.clock() - ultimoOlhar > VOLTAR_PARA_FRENTE then
			local volta = math.min(dt * 4, 1) -- volta suave para a frente
			olharGiro -= olharGiro * volta
			olharInclinacao -= olharInclinacao * volta
		end
		camera.CFrame *= CFrame.Angles(0, olharGiro, 0) * CFrame.Angles(olharInclinacao, 0, 0)
		return
	end
	olharGiro, olharInclinacao = 0, 0
	local distancia = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	-- (distância bem pequena = 1ª pessoa: o personagem some e o meio da tela já está livre)
	local alvo = if quad.mirandoGancho and distancia > 2 then 1 else 0
	misturaOmbro += (alvo - misturaOmbro) * math.min(dt * 10, 1)
	if misturaOmbro < 0.01 then
		return
	end
	local chegarPerto = math.max(distancia - quad.Config.GanchoCameraDistancia, 0)
	-- No espaço da câmera: X = direita, Y = cima, Z negativo = para frente.
	camera.CFrame *= CFrame.new((quad.Config.GanchoCameraOmbro - Vector3.new(0, 0, chegarPerto)) * misturaOmbro)
end

-- Mouse travado, analógico direito e toque giram a câmera do capô.
local function aoMoverParaOlhar(quad: Quadriciclo, entrada: InputObject, processado: boolean)
	if entrada.KeyCode == Enum.KeyCode.Thumbstick2 then
		local posicao = Vector2.new(entrada.Position.X, entrada.Position.Y)
		analogicoDireito = if posicao.Magnitude > 0.15 then posicao else Vector2.zero
		return
	end
	if quad.modoCamera ~= 3 then
		return
	end
	local sensibilidade = 0
	if entrada.UserInputType == Enum.UserInputType.MouseMovement
		and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	then
		sensibilidade = SENSIBILIDADE_MOUSE -- mouse travado no meio: gira (mirando ou não)
	elseif entrada.UserInputType == Enum.UserInputType.Touch and quad.mirandoGancho and not processado then
		sensibilidade = SENSIBILIDADE_TOQUE -- (toque em botão da tela não gira)
	end
	if sensibilidade == 0 then
		return
	end
	ultimoOlhar = os.clock()
	olharGiro = math.clamp(olharGiro - entrada.Delta.X * sensibilidade, -GIRO_MAXIMO, GIRO_MAXIMO)
	olharInclinacao = math.clamp(olharInclinacao - entrada.Delta.Y * sensibilidade, -INCLINACAO_MAXIMA, INCLINACAO_MAXIMA)
end

local function ligarCameraOmbro(quad: Quadriciclo)
	misturaOmbro, olharGiro, olharInclinacao = 0, 0, 0
	analogicoDireito = Vector2.zero
	RunService:BindToRenderStep(CAMERA_OMBRO, Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		atualizarCameraOmbro(quad, dt)
	end)
	conexaoOlhar = UserInputService.InputChanged:Connect(function(entrada: InputObject, processado: boolean)
		aoMoverParaOlhar(quad, entrada, processado)
	end)
end

local function desligarCameraOmbro()
	RunService:UnbindFromRenderStep(CAMERA_OMBRO)
	local conexao = conexaoOlhar
	if conexao then
		conexao:Disconnect()
	end
	conexaoOlhar = nil
	misturaOmbro = 0
end

-- Sentou: liga os controles do gancho, a troca de gancho, o HUD, a câmera de mira e o laço de cada frame.
function Gancho.ligar(quad: Quadriciclo)
	filtroSemAgua = criarFiltro(quad, true)
	filtroEscalada = criarFiltro(quad, false)
	-- Controle (L1) e celular (botão GANCHO): segure para mirar, solte para lançar. (O Q saiu.)
	ContextActionService:BindActionAtPriority(ACAO_GANCHO, function(_nomeAcao: string, estado: Enum.UserInputState, _entrada: InputObject): Enum.ContextActionResult?
		aoGancho(quad, estado)
		return Enum.ContextActionResult.Sink
	end, true, Veiculo.PRIORIDADE, Enum.KeyCode.ButtonL1)
	ContextActionService:SetTitle(ACAO_GANCHO, "GANCHO")
	-- (NOVO) Mouse: botão DIREITO mira, botão ESQUERDO lança (ou solta o gancho preso).
	table.insert(conexoesDoMouse, UserInputService.InputBegan:Connect(function(entrada: InputObject, processado: boolean)
		aoApertarMouse(quad, entrada, processado)
	end))
	table.insert(conexoesDoMouse, UserInputService.InputEnded:Connect(function(entrada: InputObject, _processado: boolean)
		aoSoltarMouse(quad, entrada)
	end))
	-- TROCAR DE GANCHO: 1, 2 e 3 escolhem direto; as setas ←/→ do controle passam de um em um.
	-- (false = sem botão novo no celular: lá é só tocar no ícone da barra.)
	-- Criou um 4º tipo? Coloque Enum.KeyCode.Four aqui no fim também.
	ContextActionService:BindActionAtPriority(ACAO_TROCAR_GANCHO, function(_nomeAcao: string, estado: Enum.UserInputState, entrada: InputObject): Enum.ContextActionResult?
		if estado == Enum.UserInputState.Begin then
			if entrada.KeyCode == Enum.KeyCode.DPadLeft then
				trocarGancho(-1)
			elseif entrada.KeyCode == Enum.KeyCode.DPadRight then
				trocarGancho(1)
			else
				for _, tipo in TIPOS_DE_GANCHO do
					if tipo.tecla == entrada.KeyCode then
						tipoSelecionado = tipo.id
					end
				end
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Veiculo.PRIORIDADE, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)
	conexaoCordaGancho = quad.chassi.ChildAdded:Connect(function(objeto: Instance)
		ajustarCordaDoGancho(quad, objeto)
	end)
	criarHudGancho(quad)
	ligarCameraOmbro(quad)
	conexaoHudGancho = RunService.Heartbeat:Connect(function(dt: number)
		atualizarGancho(quad, dt)
	end)
end

-- Levantou: solta o gancho (se estiver preso) e desliga tudo.
function Gancho.desligar(quad: Quadriciclo)
	ContextActionService:UnbindAction(ACAO_GANCHO)
	ContextActionService:UnbindAction(ACAO_TROCAR_GANCHO)
	for _, conexao in conexoesDoMouse do
		conexao:Disconnect() -- (NOVO) para de ouvir os botões do mouse
	end
	table.clear(conexoesDoMouse)
	quad.mirandoGancho = false
	soltarMeuGancho(quad) -- saiu do banco com o gancho preso: solta
	apagarEscalada()
	apagarImpulso() -- tira a força do impulso e o endireitador do pouso
	local conexaoCorda, conexaoHud = conexaoCordaGancho, conexaoHudGancho
	if conexaoCorda then
		conexaoCorda:Disconnect()
	end
	if conexaoHud then
		conexaoHud:Disconnect()
	end
	conexaoCordaGancho, conexaoHudGancho = nil, nil
	desligarCameraOmbro()
	destruirHudGancho()
	filtroSemAgua, filtroEscalada = nil, nil
end

-- =====================================================================
-- VISUAL E SONS DO GANCHO (todo mundo vê e ouve)
-- =====================================================================
-- Todo mundo vê: o gancho sai GIRANDO e a corda faz uma "barriga" que roda em volta da linha,
-- como uma corda de verdade. Quando prende, a corda estica reta. Cada computador desenha o
-- voo sozinho (liso a 60 FPS) com o que o Servidor publica: os Attributes "GanchoEstado" e
-- "GanchoTipo" e o ObjectValue "GanchoAlvo".
--
-- (NOVO) O MODELO 3D DE CADA TIPO: coloque no ReplicatedStorage um Model com um destes nomes:
--   GanchoModeloImpulso · GanchoModeloSegurar · GanchoModeloBotao
-- Sem o do tipo, o IMPULSO e o SEGURAR usam o "GanchoModelo" (se existir). Sem nenhum, o script
-- desenha um: o gancho de metal (laranja e brilhando no IMPULSO) e a mão branca no BOTÃO.
-- No SEU Model, coloque 2 Attachments (dentro de qualquer Part dele):
--   "Corda" = onde a corda amarra (a parte de TRÁS: o pulso da mão, a argola do gancho)
--   "Ponta" = a parte que encosta no alvo (a ponta do dedo, a ponta do gancho)
-- O script vira o modelo sozinho: a linha da "Corda" até a "Ponta" aponta para o alvo e a "Ponta"
-- chega bem no ponto. Atributo "Gira" no Model (true/false) escolhe se ele gira voando (o padrão
-- é girar; a mão do BOTÃO não gira). Os sons de cada tipo ficam na Configuracao (GanchoSom...).
local META_DO_GANCHO = 0.9 -- (seu modelo sem "Ponta") a ponta fica isso à frente do pivô dele
local META_DA_MAO = 1.55 -- (sua mão sem "Ponta") a ponta do dedo fica isso à frente do pivô dela
local PEDACOS_DA_CORDA = 10 -- (NOVO) em quantos pedaços (Beams) a corda é desenhada (mais = espiral mais lisa)
local VOLTAS_DA_ESPIRAL = 1.5 -- (NOVO) quantas voltas a espiral dá de uma ponta à outra da corda
local GIRO_DA_ESPIRAL = 14 -- (NOVO) (radianos/s) rapidez com que a espiral roda (14 = umas 2 voltas por segundo)

type VisualGancho = {
	pecas: Model, -- o gancho 3D (ou a mão)
	saida: Attachment, -- ponta da corda no quadriciclo
	ponta: Attachment, -- ponta da corda no gancho (o Attachment "Corda" do modelo)
	cordas: { Beam }, -- (NOVO) os pedaços da corda
	pontos: { Attachment }, -- (NOVO) os pontos da corda (o 1º é a "saida", o último é a "ponta")
	somPrender: Sound, -- toca no gancho quando ele prende
	prendeu: boolean, -- o som de prender já tocou?
	ajuste: CFrame, -- leva a "Ponta" do modelo até a ponta do voo (calculado quando o modelo aparece)
	gira: boolean, -- gira voando? (o gancho gira; a mão voa reta)
	tipo: string, -- "Impulso", "Segurar" ou "Botao" (para os sons e a cor)
}

-- Como CFrame.lookAt, mas sem quebrar quando a direção é quase vertical.
local function olharPara(posicao: Vector3, direcao: Vector3): CFrame
	local cima = if math.abs(direcao.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(posicao, posicao + direcao, cima)
end

-- A cor da corda de cada tipo (Configuracao): IMPULSO laranja, BOTÃO azul, SEGURAR a de sempre.
local function corDaCorda(Config: any, tipo: unknown): Color3
	if tipo == "Impulso" then
		return Config.GanchoCorCordaImpulso
	elseif tipo == "Botao" then
		return Config.GanchoCorCordaBotao
	end
	return Config.GanchoCorCorda
end

-- Toca o som DESTE tipo, se ele tiver um. ("sons" tem um som para cada tipo.)
local function tocarSomDoTipo(sons: { [string]: Sound }, tipo: unknown)
	local som = if typeof(tipo) == "string" then sons[tipo] else nil
	if som then
		som:Play()
	end
end

-- Coloca um Attachment com nome numa peça (nos modelos que o script desenha).
local function marcar(peca: BasePart, nome: string, posicao: Vector3)
	local anexo = Instance.new("Attachment")
	anexo.Name = nome
	anexo.Position = posicao
	anexo.Parent = peca
end

-- MÃO do gancho de BOTÃO (desenhada pelo script): uma luva branca de desenho animado com o dedo
-- indicador apontando. (A SUA mão: um Model "GanchoModeloBotao" no ReplicatedStorage, veja acima.)
local function criarMaoDoGancho(): Model
	local mao = Instance.new("Model")
	local function peca(tamanho: Vector3, cframe: CFrame, cor: Color3): Part
		local nova = Instance.new("Part")
		nova.Size = tamanho
		nova.CFrame = cframe
		nova.Material = Enum.Material.SmoothPlastic
		nova.Color = cor
		nova.Parent = mao
		return nova
	end
	local luva = Color3.fromRGB(245, 245, 245) -- branca
	local punho = Color3.fromRGB(205, 205, 215) -- cinza bem claro
	local palma = peca(Vector3.new(1, 0.5, 0.9), CFrame.identity, luva)
	mao.PrimaryPart = palma
	peca(Vector3.new(0.28, 0.28, 1.1), CFrame.new(-0.3, 0.05, -1), luva) -- dedo indicador, esticado para a frente
	peca(Vector3.new(0.68, 0.38, 0.38), CFrame.new(0.14, -0.08, -0.6), luva) -- os outros 3 dedos, dobrados
	peca(Vector3.new(0.26, 0.26, 0.55), CFrame.new(-0.62, -0.05, -0.2) * CFrame.Angles(0, math.rad(-25), 0), luva) -- polegar
	peca(Vector3.new(1.1, 0.62, 0.35), CFrame.new(0, 0, 0.6), punho) -- punho da luva
	marcar(palma, "Corda", Vector3.new(-0.3, 0.05, 0.8)) -- atrás do punho, na linha do dedo: a corda amarra aqui
	marcar(palma, "Ponta", Vector3.new(-0.3, 0.05, -1.55)) -- a ponta do dedo: é ela que encosta no botão
	return mao
end

-- GANCHO de metal (desenhado pelo script): haste, argola atrás (onde a corda prende) e 3 garras
-- viradas para trás.
local function criarGanchoPadrao(Config: any): Model
	local pecas = Instance.new("Model")
	local function peca(tamanho: Vector3, cframe: CFrame, forma: Enum.PartType): Part
		local nova = Instance.new("Part")
		nova.Shape = forma
		nova.Size = tamanho
		nova.CFrame = cframe
		nova.Material = Enum.Material.Metal
		nova.Color = Config.GanchoCorMetal
		nova.Parent = pecas
		return nova
	end
	local haste = peca(Vector3.new(0.28, 0.28, 1.8), CFrame.identity, Enum.PartType.Block)
	pecas.PrimaryPart = haste
	peca(Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, 0, 1), Enum.PartType.Ball) -- argola
	for i = 0, 2 do
		local garra = CFrame.new(0, 0, -0.9) * CFrame.Angles(0, 0, math.rad(i * 120)) -- na ponta, a cada 120°
			* CFrame.Angles(math.rad(-40), 0, 0) * CFrame.new(0, 0, 0.575) -- inclinada 40° para trás
		peca(Vector3.new(0.2, 0.2, 1.15), garra, Enum.PartType.Block)
	end
	marcar(haste, "Corda", Vector3.new(0, 0, 1)) -- no meio da argola
	marcar(haste, "Ponta", Vector3.new(0, 0, -0.9)) -- a ponta da haste
	return pecas
end

-- O SEU modelo deste tipo no ReplicatedStorage, ou nil. (O IMPULSO e o SEGURAR aceitam o "GanchoModelo".)
local function moldeDoTipo(tipo: string): Model?
	local achado = ReplicatedStorage:FindFirstChild("GanchoModelo" .. tipo)
	if achado == nil and tipo ~= "Botao" then
		achado = ReplicatedStorage:FindFirstChild("GanchoModelo")
	end
	if achado and achado:IsA("Model") and achado:FindFirstChildWhichIsA("BasePart", true) then
		return achado
	end
	return nil
end

-- A peça principal do modelo: a PrimaryPart, ou a primeira Part que achar.
local function pecaPrincipal(pecas: Model): BasePart
	local principal = pecas.PrimaryPart
	if principal then
		return principal
	end
	for _, objeto in pecas:GetDescendants() do
		if objeto:IsA("BasePart") then
			return objeto
		end
	end
	error("O modelo do gancho não tem nenhuma Part.") -- (não acontece: o moldeDoTipo confere antes)
end

-- Um Attachment com este nome dentro do modelo, ou nil. (Só vale Attachment: se uma Part também se
-- chamar "Ponta", ela é pulada.)
local function anexoDoModelo(pecas: Model, nome: string): Attachment?
	for _, objeto in pecas:GetDescendants() do
		if objeto.Name == nome and objeto:IsA("Attachment") then
			return objeto
		end
	end
	return nil
end

local function criarVisualGancho(quad: Quadriciclo): VisualGancho
	local Config = quad.Config
	local tipoLido = quad.modelo:GetAttribute("GanchoTipo") -- "Impulso", "Segurar" ou "Botao" (o Servidor marca)
	local tipo = if typeof(tipoLido) == "string" then tipoLido else "Segurar"
	local molde = moldeDoTipo(tipo)
	local pecas: Model
	if molde then
		pecas = molde:Clone() :: Model -- o SEU modelo (o "::" só confirma para o Studio que a cópia é um Model)
	elseif tipo == "Botao" then
		pecas = criarMaoDoGancho() -- a mão desenhada
	else
		pecas = criarGanchoPadrao(Config) -- o gancho de metal desenhado
	end
	for _, objeto in pecas:GetDescendants() do -- só enfeite: não bate, não pesa, a mira atravessa
		if objeto:IsA("BasePart") then
			objeto.Anchored = true
			objeto.CanCollide = false
			objeto.CanTouch = false
			objeto.CanQuery = false
			objeto.CastShadow = false
			if tipo == "Impulso" and molde == nil then
				objeto.Color = Config.GanchoCorCordaImpulso -- o gancho DESENHADO do IMPULSO brilha laranja (o seu fica como você fez)
				objeto.Material = Enum.Material.Neon
			end
		end
	end
	local principal = pecaPrincipal(pecas)
	-- AJUSTE: onde a "Ponta" fica e para onde ela aponta, medidos a partir do pivô do modelo.
	local pivo = pecas:GetPivot()
	local anexoPonta = anexoDoModelo(pecas, "Ponta")
	local anexoCorda = anexoDoModelo(pecas, "Corda")
	local pontaLocal = if anexoPonta
		then pivo:PointToObjectSpace(anexoPonta.WorldPosition)
		else Vector3.new(0, 0, -(if tipo == "Botao" then META_DA_MAO else META_DO_GANCHO)) -- sem "Ponta": à frente do pivô
	local eixo = Vector3.new(0, 0, -1) -- sem "Ponta" ou sem "Corda": a frente do pivô aponta para o alvo
	if anexoPonta and anexoCorda then
		local daCordaAPonta = pontaLocal - pivo:PointToObjectSpace(anexoCorda.WorldPosition)
		if daCordaAPonta.Magnitude > 0.01 then
			eixo = daCordaAPonta.Unit
		end
	end
	local ajuste = olharPara(pontaLocal, eixo):Inverse()
	local ponta = anexoCorda or Instance.new("Attachment") -- sem "Corda": a corda amarra no meio da peça principal
	if ponta.Parent == nil then
		ponta.Parent = principal
	end
	local giraLido = pecas:GetAttribute("Gira")
	local gira = if typeof(giraLido) == "boolean" then giraLido else tipo ~= "Botao"
	local saida = Instance.new("Attachment")
	saida.Name = "SaidaCordaVisual"
	saida.Parent = quad.chassi
	-- (NOVO) A CORDA EM PEDAÇOS: vários pontos (Attachments) ligados por Beams. Assim ela pode fazer a
	-- espiral (várias curvas), coisa que uma Beam sozinha não consegue.
	local pontos: { Attachment } = { saida }
	for i = 1, PEDACOS_DA_CORDA - 1 do
		local ponto = Instance.new("Attachment")
		ponto.Name = "PontoDaCorda" .. i
		ponto.Parent = principal -- (dentro do gancho: some junto quando o visual é apagado)
		table.insert(pontos, ponto)
	end
	table.insert(pontos, ponta)
	local cordas: { Beam } = {}
	for i = 1, PEDACOS_DA_CORDA do
		local corda = Instance.new("Beam")
		corda.Attachment0 = pontos[i]
		corda.Attachment1 = pontos[i + 1]
		corda.Width0 = Config.GanchoLarguraCorda
		corda.Width1 = Config.GanchoLarguraCorda
		corda.Color = ColorSequence.new(corDaCorda(Config, tipo)) -- cada tipo tem a cor da sua corda
		corda.Transparency = NumberSequence.new(0)
		corda.LightInfluence = 1
		corda.FaceCamera = true
		corda.Segments = 8 -- (cada pedaço é curto: 8 já fica liso)
		corda.Parent = pecas
		table.insert(cordas, corda)
	end
	local somPrender = Instance.new("Sound")
	somPrender.Name = "SomGanchoPrender"
	somPrender.SoundId = somDoTipo(Config, "Prender", tipo) -- o som de prender DESTE tipo
	somPrender.Volume = 0.8
	somPrender.RollOffMaxDistance = 150
	somPrender.Parent = principal
	pecas.Name = "GanchoVisual"
	pecas.Parent = quad.modelo -- dentro do quadriciclo: some junto com ele, e a mira do gancho ignora
	return {
		pecas = pecas, saida = saida, ponta = ponta, cordas = cordas, pontos = pontos, somPrender = somPrender, prendeu = false,
		ajuste = ajuste, gira = gira, tipo = tipo,
	}
end

-- Chamado uma vez para cada quadriciclo que aparece no seu jogo.
function Gancho.criarVisual(quad: Quadriciclo)
	local Config = quad.Config
	local modelo = quad.modelo
	local visualGancho: VisualGancho? = nil
	local conexaoVisualGancho: RBXScriptConnection? = nil
	local saidaDoGancho: Attachment? = nil -- o "SaidaGancho" que o Servidor usa (de onde a corda sai)
	local percorridoVisual = 0 -- quantos studs o gancho desenhado já voou
	local giroGancho = 0
	local curvaCorda = 0
	-- (NOVO) Um som de LANÇAR e um de RECOLHER para cada tipo (Configuracao: GanchoSomLancarImpulso...).
	local sonsLancar: { [string]: Sound } = {}
	local sonsRecolher: { [string]: Sound } = {}
	for _, tipo in TIPOS_DE_GANCHO do
		sonsLancar[tipo.id] = Veiculo.criarSom(quad, "SomGanchoLancar" .. tipo.id, somDoTipo(Config, "Lancar", tipo.id), false)
		sonsRecolher[tipo.id] = Veiculo.criarSom(quad, "SomGanchoRecolher" .. tipo.id, somDoTipo(Config, "Recolher", tipo.id), false)
	end

	local function apagarVisualGancho(comSom: boolean)
		local visual = visualGancho
		if visual then
			visual.pecas:Destroy()
			visual.saida:Destroy()
			if comSom then
				tocarSomDoTipo(sonsRecolher, visual.tipo) -- o som de recolher DESTE tipo
			end
		end
		visualGancho = nil
		local conexao = conexaoVisualGancho
		if conexao then
			conexao:Disconnect()
		end
		conexaoVisualGancho = nil
	end

	-- Roda a cada frame enquanto o gancho existe (para todo mundo, não só para o motorista).
	local function atualizarVisualGancho(dt: number)
		local estado = modelo:GetAttribute("GanchoEstado")
		if estado == nil then
			apagarVisualGancho(true) -- soltou: some tudo
			return
		end
		local valor = modelo:FindFirstChild("GanchoAlvo")
		local alvo = if valor and valor:IsA("ObjectValue") then valor.Value else nil
		if saidaDoGancho == nil then
			local achada = modelo:FindFirstChild("SaidaGancho", true)
			saidaDoGancho = if achada and achada:IsA("Attachment") then achada else nil
		end
		local saida = saidaDoGancho
		if not (alvo and alvo:IsA("Attachment")) or saida == nil then
			return -- ainda chegando pela internet
		end
		local visual = visualGancho or criarVisualGancho(quad)
		visualGancho = visual
		-- Onde está a ponta agora: sai do quadriciclo e anda GanchoVelocidadeVoo studs/s até o alvo
		-- (a mesma velocidade do Servidor). Se ele já disse "Preso", o desenho acelera para alcançar.
		local origem = saida.WorldPosition
		local caminho = alvo.WorldPosition - origem
		local distancia = caminho.Magnitude
		local direcao = if distancia > 0.01 then caminho / distancia else Vector3.zAxis
		percorridoVisual += Config.GanchoVelocidadeVoo * (if estado == "Preso" then 2 else 1) * dt
		local progresso = math.clamp(percorridoVisual / math.max(distancia, 1), 0, 1)
		local voando = progresso < 1
		if voando then
			giroGancho += if visual.gira then dt * Config.GanchoGiro else 0 -- (a mão do BOTÃO voa reta, sem girar)
		elseif estado == "Preso" and not visual.prendeu then
			visual.prendeu = true
			visual.somPrender:Play() -- chegou e prendeu
		end
		local pontaAgora = origem + caminho * progresso
		-- A "Ponta" do modelo fica na ponta do voo, apontando para o alvo e girando em volta da linha.
		visual.pecas:PivotTo(olharPara(pontaAgora, direcao) * CFrame.Angles(0, 0, giroGancho) * visual.ajuste)
		-- (NOVO) A corda de FÍSICA (a RopeConstraint "CordaGancho" do Servidor) fica sempre INVISÍVEL:
		-- quem desenha a corda são só os pedaços (Beams) deste visual.
		local cordaFisica = quad.chassi:FindFirstChild(NOME_CORDA_GANCHO)
		local folga = 0 -- quantos studs de corda "sobram" (corda frouxa)
		if cordaFisica and cordaFisica:IsA("RopeConstraint") then
			cordaFisica.Visible = false
			folga = math.max(cordaFisica.Length - distancia, 0)
		end
		-- (NOVO) CORDA EM ESPIRAL: voando, ela sai girando como um saca-rolha. Quando prende, a espiral some.
		local fimDaCorda = visual.ponta.WorldPosition -- onde ela amarra no gancho (ele já está no lugar deste frame)
		local trecho = fimDaCorda - origem
		local eixo = if trecho.Magnitude > 0.01 then trecho.Unit else direcao
		local larguraMaxima = if typeof(Config.GanchoEspiralLargura) == "number" then Config.GanchoEspiralLargura else 1.5
		local larguraAlvo = if voando then math.min(trecho.Magnitude * 0.15, larguraMaxima) else 0
		curvaCorda += (larguraAlvo - curvaCorda) * math.min(dt * 10, 1) -- (agora curvaCorda = a largura da espiral)
		-- SEGURAR preso com a corda FROUXA: ela faz uma "barriga" para baixo, do tamanho da folga.
		local barriga = if not voando and visual.tipo == "Segurar" then math.sqrt(3 * distancia * folga / 8) else 0
		local lados = olharPara(origem, eixo) -- dois "lados" da corda (direita e cima), para desenhar a espiral
		local fase = os.clock() * GIRO_DA_ESPIRAL -- a espiral roda sem parar
		local quantos = #visual.pontos - 1
		local posicoes: { Vector3 } = {}
		for i = 0, quantos do
			local t = i / quantos -- 0 = no quadriciclo · 1 = no gancho
			local angulo = fase + t * VOLTAS_DA_ESPIRAL * 2 * math.pi
			local largura = curvaCorda * math.sin(math.pi * t) -- 0 nas pontas, mais larga no meio
			local espiral = (lados.RightVector * math.cos(angulo) + lados.UpVector * math.sin(angulo)) * largura
			local caida = Vector3.new(0, -barriga * 4 * t * (1 - t), 0) -- (a barriga: 0 nas pontas, maior no meio)
			table.insert(posicoes, origem + trecho * t + espiral + caida)
		end
		-- Cada ponto aponta (eixo X) para onde a corda segue: assim os pedaços se emendam lisinhos, sem quinas.
		for i, ponto in visual.pontos do
			local segue = posicoes[math.min(i + 1, #posicoes)] - posicoes[math.max(i - 1, 1)]
			local rumo = if segue.Magnitude > 0.001 then segue.Unit else eixo
			ponto.WorldCFrame = olharPara(posicoes[i], rumo) * CFrame.Angles(0, math.rad(90), 0)
		end
		for i, pedaco in visual.cordas do
			local curva = (posicoes[i + 1] - posicoes[i]).Magnitude / 3
			pedaco.CurveSize0 = curva -- sai do ponto i na direção da corda...
			pedaco.CurveSize1 = -curva -- ...e chega no ponto i+1 na direção da corda
		end
	end

	local function aoMudarEstadoGancho()
		if modelo:GetAttribute("GanchoEstado") ~= nil and conexaoVisualGancho == nil then
			percorridoVisual = 0
			giroGancho = 0
			curvaCorda = 0
			conexaoVisualGancho = RunService.PreRender:Connect(atualizarVisualGancho)
			if modelo:GetAttribute("GanchoEstado") == "NoAr" then
				tocarSomDoTipo(sonsLancar, modelo:GetAttribute("GanchoTipo")) -- o gancho saiu (o som do tipo dele)
			end
		end
	end

	Veiculo.guardarConexao(quad, modelo:GetAttributeChangedSignal("GanchoEstado"):Connect(aoMudarEstadoGancho))
	table.insert(quad.limpezas, function()
		apagarVisualGancho(false) -- o quadriciclo saiu do seu jogo: o desenho some (sem som)
	end)
	aoMudarEstadoGancho() -- quem entra no jogo com um gancho já no ar também vê
end

return Gancho
