--[[
	MeshBuilder — transforma a geometria num MeshPart de verdade, via EditableMesh.

	Cada triângulo recebe três vértices próprios e uma única normal compartilhada
	entre eles: é isso que produz a aresta dura do visual low poly facetado
	(vértices compartilhados dariam sombreamento suave, e a pedra viraria uma
	batata lisa).

	A API de EditableMesh não existe em todas as versões do engine, então todo o
	caminho é protegido: se falhar, o RockKit cai no PartBuilder sozinho.
]]

local AssetService = game:GetService("AssetService")

local Shape = require(script.Parent.Shape)

local MeshBuilder = {}

local supported: boolean? = nil

export type MeshOptions = {
	collisionFidelity: Enum.CollisionFidelity?,
	-- quantos studs cobre um "ladrilho" da textura do material
	textureScale: number?,
}

-- Projeção planar pelo eixo dominante da normal (triplanar simplificado):
-- mantém a textura do material no mesmo tamanho real em todas as faces.
local function planarUV(point: Vector3, normal: Vector3): Vector2
	local ax, ay, az = math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z)
	if ay >= ax and ay >= az then
		return Vector2.new(point.X, point.Z)
	elseif ax >= az then
		return Vector2.new(point.Z, point.Y)
	end
	return Vector2.new(point.X, point.Y)
end

function MeshBuilder.isSupported(): boolean
	if supported == nil then
		supported = (pcall(function()
			local probe = AssetService:CreateEditableMesh()
			local _ = (Content :: any).fromObject(probe)
			pcall(function()
				probe:Destroy()
			end)
		end))
	end
	return supported :: boolean
end

function MeshBuilder.build(geometry: Shape.Geometry, options: MeshOptions): MeshPart?
	local fidelity = options.collisionFidelity or Enum.CollisionFidelity.Box
	local uvScale = 1 / math.max(options.textureScale or 8, 0.01)

	local ok, result = pcall(function()
		local mesh = AssetService:CreateEditableMesh()

		for _, triangle in geometry.triangles do
			local normal = triangle.normal
			local normalId = mesh:AddNormal(normal)

			local a = mesh:AddVertex(triangle.a)
			local b = mesh:AddVertex(triangle.b)
			local c = mesh:AddVertex(triangle.c)
			local face = mesh:AddTriangle(a, b, c)

			mesh:SetFaceNormals(face, { normalId, normalId, normalId })
			mesh:SetFaceUVs(face, {
				mesh:AddUV(planarUV(triangle.a, normal) * uvScale),
				mesh:AddUV(planarUV(triangle.b, normal) * uvScale),
				mesh:AddUV(planarUV(triangle.c, normal) * uvScale),
			})
		end

		local content = (Content :: any).fromObject(mesh)

		-- A tabela de opções é recente; se o engine não aceitar, tenta sem ela.
		local built: MeshPart
		local withOptions, part = pcall(function()
			return AssetService:CreateMeshPartAsync(content, { CollisionFidelity = fidelity })
		end)
		if withOptions then
			built = part
		else
			built = AssetService:CreateMeshPartAsync(content)
			built.CollisionFidelity = fidelity
		end

		pcall(function()
			mesh:Destroy()
		end)
		return built
	end)

	if not ok then
		supported = false
		return nil
	end
	return result
end

return MeshBuilder
