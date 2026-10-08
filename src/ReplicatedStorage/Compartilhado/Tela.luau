--!strict
--[[
	=====================================================================
	Tela  (ModuleScript)
	Local: ReplicatedStorage > Compartilhado > Tela
	=====================================================================

	O TAMANHO dos HUDs e o JEITO DE JOGAR de cada aparelho (usado por todos os HUDs):
	  - Tela.escala() ........ 1 no computador; menor no celular e no tablet (a tela é pequena e os
	                           dedos tampam). Também diminui num computador com a janela bem pequena.
	  - Tela.encolher(hud) ... coloca esse tamanho num HUD (e acerta sozinho se a tela mudar, por
	                           exemplo quando o celular gira).
	  - Tela.tamanho(34) ..... um número (ex.: o tamanho de um texto) já no tamanho certo da tela.
	  - Tela.noToque() ....... o jogador está jogando pela tela de toque (celular/tablet)?
	  - Tela.noControle() .... o jogador está jogando com controle (videogame)?
	Quer os HUDs ainda menores (ou maiores) no celular? Mude os AJUSTES aqui embaixo: vale para todos.
]]

local UserInputService = game:GetService("UserInputService")

local Tela = {}

-- =====================================================================
-- AJUSTES (1 = o tamanho normal, o do computador)
-- =====================================================================
local TAMANHO_TELA_PEQUENA = 0.65 -- numa tela com 400 pixels de altura (celular deitado)
local ALTURA_TELA_PEQUENA = 400 -- (pixels) até esta altura, vale o TAMANHO_TELA_PEQUENA
local ALTURA_TELA_NORMAL = 800 -- (pixels) desta altura para cima, tamanho normal (no meio, fica no meio)
local TAMANHO_MAXIMO_NO_TOQUE = 0.85 -- com tela de toque (celular/tablet), nunca maior que isso

-- =====================================================================
-- QUE APARELHO É ESTE?
-- =====================================================================
-- Jogando pela tela de toque (celular ou tablet)?
function Tela.noToque(): boolean
	local preferido = UserInputService.PreferredInput
	if preferido == Enum.PreferredInput.Touch then
		return true
	end
	-- (logo que o jogo abre, o Roblox ainda pode não ter decidido: celular = toque e sem mouse)
	return preferido ~= Enum.PreferredInput.Gamepad and UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Jogando com controle (Xbox, PlayStation ou um controle ligado no computador/celular)?
function Tela.noControle(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end

-- =====================================================================
-- O TAMANHO
-- =====================================================================
function Tela.escala(): number
	local camera = workspace.CurrentCamera
	local altura = if camera then camera.ViewportSize.Y else 0
	if altura < 100 then
		-- (a câmera ainda não sabe o tamanho da tela: chuta pelo aparelho; acerta logo depois)
		return if Tela.noToque() then TAMANHO_TELA_PEQUENA else 1
	end
	local t = math.clamp((altura - ALTURA_TELA_PEQUENA) / (ALTURA_TELA_NORMAL - ALTURA_TELA_PEQUENA), 0, 1)
	local escala = TAMANHO_TELA_PEQUENA + (1 - TAMANHO_TELA_PEQUENA) * t
	if Tela.noToque() then
		escala = math.min(escala, TAMANHO_MAXIMO_NO_TOQUE)
	end
	return escala
end

-- Um número no tamanho da tela de agora. Ex.: Tela.tamanho(34) = 34 no computador, 22 no celular.
function Tela.tamanho(pixels: number): number
	return math.floor(pixels * Tela.escala() + 0.5)
end

-- Os HUDs encolhidos e o tamanho "de verdade" de cada um (para recalcular quando a tela muda).
local encolhidos: { [UIScale]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Deixa este HUD (e tudo dentro dele) no tamanho da tela. Ele encolhe em volta do AnchorPoint dele.
-- (Se ele já tiver um UIScale, usa o mesmo: o tamanho dele vira "o normal" e é multiplicado.)
function Tela.encolher(hud: GuiObject): UIScale
	local achada = hud:FindFirstChildOfClass("UIScale")
	local escala: UIScale
	if achada then
		escala = achada
	else
		escala = Instance.new("UIScale")
		escala.Name = "TamanhoDaTela"
		escala.Parent = hud
	end
	local normal = encolhidos[escala] or escala.Scale
	encolhidos[escala] = normal
	escala.Scale = normal * Tela.escala()
	return escala
end

-- A tela mudou (girou o celular, mudou o tamanho da janela, trocou para o toque): acerta todos.
local function reaplicar()
	local fator = Tela.escala()
	for escala, normal in encolhidos do
		escala.Scale = normal * fator
	end
end

local conexaoDaCamera: RBXScriptConnection? = nil
local function vigiarCamera()
	local antiga = conexaoDaCamera
	if antiga then
		antiga:Disconnect()
	end
	conexaoDaCamera = nil
	local camera = workspace.CurrentCamera
	if camera then
		conexaoDaCamera = camera:GetPropertyChangedSignal("ViewportSize"):Connect(reaplicar)
	end
	reaplicar()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(vigiarCamera)
UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(reaplicar)
vigiarCamera()

return Tela
