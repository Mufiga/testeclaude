--[[
	Exemplo do RockKit.

	Com ATIVADO = true, ao rodar o jogo isto monta um mostruário com um exemplar
	de cada preset na frente do spawn. Serve para você ver os formatos e os
	tamanhos reais antes de decidir o que usar.

	Quando terminar de olhar, deixe ATIVADO = false (ou apague este arquivo).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RockKit = require(ReplicatedStorage:WaitForChild("RockKit"))

local ATIVADO = true
local BIOMA = "Canyon"
local ORIGEM = Vector3.new(0, 0, -60)

if not ATIVADO then
	return
end

local pasta = Instance.new("Folder")
pasta.Name = "MostruarioRochas"
pasta.Parent = workspace

local rng = Random.new(2025)
local cursor = 0

for _, preset in RockKit.Presets.allNames() do
	local rocha = RockKit.create({
		preset = preset,
		seed = rng:NextInteger(1, 2 ^ 31 - 2),
		biome = BIOMA,
		parent = pasta,
	})

	local tamanho = rocha:GetAttribute("RockKitSize") :: Vector3
	local enterrado = rocha:GetAttribute("RockKitBury") :: number

	-- avança o cursor meio tamanho desta pedra + folga, para nada se sobrepor
	cursor += tamanho.X * 0.5 + 4
	rocha:PivotTo(CFrame.new(ORIGEM + Vector3.new(cursor, tamanho.Y * (0.5 - enterrado), 0)))
	cursor += tamanho.X * 0.5

	local etiqueta = Instance.new("Part")
	etiqueta.Name = "Etiqueta_" .. preset
	etiqueta.Size = Vector3.new(4, 0.2, 4)
	etiqueta.Anchored = true
	etiqueta.CanCollide = false
	etiqueta.Transparency = 1
	etiqueta.CFrame = CFrame.new(ORIGEM + Vector3.new(cursor - tamanho.X * 0.5, 0, 0))
	etiqueta.Parent = pasta

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(10, 2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, -2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = etiqueta

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.fromScale(1, 1)
	texto.BackgroundTransparency = 1
	texto.TextColor3 = Color3.new(1, 1, 1)
	texto.TextStrokeTransparency = 0.4
	texto.TextScaled = true
	texto.Font = Enum.Font.GothamBold
	texto.Text = ("%s  (%.1f studs)"):format(preset, tamanho.Y)
	texto.Parent = gui
end

print(("[RockKit] mostruário pronto — %s"):format(
	if RockKit.usesMeshes() then "usando MeshParts facetados" else "usando blocos (EditableMesh indisponível)"
))

--[[
	Campo de pedras no terreno. Descomente depois de ter terreno modelado:
	o raycast precisa de chão embaixo da área, senão não coloca nada.

	RockKit.scatter({
		center = Vector3.new(0, 0, 0),
		areaSize = Vector3.new(400, 600, 400),
		count = 150,
		biome = BIOMA,
		presets = { "Pebble", "Stone", "Boulder", "Shard" },
		maxSlope = 38,
		terrainOnly = true,
		parent = pasta,
	})
]]
