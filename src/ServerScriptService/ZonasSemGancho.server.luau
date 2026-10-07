--!strict
--[[
	=====================================================================
	ZonasSemGancho  (Script normal)
	Local: ServerScriptService > ZonasSemGancho
	=====================================================================

	Prepara as ZONAS SEM GANCHO do mapa: qualquer Part com a tag "ZonaSemGancho"
	(ou um Model/Folder com a tag: vale cada Part dentro dele). Cada uma:
	  - fica ancorada e sem colisão: o quadriciclo e os jogadores passam por dentro;
	  - não atrapalha os raios (a mira do gancho e outros scripts atravessam);
	  - fica INVISÍVEL no jogo. Quer que os jogadores vejam a área? Crie nela o
	    atributo "Visivel" (boolean) marcado.
	No Studio a zona continua do jeito que você montou, para você enxergar.
	Quem faz a regra do gancho valer é o módulo Gancho (no QuadricicloCliente).
]]

local CollectionService = game:GetService("CollectionService")

local TAG_ZONA_SEM_GANCHO = "ZonaSemGancho"

local function prepararPeca(peca: BasePart, visivel: boolean)
	peca.Anchored = true
	peca.CanCollide = false
	peca.CanTouch = false
	peca.CanQuery = false
	if not visivel then
		peca.Transparency = 1
	end
end

local function prepararZona(zona: Instance)
	local visivel = zona:GetAttribute("Visivel") == true
	if zona:IsA("BasePart") then
		prepararPeca(zona, visivel)
	end
	for _, peca in zona:GetDescendants() do
		if peca:IsA("BasePart") then
			prepararPeca(peca, visivel)
		end
	end
end

CollectionService:GetInstanceAddedSignal(TAG_ZONA_SEM_GANCHO):Connect(prepararZona) -- (zonas criadas depois)
for _, zona in CollectionService:GetTagged(TAG_ZONA_SEM_GANCHO) do
	prepararZona(zona)
end

