--!strict
--[[
	=====================================================================
	Gancho  (ModuleScript)
	Local: ServerScriptService > QuadricicloServidor > Gancho
	=====================================================================

	O GANCHO no servidor: voo, corda no cenário, segurar/puxar personagens, botões e recarga.
	O QuadricicloCliente mira e manda "GanchoLiga" (alvo + ponto do impacto + tipo) ou "GanchoDesliga".
	Aqui conferimos tudo, contamos o voo do gancho, aplicamos o efeito e desfazemos ao soltar.
	O gancho girando e a corda são DESENHADOS em cada cliente (fica liso para todo mundo),
	a partir do que publicamos no modelo e no Player:
	  modelo: Attribute "GanchoEstado"  = "NoAr" (voando), "Preso" ou nil (nada)
	          Attribute "GanchoTipo"    = "Impulso", "Segurar" ou "Botao"
	          ObjectValue "GanchoAlvo"  = Attachment onde o gancho vai prender
	  Player: Attribute "GanchoRecargaAte" + tipo = horário em que aquele gancho volta a funcionar
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local Montagem = require(script.Parent:WaitForChild("Montagem"))
type Veiculo = Montagem.Veiculo
type Config = Montagem.Config

local Gancho = {}

local TAG_BOTAO_GANCHO = "BotaoGancho" -- tag (CollectionService) ou nome da peça
local NOME_CORDA_GANCHO = "CordaGancho" -- o QuadricicloCliente procura este nome para acertar o tamanho da corda
local TEMPO_MAX_VOO = 3 -- (s) se o gancho não chegar nesse tempo, errou

-- Os tipos de gancho que existem (o cliente manda qual o jogador escolheu na barra):
--   "Impulso" = só prende no CENÁRIO (o puxão, o pêndulo e o estilingue quem faz é o cliente)
--   "Segurar" = prende no cenário (corda, escalada) OU prende outro jogador no lugar
--   "Botao"   = só aperta os BotaoGancho
local TIPOS_DE_GANCHO: { [string]: boolean } = { Impulso = true, Segurar = true, Botao = true }

-- Um BindableEvent só, para TODOS os veículos: ServerStorage > BotaoGanchoAtivado.
-- Nas portas: evento.Event:Connect(function(botao, ligado, jogador) ... end)
local function pegarEventoDosBotoes(): BindableEvent
	local existente = ServerStorage:FindFirstChild("BotaoGanchoAtivado")
	if existente and existente:IsA("BindableEvent") then
		return existente
	end
	local novo = Instance.new("BindableEvent")
	novo.Name = "BotaoGanchoAtivado"
	novo.Parent = ServerStorage
	return novo
end
local eventoBotoesGancho = pegarEventoDosBotoes()

-- O gancho de UM veículo.
type Estado = {
	v: Veiculo,
	saida: Attachment, -- de onde a corda sai: o "SaidaGancho" do veículo (ou o centro do Chassi)
	alvo: ObjectValue, -- "GanchoAlvo": os clientes desenham o voo até este Attachment
	pecas: { Instance }, -- tudo que o gancho criou (some ao soltar)
	conexao: RBXScriptConnection?, -- laço do voo ou do puxão
	desfazer: (() -> ())?, -- o que fazer ao soltar (ex.: botão volta a ficar vermelho)
	dono: Player?, -- quem lançou o gancho que está voando ou preso agora
	tipo: string, -- o TIPO do gancho que está voando ou preso agora (cada tipo tem a sua recarga)
}
local estados: { [Model]: Estado } = {}

-- Quantos segundos cada tipo recarrega depois de usar (os números ficam na Configuracao).
local function recargaDoTipo(Config: Config, tipo: string): number
	if tipo == "Impulso" then
		return Config.GanchoRecargaImpulso
	elseif tipo == "Botao" then
		return Config.GanchoRecargaBotao
	end
	return Config.GanchoRecargaSegurar
end

-- O alcance de cada tipo: o SEGURAR é mais curto (GanchoAlcanceSegurar); o IMPULSO e o BOTÃO
-- usam o GanchoAlcance. (O cliente confere com a mesma regra.)
local function alcanceDoTipo(Config: Config, tipo: string): number
	return if tipo == "Segurar" then Config.GanchoAlcanceSegurar else Config.GanchoAlcance
end

local function guardar(estado: Estado, objeto: Instance)
	table.insert(estado.pecas, objeto)
end

-- Solta o gancho: desfaz tudo que ele criou e começa a recarga de quem lançou.
local function soltar(estado: Estado)
	local conexao = estado.conexao
	if conexao then
		conexao:Disconnect()
	end
	estado.conexao = nil
	local desfazer = estado.desfazer
	estado.desfazer = nil
	if desfazer then
		desfazer()
	end
	for _, objeto in estado.pecas do
		objeto:Destroy()
	end
	table.clear(estado.pecas)
	local dono = estado.dono
	estado.dono = nil
	if dono then
		-- Usou o gancho: começa a RECARGA DESTE TIPO (cada tipo tem a sua). Fica no Player, então trocar
		-- de veículo não zera. O nome junta o tipo: "GanchoRecargaAteImpulso", "GanchoRecargaAteSegurar"...
		dono:SetAttribute("GanchoRecargaAte" .. estado.tipo, workspace:GetServerTimeNow() + recargaDoTipo(estado.v.Config, estado.tipo))
	end
	estado.alvo.Value = nil
	estado.v.modelo:SetAttribute("GanchoEstado", nil)
	estado.v.modelo:SetAttribute("GanchoTipo", nil)
end

-- Attachment no ponto do impacto, "grudado" na peça atingida (anda junto se ela se mexer).
local function criarPonta(estado: Estado, parte: BasePart, ponto: Vector3): Attachment
	local ponta = Instance.new("Attachment")
	ponta.Name = "PontaGancho"
	ponta.Position = parte.CFrame:PointToObjectSpace(ponto)
	ponta.Parent = parte
	guardar(estado, ponta)
	return ponta
end

-- Sobe a partir da peça procurando quem está "dentro" dela: um Model com Humanoid (funciona até
-- acertando um chapéu) ou um VEÍCULO com alguém sentado (aí o alvo é quem está dirigindo).
local function humanoideDe(parte: Instance): Humanoid?
	local atual = parte.Parent
	while atual and atual ~= workspace do
		if atual:IsA("Model") then
			local humanoide = atual:FindFirstChildOfClass("Humanoid")
			if humanoide then
				return humanoide
			end
			local banco = atual:FindFirstChildWhichIsA("VehicleSeat")
			if banco and banco:IsA("VehicleSeat") and banco.Occupant then
				return banco.Occupant -- acertou outro veículo: vale o motorista dele
			end
		end
		atual = atual.Parent
	end
	return nil
end

-- O ponto precisa estar NA peça (um trapaceiro poderia mandar um ponto no meio do céu).
local function pontoNaPeca(parte: BasePart, ponto: Vector3): boolean
	if parte:IsA("Terrain") then
		return true
	end
	local p = parte.CFrame:PointToObjectSpace(ponto)
	local limite = parte.Size / 2 + Vector3.one -- 1 stud de folga
	return math.abs(p.X) <= limite.X and math.abs(p.Y) <= limite.Y and math.abs(p.Z) <= limite.Z
end

-- Peça presa no mundo: Terrain, ancorada ou soldada em algo ancorado (parede, chão, poste).
local function pecaFixa(parte: BasePart): boolean
	if parte:IsA("Terrain") or parte.Anchored then
		return true
	end
	local raiz = parte.AssemblyRootPart -- pode ser nil
	return if raiz then raiz.Anchored else false
end

-- CENÁRIO: RopeConstraint do Chassi até a ponta, do tamanho da distância de AGORA.
-- Caindo, o veículo fica pendurado (balança como pêndulo); no chão, não passa desse raio.
local function prenderNoCenario(estado: Estado, ponta: Attachment)
	local v = estado.v
	local corda = Instance.new("RopeConstraint")
	corda.Name = NOME_CORDA_GANCHO
	corda.Attachment0 = estado.saida
	corda.Attachment1 = ponta
	corda.Length = math.max((ponta.WorldPosition - estado.saida.WorldPosition).Magnitude, v.Config.GanchoComprimentoMinimo)
	corda.Restitution = 0 -- não quica quando estica
	-- A corda nasce DESLIGADA. Quem liga é o computador do motorista (módulo Gancho do cliente), já com
	-- o tamanho TRAVADO na distância exata do instante em que o gancho chegou. Assim ela nunca "estica"
	-- nem dá tranco por causa do atraso da internet.
	corda.Enabled = false
	corda.Visible = v.Config.DEBUG_MODE -- (a corda que todo mundo vê é desenhada pelos clientes)
	corda.Parent = v.chassi
	guardar(estado, corda)
end

-- PERSONAGEM: AlignPosition no HumanoidRootPart, levando o alvo para perto do veículo.
-- Modo OneAttachment = vai até um PONTO do mundo. Ligar o alvo direto no veículo (dois
-- Attachments) juntaria as duas físicas, e um dos jogadores perderia o Network Ownership.
local function puxarPersonagem(estado: Estado, humanoide: Humanoid, raiz: BasePart, ponta: Attachment)
	local v = estado.v
	local Config = v.Config
	-- Sentado (em outro veículo)? Arranca do banco, senão puxaríamos o veículo inteiro.
	local banco = humanoide.SeatPart
	local solda = if banco then banco:FindFirstChild("SeatWeld") else nil
	if solda then
		solda:Destroy()
	end

	local puxao = Instance.new("AlignPosition")
	puxao.Name = "PuxaoGancho"
	puxao.Mode = Enum.PositionAlignmentMode.OneAttachment
	puxao.Attachment0 = ponta
	puxao.ApplyAtCenterOfMass = true -- puxa pelo centro: o boneco não sai girando
	puxao.MaxForce = Config.GanchoForcaPuxao
	puxao.MaxVelocity = Config.GanchoVelocidadePuxao
	puxao.Responsiveness = 30
	puxao.Position = raiz.Position
	puxao.Parent = raiz
	guardar(estado, puxao)
	-- Rede de segurança: o puxão some sozinho mesmo se algo der errado aqui.
	Debris:AddItem(puxao, Config.GanchoTempoMaxPuxao + 1)
	Debris:AddItem(ponta, Config.GanchoTempoMaxPuxao + 1)

	local inicio = os.clock()
	estado.conexao = RunService.Heartbeat:Connect(function()
		if humanoide.Health <= 0 or not raiz:IsDescendantOf(workspace) or os.clock() - inicio > Config.GanchoTempoMaxPuxao then
			soltar(estado) -- morreu, sumiu ou passou do tempo máximo
			return
		end
		-- Destino: GanchoDistanciaParada studs do Chassi, do lado em que o personagem está.
		local daqui = raiz.Position - v.chassi.Position
		local lado = Vector3.new(daqui.X, 0, daqui.Z)
		lado = if lado.Magnitude > 0.1 then lado.Unit else v.assento.CFrame.LookVector
		puxao.Position = v.chassi.Position + lado * Config.GanchoDistanciaParada + Vector3.new(0, 2, 0)
	end)
end

-- BOTÃO: muda a cor, marca o Attribute "Ativado" e avisa pelo BindableEvent.
local function mudarBotaoGancho(Config: Config, botao: BasePart, ligado: boolean, jogador: Player)
	botao.Color = if ligado then Config.GanchoCorBotaoLigado else Config.GanchoCorBotaoDesligado
	botao:SetAttribute("Ativado", ligado)
	eventoBotoesGancho:Fire(botao, ligado, jogador)
end

local function acionarBotaoGancho(estado: Estado, botao: BasePart, jogador: Player)
	local Config = estado.v.Config
	mudarBotaoGancho(Config, botao, true, jogador)
	if not Config.GanchoBotaoFicaLigado then
		estado.desfazer = function()
			mudarBotaoGancho(Config, botao, false, jogador) -- soltou o gancho: volta a ficar vermelho
		end
	end
end

-- PRENDER NO LUGAR (gancho SEGURAR em outro jogador): ele fica parado onde estava por
-- Config.GanchoTempoSegurar segundos. Se ele estiver dirigindo, quem fica parado é o VEÍCULO dele
-- (ele continua sentado). Serve para atrapalhar um rival... e para AJUDAR um amigo que está caindo:
-- ele fica parado no ar e dá tempo de usar o próprio gancho.
-- (AlignPosition no modo OneAttachment = segura num PONTO do mundo, sem ligar os dois veículos.)
local function segurarPersonagem(estado: Estado, humanoide: Humanoid, raiz: BasePart)
	local v = estado.v
	local Config = v.Config
	-- O que vamos segurar: o veículo inteiro (se ele estiver sentado) ou o próprio personagem.
	local pecaSegura: BasePart = raiz
	local banco = humanoide.SeatPart
	if banco then
		pecaSegura = banco.AssemblyRootPart or banco -- a peça principal do veículo (no quadriciclo, o Chassi)
	end
	local anexo = Instance.new("Attachment")
	anexo.Name = "PrenderGancho"
	anexo.Parent = pecaSegura
	guardar(estado, anexo)

	local prender = Instance.new("AlignPosition")
	prender.Name = "PrenderGancho"
	prender.Mode = Enum.PositionAlignmentMode.OneAttachment
	prender.Attachment0 = anexo
	prender.ApplyAtCenterOfMass = true -- segura pelo centro: não sai girando
	prender.MaxForce = Config.GanchoForcaPuxao
	prender.Responsiveness = 60 -- bem "duro": quase não sai do lugar
	prender.Position = anexo.WorldPosition -- o lugar onde ele estava quando o gancho chegou
	prender.Parent = pecaSegura
	guardar(estado, prender)
	-- Rede de segurança: solta sozinho mesmo se algo der errado aqui.
	Debris:AddItem(prender, Config.GanchoTempoSegurar + 1)
	Debris:AddItem(anexo, Config.GanchoTempoSegurar + 1)

	local inicio = os.clock()
	estado.conexao = RunService.Heartbeat:Connect(function()
		local longe = (raiz.Position - v.chassi.Position).Magnitude > alcanceDoTipo(Config, "Segurar") + 30
		if humanoide.Health <= 0 or not raiz:IsDescendantOf(workspace) or longe or os.clock() - inicio > Config.GanchoTempoSegurar then
			soltar(estado) -- morreu, sumiu, você foi para longe demais ou acabou o tempo
		end
	end)
end

-- O gancho VOA até o alvo e só prende quando chega. O servidor só conta a distância
-- percorrida; quem desenha o gancho girando e a corda rodando são os clientes.
local function lancar(estado: Estado, jogador: Player, alvo: BasePart, ponto: Vector3, humanoide: Humanoid?, raiz: BasePart?, tipo: string)
	local v = estado.v
	local Config = v.Config
	estado.dono = jogador
	estado.tipo = tipo
	v.modelo:SetAttribute("GanchoTipo", tipo) -- os clientes desenham o gancho deste tipo (a mão, a cor da corda...)
	local ponta: Attachment
	if raiz then
		ponta = Instance.new("Attachment") -- personagem: a ponta fica no HumanoidRootPart (segue o boneco)
		ponta.Name = "PontaGancho"
		ponta.Parent = raiz
		guardar(estado, ponta)
	else
		ponta = criarPonta(estado, alvo, ponto)
	end
	estado.alvo.Value = ponta
	v.modelo:SetAttribute("GanchoEstado", "NoAr")

	local percorrido = 0
	local inicio = os.clock()
	estado.conexao = RunService.Heartbeat:Connect(function(dt: number)
		if not ponta:IsDescendantOf(workspace) or (humanoide and humanoide.Health <= 0) or os.clock() - inicio > TEMPO_MAX_VOO then
			soltar(estado) -- o alvo sumiu, morreu ou o gancho demorou demais: errou
			return
		end
		percorrido += Config.GanchoVelocidadeVoo * dt
		if percorrido < (ponta.WorldPosition - estado.saida.WorldPosition).Magnitude then
			return -- ainda voando
		end
		-- CHEGOU: aplica o efeito de verdade.
		local conexao = estado.conexao
		if conexao then
			conexao:Disconnect()
		end
		estado.conexao = nil
		if humanoide and raiz then
			if Config.GanchoSegurarJogador == "Puxar" then
				puxarPersonagem(estado, humanoide, raiz, ponta) -- traz o jogador até você (o jeito antigo)
			else
				segurarPersonagem(estado, humanoide, raiz) -- prende o jogador (ou o veículo dele) no lugar
			end
		elseif CollectionService:HasTag(alvo, TAG_BOTAO_GANCHO) or alvo.Name == TAG_BOTAO_GANCHO then
			acionarBotaoGancho(estado, alvo, jogador)
		else
			prenderNoCenario(estado, ponta)
		end
		v.modelo:SetAttribute("GanchoEstado", "Preso")
	end)
end

-- =====================================================================
-- PARA O QuadricicloServidor
-- =====================================================================
-- O veículo apareceu: prepara o gancho dele.
function Gancho.ligar(v: Veiculo)
	-- De onde a corda sai: um Attachment "SaidaGancho" seu (opcional) ou o centro do Chassi.
	-- No centro, o veículo fica nivelado quando está pendurado.
	local achadoSaida = v.modelo:FindFirstChild("SaidaGancho", true)
	local saida: Attachment
	if achadoSaida and achadoSaida:IsA("Attachment") then
		saida = achadoSaida
	else
		saida = Instance.new("Attachment")
		saida.Name = "SaidaGancho"
		saida.Parent = v.chassi
	end
	-- Onde o gancho vai prender: os clientes desenham o voo até este Attachment.
	local achadoAlvo = v.modelo:FindFirstChild("GanchoAlvo")
	local alvo: ObjectValue
	if achadoAlvo and achadoAlvo:IsA("ObjectValue") then
		alvo = achadoAlvo
	else
		alvo = Instance.new("ObjectValue")
		alvo.Name = "GanchoAlvo"
		alvo.Parent = v.modelo
	end
	local estado: Estado = { v = v, saida = saida, alvo = alvo, pecas = {}, conexao = nil, desfazer = nil, dono = nil, tipo = "Segurar" }
	estados[v.modelo] = estado
	table.insert(v.limpezas, function()
		soltar(estado) -- o veículo sumiu: solta o gancho (e a recarga começa)
		if estados[v.modelo] == estado then
			estados[v.modelo] = nil
		end
	end)
end

-- Solta o gancho deste veículo (o motorista saiu do banco, pulou, morreu ou apertou E).
function Gancho.soltar(v: Veiculo)
	local estado = estados[v.modelo]
	if estado then
		soltar(estado)
	end
end

-- "GanchoDesliga": só quem lançou consegue soltar.
function Gancho.aoDesligar(v: Veiculo, jogador: Player)
	local estado = estados[v.modelo]
	if estado and estado.dono == jogador then
		soltar(estado)
	end
end

-- "GanchoLiga" chega com: alvo, ponto do impacto e o TIPO escolhido na barra.
-- (Quem chama, o QuadricicloServidor, já conferiu que o jogador é o motorista.)
function Gancho.aoLigar(v: Veiculo, jogador: Player, alvo: unknown, ponto: unknown, tipo: unknown)
	local estado = estados[v.modelo]
	if estado == nil or estado.dono ~= nil then
		return -- (já tem um gancho voando ou preso)
	end
	-- Confere tudo: quem manda é o cliente, e um trapaceiro pode mandar qualquer coisa.
	if typeof(alvo) ~= "Instance" or typeof(ponto) ~= "Vector3" or typeof(tipo) ~= "string" or not TIPOS_DE_GANCHO[tipo] then
		return -- (tipo que não existe = ignorado)
	end
	if not alvo:IsA("BasePart") or not alvo:IsDescendantOf(workspace) or alvo:IsDescendantOf(v.modelo) then
		return
	end
	-- RECARGA DESTE TIPO: enquanto não passar o horário marcado no Player, este gancho não funciona.
	local recargaAte = jogador:GetAttribute("GanchoRecargaAte" .. tipo)
	if typeof(recargaAte) == "number" and recargaAte > workspace:GetServerTimeNow() then
		return
	end
	-- Alcance com folga: o servidor vê o veículo um pouco atrasado (mais rápido = mais folga).
	local alcanceMaximo = alcanceDoTipo(v.Config, tipo) + 15 + v.chassi.AssemblyLinearVelocity.Magnitude * 0.5
	local humanoide = humanoideDe(alvo)
	local raiz = if humanoide then humanoide.RootPart else nil
	-- Personagem: mede até o boneco (ele se mexe). Outras peças: o ponto precisa estar nelas.
	local referencia = if raiz then raiz.Position else ponto
	if (referencia - v.chassi.Position).Magnitude > alcanceMaximo then
		return
	end
	local ehBotao = CollectionService:HasTag(alvo, TAG_BOTAO_GANCHO) or alvo.Name == TAG_BOTAO_GANCHO
	if humanoide then
		-- JOGADOR: só o gancho SEGURAR pega jogadores.
		if tipo ~= "Segurar" or raiz == nil or humanoide.Health <= 0 or humanoide.Parent == jogador.Character then
			return -- outro tipo, personagem sem HumanoidRootPart, morto, ou você mesmo
		end
	elseif not pontoNaPeca(alvo, ponto) then
		return
	elseif ehBotao then
		-- BOTÃO: só a mão (gancho BOTÃO) aperta botões.
		if tipo ~= "Botao" then
			return
		end
	elseif tipo == "Botao" or not pecaFixa(alvo) then
		return -- a mão só aperta botões; e peça SOLTA é ignorada (uma corda nela bagunçaria o Network Ownership)
	end
	lancar(estado, jogador, alvo, ponto, humanoide, raiz, tipo)
	Montagem.debugPrint(v, `Gancho {tipo} de {jogador.Name} lançado em "{alvo:GetFullName()}"`)
end

return Gancho
