--!strict
--[[
	=====================================================================
	Spawner  (Script normal)
	Local: ServerScriptService > Spawner
	=====================================================================

	GARAGEM DE QUADRICICLOS: o jogador chega perto de um spawner, aperta E, escolhe o
	quadriciclo na tela (com o modelo 3D girando) e ele aparece em cima do "PontoDeSpawn".
	  - Cada jogador tem UM quadriciclo: pedir outro apaga o anterior. Saiu do jogo, ele some.
	  - Assim que aparece, o jogador já senta nele (SENTAR_SOZINHO).
	A tela é o LocalScript "GaragemCliente".

	COMO MONTAR:
	  1) Em ReplicatedStorage, crie uma pasta "Quadriciclos" e coloque dentro os MOLDES dos
	     quadriciclos. Ex.: MOVA o seu "Quadriciclo" do Workspace para lá (com os Scripts dentro).
	     Atributos opcionais no Model do molde: "NomeExibido" e "Descricao" (texto) e "Ordem"
	     (número: a posição do cartão na tela).
	  2) Um SPAWNER é um Model com a tag "SpawnerQuadriciclo", com estas Parts dentro:
	       "PontoDeSpawn" .. o quadriciclo aparece em cima dela, virado para a FRENTE dela (face Front)
	       "Painel" ....... (opcional) onde aparece o "E  Garagem". Sem ela, aparece no PontoDeSpawn.
	     O 20_ConstruirSpawner monta um spawner bonito, já com tudo isso.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- =====================================================================
-- AJUSTES
-- =====================================================================
local TAG_SPAWNER = "SpawnerQuadriciclo"
local DISTANCIA_MAXIMA = 40 -- (studs) mais longe que isso do PontoDeSpawn, o pedido é recusado
local ESPERA_ENTRE_PEDIDOS = 3 -- (s) tempo mínimo entre um quadriciclo novo e outro
local SENTAR_SOZINHO = true -- o jogador já senta no quadriciclo novo
local ALTURA_DO_SPAWN = 2 -- (studs) o quadriciclo aparece um pouquinho acima do PontoDeSpawn

-- Pega uma pasta (ou cria, se ainda não existir).
local function pegarPasta(pai: Instance, nome: string): Instance
	local achada = pai:FindFirstChild(nome)
	if achada then
		return achada
	end
	local nova = Instance.new("Folder")
	nova.Name = nome
	nova.Parent = pai
	return nova
end

local moldes = pegarPasta(ReplicatedStorage, "Quadriciclos") -- os moldes que aparecem na garagem
local pastaDosQuads = pegarPasta(workspace, "QuadriciclosDosJogadores") -- os quadriciclos spawnados
if #moldes:GetChildren() == 0 then
	warn("[Spawner] A pasta ReplicatedStorage > Quadriciclos está vazia: coloque os moldes lá (veja o topo do script).")
end

-- O "fio" entre a tela da garagem (cliente) e este script.
local remoto = Instance.new("RemoteEvent")
remoto.Name = "Garagem"
remoto.Parent = ReplicatedStorage

local quadDoJogador: { [Player]: Model } = {} -- o quadriciclo de cada jogador
local ultimoPedido: { [Player]: number } = {} -- quando (os.clock) cada um pediu o último

-- Uma Part do spawner pelo nome. (Spawner de uma Part só? Ela mesma faz tudo.)
local function parteDoSpawner(spawner: Instance, nome: string): BasePart?
	local achada = spawner:FindFirstChild(nome, true)
	if achada and achada:IsA("BasePart") then
		return achada
	end
	if spawner:IsA("BasePart") then
		return spawner
	end
	return nil
end

-- =====================================================================
-- O "E  GARAGEM" EM CADA SPAWNER
-- =====================================================================
local function prepararSpawner(spawner: Instance)
	local ponto = parteDoSpawner(spawner, "PontoDeSpawn")
	if ponto == nil then
		warn(`[Spawner] "{spawner:GetFullName()}" não tem uma Part chamada "PontoDeSpawn".`)
		return
	end
	local painel = parteDoSpawner(spawner, "Painel") or ponto
	if painel:FindFirstChild("PromptGaragem") then
		return -- (já estava pronto)
	end
	local aviso = Instance.new("ProximityPrompt")
	aviso.Name = "PromptGaragem"
	aviso.ActionText = "Garagem"
	aviso.ObjectText = "Quadriciclos"
	aviso.KeyboardKeyCode = Enum.KeyCode.E
	aviso.GamepadKeyCode = Enum.KeyCode.ButtonX
	aviso.HoldDuration = 0
	aviso.MaxActivationDistance = 12
	aviso.RequiresLineOfSight = false
	aviso.Parent = painel
	aviso.Triggered:Connect(function(jogador: Player)
		remoto:FireClient(jogador, "Abrir", spawner) -- abre a tela da garagem SÓ para quem apertou
	end)
end

for _, spawner in CollectionService:GetTagged(TAG_SPAWNER) do
	prepararSpawner(spawner)
end
CollectionService:GetInstanceAddedSignal(TAG_SPAWNER):Connect(prepararSpawner)

-- =====================================================================
-- SPAWNAR
-- =====================================================================
local function apagarQuadDe(jogador: Player)
	local antigo = quadDoJogador[jogador]
	quadDoJogador[jogador] = nil
	if antigo then
		antigo:Destroy()
	end
end

-- Gira o quadriciclo (em volta do "de pé") para o BANCO olhar para a frente do ponto, e põe
-- o meio dele em cima do ponto, com a parte de baixo ALTURA_DO_SPAWN studs acima.
local function posicionar(quad: Model, ponto: BasePart)
	local olharDoPonto = ponto.CFrame.LookVector
	local frente = Vector3.new(olharDoPonto.X, 0, olharDoPonto.Z)
	frente = if frente.Magnitude > 0.01 then frente.Unit else Vector3.new(0, 0, -1)
	local banco = quad:FindFirstChildWhichIsA("VehicleSeat", true)
	local olharDoBanco = if banco then banco.CFrame.LookVector else quad:GetPivot().LookVector
	local atual = Vector3.new(olharDoBanco.X, 0, olharDoBanco.Z)
	atual = if atual.Magnitude > 0.01 then atual.Unit else Vector3.new(0, 0, -1)
	-- (math.atan2 descobre o ângulo de cada direção; a diferença é quanto girar)
	local giro = math.atan2(-frente.X, -frente.Z) - math.atan2(-atual.X, -atual.Z)
	local pivo = quad:GetPivot()
	quad:PivotTo(CFrame.new(pivo.Position) * CFrame.Angles(0, giro, 0) * pivo.Rotation)
	local caixa, tamanho = quad:GetBoundingBox() -- a "caixa" que cabe o quadriciclo inteiro
	-- A altura do topo do ponto (funciona até com a Part girada, como um cilindro "em pé").
	local cf = ponto.CFrame
	local meiaAltura = (math.abs(cf.RightVector.Y) * ponto.Size.X + math.abs(cf.UpVector.Y) * ponto.Size.Y
		+ math.abs(cf.LookVector.Y) * ponto.Size.Z) / 2
	local topoDoPonto = ponto.Position.Y + meiaAltura
	local mover = Vector3.new(
		ponto.Position.X - caixa.Position.X,
		topoDoPonto + ALTURA_DO_SPAWN - (caixa.Position.Y - tamanho.Y / 2),
		ponto.Position.Z - caixa.Position.Z
	)
	quad:PivotTo(quad:GetPivot() + mover)
end

local function spawnar(jogador: Player, molde: Model, ponto: BasePart)
	apagarQuadDe(jogador) -- um quadriciclo por jogador: o antigo some
	local quad = molde:Clone() :: Model -- (o "::" só confirma para o Studio que a cópia é um Model)
	quad:SetAttribute("Dono", jogador.UserId)
	posicionar(quad, ponto)
	quad.Parent = pastaDosQuads -- no Workspace, o Servidor do quadriciclo liga sozinho
	quadDoJogador[jogador] = quad
	quad.AncestryChanged:Connect(function()
		-- sumiu (caiu do mapa, foi apagado...)? esquece ele
		if not quad:IsDescendantOf(workspace) and quadDoJogador[jogador] == quad then
			quadDoJogador[jogador] = nil
		end
	end)
	remoto:FireClient(jogador, "Pronto")
	if SENTAR_SOZINHO then
		task.delay(0.5, function() -- espera o Servidor do quadriciclo ficar pronto
			local personagem = jogador.Character
			local humanoide = if personagem then personagem:FindFirstChildOfClass("Humanoid") else nil
			local banco = quad:FindFirstChildWhichIsA("VehicleSeat", true)
			if humanoide and humanoide.Health > 0 and banco and banco.Occupant == nil and quad.Parent then
				banco:Sit(humanoide)
			end
		end)
	end
end

-- O jogador apertou SPAWNAR na tela da garagem. Confere tudo antes (nunca confie no cliente!).
remoto.OnServerEvent:Connect(function(jogador: Player, acao: unknown, spawner: unknown, nome: unknown)
	if acao ~= "Spawnar" or typeof(spawner) ~= "Instance" or typeof(nome) ~= "string" then
		return
	end
	-- 1) Não pode pedir toda hora.
	local agora = os.clock()
	if agora - (ultimoPedido[jogador] or 0) < ESPERA_ENTRE_PEDIDOS then
		remoto:FireClient(jogador, "Aviso", "Espere um pouquinho para pegar outro quadriciclo.")
		return
	end
	-- 2) Tem que ser um spawner de verdade, e o molde tem que existir na pasta.
	if not CollectionService:HasTag(spawner, TAG_SPAWNER) then
		return
	end
	local ponto = parteDoSpawner(spawner, "PontoDeSpawn")
	local molde = moldes:FindFirstChild(nome)
	if ponto == nil or molde == nil or not molde:IsA("Model") then
		return
	end
	-- 3) Tem que estar perto do spawner.
	local personagem = jogador.Character
	local raiz = if personagem then personagem:FindFirstChild("HumanoidRootPart") else nil
	if not (raiz and raiz:IsA("BasePart")) or (raiz.Position - ponto.Position).Magnitude > DISTANCIA_MAXIMA then
		remoto:FireClient(jogador, "Aviso", "Chegue mais perto do spawner.")
		return
	end
	ultimoPedido[jogador] = agora
	spawnar(jogador, molde, ponto)
end)

-- Saiu do jogo: o quadriciclo dele some junto.
Players.PlayerRemoving:Connect(function(jogador: Player)
	apagarQuadDe(jogador)
	ultimoPedido[jogador] = nil
end)

