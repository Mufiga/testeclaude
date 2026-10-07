--!strict
--[[
	=====================================================================
	Vitrine  (ModuleScript)
	Local: ReplicatedStorage > Compartilhado > Vitrine
	=====================================================================

	O que a GARAGEM (GaragemCliente) e o HUD DE VEÍCULOS (SeletorDeVeiculo) fazem igual:
	  - a lista dos veículos (os moldes da pasta ReplicatedStorage > Quadriciclos) na ordem certa;
	  - o nome e a descrição de cada um (atributos "NomeExibido" e "Descricao" do molde);
	  - o veículo 3D dentro de um ViewportFrame (a "vitrine" dos cartões).
	Assim, os dois mostram sempre a mesma coisa, e uma correção aqui vale para os dois.
]]

local Vitrine = {}

local function numero(valor: unknown, padrao: number): number
	return if typeof(valor) == "number" then valor else padrao
end

-- Um texto do molde (atributo), com um "plano B". O caminhão monstro é uma CÓPIA do quadriciclo:
-- se ele ainda estiver com o texto do quadriciclo (ou sem texto), usa o texto próprio dele.
local function textoDoMolde(molde: Instance, atributo: string, doMonstro: string, padrao: string): string
	local valor = molde:GetAttribute(atributo)
	local temTexto = typeof(valor) == "string" and valor ~= ""
	if molde:GetAttribute("Monstro") == true then
		if not temTexto then
			return doMonstro
		end
		local pasta = molde.Parent
		if pasta then
			for _, outro in pasta:GetChildren() do
				if outro ~= molde and outro:GetAttribute("Monstro") ~= true and outro:GetAttribute(atributo) == valor then
					return doMonstro -- (herdou o texto do quadriciclo quando foi copiado)
				end
			end
		end
	end
	return if temTexto then tostring(valor) else padrao
end

-- O nome que aparece no cartão: o atributo "NomeExibido" do molde (ou o nome do Model).
function Vitrine.nomeBonito(molde: Instance): string
	return textoDoMolde(molde, "NomeExibido", "Caminhão Monstro", molde.Name)
end

-- A descrição do cartão: o atributo "Descricao" do molde.
function Vitrine.descricao(molde: Instance): string
	return textoDoMolde(molde, "Descricao", "Grandão: super pulo (J) e mortais", "")
end

-- Os moldes (Models) da pasta, em ordem: pelo atributo "Ordem"; empatou, o que NÃO é monstro vem
-- antes; depois, pelo nome.
function Vitrine.ordenar(moldes: Instance): { Model }
	local ordenados: { Model } = {}
	for _, molde in moldes:GetChildren() do
		if molde:IsA("Model") then
			table.insert(ordenados, molde)
		end
	end
	table.sort(ordenados, function(a: Model, b: Model): boolean
		local ordemA, ordemB = numero(a:GetAttribute("Ordem"), 999), numero(b:GetAttribute("Ordem"), 999)
		if ordemA ~= ordemB then
			return ordemA < ordemB
		end
		local monstroA, monstroB = a:GetAttribute("Monstro") == true, b:GetAttribute("Monstro") == true
		if monstroA ~= monstroB then
			return monstroB -- (o que NÃO é monstro vem primeiro)
		end
		return a.Name < b.Name
	end)
	return ordenados
end

-- Fica na cópia da vitrine só o que aparece numa ViewportFrame: as peças e o "visual" delas
-- (malhas, texturas). Scripts, sons, luzes, partículas, constraints, Attachments e telas (SurfaceGui)
-- não aparecem lá dentro: na cópia, eles só gastariam memória.
local function apareceNaVitrine(objeto: Instance): boolean
	return objeto:IsA("BasePart")
		or objeto:IsA("Model")
		or objeto:IsA("Folder")
		or objeto:IsA("DataModelMesh") -- (SpecialMesh e afins)
		or objeto:IsA("Decal") -- (Decal e Texture)
		or objeto:IsA("SurfaceAppearance")
end

-- Coloca uma CÓPIA do veículo dentro do ViewportFrame, com uma câmera olhando para ele.
-- "afastar" = quão longe a câmera fica (1 = colada; 1.15 = um pouco mais longe).
-- Devolve a câmera e o lugar inicial dela (para girar em volta do veículo).
function Vitrine.montar(viewport: ViewportFrame, molde: Model, afastar: number): (Camera, CFrame)
	local copia = molde:Clone() :: Model -- (o "::" só confirma para o Studio que a cópia é um Model)
	for _, coisa in copia:GetDescendants() do
		if not apareceNaVitrine(coisa) then
			coisa:Destroy() -- a vitrine é só para ver
		end
	end
	local caixa, tamanho = copia:GetBoundingBox() -- a "caixa" que cabe o veículo inteiro
	copia:PivotTo(copia:GetPivot() - caixa.Position) -- o meio dele fica no ponto (0, 0, 0)
	copia.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distancia = tamanho.Magnitude * afastar -- veículo maior = câmera mais longe (todos ficam do mesmo tamanho)
	local inicio = CFrame.lookAt(Vector3.new(distancia * 0.72, distancia * 0.38, distancia * 0.72), Vector3.zero)
	camera.CFrame = inicio
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return camera, inicio
end

return Vitrine
