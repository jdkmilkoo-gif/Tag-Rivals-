--!strict
-- The runner counter (owner 2026-11-10: "add a RUnner counter"): how many runners are still running, live, just right
-- of the timer at the top middle, in Huss Zero's style and moving like every other screen:
--   * a "RUNNERS" line on top, level with the timer's status line, with a glint sweeping it;
--   * a striped indigo plate like the timer's: a little cyan runner whose arms and legs swing, the runners left in big
--     numbers and the round's starting runners after them ("5/12");
--   * a thin bar under it, like the timer's: cyan for the runners still running, dark red for the ones tagged;
--   * a tag drops the number: it punches and flashes red, the plate shakes, a red "-1" drops off it, the little runner
--     flashes red and the bar shrinks;
--   * once the runners get the last-runner speeds the number and bar turn gold and the little runner runs faster; with
--     one left the line says LAST ONE! and the plate pulses; with none left it says ALL TAGGED and the runner stops.
-- It slides down from the top while a round is on (the teleport, the match and the end screen), for everyone, lobby
-- watchers too, and slides away after. The numbers are the server's (Round sets RunnersLeft and RunnersAtStart on
-- Workspace), so they're never wrong; nothing here runs while it's off screen.
-- On a phone the coin counter is lifted to just above the Dash button and keeps clear of this one (HudLayout). If the
-- two ever do meet, the bar steps aside (and the "-1" drops less far).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoundRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RoundRules"))
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)

local RunnerCounter = {}

local player = Players.LocalPlayer

-- The timer's layout (RoundHud): its plate is TIMER_WIDTH across, centred at the top, TIMER_TOP pixels down, under a
-- STATUS_TEXT line. The counter lines up with it, GAP to its right. Pixels at full size.
local TIMER_WIDTH = 260
local TIMER_TOP = 10
local STATUS_TEXT = 19
local PLATE_TALL = 62
local BAR_TALL = 9
local GAP = 12
local WIDTH = 132
local PLATE_Y = STATUS_TEXT + 6
local BAR_Y = PLATE_Y + PLATE_TALL + 6
local LABEL_TEXT = 17
local COUNT_TEXT = 38
local TOTAL_TEXT = 18
local DROP_TEXT = 24
local ICON_W, ICON_H = 28, 40
local SLIDE_PIXELS = 140 -- how far up it hides between rounds
local BOB = 3 -- how far it bobs (Config.Ui.BOB_PIXELS), counted into where it rests

local PUNCH_TIME = 0.4 -- s the number's punch takes
local FLASH_TIME = 0.45 -- s the red flash on a tag takes to fade
local SHAKE_TIME = 0.3 -- s the plate shakes on a tag
local DROP_TIME = 0.85 -- s the "-1" takes to drop and fade
local RUN_HZ = 2.2 -- the little runner's strides a second
local RUN_HZ_FAST = 3.4 -- once the runners get the last-runner speeds

local WHITE = Color3.new(1, 1, 1)
local RUNNER_CYAN = Color3.fromHex("2EE6FF")
local RUNNER_BACK = Color3.fromHex("1A9DB3") -- the far arm and leg, a shade darker
local CHASER_RED = Color3.fromHex("FF2B4A")
local TOTAL_GREY = Color3.fromHex("B9C2E6")
local BAR_BACK = Color3.fromHex("3A0A18")

-- A limb of the little runner: swings round `pivot` (shoulder or hip, icon pixels), `length` long, `sign` sets which
-- way it swings with the stride.
type Limb = { frame: Frame, pivot: Vector2, length: number, swing: number, sign: number, color: Color3 }

local function number(value: unknown): number
	return if type(value) == "number" then value else 0
end

local function glintColors(base: Color3): ColorSequence
	-- the same sweep PlasticUi.shimmer draws, on another colour
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, base),
		ColorSequenceKeypoint.new(0.4, base),
		ColorSequenceKeypoint.new(0.5, base:Lerp(WHITE, 0.85)),
		ColorSequenceKeypoint.new(0.6, base),
		ColorSequenceKeypoint.new(1, base),
	})
end

-- A square plastic bit of the little runner (TagFeed's knife is built the same way).
local function bit(parent: Instance, name: string, w: number, h: number, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	PlasticUi.outline(f, 1.5)
	f.Parent = parent
	return f
end

function RunnerCounter.start()
	local gui = PlasticUi.screen("TagRivalsRunners", 3)

	local holder = Instance.new("Frame")
	holder.Name = "RunnerCounter"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(WIDTH, BAR_Y + BAR_TALL)
	holder.Visible = false
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	---------------------------------------------------------------- the line on top
	local label = PlasticUi.text({ name = "Label", size = LABEL_TEXT, parent = holder, zIndex = 4 })
	label.root.Size = UDim2.new(1, 0, 0, STATUS_TEXT + 4)
	PlasticUi.shimmer(label.label, RUNNER_CYAN, 2.2)
	local labelGlint = label.label:FindFirstChildOfClass("UIGradient")

	---------------------------------------------------------------- the plate
	local plate = PlasticUi.block({
		name = "Plate",
		width = WIDTH,
		height = PLATE_TALL,
		color = PlasticUi.PLATE,
		parent = holder,
		dotsCover = 0.6,
	})
	plate.root.Position = UDim2.fromOffset(0, PLATE_Y)
	local stripes = PlasticUi.stripedPlate("Stripes", WIDTH, PLATE_TALL - plate.depth, PlasticUi.PLATE)
	stripes.ZIndex = 0
	stripes.Size = UDim2.fromScale(1, 1)
	stripes.Parent = plate.face
	local plateScale = Instance.new("UIScale")
	plateScale.Parent = plate.root
	local faceTall = PLATE_TALL - plate.depth

	-- the little runner, leaning into its stride
	local icon = Instance.new("Frame")
	icon.Name = "Runner"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Size = UDim2.fromOffset(ICON_W, ICON_H)
	icon.ZIndex = 4
	icon.Parent = plate.face
	local limbs: { Limb } = {}
	local function limb(
		name: string,
		w: number,
		length: number,
		pivot: Vector2,
		swing: number,
		sign: number,
		front: boolean
	)
		local color = if front then RUNNER_CYAN else RUNNER_BACK
		local frame = bit(icon, name, w, length, color, if front then 4 else 1)
		table.insert(limbs, {
			frame = frame,
			pivot = pivot,
			length = length,
			swing = swing,
			sign = sign,
			color = color,
		})
	end
	local shoulder = Vector2.new(17.5, 12)
	local hip = Vector2.new(14, 22)
	limb("BackArm", 4, 11, shoulder, 45, -1, false)
	limb("BackLeg", 5, 15, hip, 35, 1, false)
	local torso = bit(icon, "Body", 7, 12, RUNNER_CYAN, 2)
	torso.Position = UDim2.fromOffset(16, 16.5)
	torso.Rotation = 16
	local head = bit(icon, "Head", 8, 8, RUNNER_CYAN, 3)
	head.Position = UDim2.fromOffset(19, 6)
	limb("FrontLeg", 5, 15, hip, 35, -1, true)
	limb("FrontArm", 4, 11, shoulder, 45, 1, true)

	-- the runners left, big, and the round's starting runners after them
	local count = PlasticUi.text({
		name = "Count",
		size = COUNT_TEXT,
		parent = plate.face,
		zIndex = 4,
		align = Enum.TextXAlignment.Right,
	})
	count.root.AnchorPoint = Vector2.new(1, 0.5)
	count.root.Position = UDim2.fromOffset(90, faceTall / 2)
	count.root.Size = UDim2.fromOffset(54, faceTall)
	local countScale = Instance.new("UIScale")
	countScale.Parent = count.root
	local total = PlasticUi.text({
		name = "Total",
		size = TOTAL_TEXT,
		parent = plate.face,
		zIndex = 4,
		align = Enum.TextXAlignment.Left,
		color = TOTAL_GREY,
	})
	-- sits on the big number's baseline
	total.root.Position = UDim2.fromOffset(91, faceTall / 2 - 5)
	total.root.Size = UDim2.fromOffset(WIDTH - 95, 24)

	---------------------------------------------------------------- the bar
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = BAR_BACK
	bar.BackgroundTransparency = 0.1
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	bar.Position = UDim2.fromOffset(0, BAR_Y)
	bar.Size = UDim2.fromOffset(WIDTH, BAR_TALL)
	PlasticUi.outline(bar, 2)
	bar.Parent = holder
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = RUNNER_CYAN
	fill.BorderSizePixel = 0
	fill.ClipsDescendants = true
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bar
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.6
	shine.Size = UDim2.fromScale(1, 0.4)
	shine.Parent = fill
	local glint = Instance.new("Frame")
	glint.Name = "Glint"
	glint.BorderSizePixel = 0
	glint.BackgroundColor3 = WHITE
	glint.Size = UDim2.fromScale(0.25, 1)
	glint.ZIndex = 2
	local soft = Instance.new("UIGradient")
	soft.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	soft.Parent = glint
	glint.Parent = fill

	---------------------------------------------------------------- the "-1" a tag drops
	local drop = PlasticUi.text({ name = "Lost", size = DROP_TEXT, parent = holder, zIndex = 6, color = CHASER_RED })
	drop.root.AnchorPoint = Vector2.new(0.5, 0.5)
	drop.root.Size = UDim2.fromOffset(70, DROP_TEXT + 8)
	drop.root.Rotation = 8
	drop.root.Visible = false
	local dropScale = Instance.new("UIScale")
	dropScale.Parent = drop.root

	gui.Parent = player:WaitForChild("PlayerGui")

	---------------------------------------------------------------- the numbers
	local shownLeft = 0
	local shownStart = 0
	local punchAt = -math.huge
	local flashAt = -math.huge
	local shakeAt = -math.huge
	local dropAt = -math.huge
	local labelColor: Color3? = nil

	local function fastRunners(): boolean
		return shownLeft >= 1 and shownLeft <= RoundRules.fastRunners(shownStart)
	end

	local function lastOne(): boolean
		return shownStart >= 2 and shownLeft == 1
	end

	local function setLabel(text: string, color: Color3)
		label:set(text)
		if color ~= labelColor and labelGlint then
			labelColor = color
			labelGlint.Color = glintColors(color)
		end
	end

	local function showNumbers()
		count:set(tostring(shownLeft))
		total:set("/" .. tostring(shownStart))
		if shownLeft <= 0 then
			setLabel("ALL TAGGED", CHASER_RED)
		elseif lastOne() then
			setLabel("LAST ONE!", PlasticUi.GOLD)
		else
			setLabel("RUNNERS", RUNNER_CYAN)
		end
		fill.BackgroundColor3 = if fastRunners() then PlasticUi.GOLD else RUNNER_CYAN
	end

	local function readCounts()
		local start = number(Workspace:GetAttribute(RoundRules.ATTR_RUNNERS_START))
		if start <= 0 then
			return -- between rounds: it keeps the last numbers while it slides away
		end
		local left = math.clamp(number(Workspace:GetAttribute(RoundRules.ATTR_RUNNERS_LEFT)), 0, start)
		local now = os.clock()
		local state = Workspace:GetAttribute(RoundRules.ATTR_STATE)
		if state == "Match" and start == shownStart and left < shownLeft then
			-- a runner was tagged (or left the game)
			drop:set("-" .. tostring(shownLeft - left))
			punchAt, flashAt, shakeAt, dropAt = now, now, now, now
		elseif start ~= shownStart or left > shownLeft then
			punchAt = now -- a new round
		end
		shownLeft, shownStart = left, start
		showNumbers()
	end
	Workspace:GetAttributeChangedSignal(RoundRules.ATTR_RUNNERS_LEFT):Connect(readCounts)
	Workspace:GetAttributeChangedSignal(RoundRules.ATTR_RUNNERS_START):Connect(readCounts)
	readCounts()
	showNumbers()

	---------------------------------------------------------------- every frame (only while it's on screen)
	local slide = 1 -- 0 on screen, 1 hidden above it
	local fillShown = 1
	local runPhase = 0
	local iconRed = false
	local countColor: Color3? = nil

	RunService.PreRender:Connect(function(dt: number)
		local state = Workspace:GetAttribute(RoundRules.ATTR_STATE)
		local on = shownStart > 0 and (state == "Teleport" or state == "Match" or state == "Cleanup")
		slide += ((if on then 0 else 1) - slide) * (1 - math.exp(-10 * dt))
		local size = PlasticUi.screenScale()
		local camera = Workspace.CurrentCamera
		local middle = if camera then camera.ViewportSize.X / 2 else 400
		local left = middle + (TIMER_WIDTH / 2 + GAP) * size
		-- where it rests, for the pieces that keep clear of it (the coin counter on a phone)
		local rest = HudLayout.rect(left, TIMER_TOP, left + WIDTH * size, TIMER_TOP + (BAR_Y + BAR_TALL) * size + BOB)
		HudLayout.report("Runners", if on then rest else nil)
		local visible = slide < 0.995
		if holder.Visible ~= visible then
			holder.Visible = visible
		end
		if not visible then
			return
		end
		local now = os.clock()

		-- beside the timer, bobbing and leaning in step with it; a tag shakes it
		local bob, tilt = PlasticUi.motion(0.65)
		local s = (now - shakeAt) / SHAKE_TIME
		local shake = if s >= 0 and s < 1 then math.sin(s * math.pi * 7) * 4 * (1 - s) else 0
		holder.Position = UDim2.new(
			0.5,
			(TIMER_WIDTH / 2 + GAP + shake) * size + tilt * 2,
			0,
			TIMER_TOP + bob - slide * SLIDE_PIXELS * size
		)
		holder.Rotation = tilt * 0.4
		scale.Scale = size

		-- if the coin counter ever comes up against this one (it keeps clear on the phones tried), the bar steps aside
		local coin = HudLayout.get("Coin")
		local tight = coin ~= nil and HudLayout.touches(coin, rest)
		if bar.Visible == tight then
			bar.Visible = not tight
		end

		-- the number: punches on a change, flashes red on a tag, gold for the last runners, red when none are left
		local p = (now - punchAt) / PUNCH_TIME
		if p >= 0 and p < 1 then
			local k = (1 - p) * (1 - p)
			countScale.Scale = 1 + 0.4 * k
			count.root.Rotation = -5 * k
		elseif countScale.Scale ~= 1 then
			countScale.Scale = 1
			count.root.Rotation = 0
		end
		local base = WHITE
		if shownLeft <= 0 then
			base = CHASER_RED
		elseif lastOne() then
			base = PlasticUi.GOLD:Lerp(WHITE, 0.5 + 0.5 * math.sin(now * math.pi * 4))
		elseif fastRunners() then
			base = PlasticUi.GOLD
		end
		local f = (now - flashAt) / FLASH_TIME
		local flashing = f >= 0 and f < 1
		local color = if flashing then CHASER_RED:Lerp(base, f) else base
		if color ~= countColor then
			countColor = color
			count:setColor(color)
		end
		-- the last one left: the plate pulses like the timer's last seconds
		plateScale.Scale = if lastOne() then 1 + 0.03 * math.sin(now * math.pi * 4) else 1

		-- the little runner: swings its arms and legs and bounces each stride (faster for the last runners); flashes
		-- red on a tag; stands still in red when everyone's tagged
		local caught = shownLeft <= 0
		if not caught then
			runPhase = (runPhase + dt * 2 * math.pi * (if fastRunners() then RUN_HZ_FAST else RUN_HZ)) % (2 * math.pi)
		end
		local stride = if caught then 0 else math.sin(runPhase)
		for _, each in limbs do
			local angle = each.sign * each.swing * stride
			local r = math.rad(angle)
			local half = each.length / 2
			each.frame.Position = UDim2.fromOffset(each.pivot.X - half * math.sin(r), each.pivot.Y + half * math.cos(r))
			each.frame.Rotation = angle
		end
		icon.Position = UDim2.new(0, 8, 0.5, if caught then 0 else -1.5 * math.abs(stride))
		if flashing or caught then
			iconRed = true
			local k = if caught then 0 else f
			for _, each in limbs do
				each.frame.BackgroundColor3 = CHASER_RED:Lerp(each.color, k)
			end
			torso.BackgroundColor3 = CHASER_RED:Lerp(RUNNER_CYAN, k)
			head.BackgroundColor3 = torso.BackgroundColor3
		elseif iconRed then
			iconRed = false
			for _, each in limbs do
				each.frame.BackgroundColor3 = each.color
			end
			torso.BackgroundColor3 = RUNNER_CYAN
			head.BackgroundColor3 = RUNNER_CYAN
		end

		-- the bar: eases to the share still running; its glint sweeps now and then
		local target = if shownStart > 0 then math.clamp(shownLeft / shownStart, 0, 1) else 0
		if math.abs(fillShown - target) > 1e-3 then
			fillShown += (target - fillShown) * (1 - math.exp(-8 * dt))
			fill.Size = UDim2.fromScale(fillShown, 1)
		end
		local glintAge = (now + 1.1) % 2.2
		glint.Visible = glintAge < 0.6
		glint.Position = UDim2.fromScale(-0.3 + 1.6 * (glintAge / 0.6), 0)

		-- the "-1": pops out of the plate, drops past the bar (less far when the bar's stepped aside) and fades
		local d = (now - dropAt) / DROP_TIME
		if d >= 0 and d < 1 then
			drop.root.Visible = true
			drop.root.Position = UDim2.fromOffset(WIDTH - 22, PLATE_Y + 40 + (if tight then 10 else 34) * d)
			dropScale.Scale = if d < 0.15 then 0.5 + 0.9 * (d / 0.15) else 1.4 - 0.4 * math.min((d - 0.15) / 0.3, 1)
			drop:setFade(if d > 0.55 then (d - 0.55) / 0.45 else 0)
		elseif drop.root.Visible then
			drop.root.Visible = false
		end
	end)
end

return RunnerCounter
