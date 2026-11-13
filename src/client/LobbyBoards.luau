--!strict
-- The lobby's show pieces as each screen draws them (the server only makes the parts and publishes the numbers:
-- Leaderboards, LobbyExtras), in the game's style:
--   * the six holographic leaderboards in the lobby's middle: a striped header in the board's colour, then the top
--     10: rank, name, number. The top three ranks are gold, silver and bronze, your own row is cyan, and rows pop
--     when they change;
--   * the pedestals' plates: 1ST, 2ND, 3RD.
-- All of it is switched off while you're in a round (you can't read it from down there), so it costs nothing then.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ProgressRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressRules"))
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local PlasticUi = require(script.Parent.PlasticUi)

local LobbyBoards = {}

local player = Players.LocalPlayer

local PIXELS = 40 -- canvas pixels a stud
local HEAD_TALL = 86
local ROW_TALL = 50
local ROWS = 10
local NAME_MAX = 16
local WHITE = Color3.new(1, 1, 1)
local CYAN = Color3.fromHex("2EE6FF")
local PLACE_COLORS = { Color3.fromHex("FFD23A"), Color3.fromHex("DDE2EE"), Color3.fromHex("E8A06A") }
local PLACE_WORDS = { "1ST", "2ND", "3RD" }

type RowUi = {
	holder: Frame,
	scale: UIScale,
	rank: PlasticUi.Text,
	name: PlasticUi.Text,
	value: PlasticUi.Text,
	shown: string,
	popAt: number,
}
type BoardUi = { gui: SurfaceGui, rows: { RowUi }, empty: PlasticUi.Text, busyUntil: number }

local boards: { BoardUi } = {}
local guis: { SurfaceGui } = {}

local function surface(part: BasePart, name: string, pixels: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Adornee = part
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	table.insert(guis, gui)
	return gui
end

local function shorten(name: string): string
	if utf8.len(name) and (utf8.len(name) :: number) > NAME_MAX then
		local cut = utf8.offset(name, NAME_MAX)
		if cut then
			return string.sub(name, 1, cut - 1) .. "…"
		end
	end
	return name
end

local function buildBoard(part: BasePart)
	local wide = math.floor(part.Size.X * PIXELS)
	local tall = math.floor(part.Size.Y * PIXELS)
	local colorHex = part:GetAttribute(ProgressRules.ATTR_BOARD_COLOR)
	local color = Color3.fromHex(if type(colorHex) == "string" then colorHex else "2B6BFF")
	local heading = part:GetAttribute(ProgressRules.ATTR_BOARD_TITLE)
	local gui = surface(part, "Board_" .. part.Name, PIXELS)

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BackgroundColor3 = PlasticUi.PLATE
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Size = UDim2.fromOffset(wide, tall)
	back.Parent = gui
	local edge = PlasticUi.outline(back, 6)
	edge.Color = color

	local head = PlasticUi.stripedPlate("Head", wide, HEAD_TALL, PlasticUi.darker(color, 0.25))
	head.ZIndex = 2
	head.Parent = back
	local title = PlasticUi.text({ name = "Title", size = 30, parent = head, zIndex = 3 })
	title.root.Size = UDim2.fromScale(1, 1)
	title.label.TextScaled = true
	title.drop.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 38
	limit.Parent = title.label
	local limitDrop = limit:Clone()
	limitDrop.Parent = title.drop
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.Parent = title.root
	title:set(if type(heading) == "string" then heading else part.Name)

	local rows: { RowUi } = {}
	for i = 1, ROWS do
		local holder = Instance.new("Frame")
		holder.Name = "Row" .. i
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromOffset(wide / 2, HEAD_TALL + 8 + (i - 0.5) * ROW_TALL)
		holder.Size = UDim2.fromOffset(wide - 20, ROW_TALL - 6)
		holder.BackgroundColor3 = WHITE
		holder.BackgroundTransparency = if i % 2 == 1 then 0.88 else 0.94
		holder.BorderSizePixel = 0
		holder.ZIndex = 2
		holder.Visible = false
		holder.Parent = back
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		local rank = PlasticUi.text({
			name = "Rank",
			size = 26,
			parent = holder,
			zIndex = 3,
			color = PLACE_COLORS[i] or WHITE,
		})
		rank.root.Size = UDim2.fromOffset(64, ROW_TALL - 6)
		rank:set("#" .. i)
		local name = PlasticUi.text({
			name = "Name",
			size = 24,
			parent = holder,
			zIndex = 3,
			align = Enum.TextXAlignment.Left,
		})
		name.root.Position = UDim2.fromOffset(70, 0)
		name.root.Size = UDim2.fromOffset(wide - 20 - 70 - 120, ROW_TALL - 6)
		local value = PlasticUi.text({
			name = "Value",
			size = 26,
			parent = holder,
			zIndex = 3,
			color = color:Lerp(WHITE, 0.45),
			align = Enum.TextXAlignment.Right,
		})
		value.root.Position = UDim2.fromOffset(wide - 20 - 130, 0)
		value.root.Size = UDim2.fromOffset(120, ROW_TALL - 6)
		rows[i] = { holder = holder, scale = scale, rank = rank, name = name, value = value, shown = "", popAt = -math.huge }
	end
	local empty = PlasticUi.text({ name = "Empty", size = 26, parent = back, zIndex = 3 })
	empty.root.Position = UDim2.fromOffset(0, HEAD_TALL + 60)
	empty.root.Size = UDim2.fromOffset(wide, 80)
	empty.label.TextWrapped = true
	empty.drop.TextWrapped = true
	empty:set("NO ONE YET.\nBE THE FIRST!")

	local board: BoardUi = { gui = gui, rows = rows, empty = empty, busyUntil = 0 }
	table.insert(boards, board)

	local function redraw()
		local text = part:GetAttribute(ProgressRules.ATTR_BOARD_ROWS)
		local ok, list = pcall(function()
			return HttpService:JSONDecode(if type(text) == "string" then text else "[]")
		end)
		local entries: { any } = if ok and type(list) == "table" then list else {}
		local now = os.clock()
		empty.root.Visible = #entries == 0
		for i, row in rows do
			local entry = entries[i]
			if type(entry) == "table" then
				local who = shorten(tostring(entry.n))
				local amount = ProgressRules.short(if type(entry.v) == "number" then entry.v else 0)
				local key = `{who}|{amount}`
				row.holder.Visible = true
				if key ~= row.shown then
					row.shown = key
					row.name:set(who)
					row.name:setColor(if entry.u == player.UserId then CYAN else WHITE)
					row.value:set(amount)
					row.popAt = now + (i - 1) * 0.04
					board.busyUntil = math.max(board.busyUntil, row.popAt + 0.4)
				end
			else
				row.holder.Visible = false
				row.shown = ""
			end
		end
	end
	part:GetAttributeChangedSignal(ProgressRules.ATTR_BOARD_ROWS):Connect(redraw)
	redraw()
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function buildPlate(part: BasePart)
	local place = part:GetAttribute(ProgressRules.ATTR_PLACE)
	if type(place) ~= "number" or not PLACE_WORDS[place] then
		return
	end
	local gui = surface(part, "Pedestal" .. place, 50)
	local words = PlasticUi.text({ name = "Place", size = 84, parent = gui, zIndex = 2 })
	words.root.Size = UDim2.fromScale(1, 1)
	words.label.TextScaled = true
	words.drop.TextScaled = true
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.1, 0)
	pad.PaddingRight = UDim.new(0.1, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = words.root
	words:set(PLACE_WORDS[place])
	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Builds on every part in a folder that `wants` it, as they come.
local function watch(folderName: string, build: (part: BasePart) -> ())
	task.spawn(function()
		local folder = Workspace:WaitForChild(folderName, 120)
		if not folder then
			return
		end
		local function consider(child: Instance)
			if child:IsA("BasePart") then
				local ok, problem = pcall(build, child)
				if not ok then
					warn(`[Tag Rivals] a lobby board couldn't be drawn: {problem}`)
				end
			end
		end
		folder.ChildAdded:Connect(function(child)
			task.defer(consider, child)
		end)
		for _, child in folder:GetChildren() do
			consider(child)
		end
	end)
end

function LobbyBoards.start()
	watch(ProgressRules.BOARDS, buildBoard)
	watch(ProgressRules.EXTRAS, function(part: BasePart)
		if part.Name == "Pedestal" then
			buildPlate(part)
		end
	end)

	local since = 0
	local on = true
	RunService.PreRender:Connect(function(dt: number)
		since += dt
		if since >= 0.5 then
			since = 0
			local want = player:GetAttribute(RoundRules.ATTR_IN_ROUND) ~= true
			if want ~= on then
				on = want
				for _, gui in guis do
					gui.Enabled = on
				end
			end
			for _, gui in guis do
				if gui.Enabled ~= on then
					gui.Enabled = on -- (one built since)
				end
			end
		end
		if not on then
			return
		end
		-- rows pop when they change
		local now = os.clock()
		for _, board in boards do
			if now < board.busyUntil + 0.05 then
				for _, row in board.rows do
					local age = now - row.popAt
					row.scale.Scale = if age >= 0 and age < 0.3 then 1 + 0.1 * math.sin(math.pi * age / 0.3) else 1
				end
			end
		end
	end)
end

return LobbyBoards
