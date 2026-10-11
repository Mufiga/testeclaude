--=====================================================================
-- Ambiente falso do Roblox, só o suficiente pra rodar o script servidor
--=====================================================================
local NOW = 1000000
local threads = {}   -- { co = coroutine, wake = number }

task = {}
function task.wait(t)
	local co = coroutine.running()
	table.insert(threads, { co = co, wake = NOW + (t or 0) })
	coroutine.yield()
	return t or 0
end
function task.spawn(fn, ...)
	local co = coroutine.create(fn)
	local ok, err = coroutine.resume(co, ...)
	if not ok then error("task.spawn: " .. tostring(err), 0) end
	return co
end
function warn(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	print("[warn] " .. table.concat(parts, " "))
end

-- avança o relógio virtual e acorda quem terminou de esperar
function advance(seconds)
	local target = NOW + seconds
	while true do
		local nextIdx, nextWake = nil, math.huge
		for i, t in threads do
			if t.wake <= target and t.wake < nextWake then nextIdx, nextWake = i, t.wake end
		end
		if not nextIdx then break end
		local t = table.remove(threads, nextIdx)
		NOW = math.max(NOW, t.wake)
		local ok, err = coroutine.resume(t.co)
		if not ok then error("thread: " .. tostring(err), 0) end
	end
	NOW = target
end
function clockNow() return NOW end

local __realos = os
os = setmetatable({ time = function() return NOW end, clock = function() return NOW end }, { __index = __realos })

--------------------------------------------------------------- tipos basicos
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3) end
Vector3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3.__mul = function(a, b)
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

CFrame = {}
CFrame.__index = CFrame
local function mkcf(x, y, z)
	return setmetatable({
		Position = Vector3.new(x, y, z),
		LookVector = Vector3.new(0, 0, -1),
		X = x, Y = y, Z = z,
	}, CFrame)
end
function CFrame.new(x, y, z)
	if type(x) == "table" then return mkcf(x.X, x.Y, x.Z) end
	return mkcf(x or 0, y or 0, z or 0)
end
function CFrame.Angles() return mkcf(0, 0, 0) end
function CFrame.lookAt(pos) return mkcf(pos.X, pos.Y, pos.Z) end
CFrame.__mul = function(a, b) return mkcf(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end

Enum = setmetatable({}, { __index = function(_, group)
	return setmetatable({}, { __index = function(_, item) return group .. "." .. item end })
end })

--------------------------------------------------------------------- Instance
function newSignal()
	local s = { handlers = {} }
	function s:Connect(fn) table.insert(self.handlers, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, fn in self.handlers do fn(...) end end
	return s
end


local function newInstance(className)
	local inst
	inst = {
		ClassName = className,
		Name = className,
		Children = {},
		Value = "",
		IsA = function(self, c) return self.ClassName == c end,
		FindFirstChild = function(self, n)
			for _, c in self.Children do if c.Name == n then return c end end
			return nil
		end,
		Destroy = function() end,
	}
	return setmetatable(inst, { __newindex = function(t, k, v)
		if k == "Parent" and v ~= nil and type(v) == "table" and v.Children then
			table.insert(v.Children, t)
		end
		rawset(t, k, v)
	end })
end
Instance = { new = newInstance }
