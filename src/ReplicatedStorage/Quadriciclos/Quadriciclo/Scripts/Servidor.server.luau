--!strict
--[[
	=====================================================================
	Servidor  (Script normal: RunContext = Legacy, que é o padrão)
	Local: Quadriciclo > Scripts > Servidor
	=====================================================================

	Este script roda UMA vez no servidor quando o jogo começa e faz:
	  1. Encontra as peças do quadriciclo e confere se estão montadas certo.
	  2. Aplica os valores da Configuracao nas molas, motores e direção.
	  3. Aplica massa e atrito (CustomPhysicalProperties) nas peças físicas.
	  4. Cria os Collision Groups (as rodas não colidem com o chassi).
	  5. Garante que as malhas visuais não têm massa nem colisão.
	  6. Modo Debug: pinta as peças invisíveis de neon e imprime um relatório.
	  7. Quando alguém senta no banco, passa a física (Network Ownership)
	     para esse jogador. Quando ele levanta, devolve para o servidor.

	Quem ACELERA e VIRA é o script "Cliente", no computador do jogador.
]]

-- =====================================================================
-- SERVIÇOS (as "ferramentas" do Roblox que vamos usar)
-- =====================================================================
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

-- =====================================================================
-- REFERÊNCIAS: onde estão as coisas dentro do modelo
-- =====================================================================
local Config = require(script.Parent:WaitForChild("Configuracao")) -- os valores de ajuste
local pastaScripts = script.Parent :: Instance -- a pasta "Scripts"
local modelo = pastaScripts.Parent :: Model -- o Model "Quadriciclo"

-- Nomes dos Collision Groups (grupos de colisão).
local GRUPO_CHASSI = "QuadricicloChassi"
local GRUPO_RODAS = "QuadricicloRodas"
local GRUPO_PILOTO = "QuadricicloPiloto"

-- Cores usadas no modo debug para cada tipo de peça física.
local COR_DEBUG_CHASSI = Color3.fromRGB(0, 170, 255) -- azul
local COR_DEBUG_BANCO = Color3.fromRGB(0, 255, 120) -- verde
local COR_DEBUG_MANGA = Color3.fromRGB(255, 200, 0) -- amarelo
local COR_DEBUG_RODA = Color3.fromRGB(255, 60, 60) -- vermelho

-- =====================================================================
-- FUNÇÕES DE AJUDA
-- =====================================================================

-- Lista o que existe dentro de uma pasta, com os nomes entre aspas.
-- Ajuda a achar erro de digitação (espaço sobrando, acento, letra maiúscula).
local function listarFilhos(pai: Instance): string
	local nomes: { string } = {}
	for _, filho in pai:GetChildren() do
		table.insert(nomes, `"{filho.Name}" ({filho.ClassName})`)
	end
	return if #nomes > 0 then table.concat(nomes, ", ") else "nada"
end

-- Letras com acento e a mesma letra sem acento (usada só para COMPARAR nomes).
local SEM_ACENTO: { [string]: string } = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["é"] = "e", ["ê"] = "e",
	["í"] = "i", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ú"] = "u", ["ç"] = "c",
	["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["É"] = "e", ["Ê"] = "e",
	["Í"] = "i", ["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ú"] = "u", ["Ç"] = "c",
}

-- "Simplifica" um nome: sem espaços, sem acentos e tudo minúsculo.
-- Assim "Suspensão ", "suspensao" e "Suspensao" ficam iguais na comparação.
local function simplificar(nome: string): string
	local texto = string.gsub(nome, "%s", "") -- tira os espaços (inclusive o invisível do final)
	for comAcento, semAcento in SEM_ACENTO do
		texto = string.gsub(texto, comAcento, semAcento) -- "ã" vira "a", "ç" vira "c"...
	end
	return string.lower(texto) -- "Manga" vira "manga"
end

-- Quando um item não é encontrado, descobre o motivo e explica em português.
local function explicarFalta(pai: Instance, nome: string, classe: string): string
	-- 1) Existe algo com o nome QUASE igual? (espaço sobrando, acento, maiúscula)
	for _, filho in pai:GetChildren() do
		if simplificar(filho.Name) == simplificar(nome) then
			return `Achei "{filho.Name}", que é quase igual: renomeie para "{nome}" (sem espaço, sem acento e com a mesma maiúscula).`
		end
	end
	-- 2) O item existe, mas ficou DENTRO de outra peça em vez de direto na pasta?
	for _, descendente in pai:GetDescendants() do
		local paiDele = descendente.Parent
		if descendente.Name == nome and descendente:IsA(classe) and paiDele ~= nil and paiDele ~= pai then
			return `Achei "{nome}" dentro de "{paiDele.Name}": arraste-o no Explorer para ficar direto dentro de "{pai.Name}".`
		end
	end
	-- 3) Não achei nada parecido: mostramos tudo que existe lá.
	return `O que tem lá: {listarFilhos(pai)}.`
end

-- Procura um filho pelo nome e confere a classe dele.
-- Se algo estiver errado, para o script com uma mensagem clara no Output.
local function buscar(pai: Instance, nome: string, classe: string): Instance
	local objeto = pai:FindFirstChild(nome)
	if objeto ~= nil and objeto:IsA(classe) then
		return objeto
	end
	if objeto == nil then
		error(`[Quadriciclo] Não encontrei "{nome}" dentro de "{pai:GetFullName()}". {explicarFalta(pai, nome, classe)}`, 0)
	end
	error(`[Quadriciclo] "{objeto:GetFullName()}" deveria ser um {classe}, mas é um {objeto.ClassName}.`, 0)
end

-- Imprime só quando o DEBUG_MODE está ligado.
local function debugPrint(mensagem: string)
	if Config.DEBUG_MODE then
		print("[Quadriciclo] " .. mensagem)
	end
end

-- =====================================================================
-- 1) ENCONTRAR AS PEÇAS
-- =====================================================================
local chassi = buscar(modelo, "Chassi", "BasePart") :: BasePart
local assento = buscar(modelo, "Banco", "VehicleSeat") :: VehicleSeat
local pastaRodas = buscar(modelo, "Rodas", "Folder")
local pastaVisual = modelo:FindFirstChild("Visual") -- opcional (pode não existir)

-- Tudo que o servidor precisa saber sobre cada roda.
type InfoRoda = {
	nome: string,
	manga: BasePart, -- peça entre a mola e a roda (sobe, desce e, na frente, vira)
	roda: BasePart, -- cilindro invisível que encosta no chão
	suspensao: SlidingBallConstraint, -- CylindricalConstraint (frente) ou PrismaticConstraint (trás)
	mola: SpringConstraint,
	motor: HingeConstraint,
}

local rodas: { InfoRoda } = {}
local problemasDeMontagem: { string } = {}

-- Confere um item dentro da pasta de uma roda. Se faltar ou estiver errado,
-- anota o problema (para mostrar TODOS de uma vez no final) e devolve nil.
local function itemDaRoda(pasta: Instance, nome: string, classe: string, descricao: string): Instance?
	local objeto = pasta:FindFirstChild(nome)
	if objeto == nil then
		table.insert(problemasDeMontagem, `• {pasta.Name}: falta "{nome}" ({descricao}). {explicarFalta(pasta, nome, classe)}`)
		return nil
	end
	if not objeto:IsA(classe) then
		table.insert(
			problemasDeMontagem,
			`• {pasta.Name}: "{nome}" deveria ser {descricao}, mas é {objeto.ClassName}. Apague e crie de novo pelo + da pasta.`
		)
		return nil
	end
	return objeto
end

for _, pasta in pastaRodas:GetChildren() do
	-- Cada roda fica numa pasta própria (ex.: "DianteiraEsquerda").
	if not (pasta:IsA("Folder") or pasta:IsA("Model")) then
		continue
	end
	local manga = itemDaRoda(pasta, "Manga", "BasePart", "Part")
	local roda = itemDaRoda(pasta, "Roda", "BasePart", "Part cilindro")
	-- "SlidingBallConstraint" é a classe-mãe da Cylindrical e da Prismatic: assim aceitamos as duas.
	local suspensao = itemDaRoda(pasta, "Suspensao", "SlidingBallConstraint", "CylindricalConstraint ou PrismaticConstraint")
	local mola = itemDaRoda(pasta, "Mola", "SpringConstraint", "SpringConstraint")
	local motor = itemDaRoda(pasta, "Motor", "HingeConstraint", "HingeConstraint")
	if manga and roda and suspensao and mola and motor then
		local info: InfoRoda = {
			nome = pasta.Name,
			manga = manga :: BasePart,
			roda = roda :: BasePart,
			suspensao = suspensao :: SlidingBallConstraint,
			mola = mola :: SpringConstraint,
			motor = motor :: HingeConstraint,
		}
		table.insert(rodas, info)
	end
end

-- Mostra todos os problemas de uma vez: assim você corrige tudo numa rodada só.
if #problemasDeMontagem > 0 then
	error(
		"[Quadriciclo] Encontrei problemas nas pastas das rodas:\n"
			.. table.concat(problemasDeMontagem, "\n")
			.. "\nDica: os nomes precisam ser idênticos (maiúsculas, acentos e espaços contam)"
			.. " e os 5 itens ficam DIRETO dentro da pasta da roda, não dentro de outra peça.",
		0
	)
end

if #rodas == 0 then
	error("[Quadriciclo] A pasta Rodas está vazia. Cada roda precisa de uma pasta com Manga, Roda, Suspensao, Mola e Motor.", 0)
end

-- Lista de todas as peças físicas (usada várias vezes abaixo).
local pecasFisicas: { BasePart } = { chassi, assento }
for _, info in rodas do
	table.insert(pecasFisicas, info.manga)
	table.insert(pecasFisicas, info.roda)
end

-- =====================================================================
-- 2) CONFERIR A MONTAGEM (ajuda muito quando você monta à mão)
-- =====================================================================
local problemasDeLigacao: { string } = {}

-- Mostra onde um Attachment está, no formato "Peça › Attachment".
local function ondeEsta(anexo: Attachment): string
	local peca = anexo.Parent
	return if peca then `{peca.Name} › {anexo.Name}` else anexo.Name
end

-- Orientation de um Attachment em texto, arredondada (ex.: "0, 180, 0").
local function orientacaoEmTexto(anexo: Attachment): string
	local o = anexo.Orientation
	return string.format("%d, %d, %d", math.round(o.X), math.round(o.Y), math.round(o.Z))
end

-- Confere se uma constraint liga as DUAS peças certas.
-- Exemplo: o Motor precisa ligar um Attachment da Manga com um Attachment da Roda.
-- Devolve true quando está tudo certo (e anota o problema quando não está).
local function conferirLigacao(
	info: InfoRoda,
	constraint: Constraint,
	pecaA: BasePart,
	pecaB: BasePart,
	comoDeveSer: string
): boolean
	local anexo0 = constraint.Attachment0
	local anexo1 = constraint.Attachment1
	if anexo0 == nil or anexo1 == nil then
		table.insert(problemasDeLigacao, `• {info.nome} › {constraint.Name}: falta preencher o Attachment0 ou o Attachment1. O certo é {comoDeveSer}.`)
		return false
	end
	-- Tanto faz a ordem: A0 na peça A e A1 na peça B, ou o contrário.
	local peca0 = anexo0.Parent
	local peca1 = anexo1.Parent
	local pecasCertas = (peca0 == pecaA and peca1 == pecaB) or (peca0 == pecaB and peca1 == pecaA)
	if not pecasCertas then
		table.insert(
			problemasDeLigacao,
			`• {info.nome} › {constraint.Name}: está ligando "{ondeEsta(anexo0)}" com "{ondeEsta(anexo1)}". O certo é {comoDeveSer}.`
		)
		return false
	end
	return true
end

local function conferirMontagem()
	-- Peça ancorada não se mexe: desancoramos e avisamos.
	for _, parte in pecasFisicas do
		if parte.Anchored then
			parte.Anchored = false
			warn(`[Quadriciclo] "{parte:GetFullName()}" estava Anchored. Desancorei para ele poder andar.`)
		end
	end

	-- O Banco precisa estar soldado no Chassi (WeldConstraint).
	if #assento:GetJoints() == 0 then
		warn("[Quadriciclo] O Banco não está soldado em nada. Crie um WeldConstraint com Part0 = Banco e Part1 = Chassi.")
	end

	-- Direções de referência do veículo (o Banco aponta para a frente).
	local cima = assento.CFrame.UpVector
	local direita = assento.CFrame.RightVector

	for _, info in rodas do
		-- a) Cada constraint liga as peças certas? (erro mais comum de quem monta à mão)
		local suspensaoOk = conferirLigacao(
			info,
			info.suspensao,
			chassi,
			info.manga,
			`Attachment0 = Chassi › Suspensao_{info.nome} e Attachment1 = Manga › Suspensao`
		)
		local molaOk = conferirLigacao(
			info,
			info.mola,
			chassi,
			info.manga,
			`Attachment0 = Chassi › Mola_{info.nome} e Attachment1 = Manga › Mola`
		)
		local motorOk = conferirLigacao(info, info.motor, info.manga, info.roda, "Attachment0 = Manga › Eixo e Attachment1 = Roda › Eixo")

		-- b) SUSPENSAO: os dois Attachments precisam ter a MESMA orientação
		--    e ficar na mesma "linha" do trilho (um exatamente em cima do outro).
		if suspensaoOk then
			local anexo0 = info.suspensao.Attachment0 :: Attachment
			local anexo1 = info.suspensao.Attachment1 :: Attachment
			local mesmaOrientacao = anexo0.WorldAxis:Dot(anexo1.WorldAxis) > 0.99
				and anexo0.WorldSecondaryAxis:Dot(anexo1.WorldSecondaryAxis) > 0.99
			if not mesmaOrientacao then
				table.insert(
					problemasDeLigacao,
					`• {info.nome} › Suspensao: os dois Attachments estão com Orientation diferente `
						.. `("{ondeEsta(anexo0)}" = {orientacaoEmTexto(anexo0)}, "{ondeEsta(anexo1)}" = {orientacaoEmTexto(anexo1)}). `
						.. "Os dois precisam ser 0, 0, -90 (e a Manga com Orientation 0, 0, 0)."
				)
			end
			local eixo = anexo0.WorldAxis
			local diferenca = anexo1.WorldPosition - anexo0.WorldPosition
			local desvioDeLado = (diferenca - eixo * diferenca:Dot(eixo)).Magnitude -- quanto um está "ao lado" do outro
			if desvioDeLado > 0.3 then
				table.insert(
					problemasDeLigacao,
					`• {info.nome} › Suspensao: os dois Attachments estão desalinhados ({string.format("%.2f", desvioDeLado)} studs de lado). `
						.. `Confira se o Attachment0 é o Suspensao_{info.nome} (o desta roda) e as Positions da tabela do Passo 2.`
				)
			end
			-- O trilho precisa apontar o eixo X para cima ou para baixo.
			if math.abs(eixo:Dot(cima)) < 0.9 then
				warn(`[Quadriciclo] {info.nome}: o eixo X (seta amarela) dos Attachments da Suspensao deveria apontar para BAIXO. Use Orientation = (0, 0, -90).`)
			end
		end

		-- c) MOTOR: os dois Eixos precisam estar no mesmo lugar e apontar para o mesmo lado.
		if motorOk then
			local anexo0 = info.motor.Attachment0 :: Attachment
			local anexo1 = info.motor.Attachment1 :: Attachment
			local distancia = (anexo1.WorldPosition - anexo0.WorldPosition).Magnitude
			if distancia > 0.3 then
				table.insert(
					problemasDeLigacao,
					`• {info.nome} › Motor: o Eixo da Manga e o Eixo da Roda estão {string.format("%.2f", distancia)} studs longe um do outro. `
						.. "A Manga e a Roda precisam ter a mesma Position (tabela do Passo 1) e os dois Eixos Position = 0, 0, 0."
				)
			end
			if anexo0.WorldAxis:Dot(anexo1.WorldAxis) < 0.99 then
				table.insert(
					problemasDeLigacao,
					`• {info.nome} › Motor: os dois Eixos apontam para lados diferentes `
						.. `("{ondeEsta(anexo0)}" = {orientacaoEmTexto(anexo0)}, "{ondeEsta(anexo1)}" = {orientacaoEmTexto(anexo1)}). `
						.. "Os dois precisam ser 0, 180, 0 (e a Roda com Orientation 0, 0, 0)."
				)
			end
			-- O eixo do motor precisa apontar para a lateral (como o eixo de uma roda de verdade).
			if math.abs(anexo0.WorldAxis:Dot(direita)) < 0.9 then
				warn(`[Quadriciclo] {info.nome}: o eixo X dos Attachments do Motor deveria apontar para a LATERAL. Use Orientation = (0, 180, 0).`)
			end
		end

		-- d) MOLA: precisa começar dentro dos limites, senão o quadriciclo dá um tranco ao iniciar.
		if molaOk then
			local comprimento = info.mola.CurrentLength
			if comprimento < Config.SpringMinLength or comprimento > Config.SpringMaxLength then
				warn(
					`[Quadriciclo] {info.nome}: a Mola começa com {string.format("%.2f", comprimento)} studs, `
						.. `fora dos limites ({Config.SpringMinLength} a {Config.SpringMaxLength}). Confira a altura da Manga.`
				)
			end
		end
	end

	-- Mostra todos os problemas de uma vez e para o script (com eles o quadriciclo "explodiria").
	if #problemasDeLigacao > 0 then
		error(
			"[Quadriciclo] Encontrei problemas nos Attachments das constraints:\n"
				.. table.concat(problemasDeLigacao, "\n")
				.. "\nDica: clique na constraint, depois no campo Attachment0 (ou Attachment1) das Properties"
				.. " e escolha o Attachment certo no Explorer. As Positions e Orientations estão na tabela do Passo 2.",
			0
		)
	end
end

-- =====================================================================
-- 3) APLICAR A CONFIGURAÇÃO NAS CONSTRAINTS
-- =====================================================================

-- BATENTE NO TRILHO. O limite da mola (MinLength) mede só a DISTÂNCIA entre os
-- Attachments. Numa pancada forte (morro íngreme, queda), a Manga pode passar do
-- batente, atravessar o Chassi (roda e chassi não colidem) e ficar presa do outro
-- lado, com a roda em cima do chassi. O limite do trilho tem SINAL: ele sabe o que é
-- "para cima" e "para baixo", então a roda nunca troca de lado.
-- Aqui convertemos o curso da mola (SpringMinLength a SpringMaxLength) em posições do trilho.
local function configurarBatente(info: InfoRoda)
	local suspensao = info.suspensao
	-- CurrentPosition = onde a Manga está ao longo do trilho, medido pelo próprio Roblox.
	local posicaoInicial = suspensao.CurrentPosition
	if math.abs(posicaoInicial) < 0.05 then
		task.wait() -- espera 1 frame para o Roblox medir o trilho e tenta de novo
		posicaoInicial = suspensao.CurrentPosition
	end
	if math.abs(posicaoInicial) < 0.05 then
		suspensao.LimitsEnabled = false
		warn(
			`[Quadriciclo] {info.nome}: não consegui medir a posição da Suspensao `
				.. "(a Manga está na mesma altura do Attachment do Chassi?). Fica só o batente da mola."
		)
		return
	end
	-- Ao dar Play, a Manga está ABAIXO do topo do trilho. Então o sinal da posição
	-- mostra para que lado do trilho a roda desce (e a mola estica): +1 ou -1.
	local sinal = if posicaoInicial > 0 then 1 else -1
	local comprimentoInicial = info.mola.CurrentLength
	-- Posição do trilho em que a mola chega em cada limite:
	local comprimida = posicaoInicial + sinal * (Config.SpringMinLength - comprimentoInicial)
	local esticada = posicaoInicial + sinal * (Config.SpringMaxLength - comprimentoInicial)
	local inferior = math.min(comprimida, esticada)
	local superior = math.max(comprimida, esticada)
	-- Mudamos na ordem certa para o LowerLimit nunca ficar maior que o UpperLimit no meio do caminho.
	if inferior > suspensao.UpperLimit then
		suspensao.UpperLimit = superior
		suspensao.LowerLimit = inferior
	else
		suspensao.LowerLimit = inferior
		suspensao.UpperLimit = superior
	end
	suspensao.Restitution = 0 -- batente "morto": não quica
	suspensao.LimitsEnabled = true
	debugPrint(`{info.nome}: batente no trilho de {string.format("%.2f", inferior)} a {string.format("%.2f", superior)}`)
end

local function configurarRoda(info: InfoRoda)
	-- ---------- MOLA (SpringConstraint) ----------
	local mola = info.mola
	mola.Stiffness = Config.SpringStiffness -- dureza
	mola.Damping = Config.SpringDamping -- amortecimento
	mola.FreeLength = Config.SpringFreeLength -- tamanho sem peso
	mola.LimitsEnabled = true -- batente reserva (o principal fica no trilho, logo abaixo)
	mola.MinLength = Config.SpringMinLength
	mola.MaxLength = Config.SpringMaxLength
	-- Aparência (a espiral amarela do vídeo):
	mola.Visible = Config.SpringVisible or Config.DEBUG_MODE
	mola.Color = Config.SpringColor
	mola.Coils = Config.SpringCoils
	mola.Radius = Config.SpringRadius
	mola.Thickness = Config.SpringThickness

	-- ---------- TRILHO DA SUSPENSÃO ----------
	-- Sobe e desce livre (quem segura o peso é a mola), com o batente no próprio trilho.
	local suspensao = info.suspensao
	suspensao.ActuatorType = Enum.ActuatorType.None
	configurarBatente(info)

	-- Na frente, a Suspensao é uma CylindricalConstraint: além de deslizar,
	-- ela GIRA em torno do mesmo eixo vertical. Esse giro é a direção!
	if suspensao:IsA("CylindricalConstraint") then
		suspensao.InclinationAngle = 0 -- 0 = gira em torno do mesmo eixo em que desliza
		suspensao.AngularActuatorType = Enum.ActuatorType.Servo -- servo = vai até um ângulo alvo
		suspensao.ServoMaxTorque = Config.SteerTorque
		suspensao.AngularSpeed = math.rad(Config.SteerSpeed) -- a propriedade usa radianos por segundo
		suspensao.AngularLimitsEnabled = true -- trava de segurança do volante
		suspensao.LowerAngle = -(Config.SteerAngle + 5)
		suspensao.UpperAngle = Config.SteerAngle + 5
		suspensao.TargetAngle = 0
	end

	-- ---------- MOTOR DA RODA (HingeConstraint) ----------
	local motor = info.motor
	motor.ActuatorType = Enum.ActuatorType.Motor
	motor.AngularVelocity = 0 -- parado
	motor.MotorMaxTorque = Config.MaxTorque -- parado + torque = "freio de mão"
	motor.MotorMaxAcceleration = math.huge -- sem limite: a rampa de aceleração é feita pelo Cliente
end

-- =====================================================================
-- 4) MASSA E ADERÊNCIA (CustomPhysicalProperties)
-- =====================================================================
-- PhysicalProperties.new(densidade, atrito, elasticidade, pesoDoAtrito, pesoDaElasticidade)
-- (NOVO) LASTRO: um peso invisível soldado no Chassi, lá embaixo, na altura dos eixos das rodas.
-- Uma parte do peso do Chassi (Config.LastroFracao) passa para ele: o peso TOTAL continua o mesmo
-- (as molas não afundam), mas o CENTRO DE MASSA desce. Centro de massa baixo = muito mais difícil de
-- capotar em curva rápida. Ele não colide com nada, então não raspa no chão nem atrapalha as rodas.
local function criarLastro()
	local fracao = math.clamp(Config.LastroFracao or 0, 0, 0.9)
	local antigo = modelo:FindFirstChild("Lastro")
	if antigo then
		antigo:Destroy() -- (um lastro que ficou salvo no modelo: o script cria um novo, do tamanho certo)
	end
	-- 1) O Chassi com o peso "cheio" de antes (para medir quanto ele pesa).
	chassi.CustomPhysicalProperties = PhysicalProperties.new(Config.ChassisDensity, Config.ChassisFriction, 0, 1, 1)
	if fracao <= 0 then
		return -- LastroFracao = 0: sem lastro, tudo como antes
	end
	local massaDoLastro = chassi.Mass * fracao
	-- 2) O Chassi fica mais leve... e essa diferença de peso vai para o lastro.
	chassi.CustomPhysicalProperties = PhysicalProperties.new(Config.ChassisDensity * (1 - fracao), Config.ChassisFriction, 0, 1, 1)
	-- 3) A altura dos eixos: a média das Rodas, medida "em pé" (com a orientação do Banco).
	local referencia = CFrame.new(chassi.Position) * assento.CFrame.Rotation
	local alturaDosEixos = 0
	for _, info in rodas do
		alturaDosEixos += referencia:PointToObjectSpace(info.roda.Position).Y
	end
	-- (math.min com 0: o lastro nunca fica ACIMA do centro do Chassi, senão o centro de massa subiria)
	alturaDosEixos = math.min(alturaDosEixos / #rodas, 0) - (Config.LastroAbaixoDoEixo or 0)
	-- 4) O lastro: um cubinho bem denso (densidade 50), no meio do quadriciclo, na altura dos eixos.
	local lado = math.max((massaDoLastro / 50) ^ (1 / 3), 0.2)
	local lastro = Instance.new("Part")
	lastro.Name = "Lastro"
	lastro.Size = Vector3.new(lado, lado, lado)
	lastro.CustomPhysicalProperties = PhysicalProperties.new(math.min(massaDoLastro / lado ^ 3, 100), 0, 0, 1, 1)
	lastro.CFrame = referencia * CFrame.new(0, alturaDosEixos, 0)
	lastro.Anchored = false
	lastro.CanCollide = false -- não bate em nada (não raspa no chão)
	lastro.CanTouch = false
	lastro.CanQuery = false -- a mira do gancho e os raios atravessam
	lastro.Massless = false -- (o peso dele é justamente o que interessa)
	lastro.Material = Enum.Material.Neon
	lastro.Color = Color3.fromRGB(255, 0, 255) -- rosa (só aparece no DEBUG_MODE)
	lastro.Transparency = if Config.DEBUG_MODE then 0.3 else 1
	local solda = Instance.new("WeldConstraint")
	solda.Part0 = lastro
	solda.Part1 = chassi
	solda.Parent = lastro
	lastro.Parent = modelo
	debugPrint(`Lastro: {string.format("%.1f", massaDoLastro)} de massa, {string.format("%.2f", -alturaDosEixos)} studs abaixo do centro do Chassi`)
end

local function aplicarFisica()
	criarLastro() -- (NOVO) o Chassi fica mais leve e o peso que sobrou vai para o lastro, lá embaixo
	for _, info in rodas do
		info.manga.CustomPhysicalProperties = PhysicalProperties.new(Config.KnuckleDensity, 0.3, 0, 1, 1)
		info.roda.CustomPhysicalProperties = PhysicalProperties.new(
			Config.TireDensity,
			Config.TireFriction,
			Config.TireElasticity,
			Config.TireFrictionWeight,
			Config.TireElasticityWeight
		)
	end

	-- O Banco não deve mudar o centro de massa e não precisa colidir
	-- (para sentar basta "encostar": CanTouch continua ligado).
	assento.Massless = true
	assento.CanCollide = false
	assento.CanTouch = true
	assento.HeadsUpDisplay = false -- esconde o velocímetro antigo do VehicleSeat

	-- Mangas não precisam colidir com nada: são só "juntas" mecânicas.
	for _, info in rodas do
		info.manga.CanCollide = false
		info.manga.CanTouch = false
		info.manga.CanQuery = false
		info.roda.CanCollide = true -- a roda É o que encosta no chão
	end
	chassi.CanCollide = true -- o chassi bate em paredes e raspa em pedras
end

-- =====================================================================
-- 5) COLLISION GROUPS
-- =====================================================================
-- Rodas x Chassi = não colidem (senão uma empurra a outra e tudo treme).
-- Rodas x Rodas = não colidem. Piloto x (Chassi e Rodas) = não colidem.
-- Todos continuam colidindo com o mundo (grupo "Default").
local function configurarCollisionGroups()
	local sucesso, mensagemErro = pcall(function()
		for _, nome in { GRUPO_CHASSI, GRUPO_RODAS, GRUPO_PILOTO } do
			if not PhysicsService:IsCollisionGroupRegistered(nome) then
				PhysicsService:RegisterCollisionGroup(nome)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(GRUPO_RODAS, GRUPO_CHASSI, false)
		PhysicsService:CollisionGroupSetCollidable(GRUPO_RODAS, GRUPO_RODAS, false)
		PhysicsService:CollisionGroupSetCollidable(GRUPO_PILOTO, GRUPO_CHASSI, false)
		PhysicsService:CollisionGroupSetCollidable(GRUPO_PILOTO, GRUPO_RODAS, false)
	end)
	if not sucesso then
		warn(`[Quadriciclo] Não consegui configurar os Collision Groups: {mensagemErro}`)
		return
	end

	chassi.CollisionGroup = GRUPO_CHASSI
	assento.CollisionGroup = GRUPO_CHASSI
	for _, info in rodas do
		info.manga.CollisionGroup = GRUPO_RODAS
		info.roda.CollisionGroup = GRUPO_RODAS
	end
end

-- =====================================================================
-- 6) MALHAS VISUAIS: sem massa, sem colisão, sempre soldadas
-- =====================================================================

-- A Roda física GIRA, e tudo que está soldado nela gira junto, em volta do eixo dela.
-- Um pneu bem no centro da Roda parece só rolar; fora do centro, ele dá voltas em volta
-- da roda. Isso acontece quando o pneu foi soldado na Roda errada (as 4 se chamam "Roda")
-- ou quando a Position dele é diferente da Position da Roda.
local function conferirPecaDaRoda(objeto: BasePart)
	for _, info in rodas do
		-- Peças soldadas entre si formam um "conjunto" (assembly) com a mesma peça-raiz.
		-- Mesma raiz da Roda = a peça está soldada nesta roda (direto ou por outra malha).
		if objeto.AssemblyRootPart ~= info.roda.AssemblyRootPart then
			continue
		end
		-- O eixo da roda passa pelo Attachment do Motor que fica dentro da Roda.
		local anexo0 = info.motor.Attachment0 :: Attachment
		local anexo1 = info.motor.Attachment1 :: Attachment
		local eixo = if anexo0.Parent == info.roda then anexo0 else anexo1
		local diferenca = objeto.Position - eixo.WorldPosition
		local paraOLado = diferenca:Dot(eixo.WorldAxis) -- ao longo do eixo (pneu largo, calota)
		local foraDoEixo = (diferenca - eixo.WorldAxis * paraOLado).Magnitude -- para cima, baixo, frente ou trás
		if foraDoEixo > 0.3 or math.abs(paraOLado) > 1.5 then
			warn(
				`[Quadriciclo] A peça "{objeto.Name}" está soldada na Roda de {info.nome}, mas fica a `
					.. `{string.format("%.1f", diferenca.Magnitude)} studs do centro dela, então gira junto com essa roda fora do lugar. `
					.. "Deixe a peça com a mesma Position da Roda certa e, na WeldConstraint dela, escolha de novo o Part1: Rodas › (pasta da roda) › Roda."
			)
		end
		return
	end
end

local function prepararVisual()
	if pastaVisual == nil then
		return
	end
	local corrigidas = 0
	for _, objeto in pastaVisual:GetDescendants() do
		if objeto:IsA("BasePart") then
			if not objeto.Massless or objeto.CanCollide then
				corrigidas += 1
			end
			objeto.Massless = true -- não pesa nada: não muda o centro de massa
			objeto.CanCollide = false -- não bate em nada: quem colide são as peças físicas
			objeto.CanTouch = false
			objeto.CanQuery = false
			objeto.Anchored = false
			if #objeto:GetJoints() == 0 then
				warn(`[Quadriciclo] A malha "{objeto:GetFullName()}" não está soldada em nada e vai cair! Crie um WeldConstraint ligando ela à peça física.`)
			end
		end
	end
	if corrigidas > 0 then
		debugPrint(`{corrigidas} peça(s) visual(is) estavam com massa ou colisão. Corrigi para Massless = true e CanCollide = false.`)
	end

	-- Peças soldadas numa Roda (pneu, calota...) precisam ficar em volta do centro dela.
	for _, objeto in pastaVisual:GetDescendants() do
		if objeto:IsA("BasePart") then
			conferirPecaDaRoda(objeto)
		end
	end
end

-- =====================================================================
-- 7) MODO DEBUG: pinta de neon e imprime um relatório
-- =====================================================================
local function pintarDebug(parte: BasePart, cor: Color3)
	parte.Material = Enum.Material.Neon
	parte.Color = cor
	parte.Transparency = 0.5 -- levemente transparente
	parte.CastShadow = false
end

local function ligarVisualDebug()
	pintarDebug(chassi, COR_DEBUG_CHASSI)
	pintarDebug(assento, COR_DEBUG_BANCO)
	for _, info in rodas do
		pintarDebug(info.manga, COR_DEBUG_MANGA)
		pintarDebug(info.roda, COR_DEBUG_RODA)
	end

	-- Malhas ficam quase transparentes para você enxergar as peças físicas por dentro.
	if pastaVisual then
		for _, objeto in pastaVisual:GetDescendants() do
			if objeto:IsA("BasePart") then
				objeto.Transparency = math.max(objeto.Transparency, 0.8)
			end
		end
	end

	-- Mostra constraints (molas, eixos, trilhos) e attachments.
	for _, objeto in modelo:GetDescendants() do
		if objeto:IsA("Constraint") then
			objeto.Visible = true
		elseif objeto:IsA("Attachment") then
			objeto.Visible = true
		end
		if objeto:IsA("CylindricalConstraint") then
			objeto.RotationAxisVisible = true -- mostra o eixo em que a roda da frente vira
		end
	end
end

local function imprimirRelatorio()
	local massaSuspensa = chassi.AssemblyMass -- Chassi + tudo que está soldado nele
	local massaTotal = massaSuspensa
	local rodasQueViram = 0
	for _, info in rodas do
		massaTotal += info.manga.AssemblyMass + info.roda.AssemblyMass
		if info.suspensao:IsA("CylindricalConstraint") then
			rodasQueViram += 1
		end
	end

	-- Quanto cada mola precisa segurar e qual será o tamanho dela parada:
	-- força = massa × gravidade  e  compressão = força / dureza.
	local pesoPorMola = massaSuspensa * workspace.Gravity / #rodas
	local comprimentoParado = Config.SpringFreeLength - pesoPorMola / Config.SpringStiffness

	print("[Quadriciclo] ========== RELATÓRIO DE MONTAGEM ==========")
	print(`[Quadriciclo] Rodas: {#rodas} ({rodasQueViram} com direção) | Tração: {Config.DriveMode}`)
	print(`[Quadriciclo] Massa total: {string.format("%.1f", massaTotal)} | Massa sobre as molas: {string.format("%.1f", massaSuspensa)}`)
	print(
		`[Quadriciclo] Mola parada: ~{string.format("%.2f", comprimentoParado)} studs `
			.. `(limites {Config.SpringMinLength} a {Config.SpringMaxLength})`
	)
	if comprimentoParado <= Config.SpringMinLength + 0.05 then
		warn("[Quadriciclo] As molas não aguentam o peso: o quadriciclo vai ficar apoiado no batente. Aumente SpringStiffness ou SpringFreeLength.")
	elseif comprimentoParado >= Config.SpringMaxLength then
		warn("[Quadriciclo] As molas estão fortes demais: a roda fica sempre esticada no limite. Diminua SpringStiffness ou SpringFreeLength.")
	end
end

-- =====================================================================
-- 8) BANCO E NETWORK OWNERSHIP (dono da física)
-- =====================================================================
-- Guardamos como o personagem era antes de sentar, para devolver igualzinho depois.
type EstadoOriginal = { massless: boolean, grupo: string }
local estadoDoPiloto: { [BasePart]: EstadoOriginal } = {}

local function definirDonoDaFisica(jogador: Player?)
	local podeMudar, motivo = chassi:CanSetNetworkOwnership()
	if not podeMudar then
		warn(`[Quadriciclo] Não dá para mudar o dono da física: {motivo}`)
		return
	end
	-- Basta chamar no Chassi: Mangas e Rodas estão ligadas a ele por constraints,
	-- formam um "mecanismo" e recebem o mesmo dono automaticamente.
	chassi:SetNetworkOwner(jogador)
	debugPrint(`Dono da física agora: {if jogador then jogador.Name else "SERVIDOR"}`)
end

local function prepararPiloto(personagem: Model)
	table.clear(estadoDoPiloto)
	for _, objeto in personagem:GetDescendants() do
		if objeto:IsA("BasePart") then
			estadoDoPiloto[objeto] = { massless = objeto.Massless, grupo = objeto.CollisionGroup }
			objeto.CollisionGroup = GRUPO_PILOTO -- pernas não enroscam nas rodas
			if Config.MasslessDriver then
				objeto.Massless = true -- o piloto não muda o centro de massa
			end
		end
	end
end

local function restaurarPiloto()
	for parte, estado in estadoDoPiloto do
		if parte.Parent ~= nil then -- o personagem pode ter sido destruído (morreu/saiu)
			parte.Massless = estado.massless
			parte.CollisionGroup = estado.grupo
		end
	end
	table.clear(estadoDoPiloto)
end

-- Deixa o quadriciclo "estacionado": rodas seguras e guidão reto.
local function estacionar()
	for _, info in rodas do
		info.motor.AngularVelocity = 0
		info.motor.MotorMaxTorque = Config.MaxTorque
		local suspensao = info.suspensao
		if suspensao:IsA("CylindricalConstraint") then
			suspensao.TargetAngle = 0
		end
	end
end

local function aoMudarOcupante()
	local humanoide = assento.Occupant
	if humanoide then
		-- Alguém sentou. É um jogador de verdade (e não um NPC)?
		local personagem = humanoide.Parent
		if personagem and personagem:IsA("Model") then
			local jogador = Players:GetPlayerFromCharacter(personagem)
			if jogador then
				prepararPiloto(personagem)
				-- OBRIGATÓRIO: a física passa a ser calculada no computador do jogador.
				-- Assim o controle responde na hora, sem esperar a internet.
				definirDonoDaFisica(jogador)
			end
		end
	else
		-- O motorista levantou (pulou, morreu ou saiu do jogo).
		restaurarPiloto()
		estacionar()
		-- Espera 1 frame: o Roblox ainda está desfazendo a solda do banco (SeatWeld).
		-- Se devolvêssemos a física antes, o personagem seria levado junto para o servidor.
		task.wait()
		if assento.Occupant == nil then
			definirDonoDaFisica(nil) -- nil = o SERVIDOR volta a ser o dono
		end
	end
end

-- =====================================================================
-- 9) AÇÕES DO MOTORISTA: buzina, nitro e sair do banco
-- =====================================================================
-- O Cliente pede pelo RemoteEvent; o servidor confere se quem pediu é mesmo o
-- motorista e marca um Attribute no modelo. Attributes chegam em TODOS os
-- jogadores: é assim que os outros ouvem a buzina e veem o fogo roxo.
local eventoAcao = Instance.new("RemoteEvent")
eventoAcao.Name = "AcaoQuadriciclo"
eventoAcao.Parent = pastaScripts

local function ehOMotorista(jogador: Player): boolean
	local humanoide = assento.Occupant
	return humanoide ~= nil and humanoide.Parent == jogador.Character
end

eventoAcao.OnServerEvent:Connect(function(jogador: Player, acao: unknown, ligado: unknown)
	-- Confere tudo: quem manda é o cliente, e um trapaceiro pode mandar qualquer coisa.
	if typeof(acao) ~= "string" or typeof(ligado) ~= "boolean" or not ehOMotorista(jogador) then
		return
	end
	if acao == "Buzina" or acao == "Nitro" then
		modelo:SetAttribute(acao, ligado)
	elseif acao == "Sair" then
		local solda = assento:FindFirstChild("SeatWeld") -- a solda que prende o jogador no banco
		if solda then
			solda:Destroy() -- sem ela, o jogador sai do banco
		end
	end
end)

-- Banco vazio (saiu, pulou, morreu): desliga a buzina e o nitro para todo mundo.
assento:GetPropertyChangedSignal("Occupant"):Connect(function()
	if assento.Occupant == nil then
		modelo:SetAttribute("Buzina", false)
		modelo:SetAttribute("Nitro", false)
	end
end)
-- =====================================================================
-- 10) GANCHO: voo, corda no cenário, puxão em personagens, botões e recarga
-- =====================================================================
-- O Cliente mira e manda "GanchoLiga" (alvo + ponto do impacto) ou "GanchoDesliga".
-- O servidor confere tudo, conta o voo do gancho, aplica o efeito e desfaz ao soltar.
-- O gancho girando e a corda são DESENHADOS em cada Cliente (fica liso para todo mundo),
-- a partir do que o servidor publica no modelo e no Player:
--   modelo: Attribute "GanchoEstado"     = "NoAr" (voando), "Preso" ou nil (nada)
--           ObjectValue "GanchoAlvo"     = Attachment onde o gancho vai prender
--   Player: Attribute "GanchoRecargaAte" = horário em que o gancho volta a funcionar
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local TAG_BOTAO_GANCHO = "BotaoGancho" -- tag (CollectionService) ou nome da peça
local NOME_CORDA_GANCHO = "CordaGancho" -- o Cliente procura este nome para acertar o tamanho da corda
local TEMPO_MAX_VOO = 3 -- (s) se o gancho não chegar nesse tempo, errou

-- Um BindableEvent só, para TODOS os quadriciclos: ServerStorage > BotaoGanchoAtivado.
-- Nas portas: evento.Event:Connect(function(botao, ligado, jogador) ... end)
local function pegarEventoDosBotoes(): BindableEvent
	local existente = ServerStorage:FindFirstChild("BotaoGanchoAtivado")
	if existente and existente:IsA("BindableEvent") then
		return existente
	end
	local novo = Instance.new("BindableEvent")
	novo.Name = "BotaoGanchoAtivado"
	novo.Parent = ServerStorage
	return novo
end
local eventoBotoesGancho = pegarEventoDosBotoes()

-- De onde a corda sai: um Attachment "SaidaGancho" seu (opcional) ou o centro do Chassi.
-- No centro, o quadriciclo fica nivelado quando está pendurado.
local achadoSaida = modelo:FindFirstChild("SaidaGancho", true)
local anexoGancho: Attachment = if achadoSaida and achadoSaida:IsA("Attachment")
	then achadoSaida
	else Instance.new("Attachment")
if anexoGancho.Parent == nil then
	anexoGancho.Name = "SaidaGancho"
	anexoGancho.Parent = chassi
end

-- Onde o gancho vai prender: os Clientes desenham o voo até este Attachment.
local alvoDoGancho = Instance.new("ObjectValue")
alvoDoGancho.Name = "GanchoAlvo"
alvoDoGancho.Parent = modelo

local pecasDoGancho: { Instance } = {} -- tudo que o gancho criou (some ao soltar)
local conexaoGancho: RBXScriptConnection? = nil -- laço do voo ou do puxão
local desfazerGancho: (() -> ())? = nil -- o que fazer ao soltar (ex.: botão volta a ficar vermelho)
local donoDoGancho: Player? = nil -- quem lançou o gancho que está voando ou preso agora
local tipoDoGancho = "Segurar" -- o TIPO do gancho que está voando ou preso agora (cada tipo tem a sua recarga)

-- Os tipos de gancho que existem (o Cliente manda qual o jogador escolheu na barra):
--   "Impulso" = só prende no CENÁRIO (o puxão, o pêndulo e o estilingue quem faz é o Cliente)
--   "Segurar" = prende no cenário (corda, escalada) OU prende outro jogador no lugar
--   "Botao"   = só aperta os BotaoGancho
local TIPOS_DE_GANCHO: { [string]: boolean } = { Impulso = true, Segurar = true, Botao = true }

-- Quantos segundos cada tipo recarrega depois de usar (os números ficam na Configuracao).
local function recargaDoTipo(tipo: string): number
	if tipo == "Impulso" then
		return Config.GanchoRecargaImpulso
	elseif tipo == "Botao" then
		return Config.GanchoRecargaBotao
	end
	return Config.GanchoRecargaSegurar
end

-- (NOVO) O alcance de cada tipo: o SEGURAR é mais curto (Config.GanchoAlcanceSegurar); o IMPULSO e o
-- BOTÃO usam o Config.GanchoAlcance.
local function alcanceDoTipo(tipo: string): number
	if tipo == "Segurar" and typeof(Config.GanchoAlcanceSegurar) == "number" then
		return Config.GanchoAlcanceSegurar
	end
	return Config.GanchoAlcance
end


local function guardarNoGancho(objeto: Instance)
	table.insert(pecasDoGancho, objeto)
end

local function soltarGancho()
	local conexao = conexaoGancho
	if conexao then
		conexao:Disconnect()
	end
	conexaoGancho = nil
	local desfazer = desfazerGancho
	desfazerGancho = nil
	if desfazer then
		desfazer()
	end
	for _, objeto in pecasDoGancho do
		objeto:Destroy()
	end
	table.clear(pecasDoGancho)
	local dono = donoDoGancho
	donoDoGancho = nil
	if dono then
		-- Usou o gancho: começa a RECARGA DESTE TIPO (cada tipo tem a sua). Fica no Player, então trocar
		-- de quadriciclo não zera. O nome junta o tipo: "GanchoRecargaAteImpulso", "GanchoRecargaAteSegurar"...
		dono:SetAttribute("GanchoRecargaAte" .. tipoDoGancho, workspace:GetServerTimeNow() + recargaDoTipo(tipoDoGancho))
	end
	alvoDoGancho.Value = nil
	modelo:SetAttribute("GanchoEstado", nil)
	modelo:SetAttribute("GanchoTipo", nil)
end

-- Attachment no ponto do impacto, "grudado" na peça atingida (anda junto se ela se mexer).
local function criarPontaGancho(parte: BasePart, ponto: Vector3): Attachment
	local ponta = Instance.new("Attachment")
	ponta.Name = "PontaGancho"
	ponta.Position = parte.CFrame:PointToObjectSpace(ponto)
	ponta.Parent = parte
	guardarNoGancho(ponta)
	return ponta
end

-- Sobe a partir da peça procurando quem está "dentro" dela: um Model com Humanoid (funciona até
-- acertando um chapéu) ou um VEÍCULO com alguém sentado (aí o alvo é quem está dirigindo).
local function humanoideDe(parte: Instance): Humanoid?
	local atual = parte.Parent
	while atual and atual ~= workspace do
		if atual:IsA("Model") then
			local humanoide = atual:FindFirstChildOfClass("Humanoid")
			if humanoide then
				return humanoide
			end
			local banco = atual:FindFirstChildWhichIsA("VehicleSeat")
			if banco and banco:IsA("VehicleSeat") and banco.Occupant then
				return banco.Occupant -- acertou outro quadriciclo: vale o motorista dele
			end
		end
		atual = atual.Parent
	end
	return nil
end

-- O ponto precisa estar NA peça (um trapaceiro poderia mandar um ponto no meio do céu).
local function pontoNaPeca(parte: BasePart, ponto: Vector3): boolean
	if parte:IsA("Terrain") then
		return true
	end
	local p = parte.CFrame:PointToObjectSpace(ponto)
	local limite = parte.Size / 2 + Vector3.one -- 1 stud de folga
	return math.abs(p.X) <= limite.X and math.abs(p.Y) <= limite.Y and math.abs(p.Z) <= limite.Z
end

-- Peça presa no mundo: Terrain, ancorada ou soldada em algo ancorado (parede, chão, poste).
local function pecaFixa(parte: BasePart): boolean
	if parte:IsA("Terrain") or parte.Anchored then
		return true
	end
	local raiz = parte.AssemblyRootPart -- pode ser nil
	return if raiz then raiz.Anchored else false
end

-- CENÁRIO: RopeConstraint do Chassi até a ponta, do tamanho da distância de AGORA.
-- Caindo, o quadriciclo fica pendurado (balança como pêndulo); no chão, não passa desse raio.
local function prenderNoCenario(ponta: Attachment)
	local corda = Instance.new("RopeConstraint")
	corda.Name = NOME_CORDA_GANCHO
	corda.Attachment0 = anexoGancho
	corda.Attachment1 = ponta
	corda.Length = math.max((ponta.WorldPosition - anexoGancho.WorldPosition).Magnitude, Config.GanchoComprimentoMinimo)
	corda.Restitution = 0 -- não quica quando estica
	-- (NOVO) A corda nasce DESLIGADA. Quem liga é o computador do motorista (módulo Gancho), já com o
	-- tamanho TRAVADO na distância exata do instante em que o gancho chegou. Assim ela nunca "estica"
	-- nem dá tranco por causa do atraso da internet.
	corda.Enabled = false
	corda.Visible = Config.DEBUG_MODE -- (a corda que todo mundo vê é desenhada pelos Clientes)
	corda.Parent = chassi
	guardarNoGancho(corda)
end

-- PERSONAGEM: AlignPosition no HumanoidRootPart, levando o alvo para perto do quadriciclo.
-- Modo OneAttachment = vai até um PONTO do mundo. Ligar o alvo direto no quadriciclo (dois
-- Attachments) juntaria as duas físicas, e um dos jogadores perderia o Network Ownership.
local function puxarPersonagem(humanoide: Humanoid, raiz: BasePart, ponta: Attachment)
	-- Sentado (em outro veículo)? Arranca do banco, senão puxaríamos o veículo inteiro.
	local banco = humanoide.SeatPart
	local solda = if banco then banco:FindFirstChild("SeatWeld") else nil
	if solda then
		solda:Destroy()
	end

	local puxao = Instance.new("AlignPosition")
	puxao.Name = "PuxaoGancho"
	puxao.Mode = Enum.PositionAlignmentMode.OneAttachment
	puxao.Attachment0 = ponta
	puxao.ApplyAtCenterOfMass = true -- puxa pelo centro: o boneco não sai girando
	puxao.MaxForce = Config.GanchoForcaPuxao
	puxao.MaxVelocity = Config.GanchoVelocidadePuxao
	puxao.Responsiveness = 30
	puxao.Position = raiz.Position
	puxao.Parent = raiz
	guardarNoGancho(puxao)
	-- Rede de segurança: o puxão some sozinho mesmo se este script parar (ex.: quadriciclo apagado).
	Debris:AddItem(puxao, Config.GanchoTempoMaxPuxao + 1)
	Debris:AddItem(ponta, Config.GanchoTempoMaxPuxao + 1)

	local inicio = os.clock()
	conexaoGancho = RunService.Heartbeat:Connect(function()
		if humanoide.Health <= 0 or not raiz:IsDescendantOf(workspace) or os.clock() - inicio > Config.GanchoTempoMaxPuxao then
			soltarGancho() -- morreu, sumiu ou passou do tempo máximo
			return
		end
		-- Destino: GanchoDistanciaParada studs do Chassi, do lado em que o personagem está.
		local daqui = raiz.Position - chassi.Position
		local lado = Vector3.new(daqui.X, 0, daqui.Z)
		lado = if lado.Magnitude > 0.1 then lado.Unit else assento.CFrame.LookVector
		puxao.Position = chassi.Position + lado * Config.GanchoDistanciaParada + Vector3.new(0, 2, 0)
	end)
end

-- BOTÃO: muda a cor, marca o Attribute "Ativado" e avisa pelo BindableEvent.
local function mudarBotaoGancho(botao: BasePart, ligado: boolean, jogador: Player)
	botao.Color = if ligado then Config.GanchoCorBotaoLigado else Config.GanchoCorBotaoDesligado
	botao:SetAttribute("Ativado", ligado)
	eventoBotoesGancho:Fire(botao, ligado, jogador)
end

local function acionarBotaoGancho(botao: BasePart, jogador: Player)
	mudarBotaoGancho(botao, true, jogador)
	if not Config.GanchoBotaoFicaLigado then
		desfazerGancho = function()
			mudarBotaoGancho(botao, false, jogador) -- soltou o gancho: volta a ficar vermelho
		end
	end
end

-- PRENDER NO LUGAR (gancho SEGURAR em outro jogador): ele fica parado onde estava por
-- Config.GanchoTempoSegurar segundos. Se ele estiver dirigindo, quem fica parado é o VEÍCULO dele
-- (ele continua sentado). Serve para atrapalhar um rival... e para AJUDAR um amigo que está caindo:
-- ele fica parado no ar e dá tempo de usar o próprio gancho.
-- (AlignPosition no modo OneAttachment = segura num PONTO do mundo, sem ligar os dois veículos.)
local function segurarPersonagem(humanoide: Humanoid, raiz: BasePart)
	-- O que vamos segurar: o veículo inteiro (se ele estiver sentado) ou o próprio personagem.
	local pecaSegura: BasePart = raiz
	local banco = humanoide.SeatPart
	if banco then
		pecaSegura = banco.AssemblyRootPart or banco -- a peça principal do veículo (no quadriciclo, o Chassi)
	end
	local anexo = Instance.new("Attachment")
	anexo.Name = "PrenderGancho"
	anexo.Parent = pecaSegura
	guardarNoGancho(anexo)

	local prender = Instance.new("AlignPosition")
	prender.Name = "PrenderGancho"
	prender.Mode = Enum.PositionAlignmentMode.OneAttachment
	prender.Attachment0 = anexo
	prender.ApplyAtCenterOfMass = true -- segura pelo centro: não sai girando
	prender.MaxForce = Config.GanchoForcaPuxao
	prender.Responsiveness = 60 -- bem "duro": quase não sai do lugar
	prender.Position = anexo.WorldPosition -- o lugar onde ele estava quando o gancho chegou
	prender.Parent = pecaSegura
	guardarNoGancho(prender)
	-- Rede de segurança: solta sozinho mesmo se este script parar (ex.: quadriciclo apagado).
	Debris:AddItem(prender, Config.GanchoTempoSegurar + 1)
	Debris:AddItem(anexo, Config.GanchoTempoSegurar + 1)

	local inicio = os.clock()
	conexaoGancho = RunService.Heartbeat:Connect(function()
		local longe = (raiz.Position - chassi.Position).Magnitude > alcanceDoTipo("Segurar") + 30
		if humanoide.Health <= 0 or not raiz:IsDescendantOf(workspace) or longe or os.clock() - inicio > Config.GanchoTempoSegurar then
			soltarGancho() -- morreu, sumiu, você foi para longe demais ou acabou o tempo
		end
	end)
end

-- O gancho VOA até o alvo e só prende quando chega. O servidor só conta a distância
-- percorrida; quem desenha o gancho girando e a corda rodando são os Clientes.
local function lancarGancho(jogador: Player, alvo: BasePart, ponto: Vector3, humanoide: Humanoid?, raiz: BasePart?, tipo: string)
	donoDoGancho = jogador
	tipoDoGancho = tipo
	modelo:SetAttribute("GanchoTipo", tipo) -- os Clientes desenham o gancho deste tipo (a mão, a cor da corda...)
	local ponta: Attachment
	if raiz then
		ponta = Instance.new("Attachment") -- personagem: a ponta fica no HumanoidRootPart (segue o boneco)
		ponta.Name = "PontaGancho"
		ponta.Parent = raiz
		guardarNoGancho(ponta)
	else
		ponta = criarPontaGancho(alvo, ponto)
	end
	alvoDoGancho.Value = ponta
	modelo:SetAttribute("GanchoEstado", "NoAr")

	local percorrido = 0
	local inicio = os.clock()
	conexaoGancho = RunService.Heartbeat:Connect(function(dt: number)
		if not ponta:IsDescendantOf(workspace) or (humanoide and humanoide.Health <= 0) or os.clock() - inicio > TEMPO_MAX_VOO then
			soltarGancho() -- o alvo sumiu, morreu ou o gancho demorou demais: errou
			return
		end
		percorrido += Config.GanchoVelocidadeVoo * dt
		if percorrido < (ponta.WorldPosition - anexoGancho.WorldPosition).Magnitude then
			return -- ainda voando
		end
		-- CHEGOU: aplica o efeito de verdade.
		local conexao = conexaoGancho
		if conexao then
			conexao:Disconnect()
		end
		conexaoGancho = nil
		if humanoide and raiz then
			if Config.GanchoSegurarJogador == "Puxar" then
				puxarPersonagem(humanoide, raiz, ponta) -- traz o jogador até você (o jeito antigo)
			else
				segurarPersonagem(humanoide, raiz) -- prende o jogador (ou o veículo dele) no lugar
			end
		elseif CollectionService:HasTag(alvo, TAG_BOTAO_GANCHO) or alvo.Name == TAG_BOTAO_GANCHO then
			acionarBotaoGancho(alvo, jogador)
		else
			prenderNoCenario(ponta)
		end
		modelo:SetAttribute("GanchoEstado", "Preso")
	end)
end

-- Segundo "ouvinte" do mesmo RemoteEvent. O de cima já ignora as ações do gancho sozinho
-- (ele só aceita "ligado" boolean), então não precisa mexer nele.
-- "GanchoLiga" chega com: alvo, ponto do impacto e o TIPO escolhido na barra.
eventoAcao.OnServerEvent:Connect(function(jogador: Player, acao: unknown, alvo: unknown, ponto: unknown, tipo: unknown)
	if acao == "GanchoDesliga" then
		if donoDoGancho == jogador then
			soltarGancho()
		end
		return
	end
	-- Confere tudo: quem manda é o cliente, e um trapaceiro pode mandar qualquer coisa.
	if acao ~= "GanchoLiga" or not ehOMotorista(jogador) or donoDoGancho ~= nil then
		return -- (donoDoGancho ~= nil: já tem um gancho voando ou preso)
	end
	if typeof(alvo) ~= "Instance" or typeof(ponto) ~= "Vector3" or typeof(tipo) ~= "string" or not TIPOS_DE_GANCHO[tipo] then
		return -- (tipo que não existe = ignorado)
	end
	if not alvo:IsA("BasePart") or not alvo:IsDescendantOf(workspace) or alvo:IsDescendantOf(modelo) then
		return
	end
	-- RECARGA DESTE TIPO: enquanto não passar o horário marcado no Player, este gancho não funciona.
	local recargaAte = jogador:GetAttribute("GanchoRecargaAte" .. tipo)
	if typeof(recargaAte) == "number" and recargaAte > workspace:GetServerTimeNow() then
		return
	end
	-- Alcance com folga: o servidor vê o quadriciclo um pouco atrasado (mais rápido = mais folga).
	local alcanceMaximo = alcanceDoTipo(tipo) + 15 + chassi.AssemblyLinearVelocity.Magnitude * 0.5 -- (o SEGURAR é mais curto)
	local humanoide = humanoideDe(alvo)
	local raiz = if humanoide then humanoide.RootPart else nil
	-- Personagem: mede até o boneco (ele se mexe). Outras peças: o ponto precisa estar nelas.
	local referencia = if raiz then raiz.Position else ponto
	if (referencia - chassi.Position).Magnitude > alcanceMaximo then
		return
	end
	local ehBotao = CollectionService:HasTag(alvo, TAG_BOTAO_GANCHO) or alvo.Name == TAG_BOTAO_GANCHO
	if humanoide then
		-- JOGADOR: só o gancho SEGURAR pega jogadores.
		if tipo ~= "Segurar" or raiz == nil or humanoide.Health <= 0 or humanoide.Parent == jogador.Character then
			return -- outro tipo, personagem sem HumanoidRootPart, morto, ou você mesmo
		end
	elseif not pontoNaPeca(alvo, ponto) then
		return
	elseif ehBotao then
		-- BOTÃO: só a mão (gancho BOTÃO) aperta botões.
		if tipo ~= "Botao" then
			return
		end
	elseif tipo == "Botao" or not pecaFixa(alvo) then
		return -- a mão só aperta botões; e peça SOLTA é ignorada (uma corda nela bagunçaria o Network Ownership)
	end
	lancarGancho(jogador, alvo, ponto, humanoide, raiz, tipo)
	debugPrint(`Gancho {tipo} de {jogador.Name} lançado em "{alvo:GetFullName()}"`)
end)

-- Solta o gancho quando o motorista sai do banco (pulou, morreu, apertou E) ou o quadriciclo some.
assento:GetPropertyChangedSignal("Occupant"):Connect(soltarGancho)
modelo.AncestryChanged:Connect(function()
	if not modelo:IsDescendantOf(workspace) then
		soltarGancho()
	end
end)

-- O motorista avisa quando começa e para de derrapar; o servidor marca no modelo e todo mundo
-- vê a fumaça e as faíscas e ouve o pneu (igual ao nitro e à buzina).
eventoAcao.OnServerEvent:Connect(function(jogador: Player, acao: unknown, ligado: unknown)
	if acao == "Derrapando" and typeof(ligado) == "boolean" and ehOMotorista(jogador) then
		modelo:SetAttribute("Derrapando", ligado)
	end
end)
assento:GetPropertyChangedSignal("Occupant"):Connect(function()
	if assento.Occupant == nil then
		modelo:SetAttribute("Derrapando", false)
	end
end)

-- =====================================================================
-- 11) PANCADA: este quadriciclo bateu MUITO rápido em OUTRO quadriciclo
-- =====================================================================
-- O Cliente de quem dirige ESTE quadriciclo avisa "Bater" + o quadriciclo atingido. A física de cada
-- quadriciclo é calculada no computador do SEU motorista, então a batida normal quase não mexe no outro.
-- Aqui o servidor confere tudo, calcula o TRANCO (empurrão, pulinho e giro) e manda o computador de
-- quem dirige o outro aplicar ("Pancada", pelo RemoteEvent do quadriciclo DELE).
local DISTANCIA_PANCADA = 30 -- (studs) folga: o servidor vê os dois quadriciclos um pouco atrasados
local ESPERA_PANCADA = 1 -- (s) o mesmo quadriciclo só leva outra pancada deste depois disso
local ultimaPancada: { [Model]: number } = {}

-- A maior velocidade dos últimos instantes (ela vai caindo devagar). Quando o aviso "Bater" chega, a
-- batida já pode ter freado este quadriciclo: vale a velocidade de logo antes dela.
local rapidezRecente = 0
local velocidadeRecente = Vector3.zero
RunService.Heartbeat:Connect(function(dt: number)
	local agora = chassi.AssemblyLinearVelocity
	rapidezRecente -= 60 * dt -- (cai 60 studs/s a cada segundo)
	if agora.Magnitude >= rapidezRecente then
		rapidezRecente = agora.Magnitude
		velocidadeRecente = agora
	end
end)

-- Só a parte "deitada" (sem o sobe e desce) de uma direção, com tamanho 1. Quase toda vertical = zero.
local function noPlano(vetor: Vector3): Vector3
	local plano = Vector3.new(vetor.X, 0, vetor.Z)
	return if plano.Magnitude > 0.1 then plano.Unit else Vector3.zero
end

local function darPancada(alvo: Model, chassiDoAlvo: BasePart, motorista: Player)
	-- PARA ONDE: para onde você ia, mais um pouco "para longe de você" (batida de lado empurra de lado).
	local paraOAlvo = chassiDoAlvo.Position - chassi.Position
	local direcao = noPlano(noPlano(velocidadeRecente) + noPlano(paraOAlvo))
	local mudanca = direcao * Config.BaterEmpurrao + Vector3.yAxis * Config.BaterSubida -- (studs/s)
	-- GIRO: a batida pegou mais de lado? Ele roda. (O sinal diz para qual lado.)
	local lado = noPlano(paraOAlvo):Cross(direcao).Y -- perto de 0 = batida bem no meio (sem giro)
	local giro = if math.abs(lado) > 0.1 then -lado * Config.BaterGiro else 0
	-- Quem calcula a física do outro quadriciclo é o computador do motorista DELE: mandamos para lá.
	local pastaDoAlvo = alvo:FindFirstChild("Scripts")
	local eventoDoAlvo = if pastaDoAlvo then pastaDoAlvo:FindFirstChild("AcaoQuadriciclo") else nil
	if eventoDoAlvo and eventoDoAlvo:IsA("RemoteEvent") then
		eventoDoAlvo:FireClient(motorista, "Pancada", mudanca, giro)
	end
	-- SOM da batida (tocado aqui no servidor: todo mundo perto ouve).
	if Config.BaterSomId ~= "" then
		local som = Instance.new("Sound")
		som.Name = "SomPancada"
		som.SoundId = Config.BaterSomId
		som.Volume = 1
		som.RollOffMaxDistance = 200
		som.Parent = chassiDoAlvo
		som:Play()
		Debris:AddItem(som, 5)
	end
end

eventoAcao.OnServerEvent:Connect(function(jogador: Player, acao: unknown, alvo: unknown)
	if acao ~= "Bater" or not ehOMotorista(jogador) then
		return
	end
	-- Confere tudo: quem manda é o cliente, e um trapaceiro pode mandar qualquer coisa.
	if typeof(alvo) ~= "Instance" or not alvo:IsA("Model") or alvo == modelo or not alvo:IsDescendantOf(workspace) then
		return
	end
	if not CollectionService:HasTag(alvo, "Quadriciclo") then
		return -- só vale bater em quadriciclo
	end
	local chassiDoAlvo = alvo:FindFirstChild("Chassi")
	local bancoDoAlvo = alvo:FindFirstChild("Banco")
	if not (chassiDoAlvo and chassiDoAlvo:IsA("BasePart")) or not (bancoDoAlvo and bancoDoAlvo:IsA("VehicleSeat")) then
		return
	end
	-- Precisa ter OUTRO JOGADOR dirigindo ele.
	local outroPiloto = bancoDoAlvo.Occupant
	local personagem = if outroPiloto then outroPiloto.Parent else nil
	local motorista = if personagem and personagem:IsA("Model") then Players:GetPlayerFromCharacter(personagem) else nil
	if motorista == nil or motorista == jogador then
		return
	end
	-- Estava rápido de verdade e está perto? (com folga: o servidor vê tudo um pouquinho atrasado)
	if rapidezRecente < Config.BaterVelocidadeMinima * 0.7 then
		return
	end
	if (chassiDoAlvo.Position - chassi.Position).Magnitude > DISTANCIA_PANCADA then
		return
	end
	local agora = os.clock()
	if agora - (ultimaPancada[alvo] or 0) < ESPERA_PANCADA then
		return
	end
	ultimaPancada[alvo] = agora
	darPancada(alvo, chassiDoAlvo, motorista)
	debugPrint(`Pancada de {jogador.Name} em "{alvo:GetFullName()}"`)
end)

-- =====================================================================
-- INÍCIO: executa tudo na ordem
-- =====================================================================
if modelo.PrimaryPart == nil then
	modelo.PrimaryPart = chassi -- ajuda a mover o modelo inteiro (PivotTo)
end
-- Com StreamingEnabled, "Atomic" faz o modelo chegar inteiro no jogador (o ideal é já
-- deixar assim no Studio; o pcall evita que um erro aqui pare o script inteiro).
pcall(function()
	modelo.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
end)

conferirMontagem()
for _, info in rodas do
	configurarRoda(info)
end
aplicarFisica()
configurarCollisionGroups()
prepararVisual()

if Config.DEBUG_MODE then
	ligarVisualDebug()
	imprimirRelatorio()
end

assento:GetPropertyChangedSignal("Occupant"):Connect(aoMudarOcupante)
aoMudarOcupante() -- começa estacionado e com o servidor como dono da física
modelo:AddTag("Quadriciclo")
