--!strict
--[[
	=====================================================================
	FreioDeMao  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > FreioDeMao
	=====================================================================

	Para TODO MUNDO (criarEfeitos): fumaça e faíscas em cada roda e o som
	de pneu (Config.FreioDeMaoSomId) enquanto o quadriciclo derrapa.
	Para QUEM DIRIGE (ligar/atualizar/desligar): tecla Espaço / botão B /
	botão F. MÃO. Andando, as rodas travadas ficam com pouco atrito
	(Config.FreioDeMaoAtrito): o carro escorrega e vai freando aos poucos.
	Quase parado, o atrito volta ao normal e ele para de vez.
	(Quem TRAVA as rodas é o "atualizar" do QuadricicloCliente.)
]]

local ContextActionService = game:GetService("ContextActionService")

local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
type Quadriciclo = Veiculo.Quadriciclo

local FreioDeMao = {}

local ACAO_FREIO_DE_MAO = "QuadricicloFreioDeMao"

local derrapandoAvisado = false -- o que o Servidor já sabe (para os outros verem)

-- =====================================================================
-- FUMAÇA, FAÍSCAS E SOM DE PNEU (todo mundo vê e ouve)
-- =====================================================================
local function criarEfeitosDaRoda(quad: Quadriciclo, manga: BasePart, roda: BasePart, baixo: Vector3): (ParticleEmitter, ParticleEmitter)
	local raio = math.min(roda.Size.Y, roda.Size.Z) / 2
	local anexo = Instance.new("Attachment") -- no chão, embaixo da roda (preso na Manga: vira e sobe junto)
	anexo.Name = "EfeitosFreio"
	anexo.Position = manga.CFrame:PointToObjectSpace(roda.Position + baixo * raio)
	anexo.Parent = manga
	Veiculo.guardar(quad, anexo)

	-- (NOVO) FUMAÇA CARTOON (mais leve): poucas bolotas brancas e macias, que incham ("puf!") e somem.
	-- Quer uma nuvem de desenho de verdade? Coloque o ID de uma imagem em Config.FreioDeMaoTexturaFumaca.
	local textura = quad.Config.FreioDeMaoTexturaFumaca
	local fumaca = Instance.new("ParticleEmitter")
	fumaca.Texture = if typeof(textura) == "string" and textura ~= "" then textura else "rbxasset://textures/particles/smoke_main.dds"
	fumaca.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 212, 232)) -- branco que puxa pro lilás
	fumaca.LightInfluence = 0.3 -- quase "chapada" (cara de desenho), mas ainda pega um pouco da luz do lugar
	fumaca.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.25, 2), -- incha rápido...
		NumberSequenceKeypoint.new(1, 2.6), -- ...e cresce devagar até sumir
	})
	fumaca.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.6, 0.25), -- cheia, mas macia
		NumberSequenceKeypoint.new(1, 1), -- some suave no fim
	})
	fumaca.Squash = NumberSequence.new({
		NumberSequenceKeypoint.new(0, -0.3), -- nasce "achatada"...
		NumberSequenceKeypoint.new(0.3, 0.1), -- ...estica um pouquinho (efeito borrachudo)...
		NumberSequenceKeypoint.new(1, 0), -- ...e volta ao normal
	})
	fumaca.Lifetime = NumberRange.new(0.5, 0.8)
	fumaca.Rate = 9 -- (eram 20) menos fumaça
	fumaca.Speed = NumberRange.new(2, 4)
	fumaca.SpreadAngle = Vector2.new(35, 35)
	fumaca.Acceleration = Vector3.new(0, 3, 0)
	fumaca.Drag = 4 -- freia rápido: as bolotas ficam boiando atrás da roda
	fumaca.Rotation = NumberRange.new(0, 360)
	fumaca.RotSpeed = NumberRange.new(-40, 40)
	fumaca.ZOffset = 0.5 -- desenha um pouquinho na frente da roda
	fumaca.EmissionDirection = Enum.NormalId.Top
	fumaca.Enabled = false
	fumaca.Parent = anexo

	-- ESTRELINHAS CARTOON: amarelas, girando, que pulam e caem (a metade de antes).
	local faisca = Instance.new("ParticleEmitter")
	faisca.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	faisca.Color = ColorSequence.new(Color3.fromRGB(255, 245, 150), Color3.fromRGB(255, 175, 60))
	faisca.LightEmission = 0.6
	faisca.LightInfluence = 0
	faisca.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.2, 0.8), -- "pisca" grande...
		NumberSequenceKeypoint.new(1, 0), -- ...e some
	})
	faisca.Lifetime = NumberRange.new(0.25, 0.45)
	faisca.Rate = 10
	faisca.Speed = NumberRange.new(7, 12)
	faisca.SpreadAngle = Vector2.new(55, 55)
	faisca.Acceleration = Vector3.new(0, -45, 0)
	faisca.Rotation = NumberRange.new(0, 360)
	faisca.RotSpeed = NumberRange.new(-300, 300) -- girando
	faisca.EmissionDirection = Enum.NormalId.Top
	faisca.Enabled = false
	faisca.Parent = anexo

	-- (NOVO) UM POUQUINHO DE LUZ perto da roda: acende e apaga junto com as estrelinhas.
	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 190, 120) -- laranja clarinho
	luz.Brightness = 0.6 -- fraquinha
	luz.Range = 5 -- só pertinho da roda
	luz.Shadows = false
	luz.Enabled = false
	luz.Parent = anexo
	faisca:GetPropertyChangedSignal("Enabled"):Connect(function()
		luz.Enabled = faisca.Enabled -- estrelinhas ligadas = luz acesa
	end)

	local faisca = Instance.new("ParticleEmitter") -- faíscas laranja que pulam e caem rápido
	faisca.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	faisca.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 120, 30))
	faisca.LightEmission = 1
	faisca.LightInfluence = 0
	faisca.Size = NumberSequence.new(0.25, 0)
	faisca.Lifetime = NumberRange.new(0.15, 0.35)
	faisca.Rate = 70
	faisca.Speed = NumberRange.new(8, 16)
	faisca.SpreadAngle = Vector2.new(60, 60)
	faisca.Acceleration = Vector3.new(0, -60, 0)
	faisca.EmissionDirection = Enum.NormalId.Top
	faisca.Enabled = false
	faisca.Parent = anexo
	return fumaca, faisca
end

-- Chamado uma vez para cada quadriciclo que aparece no seu jogo.
function FreioDeMao.criarEfeitos(quad: Quadriciclo)
	local Config = quad.Config
	local fumacasFreio: { ParticleEmitter } = {}
	local faiscasFreio: { ParticleEmitter } = {}
	local somDerrapagem = Veiculo.criarSom(quad, "SomDerrapagem", Config.FreioDeMaoSomId, true)
	local derrapagemVisivel = false

	-- Cria os efeitos em todas as rodas (para todo mundo, não só para quem dirige).
	local baixo = -Veiculo.referencia(quad).UpVector
	for _, pasta in quad.pastaRodas:GetChildren() do
		local manga = pasta:FindFirstChild("Manga")
		local roda = pasta:FindFirstChild("Roda")
		if manga and manga:IsA("BasePart") and roda and roda:IsA("BasePart") then
			local fumaca, faisca = criarEfeitosDaRoda(quad, manga, roda, baixo)
			table.insert(fumacasFreio, fumaca)
			table.insert(faiscasFreio, faisca)
		end
	end

	-- volume: só quem dirige manda (mais rápido = mais alto).
	quad.mostrarDerrapagem = function(ligado: boolean, volume: number?)
		if volume then
			somDerrapagem.Volume = volume
		end
		if ligado == derrapagemVisivel then
			return
		end
		derrapagemVisivel = ligado
		for _, fumaca in fumacasFreio do
			fumaca.Enabled = ligado and Config.FreioDeMaoEfeitos
		end
		for _, faisca in faiscasFreio do
			faisca.Enabled = ligado and Config.FreioDeMaoEfeitos
		end
		if ligado then
			somDerrapagem:Play()
		else
			somDerrapagem:Stop()
		end
	end

	-- Os OUTROS jogadores seguem o que o Servidor marcou no modelo (igual ao nitro e à buzina).
	local function aoMudarAtributo()
		if not quad.dirigindo then
			quad.mostrarDerrapagem(quad.modelo:GetAttribute("Derrapando") == true)
		end
	end
	Veiculo.guardarConexao(quad, quad.modelo:GetAttributeChangedSignal("Derrapando"):Connect(aoMudarAtributo))
	aoMudarAtributo() -- quem chega no meio de uma derrapada já vê
end

-- =====================================================================
-- QUEM DIRIGE
-- =====================================================================
-- (NOVO) FREIO DE MÃO DINÂMICO: o atrito das rodas TRAVADAS depende da velocidade.
--   Devagar ........ Config.FreioDeMaoAtrito (agarra e para).
--   Muito rápido ... Config.FreioDeMaoAtritoRapido (escorrega longe), a partir de
--                    Config.FreioDeMaoVelocidadeRapida. No meio do caminho, o atrito muda aos poucos.
--   Conforme o quadriciclo perde velocidade, o atrito sobe sozinho e ele termina de parar.
-- Muito rápido, as rodas SOLTAS (a frente, com HandbrakeRearOnly) também perdem um pouco de
-- aderência (Config.FreioDeMaoAderenciaFrente): o quadriciclo desliza inteiro em vez de rodar de
-- repente e capotar. Toda mudança de atrito é SUAVE: sem tranco ao puxar nem ao soltar o freio.
local SUAVIDADE_PUXAR = 15 -- rapidez com que o atrito CAI quando você puxa o freio (maior = mais rápido)
local SUAVIDADE_SOLTAR = 4 -- rapidez com que o atrito VOLTA quando você solta (devagar = sem tranco de lado)
local atritoTravadas = -1 -- o atrito de agora das rodas que o freio trava (-1 = ainda não começou)
local atritoSoltas = -1 -- o atrito de agora das rodas soltas
local relogioFreio = os.clock() -- para medir o tempo entre um frame e outro
local estacionado = false -- (NOVO) true = freio de ESTACIONAR (puxado devagar): 4 rodas travadas e atrito normal

-- Um número da Configuracao (ou o padrão, se a Configuracao ainda não tiver esse valor).
local function numeroDaConfig(valor: unknown, padrao: number): number
	return if typeof(valor) == "number" then valor else padrao
end

-- Leva o atrito de agora até o alvo aos poucos. Pertinho do alvo, encaixa nele.
local function aproximarAtrito(atual: number, alvo: number, dt: number): number
	local rapidez = if alvo < atual then SUAVIDADE_PUXAR else SUAVIDADE_SOLTAR
	local novo = atual + (alvo - atual) * math.min(dt * rapidez, 1)
	return if math.abs(alvo - novo) < 0.01 then alvo else novo
end

-- Coloca o atrito nas rodas: "travadas" nas que o freio de mão trava, "soltas" nas outras.
local function aplicarAtrito(quad: Quadriciclo, travadas: number, soltas: number)
	local Config = quad.Config
	for _, info in quad.rodas do
		local trava = not Config.HandbrakeRearOnly or not info.dianteira -- o freio de mão trava esta roda?
		info.roda.CustomPhysicalProperties = PhysicalProperties.new(
			Config.TireDensity,
			if trava then travadas else soltas,
			Config.TireElasticity,
			Config.TireFrictionWeight,
			Config.TireElasticityWeight
		)
	end
end

-- (NOVO) Alguma roda está encostada no chão? (um raio para "baixo" do quadriciclo, saindo do meio de
-- cada roda.) Pendurado no gancho ou voando, nenhuma está: sem fumaça, sem faísca e sem som.
local function rodaNoChao(quad: Quadriciclo): boolean
	local filtro = RaycastParams.new()
	filtro.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar: { Instance } = { quad.modelo } -- não conta o próprio quadriciclo...
	local piloto = quad.assento.Occupant
	local personagem = if piloto then piloto.Parent else nil
	if personagem then
		table.insert(ignorar, personagem) -- ...nem quem está dirigindo
	end
	filtro.FilterDescendantsInstances = ignorar
	filtro.IgnoreWater = true
	local baixo = -Veiculo.referencia(quad).UpVector -- o "baixo" do quadriciclo (funciona em rampa)
	for _, info in quad.rodas do
		if workspace:Raycast(info.roda.Position, baixo * (info.raio + 0.75), filtro) then
			return true
		end
	end
	return false
end

-- (NOVO) GIRO MÁXIMO NA DERRAPADA: com o freio de mão, o quadriciclo não pode girar de lado mais rápido
-- que Config.FreioDeMaoGiroMaximo graus por segundo (na velocidade Config.FreioDeMaoVelocidadeRapida).
-- Na metade dessa velocidade, pode o dobro; devagar, fica praticamente livre. Só corta o EXCESSO.
-- (NOVO) ESTABILIZADOR DA DERRAPADA: com o freio de mão, o quadriciclo NÃO gira sozinho.
-- Sem virar, ele desliza RETO. Virando (A/D), ele gira para esse lado, no máximo Config.FreioDeMaoGiroMaximo
-- graus por segundo (na velocidade Config.FreioDeMaoVelocidadeRapida; mais devagar, pode girar mais).
-- Voltando da derrapada (soltou o freio), ele só corta o giro EXAGERADO.
local FORCA_ESTABILIZADOR = 8 -- quão rápido o giro é corrigido (maior = mais "no trilho")
local function estabilizarGiro(quad: Quadriciclo, velocidade: number, volante: number, derrapando: boolean, dt: number)
	local Config = quad.Config
	local rapida = math.max(numeroDaConfig(Config.FreioDeMaoVelocidadeRapida, 90), 1)
	local graus = numeroDaConfig(Config.FreioDeMaoGiroMaximo, 70)
	local limite = math.rad(graus) * rapida / math.max(velocidade, 1) -- (rad/s) mais rápido = gira menos
	local cima = Veiculo.referencia(quad).UpVector
	local giro = quad.chassi.AssemblyAngularVelocity:Dot(cima) -- quão rápido ele gira agora, em volta do "de pé"
	local novo = giro
	if derrapando then
		local alvo = -volante * limite -- D (volante positivo) gira para a direita · sem virar = 0 (reto)
		novo += (alvo - giro) * math.min(dt * FORCA_ESTABILIZADOR, 1)
	end
	novo = math.clamp(novo, -limite, limite) -- nunca passa do limite
	local mudar = novo - giro
	if math.abs(mudar) < 0.0001 then
		return
	end
	-- Muda o giro de todas as peças (Chassi, Mangas e Rodas) juntas: ele gira inteiro, como um bloco.
	local delta = cima * mudar
	local centro = quad.chassi.AssemblyCenterOfMass
	for _, parte in quad.pecasFisicas do
		parte.AssemblyAngularVelocity += delta
		parte.AssemblyLinearVelocity += delta:Cross(parte.AssemblyCenterOfMass - centro)
	end
end


-- Chamado a cada frame pelo "atualizar", logo depois de travar as rodas.
function FreioDeMao.atualizar(quad: Quadriciclo, volante: number?)
	local Config = quad.Config
	local agora = os.clock()
	local dt = math.min(agora - relogioFreio, 0.1)
	relogioFreio = agora
	local velocidade = quad.chassi.AssemblyLinearVelocity.Magnitude
	-- (NOVO) FREIO DE ESTACIONAR: puxou devagar (ou a derrapada já perdeu a velocidade)? Fica estacionado
	-- até você soltar o freio. A derrapada (atrito baixo) é só para quem puxa o freio andando rápido.
	-- (NOVO) De RÉ (indo para trás), o freio de mão sempre ESTACIONA: na ladeira, ele não escorrega.
	local paraFrente = quad.chassi.AssemblyLinearVelocity:Dot(Veiculo.referencia(quad).LookVector) -- (negativo = de ré)
	if not quad.freioDeMao then
		estacionado = false
	elseif velocidade < numeroDaConfig(Config.FreioDeMaoVelocidadeEstacionar, 6) or paraFrente < -1.5 then
		estacionado = true
	end
	local derrapando = quad.freioDeMao and not estacionado and velocidade > Veiculo.PARADO -- parado não escorrega

	-- 1) O ATRITO QUE A GENTE QUER AGORA: mais rápido = menos atrito = desliza mais longe.
	local normal = Config.TireFriction
	local alvoTravadas, alvoSoltas = normal, normal
	if derrapando then
		local rapidaDemais = math.max(numeroDaConfig(Config.FreioDeMaoVelocidadeRapida, 90), 1)
		local fracao = math.clamp(velocidade / rapidaDemais, 0, 1) -- 0 = quase parado · 1 = muito rápido
		local devagar = numeroDaConfig(Config.FreioDeMaoAtrito, 0.35)
		local rapido = numeroDaConfig(Config.FreioDeMaoAtritoRapido, 0.08)
		alvoTravadas = devagar + (rapido - devagar) * fracao
		alvoTravadas *= numeroDaConfig(Config.FreioDeMaoEscorregar, 0.6) -- (NOVO) menos atrito = desliza mais e demora a parar
		-- (NOVO) Na LADEIRA, a derrapada precisa de atrito para frear (senão desce acelerando).
		-- Quanto mais inclinada a rampa, mais atrito (no máximo, o normal).
		local cima = Veiculo.referencia(quad).UpVector
		local y = math.max(cima.Y, 0.2)
		local rampa = math.sqrt(math.max(1 - y * y, 0)) / y -- 0 = chão plano · 1 = rampa de 45°
		local precisa = rampa * (if Config.HandbrakeRearOnly then 2.5 else 1.3) -- (só as de trás travam = precisa de mais)
		alvoTravadas = math.max(alvoTravadas, math.min(precisa, normal))
		local aderencia = numeroDaConfig(Config.FreioDeMaoAderenciaFrente, 1)
		alvoSoltas = normal * (1 + (aderencia - 1) * fracao)
	end

	-- 2) MUDA AOS POUCOS: cai rápido quando você puxa e volta devagar quando você solta.
	if atritoTravadas < 0 then
		atritoTravadas, atritoSoltas = normal, normal -- primeira vez: começa do normal
	end
	local novoTravadas = aproximarAtrito(atritoTravadas, alvoTravadas, dt)
	local novoSoltas = aproximarAtrito(atritoSoltas, alvoSoltas, dt)
	if novoTravadas ~= atritoTravadas or novoSoltas ~= atritoSoltas then
		atritoTravadas, atritoSoltas = novoTravadas, novoSoltas
		aplicarAtrito(quad, novoTravadas, novoSoltas) -- (só mexe nas rodas quando o atrito muda)
	end

	-- 2b) (NOVO) Derrapando: não gira sozinho (só para onde você virar). Voltando da derrapada: sem giro exagerado.
	if derrapando or atritoTravadas < normal - 0.01 then
		estabilizarGiro(quad, velocidade, volante or 0, derrapando, dt)
	end

	-- 2c) (NOVO) FREIO DE ESTACIONAR: atrito normal na hora e as 4 rodas travadas com força.
	if estacionado then
		if atritoTravadas ~= normal or atritoSoltas ~= normal then
			atritoTravadas, atritoSoltas = normal, normal
			aplicarAtrito(quad, normal, normal)
		end
		for _, info in quad.rodas do
			info.motor.AngularVelocity = 0 -- roda parada...
			info.motor.MotorMaxTorque = Config.MaxTorque * Config.HandbrakeTorqueMultiplier -- ...com força
		end
	end
	-- 3) FUMAÇA, FAÍSCAS E SOM: só derrapando DE VERDADE, com alguma roda no chão.
	local efeitos = derrapando and rodaNoChao(quad)
	quad.mostrarDerrapagem(efeitos, math.clamp(velocidade / 25, 0.35, 1)) -- você vê e ouve na hora...
	if efeitos ~= derrapandoAvisado then
		derrapandoAvisado = efeitos
		Veiculo.avisarServidor(quad, "Derrapando", efeitos) -- ...e os outros jogadores logo depois
	end
end

-- Sentou: liga a tecla do freio de mão.
function FreioDeMao.ligar(quad: Quadriciclo)
	ContextActionService:BindActionAtPriority(ACAO_FREIO_DE_MAO, function(_nomeAcao: string, estado: Enum.UserInputState, _entrada: InputObject): Enum.ContextActionResult?
		quad.freioDeMao = Veiculo.segurando(estado)
		return Enum.ContextActionResult.Sink
	end, true, Veiculo.PRIORIDADE, Enum.KeyCode.Space, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(ACAO_FREIO_DE_MAO, "F. MÃO")
end

-- Levantou: tudo volta ao normal.
-- Levantou: tudo volta ao normal.
function FreioDeMao.desligar(quad: Quadriciclo)
	ContextActionService:UnbindAction(ACAO_FREIO_DE_MAO)
	quad.freioDeMao = false
	aplicarAtrito(quad, quad.Config.TireFriction, quad.Config.TireFriction) -- (NOVO) todas as rodas com o atrito normal
	atritoTravadas, atritoSoltas = -1, -1 -- (o próximo quadriciclo começa do normal dele)
	quad.mostrarDerrapagem(false)
	if derrapandoAvisado then
		derrapandoAvisado = false
		Veiculo.avisarServidor(quad, "Derrapando", false)
	end
end

return FreioDeMao


