--!strict
--[[
	=====================================================================
	TeclasMenu  (ModuleScript)
	Local: StarterPlayer > StarterPlayerScripts > QuadricicloCliente > TeclasMenu
	=====================================================================

	Faz o seu menu "Controles" (dentro do HUDQuadriciclo) reagir enquanto você dirige.
	O script acha os textos do menu pelo que está ESCRITO neles: "Buzina", "Nitro",
	"Freio De Mão" e as teclas "H", "LShift" (ou "Shift"), "Espaço" (ou "Space"), "C" e "Q".
	  Tecla apertada: o "cilindro" em volta dela fica branquinho e afunda um pouquinho.
	  Buzina: amarela e tremendo enquanto toca; vermelha depois de 10 s seguidos.
	  Nitro: verde ligado; vermelho quando o tanque está no fim e até dar para usar de novo.
	  Freio De Mão: vermelho enquanto segura; treme só com o carro andando.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Veiculo = require(script.Parent:WaitForChild("Veiculo"))
local Nitro = require(script.Parent:WaitForChild("Nitro"))
type Quadriciclo = Veiculo.Quadriciclo

local TeclasMenu = {}

local COR_TEXTO_AMARELO = Color3.fromRGB(255, 215, 40)
local COR_TEXTO_VERDE = Color3.fromRGB(70, 230, 100)
local COR_TEXTO_VERMELHO = Color3.fromRGB(255, 60, 60)
local NITRO_NO_FIM = 0.25 -- abaixo de 25% do tanque, o texto do nitro fica vermelho
local BUZINA_MUITO_TEMPO = 10 -- (s) segurando a buzina esse tempo, o texto fica vermelho

type TextoDoMenu = { rotulo: TextLabel, corNormal: Color3, giroNormal: number }
type TeclaDoMenu = { brilho: Frame, escala: UIScale, escalaNormal: number }

-- Texto "simplificado" (minúsculo, sem acento e sem espaço) → o que ele é no menu.
local TEXTOS_PROCURADOS: { [string]: string } = { buzina = "Buzina", nitro = "Nitro", freiodemao = "Freio De Mão" }
local TECLAS_PROCURADAS: { [string]: string } = {
	h = "Buzina", lshift = "Nitro", shift = "Nitro", leftshift = "Nitro",
	espaco = "Freio De Mão", space = "Freio De Mão", c = "Câmera", q = "Gancho",
}
-- Teclas que o script avisa no Output se não achar (a do Q é opcional).
local TECLAS_OBRIGATORIAS: { [string]: string } = { Buzina = "H", Nitro = "LShift", ["Freio De Mão"] = "Espaço", ["Câmera"] = "C" }
local SEM_ACENTO_MENU: { [string]: string } = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["é"] = "e", ["ê"] = "e", ["í"] = "i",
	["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ú"] = "u", ["ç"] = "c",
	["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ã"] = "a", ["É"] = "e", ["Ê"] = "e", ["Í"] = "i",
	["Ó"] = "o", ["Ô"] = "o", ["Õ"] = "o", ["Ú"] = "u", ["Ç"] = "c",
}

local telaDoMenu: ScreenGui? = nil -- HUD em que o menu já foi procurado
local textosDoMenu: { [string]: TextoDoMenu } = {}
local teclasDoMenu: { [string]: TeclaDoMenu } = {}
local jaAvisouMenu = false
local buzinaSegurandoHa = 0
local conexaoMenu: RBXScriptConnection? = nil

local function simplificarTexto(texto: string): string
	local simples = string.lower(texto)
	for comAcento, semAcento in SEM_ACENTO_MENU do
		simples = string.gsub(simples, comAcento, semAcento)
	end
	return (string.gsub(simples, "[%s%-_%.:]", ""))
end

-- A "tecla" é o próprio texto (se ele tiver fundo) ou a moldura arredondada em volta dele.
local function prepararTecla(rotulo: TextLabel): TeclaDoMenu
	local moldura: GuiObject = rotulo
	local pai = rotulo.Parent
	if rotulo.BackgroundTransparency > 0.9 and pai and pai:IsA("GuiObject") and pai:FindFirstChildOfClass("UICorner") then
		local tamanho = pai.AbsoluteSize
		if tamanho.Y > 0 and tamanho.X <= tamanho.Y * 4 then -- tem jeito de tecla, não de linha inteira do menu
			moldura = pai
		end
	end
	local brilho = Instance.new("Frame") -- o "branquinho" de tecla apertada (começa invisível)
	brilho.Name = "BrilhoApertado"
	brilho.Size = UDim2.fromScale(1, 1)
	brilho.BackgroundColor3 = Color3.new(1, 1, 1)
	brilho.BackgroundTransparency = 1
	brilho.BorderSizePixel = 0
	brilho.ZIndex = rotulo.ZIndex - 1 -- (se a moldura for o pai, fica atrás da letra)
	local canto = moldura:FindFirstChildOfClass("UICorner")
	if canto then
		canto:Clone().Parent = brilho -- mesmo arredondado da tecla
	end
	brilho.Parent = moldura
	local escala: UIScale = moldura:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	escala.Parent = moldura
	return { brilho = brilho, escala = escala, escalaNormal = escala.Scale }
end

local function procurarMenu(menu: Instance?)
	table.clear(textosDoMenu)
	table.clear(teclasDoMenu)
	if menu == nil then
		return
	end
	for _, objeto in menu:GetDescendants() do
		if objeto:IsA("TextLabel") then
			local chave = simplificarTexto(objeto.Text)
			local texto, tecla = TEXTOS_PROCURADOS[chave], TECLAS_PROCURADAS[chave]
			if texto and textosDoMenu[texto] == nil then
				textosDoMenu[texto] = { rotulo = objeto, corNormal = objeto.TextColor3, giroNormal = objeto.Rotation }
			elseif tecla and teclasDoMenu[tecla] == nil then
				teclasDoMenu[tecla] = prepararTecla(objeto)
			end
		end
	end
	if not jaAvisouMenu then -- avisa uma vez o que não achou (para você saber o que renomear)
		jaAvisouMenu = true
		for _, nome in { "Buzina", "Nitro", "Freio De Mão" } do
			if textosDoMenu[nome] == nil then
				warn(`[Quadriciclo] Menu "Controles": não achei um texto escrito "{nome}".`)
			end
		end
		for nome, letra in TECLAS_OBRIGATORIAS do
			if teclasDoMenu[nome] == nil then
				warn(`[Quadriciclo] Menu "Controles": não achei a tecla escrita "{letra}".`)
			end
		end
	end
end

local function pintarTexto(nome: string, cor: Color3?, tremer: boolean)
	local item = textosDoMenu[nome]
	if item then
		item.rotulo.TextColor3 = cor or item.corNormal
		item.rotulo.Rotation = if tremer then item.giroNormal + math.sin(os.clock() * 45) * 4 else item.giroNormal
	end
end

local function apertarTecla(nome: string, apertada: boolean, dt: number)
	local tecla = teclasDoMenu[nome]
	if tecla then
		local suave = math.min(dt * 18, 1)
		local brilho = if apertada then 0.55 else 1
		local escala = if apertada then tecla.escalaNormal * 0.92 else tecla.escalaNormal
		tecla.brilho.BackgroundTransparency += (brilho - tecla.brilho.BackgroundTransparency) * suave
		tecla.escala.Scale += (escala - tecla.escala.Scale) * suave
	end
end

local function atualizarMenuDeTeclas(quad: Quadriciclo, dt: number)
	local tela = quad.tela
	if tela ~= telaDoMenu then -- HUD novo: procura o menu de novo
		local menu = if tela then tela:FindFirstChild("Controles", true) else nil
		if menu and menu:IsA("GuiObject") and menu.AbsoluteSize.Y <= 0 then
			return -- o HUD acabou de aparecer: espera 1 frame para ele ter tamanho
		end
		telaDoMenu = tela
		procurarMenu(menu)
	end

	-- BUZINA: amarela e tremendo enquanto toca; vermelha depois de 10 s seguidos.
	buzinaSegurandoHa = if quad.buzinaLigada then buzinaSegurandoHa + dt else 0
	local corBuzina: Color3? = nil
	if quad.buzinaLigada then
		corBuzina = if buzinaSegurandoHa >= BUZINA_MUITO_TEMPO then COR_TEXTO_VERMELHO else COR_TEXTO_AMARELO
	end
	pintarTexto("Buzina", corBuzina, quad.buzinaLigada)

	-- NITRO: verde ligado; vermelho no fim do tanque e até carregar o suficiente para usar de novo.
	local corNitro: Color3? = nil
	if (quad.nitroAtivo and quad.cargaNitro < NITRO_NO_FIM) or quad.nitroTravado or quad.cargaNitro < Nitro.MINIMO_PARA_LIGAR then
		corNitro = COR_TEXTO_VERMELHO
	elseif quad.nitroAtivo or quad.nitroPedido then
		corNitro = COR_TEXTO_VERDE
	end
	pintarTexto("Nitro", corNitro, false)

	-- FREIO DE MÃO: vermelho enquanto segura; treme só com o carro andando.
	local andando = quad.chassi.AssemblyLinearVelocity.Magnitude > Veiculo.PARADO
	pintarTexto("Freio De Mão", if quad.freioDeMao then COR_TEXTO_VERMELHO else nil, quad.freioDeMao and andando)

	-- TECLAS apertadas ficam branquinhas.
	apertarTecla("Buzina", quad.buzinaLigada, dt)
	apertarTecla("Nitro", quad.nitroPedido, dt)
	apertarTecla("Freio De Mão", quad.freioDeMao, dt)
	apertarTecla("Câmera", UserInputService:IsKeyDown(Enum.KeyCode.C), dt)
	apertarTecla("Gancho", quad.mirandoGancho, dt)
end

-- Sentou: o menu começa a reagir a cada frame.
function TeclasMenu.ligar(quad: Quadriciclo)
	conexaoMenu = RunService.PreRender:Connect(function(dt: number)
		atualizarMenuDeTeclas(quad, dt)
	end)
end

-- Levantou: tudo volta ao normal.
function TeclasMenu.desligar()
	local conexao = conexaoMenu
	if conexao then
		conexao:Disconnect()
	end
	conexaoMenu = nil
	for nome in textosDoMenu do
		pintarTexto(nome, nil, false)
	end
	for nome in teclasDoMenu do
		apertarTecla(nome, false, 1)
	end
end

return TeclasMenu

