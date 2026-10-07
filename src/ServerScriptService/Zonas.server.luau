--!strict
--[[
	=====================================================================
	Zonas  (Script normal)
	Local: ServerScriptService > Zonas
	=====================================================================

	Junta os antigos "ZonasSemGancho" e "ZonasSemImpulso" (pode apagar os dois).

	Os dois tipos de ZONA do mapa:
	  "ZonaSemGancho"  = NENHUM dos 3 ganchos funciona (Impulso, Segurar e Botão)
	  "ZonaSemImpulso" = só o gancho de IMPULSO não funciona. Use onde o impulso deixaria o
	                     jogador "cortar caminho" e roubar no mapa.
	Como criar uma: coloque uma Part cobrindo a área (pode ser grande e alta) e, na janela
	Properties, lá embaixo em "Tags", adicione a tag. Também vale colocar a tag num Model ou
	Folder: aí cada Part de dentro vira zona.

	Este script deixa as zonas "fantasmas" quando o jogo começa: ancoradas, sem colisão e sem
	atrapalhar os raios (a mira do gancho atravessa). E INVISÍVEIS, a não ser que você crie nela
	o atributo "Visivel" (boolean) marcado. No Studio (sem dar Play) elas continuam do jeito que
	você montou, para você enxergar.
	Atributo "Ativa" = false desliga a zona sem apagar (quem confere é o módulo Gancho do cliente).
]]

local CollectionService = game:GetService("CollectionService")

local TAGS_DAS_ZONAS = { "ZonaSemGancho", "ZonaSemImpulso" } -- (as mesmas tags que o módulo Gancho procura)

-- Deixa UMA peça fantasma: não bate, não encosta e os raios passam direto (a mira do gancho também).
local function prepararPeca(peca: BasePart, visivel: boolean)
	peca.Anchored = true -- não cai
	peca.CanCollide = false
	peca.CanTouch = false
	peca.CanQuery = false -- (só dá para desligar depois do CanCollide)
	if not visivel then
		peca.Transparency = 1
		peca.CastShadow = false
	end
end

-- Uma zona pode ser uma Part ou um Model/Folder cheio de Parts.
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

for _, tag in TAGS_DAS_ZONAS do
	-- As zonas que já estão no mapa...
	for _, zona in CollectionService:GetTagged(tag) do
		prepararZona(zona)
	end
	-- ...e as que ganharem a tag depois (por exemplo, criadas por outro script durante o jogo).
	CollectionService:GetInstanceAddedSignal(tag):Connect(prepararZona)
end
