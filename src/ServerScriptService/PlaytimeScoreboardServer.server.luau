--!optimize 2
--[[
	PlaytimeScoreboardServer
	------------------------
	Script (servidor) -> ServerScriptService

	O que ele faz:
	  - Conta o tempo de jogo SEM nenhum loop por frame (o tempo e calculado
	    na hora em que alguem pergunta: base salva + os.time() - entrada).
	  - Salva em DataStore e manda o ranking pro OrderedDataStore.
	  - Monta a placa de madeira no mundo.
	  - Manda o top N pros clientes de tempos em tempos.

	Ao todo sao 2 loops no servidor inteiro (ranking e autosave), ambos
	medidos em dezenas de segundos. Custo de CPU praticamente zero.
]]

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage:WaitForChild("PlaytimeConfig"))

local TAG = "[Placa de Tempo]"

--------------------------------------------------------------------------
-- Remote
--------------------------------------------------------------------------

local remote = Instance.new("RemoteEvent")
remote.Name = "PlaytimeBoardUpdate"
remote.Parent = ReplicatedStorage

--------------------------------------------------------------------------
-- DataStores (com degradacao elegante se a API estiver desligada)
--------------------------------------------------------------------------

local playerStore: DataStore
local rankStore: OrderedDataStore
local dataOk = true

local function disableData(err: any)
	if not dataOk then
		return
	end
	dataOk = false
	warn(("%s sem acesso ao DataStore (%s)."):format(TAG, tostring(err)))
	warn(("%s no Studio: Home > Game Settings > Security > Enable Studio Access to API Services."):format(TAG))
	warn(("%s a placa continua funcionando, mas so com o tempo desta sessao."):format(TAG))
end

do
	local ok, err = pcall(function()
		playerStore = DataStoreService:GetDataStore(Config.DataStoreName)
		rankStore = DataStoreService:GetOrderedDataStore(Config.DataStoreName .. "_Rank")
	end)
	if not ok then
		disableData(err)
	end
end

-- Avisa logo de cara se a API estiver desligada, em vez de so na hora de salvar.
task.spawn(function()
	if not dataOk then
		return
	end
	local ok, err = pcall(playerStore.GetAsync, playerStore, "__probe")
	if not ok then
		local msg = string.lower(tostring(err))
		if string.find(msg, "403") or string.find(msg, "not allowed") or string.find(msg, "studio") then
			disableData(err)
		end
	end
end)

local function retry(fn: () -> any, tries: number?): (boolean, any)
	local attempts = tries or 3
	local lastErr: any = nil
	for i = 1, attempts do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		if i < attempts then
			task.wait(i * 2)
		end
	end
	return false, lastErr
end

--------------------------------------------------------------------------
-- Sessoes
--------------------------------------------------------------------------

-- Uma sessao em andamento. O tempo total nao fica guardado aqui: e calculado
-- na hora em totalFor(), somando o que ja estava salvo com o tempo da sessao.
type Session = {
	base: number,   -- segundos ja salvos no DataStore
	joined: number, -- os.time() de quando entrou
	loaded: boolean,
}

-- Uma linha do ranking, do jeito que vai para o cliente.
type Entry = {
	userId: number,
	seconds: number,
	online: boolean,
	name: string?,
	display: string?,
}

type UserName = { name: string, display: string }

local sessions: { [Player]: Session } = {}
local nameCache: { [number]: UserName } = {}
local cachedList: { Entry } = {}

local function totalFor(player: Player): number
	local s = sessions[player]
	if not s then
		return 0
	end
	return s.base + (os.time() - s.joined)
end

--------------------------------------------------------------------------
-- Leaderstats (opcional)
--------------------------------------------------------------------------

local function ensureLeaderstats(player: Player): StringValue?
	if not Config.Leaderstats then
		return nil
	end
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local value = folder:FindFirstChild(Config.LeaderstatsName)
	if value and not value:IsA("StringValue") then
		-- Ja existe outra coisa com esse nome; nao mexe no sistema do jogo.
		return nil
	end
	if not value then
		value = Instance.new("StringValue")
		value.Name = Config.LeaderstatsName
		value.Value = Config.FormatShort(totalFor(player))
		value.Parent = folder
	end
	return value
end

local function updateLeaderstats(player: Player)
	local value = ensureLeaderstats(player)
	if value then
		local text = Config.FormatShort(totalFor(player))
		if value.Value ~= text then
			value.Value = text
		end
	end
end

--------------------------------------------------------------------------
-- Nomes (1 chamada web pra todos os ids que faltam, com cache)
--------------------------------------------------------------------------

local function resolveNames(ids: { number })
	local missing: { number } = {}
	for _, id in ids do
		if not nameCache[id] then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok and infos then
		for _, info in infos do
			nameCache[info.Id] = { name = info.Username, display = info.DisplayName }
		end
	end
	-- Quem falhar fica de fora do cache e e tentado de novo no proximo refresh.
end

--------------------------------------------------------------------------
-- Montar o ranking
--------------------------------------------------------------------------

local function refreshBoard()
	local candidates: { [number]: number } = {}

	if dataOk then
		local ok, pages = retry(function()
			return rankStore:GetSortedAsync(false, math.clamp(Config.TopCount, 1, 100))
		end, 2)
		if ok and pages then
			for _, entry in pages:GetCurrentPage() do
				local id = tonumber(entry.key)
				local secs = tonumber(entry.value)
				if id and secs then
					candidates[id] = math.max(candidates[id] or 0, secs)
				end
			end
		elseif not ok then
			-- Falha passageira: so avisa. Desligar o DataStore aqui faria o
			-- servidor inteiro parar de salvar por causa de um soluco da API.
			warn(("%s falha ao ler o ranking: %s"):format(TAG, tostring(pages)))
		end
	end

	-- Quem esta online entra com o tempo ao vivo, mesmo antes do proximo save.
	local online: { [number]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local s = sessions[player]
		if s and s.loaded then
			candidates[player.UserId] = math.max(candidates[player.UserId] or 0, totalFor(player))
			online[player.UserId] = true
		end
	end

	local list: { Entry } = {}
	for id, secs in candidates do
		table.insert(list, {
			userId = id,
			seconds = secs,
			online = online[id] or false,
		})
	end

	table.sort(list, function(a: Entry, b: Entry)
		if a.seconds == b.seconds then
			return a.userId < b.userId
		end
		return a.seconds > b.seconds
	end)

	while #list > Config.TopCount do
		table.remove(list)
	end

	local ids: { number } = {}
	for _, entry in list do
		table.insert(ids, entry.userId)
	end
	resolveNames(ids)

	for _, entry in list do
		local cached = nameCache[entry.userId]
		entry.name = cached and cached.name or "..."
		entry.display = cached and cached.display or "..."
	end

	cachedList = list
end

--------------------------------------------------------------------------
-- Envio pros clientes
--------------------------------------------------------------------------

local function pushTo(player: Player)
	local s = sessions[player]
	remote:FireClient(player, {
		entries = cachedList,
		you = (s and s.loaded) and { seconds = totalFor(player) } or nil,
	})
end

local function pushAll()
	for _, player in Players:GetPlayers() do
		pushTo(player)
	end
end

--------------------------------------------------------------------------
-- Salvar
--------------------------------------------------------------------------

local function savePlayer(player: Player)
	if not dataOk then
		return
	end
	local s = sessions[player]
	if not s or not s.loaded then
		return
	end

	local total = totalFor(player)
	if total <= 0 then
		return
	end

	local key = Config.KeyPrefix .. player.UserId
	local ok, err = pcall(function()
		playerStore:UpdateAsync(key, function(old): number?
			local previous = tonumber(old) or 0
			if total <= previous then
				return nil -- cancela a escrita, nao ha nada novo
			end
			return total
		end)
	end)

	if not ok then
		warn(("%s falha ao salvar %s: %s"):format(TAG, player.Name, tostring(err)))
		return
	end

	pcall(function()
		rankStore:SetAsync(tostring(player.UserId), total)
	end)
end

--------------------------------------------------------------------------
-- Entrada / saida
--------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local session = { base = 0, joined = os.time(), loaded = false }
	sessions[player] = session
	nameCache[player.UserId] = { name = player.Name, display = player.DisplayName }

	if dataOk then
		local ok, value = retry(function()
			return playerStore:GetAsync(Config.KeyPrefix .. player.UserId)
		end)
		if ok then
			session.base = math.max(0, tonumber(value) or 0)
		else
			warn(("%s falha ao carregar %s: %s"):format(TAG, player.Name, tostring(value)))
		end
	end

	-- Saiu enquanto carregava: nao salva nada por cima do progresso dele.
	if sessions[player] ~= session then
		return
	end

	session.loaded = true
	updateLeaderstats(player)
	pushTo(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	savePlayer(player)
	sessions[player] = nil
end)

game:BindToClose(function()
	local pending = 0
	for _, player in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			savePlayer(player)
			pending -= 1
		end)
	end
	local waited = 0
	while pending > 0 and waited < 25 do
		waited += task.wait(0.1)
	end
end)

--------------------------------------------------------------------------
-- Construcao da placa de madeira
--------------------------------------------------------------------------

local function resolveBoardCFrame(): CFrame
	if Config.BoardPosition then
		return CFrame.new(Config.BoardPosition) * CFrame.Angles(0, math.rad(Config.BoardRotationY or 0), 0)
	end

	-- Sem posicao definida: coloca atras do spawn, virada pra quem nasce.
	local spawnPart = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local height = Config.BoardHeight / 2 + (Config.ShowPosts and Config.PostHeight or 0)

	if spawnPart then
		local groundY = spawnPart.Position.Y - spawnPart.Size.Y / 2
		local behind = spawnPart.Position - spawnPart.CFrame.LookVector * 14
		local position = Vector3.new(behind.X, groundY + height, behind.Z)
		return CFrame.lookAt(position, Vector3.new(spawnPart.Position.X, position.Y, spawnPart.Position.Z))
	end

	return CFrame.new(0, height, 0) * CFrame.Angles(0, math.rad(Config.BoardRotationY or 0), 0)
end

local function buildBoard()
	local palette = Config.Palette
	local width, height = Config.BoardWidth, Config.BoardHeight
	local base = resolveBoardCFrame()

	local model = Instance.new("Model")
	model.Name = "PlaytimeBoard"

	local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = material
		part.Anchored = true
		part.CanCollide = Config.BoardCollide
		part.CanTouch = false  -- sem eventos de toque
		part.CanQuery = false  -- raycasts ignoram a placa
		part.CastShadow = Config.BoardCastShadow
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		return part
	end

	-- Painel: a face "Front" dele e onde a tela aparece.
	local panel = newPart(
		"Panel",
		Vector3.new(width, height, 0.4),
		base,
		palette.Panel,
		Enum.Material.SmoothPlastic
	)

	-- Moldura escura por tras, sobrando nas bordas.
	newPart(
		"Frame",
		Vector3.new(width + 0.9, height + 0.9, 0.5),
		base * CFrame.new(0, 0, 0.3),
		palette.WoodDark,
		Enum.Material.WoodPlanks
	)

	-- Telhadinho de duas aguas.
	local topY = (height + 0.9) / 2
	local run = width * 0.28
	local angle = math.rad(22)
	local offsetX = run * math.cos(angle)
	local offsetY = run * math.sin(angle)
	local roofSize = Vector3.new(run * 2, 0.4, 2.0)

	newPart("RoofLeft", roofSize, base * CFrame.new(-offsetX, topY + offsetY, 0.2) * CFrame.Angles(0, 0, angle), palette.WoodMid, Enum.Material.WoodPlanks)
	newPart("RoofRight", roofSize, base * CFrame.new(offsetX, topY + offsetY, 0.2) * CFrame.Angles(0, 0, -angle), palette.WoodMid, Enum.Material.WoodPlanks)
	newPart("Ridge", Vector3.new(0.55, 0.55, 2.2), base * CFrame.new(0, topY + offsetY * 2, 0.2), palette.WoodDark, Enum.Material.WoodPlanks)

	-- Pernas.
	if Config.ShowPosts then
		local postHeight = Config.PostHeight
		local postY = -(height + 0.9) / 2 - postHeight / 2
		local postX = width / 2 - 0.6
		newPart("PostLeft", Vector3.new(0.8, postHeight, 0.8), base * CFrame.new(-postX, postY, 0.3), palette.WoodMid, Enum.Material.Wood)
		newPart("PostRight", Vector3.new(0.8, postHeight, 0.8), base * CFrame.new(postX, postY, 0.3), palette.WoodMid, Enum.Material.Wood)
	end

	model.PrimaryPart = panel
	model.Parent = workspace
	CollectionService:AddTag(panel, Config.BoardTag)

	return panel
end

if Config.AutoBuildBoard and #CollectionService:GetTagged(Config.BoardTag) == 0 then
	buildBoard()
end

--------------------------------------------------------------------------
-- Loop 1: ranking
--------------------------------------------------------------------------

task.spawn(function()
	refreshBoard()
	pushAll()
	while true do
		task.wait(Config.RefreshInterval)
		refreshBoard()
		pushAll()
		for _, player in Players:GetPlayers() do
			updateLeaderstats(player)
		end
	end
end)

--------------------------------------------------------------------------
-- Loop 2: autosave (espalhado, pra nao estourar o limite do DataStore)
--------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		if dataOk then
			for _, player in Players:GetPlayers() do
				savePlayer(player)
				task.wait(Config.SaveSpacing)
			end
		end
	end
end)
