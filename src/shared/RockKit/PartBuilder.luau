--[[
	PartBuilder — reserva para quando EditableMesh não está disponível.

	Monta a pedra empilhando blocos girados em ângulos quebrados (mais cunhas no
	topo nos presets pontudos). Não fica tão limpo quanto a malha facetada, mas
	usa só Part/WedgePart: roda em qualquer versão do engine e em qualquer lugar.
]]

local PartBuilder = {}

export type Look = {
	material: Enum.Material,
	color: Color3,
	castShadow: boolean,
	canCollide: boolean,
	canTouch: boolean,
}

export type BuildParams = {
	seed: number,
	size: Vector3,
	taperTop: number,
	taperCurve: number,
	tilt: number,
	shards: { number },
}

local function newPart(className: string, size: Vector3, cframe: CFrame, look: Look, parent: Instance): BasePart
	local part = Instance.new(className) :: BasePart
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Material = look.material
	part.Color = look.color
	part.CastShadow = look.castShadow
	part.CanCollide = look.canCollide
	part.CanTouch = look.canTouch
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function PartBuilder.build(params: BuildParams, look: Look): Model
	local rng = Random.new(params.seed + 7919)
	local model = Instance.new("Model")
	local size = params.size

	local count = rng:NextInteger(params.shards[1], params.shards[2])
	local layer = size.Y / count

	for index = 1, count do
		local t = if count > 1 then (index - 1) / (count - 1) else 0
		local shrink = 1 + (params.taperTop - 1) * t ^ params.taperCurve
		local width = size.X * shrink * rng:NextNumber(0.55, 1.0)
		local depth = size.Z * shrink * rng:NextNumber(0.55, 1.0)
		local height = layer * rng:NextNumber(0.9, 1.6)
		local jitter = size.X * shrink * 0.18

		local cframe = CFrame.new(
			rng:NextNumber(-jitter, jitter),
			-size.Y * 0.5 + layer * (index - 0.5),
			rng:NextNumber(-jitter, jitter)
		) * CFrame.Angles(
			math.rad(rng:NextNumber(-9, 9)),
			rng:NextNumber(0, math.pi * 2),
			math.rad(rng:NextNumber(-9, 9))
		)

		newPart("Part", Vector3.new(width, height, depth), cframe, look, model)
	end

	-- Presets afilados (agulha, lasca) ganham cunhas no topo para fechar a ponta.
	if params.taperTop < 0.6 then
		for _ = 1, rng:NextInteger(1, 2) do
			local width = math.max(size.X * params.taperTop * rng:NextNumber(0.8, 1.6), 0.1)
			local depth = math.max(size.Z * params.taperTop * rng:NextNumber(0.8, 1.6), 0.1)
			local height = size.Y * rng:NextNumber(0.12, 0.26)

			local cframe = CFrame.new(
				rng:NextNumber(-width, width) * 0.4,
				size.Y * 0.5 - height * 0.35,
				rng:NextNumber(-depth, depth) * 0.4
			) * CFrame.Angles(
				math.rad(rng:NextNumber(-12, 12)),
				rng:NextNumber(0, math.pi * 2),
				math.rad(rng:NextNumber(-12, 12))
			)

			newPart("WedgePart", Vector3.new(width, height, depth), cframe, look, model)
		end
	end

	if params.tilt > 1e-4 then
		local axis = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		if axis.Magnitude > 1e-3 then
			local rotation = CFrame.fromAxisAngle(axis.Unit, params.tilt)
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") then
					child.CFrame = rotation * child.CFrame
				end
			end
		end
	end

	-- Recentra a bounding box na origem para o modelo se comportar como o
	-- MeshPart equivalente (pivô no centro, não na primeira peça criada).
	local boxCFrame, boxSize = model:GetBoundingBox()
	local offset = boxCFrame.Position
	if offset.Magnitude > 1e-5 then
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				child.CFrame = child.CFrame - offset
			end
		end
	end

	-- Sem PrimaryPart de propósito: assim `PivotTo` usa o WorldPivot que
	-- acabamos de centralizar, em vez do centro de uma peça qualquer.
	model.WorldPivot = CFrame.identity
	model:SetAttribute("RockKitSize", boxSize)

	return model
end

return PartBuilder
