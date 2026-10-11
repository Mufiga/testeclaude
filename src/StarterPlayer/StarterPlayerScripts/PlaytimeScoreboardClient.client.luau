--!optimize 2
--[[
	PlaytimeScoreboardClient
	------------------------
	LocalScript -> StarterPlayer > StarterPlayerScripts

	Cuidados com performance:
	  - A interface e montada UMA vez; depois so o texto muda.
	  - A SurfaceGui fica dentro da PlayerGui (Adornee), entao os elementos
	    da interface nao sao replicados pela rede pra todo mundo.
	  - MaxDistance faz a placa parar de ser desenhada de longe.
	  - Um unico loop de 1 segundo, e ele so faz algo se voce estiver perto.
	  - Texto so e escrito quando realmente mudou (setText).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("PlaytimeConfig"))
local remote = ReplicatedStorage:WaitForChild("PlaytimeBoardUpdate")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local palette = Config.Palette
local ROWS = math.max(1, Config.TopCount)
local GATE = Config.MaxRenderDistance > 0 and Config.MaxRenderDistance or math.huge

--------------------------------------------------------------------------
-- Tipos
--------------------------------------------------------------------------

-- Uma linha do ranking, do jeito que o servidor manda.
export type Entry = {
	userId: number,
	name: string?,
	display: string?,
	seconds: number,
	online: boolean?,
}

-- Os rotulos de uma linha ja montada na tela.
export type Row = {
	frame: Frame,
	badge: Frame,
	badgeLabel: TextLabel,
	avatar: ImageLabel?,
	name: TextLabel,
	time: TextLabel,
	userId: number, -- -1 = nunca desenhada, 0 = vaga vazia
}

export type Board = {
	adornee: BasePart,
	gui: SurfaceGui,
	rows: { Row },
	footerValue: TextLabel?,
}

--------------------------------------------------------------------------
-- Estado recebido do servidor
--------------------------------------------------------------------------

local state: {
	entries: { Entry },
	yourSeconds: number?,
	receivedAt: number,
} = {
	entries = {},
	yourSeconds = nil,
	receivedAt = os.clock(),
}

local boards: { [BasePart]: Board } = {}

--------------------------------------------------------------------------
-- Helpers de interface
--------------------------------------------------------------------------

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function setColor(object: any, property: string, color: Color3)
	if object[property] ~= color then
		object[property] = color
	end
end

local function corner(parent: Instance, radius: number)
	local ui = Instance.new("UICorner")
	ui.CornerRadius = UDim.new(radius, 0)
	ui.Parent = parent
	return ui
end

local function square(parent: Instance)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = parent
	return ratio
end

local function capTextSize(label: TextLabel, maxSize: number, minSize: number?)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.MinTextSize = minSize or 1
	constraint.Parent = label
end

-- UIFlexItem e recente; se nao existir, o layout continua funcionando.
local function fillRemaining(object: Instance)
	local ok, flex = pcall(Instance.new, "UIFlexItem")
	if ok and flex then
		flex.FlexMode = Enum.UIFlexMode.Fill
		flex.Parent = object
	end
end

local function newText(name: string, font: Enum.Font, color: Color3, maxSize: number, minSize: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextScaled = true
	label.RichText = false
	capTextSize(label, maxSize, minSize)
	return label
end

local function rankColor(rank: number): Color3
	if rank == 1 then
		return palette.Gold
	elseif rank == 2 then
		return palette.Silver
	elseif rank == 3 then
		return palette.Bronze
	end
	return palette.Rank
end

--------------------------------------------------------------------------
-- Montagem da placa (roda uma vez por placa)
--------------------------------------------------------------------------

local function buildBoard(adornee: BasePart): Board
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlaytimeBoardGui"
	gui.Adornee = adornee
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Config.PixelsPerStud
	gui.MaxDistance = Config.MaxRenderDistance
	gui.LightInfluence = Config.LightInfluence
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = palette.Panel
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.035, 0)
	padding.PaddingBottom = UDim.new(0.035, 0)
	padding.PaddingLeft = UDim.new(0.03, 0)
	padding.PaddingRight = UDim.new(0.03, 0)
	padding.Parent = root

	---------------------------------------------------------------- cabecalho
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.165)
	header.BackgroundColor3 = palette.WoodDark
	header.BorderSizePixel = 0
	header.Parent = root
	corner(header, 0.22)

	local headerShade = Instance.new("UIGradient")
	headerShade.Color = ColorSequence.new(
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(205, 205, 205)
	)
	headerShade.Rotation = 90
	headerShade.Parent = header

	local title = newText("Title", Config.TitleFont, palette.Panel, 40)
	title.Size = UDim2.fromScale(1, 0.58)
	title.Position = UDim2.fromScale(0, 0.08)
	title.Parent = header

	local subtitle = newText("Subtitle", Config.NameFont, palette.InkSoft, 16)
	subtitle.Size = UDim2.fromScale(1, 0.26)
	subtitle.Position = UDim2.fromScale(0, 0.66)
	subtitle.Text = string.format(Config.Subtitle, ROWS)
	subtitle.Parent = header
	setText(title, Config.Title)

	-- Faixa verde, puxando o verde da grama do cenario.
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.fromScale(1, 0.014)
	accent.Position = UDim2.fromScale(0, 0.183)
	accent.BackgroundColor3 = palette.Leaf
	accent.BorderSizePixel = 0
	accent.Parent = root
	corner(accent, 1)

	------------------------------------------------------------------- linhas
	local showFooter = Config.ShowYourTime == true

	local rowsFrame = Instance.new("Frame")
	rowsFrame.Name = "Rows"
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.Size = UDim2.fromScale(1, showFooter and 0.655 or 0.785)
	rowsFrame.Position = UDim2.fromScale(0, 0.215)
	rowsFrame.Parent = root

	local rowGap = 0.014
	local rowHeight = (1 - rowGap * (ROWS - 1)) / ROWS

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(rowGap, 0)
	list.Parent = rowsFrame

	local rows: { Row } = {}

	for i = 1, ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.fromScale(1, rowHeight)
		row.BackgroundColor3 = palette.PanelAlt
		row.BackgroundTransparency = (i % 2 == 0) and 1 or 0
		row.BorderSizePixel = 0
		row.Parent = rowsFrame
		corner(row, 0.3)

		local rowPadding = Instance.new("UIPadding")
		rowPadding.PaddingLeft = UDim.new(0.014, 0)
		rowPadding.PaddingRight = UDim.new(0.018, 0)
		rowPadding.Parent = row

		local rowList = Instance.new("UIListLayout")
		rowList.FillDirection = Enum.FillDirection.Horizontal
		rowList.VerticalAlignment = Enum.VerticalAlignment.Center
		rowList.SortOrder = Enum.SortOrder.LayoutOrder
		rowList.Padding = UDim.new(0.012, 0)
		rowList.Parent = row

		-- medalha / numero da posicao
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.LayoutOrder = 1
		badge.Size = UDim2.fromScale(0, 0.74)
		badge.BackgroundColor3 = rankColor(i)
		badge.BorderSizePixel = 0
		badge.Parent = row
		square(badge)
		corner(badge, 0.35)

		local badgeLabel = newText("Rank", Config.TimeFont, Color3.fromRGB(255, 255, 255), 20)
		badgeLabel.Size = UDim2.fromScale(1, 0.72)
		badgeLabel.Position = UDim2.fromScale(0, 0.14)
		badgeLabel.Text = tostring(i)
		badgeLabel.Parent = badge

		-- rostinho
		local avatar
		if Config.ShowAvatars then
			avatar = Instance.new("ImageLabel")
			avatar.Name = "Avatar"
			avatar.LayoutOrder = 2
			avatar.Size = UDim2.fromScale(0, 0.84)
			avatar.BackgroundColor3 = palette.PanelAlt
			avatar.BackgroundTransparency = 0.4
			avatar.BorderSizePixel = 0
			avatar.ImageTransparency = 1
			avatar.ScaleType = Enum.ScaleType.Fit
			avatar.Parent = row
			square(avatar)
			corner(avatar, 1)
		end

		local name = newText("PlayerName", Config.NameFont, palette.Ink, 24, 11)
		name.LayoutOrder = 3
		name.Size = UDim2.fromScale(0.3, 0.78)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = Config.EmptyText
		name.Parent = row
		fillRemaining(name)

		local time = newText("Time", Config.TimeFont, palette.Ink, 24)
		time.LayoutOrder = 4
		time.Size = UDim2.fromScale(0.26, 0.78)
		time.TextXAlignment = Enum.TextXAlignment.Right
		time.Text = Config.EmptyText
		time.Parent = row

		rows[i] = {
			frame = row,
			badge = badge,
			badgeLabel = badgeLabel,
			avatar = avatar,
			name = name,
			time = time,
			userId = -1,
		}
	end

	------------------------------------------------------------------ rodape
	local footerValue: TextLabel? = nil
	if showFooter then
		local footer = Instance.new("Frame")
		footer.Name = "Footer"
		footer.Size = UDim2.fromScale(1, 0.1)
		footer.Position = UDim2.fromScale(0, 0.9)
		footer.BackgroundColor3 = palette.Leaf
		footer.BorderSizePixel = 0
		footer.Parent = root
		corner(footer, 0.3)

		local footerPadding = Instance.new("UIPadding")
		footerPadding.PaddingLeft = UDim.new(0.03, 0)
		footerPadding.PaddingRight = UDim.new(0.03, 0)
		footerPadding.Parent = footer

		local footerLabel = newText("Label", Config.NameFont, Color3.fromRGB(255, 255, 255), 18)
		footerLabel.Size = UDim2.fromScale(0.45, 0.6)
		footerLabel.Position = UDim2.fromScale(0, 0.2)
		footerLabel.TextXAlignment = Enum.TextXAlignment.Left
		footerLabel.Text = Config.YourTimeLabel
		footerLabel.Parent = footer

		footerValue = newText("Value", Config.TimeFont, Color3.fromRGB(255, 255, 255), 26)
		footerValue.Size = UDim2.fromScale(0.55, 0.68)
		footerValue.Position = UDim2.fromScale(0.45, 0.16)
		footerValue.TextXAlignment = Enum.TextXAlignment.Right
		footerValue.Text = Config.EmptyText
		footerValue.Parent = footer
	end

	return {
		adornee = adornee,
		gui = gui,
		rows = rows,
		footerValue = footerValue,
	}
end

--------------------------------------------------------------------------
-- Desenho (so troca texto/cor, nunca cria instancias)
--------------------------------------------------------------------------

local function render(board: Board)
	local elapsed = os.clock() - state.receivedAt
	local entries = state.entries

	for i = 1, ROWS do
		local row = board.rows[i]
		local entry = entries[i]

		if entry then
			local seconds = entry.seconds + (entry.online and elapsed or 0)
			setText(row.name, entry.display or entry.name or Config.EmptyText)
			setText(row.time, Config.FormatShort(seconds))
			setColor(row.badge, "BackgroundColor3", rankColor(i))

			if row.avatar and row.userId ~= entry.userId then
				row.avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", entry.userId)
				row.avatar.ImageTransparency = 0
			end

			local isYou = entry.userId == localPlayer.UserId
			local transparency = isYou and 0 or ((i % 2 == 0) and 1 or 0)
			setColor(row.frame, "BackgroundColor3", isYou and palette.YouTint or palette.PanelAlt)
			if row.frame.BackgroundTransparency ~= transparency then
				row.frame.BackgroundTransparency = transparency
			end
			setColor(row.name, "TextColor3", isYou and palette.LeafDark or palette.Ink)
			setColor(row.time, "TextColor3", isYou and palette.LeafDark or palette.Ink)

			row.userId = entry.userId
		elseif row.userId ~= 0 then
			-- vaga vazia: fica elegante em vez de sumir
			row.userId = 0
			setText(row.name, Config.EmptyText)
			setText(row.time, Config.EmptyText)
			setColor(row.badge, "BackgroundColor3", palette.Rank)
			row.frame.BackgroundColor3 = palette.PanelAlt
			row.frame.BackgroundTransparency = (i % 2 == 0) and 1 or 0
			row.name.TextColor3 = palette.InkSoft
			row.time.TextColor3 = palette.InkSoft
			if row.avatar then
				row.avatar.ImageTransparency = 1
				row.avatar.Image = ""
			end
		end
	end

	if board.footerValue then
		if state.yourSeconds then
			setText(board.footerValue, Config.FormatLong(state.yourSeconds + elapsed))
		else
			setText(board.footerValue, Config.EmptyText)
		end
	end
end

local function renderAll()
	for _, board in boards do
		render(board)
	end
end

--------------------------------------------------------------------------
-- Entrada e saida de placas no mundo
--------------------------------------------------------------------------

local function addBoard(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	if boards[instance] then
		return
	end
	local board = buildBoard(instance)
	boards[instance] = board
	render(board)
end

local function removeBoard(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local board = boards[instance]
	if board then
		board.gui:Destroy()
		boards[instance] = nil
	end
end

for _, instance in CollectionService:GetTagged(Config.BoardTag) do
	addBoard(instance)
end
CollectionService:GetInstanceAddedSignal(Config.BoardTag):Connect(addBoard)
CollectionService:GetInstanceRemovedSignal(Config.BoardTag):Connect(removeBoard)

--------------------------------------------------------------------------
-- Dados do servidor
--------------------------------------------------------------------------

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	state.entries = payload.entries or state.entries
	if payload.you and type(payload.you.seconds) == "number" then
		state.yourSeconds = payload.you.seconds
	end
	state.receivedAt = os.clock()
	renderAll()
end)

--------------------------------------------------------------------------
-- Unico loop do cliente: 1x por segundo, e so se voce estiver perto
--------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(1)
		if next(boards) ~= nil then
			local origin = camera and camera.CFrame.Position
			if origin then
				for _, board in boards do
					if (board.adornee.Position - origin).Magnitude <= GATE then
						render(board)
					end
				end
			end
		end
	end
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	camera = workspace.CurrentCamera
end)
