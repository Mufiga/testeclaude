--===================== ambiente falso (cliente) =====================
local NOW = 500
task = {}
function task.wait(t) coroutine.yield() return t or 0 end
function task.spawn(fn, ...) local co = coroutine.create(fn); local ok, e = coroutine.resume(co, ...); if not ok then error(e, 0) end end
function warn(...) print("[warn]", ...) end
local __realos = os
os = setmetatable({ clock = function() return NOW end, time = function() return NOW end }, { __index = __realos })
function setClock(v) NOW = v end

Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3) end
Vector3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3.Magnitude = nil
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = {
	new = function(sx, ox, sy, oy) return { X = { Scale = sx } , Y = { Scale = sy } } end,
	fromScale = function(sx, sy) return { X = { Scale = sx }, Y = { Scale = sy } } end,
}
ColorSequence = { new = function(a, b) return { a, b } end }
Enum = setmetatable({}, { __index = function(_, g)
	return setmetatable({}, { __index = function(_, i) return g .. "." .. i end })
end })

function newSignal()
	local s = { h = {} }
	function s:Connect(fn) table.insert(self.h, fn) end
	function s:Fire(...) for _, fn in self.h do fn(...) end end
	return s
end

ALL = {}
Instance = { new = function(cn)
	local inst = { ClassName = cn, Children = {}, Name = cn }
	function inst:IsA(c) return self.ClassName == c end
	function inst:Destroy() end
	table.insert(ALL, inst)
	return inst
end }

local addedSig, removedSig = newSignal(), newSignal()
BOARD_PART = { ClassName = "Part", Position = Vector3.new(0, 0, 0) }
function BOARD_PART:IsA(c) return c == "BasePart" or c == "Part" end
-- Magnitude precisa existir no resultado da subtracao
Vector3.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2) end
	return rawget(Vector3, k)
end

REMOTE = { OnClientEvent = newSignal() }
local playerGui = { ClassName = "PlayerGui", Children = {} }
LOCAL_PLAYER = { UserId = 777, Name = "Eu", WaitForChild = function() return playerGui end }

local services = {
	CollectionService = {
		GetTagged = function() return { BOARD_PART } end,
		GetInstanceAddedSignal = function() return addedSig end,
		GetInstanceRemovedSignal = function() return removedSig end,
	},
	Players = { LocalPlayer = LOCAL_PLAYER },
	ReplicatedStorage = {
		WaitForChild = function(_, name)
			if name == "PlaytimeBoardUpdate" then return REMOTE end
			return "PlaytimeConfig"
		end,
	},
}
workspace = {
	CurrentCamera = { CFrame = { Position = Vector3.new(0, 0, 0) } },
	GetPropertyChangedSignal = function() return newSignal() end,
}
game = { GetService = function(_, n) assert(services[n], n); return services[n] end }
