--[[
	Stubs mínimos das APIs da Roblox usadas por Noise/Shape/Presets, para rodar
	a geometria num interpretador Luau comum (sem Studio). Só existe para teste:
	nada daqui vai para o jogo.
]]

local v3mt = {}
local v3methods = {}

local function v3(x: number, y: number, z: number)
	return setmetatable({ X = x, Y = y, Z = z }, v3mt)
end

function v3methods:Dot(other)
	return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end

function v3methods:Cross(other)
	return v3(
		self.Y * other.Z - self.Z * other.Y,
		self.Z * other.X - self.X * other.Z,
		self.X * other.Y - self.Y * other.X
	)
end

function v3methods:Min(other)
	return v3(math.min(self.X, other.X), math.min(self.Y, other.Y), math.min(self.Z, other.Z))
end

function v3methods:Max(other)
	return v3(math.max(self.X, other.X), math.max(self.Y, other.Y), math.max(self.Z, other.Z))
end

function v3methods:Lerp(other, alpha)
	return v3(
		self.X + (other.X - self.X) * alpha,
		self.Y + (other.Y - self.Y) * alpha,
		self.Z + (other.Z - self.Z) * alpha
	)
end

v3mt.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			return v3(0, 0, 0)
		end
		return v3(self.X / m, self.Y / m, self.Z / m)
	end
	return v3methods[key]
end

v3mt.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
v3mt.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
v3mt.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
v3mt.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
v3mt.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
v3mt.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z) end

local Vector3 = {
	new = v3,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

local cfmt = {}
cfmt.__mul = function(a, b)
	local m = a.m
	return v3(
		m[1] * b.X + m[2] * b.Y + m[3] * b.Z,
		m[4] * b.X + m[5] * b.Y + m[6] * b.Z,
		m[7] * b.X + m[8] * b.Y + m[9] * b.Z
	)
end

local CFrame = {
	identity = setmetatable({ m = { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, cfmt),
	fromAxisAngle = function(axis, angle)
		local c, s = math.cos(angle), math.sin(angle)
		local t = 1 - c
		local x, y, z = axis.X, axis.Y, axis.Z
		return setmetatable({
			m = {
				t * x * x + c, t * x * y - s * z, t * x * z + s * y,
				t * x * y + s * z, t * y * y + c, t * y * z - s * x,
				t * x * z - s * y, t * y * z + s * x, t * z * z + c,
			},
		}, cfmt)
	end,
}

-- LCG determinístico: não precisa bater com o da Roblox, só ser reprodutível.
local RandomClass = {}
RandomClass.__index = RandomClass

function RandomClass:_next(): number
	self.state = (1103515245 * self.state + 12345) % 2147483648
	return self.state / 2147483648
end

function RandomClass:NextNumber(a: number?, b: number?): number
	local r = self:_next()
	if a == nil or b == nil then
		return r
	end
	return a + (b - a) * r
end

function RandomClass:NextInteger(a: number, b: number): number
	return math.min(b, a + math.floor(self:_next() * (b - a + 1)))
end

local Random = {
	new = function(seed: number?)
		local s = math.floor(math.abs(seed or 0)) % 2147483647
		return setmetatable({ state = (s * 16807 + 7) % 2147483648 }, RandomClass)
	end,
}

-- Perlin 3D, no mesmo formato de math.noise (~[-0.5, 0.5]).
-- `math` e read-only no interpretador, entao criamos uma tabela que a sombreia.
local perlin
do
	local perm = {}
	local base = {}
	for i = 0, 255 do
		base[i] = i
	end
	local shuffler = Random.new(1337)
	for i = 255, 1, -1 do
		local j = shuffler:NextInteger(0, i)
		base[i], base[j] = base[j], base[i]
	end
	for i = 0, 511 do
		perm[i] = base[i % 256]
	end

	local function fade(t: number): number
		return t * t * t * (t * (t * 6 - 15) + 10)
	end

	local function lerp(a: number, b: number, t: number): number
		return a + (b - a) * t
	end

	local function grad(hash: number, x: number, y: number, z: number): number
		local h = hash % 16
		local u = if h < 8 then x else y
		local v
		if h < 4 then
			v = y
		elseif h == 12 or h == 14 then
			v = x
		else
			v = z
		end
		local a = if h % 2 == 0 then u else -u
		local b = if math.floor(h / 2) % 2 == 0 then v else -v
		return a + b
	end

	perlin = function(x: number, y: number?, z: number?): number
		y = y or 0
		z = z or 0
		local xi, yi, zi = math.floor(x) % 256, math.floor(y) % 256, math.floor(z) % 256
		local xf, yf, zf = x - math.floor(x), y - math.floor(y), z - math.floor(z)
		local u, v, w = fade(xf), fade(yf), fade(zf)

		local A = perm[xi] + yi
		local AA = perm[A % 512] + zi
		local AB = perm[(A + 1) % 512] + zi
		local B = perm[(xi + 1) % 256] + yi
		local BA = perm[B % 512] + zi
		local BB = perm[(B + 1) % 512] + zi

		local result = lerp(
			lerp(
				lerp(grad(perm[AA % 512], xf, yf, zf), grad(perm[BA % 512], xf - 1, yf, zf), u),
				lerp(grad(perm[AB % 512], xf, yf - 1, zf), grad(perm[BB % 512], xf - 1, yf - 1, zf), u),
				v
			),
			lerp(
				lerp(grad(perm[(AA + 1) % 512], xf, yf, zf - 1), grad(perm[(BA + 1) % 512], xf - 1, yf, zf - 1), u),
				lerp(
					grad(perm[(AB + 1) % 512], xf, yf - 1, zf - 1),
					grad(perm[(BB + 1) % 512], xf - 1, yf - 1, zf - 1),
					u
				),
				v
			),
			w
		)
		return result * 0.5
	end
end

local Enum = {
	CollisionFidelity = {
		Box = { Name = "Box" },
		Hull = { Name = "Hull" },
		Default = { Name = "Default" },
		PreciseConvexDecomposition = { Name = "PreciseConvexDecomposition" },
	},
}

local realMath = math
local math = setmetatable({ noise = perlin }, { __index = realMath })

-- Silencia o aviso de "variavel nao usada" nos stubs que so existem como upvalue.
local _unused = { Vector3, CFrame, Random, Enum, math }
