--!strict
-- The tag feed (owner 2026-11-09: "a kill-feed style list of tags, e.g. 'Chaser [knife icon] Runner'"; restyled
-- 2026-11-10 from the owner's picture, "Add these": "Bot 22 [lightning] ELIMINATED Bot Pixel" on dark glass with a
-- neon pink edge). Each tag slides in as a row sized to its words: the chaser's name in white, a little lightning bolt,
-- TAGGED in gold going orange (DASH TAG for a dash tag), the runner's name in cyan. Someone who fell off a cut strip
-- gets "Name [bolt] FELL OFF!" in red. Rows involving you have a gold edge. New ones push the old ones down; each fades
-- after FEED_SHOW seconds.
-- Everything moves: the rows bob out of step, a light runs round each edge, the bolts flicker.
-- Where it goes (HudLayout; owner 2026-11-10: "clean up the mobile ui abit"): on the right, under the timer's level,
-- with as many rows as fit above the coin counter. On a phone there's no room there (the coin counter and the Dash
-- button fill the right side), so it moves to the left, under Roblox's own buttons: up to 3 rows, sliding in from the
-- left, a little bigger to read, and narrow enough to stay clear of the timer and the pop-ups under it. The rows fade
-- away when the end screen comes in, which has the round's top chasers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)

local T = Config.Tag
local NEON = Config.Neon

local TagFeed = {}

local player = Players.LocalPlayer
local RoundRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent

local ROW_WIDE = 320 -- a row's widest at full size, where there's room (each row is as wide as its words)
local ROW_NARROW = 200 -- never narrower than this (a small phone's left side)
local ROW_TALL = 34
local ROW_GAP = 6
local TOP = 132 -- pixels from the top on the right, under the timer's level (times the HUD's size)
local NAME_TEXT = 17
local VERB_TEXT = 15 -- TAGGED / FELL OFF!
local PAD_X = 12 -- pixels from a row's edge to its words
local GLOW = 9 -- pixels the neon edge's glow reaches out round a row
local BOLT_WIDE, BOLT_TALL = 15, 20
local SIZE = 0.9 -- the rows' size, share of the rest of the HUD's
local SIZE_SMALL = 1 -- on a phone, so the names stay readable
local RIGHT_ROWS_MIN = 3 -- fewer rows than this fit on the right: it goes left
local LEFT_ROWS = 3 -- rows on the left
local CHASER = Color3.new(1, 1, 1)
local RUNNER = Color3.fromHex("2EE6FF")
local EDGE = Color3.fromHex("FF4FC8") -- the neon edge
local EDGE_YOU = PlasticUi.GOLD
local GLASS = Color3.fromHex("140E30")
local VERB_TAG = { Color3.fromHex("FFE85E"), Color3.fromHex("FF9A1F") } -- top and bottom of TAGGED
local VERB_FELL = { Color3.fromHex("FF8A5C"), Color3.fromHex("FF2B3A") }

type Row = {
	frame: CanvasGroup,
	glint: UIGradient,
	bolt: ImageLabel,
	wide: number,
	born: number,
	slot: number,
	phase: number,
}

-- Where the feed goes on this screen.
type Plan = {
	left: boolean, -- on the left (a phone) rather than the right
	x: number, -- its outer edge: screen pixels from that side
	top: number,
	size: number, -- how big the rows are drawn
	wide: number, -- a new row's width, pixels at full size
	rows: number, -- rows shown at most
}

local rows: { Row } = {}

-- How wide `text` is in the HUD's font at `size` (pixels at full size).
local widths: { [string]: number } = {}
local function textWidth(text: string, size: number): number
	local key = size .. "|" .. text
	local known = widths[key]
	if known then
		return known
	end
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = PlasticUi.FONT
	params.Size = size
	params.Width = 100000
	local ok, bounds = pcall(function()
		return TextService:GetTextBoundsAsync(params)
	end)
	-- a little more for the italic's lean and the outline
	local wide = (if ok then bounds.X else #text * size * 0.62) + size * 0.25
	widths[key] = wide
	return wide
end

-- Words in a row, `x` pixels from its left, `wide` across.
local function words(parent: Instance, text: string, size: number, color: Color3, x: number, wide: number): PlasticUi.Text
	local label = PlasticUi.text({ name = "Words", size = size, parent = parent, color = color, zIndex = 4 })
	label.root.AnchorPoint = Vector2.new(0, 0.5)
	label.root.Position = UDim2.new(0, x, 0.5, -1)
	label.root.Size = UDim2.fromOffset(wide, size + 6)
	label.label.TextXAlignment = Enum.TextXAlignment.Left
	label.drop.TextXAlignment = Enum.TextXAlignment.Left
	label.label.TextTruncate = Enum.TextTruncate.AtEnd
	label.drop.TextTruncate = Enum.TextTruncate.AtEnd
	label:set(text)
	return label
end

-- A gold-to-orange (or orange-to-red) fill down the verb's letters.
local function verbFill(label: TextLabel, colors: { Color3 })
	label.TextColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(colors[1], colors[2])
	gradient.Parent = label
end

-- Where the feed goes on this screen: on the right if enough rows fit above the coin counter (and the phone Dash
-- button), else on the left.
local function plan(): Plan
	local scale = PlasticUi.screenScale()
	local size = scale * (if HudLayout.small() then SIZE_SMALL else SIZE)
	local step = (ROW_TALL + ROW_GAP) * size
	local top = TOP * scale
	-- rows that fit above the coin counter and the phone Dash button, on the right
	local fit = T.FEED_MAX
	for _, name in { "Coin", "DashButton" } do
		local piece = HudLayout.get(name)
		if piece then
			fit = math.min(fit, math.floor((piece.top - HudLayout.GAP - top + ROW_GAP * size) / step))
		end
	end
	if fit >= RIGHT_ROWS_MIN then
		return { left = false, x = HudLayout.EDGE, top = top, size = size, wide = ROW_WIDE, rows = fit }
	end
	-- on the left, under Roblox's buttons, clear of the timer (and so of the pop-ups, which are drawn about as wide)
	local timer = HudLayout.get("Timer")
	local room = (if timer then timer.left else HudLayout.screen().X / 2 - 130 * scale) - HudLayout.GAP - HudLayout.EDGE
	return {
		left = true,
		x = HudLayout.EDGE,
		top = HudLayout.robloxButtonsBottom() + HudLayout.GAP / 2,
		size = size,
		wide = math.clamp(room / size, ROW_NARROW, ROW_WIDE),
		rows = math.min(LEFT_ROWS, T.FEED_MAX),
	}
end

-- One row: `first` (white or cyan), the bolt, `verb` in `verbColors`, then `second` (cyan; may be nil). `mine` gives
-- it the gold edge. At most `wide` pixels across (names are cut short to fit).
local function addRow(
	holder: Frame,
	wide: number,
	first: string,
	firstColor: Color3,
	verb: string,
	verbColors: { Color3 },
	second: string?,
	mine: boolean
)
	local firstWide = textWidth(first, NAME_TEXT)
	local verbWide = textWidth(verb, VERB_TEXT)
	local secondWide = if second then textWidth(second, NAME_TEXT) else 0
	local fixed = PAD_X * 2 + 6 + BOLT_WIDE + 5 + verbWide + (if second then 8 else 0)
	-- too long: the names share what's left
	local namesRoom = wide - GLOW * 2 - fixed
	if firstWide + secondWide > namesRoom then
		local k = math.max(namesRoom, 40) / (firstWide + secondWide)
		firstWide *= k
		secondWide *= k
	end
	local rowWide = fixed + firstWide + secondWide

	local frame = Instance.new("CanvasGroup")
	frame.Name = "Tag"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(rowWide + GLOW * 2, ROW_TALL + GLOW * 2)
	frame.Position = UDim2.fromOffset(wide + 40, 0)
	frame.GroupTransparency = 0

	-- dark glass with rounded corners
	local glass = Instance.new("Frame")
	glass.Name = "Glass"
	glass.Position = UDim2.fromOffset(GLOW, GLOW)
	glass.Size = UDim2.fromOffset(rowWide, ROW_TALL)
	glass.BackgroundColor3 = GLASS
	glass.BackgroundTransparency = 0.12
	glass.BorderSizePixel = 0
	glass.ZIndex = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = glass
	glass.Parent = frame

	-- the neon edge with its glow, and a light that runs along it
	local edge = Instance.new("ImageLabel")
	edge.Name = "Edge"
	edge.BackgroundTransparency = 1
	edge.Size = UDim2.fromScale(1, 1)
	edge.Image = NEON.ROW
	edge.ScaleType = Enum.ScaleType.Slice
	edge.SliceCenter = NEON.ROW_SLICE
	edge.SliceScale = 0.5
	edge.ZIndex = 2
	local tint = if mine then EDGE_YOU else EDGE
	local glint = Instance.new("UIGradient")
	glint.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tint),
		ColorSequenceKeypoint.new(0.42, tint),
		ColorSequenceKeypoint.new(0.5, tint:Lerp(Color3.new(1, 1, 1), 0.8)),
		ColorSequenceKeypoint.new(0.58, tint),
		ColorSequenceKeypoint.new(1, tint),
	})
	glint.Parent = edge
	edge.Parent = frame

	local x = GLOW + PAD_X
	words(frame, first, NAME_TEXT, firstColor, x, firstWide)
	x += firstWide + 6
	local bolt = Instance.new("ImageLabel")
	bolt.Name = "Bolt"
	bolt.AnchorPoint = Vector2.new(0, 0.5)
	bolt.Position = UDim2.new(0, x - 3, 0.5, 0)
	bolt.Size = UDim2.fromOffset(BOLT_WIDE + 6, BOLT_TALL + 6)
	bolt.BackgroundTransparency = 1
	bolt.Image = NEON.BOLT
	bolt.ZIndex = 4
	bolt.Parent = frame
	x += BOLT_WIDE + 5
	local verbLabel = words(frame, verb, VERB_TEXT, Color3.new(1, 1, 1), x, verbWide)
	verbFill(verbLabel.label, verbColors)
	x += verbWide + 8
	if second then
		words(frame, second, NAME_TEXT, RUNNER, x, secondWide)
	end
	frame.Parent = holder

	for _, row in rows do
		row.slot += 1
	end
	table.insert(rows, 1, {
		frame = frame,
		glint = glint,
		bolt = bolt,
		wide = rowWide + GLOW * 2,
		born = os.clock(),
		slot = 0,
		phase = math.random(),
	})
	while #rows > T.FEED_MAX do
		local old = table.remove(rows) :: Row
		old.frame:Destroy()
	end
end

-- A tag: "Chaser [bolt] TAGGED Runner".
local function add(info: any, holder: Frame, wide: number)
	local mine = info.chaser == player or info.runner == player
	local verb = if info.dash == true then "DASH TAG" else "TAGGED"
	addRow(holder, wide, tostring(info.chaserName), CHASER, verb, VERB_TAG, tostring(info.runnerName), mine)
end

-- Someone fell off a cut strip: "Name [bolt] FELL OFF!" (cyan for a runner, who's a chaser now; white for a chaser).
local function addFell(info: any, holder: Frame, wide: number)
	local color = if info.runner == true then RUNNER else CHASER
	addRow(holder, wide, tostring(info.name), color, "FELL OFF!", VERB_FELL, nil, info.who == player)
end

-- Back-eased slide in from the side over SLIDE_TIME (a little overshoot): how far out it still is.
local SLIDE_TIME = 0.35
local function slideOut(age: number, wide: number): number
	local x = math.clamp(age / SLIDE_TIME, 0, 1)
	local c = 1.70158
	local eased = 1 + (c + 1) * (x - 1) ^ 3 + c * (x - 1) ^ 2
	return (wide + 40) * (1 - eased)
end

function TagFeed.start()
	local gui = PlasticUi.screen("TagRivalsTagFeed", 4)
	local holder = Instance.new("Frame")
	holder.Name = "Feed"
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(ROW_WIDE, (ROW_TALL + ROW_GAP) * T.FEED_MAX)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	gui.Parent = player:WaitForChild("PlayerGui")

	local current = plan()
	local ending = false
	RoundRemote.OnClientEvent:Connect(function(kind: string, a: any)
		if kind == "tag" and type(a) == "table" then
			add(a, holder, current.wide)
		elseif kind == "fell" and type(a) == "table" then
			addFell(a, holder, current.wide)
		elseif kind == "fade" then
			for _, row in rows do
				row.frame:Destroy()
			end
			table.clear(rows)
		end
	end)

	RunService.PreRender:Connect(function()
		local now = os.clock()
		current = plan()
		local step = ROW_TALL + ROW_GAP
		local wide = if current.left then current.wide else ROW_WIDE
		-- (each row's frame has GLOW pixels of room round it for its edge's glow; rows line up by their glass)
		scale.Scale = current.size
		holder.AnchorPoint = Vector2.new(if current.left then 0 else 1, 0)
		holder.Position = if current.left
			then UDim2.fromOffset(current.x, current.top)
			else UDim2.new(1, -current.x, 0, current.top)
		holder.Size = UDim2.fromOffset(wide, step * current.rows)
		-- where it rests, for the pieces that keep clear of it (the test-bots panel under it on the left)
		local screen = HudLayout.screen()
		local outer = if current.left then current.x else screen.X - current.x
		local across = wide * current.size
		HudLayout.report(
			"Feed",
			HudLayout.rect(
				if current.left then outer else outer - across,
				current.top,
				if current.left then outer + across else outer,
				current.top + (step * current.rows - ROW_GAP) * current.size
			)
		)
		-- the end screen: the rows fade away now
		local cleanup = Workspace:GetAttribute(RoundRules.ATTR_STATE) == "Cleanup"
		if cleanup and not ending then
			for _, row in rows do
				row.born = math.min(row.born, now - T.FEED_SHOW)
			end
		end
		ending = cleanup
		-- only as many as fit (the oldest go first)
		while #rows > current.rows do
			local old = table.remove(rows) :: Row
			old.frame:Destroy()
		end

		local i = 1
		while i <= #rows do
			local row = rows[i]
			local age = now - row.born
			if age > T.FEED_SHOW + 0.4 then
				row.frame:Destroy()
				table.remove(rows, i)
			else
				local bob = PlasticUi.motion(row.phase)
				local y = row.slot * step
				local at = row.frame.Position
				-- slide to its slot (rows below move down as new ones come in)
				local targetY = y + bob * 0.5
				local newY = at.Y.Offset + (targetY - at.Y.Offset) * 0.25
				-- in from its side: on the right each row lines up with the right edge, on the left with the left edge
				local out = slideOut(age, row.wide)
				local x = if current.left then -GLOW - out else wide - row.wide + GLOW + out
				row.frame.Position = UDim2.fromOffset(x, newY - GLOW)
				-- a light runs along the edge; the bolt flickers now and then
				row.glint.Offset = Vector2.new(-1 + ((now * 0.55 + row.phase) % 2.2), 0)
				local flicker = math.sin(now * 23 + row.phase * 40) * math.sin(now * 7.3 + row.phase * 9)
				row.bolt.ImageTransparency = if flicker > 0.82 then 0.45 else 0
				row.frame.GroupTransparency = if age > T.FEED_SHOW then (age - T.FEED_SHOW) / 0.4 else 0
				i += 1
			end
		end
	end)
end

return TagFeed
