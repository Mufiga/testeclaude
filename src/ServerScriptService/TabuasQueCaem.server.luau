--!strict
--[[
	=====================================================================
	TabuasQueCaem  (Script normal)
	Local: ServerScriptService > TabuasQueCaem
	=====================================================================

	Toda Part com a tag "TabuaQueCai": quando um jogador (a pé ou de quadriciclo) passa em cima,
	ela TREME um pouquinho, CAI (despenca, sem segurar ninguém) e, depois de um tempo, VOLTA
	para o lugar dela, inteira.
	Serve para qualquer Part: as tábuas da ponte (o 29_ConstruirPonte já coloca a tag), plataformas,
	pedras que desabam...

	Atributos opcionais na Part (Properties > Attributes):
	  "Espera" .. (s) quanto tempo ela treme antes de cair (padrão 0.6)
	  "Volta" ... (s) depois de quanto tempo (contando do toque) ela volta (padrão 5)
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local TAG_TABUA = "TabuaQueCai"
local TAG_QUADRICICLO = "Quadriciclo" -- (o Servidor de cada quadriciclo coloca esta tag no Model)
local TEMPO_CAINDO = 1.5 -- (s) quanto tempo ela fica caindo antes de sumir (para não cair para sempre)

local caindo: { [BasePart]: boolean } = {} -- as tábuas que já estão tremendo ou caindo agora
local sorteio = Random.new()

local function numero(valor: unknown, padrao: number): number
	return if typeof(valor) == "number" then valor else padrao
end

-- Quem encostou é um jogador (o corpo dele) ou um quadriciclo? (Outras coisas não derrubam a tábua.)
local function ehJogadorOuQuadriciclo(peca: BasePart): boolean
	local modelo = peca:FindFirstAncestorOfClass("Model")
	while modelo do
		if Players:GetPlayerFromCharacter(modelo) or CollectionService:HasTag(modelo, TAG_QUADRICICLO) then
			return true
		end
		modelo = modelo:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- Treme, cai, some e volta.
local function derrubar(tabua: BasePart)
	if caindo[tabua] then
		return -- (já está caindo)
	end
	caindo[tabua] = true
	local lugar = tabua.CFrame -- guarda como ela era, para voltar igualzinha
	local transparencia = tabua.Transparency
	local colide = tabua.CanCollide
	local espera = math.max(numero(tabua:GetAttribute("Espera"), 0.6), 0)
	local volta = math.max(numero(tabua:GetAttribute("Volta"), 5), espera + TEMPO_CAINDO + 0.5)
	local comeco = os.clock()

	-- 1) TREME: mexe um pouquinho para os lados (quem está em cima sente!).
	while os.clock() - comeco < espera do
		tabua.CFrame = lugar
			* CFrame.new(sorteio:NextNumber(-0.08, 0.08), 0, sorteio:NextNumber(-0.08, 0.08))
			* CFrame.Angles(0, 0, math.rad(sorteio:NextNumber(-2, 2)))
		task.wait(0.05)
	end

	-- 2) CAI: fica solta (a gravidade puxa) e para de segurar quem estava em cima.
	tabua.CFrame = lugar
	tabua.CanCollide = false
	tabua.Anchored = false
	pcall(function()
		tabua:SetNetworkOwner(nil) -- (o servidor calcula a queda: todo mundo vê igual)
	end)
	task.wait(TEMPO_CAINDO)

	-- 3) SOME: volta para o lugar, invisível (assim ela não cai até sumir do mapa).
	tabua.Anchored = true
	tabua.AssemblyLinearVelocity = Vector3.zero
	tabua.AssemblyAngularVelocity = Vector3.zero
	tabua.CFrame = lugar
	tabua.Transparency = 1

	-- 4) VOLTA: depois do tempo, aparece de novo, inteira.
	task.wait(math.max(volta - (os.clock() - comeco), 0))
	tabua.Transparency = transparencia
	tabua.CanCollide = colide
	caindo[tabua] = nil
end

-- Liga o "encostou" de cada tábua (as que já estão no mapa e as que aparecerem depois).
local function prepararTabua(objeto: Instance)
	if not objeto:IsA("BasePart") then
		return
	end
	local tabua: BasePart = objeto
	tabua.CanTouch = true
	tabua.Touched:Connect(function(outra: BasePart)
		if not caindo[tabua] and ehJogadorOuQuadriciclo(outra) then
			task.spawn(derrubar, tabua)
		end
	end)
end

for _, objeto in CollectionService:GetTagged(TAG_TABUA) do
	prepararTabua(objeto)
end
CollectionService:GetInstanceAddedSignal(TAG_TABUA):Connect(prepararTabua)

