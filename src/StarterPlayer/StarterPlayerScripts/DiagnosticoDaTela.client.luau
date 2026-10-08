--!strict
--[[
	=====================================================================
	DiagnosticoDaTela  (LocalScript) — SÓ FUNCIONA NO STUDIO
	Local: StarterPlayer > StarterPlayerScripts > DiagnosticoDaTela
	=====================================================================

	Procura o que está CORTADO ou ESCONDIDO na tela e escreve no Output (em amarelo, começando com
	"[Tela]"). Feito para usar com o emulador de celular: Test › Device, escolha um aparelho, dê Play,
	sente num veículo e olhe o Output. Ele avisa:
	  - um pedaço de HUD que passa da borda da tela (ou da área segura: o entalhe do celular, a
	    barrinha de baixo do iPhone, a barra do Roblox em cima);
	  - um texto que não cabe na caixa dele (aparece cortado ou com "...");
	  - um botão da tela do celular (BotoesDoCelular) em cima de outro HUD (ex.: o seu HUDQuadriciclo);
	  - os botões AUTOMÁTICOS do Roblox na tela: sinal de que algum script antigo ainda cria botões.
	Quando muda a tela (outro aparelho, girou, trocou para o toque), ele escreve o tamanho da tela e
	procura de novo. Se estiver tudo certo, escreve "Nada cortado nesta tela".

	Algum HUD seu sai da tela DE PROPÓSITO (um efeito)? Coloque nele o atributo PodeSairDaTela = true
	(Properties › Attributes › +, tipo boolean): ele e o que tem dentro deixam de ser conferidos.

	No jogo publicado ele não faz nada. Pode apagar este script quando quiser: ele não muda o jogo.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	return -- (no jogo publicado, não faz nada)
end

local Tela = require(ReplicatedStorage:WaitForChild("Compartilhado"):WaitForChild("Tela"))
local jogador = Players.LocalPlayer :: Player
local playerGui = jogador:WaitForChild("PlayerGui") :: PlayerGui

local INTERVALO = 2 -- (segundos) de quanto em quanto tempo ele olha a tela
local FOLGA = 3 -- (pixels) passar da borda menos que isso não conta
local SOBREPOSICAO = 0.15 -- um botão do celular cobrindo mais que 15% de outro HUD = avisa
local TELAS_DO_ROBLOX = { TouchGui = true, ContextActionGui = true, Freecam = true } -- (não são suas)
-- Efeitos que passam da borda de propósito (os riscos de velocidade saem um pouco da tela).
local TELAS_IGNORADAS = { EfeitoVelocidade = true, MedidorDaTela = true }

-- Uma tela vazia, só para medir a ÁREA SEGURA (o que sobra sem o entalhe e a barra do Roblox).
local medidor = Instance.new("ScreenGui")
medidor.Name = "MedidorDaTela"
medidor.ResetOnSpawn = false
medidor.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
medidor.Parent = playerGui

type Retangulo = { x0: number, y0: number, x1: number, y1: number }

local function retanguloDe(posicao: Vector2, tamanho: Vector2): Retangulo
	return { x0 = posicao.X, y0 = posicao.Y, x1 = posicao.X + tamanho.X, y1 = posicao.Y + tamanho.Y }
end

local function cruzar(a: Retangulo, b: Retangulo): Retangulo?
	local r = { x0 = math.max(a.x0, b.x0), y0 = math.max(a.y0, b.y0), x1 = math.min(a.x1, b.x1), y1 = math.min(a.y1, b.y1) }
	if r.x1 - r.x0 <= 0 or r.y1 - r.y0 <= 0 then
		return nil
	end
	return r
end

local function area(r: Retangulo): number
	return (r.x1 - r.x0) * (r.y1 - r.y0)
end

local function nomeCurto(objeto: Instance): string
	local completo = objeto:GetFullName()
	local inicio = playerGui:GetFullName() .. "."
	if string.sub(completo, 1, #inicio) == inicio then
		return string.sub(completo, #inicio + 1)
	end
	return completo
end

-- Onde o TEXTO aparece de verdade (numa caixa sem fundo, só o texto conta, não a caixa inteira).
local function retanguloDoTexto(caixa: Retangulo, limites: Vector2, alinhamentoX: Enum.TextXAlignment, alinhamentoY: Enum.TextYAlignment): Retangulo
	local largura = math.min(limites.X, caixa.x1 - caixa.x0)
	local altura = math.min(limites.Y, caixa.y1 - caixa.y0)
	local x0 = if alinhamentoX == Enum.TextXAlignment.Left then caixa.x0
		elseif alinhamentoX == Enum.TextXAlignment.Right then caixa.x1 - largura
		else (caixa.x0 + caixa.x1 - largura) / 2
	local y0 = if alinhamentoY == Enum.TextYAlignment.Top then caixa.y0
		elseif alinhamentoY == Enum.TextYAlignment.Bottom then caixa.y1 - altura
		else (caixa.y0 + caixa.y1 - altura) / 2
	return { x0 = x0, y0 = y0, x1 = x0 + largura, y1 = y0 + altura }
end

-- O pedaço VISÍVEL deste objeto (ou nil se ele não mostra nada), e se o texto dele não cabe.
local function oQueAparece(objeto: GuiObject): (Retangulo?, string?)
	local caixa = retanguloDe(objeto.AbsolutePosition, objeto.AbsoluteSize)
	local temFundo = objeto.BackgroundTransparency < 0.98
	local texto: string? = nil
	local textoCabe = true
	local limites, alinhamentoX, alinhamentoY = Vector2.zero, Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
	if objeto:IsA("TextLabel") or objeto:IsA("TextButton") or objeto:IsA("TextBox") then
		if objeto.Text ~= "" and objeto.TextTransparency < 0.98 then
			texto = objeto.Text
			-- (com "..." de propósito, o TextTruncate, não conta como cortado)
			textoCabe = objeto.TextFits or objeto.TextTruncate ~= Enum.TextTruncate.None
			limites, alinhamentoX, alinhamentoY = objeto.TextBounds, objeto.TextXAlignment, objeto.TextYAlignment
		end
	end
	local problemaDoTexto = if texto and not textoCabe then `o texto "{texto}" não cabe na caixa dele` else nil
	if temFundo or objeto:IsA("ViewportFrame") then
		return caixa, problemaDoTexto
	end
	if (objeto:IsA("ImageLabel") or objeto:IsA("ImageButton")) and objeto.Image ~= "" and objeto.ImageTransparency < 0.98 then
		return caixa, problemaDoTexto
	end
	if texto then
		return retanguloDoTexto(caixa, limites, alinhamentoX, alinhamentoY), problemaDoTexto
	end
	return nil, nil
end

-- =====================================================================
-- OLHAR A TELA
-- =====================================================================
type Problemas = { [string]: string } -- chave → a frase do aviso
type Pedaco = { nome: string, retangulo: Retangulo, tela: string }

local function procurar(): Problemas
	local problemas: Problemas = {}
	local conteudos: { Pedaco } = {} -- o que aparece (de todas as telas), para ver o que fica embaixo dos botões
	local botoesDoCelular: { Pedaco } = {}

	local function percorrer(pai: Instance, recorte: Retangulo?, areaDaTela: Retangulo, nomeDaTela: string, doRoblox: boolean)
		for _, filho in pai:GetChildren() do
			if not filho:IsA("GuiObject") or not filho.Visible or filho:GetAttribute("PodeSairDaTela") == true then
				continue
			end
			local aparece, problemaDoTexto = oQueAparece(filho)
			local visivel = aparece
			if visivel and recorte then
				visivel = cruzar(visivel, recorte) -- (uma lista que rola ou um quadro que corta o que sai dele)
			end
			if visivel and not doRoblox then
				local nome = nomeCurto(filho)
				local fora = math.max(areaDaTela.x0 - visivel.x0, visivel.x1 - areaDaTela.x1, areaDaTela.y0 - visivel.y0, visivel.y1 - areaDaTela.y1)
				if fora > FOLGA then
					problemas["fora:" .. nome] = `{nome} passa {math.floor(fora)} pixels da borda da tela (fica cortado)`
				end
				if problemaDoTexto then
					problemas["texto:" .. nome] = `{nome}: {problemaDoTexto}`
				end
			end
			if visivel then
				local pedaco = { nome = nomeCurto(filho), retangulo = visivel, tela = nomeDaTela }
				if nomeDaTela == "BotoesDoCelular" and filho:IsA("TextButton") then
					table.insert(botoesDoCelular, pedaco)
				else
					table.insert(conteudos, pedaco)
				end
			end
			local recorteDosFilhos = recorte
			if filho:IsA("ScrollingFrame") or filho:IsA("CanvasGroup") or filho.ClipsDescendants then
				local proprio = retanguloDe(filho.AbsolutePosition, filho.AbsoluteSize)
				recorteDosFilhos = if recorte then cruzar(proprio, recorte) else proprio
			end
			if recorteDosFilhos ~= nil or recorte == nil then
				percorrer(filho, recorteDosFilhos, areaDaTela, nomeDaTela, doRoblox)
			end
		end
	end

	for _, tela in playerGui:GetChildren() do
		if tela:IsA("ScreenGui") and tela.Enabled and not TELAS_IGNORADAS[tela.Name] then
			local areaDaTela = retanguloDe(tela.AbsolutePosition, tela.AbsoluteSize)
			percorrer(tela, nil, areaDaTela, tela.Name, TELAS_DO_ROBLOX[tela.Name] == true)
		end
	end

	-- Os botões do celular em cima de outro HUD (o botão é redondo: conta só o miolo dele).
	local camera = workspace.CurrentCamera
	local tamanhoDaTela = if camera then camera.ViewportSize else Vector2.zero
	local areaTotal = tamanhoDaTela.X * tamanhoDaTela.Y
	for _, botao in botoesDoCelular do
		local r = botao.retangulo
		local miolo = (r.x1 - r.x0) * 0.15
		local redondo = { x0 = r.x0 + miolo, y0 = r.y0 + miolo, x1 = r.x1 - miolo, y1 = r.y1 - miolo }
		for _, outro in conteudos do
			if outro.tela == "BotoesDoCelular" or area(outro.retangulo) > areaTotal * 0.3 then
				continue -- (os próprios botões, e fundos que cobrem quase a tela toda)
			end
			local junto = cruzar(redondo, outro.retangulo)
			if junto and area(junto) > SOBREPOSICAO * math.min(area(redondo), area(outro.retangulo)) then
				local nomeDoBotao = string.match(botao.nome, "[^%.]+$") or botao.nome
				problemas["junto:" .. botao.nome .. outro.nome] = `o botão {nomeDoBotao} (BotoesDoCelular) fica em cima de {outro.nome}`
			end
		end
	end

	-- Os botões AUTOMÁTICOS do Roblox (ContextActionService com "true"): quem cria?
	local automaticos = playerGui:FindFirstChild("ContextActionGui")
	if automaticos and automaticos:IsA("ScreenGui") and automaticos.Enabled then
		local titulos: { string } = {}
		for _, objeto in automaticos:GetDescendants() do
			if objeto:IsA("TextLabel") and objeto.Name == "ActionTitle" and objeto.Text ~= "" then
				local botao = objeto.Parent
				if botao and botao:IsA("GuiObject") and botao.Visible and botao.Parent ~= nil then
					table.insert(titulos, objeto.Text)
				end
			end
		end
		if #titulos > 0 then
			table.sort(titulos)
			problemas["automaticos"] = `botões AUTOMÁTICOS do Roblox na tela ({table.concat(titulos, ", ")}): algum script`
				.. " ainda cria botões com ContextActionService (o \"true\"). Confira se TODOS os scripts da"
				.. " Atualização 2 foram trocados (veja o README)."
		end
	end
	return problemas
end

-- =====================================================================
-- ESCREVER NO OUTPUT (só o que aparece em DUAS olhadas seguidas: animações não contam)
-- =====================================================================
local avisados: { [string]: boolean } = {}
local vistosAntes: Problemas = {}
local configuracao = ""
local precisaDizerQueEstaCerto = false

local function descreverTela(): string
	local camera = workspace.CurrentCamera
	local tamanho = if camera then camera.ViewportSize else Vector2.zero
	local segura = medidor.AbsoluteSize
	return string.format("%d × %d pixels (área segura %d × %d) · jogando com: %s · tamanho dos HUDs: %.2f",
		math.floor(tamanho.X), math.floor(tamanho.Y), math.floor(segura.X), math.floor(segura.Y),
		UserInputService.PreferredInput.Name, Tela.escala())
end

local function olhar()
	local agora = descreverTela()
	if agora ~= configuracao then
		configuracao = agora
		table.clear(avisados)
		table.clear(vistosAntes)
		precisaDizerQueEstaCerto = true
		print("[Tela] " .. agora)
		return -- (espera a próxima olhada: a tela acabou de mudar)
	end
	local problemas = procurar()
	local novos = 0
	for chave, frase in problemas do
		if vistosAntes[chave] and not avisados[chave] then
			avisados[chave] = true
			novos += 1
			warn("[Tela] " .. frase)
		end
	end
	vistosAntes = problemas
	if precisaDizerQueEstaCerto and next(problemas) == nil then
		precisaDizerQueEstaCerto = false
		print("[Tela] Nada cortado nesta tela.")
	elseif novos > 0 then
		precisaDizerQueEstaCerto = false
	end
end

while true do
	task.wait(INTERVALO)
	xpcall(olhar, function(erro: unknown)
		warn("[Tela] O diagnóstico teve um erro (o jogo continua normal): " .. tostring(erro))
	end)
end
