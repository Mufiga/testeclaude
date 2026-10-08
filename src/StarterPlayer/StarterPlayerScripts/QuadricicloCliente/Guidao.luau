--!strict
--[[
	=====================================================================
	Guidao  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Guidao
	=====================================================================

	O GUIDÃO (quadriciclo) e o VOLANTE (trator, caminhão...) giram junto com as rodas da frente, e quem
	está dirigindo segura neles com as DUAS MÃOS (as mãos acompanham quando gira).
	TODO MUNDO VÊ: cada jogador calcula no próprio computador, a partir das rodas da frente (que o
	Roblox já mostra viradas para todos). Não usa a internet.

	COMO MONTAR (no Studio, no molde do veículo em ReplicatedStorage › Quadriciclos):
	  1. A peça do guidão se chama "Guidao" (no trator/caminhão: "Volante"). Guidão feito de várias
	     peças? Coloque todas num Model (ou Folder) chamado "Guidao": elas giram juntas.
	  2. (Opcional) ONDE ficam as mãos: dois Attachments dentro da peça, "MaoEsquerda" e "MaoDireita".
	     Sem eles, as mãos vão sozinhas para as pontas do guidão (ou para as "10 e 2 horas" do volante).
	  3. (Opcional) O EIXO do giro: um Attachment "Eixo" dentro da peça. A seta AMARELA dele é o eixo:
	     aponte para CIMA no guidão e para o PILOTO no volante. Sem ele, o guidão gira em volta do
	     "para cima" do veículo e o volante em volta do próprio centro (o lado mais fino da peça).
	  4. (Opcional) Atributos na peça (ou no Model): "Giro" (número: quantas vezes gira mais que as
	     rodas; padrão: guidão 1, volante 6) e "Inverter" (boolean: girou para o lado errado? marque).
	As mãos funcionam em personagens R15 (os do Roblox hoje). Num R6, só o guidão gira.
]]

local RunService = game:GetService("RunService")

local Veiculo = require(script.Parent:WaitForChild("Veiculo")) -- (a "frente" e o "cima" do veículo)
type Quadriciclo = Veiculo.Quadriciclo

local Guidao = {}

-- =====================================================================
-- AJUSTES
-- =====================================================================
local GIRO_DO_GUIDAO = 1 -- o guidão gira o mesmo tanto que as rodas
local GIRO_DO_VOLANTE = 6 -- o volante gira 6 vezes mais que as rodas (como num carro)
local SUAVIDADE = 14 -- quão rápido o guidão acompanha as rodas (maior = mais grudado)
local DISTANCIA_MAXIMA = 250 -- (studs) mais longe que isso da câmera, nem calcula (ninguém vê)
local MAOS_NO_GUIDAO = true -- false = só o guidão gira; as mãos ficam como antes

-- =====================================================================
-- O QUE O MÓDULO GUARDA
-- =====================================================================
type Direcao = { constraint: CylindricalConstraint, sinal: number } -- uma roda da frente que vira
type Guiador = {
	quad: Quadriciclo,
	principal: BasePart, -- a peça que gira (as outras do guidão vão presas nela)
	motor: Motor6D, -- a junta (só NESTE computador) que gira o guidão
	giro: number, -- quantas vezes gira mais que as rodas (negativo = invertido)
	direcoes: { Direcao },
	angulo: number, -- (graus) o ângulo de agora (suavizado)
	aplicado: number, -- (graus) o último ângulo colocado na junta
	maoEsquerda: Attachment, -- onde as mãos seguram (giram junto com o guidão)
	maoDireita: Attachment,
	poloEsquerdo: Attachment, -- para onde os cotovelos apontam (presos no banco)
	poloDireito: Attachment,
	maos: { IKControl }, -- as mãos de quem está dirigindo agora
}
local guiadores: { [Quadriciclo]: Guiador } = {}
local conexao: RBXScriptConnection? = nil

-- O giro acontece em volta do "-Z" do pivô (o LookVector dele, que apontamos para o eixo).
local EIXO_LOCAL = Vector3.new(0, 0, -1)

-- =====================================================================
-- ACHAR O GUIDÃO (ou o volante)
-- =====================================================================
local function tipoDoNome(nome: string): string?
	local minusculo = string.lower(nome)
	if minusculo == "guidao" or minusculo == "guidão" then
		return "Guidao"
	elseif minusculo == "volante" then
		return "Volante"
	end
	return nil
end

-- O guidão (peça, Model ou Folder) e se ele é um volante.
local function acharGrupo(modelo: Model): (Instance?, boolean)
	for _, objeto in modelo:GetDescendants() do
		local tipo = tipoDoNome(objeto.Name)
		if tipo and (objeto:IsA("BasePart") or objeto:IsA("Model") or objeto:IsA("Folder")) then
			return objeto, tipo == "Volante"
		end
	end
	return nil, false
end

-- Todas as peças do guidão e a principal (a do Model, ou a maior).
local function pecasDoGrupo(grupo: Instance): ({ BasePart }, BasePart?)
	local pecas: { BasePart } = {}
	if grupo:IsA("BasePart") then
		table.insert(pecas, grupo)
	end
	for _, objeto in grupo:GetDescendants() do
		if objeto:IsA("BasePart") then
			table.insert(pecas, objeto)
		end
	end
	local principal: BasePart? = if grupo:IsA("BasePart") then grupo
		elseif grupo:IsA("Model") then grupo.PrimaryPart
		else nil
	if principal == nil then
		local maiorVolume = -1
		for _, peca in pecas do
			local volume = peca.Size.X * peca.Size.Y * peca.Size.Z
			if volume > maiorVolume then
				maiorVolume = volume
				principal = peca
			end
		end
	end
	return pecas, principal
end

-- As rodas da frente que viram (a mesma conta do Veiculo.prepararRodas: + = para a direita).
local function rodasQueViram(quad: Quadriciclo): { Direcao }
	local lista: { Direcao } = {}
	local referencia = Veiculo.referencia(quad)
	for _, pasta in quad.pastaRodas:GetChildren() do
		local suspensao = pasta:FindFirstChild("Suspensao")
		local manga = pasta:FindFirstChild("Manga")
		local anexo = if suspensao and suspensao:IsA("CylindricalConstraint") then suspensao.Attachment0 else nil
		if suspensao and suspensao:IsA("CylindricalConstraint") and anexo then
			if referencia:PointToObjectSpace(anexo.WorldPosition).Z < 0 then -- (só as da frente)
				local sinal = if anexo.WorldAxis:Dot(referencia.UpVector) < 0 then 1 else -1
				if anexo.Parent == manga then
					sinal = -sinal -- (Attachment0 na Manga: montado ao contrário)
				end
				table.insert(lista, { constraint = suspensao, sinal = sinal })
			end
		end
	end
	return lista
end

-- (graus) quanto as rodas da frente estão viradas agora (+ = para a direita).
local function anguloDasRodas(guiador: Guiador): number
	local soma = 0
	for _, direcao in guiador.direcoes do
		soma += direcao.constraint.CurrentAngle * direcao.sinal
	end
	return if #guiador.direcoes > 0 then soma / #guiador.direcoes else 0
end

-- =====================================================================
-- PRENDER O GUIDÃO NUMA JUNTA QUE GIRA (só neste computador)
-- =====================================================================
-- As soldas que prendem o guidão no resto do veículo são desligadas AQUI (no servidor e nos outros
-- jogadores nada muda: cada um faz o mesmo no seu). O guidão fica preso por um Motor6D, que dá para
-- girar a cada frame. O que está soldado SÓ no guidão (um farol, um retrovisor) continua nele e gira
-- junto; o que está soldado no resto do veículo continua parado.

-- As duas peças de uma solda (WeldConstraint, Weld, Motor6D...), ou nil se não for uma solda.
local function pecasDaSolda(objeto: Instance): (BasePart?, BasePart?)
	if objeto:IsA("WeldConstraint") or objeto:IsA("JointInstance") then
		if objeto.Enabled then
			return objeto.Part0, objeto.Part1
		end
	end
	return nil, nil
end

local function prender(quad: Quadriciclo, pecas: { BasePart }, principal: BasePart, pivo: CFrame): Motor6D?
	local doGuidao: { [BasePart]: boolean } = {}
	for _, peca in pecas do
		doGuidao[peca] = true
	end
	-- 1) Quem cada peça toca pelas soldas (de todo o veículo)
	local soldas: { Instance } = {}
	local vizinhos: { [BasePart]: { BasePart } } = {}
	for _, objeto in quad.modelo:GetDescendants() do
		local a, b = pecasDaSolda(objeto)
		if a and b then
			table.insert(soldas, objeto)
			vizinhos[a] = vizinhos[a] or {}
			vizinhos[b] = vizinhos[b] or {}
			table.insert(vizinhos[a], b)
			table.insert(vizinhos[b], a)
		end
	end
	-- 2) O que continua ligado ao Chassi SEM passar pelo guidão = "o resto do veículo"
	local doVeiculo: { [BasePart]: boolean } = { [quad.chassi] = true }
	local fila = { quad.chassi }
	while #fila > 0 do
		local peca = table.remove(fila) :: BasePart
		local lista = vizinhos[peca]
		if lista then
			for _, vizinho in lista do
				if not doVeiculo[vizinho] and not doGuidao[vizinho] then
					doVeiculo[vizinho] = true
					table.insert(fila, vizinho)
				end
			end
		end
	end
	-- 3) Desliga as soldas entre o guidão e o resto do veículo (só aqui) e junta o guidão na principal
	local base: BasePart? = nil
	for _, solda in soldas do
		local a, b = pecasDaSolda(solda)
		if a and b then
			local doGuidaoNaSolda = if doGuidao[a] then a elseif doGuidao[b] then b else nil
			local outra = if doGuidaoNaSolda == a then b else a
			if doGuidaoNaSolda and doVeiculo[outra] then
				(solda :: any).Enabled = false
				base = base or outra
				if doGuidaoNaSolda ~= principal then
					local junta = Instance.new("WeldConstraint")
					junta.Name = "GuidaoSolda"
					junta.Part0 = principal
					junta.Part1 = doGuidaoNaSolda
					junta.Parent = principal
					Veiculo.guardar(quad, junta)
				end
			end
		end
	end
	if base == nil then
		return nil -- (o guidão não está soldado no veículo: o servidor já avisa no Output)
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "GiroDoGuidao"
	motor.Part0 = base
	motor.Part1 = principal
	motor.C0 = base.CFrame:ToObjectSpace(pivo)
	motor.C1 = principal.CFrame:ToObjectSpace(pivo)
	motor.Parent = principal
	Veiculo.guardar(quad, motor)
	return motor
end

-- O pivô do giro: a posição e o eixo (o LookVector do CFrame que esta função devolve).
local function pivoDoGiro(quad: Quadriciclo, grupo: Instance, principal: BasePart, ehVolante: boolean): CFrame
	local referencia = Veiculo.referencia(quad)
	local eixoMarcado = grupo:FindFirstChild("Eixo", true)
	local posicao = principal.Position
	local eixo: Vector3
	if eixoMarcado and eixoMarcado:IsA("Attachment") then
		posicao = eixoMarcado.WorldPosition
		eixo = eixoMarcado.WorldAxis -- (a seta amarela)
	elseif ehVolante then
		local tamanho = principal.Size -- o lado mais fino da peça = o eixo do volante
		local fino = if tamanho.X <= tamanho.Y and tamanho.X <= tamanho.Z then Vector3.xAxis
			elseif tamanho.Y <= tamanho.Z then Vector3.yAxis
			else Vector3.zAxis
		eixo = principal.CFrame:VectorToWorldSpace(fino)
		if eixo:Dot(quad.assento.Position - posicao) < 0 then
			eixo = -eixo -- (aponta para o piloto)
		end
	else
		eixo = referencia.UpVector
	end
	local dica = if math.abs(eixo:Dot(referencia.UpVector)) > 0.9 then referencia.LookVector else referencia.UpVector
	return CFrame.lookAt(posicao, posicao + eixo, dica)
end

-- Um Attachment (criado só neste computador) num ponto do mundo.
local function anexoNoMundo(quad: Quadriciclo, pai: BasePart, nome: string, posicao: Vector3): Attachment
	local anexo = Instance.new("Attachment")
	anexo.Name = nome
	anexo.Parent = pai
	anexo.WorldPosition = posicao
	Veiculo.guardar(quad, anexo)
	return anexo
end

-- Onde as mãos seguram: os Attachments "MaoEsquerda"/"MaoDireita" ou, sem eles, as pontas do guidão
-- (ou as "10 e 2 horas" do volante).
local function pontosDasMaos(quad: Quadriciclo, grupo: Instance, principal: BasePart, ehVolante: boolean, pivo: CFrame): (Attachment, Attachment)
	local esquerda = grupo:FindFirstChild("MaoEsquerda", true)
	local direita = grupo:FindFirstChild("MaoDireita", true)
	if esquerda and esquerda:IsA("Attachment") and direita and direita:IsA("Attachment") then
		return esquerda, direita
	end
	local referencia = Veiculo.referencia(quad)
	local paraDireita = referencia.RightVector
	local pontoEsquerdo: Vector3
	local pontoDireito: Vector3
	if ehVolante then
		local eixo = pivo.LookVector -- (aponta para o piloto)
		local raio = math.max(principal.Size.X, principal.Size.Y, principal.Size.Z) / 2 * 0.85
		local lado = paraDireita - eixo * paraDireita:Dot(eixo) -- a "direita", deitada no volante
		lado = if lado.Magnitude > 0.01 then lado.Unit else paraDireita
		local cima = eixo:Cross(lado)
		if cima:Dot(referencia.UpVector) < 0 then
			cima = -cima
		end
		local horizontal, vertical = math.cos(math.rad(30)) * raio, math.sin(math.rad(30)) * raio -- 10 e 2 horas
		pontoEsquerdo = pivo.Position - lado * horizontal + cima * vertical
		pontoDireito = pivo.Position + lado * horizontal + cima * vertical
	else
		local tamanho = principal.Size -- o lado mais comprido da peça = a barra do guidão
		local comprido = if tamanho.X >= tamanho.Y and tamanho.X >= tamanho.Z then Vector3.xAxis
			elseif tamanho.Y >= tamanho.Z then Vector3.yAxis
			else Vector3.zAxis
		local barra = principal.CFrame:VectorToWorldSpace(comprido)
		if barra:Dot(paraDireita) < 0 then
			barra = -barra -- (aponta para a direita)
		end
		local metade = math.max(tamanho.X, tamanho.Y, tamanho.Z) * 0.42
		pontoEsquerdo = principal.Position - barra * metade
		pontoDireito = principal.Position + barra * metade
	end
	return anexoNoMundo(quad, principal, "MaoEsquerda", pontoEsquerdo), anexoNoMundo(quad, principal, "MaoDireita", pontoDireito)
end

-- =====================================================================
-- AS MÃOS DE QUEM DIRIGE (IKControl: o Roblox dobra o braço até a mão chegar no guidão)
-- =====================================================================
local function soltarMaos(guiador: Guiador)
	for _, mao in guiador.maos do
		mao:Destroy()
	end
	table.clear(guiador.maos)
end

local function segurar(guiador: Guiador, humanoide: Humanoid?)
	soltarMaos(guiador)
	if not MAOS_NO_GUIDAO or humanoide == nil or humanoide.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	local personagem = humanoide.Parent
	if personagem == nil then
		return
	end
	for _, lado in { "Left", "Right" } do
		local braco = personagem:FindFirstChild(lado .. "UpperArm")
		local mao = personagem:FindFirstChild(lado .. "Hand")
		if braco and braco:IsA("BasePart") and mao and mao:IsA("BasePart") then
			local pegada = mao:FindFirstChild(lado .. "GripAttachment") -- (o meio da palma da mão)
			local ik = Instance.new("IKControl")
			ik.Name = "MaoNoGuidao" .. lado
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = braco
			ik.EndEffector = if pegada and pegada:IsA("Attachment") then pegada else mao
			ik.Target = if lado == "Left" then guiador.maoEsquerda else guiador.maoDireita
			ik.Pole = if lado == "Left" then guiador.poloEsquerdo else guiador.poloDireito
			ik.SmoothTime = 0.05
			ik.Parent = humanoide
			table.insert(guiador.maos, ik)
		end
	end
end

-- =====================================================================
-- A CADA FRAME: o guidão acompanha as rodas da frente
-- =====================================================================
local function atualizar(dt: number)
	local camera = workspace.CurrentCamera
	local daCamera = if camera then camera.CFrame.Position else Vector3.zero
	for quad, guiador in guiadores do
		if (guiador.principal.Position - daCamera).Magnitude > DISTANCIA_MAXIMA then
			continue
		end
		if #guiador.direcoes == 0 then
			guiador.direcoes = rodasQueViram(quad) -- (as rodas ainda estavam chegando: tenta de novo)
		end
		local alvo = anguloDasRodas(guiador) * guiador.giro
		guiador.angulo += (alvo - guiador.angulo) * math.min(dt * SUAVIDADE, 1)
		if math.abs(guiador.angulo - guiador.aplicado) > 0.05 then
			guiador.aplicado = guiador.angulo
			-- (para a direita = sentido do relógio visto de cima, no guidão, e visto pelo piloto, no volante)
			guiador.motor.Transform = CFrame.fromAxisAngle(EIXO_LOCAL, math.rad(-guiador.angulo))
		end
	end
end

-- =====================================================================
-- O QUE O QUADRICICLOCLIENTE USA
-- =====================================================================
-- Um veículo apareceu no seu jogo (o QuadricicloCliente chama para TODOS, não só o que você dirige).
function Guidao.criar(quad: Quadriciclo)
	local grupo, ehVolante = acharGrupo(quad.modelo)
	if grupo == nil then
		return -- (este veículo não tem guidão nem volante)
	end
	local pecas, principal = pecasDoGrupo(grupo)
	if principal == nil then
		return
	end
	local pivo = pivoDoGiro(quad, grupo, principal, ehVolante)
	-- (as mãos são marcadas antes de soltar o guidão: tudo ainda está no lugar certo)
	local maoEsquerda, maoDireita = pontosDasMaos(quad, grupo, principal, ehVolante, pivo)
	local motor = prender(quad, pecas, principal, pivo)
	if motor == nil then
		return
	end
	-- Os cotovelos apontam para fora e um pouco para baixo (pontos presos no banco: não giram).
	local banco = quad.assento
	local giroMarcado = grupo:GetAttribute("Giro")
	local giro = if typeof(giroMarcado) == "number" then giroMarcado elseif ehVolante then GIRO_DO_VOLANTE else GIRO_DO_GUIDAO
	if grupo:GetAttribute("Inverter") == true then
		giro = -giro
	end
	local guiador: Guiador = {
		quad = quad,
		principal = principal,
		motor = motor,
		giro = giro,
		direcoes = rodasQueViram(quad),
		angulo = 0,
		aplicado = 0,
		maoEsquerda = maoEsquerda,
		maoDireita = maoDireita,
		poloEsquerdo = anexoNoMundo(quad, banco, "CotoveloEsquerdo", banco.CFrame:PointToWorldSpace(Vector3.new(-2.2, 1.2, 0.5))),
		poloDireito = anexoNoMundo(quad, banco, "CotoveloDireito", banco.CFrame:PointToWorldSpace(Vector3.new(2.2, 1.2, 0.5))),
		maos = {},
	}
	guiadores[quad] = guiador

	-- Quem senta segura no guidão; quem levanta solta.
	Veiculo.guardarConexao(quad, banco:GetPropertyChangedSignal("Occupant"):Connect(function()
		segurar(guiador, banco.Occupant)
	end))
	segurar(guiador, banco.Occupant) -- (alguém já pode estar sentado)
	table.insert(quad.limpezas, function()
		soltarMaos(guiador)
		guiadores[quad] = nil
	end)

	if conexao == nil then
		conexao = RunService.PreRender:Connect(atualizar)
	end
end

return Guidao
