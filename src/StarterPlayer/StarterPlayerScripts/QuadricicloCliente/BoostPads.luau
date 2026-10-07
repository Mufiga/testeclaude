--!strict
--[[
	=====================================================================
	BoostPads  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > BoostPads
	=====================================================================

	PADS DE BOOST: passou com o quadriciclo por cima de uma Part com a tag "BoostPad", ele ganha um
	EMPURRÃO forte para a frente do pad (a face Front) e, por alguns segundos, pode passar da
	velocidade máxima (o extra vai diminuindo até acabar). A tela treme, a câmera "abre" com a
	velocidade e sai um rastro de brilho do quadriciclo.
	Quem aplica é o computador de quem dirige (a física do quadriciclo é dele): zero lag.

	Atributos opcionais no pad (Properties > Attributes):
	  "Forca" ......... (studs/s) o tamanho do empurrão (padrão 50)
	  "Duracao" ....... (s) quanto tempo ele pode passar da máxima (padrão 1.5)
	  "Subida" ........ (studs/s) um pulinho para cima junto (padrão 0; bom para rampas)
	  "FrenteDoCarro" . (true/false) empurra para a frente do QUADRICICLO, não do pad
	SETAS: Parts chamadas "Seta1", "Seta2"... (de trás para a frente) no MESMO Model do pad piscam
	em sequência, "andando" para a frente. O 23_ConstruirBoostPad já monta tudo assim.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
local Camera = require(script.Parent:WaitForChild("Camera"))
type Quadriciclo = Veiculo.Quadriciclo

local BoostPads = {}

-- =====================================================================
-- AJUSTES
-- =====================================================================
local TAG_BOOST = "BoostPad"
local ESPERA_DO_PAD = 1 -- (s) o mesmo pad só empurra de novo depois disso
local SOM_DO_BOOST = "" -- (opcional) "rbxassetid://..." de um som de "vuuush"
local DISTANCIA_DAS_SETAS = 300 -- (studs) só as setas dos pads perto da câmera piscam (as longe ficam paradas: economiza)

local pads: { BasePart } = {} -- todos os pads do mapa (a lista se atualiza sozinha)
local setasDoPad: { [BasePart]: { { BasePart } } } = {} -- as setas de cada pad (cada seta pode ter várias Parts)
local ultimoUso: { [BasePart]: number } = {} -- quando (os.clock) cada pad empurrou pela última vez
local boostAte = 0 -- (os.clock) até quando dura o boost de agora
local boostDuracao = 1
local boostForca = 0

local function numero(valor: unknown, padrao: number): number
	return if typeof(valor) == "number" then valor else padrao
end

-- =====================================================================
-- A LISTA DE PADS E AS SETAS
-- =====================================================================
-- Acha "Seta1", "Seta2"... no Model do pad.
local function acharSetas(pad: BasePart): { { BasePart } }
	local grupos: { { BasePart } } = {}
	local pai = pad.Parent
	if pai == nil or pai == workspace then
		return grupos -- pad solto no Workspace: sem setas
	end
	for _, filho in pai:GetDescendants() do
		local qual = string.match(filho.Name, "^Seta(%d+)$")
		if qual and filho:IsA("BasePart") then
			local i = tonumber(qual) :: number
			local grupo = grupos[i] or {}
			grupos[i] = grupo
			table.insert(grupo, filho)
		end
	end
	return grupos
end

local function adicionar(objeto: Instance)
	if objeto:IsA("BasePart") and not table.find(pads, objeto) then
		table.insert(pads, objeto)
		setasDoPad[objeto] = acharSetas(objeto)
	end
end

local function remover(objeto: Instance)
	if objeto:IsA("BasePart") then
		local indice = table.find(pads, objeto)
		if indice then
			table.remove(pads, indice)
		end
		setasDoPad[objeto] = nil
		ultimoUso[objeto] = nil
	end
end

-- A cada frame: as setas acendem uma depois da outra, como uma onda indo para a frente.
-- (OTIMIZADO) Só os pads perto da câmera: num mapa grande, com muitos pads, os que você nem está
-- vendo não ficam mudando a cada frame.
local function animarSetas()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local daCamera = camera.CFrame.Position
	local tempo = os.clock() * 4
	for pad, grupos in setasDoPad do
		if (pad.Position - daCamera).Magnitude > DISTANCIA_DAS_SETAS then
			continue
		end
		for i, grupo in grupos do
			local brilho = (math.sin(tempo - i * 1.3) + 1) / 2 -- 0 = apagada · 1 = acesa
			for _, parte in grupo do
				parte.Transparency = 0.65 - 0.6 * brilho
			end
		end
	end
end

-- =====================================================================
-- O EMPURRÃO
-- =====================================================================
-- O ponto está em cima do pad? (dentro da caixa dele, até 6 studs acima)
local function emCimaDoPad(pad: BasePart, ponto: Vector3): boolean
	local relativo = pad.CFrame:PointToObjectSpace(ponto)
	local meio = pad.Size / 2
	return math.abs(relativo.X) <= meio.X + 1
		and math.abs(relativo.Z) <= meio.Z + 1
		and relativo.Y >= -meio.Y - 1
		and relativo.Y <= meio.Y + 6
end

local function disparar(quad: Quadriciclo, pad: BasePart)
	local forca = numero(pad:GetAttribute("Forca"), 50)
	local duracao = math.max(numero(pad:GetAttribute("Duracao"), 1.5), 0.1)
	local subida = numero(pad:GetAttribute("Subida"), 0)
	local direcao = if pad:GetAttribute("FrenteDoCarro") == true then Veiculo.referencia(quad).LookVector else pad.CFrame.LookVector
	local empurrao = direcao * forca + Vector3.yAxis * subida
	for _, parte in quad.pecasFisicas do
		parte.AssemblyLinearVelocity += empurrao -- todas as peças juntas: o quadriciclo vai inteiro
	end
	boostForca, boostDuracao, boostAte = forca, duracao, os.clock() + duracao
	Camera.tremer(0.2) -- tranco na tela

	-- RASTRO: um estouro de brilhos ciano e roxo saindo para trás (só você vê).
	local anexo = Instance.new("Attachment")
	anexo.Parent = quad.chassi
	anexo.WorldCFrame = CFrame.lookAt(quad.chassi.Position, quad.chassi.Position - direcao) -- a "frente" dele aponta para trás
	local rastro = Instance.new("ParticleEmitter")
	rastro.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rastro.Color = ColorSequence.new(Color3.fromRGB(120, 240, 255), Color3.fromRGB(170, 90, 255))
	rastro.LightEmission = 1
	rastro.Size = NumberSequence.new(0.9, 0)
	rastro.Lifetime = NumberRange.new(0.3, 0.55)
	rastro.Speed = NumberRange.new(12, 22)
	rastro.SpreadAngle = Vector2.new(25, 25)
	rastro.EmissionDirection = Enum.NormalId.Front
	rastro.Enabled = false
	rastro.Parent = anexo
	rastro:Emit(35)
	task.delay(1, function()
		anexo:Destroy()
	end)

	if SOM_DO_BOOST ~= "" then
		local som = Instance.new("Sound")
		som.SoundId = SOM_DO_BOOST
		som.Volume = 0.8
		som.Parent = quad.chassi
		som:Play()
		som.Ended:Once(function()
			som:Destroy()
		end)
	end
end

-- =====================================================================
-- PARA O QuadricicloCliente
-- =====================================================================
-- Chamado a cada frame pelo "atualizar". Devolve quantos studs/s ACIMA da máxima o quadriciclo
-- pode andar agora (0 = sem boost).
function BoostPads.atualizar(quad: Quadriciclo): number
	local agora = os.clock()
	local posicao = quad.chassi.Position
	for _, pad in pads do
		if agora - (ultimoUso[pad] or 0) > ESPERA_DO_PAD and emCimaDoPad(pad, posicao) then
			ultimoUso[pad] = agora
			disparar(quad, pad)
		end
	end
	if agora < boostAte then
		return boostForca * (boostAte - agora) / boostDuracao -- vai diminuindo até 0
	end
	return 0
end

-- Chamado UMA vez, quando o jogo começa: acha os pads e liga a animação das setas.
function BoostPads.iniciar()
	for _, objeto in CollectionService:GetTagged(TAG_BOOST) do
		adicionar(objeto)
	end
	CollectionService:GetInstanceAddedSignal(TAG_BOOST):Connect(adicionar)
	CollectionService:GetInstanceRemovedSignal(TAG_BOOST):Connect(remover)
	RunService.RenderStepped:Connect(animarSetas)
end

return BoostPads
