--!strict
--[[
	=====================================================================
	PoeiraDoChao  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > PoeiraDoChao
	       (DENTRO do QuadricicloCliente, junto com Veiculo, Sensacao, Pista...)
	=====================================================================

	O CHÃO VOANDO: as rodas jogam pedacinhos e poeira DO CHÃO que está embaixo de cada uma, com a
	COR e o JEITO dele. Vale para o quadriciclo e para o caminhão monstro.
	  - No TERRAIN: grama, terra, lama, areia, neve, gelo, pedra, asfalto, água... A cor é a do
	    material no SEU mapa (a mesma do Terrain › Material Colors).
	  - Numa PEÇA: o jeito vem do material dela (madeira, metal, concreto, plástico...) e a cor é a
	    COR da peça.
	QUANDO:
	  ARRANCADA ..... acelerando, as rodas de tração jogam o chão para trás (mais forte saindo devagar
	                  ou com a roda patinando).
	  CHÃO SOLTO .... em terra, areia, neve, lama e água, só de andar já levanta (mais rápido = mais).
	  FREADA ........ freando (ou no freio de mão), as rodas jogam o chão para a frente.
	  DERRAPANDO .... escorregando de lado: poeira.
	  TURBO ......... ligou o nitro (ou passou num boost pad): um estouro de chão nas rodas de tração
	                  (e mais chão enquanto o turbo dura).
	  POUSO ......... CADA roda que volta a encostar no chão solta um "puf" do chão, até num pulinho de
	                  1 stud numa lombadinha. Quanto mais forte a batida, maior o "puf".
	  METAL ......... no metal, em vez de terra, saem FAÍSCAS.
	Cada coisa tem liga/desliga e quantidade nos AJUSTES. Quer mudar a cara de um tipo de chão? Tabela
	TIPOS. Um material que ficou no tipo errado? Tabela MATERIAL_PARA_TIPO.
	O QuadricicloCliente chama PoeiraDoChao.atualizar(quad, dt, pedal, noBoost) a cada frame.
	Só quem está dirigindo vê (como o resto do Sensacao): roda no seu computador, sem usar a internet.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Veiculo = require(script.Parent:WaitForChild("Veiculo")) -- (a "frente" e o "cima" do veículo)

local PoeiraDoChao = {}

-- =====================================================================
-- AJUSTES
-- =====================================================================
local QUANTIDADE = 1 -- tudo junto: 0.5 = metade · 2 = o dobro · 0 = desliga tudo
local ARRANCADA = true -- acelerando: as rodas de tração jogam o chão para trás
local CHAO_SOLTO = true -- em terra, areia, neve, lama e água, só de andar já levanta
local FREADA = true -- freando: as rodas jogam o chão para a frente
local DERRAPANDO = true -- escorregando de lado: poeira
local TURBO = true -- ligou o nitro (ou pegou um boost pad): estouro de chão nas rodas de tração
local POUSO = true -- cada roda que volta a encostar no chão solta um "puf"

local PEDACOS_POR_SEGUNDO = 55 -- o máximo de pedacinhos por segundo em CADA roda (com tudo no máximo)
local POEIRA_POR_SEGUNDO = 18 -- o máximo de poeira por segundo em CADA roda
local POUSO_BATIDA_MINIMA = 5 -- (studs/s) a roda batendo no chão mais devagar que isso não solta nada
local POUSO_BATIDA_FORTE = 45 -- (studs/s) batendo assim (ou mais), o "puf" é o maior
local POUSO_TEMPO_NO_AR = 0.05 -- (s) a roda precisa ficar pelo menos isso sem chão (cair 1 stud ≈ 0,1 s)
local POUSO_INTERVALO = 0.15 -- (s) a mesma roda só solta outro "puf" depois disso (chão esburacado)
local FREADA_VELOCIDADE_MINIMA = 6 -- (studs/s) freando mais devagar que isso, não solta nada
local FOLGA_DO_CHAO = 0.35 -- (studs) a roda mais longe do chão que isso já conta como "no ar"

-- =====================================================================
-- OS TIPOS DE CHÃO
-- =====================================================================
type Tipo = {
	solto: number, -- 0 = chão duro (só solta acelerando, freando ou batendo) · 1 = bem solto (levanta só de andar)
	pedacos: number, -- quantos pedacinhos voam (0 = nenhum · 1 = normal)
	peso: number, -- (studs/s²) a "gravidade" dos pedacinhos: alto = caem rápido (lama) · baixo = boiam (neve)
	tamanho: number, -- (studs) o tamanho dos pedacinhos (numa roda de quadriciclo)
	poeira: number, -- quanta poeira sai (0 = nenhuma · 1 = normal)
	clarear: number, -- quanto a poeira é mais clara que o chão (0 = a mesma cor · 1 = branca)
	brilho: number, -- os pedacinhos brilham (0 = nada · 1 = muito)
	misturar: Color3?, -- os pedacinhos misturam com esta cor (a grama leva um pouco de terra junto)
	faiscas: boolean?, -- true = em vez de pedacinhos, saem faíscas
}
local TIPOS: { [string]: Tipo } = {
	Grama = { solto = 0.4, pedacos = 1, peso = 50, tamanho = 0.35, poeira = 0.35, clarear = 0.25, brilho = 0, misturar = Color3.fromRGB(110, 80, 50) },
	Terra = { solto = 0.85, pedacos = 1.1, peso = 70, tamanho = 0.45, poeira = 0.9, clarear = 0.35, brilho = 0 },
	Lama = { solto = 1, pedacos = 1.3, peso = 95, tamanho = 0.6, poeira = 0.1, clarear = 0, brilho = 0 },
	Areia = { solto = 1, pedacos = 1.4, peso = 55, tamanho = 0.3, poeira = 1, clarear = 0.25, brilho = 0 },
	Neve = { solto = 1, pedacos = 1.2, peso = 22, tamanho = 0.4, poeira = 1.2, clarear = 0.1, brilho = 0.15 },
	Gelo = { solto = 0.15, pedacos = 0.5, peso = 60, tamanho = 0.25, poeira = 0.5, clarear = 0.3, brilho = 0.3 },
	Pedra = { solto = 0.15, pedacos = 0.6, peso = 85, tamanho = 0.22, poeira = 0.7, clarear = 0.4, brilho = 0 },
	Asfalto = { solto = 0, pedacos = 0, peso = 0, tamanho = 0, poeira = 0.8, clarear = 0.7, brilho = 0 }, -- (fumaça de pneu)
	Madeira = { solto = 0, pedacos = 0.4, peso = 70, tamanho = 0.2, poeira = 0.5, clarear = 0.4, brilho = 0 },
	Metal = { solto = 0, pedacos = 0.8, peso = 60, tamanho = 0.15, poeira = 0.25, clarear = 0.5, brilho = 1, faiscas = true },
	Agua = { solto = 1, pedacos = 1.5, peso = 60, tamanho = 0.35, poeira = 0.8, clarear = 0.6, brilho = 0.3 },
	Liso = { solto = 0, pedacos = 0, peso = 0, tamanho = 0, poeira = 0.6, clarear = 0.5, brilho = 0 }, -- (plástico, vidro...)
}
-- Que tipo de chão é cada material. Os que não estão aqui (plástico, neon, vidro, tecido...) são "Liso":
-- só uma poeirinha da cor da peça.
local MATERIAL_PARA_TIPO: { [Enum.Material]: string } = {
	[Enum.Material.Grass] = "Grama",
	[Enum.Material.LeafyGrass] = "Grama",
	[Enum.Material.Ground] = "Terra",
	[Enum.Material.Mud] = "Lama",
	[Enum.Material.Sand] = "Areia",
	[Enum.Material.Salt] = "Areia",
	[Enum.Material.Snow] = "Neve",
	[Enum.Material.Ice] = "Gelo",
	[Enum.Material.Glacier] = "Gelo",
	[Enum.Material.Rock] = "Pedra",
	[Enum.Material.Slate] = "Pedra",
	[Enum.Material.Basalt] = "Pedra",
	[Enum.Material.Limestone] = "Pedra",
	[Enum.Material.Granite] = "Pedra",
	[Enum.Material.Marble] = "Pedra",
	[Enum.Material.Sandstone] = "Pedra",
	[Enum.Material.Cobblestone] = "Pedra",
	[Enum.Material.Brick] = "Pedra",
	[Enum.Material.Pebble] = "Pedra",
	[Enum.Material.CrackedLava] = "Pedra",
	[Enum.Material.Asphalt] = "Asfalto",
	[Enum.Material.Concrete] = "Asfalto",
	[Enum.Material.Pavement] = "Asfalto",
	[Enum.Material.Wood] = "Madeira",
	[Enum.Material.WoodPlanks] = "Madeira",
	[Enum.Material.Metal] = "Metal",
	[Enum.Material.DiamondPlate] = "Metal",
	[Enum.Material.CorrodedMetal] = "Metal",
	[Enum.Material.Foil] = "Metal",
	[Enum.Material.Water] = "Agua",
}

local TEXTURA_POEIRA = "rbxasset://textures/particles/smoke_main.dds"
local TEXTURA_FAISCA = "rbxasset://textures/particles/sparkles_main.dds"
local BRANCO = Color3.new(1, 1, 1)
local PRETO = Color3.new(0, 0, 0)

-- =====================================================================
-- O QUE O MÓDULO GUARDA
-- =====================================================================
type Roda = {
	roda: BasePart,
	raio: number,
	tracao: boolean, -- recebe força do motor? (só essas jogam o chão na arrancada e no turbo)
	eixo: Attachment?, -- o Attachment do motor da roda (o eixo X dele = para onde aponta o eixo da roda)
	escala: number, -- roda maior (caminhão monstro) = pedaços maiores e mais rápidos
	ponto: Attachment, -- (solto no mundo) embaixo da roda: de onde o chão voa
	jato: ParticleEmitter, -- os pedacinhos (ou as faíscas)
	nuvem: ParticleEmitter, -- a poeira
	velocidadeDoJato: NumberRange, -- (as rapidezes normais: o "puf" muda e depois volta)
	velocidadeDaNuvem: NumberRange,
	tipo: string?, -- o tipo de chão que os emissores estão mostrando agora
	cor: Color3?, -- a cor do chão que eles estão mostrando agora
	tocando: boolean, -- encostando no chão agora?
	noAr: number, -- (s) há quanto tempo a roda não encosta no chão
	velocidadeNoAr: Vector3, -- a velocidade da roda no último frame sem chão (para medir a batida)
	ultimoPouso: number, -- (os.clock) o último "puf" desta roda
}
type Estado = {
	quad: any,
	chassi: BasePart,
	rodas: { Roda },
	criados: { Instance }, -- tudo que o módulo criou (para apagar no fim)
	filtro: RaycastParams, -- os raios do chão: ignoram o veículo, o seu boneco e a água
	filtroAgua: RaycastParams, -- os raios que procuram a água
	nitroAntes: boolean,
}

local estado: Estado? = nil
local ultimaAtualizacao = 0
local vigia: RBXScriptConnection? = nil

-- Devolve o valor como uma Instance (ou nil, se ele não for uma).
local function comoInstancia(valor: any): Instance?
	return if typeof(valor) == "Instance" then (valor :: Instance) else nil
end

-- =====================================================================
-- O CHÃO: que tipo é e de que cor
-- =====================================================================
local function lerChao(acerto: RaycastResult): (string, Color3)
	local material = acerto.Material
	local nome = MATERIAL_PARA_TIPO[material] or "Liso"
	local peca = acerto.Instance
	if peca:IsA("Terrain") then
		if material == Enum.Material.Water then
			return nome, peca.WaterColor:Lerp(BRANCO, 0.55) -- (a espuma é mais clara que a água)
		end
		return nome, peca:GetMaterialColor(material) -- a cor do material no SEU mapa
	elseif peca:IsA("BasePart") then
		return nome, peca.Color -- a cor da peça
	end
	return nome, Color3.fromRGB(180, 170, 150)
end

-- A cor da POEIRA deste chão (outros efeitos usam a mesma, como a onda de poeira do módulo Pista).
function PoeiraDoChao.corDaPoeira(acerto: RaycastResult): ColorSequence
	local nome, cor = lerChao(acerto)
	local clara = cor:Lerp(BRANCO, TIPOS[nome].clarear)
	return ColorSequence.new(clara, clara:Lerp(cor, 0.4))
end

-- Os emissores desta roda passam a mostrar este chão (só muda alguma coisa quando o chão muda).
local function vestir(roda: Roda, nome: string, cor: Color3)
	if roda.tipo == nome and roda.cor == cor then
		return
	end
	roda.tipo = nome
	roda.cor = cor
	local tipo = TIPOS[nome]
	local jato = roda.jato
	if tipo.faiscas then
		jato.Texture = TEXTURA_FAISCA
		jato.Color = ColorSequence.new(Color3.fromRGB(255, 235, 160), Color3.fromRGB(255, 130, 40))
		jato.LightEmission = 1
		jato.LightInfluence = 0
		jato.Size = NumberSequence.new(0.5 * roda.escala, 0)
		jato.Lifetime = NumberRange.new(0.15, 0.35)
	else
		jato.Texture = TEXTURA_POEIRA
		local misturar = tipo.misturar
		jato.Color = ColorSequence.new(cor, if misturar then cor:Lerp(misturar, 0.6) else cor:Lerp(PRETO, 0.25))
		jato.LightEmission = tipo.brilho
		jato.LightInfluence = 0.8
		local tamanho = tipo.tamanho * roda.escala
		jato.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, tamanho),
			NumberSequenceKeypoint.new(0.5, tamanho * 1.3),
			NumberSequenceKeypoint.new(1, tamanho * 0.5),
		})
		jato.Lifetime = NumberRange.new(0.35, 0.75)
	end
	jato.Acceleration = Vector3.new(0, -tipo.peso, 0)
	local clara = cor:Lerp(BRANCO, tipo.clarear)
	roda.nuvem.Color = ColorSequence.new(clara, clara:Lerp(cor, 0.4))
end

-- Aponta o ponto da roda: fica no chão, com a "frente" (de onde as partículas saem) para "direcao".
-- (reserva: um "cima" para usar quando a direção é a própria normal do chão, como no pouso)
local function apontar(roda: Roda, posicao: Vector3, direcao: Vector3, normal: Vector3, reserva: Vector3)
	local unidade = direcao.Unit
	local cima = normal
	if math.abs(unidade:Dot(cima)) > 0.98 then
		cima = if math.abs(unidade:Dot(reserva)) < 0.9 then reserva else Vector3.xAxis
	end
	roda.ponto.WorldCFrame = CFrame.lookAt(posicao, posicao + direcao, cima)
end

-- Um estouro de uma vez (o pouso e o turbo): muda o jeito de sair, solta e volta ao normal.
--   espalhar / espalharPoeira: (graus) o quanto os pedacinhos / a poeira se abrem em volta da direção
local function estourar(roda: Roda, pedacos: number, poeira: number, espalhar: number, espalharPoeira: number, rapidez: number)
	local jato, nuvem = roda.jato, roda.nuvem
	local tipo = TIPOS[roda.tipo or "Liso"]
	local maisRapido = math.sqrt(roda.escala)
	local quantosPedacos = math.round(pedacos * tipo.pedacos * QUANTIDADE)
	if quantosPedacos > 0 then
		jato.SpreadAngle = Vector2.new(espalhar, espalhar)
		jato.Speed = NumberRange.new(rapidez * 0.5 * maisRapido, rapidez * maisRapido)
		jato:Emit(quantosPedacos)
		jato.SpreadAngle = Vector2.new(20, 20)
		jato.Speed = roda.velocidadeDoJato
	end
	local quantaPoeira = math.round(poeira * tipo.poeira * QUANTIDADE)
	if quantaPoeira > 0 then
		nuvem.SpreadAngle = Vector2.new(espalharPoeira, espalharPoeira)
		nuvem.Speed = NumberRange.new(rapidez * 0.25 * maisRapido, rapidez * 0.5 * maisRapido)
		nuvem:Emit(quantaPoeira)
		nuvem.SpreadAngle = Vector2.new(50, 50)
		nuvem.Speed = roda.velocidadeDaNuvem
	end
end

-- =====================================================================
-- LIGAR E DESLIGAR
-- =====================================================================
local function prepararRoda(info: any, criados: { Instance }): Roda?
	local roda = comoInstancia(info.roda)
	if roda == nil or not roda:IsA("BasePart") then
		return nil
	end
	local raio: number = if typeof(info.raio) == "number" then info.raio else roda.Size.Y / 2
	local escala = math.clamp(raio / 1.2, 0.7, 3)
	local maisRapido = math.sqrt(escala)
	local motor = comoInstancia(info.motor)
	local eixo = if motor and motor:IsA("HingeConstraint") then motor.Attachment0 else nil

	local ponto = Instance.new("Attachment")
	ponto.Name = "PoeiraDoChao"
	ponto.Parent = workspace.Terrain -- (solto no mundo: as partículas ficam para trás quando o veículo anda)
	table.insert(criados, ponto)

	-- OS PEDACINHOS: voam para longe da roda e caem de volta (a cor e o peso vêm do chão).
	local velocidadeDoJato = NumberRange.new(10 * maisRapido, 20 * maisRapido)
	local jato = Instance.new("ParticleEmitter")
	jato.Name = "PedacosDoChao"
	jato.Texture = TEXTURA_POEIRA
	jato.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	jato.Speed = velocidadeDoJato
	jato.SpreadAngle = Vector2.new(20, 20)
	jato.Drag = 1
	jato.Rotation = NumberRange.new(0, 360)
	jato.RotSpeed = NumberRange.new(-200, 200)
	jato.EmissionDirection = Enum.NormalId.Front
	jato.Rate = 0
	jato.Parent = ponto

	-- A POEIRA: bolotas que incham, boiam e somem.
	local velocidadeDaNuvem = NumberRange.new(2 * maisRapido, 5 * maisRapido)
	local nuvem = Instance.new("ParticleEmitter")
	nuvem.Name = "PoeiraDoChao"
	nuvem.Texture = TEXTURA_POEIRA
	nuvem.LightInfluence = 0.6
	nuvem.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6 * escala),
		NumberSequenceKeypoint.new(0.3, 1.8 * escala), -- incha rápido...
		NumberSequenceKeypoint.new(1, 2.8 * escala), -- ...e continua crescendo devagar
	})
	nuvem.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.6, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	nuvem.Lifetime = NumberRange.new(0.6, 1.1)
	nuvem.Speed = velocidadeDaNuvem
	nuvem.SpreadAngle = Vector2.new(50, 50)
	nuvem.Acceleration = Vector3.new(0, 2.5, 0) -- sobe um pouquinho
	nuvem.Drag = 3 -- e freia no ar (fica boiando atrás da roda)
	nuvem.Rotation = NumberRange.new(0, 360)
	nuvem.RotSpeed = NumberRange.new(-30, 30)
	nuvem.EmissionDirection = Enum.NormalId.Front
	nuvem.Rate = 0
	nuvem.Parent = ponto

	return {
		roda = roda,
		raio = raio,
		tracao = info.tracao == true,
		eixo = eixo,
		escala = escala,
		ponto = ponto,
		jato = jato,
		nuvem = nuvem,
		velocidadeDoJato = velocidadeDoJato,
		velocidadeDaNuvem = velocidadeDaNuvem,
		tipo = nil,
		cor = nil,
		tocando = true, -- (começa "no chão": sentar não solta "puf")
		noAr = 0,
		velocidadeNoAr = Vector3.zero,
		ultimoPouso = 0,
	}
end

local function parar(atual: Estado)
	for _, roda in atual.rodas do
		roda.jato.Rate = 0
		roda.nuvem.Rate = 0
	end
end

local function desligar()
	local conexao = vigia
	if conexao then
		conexao:Disconnect()
	end
	vigia = nil
	local atual = estado
	estado = nil
	if atual == nil then
		return
	end
	parar(atual)
	-- espera as últimas partículas sumirem e apaga tudo que o módulo criou
	local criados = atual.criados
	task.delay(1.5, function()
		for _, objeto in criados do
			objeto:Destroy()
		end
	end)
end

local function ligar(quad: any): Estado?
	local chassi = comoInstancia(quad.chassi)
	if chassi == nil or not chassi:IsA("BasePart") or chassi.Parent == nil then
		return nil
	end
	local criados: { Instance } = {}
	local rodas: { Roda } = {}
	if typeof(quad.rodas) == "table" then
		for _, info in quad.rodas do
			local roda = prepararRoda(info, criados)
			if roda then
				table.insert(rodas, roda)
			end
		end
	end
	-- Os raios ignoram o veículo e o seu boneco. O do chão atravessa a água; o outro procura a água.
	local ignorar: { Instance } = {}
	local modelo = comoInstancia(quad.modelo)
	if modelo then
		table.insert(ignorar, modelo)
	end
	local jogador = Players.LocalPlayer
	local personagem = if jogador then jogador.Character else nil
	if personagem then
		table.insert(ignorar, personagem)
	end
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	filtro.FilterDescendantsInstances = ignorar
	filtro.IgnoreWater = true
	local filtroAgua = RaycastParams.new()
	filtroAgua.FilterType = Enum.RaycastFilterType.Exclude
	filtroAgua.FilterDescendantsInstances = ignorar
	filtroAgua.IgnoreWater = false
	-- Rede de segurança: se o QuadricicloCliente parar de chamar o atualizar, o chão para de voar.
	vigia = RunService.Heartbeat:Connect(function()
		local atual = estado
		if atual and os.clock() - ultimaAtualizacao > 0.5 then
			parar(atual)
		end
	end)
	return {
		quad = quad,
		chassi = chassi,
		rodas = rodas,
		criados = criados,
		filtro = filtro,
		filtroAgua = filtroAgua,
		nitroAntes = quad.nitroAtivo == true,
	}
end

-- =====================================================================
-- A CADA FRAME (o QuadricicloCliente chama isto enquanto você dirige)
-- =====================================================================
--   pedal: de -1 (freio/ré) a 1 (acelerador), o mesmo que o QuadricicloCliente usa para dirigir.
--   noBoost: true = o empurrão de um boost pad está valendo agora (conta como turbo, igual ao nitro).
function PoeiraDoChao.atualizar(quad: any, dt: number, pedal: number, noBoost: boolean?)
	ultimaAtualizacao = os.clock()
	-- Trocou de veículo (ou ele sumiu)? Desliga o velho e prepara o novo.
	local velho = estado
	if velho and (velho.quad ~= quad or velho.chassi.Parent == nil) then
		desligar()
	end
	if QUANTIDADE <= 0 then
		return
	end
	if estado == nil then
		estado = ligar(quad)
	end
	local atual = estado
	if atual == nil then
		return
	end
	local agora = os.clock()
	local referencia: CFrame = Veiculo.referencia(quad)
	local cima = referencia.UpVector
	local frente = referencia.LookVector
	local velocidade = atual.chassi.AssemblyLinearVelocity
	local rapidez = velocidade.Magnitude
	local velocidadeFrente = velocidade:Dot(frente)

	-- O que o motorista está fazendo
	local freando = FREADA
		and ((pedal < -0.1 and velocidadeFrente > FREADA_VELOCIDADE_MINIMA)
			or (pedal > 0.1 and velocidadeFrente < -FREADA_VELOCIDADE_MINIMA) -- (freando quando vinha de ré)
			or (quad.freioDeMao == true and rapidez > FREADA_VELOCIDADE_MINIMA))
	local acelerando = if ARRANCADA and not freando and math.abs(pedal) > 0.1 then math.abs(pedal) else 0
	local sentido = if pedal < 0 then -1 else 1 -- (+1 = para a frente · -1 = de ré)
	local nitro = TURBO and (quad.nitroAtivo == true or noBoost == true)
	local turboComecou = nitro and not atual.nitroAntes
	atual.nitroAntes = nitro
	local freioDeMao = quad.freioDeMao == true

	for _, roda in atual.rodas do
		local centro = roda.roda.Position
		local vel = roda.roda.AssemblyLinearVelocity
		-- 1) O CHÃO embaixo da roda (a água, se tiver, ganha: a roda espirra água)
		local chao = workspace:Raycast(centro, -cima * (roda.raio + FOLGA_DO_CHAO), atual.filtro)
		local agua = workspace:Raycast(centro + cima * 2, -cima * (2 + roda.raio + FOLGA_DO_CHAO), atual.filtroAgua)
		if agua and agua.Material == Enum.Material.Water then
			chao = agua
		end
		if chao == nil then
			-- NO AR: nada sai; guarda a velocidade para medir a batida quando encostar
			roda.tocando = false
			roda.noAr += dt
			roda.velocidadeNoAr = vel
			if roda.jato.Rate ~= 0 then
				roda.jato.Rate = 0
			end
			if roda.nuvem.Rate ~= 0 then
				roda.nuvem.Rate = 0
			end
			continue
		end
		local nome, cor = lerChao(chao)
		vestir(roda, nome, cor)
		local tipo = TIPOS[nome]
		local normal = chao.Normal
		local posicao = chao.Position + normal * 0.25

		-- 2) POUSO: a roda estava no ar e encostou agora? "Puf!" (maior quanto mais forte a batida)
		if not roda.tocando then
			local batida = -roda.velocidadeNoAr:Dot(normal) -- quão rápido ela vinha CONTRA o chão
			if POUSO
				and roda.noAr >= POUSO_TEMPO_NO_AR
				and batida >= POUSO_BATIDA_MINIMA
				and agora - roda.ultimoPouso >= POUSO_INTERVALO
			then
				roda.ultimoPouso = agora
				local forca = math.clamp((batida - POUSO_BATIDA_MINIMA) / (POUSO_BATIDA_FORTE - POUSO_BATIDA_MINIMA), 0, 1)
				-- (sai para cima do chão; os pedacinhos num cone e a poeira quase deitada, em volta da roda)
				apontar(roda, posicao, normal, normal, frente)
				estourar(roda, 3 + 14 * forca, 2 + 9 * forca, 60, 85, 8 + 22 * forca)
			end
		end
		roda.tocando = true
		roda.noAr = 0

		-- 3) A RODA ESCORREGANDO (de lado) ou PATINANDO (girando diferente do chão)?
		local eixo = roda.eixo
		local lado = if eixo then eixo.WorldAxis else referencia.RightVector
		local escorrega = math.abs(vel:Dot(lado))
		local patina = 0
		local rolar = lado:Cross(cima)
		if rolar.Magnitude > 0.01 then
			local pneu = math.abs(roda.roda.AssemblyAngularVelocity:Dot(lado)) * roda.raio
			patina = math.abs(pneu - math.abs(vel:Dot(rolar.Unit)))
		end

		-- 4) QUANTO SAI, e para onde
		local noChao = vel - normal * vel:Dot(normal) -- a velocidade da roda "deitada" no chão
		local frenteNoChao = frente - normal * frente:Dot(normal)
		frenteNoChao = if frenteNoChao.Magnitude > 0.01 then frenteNoChao.Unit else frente
		local girando = math.clamp((patina - 4) / 16, 0, 1)
		local arrancada = 0 -- (0 a 1) o motor empurrando o chão para trás: forte saindo devagar ou patinando
		if roda.tracao and not freando then
			arrancada = math.max(acelerando * math.clamp(1 - rapidez / 35, 0, 1), if ARRANCADA then girando else 0)
		end
		local soltando = if CHAO_SOLTO then tipo.solto * math.clamp((rapidez - 4) / 50, 0, 1) else 0
		local freada = if freando then math.clamp((rapidez - FREADA_VELOCIDADE_MINIMA) / 30, 0.25, 1) else 0
		local derrapando = if DERRAPANDO then math.clamp((math.max(escorrega, patina * 0.7) - 6) / 16, 0, 1) else 0
		local turbo = if nitro and roda.tracao then 1 else 0
		local duro = 0.3 + 0.7 * tipo.solto -- (no chão duro, menos pedacinhos)

		local paraTras = math.max(arrancada * duro, soltando, turbo * (0.5 + 0.5 * tipo.solto))
		local paraFrente = freada * duro
		local pedacos = math.max(paraTras, paraFrente, derrapando * 0.6 * duro)
		if tipo.faiscas then
			-- (metal: faísca só freando, derrapando, patinando ou no turbo; andando normal, não)
			pedacos = math.max(freada, derrapando, girando, turbo * 0.5)
		end
		local poeira = math.max(derrapando, freada * 0.7, arrancada * (0.25 + 0.35 * tipo.solto), soltando * 0.6, turbo * 0.35)
		if freioDeMao and tipo.solto < 0.5 then
			poeira = 0 -- (no chão duro, a fumaça do freio de mão é a do módulo FreioDeMao)
		end
		local direcao: Vector3
		if paraFrente > paraTras then
			-- freando: para a frente (para onde o veículo vai)
			direcao = if noChao.Magnitude > 1 then noChao.Unit else frenteNoChao
		elseif arrancada > soltando or turbo > 0 then
			direcao = -frenteNoChao * sentido -- acelerando: para trás da roda (de ré: para a frente)
		else
			direcao = if noChao.Magnitude > 1 then -noChao.Unit else -frenteNoChao * sentido
		end
		apontar(roda, posicao, direcao + normal * 0.6, normal, frente)

		-- 5) TURBO: acabou de ligar o nitro? Um estouro de chão para trás
		if turboComecou and roda.tracao then
			estourar(roda, 10 * (0.5 + 0.5 * tipo.solto), 6, 30, 50, 26)
		end

		local novoJato = math.round(PEDACOS_POR_SEGUNDO * pedacos * tipo.pedacos * QUANTIDADE)
		local novaNuvem = math.round(POEIRA_POR_SEGUNDO * poeira * tipo.poeira * QUANTIDADE)
		if roda.jato.Rate ~= novoJato then
			roda.jato.Rate = novoJato
		end
		if roda.nuvem.Rate ~= novaNuvem then
			roda.nuvem.Rate = novaNuvem
		end
	end
end

-- Parou de dirigir (o QuadricicloCliente chama): para tudo NA HORA.
function PoeiraDoChao.desligar()
	desligar()
end

return PoeiraDoChao
