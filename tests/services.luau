--=====================================================================
-- Serviços falsos
--=====================================================================
DB = {}          -- DataStore normal:  [key] = value
RANK = {}        -- OrderedDataStore:  [key] = value
SENT = {}        -- payloads enviados: [playerName] = { ... }
FAIL_SORTED = false

local function makeStore()
	return {
		GetAsync = function(_, key) return DB[key] end,
		SetAsync = function(_, key, value) DB[key] = value end,
		UpdateAsync = function(_, key, transform)
			local result = transform(DB[key])
			if result ~= nil then DB[key] = result end
			return result
		end,
	}
end

local function makeOrdered()
	return {
		SetAsync = function(_, key, value) RANK[key] = value end,
		GetSortedAsync = function(_, ascending, pageSize)
			if FAIL_SORTED then error("DataStore throttled (teste)", 0) end
			local arr = {}
			for k, v in RANK do table.insert(arr, { key = k, value = v }) end
			table.sort(arr, function(a, b)
				if ascending then return a.value < b.value end
				return a.value > b.value
			end)
			while #arr > pageSize do table.remove(arr) end
			return { GetCurrentPage = function() return arr end }
		end,
	}
end

PlayersService = {
	list = {},
	PlayerAdded = newSignal(),
	PlayerRemoving = newSignal(),
	GetPlayers = function(self)
		local copy = {}
		for _, p in self.list do table.insert(copy, p) end
		return copy
	end,
}

function makePlayer(name, userId)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name .. "Disp"
	p.UserId = userId
	return p
end

function joinPlayer(p)
	table.insert(PlayersService.list, p)
	PlayersService.PlayerAdded:Fire(p)
end

function leavePlayer(p)
	for i, x in PlayersService.list do
		if x == p then table.remove(PlayersService.list, i) break end
	end
	PlayersService.PlayerRemoving:Fire(p)
end

local TAGS = {}
local services = {
	CollectionService = {
		AddTag = function(_, inst, tag) TAGS[tag] = TAGS[tag] or {}; table.insert(TAGS[tag], inst) end,
		GetTagged = function(_, tag) return TAGS[tag] or {} end,
	},
	DataStoreService = {
		GetDataStore = function() return makeStore() end,
		GetOrderedDataStore = function() return makeOrdered() end,
	},
	Players = PlayersService,
	ReplicatedStorage = { Children = {}, WaitForChild = function() return "PlaytimeConfig" end },
	UserService = {
		GetUserInfosByUserIdsAsync = function(_, ids)
			local out = {}
			for _, id in ids do
				table.insert(out, { Id = id, Username = "User" .. id, DisplayName = "Nome" .. id })
			end
			return out
		end,
	},
}

workspace = {
	FindFirstChildWhichIsA = function() return nil end,
	Children = {},
}

game = {
	GetService = function(_, name)
		assert(services[name], "servico nao stubado: " .. name)
		return services[name]
	end,
	BindToClose = function(_, fn) CLOSE_HANDLER = fn end,
}

-- RemoteEvent falso: grava o que foi enviado pra cada jogador
local realNew = Instance.new
Instance.new = function(className)
	local inst = realNew(className)
	if className == "RemoteEvent" then
		inst.FireClient = function(_, player, payload) SENT[player.Name] = payload end
	end
	return inst
end
