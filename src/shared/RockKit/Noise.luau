--[[
	Noise — ruído determinístico usado para deformar as rochas.

	`math.noise` (Perlin) da Roblox devolve algo em torno de [-0.5, 0.5] e vale
	exatamente 0 nos pontos inteiros da grade. Por isso toda amostra é deslocada
	por um offset fracionário derivado do seed: sem isso, rochas geradas em
	posições "redondas" sairiam lisas demais.
]]

local Noise = {}

-- Soma de oitavas (fractal brownian motion). Devolve ~[-0.5, 0.5].
function Noise.fbm(point: Vector3, octaves: number, lacunarity: number, gain: number): number
	local amplitude = 1
	local frequency = 1
	local total = 0
	local normalization = 0

	for _ = 1, octaves do
		total += amplitude * math.noise(point.X * frequency, point.Y * frequency, point.Z * frequency)
		normalization += amplitude
		amplitude *= gain
		frequency *= lacunarity
	end

	if normalization <= 0 then
		return 0
	end
	return total / normalization
end

-- Offset fracionário estável para um seed.
function Noise.offsetFromSeed(seed: number): Vector3
	local rng = Random.new(seed)
	return Vector3.new(rng:NextNumber(-512, 512), rng:NextNumber(-512, 512), rng:NextNumber(-512, 512))
end

return Noise
