--!strict
--[[
	=====================================================================
	Progresso  (Script normal)
	Local: ServerScriptService > Progresso
	=====================================================================

	Cuida do PROGRESSO de cada jogador e mostra na tabela do TAB:
	  METROS ...... o RECORDE de altura (em metros) a partir do "marco zero" do lobby. Quem subiu
	                mais a montanha fica em cima na tabela.
	  DINHEIRO .... ganha pegando MOEDAS no mapa e chegando em CHECKPOINTS novos. Mais pra frente,
	                vai servir para comprar skins, carros e turbos: a loja só vai precisar mexer em
	                leaderstats.Dinheiro.Value, e este script salva sozinho.
	  CHECKPOINT .. o último checkpoint alcançado: quando você morre ou reseta, nasce nele.
	Tudo fica SALVO (DataStore): quando o jogador sai, a cada minuto (só se mudou algo) e quando o
	servidor fecha.

	COMO MONTAR NO MAPA (na janela Properties, lá embaixo: "Tags" e "Attributes"):
	  MARCO ZERO .. uma Part chamada "MarcoZero" no lobby (pode ser invisível e sem colisão).
	                A altura dela é o 0 metro. Sem ela, vale a altura do SpawnLocation.
	  CHECKPOINT .. uma Part com a tag "Checkpoint" e o atributo "Numero" (number): 1, 2, 3...
	                na ordem do caminho. Dica: faça um "portal" grande e grosso (uns 10 studs), com
	                CanCollide desligado, para o veículo rápido não passar "pulando" por ele.
	                O jogador nasce em cima da parte de BAIXO dele.
	  MOEDA ....... uma Part ancorada com a tag "Moeda". Atributo "Valor" (number) opcional (padrão 1).
	                Cada jogador pega cada moeda de novo só depois de MOEDA_VOLTA segundos.
	  (Criou o atributo como TEXTO ("string") sem querer? Funciona do mesmo jeito, mas o Output avisa
	   para você trocar para "number".)

	No Studio, para SALVAR funcionar: Home > Game Settings > Security >
	"Enable Studio Access to API Services" (ligado). Sem isso, tudo funciona, mas não salva.
	O LocalScript "AvisosProgresso" mostra as mensagens na tela de cada jogador.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- =====================================================================
-- AJUSTES
-- =====================================================================
local STUDS_POR_METRO = 3.57 -- no Roblox, 1 stud ≈ 0,28 metro (então 3,57 studs = 1 metro)
local MOEDA_VOLTA = 60 -- (s) a mesma moeda volta para o mesmo jogador depois disso
local BONUS_CHECKPOINT = 10 -- dinheiro ganho ao chegar num checkpoint NOVO
local SALVAR_A_CADA = 60 -- (s) salvamento automático (só salva quem mudou alguma coisa)
local NOME_DO_COFRE = "ProgressoQuadriciclo_v1" -- nome do DataStore (trocar = todo mundo recomeça do zero)
local TAG_CHECKPOINT = "Checkpoint"
local TAG_MOEDA = "Moeda"
local TAG_QUADRICICLO = "Quadriciclo" -- (o QuadricicloServidor coloca esta tag nos veículos prontos)

-- O "aviso" para a tela do jogador (quem escuta é o LocalScript AvisosProgresso).
local aviso = Instance.new("RemoteEvent")
aviso.Name = "AvisoProgresso"
aviso.Parent = ReplicatedStorage

-- =====================================================================
-- O 0 METRO: a Part "MarcoZero" (ou o SpawnLocation, se não tiver)
-- =====================================================================
local function alturaDoZero(): number
	local marco = workspace:FindFirstChild("MarcoZero", true)
	if marco and marco:IsA("BasePart") then
		return marco.Position.Y
	end
	local nascer = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if nascer then
		return nascer.Position.Y
	end
	return 0
end
local ZERO = alturaDoZero()

-- =====================================================================
-- O PROGRESSO DE CADA JOGADOR (enquanto ele está no jogo)
-- =====================================================================
type Dados = { dinheiro: number, metros: number, checkpoint: number }
type Progresso = {
	metros: IntValue, -- (na tabela do TAB) o recorde de altura
	dinheiro: IntValue, -- (na tabela do TAB)
	checkpoint: number, -- o último checkpoint alcançado (0 = nenhum ainda)
	podeSalvar: boolean, -- false se não deu para carregar (assim não apaga o que já estava salvo)
	moedas: { [BasePart]: number }, -- quando (os.clock) ele pegou cada moeda
	ultimoSalvo: string, -- os dados da última vez que salvou (se não mudou nada, não precisa salvar de novo)
	salvando: boolean, -- está salvando agora? (assim nunca salva duas vezes ao mesmo tempo)
}
local progressos: { [Player]: Progresso } = {}
local cofre = DataStoreService:GetDataStore(NOME_DO_COFRE)

-- Um número (ou o padrão, se não for número). Aceita também número escrito como TEXTO ("1", "1555").
local function numero(valor: unknown, padrao: number): number
	if typeof(valor) == "number" then
		return valor
	elseif typeof(valor) == "string" then
		return tonumber(valor) or padrao
	end
	return padrao
end

-- Avisa (uma vez por peça) quando um atributo foi criado como TEXTO em vez de número.
local avisadas: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function conferirAtributoNumero(peca: Instance, atributo: string)
	local valor = peca:GetAttribute(atributo)
	if typeof(valor) == "string" and not avisadas[peca] then
		avisadas[peca] = true
		warn(`[Progresso] "{peca:GetFullName()}" tem o atributo "{atributo}" como TEXTO ("{valor}"). Funciona, mas`
			.. ` o certo é apagar o atributo e criar de novo como "number".`)
	end
end

-- O número de um checkpoint (atributo "Numero"), ou nil se não tiver.
local function numeroDoCheckpoint(parte: Instance): number?
	local valor = numero(parte:GetAttribute("Numero"), -1)
	return if valor >= 0 then valor else nil
end

-- =====================================================================
-- CARREGAR E SALVAR (DataStore)
-- =====================================================================
local function chave(jogador: Player): string
	return "J_" .. jogador.UserId
end

local function emTexto(dados: Dados): string
	return `{dados.dinheiro}|{dados.metros}|{dados.checkpoint}`
end

-- Lê o que está salvo (tenta 3 vezes). Devolve os dados e se deu certo.
local function carregar(jogador: Player): (Dados, boolean)
	for tentativa = 1, 3 do
		local ok, salvo = pcall(function()
			return cofre:GetAsync(chave(jogador))
		end)
		if ok then
			local tabela = if typeof(salvo) == "table" then salvo else {} -- jogador novo = tabela vazia
			return {
				dinheiro = numero(tabela.dinheiro, 0),
				metros = numero(tabela.metros, 0),
				checkpoint = numero(tabela.checkpoint, 0),
			}, true
		end
		warn(`[Progresso] Não deu para carregar {jogador.Name} (tentativa {tentativa}): {salvo}`)
		if tentativa < 3 then
			task.wait(2)
		end
	end
	return { dinheiro = 0, metros = 0, checkpoint = 0 }, false
end

-- Salva (tenta 3 vezes). Se nada mudou desde o último salvamento, não gasta o DataStore à toa.
local function salvar(jogador: Player)
	local progresso = progressos[jogador]
	if progresso == nil or not progresso.podeSalvar then
		return
	end
	while progresso.salvando do
		task.wait(0.1) -- (outro salvamento deste jogador ainda está acontecendo: espera ele terminar)
	end
	-- (copia os valores ANTES de esperar a internet)
	local dados: Dados = { dinheiro = progresso.dinheiro.Value, metros = progresso.metros.Value, checkpoint = progresso.checkpoint }
	local texto = emTexto(dados)
	if texto == progresso.ultimoSalvo then
		return -- nada mudou
	end
	progresso.salvando = true
	for tentativa = 1, 3 do
		local ok, erro = pcall(function()
			-- UpdateAsync é o jeito recomendado pelo Roblox para salvar (mais seguro que SetAsync).
			cofre:UpdateAsync(chave(jogador), function(_antigo: unknown): Dados
				return dados
			end)
		end)
		if ok then
			progresso.ultimoSalvo = texto
			break
		end
		warn(`[Progresso] Não deu para salvar {jogador.Name} (tentativa {tentativa}): {erro}`)
		if tentativa < 3 then
			task.wait(2)
		end
	end
	progresso.salvando = false
end

-- =====================================================================
-- CHECKPOINTS
-- =====================================================================
-- A Part do checkpoint com este número (ou nil).
local function acharCheckpoint(numeroDele: number): BasePart?
	for _, objeto in CollectionService:GetTagged(TAG_CHECKPOINT) do
		if objeto:IsA("BasePart") and numeroDoCheckpoint(objeto) == numeroDele then
			return objeto
		end
	end
	return nil
end

-- Nasceu (ou renasceu): leva o personagem para o último checkpoint.
local function nascerNoCheckpoint(jogador: Player, personagem: Model)
	local progresso = progressos[jogador]
	if progresso == nil or progresso.checkpoint <= 0 then
		return -- ainda carregando, ou nenhum checkpoint ainda (nasce no lobby)
	end
	local parte = acharCheckpoint(progresso.checkpoint)
	if parte == nil or personagem:WaitForChild("HumanoidRootPart", 10) == nil then
		return
	end
	task.wait() -- deixa o Roblox terminar de colocar o personagem no SpawnLocation...
	if personagem.Parent then
		-- ...e leva para o checkpoint: 4 studs acima da parte de baixo dele, virado para onde ele aponta.
		personagem:PivotTo(parte.CFrame * CFrame.new(0, -parte.Size.Y / 2 + 4, 0))
	end
end

-- Chegou num checkpoint: se for um NOVO (número maior que o atual), guarda e dá o bônus.
local function chegouNoCheckpoint(jogador: Player, parte: BasePart)
	local progresso = progressos[jogador]
	local numeroDele = numeroDoCheckpoint(parte)
	if progresso == nil or numeroDele == nil or numeroDele <= progresso.checkpoint then
		return -- ainda carregando, checkpoint sem número, ou um que ele já passou
	end
	progresso.checkpoint = numeroDele
	progresso.dinheiro.Value += BONUS_CHECKPOINT
	jogador:SetAttribute("Checkpoint", numeroDele) -- (o AvisosProgresso pinta os checkpoints que você já passou)
	aviso:FireClient(jogador, "Checkpoint", numeroDele, BONUS_CHECKPOINT)
end

-- =====================================================================
-- MOEDAS
-- =====================================================================
local function pegouMoeda(jogador: Player, moeda: BasePart)
	local progresso = progressos[jogador]
	if progresso == nil then
		return
	end
	local agora = os.clock()
	local ultimaVez = progresso.moedas[moeda]
	if ultimaVez and agora - ultimaVez < MOEDA_VOLTA then
		return -- ele já pegou esta moeda há pouco tempo
	end
	progresso.moedas[moeda] = agora
	local valor = math.max(math.floor(numero(moeda:GetAttribute("Valor"), 1)), 0)
	progresso.dinheiro.Value += valor
	aviso:FireClient(jogador, "Moeda", moeda, valor, MOEDA_VOLTA) -- a moeda some só para ele, por um tempo
end

-- =====================================================================
-- QUEM ENCOSTOU? Um personagem, ou um veículo (aí vale todo mundo sentado nele)
-- =====================================================================
-- Os bancos de cada veículo (procurados uma vez só: o caminhão monstro tem mais de 100 peças).
local bancosDoVeiculo: { [Model]: { VehicleSeat | Seat } } = setmetatable({}, { __mode = "k" }) :: any

local function bancosDe(modelo: Model): { VehicleSeat | Seat }
	local bancos = bancosDoVeiculo[modelo]
	if bancos == nil then
		local lista: { VehicleSeat | Seat } = {}
		for _, filho in modelo:GetChildren() do
			if filho:IsA("VehicleSeat") or filho:IsA("Seat") then
				table.insert(lista, filho)
			end
		end
		bancosDoVeiculo[modelo] = lista
		bancos = lista
	end
	return bancos
end

local function jogadoresDaPeca(peca: BasePart): { Player }
	local modelo = peca:FindFirstAncestorOfClass("Model")
	while modelo do
		local jogador = Players:GetPlayerFromCharacter(modelo)
		if jogador then
			return { jogador }
		end
		if CollectionService:HasTag(modelo, TAG_QUADRICICLO) then
			local lista: { Player } = {}
			for _, banco in bancosDe(modelo) do
				local humanoide = banco.Occupant
				local personagem = if humanoide then humanoide.Parent else nil
				local dono = if personagem and personagem:IsA("Model") then Players:GetPlayerFromCharacter(personagem) else nil -- (o IsA confirma que é um Model)
				if dono then
					table.insert(lista, dono)
				end
			end
			return lista
		end
		modelo = modelo:FindFirstAncestorOfClass("Model")
	end
	return {}
end

-- Liga o "encostou" de cada checkpoint e de cada moeda (os que já estão no mapa e os que aparecerem).
local function prepararCheckpoint(objeto: Instance)
	if not objeto:IsA("BasePart") then
		return
	end
	local parte: BasePart = objeto
	conferirAtributoNumero(parte, "Numero")
	parte.CanTouch = true
	parte.Touched:Connect(function(outra: BasePart)
		for _, jogador in jogadoresDaPeca(outra) do
			chegouNoCheckpoint(jogador, parte)
		end
	end)
end

local function prepararMoeda(objeto: Instance)
	if not objeto:IsA("BasePart") then
		return
	end
	local moeda: BasePart = objeto
	conferirAtributoNumero(moeda, "Valor")
	moeda.CanTouch = true
	moeda.CanCollide = false -- moeda não é parede: o veículo passa por dentro
	moeda.Touched:Connect(function(outra: BasePart)
		for _, jogador in jogadoresDaPeca(outra) do
			pegouMoeda(jogador, moeda)
		end
	end)
end

for _, objeto in CollectionService:GetTagged(TAG_CHECKPOINT) do
	prepararCheckpoint(objeto)
end
CollectionService:GetInstanceAddedSignal(TAG_CHECKPOINT):Connect(prepararCheckpoint)
for _, objeto in CollectionService:GetTagged(TAG_MOEDA) do
	prepararMoeda(objeto)
end
CollectionService:GetInstanceAddedSignal(TAG_MOEDA):Connect(prepararMoeda)

-- =====================================================================
-- ENTROU / SAIU
-- =====================================================================
local function aoEntrar(jogador: Player)
	-- A pasta "leaderstats" é o que aparece na tabela do TAB (a 1ª coluna ordena a tabela).
	local pasta = Instance.new("Folder")
	pasta.Name = "leaderstats"
	local metros = Instance.new("IntValue")
	metros.Name = "Metros"
	metros.Parent = pasta
	local dinheiro = Instance.new("IntValue")
	dinheiro.Name = "Dinheiro"
	dinheiro.Parent = pasta

	local dados, deuCerto = carregar(jogador)
	if jogador.Parent == nil then
		return -- saiu enquanto carregava
	end
	metros.Value = dados.metros
	dinheiro.Value = dados.dinheiro
	progressos[jogador] = {
		metros = metros,
		dinheiro = dinheiro,
		checkpoint = dados.checkpoint,
		podeSalvar = deuCerto,
		moedas = {},
		ultimoSalvo = emTexto(dados), -- (acabou de carregar: igual ao que está salvo)
		salvando = false,
	}
	jogador:SetAttribute("Checkpoint", dados.checkpoint)
	pasta.Parent = jogador
	if not deuCerto then
		aviso:FireClient(jogador, "Erro", "Não deu para carregar seu progresso: ele não será salvo nesta partida.")
	end
	jogador.CharacterAdded:Connect(function(personagem: Model)
		nascerNoCheckpoint(jogador, personagem)
	end)
	local personagem = jogador.Character
	if personagem then
		task.spawn(nascerNoCheckpoint, jogador, personagem) -- (ele já tinha nascido enquanto carregava)
	end
end

Players.PlayerAdded:Connect(aoEntrar)
for _, jogador in Players:GetPlayers() do
	task.spawn(aoEntrar, jogador) -- (quem entrou antes deste script rodar)
end

Players.PlayerRemoving:Connect(function(jogador: Player)
	salvar(jogador)
	progressos[jogador] = nil
end)

-- =====================================================================
-- METROS: 4 vezes por segundo, mede a altura de cada um e guarda o recorde
-- =====================================================================
task.spawn(function()
	while true do
		task.wait(0.25)
		for jogador, progresso in progressos do
			local personagem = jogador.Character
			local raiz = if personagem then personagem:FindFirstChild("HumanoidRootPart") else nil
			if raiz and raiz:IsA("BasePart") then
				local metros = math.floor((raiz.Position.Y - ZERO) / STUDS_POR_METRO)
				if metros > progresso.metros.Value then
					progresso.metros.Value = metros -- novo recorde!
				end
			end
		end
	end
end)

-- =====================================================================
-- SALVAR: a cada minuto (quem mudou algo), e quando o servidor fecha
-- =====================================================================
task.spawn(function()
	while true do
		task.wait(SALVAR_A_CADA)
		for jogador in progressos do
			task.spawn(salvar, jogador)
		end
	end
end)

game:BindToClose(function()
	local faltam = 0
	for jogador in progressos do
		faltam += 1
		task.spawn(function()
			salvar(jogador) -- (se o PlayerRemoving já estiver salvando este jogador, espera e não salva de novo)
			faltam -= 1
		end)
	end
	local limite = os.clock() + 25 -- (o Roblox espera no máximo 30 s)
	while faltam > 0 and os.clock() < limite do
		task.wait(0.1)
	end
end)
