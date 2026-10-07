--!strict
--[[
	=====================================================================
	Nitro  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > Nitro
	=====================================================================

	Para TODO MUNDO (criarEfeitos): fogo roxo em cada Attachment "SaidaNitro"
	do quadriciclo, luz roxa e os sons de ligar e desligar.
	Para QUEM DIRIGE (ligar/desligar): tecla Shift / botão R1 / botão NITRO,
	o tanque (dura Config.NitroDuration segundos e enche sozinho), a barra
	roxa "BarraNitro" do HUD. (A câmera que "abre" no nitro agora fica no módulo Camera.).
	Quem decide se o nitro está funcionando é o "atualizar" do QuadricicloCliente.
]]

local ContextActionService = game:GetService("ContextActionService")


local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
type Quadriciclo = Veiculo.Quadriciclo

local Nitro = {}

Nitro.MINIMO_PARA_LIGAR = 0.3 -- precisa de 30% do tanque para ligar (evita ligar e desligar sem carga)

local ACAO_NITRO = "QuadricicloNitro"
local COR_NITRO = Color3.fromRGB(170, 60, 255)
local COR_NITRO_USANDO = Color3.fromRGB(215, 110, 255) -- rosa-roxo: queimando nitro
local COR_NITRO_PRONTO = Color3.fromRGB(150, 60, 255) -- roxo: pode usar
local COR_NITRO_RECARREGANDO = Color3.fromRGB(85, 70, 110) -- roxo apagado: ainda não dá para usar


local telaDaBarraNitro: ScreenGui? = nil
local barraNitro: Frame? = nil

-- =====================================================================
-- FOGO ROXO, LUZ E SONS (todo mundo vê e ouve)
-- =====================================================================
local function criarFogoRoxo(anexo: Attachment): ParticleEmitter
	local fogo = Instance.new("ParticleEmitter")
	fogo.Texture = "rbxasset://textures/particles/fire_main.dds" -- textura de fogo que já vem no Roblox
	fogo.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 255)), -- miolo quase branco
		ColorSequenceKeypoint.new(0.35, COR_NITRO), -- roxo
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 0, 150)), -- roxo escuro na ponta
	})
	fogo.LightEmission = 1 -- brilha
	fogo.LightInfluence = 0 -- a luz do cenário não escurece o fogo
	fogo.LockedToPart = true -- a chama anda junto com o quadriciclo (não vira um rastro comprido)
	fogo.Size = NumberSequence.new(0.8, 0.2)
	fogo.Transparency = NumberSequence.new(0.1, 1)
	fogo.Lifetime = NumberRange.new(0.12, 0.25)
	fogo.Rate = 80
	fogo.Speed = NumberRange.new(10, 14)
	fogo.SpreadAngle = Vector2.new(8, 8)
	fogo.Rotation = NumberRange.new(0, 360)
	fogo.RotSpeed = NumberRange.new(-200, 200)
	fogo.EmissionDirection = Enum.NormalId.Right -- sai para onde aponta a seta AMARELA do Attachment
	fogo.Parent = anexo
	return fogo
end

local function criarLuzRoxa(anexo: Attachment): PointLight
	local luz = Instance.new("PointLight") -- brilho roxo em volta da saída
	luz.Color = COR_NITRO
	luz.Brightness = 3
	luz.Range = 8
	luz.Parent = anexo
	return luz
end

-- Chamado uma vez para cada quadriciclo que aparece no seu jogo.
function Nitro.criarEfeitos(quad: Quadriciclo)
	local Config = quad.Config
	local somNitroLiga = Veiculo.criarSom(quad, "SomNitroLiga", Config.NitroOnSoundId, false)
	local somNitroDesliga = Veiculo.criarSom(quad, "SomNitroDesliga", Config.NitroOffSoundId, false)
	local fogosNitro: { ParticleEmitter } = {}
	local luzesNitro: { PointLight } = {}

	for _, objeto in quad.modelo:GetDescendants() do
		if objeto:IsA("Attachment") and objeto.Name == "SaidaNitro" then
			if objeto:FindFirstChildOfClass("ParticleEmitter") == nil then
				Veiculo.guardar(quad, criarFogoRoxo(objeto))
			end
			for _, filho in objeto:GetChildren() do
				if filho:IsA("ParticleEmitter") then
					filho.Enabled = false
					table.insert(fogosNitro, filho)
				end
			end
			local luzSua = objeto:FindFirstChildOfClass("PointLight")
			local luz = luzSua or criarLuzRoxa(objeto)
			if luzSua == nil then
				Veiculo.guardar(quad, luz) -- (a luz que o script criou some junto com o quadriciclo)
			end
			luz.Enabled = false
			table.insert(luzesNitro, luz)
		end
	end
	if #fogosNitro == 0 and Config.DEBUG_MODE then
		warn('[Quadriciclo] Nenhum Attachment "SaidaNitro" no modelo: o nitro funciona, mas sem fogo.')
	end

	local nitroVisivel = false
	quad.mostrarNitro = function(ligado: boolean)
		if ligado == nitroVisivel then
			return
		end
		nitroVisivel = ligado
		for _, fogo in fogosNitro do
			fogo.Enabled = ligado
		end
		for _, luz in luzesNitro do
			luz.Enabled = ligado
		end
		if ligado then
			somNitroLiga:Play()
		else
			somNitroDesliga:Play()
		end
	end

	-- Os OUTROS jogadores seguem o que o Servidor marcou no modelo.
	local function aoMudarAtributo()
		if not quad.dirigindo then
			quad.mostrarNitro(quad.modelo:GetAttribute("Nitro") == true)
		end
	end
	Veiculo.guardarConexao(quad, quad.modelo:GetAttributeChangedSignal("Nitro"):Connect(aoMudarAtributo))
	aoMudarAtributo() -- quem chega com o nitro já ligado já vê
end

-- =====================================================================
-- QUEM DIRIGE
-- =====================================================================
-- Liga ou desliga de verdade (chamado pelo "atualizar" só quando muda).
function Nitro.mudar(quad: Quadriciclo, ligado: boolean)
	quad.nitroAtivo = ligado
	quad.mostrarNitro(ligado) -- você vê na hora, sem esperar a internet...
	Veiculo.avisarServidor(quad, "Nitro", ligado) -- ...e os outros jogadores logo depois

end

-- TANQUE: gasta ligado, enche desligado (mesmo fora do banco) e mexe na barra do HUD.
-- Devolve se o nitro PODE funcionar agora (o "atualizar" decide o resto).
function Nitro.disponivel(quad: Quadriciclo): boolean
	local Config = quad.Config
	local agora = os.clock()
	local passo = agora - quad.relogioNitro -- conta até o tempo fora do banco (o tanque enche parado)
	quad.relogioNitro = agora
	if quad.nitroAtivo then
		quad.cargaNitro = math.max(quad.cargaNitro - passo / Config.NitroDuration, 0)
	else
		quad.cargaNitro = math.min(quad.cargaNitro + passo / Config.NitroRechargeTime, 1)
	end
	if quad.cargaNitro <= 0 then
		quad.nitroTravado = true -- acabou: precisa soltar o Shift para usar de novo
	elseif not quad.nitroPedido then
		quad.nitroTravado = false
	end

	local tela = quad.tela
	if tela ~= telaDaBarraNitro then
		telaDaBarraNitro = tela
		local achada = if tela then tela:FindFirstChild("BarraNitro", true) else nil
		barraNitro = if achada and achada:IsA("Frame") then achada else nil
	end
	local barra = barraNitro
	if barra then
		barra.Size = UDim2.fromScale(quad.cargaNitro, 1)
		barra.BackgroundColor3 = if quad.nitroAtivo
			then COR_NITRO_USANDO
			elseif quad.nitroTravado or quad.cargaNitro < Nitro.MINIMO_PARA_LIGAR then COR_NITRO_RECARREGANDO
			else COR_NITRO_PRONTO
	end

	return quad.nitroPedido
		and not quad.nitroTravado
		and quad.cargaNitro > 0
		and (quad.nitroAtivo or quad.cargaNitro >= Nitro.MINIMO_PARA_LIGAR)
end

-- Sentou: liga a tecla do nitro. (A câmera que "abre" no nitro agora fica no módulo Camera.)
function Nitro.ligar(quad: Quadriciclo)
	ContextActionService:BindActionAtPriority(ACAO_NITRO, function(_nomeAcao: string, estado: Enum.UserInputState, _entrada: InputObject): Enum.ContextActionResult?
		quad.nitroPedido = Veiculo.segurando(estado)
		return Enum.ContextActionResult.Sink
	end, true, Veiculo.PRIORIDADE, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle(ACAO_NITRO, "NITRO")
end

-- Levantou: solta a tecla e apaga o nitro.
function Nitro.desligar(quad: Quadriciclo)
	ContextActionService:UnbindAction(ACAO_NITRO)
	quad.nitroPedido = false
	if quad.nitroAtivo then
		Nitro.mudar(quad, false)
	end
end

return Nitro

