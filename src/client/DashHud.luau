--!strict
-- The dash charges (design notes: 2 charges, "the HUD shows how long until the next charge"), in the style of Huss
-- Zero's dodge bar (owner 2026-11-09: "copy dis Ui Style from Huss Zero", then "dont take the Speed box", so there's no
-- SPEED badge): no box, one thin square bar per charge at the bottom middle of the screen, a small DASH word over the
-- first bar's left end and the seconds until the next charge over the last bar's right end.
-- Everything moves (owner 2026-11-09: "make the Uis All animated", "and the texture also animated"): the meter bobs and
-- leans as the camera turns; a full bar is solid in your dash colour with a white shine and a glint that sweeps across it;
-- a refilling one fills from the left, dimmer, its fill pulsing; an empty one is dark. A bar that refills pops and
-- flashes white; one you spend flashes white and squashes. Pressing with no charge flashes the bars' outlines red and
-- shakes the meter, and with no charge left the word dims.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local HudLayout = require(script.Parent.HudLayout)
local MoveController = require(script.Parent.MoveController)
local PlasticUi = require(script.Parent.PlasticUi)

local D = Config.Dash
local U = Config.Ui

local DashHud = {}

local player = Players.LocalPlayer

-- Layout in pixels at full size (before the screen scale).
local WIDTH = 230 -- the bars together
local BAR_TALL = 10 -- one charge's bar
local BAR_GAP = 8 -- between the bars
local BAR_OUTLINE = 2
local WORD_TEXT = 17 -- the DASH word and the seconds over the bars (16 read small on a phone)
local WORD_GAP = 4 -- between the words and the bars
local BOTTOM = 26 -- from the screen's bottom to the bars
local POP_TIME = 0.25 -- s a refilled bar's pop takes
local FLASH_TIME = 0.22 -- s a bar's white flash takes to fade
local SQUASH_TIME = 0.2 -- s a spent bar's squash takes
local GLINT_EVERY = 1.6 -- s between glints across a full bar
local GLINT_TIME = 0.45 -- s a glint takes to cross
local EMPTY_BAR = Color3.fromHex("0C0A1C")

type Cell = {
	frame: Frame,
	fill: Frame,
	flash: Frame,
	glint: Frame,
	outline: UIStroke,
	scale: UIScale,
	full: boolean,
	popAt: number,
	spentAt: number,
}

local function popScale(age: number): number
	if age < 0 or age >= POP_TIME then
		return 1
	end
	local x = age / POP_TIME
	return 1 + 0.35 * math.sin(math.pi * x) * (1 - x)
end

local function squashScale(age: number): number
	if age < 0 or age >= SQUASH_TIME then
		return 1
	end
	local x = age / SQUASH_TIME
	return 1 - 0.2 * math.sin(math.pi * x) * (1 - x)
end

local function flashLook(age: number): number
	if age < 0 or age >= FLASH_TIME then
		return 1
	end
	local x = age / FLASH_TIME
	return 0.15 + 0.85 * x * x
end

function DashHud.start()
	local gui = PlasticUi.screen("TagRivalsDashHud", 2)

	local tall = WORD_TEXT + WORD_GAP + BAR_TALL
	local holder = Instance.new("Frame")
	holder.Name = "DashMeter"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(WIDTH, tall)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local word = PlasticUi.text({ name = "Word", size = WORD_TEXT, parent = holder, align = Enum.TextXAlignment.Left })
	word.root.Size = UDim2.fromOffset(WIDTH, WORD_TEXT)
	word:set("DASH")
	local timer = PlasticUi.text({ name = "Timer", size = WORD_TEXT, parent = holder, align = Enum.TextXAlignment.Right })
	timer.root.Size = UDim2.fromOffset(WIDTH, WORD_TEXT)

	local count = math.max(math.floor(D.MAX_CHARGES), 1)
	local barWide = (WIDTH - (count - 1) * BAR_GAP) / count
	local cells: { Cell } = {}
	for i = 1, count do
		local frame = Instance.new("Frame")
		frame.Name = "Bar" .. i
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset((i - 1) * (barWide + BAR_GAP) + barWide / 2, WORD_TEXT + WORD_GAP + BAR_TALL / 2)
		frame.Size = UDim2.fromOffset(barWide, BAR_TALL)
		frame.BackgroundColor3 = EMPTY_BAR
		frame.BackgroundTransparency = 0.25
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = true
		local outline = PlasticUi.outline(frame, BAR_OUTLINE)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = frame
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.BorderSizePixel = 0
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0.6
		shine.Size = UDim2.fromScale(1, 0.35)
		shine.Parent = fill
		-- the glint that sweeps across a full bar
		local glint = Instance.new("Frame")
		glint.Name = "Glint"
		glint.BorderSizePixel = 0
		glint.BackgroundColor3 = Color3.new(1, 1, 1)
		glint.AnchorPoint = Vector2.new(0.5, 0)
		glint.Size = UDim2.fromScale(0.3, 1)
		glint.ZIndex = 2
		local soft = Instance.new("UIGradient")
		soft.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		soft.Parent = glint
		glint.Parent = frame
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.BorderSizePixel = 0
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.BackgroundTransparency = 1
		flash.Size = UDim2.fromScale(1, 1)
		flash.ZIndex = 3
		flash.Parent = frame
		local barScale = Instance.new("UIScale")
		barScale.Parent = frame
		frame.Parent = holder
		cells[i] = {
			frame = frame,
			fill = fill,
			flash = flash,
			glint = glint,
			outline = outline,
			scale = barScale,
			full = true,
			popAt = -math.huge,
			spentAt = -math.huge,
		}
	end

	gui.Parent = player:WaitForChild("PlayerGui")

	local emptyAt = -math.huge
	MoveController.onEmpty(function()
		emptyAt = os.clock()
	end)

	local emptyRed = Color3.fromHex(U.EMPTY_COLOR)
	RunService.PreRender:Connect(function()
		local clock = os.clock()
		local state = MoveController.state

		local emptyAge = clock - emptyAt
		local shake, red = 0, 0
		if emptyAge >= 0 and emptyAge < D.EMPTY_FLASH then
			local x = emptyAge / D.EMPTY_FLASH
			shake, red = math.sin(emptyAge * 70) * 5 * (1 - x), 1 - x
		end
		-- bobs and leans with the camera's turning (a sideways lean, not a turn: a turned frame stops clipping its glint)
		local bob, tilt = PlasticUi.motion(0.2)
		holder.Position = UDim2.new(0.5, shake + tilt * 2, 1, -BOTTOM + bob)
		local size = PlasticUi.screenScale()
		scale.Scale = size
		-- where it rests, for the pieces that keep clear of it (the end screen's list)
		local screen = HudLayout.screen()
		HudLayout.report(
			"DashBars",
			HudLayout.rect(
				screen.X / 2 - WIDTH / 2 * size,
				screen.Y - BOTTOM - tall * size - Config.Ui.BOB_PIXELS,
				screen.X / 2 + WIDTH / 2 * size,
				screen.Y - BOTTOM
			)
		)

		local color = MoveRules.dashColor(state.role, player:GetAttribute(MoveRules.ATTR_DASH_COLOR))
		local outlineColor = PlasticUi.OUTLINE_COLOR:Lerp(emptyRed, red)
		for i, cell in cells do
			local fill = MoveRules.cellFill(state.charge, i)
			local full = fill >= 1 - 1e-6
			if full and not cell.full then
				cell.popAt = clock
			elseif cell.full and not full then
				cell.spentAt = clock
			end
			cell.full = full
			cell.fill.Size = UDim2.fromScale(fill, 1)
			cell.fill.BackgroundColor3 = color
			-- a refilling bar is dimmer, its fill pulsing as it climbs
			cell.fill.BackgroundTransparency = if full then 0 else 0.35 + 0.12 * math.sin(clock * 12)
			cell.scale.Scale = popScale(clock - cell.popAt) * squashScale(clock - cell.spentAt)
			cell.flash.BackgroundTransparency = math.min(flashLook(clock - cell.popAt), flashLook(clock - cell.spentAt))
			cell.outline.Color = outlineColor
			-- the glint, each bar a little after the one before
			local glintAge = (clock + i * 0.18) % GLINT_EVERY
			cell.glint.Visible = full and glintAge < GLINT_TIME
			cell.glint.Position = UDim2.fromScale(-0.2 + 1.4 * (glintAge / GLINT_TIME), 0)
		end
		word:setColor(Color3.new(1, 1, 1):Lerp(color, 0.35))
		word:setFade(if MoveRules.canSpend(state.charge) then 0 else 0.5)
		local left = MoveRules.nextChargeIn(state.charge)
		timer:set(if left then string.format("%.1fs", left) else "")
	end)
end

return DashHud
