--!strict
--[[
	=====================================================================
	Montagem  (ModuleScript)
	Local: ServerScriptService > QuadricicloServidor > Montagem
	=====================================================================

	Prepara UM veículo quando ele aparece no Workspace (o QuadricicloServidor chama):
	  1. Encontra as peças e confere se estão montadas certo.
	  2. Aplica os valores da Configuracao nas molas, motores e direção.
	  3. Aplica massa e atrito (CustomPhysicalProperties) nas peças físicas e cria o Lastro.
	  4. Coloca as peças nos Collision Groups (as rodas não colidem com o chassi).
	  5. Garante que as malhas visuais não têm massa nem colisão.
	  6. Modo Debug: pinta as peças invisíveis de neon e imprime um relatório.
	Se algo estiver montado errado, para com uma mensagem clara no Output (em vermelho).
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Padrao = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("ConfiguracaoPadrao"))
export type Config = Padrao.Config

local Montagem = {}

-- Nomes dos Collision Groups (grupos de colisão).
Montagem.GRUPO_CHASSI = "QuadricicloChassi"
Montagem.GRUPO_RODAS = "QuadricicloRodas"
Montagem.GRUPO_PILOTO = "QuadricicloPiloto"

-- Cores usadas no modo debug para cada tipo de peça física.
local COR_DEBUG_CHASSI = Color3.fromRGB(0, 170, 255) -- azul
local COR_DEBUG_BANCO = Color3.fromRGB(0, 255, 120) -- verde
local COR_DEBUG_MANGA = Color3.fromRGB(255, 200, 0) -- amarelo
local COR_DEBUG_RODA = Color3.fromRGB(255, 60, 60) -- vermelho

-- =====================================================================
-- FORMATOS (types) que os outros módulos usam
-- =====================================================================
-- Tudo que o servidor precisa saber sobre cada roda.
export type InfoRoda = {
	nome: string,
	manga: BasePart, -- peça entre a mola e a roda (sobe, desce e, na frente, vira)
	roda: BasePart, -- cilindro invisível que encosta no chão
	suspensao: SlidingBallConstraint, -- CylindricalConstraint (frente) ou PrismaticConstraint (trás)
	mola: SpringConstraint,
	motor: HingeConstraint,
}

-- Um veículo pronto (um para cada quadriciclo/caminhão que está no Workspace).
export type Veiculo = {
	modelo: Model,
	pastaScripts: Instance, -- a pasta "Scripts" (Configuracao e o RemoteEvent)
	Config: Config, -- a Configuracao DESTE veículo (já completa com os valores padrão)
	chassi: BasePart,
	assento: VehicleSeat,
	pastaVisual: Instance?, -- a pasta "Visual" (opcional)
	rodas: { InfoRoda },
	pecasFisicas: { BasePart }, -- Chassi, Banco, Mangas e Rodas
	evento: RemoteEvent, -- o "AcaoQuadriciclo" (o fio entre o QuadricicloCliente e o servidor)
	limpezas: { () -> () }, -- o que desfazer quando o veículo sai do Workspace
}

-- =====================================================================
-- FUNÇÕES DE AJUDA
-- =====================================================================
local avisados: { [string]: boolean } = {} -- (o mesmo aviso aparece uma vez só, mesmo com 10 veículos iguais)

local function avisarUmaVez(mensagem: string)
	if not avisados[mensagem] then
		avisados[mensagem] = true
		warn(mensagem)
	end
end

-- Imprime só quando o DEBUG_MODE do veículo está ligado.
function Montagem.debugPrint(v: Veiculo, mensagem: string)
	if v.Config.DEBUG_MODE then
		print(`[Quadriciclo] {v.modelo.Name}: {mensagem}`)
	end
end

-- Este Model tem cara de veículo? (precisa ter Scripts > Configuracao)
function Montagem.ehVeiculo(objeto: Instance): boolean
	if not objeto:IsA("Model") then
		return false
	end
	local pasta = objeto:FindFirstChild("Scripts")
	local config = if pasta then pasta:FindFirstChild("Configuracao") else nil
	return config ~= nil and config:IsA("ModuleScript")
end

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
-- Se algo estiver errado, para com uma mensagem clara no Output.
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

-- =====================================================================
-- 1) ENCONTRAR AS PEÇAS
-- =====================================================================
-- Lê a Configuracao do veículo (e completa com o padrão o que faltar).
local function lerConfiguracao(pastaScripts: Instance): Config
	local modulo = buscar(pastaScripts, "Configuracao", "ModuleScript") :: ModuleScript
	local carregou, resultado = pcall(require, modulo)
	if not carregou then
		error(`[Quadriciclo] A Configuracao de "{pastaScripts:GetFullName()}" deu erro: {resultado}`, 0)
	end
	return Padrao.completar(resultado)
end

-- Confere as 5 peças de cada pasta de roda. Se faltar ou estiver errado, anota o problema
-- (para mostrar TODOS de uma vez no final) e devolve nil.
local function itemDaRoda(problemas: { string }, pasta: Instance, nome: string, classe: string, descricao: string): Instance?
	local objeto = pasta:FindFirstChild(nome)
	if objeto == nil then
		table.insert(problemas, `• {pasta.Name}: falta "{nome}" ({descricao}). {explicarFalta(pasta, nome, classe)}`)
		return nil
	end
	if not objeto:IsA(classe) then
		table.insert(problemas, `• {pasta.Name}: "{nome}" deveria ser {descricao}, mas é {objeto.ClassName}. Apague e crie de novo pelo + da pasta.`)
		return nil
	end
	return objeto
end

local function lerRodas(pastaRodas: Instance): { InfoRoda }
	local rodas: { InfoRoda } = {}
	local problemas: { string } = {}
	for _, pasta in pastaRodas:GetChildren() do
		-- Cada roda fica numa pasta própria (ex.: "DianteiraEsquerda").
		if not (pasta:IsA("Folder") or pasta:IsA("Model")) then
			continue
		end
		local manga = itemDaRoda(problemas, pasta, "Manga", "BasePart", "Part")
		local roda = itemDaRoda(problemas, pasta, "Roda", "BasePart", "Part cilindro")
		-- "SlidingBallConstraint" é a classe-mãe da Cylindrical e da Prismatic: assim aceitamos as duas.
		local suspensao = itemDaRoda(problemas, pasta, "Suspensao", "SlidingBallConstraint", "CylindricalConstraint ou PrismaticConstraint")
		local mola = itemDaRoda(problemas, pasta, "Mola", "SpringConstraint", "SpringConstraint")
		local motor = itemDaRoda(problemas, pasta, "Motor", "HingeConstraint", "HingeConstraint")
		if manga and roda and suspensao and mola and motor then
			table.insert(rodas, {
				nome = pasta.Name,
				manga = manga :: BasePart,
				roda = roda :: BasePart,
				suspensao = suspensao :: SlidingBallConstraint,
				mola = mola :: SpringConstraint,
				motor = motor :: HingeConstraint,
			})
		end
	end
	-- Mostra todos os problemas de uma vez: assim você corrige tudo numa rodada só.
	if #problemas > 0 then
		error(
			`[Quadriciclo] Encontrei problemas nas pastas das rodas de "{pastaRodas:GetFullName()}":\n`
				.. table.concat(problemas, "\n")
				.. "\nDica: os nomes precisam ser idênticos (maiúsculas, acentos e espaços contam)"
				.. " e os 5 itens ficam DIRETO dentro da pasta da roda, não dentro de outra peça.",
			0
		)
	end
	if #rodas == 0 then
		error(`[Quadriciclo] A pasta "{pastaRodas:GetFullName()}" está vazia. Cada roda precisa de uma pasta com Manga, Roda, Suspensao, Mola e Motor.`, 0)
	end
	return rodas
end

-- =====================================================================
-- 2) CONFERIR A MONTAGEM (ajuda muito quando você monta à mão)
-- =====================================================================
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
	problemas: { string },
	info: InfoRoda,
	constraint: Constraint,
	pecaA: BasePart,
	pecaB: BasePart,
	comoDeveSer: string
): boolean
	local anexo0 = constraint.Attachment0
	local anexo1 = constraint.Attachment1
	if anexo0 == nil or anexo1 == nil then
		table.insert(problemas, `• {info.nome} › {constraint.Name}: falta preencher o Attachment0 ou o Attachment1. O certo é {comoDeveSer}.`)
		return false
	end
	-- Tanto faz a ordem: A0 na peça A e A1 na peça B, ou o contrário.
	local peca0 = anexo0.Parent
	local peca1 = anexo1.Parent
	local pecasCertas = (peca0 == pecaA and peca1 == pecaB) or (peca0 == pecaB and peca1 == pecaA)
	if not pecasCertas then
		table.insert(
			problemas,
			`• {info.nome} › {constraint.Name}: está ligando "{ondeEsta(anexo0)}" com "{ondeEsta(anexo1)}". O certo é {comoDeveSer}.`
		)
		return false
	end
	return true
end

local function conferirMontagem(v: Veiculo)
	local Config, chassi, assento = v.Config, v.chassi, v.assento
	local problemas: { string } = {}

	-- Peça ancorada não se mexe: desancoramos e avisamos.
	for _, parte in v.pecasFisicas do
		if parte.Anchored then
			parte.Anchored = false
			avisarUmaVez(`[Quadriciclo] "{parte:GetFullName()}" estava Anchored. Desancorei para ele poder andar.`)
		end
	end

	-- O Banco precisa estar soldado no Chassi (WeldConstraint).
	if #assento:GetJoints() == 0 then
		avisarUmaVez(`[Quadriciclo] O Banco de "{v.modelo.Name}" não está soldado em nada. Crie um WeldConstraint com Part0 = Banco e Part1 = Chassi.`)
	end

	-- Direções de referência do veículo (o Banco aponta para a frente).
	local cima = assento.CFrame.UpVector
	local direita = assento.CFrame.RightVector

	for _, info in v.rodas do
		-- a) Cada constraint liga as peças certas? (erro mais comum de quem monta à mão)
		local suspensaoOk = conferirLigacao(
			problemas,
			info,
			info.suspensao,
			chassi,
			info.manga,
			`Attachment0 = Chassi › Suspensao_{info.nome} e Attachment1 = Manga › Suspensao`
		)
		local molaOk = conferirLigacao(
			problemas,
			info,
			info.mola,
			chassi,
			info.manga,
			`Attachment0 = Chassi › Mola_{info.nome} e Attachment1 = Manga › Mola`
		)
		local motorOk = conferirLigacao(problemas, info, info.motor, info.manga, info.roda, "Attachment0 = Manga › Eixo e Attachment1 = Roda › Eixo")

		-- b) SUSPENSAO: os dois Attachments precisam ter a MESMA orientação
		--    e ficar na mesma "linha" do trilho (um exatamente em cima do outro).
		if suspensaoOk then
			local anexo0 = info.suspensao.Attachment0 :: Attachment
			local anexo1 = info.suspensao.Attachment1 :: Attachment
			local mesmaOrientacao = anexo0.WorldAxis:Dot(anexo1.WorldAxis) > 0.99
				and anexo0.WorldSecondaryAxis:Dot(anexo1.WorldSecondaryAxis) > 0.99
			if not mesmaOrientacao then
				table.insert(
					problemas,
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
					problemas,
					`• {info.nome} › Suspensao: os dois Attachments estão desalinhados ({string.format("%.2f", desvioDeLado)} studs de lado). `
						.. `Confira se o Attachment0 é o Suspensao_{info.nome} (o desta roda) e as Positions da tabela do Passo 2.`
				)
			end
			-- O trilho precisa apontar o eixo X para cima ou para baixo.
			if math.abs(eixo:Dot(cima)) < 0.9 then
				avisarUmaVez(`[Quadriciclo] {v.modelo.Name} › {info.nome}: o eixo X (seta amarela) dos Attachments da Suspensao deveria apontar para BAIXO. Use Orientation = (0, 0, -90).`)
			end
		end

		-- c) MOTOR: os dois Eixos precisam estar no mesmo lugar e apontar para o mesmo lado.
		if motorOk then
			local anexo0 = info.motor.Attachment0 :: Attachment
			local anexo1 = info.motor.Attachment1 :: Attachment
			local distancia = (anexo1.WorldPosition - anexo0.WorldPosition).Magnitude
			if distancia > 0.3 then
				table.insert(
					problemas,
					`• {info.nome} › Motor: o Eixo da Manga e o Eixo da Roda estão {string.format("%.2f", distancia)} studs longe um do outro. `
						.. "A Manga e a Roda precisam ter a mesma Position (tabela do Passo 1) e os dois Eixos Position = 0, 0, 0."
				)
			end
			if anexo0.WorldAxis:Dot(anexo1.WorldAxis) < 0.99 then
				table.insert(
					problemas,
					`• {info.nome} › Motor: os dois Eixos apontam para lados diferentes `
						.. `("{ondeEsta(anexo0)}" = {orientacaoEmTexto(anexo0)}, "{ondeEsta(anexo1)}" = {orientacaoEmTexto(anexo1)}). `
						.. "Os dois precisam ser 0, 180, 0 (e a Roda com Orientation 0, 0, 0)."
				)
			end
			-- O eixo do motor precisa apontar para a lateral (como o eixo de uma roda de verdade).
			if math.abs(anexo0.WorldAxis:Dot(direita)) < 0.9 then
				avisarUmaVez(`[Quadriciclo] {v.modelo.Name} › {info.nome}: o eixo X dos Attachments do Motor deveria apontar para a LATERAL. Use Orientation = (0, 180, 0).`)
			end
		end

		-- d) MOLA: precisa começar dentro dos limites, senão o veículo dá um tranco ao iniciar.
		if molaOk then
			local comprimento = info.mola.CurrentLength
			if comprimento < Config.SpringMinLength or comprimento > Config.SpringMaxLength then
				avisarUmaVez(
					`[Quadriciclo] {v.modelo.Name} › {info.nome}: a Mola começa com {string.format("%.2f", comprimento)} studs, `
						.. `fora dos limites ({Config.SpringMinLength} a {Config.SpringMaxLength}). Confira a altura da Manga.`
				)
			end
		end
	end

	-- Mostra todos os problemas de uma vez e para (com eles o veículo "explodiria").
	if #problemas > 0 then
		error(
			`[Quadriciclo] Encontrei problemas nos Attachments das constraints de "{v.modelo.Name}":\n`
				.. table.concat(problemas, "\n")
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
local function configurarBatente(v: Veiculo, info: InfoRoda)
	local Config = v.Config
	local suspensao = info.suspensao
	-- CurrentPosition = onde a Manga está ao longo do trilho, medido pelo próprio Roblox.
	local posicaoInicial = suspensao.CurrentPosition
	if math.abs(posicaoInicial) < 0.05 then
		task.wait() -- espera 1 frame para o Roblox medir o trilho e tenta de novo
		posicaoInicial = suspensao.CurrentPosition
	end
	if math.abs(posicaoInicial) < 0.05 then
		suspensao.LimitsEnabled = false
		avisarUmaVez(
			`[Quadriciclo] {v.modelo.Name} › {info.nome}: não consegui medir a posição da Suspensao `
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
	Montagem.debugPrint(v, `{info.nome}: batente no trilho de {string.format("%.2f", inferior)} a {string.format("%.2f", superior)}`)
end

local function configurarRoda(v: Veiculo, info: InfoRoda)
	local Config = v.Config
	-- ---------- MOLA (SpringConstraint) ----------
	local mola = info.mola
	mola.Stiffness = Config.SpringStiffness -- dureza
	mola.Damping = Config.SpringDamping -- amortecimento
	mola.FreeLength = Config.SpringFreeLength -- tamanho sem peso
	mola.LimitsEnabled = true -- batente reserva (o principal fica no trilho, logo abaixo)
	mola.MinLength = Config.SpringMinLength
	mola.MaxLength = Config.SpringMaxLength
	-- Aparência (a espiral amarela):
	mola.Visible = Config.SpringVisible or Config.DEBUG_MODE
	mola.Color = Config.SpringColor
	mola.Coils = Config.SpringCoils
	mola.Radius = Config.SpringRadius
	mola.Thickness = Config.SpringThickness

	-- ---------- TRILHO DA SUSPENSÃO ----------
	-- Sobe e desce livre (quem segura o peso é a mola), com o batente no próprio trilho.
	local suspensao = info.suspensao
	suspensao.ActuatorType = Enum.ActuatorType.None
	configurarBatente(v, info)

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
	motor.MotorMaxAcceleration = math.huge -- sem limite: a rampa de aceleração é feita pelo QuadricicloCliente
end

-- =====================================================================
-- 4) MASSA E ADERÊNCIA (CustomPhysicalProperties)
-- =====================================================================
-- PhysicalProperties.new(densidade, atrito, elasticidade, pesoDoAtrito, pesoDaElasticidade)
-- LASTRO: um peso invisível soldado no Chassi, lá embaixo, na altura dos eixos das rodas.
-- Uma parte do peso do Chassi (Config.LastroFracao) passa para ele: o peso TOTAL continua o mesmo
-- (as molas não afundam), mas o CENTRO DE MASSA desce. Centro de massa baixo = muito mais difícil de
-- capotar em curva rápida. Ele não colide com nada, então não raspa no chão nem atrapalha as rodas.
local function criarLastro(v: Veiculo)
	local Config, chassi = v.Config, v.chassi
	local fracao = math.clamp(Config.LastroFracao, 0, 0.9)
	local antigo = v.modelo:FindFirstChild("Lastro")
	if antigo then
		antigo:Destroy() -- (um lastro que ficou salvo no modelo: cria um novo, do tamanho certo)
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
	local referencia = CFrame.new(chassi.Position) * v.assento.CFrame.Rotation
	local alturaDosEixos = 0
	for _, info in v.rodas do
		alturaDosEixos += referencia:PointToObjectSpace(info.roda.Position).Y
	end
	-- (math.min com 0: o lastro nunca fica ACIMA do centro do Chassi, senão o centro de massa subiria)
	alturaDosEixos = math.min(alturaDosEixos / #v.rodas, 0) - Config.LastroAbaixoDoEixo
	-- 4) O lastro: um cubinho bem denso (densidade 50), no meio do veículo, na altura dos eixos.
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
	lastro.CastShadow = false
	local solda = Instance.new("WeldConstraint")
	solda.Part0 = lastro
	solda.Part1 = chassi
	solda.Parent = lastro
	lastro.Parent = v.modelo
	Montagem.debugPrint(v, `Lastro: {string.format("%.1f", massaDoLastro)} de massa, {string.format("%.2f", -alturaDosEixos)} studs abaixo do centro do Chassi`)
end

local function aplicarFisica(v: Veiculo)
	local Config, assento = v.Config, v.assento
	criarLastro(v) -- o Chassi fica mais leve e o peso que sobrou vai para o lastro, lá embaixo
	for _, info in v.rodas do
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
	for _, info in v.rodas do
		info.manga.CanCollide = false
		info.manga.CanTouch = false
		info.manga.CanQuery = false
		info.roda.CanCollide = true -- a roda É o que encosta no chão
	end
	v.chassi.CanCollide = true -- o chassi bate em paredes e raspa em pedras
end

-- =====================================================================
-- 5) COLLISION GROUPS
-- =====================================================================
-- Rodas x Chassi = não colidem (senão uma empurra a outra e tudo treme).
-- Rodas x Rodas = não colidem. Piloto x (Chassi e Rodas) = não colidem.
-- Todos continuam colidindo com o mundo (grupo "Default").
-- (Registrar os grupos é uma vez só, quando o servidor começa: o QuadricicloServidor chama.)
local gruposProntos = false

function Montagem.registrarGruposDeColisao(): boolean
	local sucesso, mensagemErro = pcall(function()
		for _, nome in { Montagem.GRUPO_CHASSI, Montagem.GRUPO_RODAS, Montagem.GRUPO_PILOTO } do
			if not PhysicsService:IsCollisionGroupRegistered(nome) then
				PhysicsService:RegisterCollisionGroup(nome)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(Montagem.GRUPO_RODAS, Montagem.GRUPO_CHASSI, false)
		PhysicsService:CollisionGroupSetCollidable(Montagem.GRUPO_RODAS, Montagem.GRUPO_RODAS, false)
		PhysicsService:CollisionGroupSetCollidable(Montagem.GRUPO_PILOTO, Montagem.GRUPO_CHASSI, false)
		PhysicsService:CollisionGroupSetCollidable(Montagem.GRUPO_PILOTO, Montagem.GRUPO_RODAS, false)
	end)
	if not sucesso then
		warn(`[Quadriciclo] Não consegui configurar os Collision Groups: {mensagemErro}`)
	end
	gruposProntos = sucesso
	return sucesso
end

local function aplicarGruposDeColisao(v: Veiculo)
	if not gruposProntos then
		return
	end
	v.chassi.CollisionGroup = Montagem.GRUPO_CHASSI
	v.assento.CollisionGroup = Montagem.GRUPO_CHASSI
	for _, info in v.rodas do
		info.manga.CollisionGroup = Montagem.GRUPO_RODAS
		info.roda.CollisionGroup = Montagem.GRUPO_RODAS
	end
end

-- =====================================================================
-- 6) MALHAS VISUAIS: sem massa, sem colisão, sempre soldadas
-- =====================================================================

-- A Roda física GIRA, e tudo que está soldado nela gira junto, em volta do eixo dela.
-- Um pneu bem no centro da Roda parece só rolar; fora do centro, ele dá voltas em volta
-- da roda. Isso acontece quando o pneu foi soldado na Roda errada (as 4 se chamam "Roda")
-- ou quando a Position dele é diferente da Position da Roda.
local function conferirPecaDaRoda(v: Veiculo, objeto: BasePart)
	for _, info in v.rodas do
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
			avisarUmaVez(
				`[Quadriciclo] A peça "{objeto:GetFullName()}" está soldada na Roda de {info.nome}, mas fica a `
					.. `{string.format("%.1f", diferenca.Magnitude)} studs do centro dela, então gira junto com essa roda fora do lugar. `
					.. "Deixe a peça com a mesma Position da Roda certa e, na WeldConstraint dela, escolha de novo o Part1: Rodas › (pasta da roda) › Roda."
			)
		end
		return
	end
end

local function prepararVisual(v: Veiculo)
	-- O fogo do nitro começa APAGADO (no molde ele pode ter ficado aceso; quem acende é o QuadricicloCliente).
	for _, objeto in v.modelo:GetDescendants() do
		if objeto:IsA("Attachment") and objeto.Name == "SaidaNitro" then
			for _, efeito in objeto:GetChildren() do
				if efeito:IsA("ParticleEmitter") then
					efeito.Enabled = false
				elseif efeito:IsA("Light") then
					efeito.Enabled = false
				end
			end
		end
	end

	local pastaVisual = v.pastaVisual
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
				avisarUmaVez(`[Quadriciclo] A malha "{objeto:GetFullName()}" não está soldada em nada e vai cair! Crie um WeldConstraint ligando ela à peça física.`)
			end
		end
	end
	if corrigidas > 0 then
		Montagem.debugPrint(v, `{corrigidas} peça(s) visual(is) estavam com massa ou colisão. Corrigi para Massless = true e CanCollide = false.`)
	end

	-- Peças soldadas numa Roda (pneu, calota...) precisam ficar em volta do centro dela.
	-- (Numa segunda volta: agora nenhuma malha está mais ancorada.)
	for _, objeto in pastaVisual:GetDescendants() do
		if objeto:IsA("BasePart") then
			conferirPecaDaRoda(v, objeto)
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

local function ligarVisualDebug(v: Veiculo)
	pintarDebug(v.chassi, COR_DEBUG_CHASSI)
	pintarDebug(v.assento, COR_DEBUG_BANCO)
	for _, info in v.rodas do
		pintarDebug(info.manga, COR_DEBUG_MANGA)
		pintarDebug(info.roda, COR_DEBUG_RODA)
	end

	-- Malhas ficam quase transparentes para você enxergar as peças físicas por dentro.
	local pastaVisual = v.pastaVisual
	if pastaVisual then
		for _, objeto in pastaVisual:GetDescendants() do
			if objeto:IsA("BasePart") then
				objeto.Transparency = math.max(objeto.Transparency, 0.8)
			end
		end
	end

	-- Mostra constraints (molas, eixos, trilhos) e attachments.
	for _, objeto in v.modelo:GetDescendants() do
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

local function imprimirRelatorio(v: Veiculo)
	local Config = v.Config
	local massaSuspensa = v.chassi.AssemblyMass -- Chassi + tudo que está soldado nele
	local massaTotal = massaSuspensa
	local rodasQueViram = 0
	for _, info in v.rodas do
		massaTotal += info.manga.AssemblyMass + info.roda.AssemblyMass
		if info.suspensao:IsA("CylindricalConstraint") then
			rodasQueViram += 1
		end
	end

	-- Quanto cada mola precisa segurar e qual será o tamanho dela parada:
	-- força = massa × gravidade  e  compressão = força / dureza.
	local pesoPorMola = massaSuspensa * workspace.Gravity / #v.rodas
	local comprimentoParado = Config.SpringFreeLength - pesoPorMola / Config.SpringStiffness

	print(`[Quadriciclo] ========== RELATÓRIO DE MONTAGEM: {v.modelo.Name} ==========`)
	print(`[Quadriciclo] Rodas: {#v.rodas} ({rodasQueViram} com direção) | Tração: {Config.DriveMode}`)
	print(`[Quadriciclo] Massa total: {string.format("%.1f", massaTotal)} | Massa sobre as molas: {string.format("%.1f", massaSuspensa)}`)
	print(
		`[Quadriciclo] Mola parada: ~{string.format("%.2f", comprimentoParado)} studs `
			.. `(limites {Config.SpringMinLength} a {Config.SpringMaxLength})`
	)
	if comprimentoParado <= Config.SpringMinLength + 0.05 then
		warn("[Quadriciclo] As molas não aguentam o peso: o veículo vai ficar apoiado no batente. Aumente SpringStiffness ou SpringFreeLength.")
	elseif comprimentoParado >= Config.SpringMaxLength then
		warn("[Quadriciclo] As molas estão fortes demais: a roda fica sempre esticada no limite. Diminua SpringStiffness ou SpringFreeLength.")
	end
end

-- =====================================================================
-- PREPARAR UM VEÍCULO (executa tudo na ordem)
-- =====================================================================
-- Devolve o veículo pronto. Se algo estiver montado errado, dá um erro com a explicação
-- (quem chama, o QuadricicloServidor, mostra o erro no Output e ignora este veículo).
function Montagem.preparar(modelo: Model): Veiculo
	-- 1) As peças e a Configuracao.
	local pastaScripts = buscar(modelo, "Scripts", "Instance")
	local Config = lerConfiguracao(pastaScripts)
	local chassi = buscar(modelo, "Chassi", "BasePart") :: BasePart
	local assento = buscar(modelo, "Banco", "VehicleSeat") :: VehicleSeat
	local rodas = lerRodas(buscar(modelo, "Rodas", "Folder"))

	-- Lista de todas as peças físicas (usada várias vezes abaixo).
	local pecasFisicas: { BasePart } = { chassi, assento }
	for _, info in rodas do
		table.insert(pecasFisicas, info.manga)
		table.insert(pecasFisicas, info.roda)
	end

	-- O "fio" entre o QuadricicloCliente e o servidor: buzina, nitro, gancho, sair do banco...
	-- (Se o veículo já tinha um, de uma preparação anterior, usa o mesmo.)
	local existente = pastaScripts:FindFirstChild("AcaoQuadriciclo")
	local evento: RemoteEvent
	if existente and existente:IsA("RemoteEvent") then
		evento = existente
	else
		evento = Instance.new("RemoteEvent")
		evento.Name = "AcaoQuadriciclo"
		evento.Parent = pastaScripts
	end

	local v: Veiculo = {
		modelo = modelo,
		pastaScripts = pastaScripts,
		Config = Config,
		chassi = chassi,
		assento = assento,
		pastaVisual = modelo:FindFirstChild("Visual"), -- opcional (pode não existir)
		rodas = rodas,
		pecasFisicas = pecasFisicas,
		evento = evento,
		limpezas = {},
	}

	-- 2) Tudo na ordem.
	if modelo.PrimaryPart == nil then
		modelo.PrimaryPart = chassi -- ajuda a mover o modelo inteiro (PivotTo)
	end
	-- Com StreamingEnabled, "Atomic" faz o modelo chegar inteiro no jogador (o ideal é já
	-- deixar assim no Studio; o pcall evita que um erro aqui pare tudo).
	pcall(function()
		modelo.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	conferirMontagem(v)
	for _, info in rodas do
		configurarRoda(v, info)
	end
	aplicarFisica(v)
	aplicarGruposDeColisao(v)
	prepararVisual(v)
	if Config.DEBUG_MODE then
		ligarVisualDebug(v)
		imprimirRelatorio(v)
	end
	return v
end

return Montagem
