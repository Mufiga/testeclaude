--!strict
--[[
	=====================================================================
	ZonasSemImpulso  (Script normal)
	Local: ServerScriptService > ZonasSemImpulso
	=====================================================================

	ZONA SEM IMPULSO = um lugar onde SÓ o gancho de IMPULSO não funciona (o SEGURAR e o BOTÃO
	funcionam normalmente). Use onde o impulso deixaria o jogador "cortar caminho" e roubar no mapa.

	Como criar uma: coloque uma Part cobrindo a área (pode ser grande e alta), e na janela Properties,
	lá embaixo em "Tags", adicione a tag ZonaSemImpulso. Também vale colocar a tag num Model ou
	Folder: aí cada Part de dentro vira zona. Atributo "Ativa" = false desliga a zona sem apagar.

	Este script só deixa as zonas "fantasmas" quando o jogo começa: invisíveis, sem colisão e sem
	atrapalhar a mira. Quem confere a zona é o módulo Gancho, no computador de cada jogador.
	No Studio (sem dar Play) elas continuam visíveis, para você montar o mapa.
]]

local CollectionService = game:GetService("CollectionService")

local TAG_ZONA = "ZonaSemImpulso" -- a mesma tag que o módulo Gancho procura

-- Deixa UMA peça fantasma: some, não bate, não encosta e os raios passam direto (a mira do gancho também).
local function esconderPeca(peca: BasePart)
	peca.Anchored = true -- não cai
	peca.Transparency = 1
	peca.CanCollide = false
	peca.CanTouch = false
	peca.CanQuery = false -- (só dá para desligar depois do CanCollide)
	peca.CastShadow = false
end

-- Uma zona pode ser uma Part ou um Model/Folder cheio de Parts.
local function prepararZona(zona: Instance)
	if zona:IsA("BasePart") then
		esconderPeca(zona)
	end
	for _, peca in zona:GetDescendants() do
		if peca:IsA("BasePart") then
			esconderPeca(peca)
		end
	end
end

-- As zonas que já estão no mapa...
for _, zona in CollectionService:GetTagged(TAG_ZONA) do
	prepararZona(zona)
end
-- ...e as que ganharem a tag depois (por exemplo, criadas por outro script durante o jogo).
CollectionService:GetInstanceAddedSignal(TAG_ZONA):Connect(prepararZona)
