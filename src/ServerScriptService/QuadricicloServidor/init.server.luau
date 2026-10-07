--!strict
--[[
	=====================================================================
	QuadricicloServidor  (Script normal)
	Local: ServerScriptService > QuadricicloServidor
	=====================================================================

	UM script só, no servidor, para TODOS os veículos (quadriciclo, caminhão monstro e os que você
	criar depois). Ele substitui o script "Servidor" que ficava dentro de cada veículo: agora os
	veículos não precisam de script nenhum, só da pasta Scripts com a Configuracao.
	É o "irmão" do QuadricicloCliente (StarterPlayerScripts), que cuida do lado de cada jogador.

	Ele acha os veículos sozinho:
	  - os que o Spawner cria (pasta Workspace > QuadriciclosDosJogadores);
	  - os que você colocou direto no mapa pelo Studio (para testar).
	Para cada um: confere a montagem e aplica a Configuracao (Montagem), cuida do banco e das ações do
	motorista (Motorista), do gancho (Gancho) e da batida forte (Pancada). No fim, coloca a tag
	"Quadriciclo" no Model: é o sinal de "pronto!" para o QuadricicloCliente e para o Spawner.

	Cada assunto fica num ModuleScript aqui dentro: Montagem, Motorista, Gancho e Pancada.
	Os valores de ajuste ficam na Configuracao de cada veículo (e na ConfiguracaoPadrao).
]]

local Players = game:GetService("Players")

local Montagem = require(script:WaitForChild("Montagem"))
local Motorista = require(script:WaitForChild("Motorista"))
local Gancho = require(script:WaitForChild("Gancho"))
local Pancada = require(script:WaitForChild("Pancada"))
type Veiculo = Montagem.Veiculo

-- =====================================================================
-- AJUSTES
-- =====================================================================
local TAG_PRONTO = "Quadriciclo" -- a tag de "veículo pronto" (o QuadricicloCliente e o Spawner esperam por ela)
local NOME_DA_PASTA = "QuadriciclosDosJogadores" -- onde o Spawner coloca os veículos dos jogadores
-- ANTI-SPAM: cada jogador pode mandar até ACOES_POR_SEGUNDO ações por segundo (com uma "reserva" de
-- ACOES_DE_RESERVA para rajadas). Ninguém jogando normal chega perto disso; um trapaceiro mandando
-- milhares por segundo é ignorado (assim ele não trava o servidor nem enche a internet dos outros).
local ACOES_POR_SEGUNDO = 30
local ACOES_DE_RESERVA = 60

-- =====================================================================
-- AVISOS NO OUTPUT
-- =====================================================================
local avisados: { [string]: boolean } = {}

-- Erro de montagem: aparece em VERMELHO no Output (uma vez só), mas o resto do jogo continua.
local function mostrarErro(mensagem: string)
	if not avisados[mensagem] then
		avisados[mensagem] = true
		task.spawn(error, mensagem, 0)
	end
end

-- O veículo ainda tem o script "Servidor" antigo dentro? Os dois juntos brigariam (eventos e
-- forças em dobro). Então o antigo continua cuidando dele até você apagar o script.
local function temScriptAntigo(modelo: Model): boolean
	local pasta = modelo:FindFirstChild("Scripts")
	local antigo = if pasta then pasta:FindFirstChild("Servidor") else nil
	if antigo and antigo:IsA("Script") and antigo.Enabled then
		local mensagem = `[Quadriciclo] "{modelo.Name}" ainda tem o script "Servidor" dentro (Scripts > Servidor). Apague ele:`
			.. " agora quem cuida de todos os veículos é o ServerScriptService > QuadricicloServidor. Enquanto ele existir, este veículo usa o antigo."
		if not avisados[mensagem] then
			avisados[mensagem] = true
			warn(mensagem)
		end
		return true
	end
	return false
end

-- =====================================================================
-- ANTI-SPAM (um "balde de fichas" por jogador)
-- =====================================================================
type Balde = { fichas: number, quando: number }
local baldes: { [Player]: Balde } = {}

local function podeAgir(jogador: Player): boolean
	local agora = os.clock()
	local balde = baldes[jogador]
	if balde == nil then
		balde = { fichas = ACOES_DE_RESERVA, quando = agora }
		baldes[jogador] = balde
	end
	-- A cada segundo, o balde ganha ACOES_POR_SEGUNDO fichas (até encher). Cada ação gasta uma.
	balde.fichas = math.min(balde.fichas + (agora - balde.quando) * ACOES_POR_SEGUNDO, ACOES_DE_RESERVA)
	balde.quando = agora
	if balde.fichas < 1 then
		return false
	end
	balde.fichas -= 1
	return true
end

Players.PlayerRemoving:Connect(function(jogador: Player)
	baldes[jogador] = nil
end)

-- =====================================================================
-- O "PORTEIRO" do RemoteEvent de cada veículo: confere e manda para o módulo certo
-- =====================================================================
local function aoReceber(v: Veiculo, jogador: Player, acao: unknown, a: unknown, b: unknown, c: unknown)
	if typeof(acao) ~= "string" or not podeAgir(jogador) then
		return
	end
	if acao == "GanchoDesliga" then
		Gancho.aoDesligar(v, jogador) -- (só quem lançou consegue soltar: o módulo confere)
		return
	end
	-- Todas as outras ações são do MOTORISTA deste veículo.
	if not Motorista.ehOMotorista(v, jogador) then
		return
	end
	if acao == "GanchoLiga" then
		Gancho.aoLigar(v, jogador, a, b, c)
	elseif acao == "Bater" then
		Pancada.aoBater(v, jogador, a)
	else
		Motorista.aoAcao(v, acao, a) -- "Buzina", "Nitro", "Derrapando" e "Sair"
	end
end

-- Alguém sentou ou levantou do banco.
local function aoMudarOcupante(v: Veiculo)
	if v.assento.Occupant == nil then
		Motorista.limparAtributos(v) -- banco vazio: sem buzina, nitro e derrapagem
	end
	Gancho.soltar(v) -- trocou o motorista (ou saiu): o gancho solta
	Pancada.aoMudarOcupante(v)
	Motorista.aoMudarOcupante(v) -- (pode esperar 1 frame: fica por último)
end

-- =====================================================================
-- OS VEÍCULOS
-- =====================================================================
local veiculos: { [Model]: Veiculo } = {} -- os que estão funcionando agora
local preparando: { [Model]: boolean } = {}

-- O veículo saiu do Workspace (ou foi apagado): desfaz tudo dele.
local function esquecer(modelo: Model)
	local v = veiculos[modelo]
	if v == nil then
		return
	end
	veiculos[modelo] = nil
	for _, desfazer in v.limpezas do
		local ok, erro = pcall(function(): string?
			desfazer()
			return nil -- (deu certo: sem mensagem de erro)
		end)
		if not ok then
			warn(`[Quadriciclo] Erro ao desligar "{modelo.Name}": {erro}`)
		end
	end
	table.clear(v.limpezas)
end

local function preparar(modelo: Model)
	if veiculos[modelo] or preparando[modelo] or not modelo:IsDescendantOf(workspace) then
		return
	end
	if not Montagem.ehVeiculo(modelo) or temScriptAntigo(modelo) then
		return
	end
	preparando[modelo] = true
	local ok, resultado = pcall(Montagem.preparar, modelo)
	preparando[modelo] = nil
	if not ok then
		mostrarErro(tostring(resultado)) -- montado errado: explica no Output e ignora este veículo
		return
	end
	local v: Veiculo = resultado
	if not modelo:IsDescendantOf(workspace) then
		return -- sumiu enquanto era preparado
	end
	veiculos[modelo] = v
	Motorista.ligar(v)
	Gancho.ligar(v)
	Pancada.ligar(v)

	local conexoes = {
		v.evento.OnServerEvent:Connect(function(jogador: Player, acao: unknown, a: unknown, b: unknown, c: unknown)
			aoReceber(v, jogador, acao, a, b, c)
		end),
		v.assento:GetPropertyChangedSignal("Occupant"):Connect(function()
			aoMudarOcupante(v)
		end),
		modelo.AncestryChanged:Connect(function()
			if not modelo:IsDescendantOf(workspace) then
				esquecer(modelo) -- saiu do Workspace
			end
		end),
		modelo.Destroying:Connect(function()
			esquecer(modelo) -- foi apagado
		end),
	}
	table.insert(v.limpezas, function()
		for _, conexao in conexoes do
			conexao:Disconnect()
		end
	end)

	Pancada.aoMudarOcupante(v)
	Motorista.aoMudarOcupante(v) -- começa estacionado e com o servidor como dono da física (espera 1 frame)
	if veiculos[modelo] == v then
		modelo:AddTag(TAG_PRONTO) -- PRONTO! O QuadricicloCliente e o Spawner esperam por esta tag.
	end
end

-- Uma vez só, quando o servidor começa.
Montagem.registrarGruposDeColisao()

-- 1) Os veículos que o Spawner cria (pasta Workspace > QuadriciclosDosJogadores).
--    (O Spawner também procura esta pasta: quem rodar primeiro cria, o outro só acha.)
local pasta = workspace:FindFirstChild(NOME_DA_PASTA)
if pasta == nil then
	local nova = Instance.new("Folder")
	nova.Name = NOME_DA_PASTA
	nova.Parent = workspace
	pasta = nova
end
local pastaDosVeiculos = pasta :: Instance
pastaDosVeiculos.ChildAdded:Connect(function(filho: Instance)
	if filho:IsA("Model") then
		preparar(filho)
	end
end)

-- 2) Os que já estavam no Workspace quando o jogo começou (na pasta ou soltos no mapa, para testar).
for _, objeto in workspace:GetDescendants() do
	if objeto:IsA("Model") and Montagem.ehVeiculo(objeto) then
		task.spawn(preparar, objeto) -- (cada um no seu ritmo: um não espera o outro)
	end
end

-- 3) Rede de segurança: a cada 5 s, esquece os veículos que sumiram sem avisar.
task.spawn(function()
	while true do
		task.wait(5)
		for modelo in veiculos do
			if not modelo:IsDescendantOf(workspace) then
				esquecer(modelo)
			end
		end
	end
end)
