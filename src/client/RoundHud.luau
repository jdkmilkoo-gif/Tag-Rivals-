--!strict
-- The round on screen (design notes, UI and Round flow), in Huss Zero's style (owner: "copy dis Ui Style from Huss
-- Zero"; every screen animated):
--   * the timer at the top middle: a status line on top ("INTERMISSION", "THE SWARM IS LOOSE!", "LAST MAN
--     STANDING"), the big countdown on a striped indigo plate, and a thin bar under it that fills as time runs, in the
--     phase's colour (slate grey early, amber, orange, deep crimson for the last man). It bobs and leans, the status
--     glints, the plate's stripes scroll, the bar's glint sweeps, a new phase pops it, and the last 10 s pulse red;
--   * the fade to black before the match, with the chaser picked in the dark: "YOU ARE THE CHASER!" on yours, "RUN!"
--     and the chaser's name on everyone else's; then "GO!" as the match starts;
--   * a call-out when you're tagged ("TAGGED!") or tag someone ("+1 TAG"). The call-outs stack under the timer and
--     under SPEED UP! when it shows (HudLayout), drawn a little smaller on a phone, over the tag feed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)

local R = Config.Round

local RoundHud = {}

local player = Players.LocalPlayer
local RoundRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent

local WIDTH = 260 -- the timer's plate, pixels at full size (owner: about a quarter of the screen across)
local PLATE_TALL = 62
local BAR_TALL = 9
local STATUS_TEXT = 19
local TOP = 10
local TIMER_TALL = STATUS_TEXT + 6 + PLATE_TALL + 6 + BAR_TALL
local CALLOUT_WIDE = 900 -- room for the widest call-out ("YOU ARE THE CHASER!") so its group doesn't cut it off
local SUB_TEXT = 24
local SQUEEZE_MIN = 0.6 -- a long call-out squeezed beside the tag feed or coin counter keeps this share of its size
local POP_TIME = 0.32 -- the pop in, from half size
local WAIT_MAX = 2 -- a call-out with no room yet under the others waits its turn this long at most (seconds)
local RED = Color3.fromHex("FF3B4A")
local CHASER_RED = Color3.fromHex("FF2B4A")
local RUNNER_CYAN = Color3.fromHex("2EE6FF")

local function attr(name: string): any
	return Workspace:GetAttribute(name)
end

local function number(value: any, default: number): number
	return if type(value) == "number" then value else default
end

local function playersAndBots(): number
	local bots = Workspace:FindFirstChild("TagBots")
	return #Players:GetPlayers() + (if bots then #bots:GetChildren() else 0)
end

-- A big word that pops on the screen and fades, its middle `y` (share of the screen) down. One with a `stackName`
-- takes its place in the pop-ups' stack under the timer (HudLayout.stack) and is drawn at the pop-ups' size;
-- one without (the reveal on the black fade) sits at `y` at the HUD's size.
type Callout = { show: (self: Callout, title: string, sub: string?, color: Color3, hold: number) -> () }

local function makeCallout(gui: ScreenGui, y: number, titleSize: number, stackName: string?): Callout
	local tall = titleSize + 44
	local holder = Instance.new("CanvasGroup")
	holder.Name = "Callout"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, y)
	holder.Size = UDim2.fromOffset(CALLOUT_WIDE, tall)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.ZIndex = 5
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local title = PlasticUi.text({ name = "Title", size = titleSize, parent = holder, zIndex = 2 })
	title.root.Size = UDim2.new(1, 0, 0, titleSize + 6)
	local sub = PlasticUi.text({ name = "Sub", size = SUB_TEXT, parent = holder, zIndex = 2 })
	sub.root.Position = UDim2.fromOffset(0, titleSize + 10)
	sub.root.Size = UDim2.new(1, 0, 0, 30)

	-- how wide a line of it is at full size, pixels, outline included (the bold font measures like the bold italic)
	local function wideOf(text: string, textSize: number): number
		if text == "" then
			return 0
		end
		local bounds = TextService:GetTextSize(text, textSize, Enum.Font.MontserratBold, Vector2.new(10000, 1000))
		return bounds.X + textSize * Config.Ui.TEXT_OUTLINE * 2 + 4
	end
	local titleWide, subWide = 0, 0

	-- where its middle goes this frame (screen pixels down), how big it's drawn, and whether it fits under the others
	local function place(): (number, number, boolean)
		local screen = HudLayout.screen()
		if not stackName then
			return screen.Y * y, PlasticUi.screenScale(), true
		end
		local size = HudLayout.popScale()
		local function topAt(s: number): number
			local high = tall * s
			return HudLayout.stack(stackName, screen.Y * y - high / 2, high)
		end
		local top = topAt(size)
		-- drawn smaller if it must be (a phone): to fit under the pop-ups above it, and a long one to stay clear of
		-- the tag feed or the coin counter beside it
		local free = HudLayout.floor() - HudLayout.freeTop(stackName, screen.Y * y - tall * size / 2, tall * size)
		local fit = math.min(size, free / tall)
		if titleWide > 0 then
			local room = HudLayout.halfRoom(top, top + (titleSize + 6) * size)
			fit = math.min(fit, 2 * room / titleWide)
		end
		if subWide > 0 then
			local room = HudLayout.halfRoom(top + (titleSize + 10) * size, top + tall * size)
			fit = math.min(fit, 2 * room / subWide)
		end
		local fits = true
		if fit < size then
			fits = free >= tall * size * SQUEEZE_MIN
			size = math.max(fit, size * SQUEEZE_MIN)
			top = topAt(size)
		end
		return top + tall * size / 2, size, fits
	end

	local hideAt = -math.huge
	local shownAt = -math.huge
	local held = 0 -- how long this one holds
	local waitUntil = 0 -- while it's waiting for room: when it gives up
	local callout = {} :: any
	function callout.show(_self: Callout, text: string, subText: string?, color: Color3, hold: number)
		title:set(text)
		title:setColor(color)
		sub:set(subText or "")
		titleWide = if stackName then wideOf(text, titleSize) else 0
		subWide = if stackName then wideOf(subText or "", SUB_TEXT) else 0
		holder.Visible = true
		holder.GroupTransparency = 0
		hideAt = os.clock() + hold
		shownAt = os.clock()
		held = hold
		waitUntil = os.clock() + WAIT_MAX
	end
	RunService.PreRender:Connect(function()
		if not holder.Visible then
			return
		end
		local now = os.clock()
		local middle, size, fits = place()
		if not fits and now < waitUntil then
			-- no room yet under the pop-ups above it (a phone, a busy moment): it waits its turn, its hold not started
			if stackName then
				HudLayout.unstack(stackName)
			end
			holder.GroupTransparency = 1
			shownAt = now
			hideAt = now + held
			return
		end
		waitUntil = 0 -- showing now: it stays till its hold is up
		local past = now - hideAt
		if past > 0.3 then
			holder.Visible = false
			if stackName then
				HudLayout.unstack(stackName)
			end
			return
		end
		holder.GroupTransparency = math.clamp(past / 0.3, 0, 1)
		title.root.Rotation = -3 + 2 * math.sin(now * 5)
		holder.Position = UDim2.new(0.5, 0, 0, middle + PlasticUi.motion(0.4))
		-- pops in from half size with a little overshoot (back ease out)
		local t = math.clamp((now - shownAt) / POP_TIME, 0, 1) - 1
		scale.Scale = size * (0.5 + 0.5 * (1 + 2.70158 * t * t * t + 1.70158 * t * t))
	end)
	return callout :: Callout
end

-- The call-outs, for the other screens that have something to shout (a bounty, a new level, a finished quest): the
-- big one in the middle, or with `small` the smaller one under it. They share the round's own, so two never overlap.
local shared: { middle: Callout?, small: Callout? } = {}

function RoundHud.say(title: string, sub: string?, color: Color3, hold: number, small: boolean?)
	local callout = if small then shared.small else shared.middle
	if callout then
		callout:show(title, sub, color, hold)
	end
end

function RoundHud.start()
	local gui = PlasticUi.screen("TagRivalsRoundHud", 3)

	---------------------------------------------------------------- the timer
	local holder = Instance.new("Frame")
	holder.Name = "Timer"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(WIDTH, TIMER_TALL)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local status = PlasticUi.text({ name = "Status", size = STATUS_TEXT, parent = holder, zIndex = 4 })
	status.root.Size = UDim2.new(1, 120, 0, STATUS_TEXT + 4)
	status.root.Position = UDim2.fromOffset(-60, 0)
	PlasticUi.shimmer(status.label, PlasticUi.GOLD, 2.2)

	local plate = PlasticUi.block({
		name = "Plate",
		width = WIDTH,
		height = PLATE_TALL,
		color = PlasticUi.PLATE,
		parent = holder,
		dotsCover = 0.6,
	})
	plate.root.Position = UDim2.fromOffset(0, STATUS_TEXT + 6)
	local stripes = PlasticUi.stripedPlate("Stripes", WIDTH, PLATE_TALL - plate.depth, PlasticUi.PLATE)
	stripes.ZIndex = 0
	stripes.Size = UDim2.fromScale(1, 1)
	stripes.Parent = plate.face
	local plateScale = Instance.new("UIScale")
	plateScale.Parent = plate.root
	local clock = PlasticUi.text({ name = "Clock", size = 42, parent = plate.face, zIndex = 4 })
	clock.root.Size = UDim2.fromScale(1, 1)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Color3.fromHex("0C0A1C")
	bar.BackgroundTransparency = 0.2
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	bar.Position = UDim2.fromOffset(0, STATUS_TEXT + 6 + PLATE_TALL + 6)
	bar.Size = UDim2.fromOffset(WIDTH, BAR_TALL)
	PlasticUi.outline(bar, 2)
	bar.Parent = holder
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.6
	shine.Size = UDim2.fromScale(1, 0.4)
	shine.Parent = fill
	local glint = Instance.new("Frame")
	glint.Name = "Glint"
	glint.BorderSizePixel = 0
	glint.BackgroundColor3 = Color3.new(1, 1, 1)
	glint.Size = UDim2.fromScale(0.18, 1)
	glint.ZIndex = 2
	local soft = Instance.new("UIGradient")
	soft.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	soft.Parent = glint
	glint.Parent = bar

	---------------------------------------------------------------- the fade, the reveal, GO, call-outs
	local fadeGui = PlasticUi.screen("TagRivalsFade", 20)
	local black = Instance.new("Frame")
	black.Name = "Black"
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Size = UDim2.fromScale(1, 1)
	black.Parent = fadeGui
	local reveal = makeCallout(fadeGui, 0.45, 64)
	-- the round's call-outs: their own screen, over the tag feed (4) like SPEED UP! (5); they stack under the timer and
	-- under SPEED UP! when it shows, so a tag's two call-outs never cover each other
	local calloutGui = PlasticUi.screen("TagRivalsCallouts", 5)
	local middle = makeCallout(calloutGui, 0.5, 72, "Middle")
	local small = makeCallout(calloutGui, 0.64, 40, "Small")
	shared.middle = middle
	shared.small = small

	gui.Parent = player:WaitForChild("PlayerGui")
	calloutGui.Parent = player:WaitForChild("PlayerGui")
	fadeGui.Parent = player:WaitForChild("PlayerGui")

	local fadeInfoIn = TweenInfo.new(R.FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInfoOut = TweenInfo.new(R.FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local fadeStamp = 0
	RoundRemote.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "fade" then
			fadeStamp += 1
			local stamp = fadeStamp
			local fadeIn = if type(a) == "number" then a else R.FADE_IN
			local total = if type(b) == "number" then b else R.TELEPORT
			TweenService:Create(black, fadeInfoIn, { BackgroundTransparency = 0 }):Play()
			task.delay(math.max(total - R.FADE_OUT, fadeIn), function()
				if stamp == fadeStamp then
					TweenService:Create(black, fadeInfoOut, { BackgroundTransparency = 1 }):Play()
				end
			end)
			-- never stuck black (a lost message)
			task.delay(total + 1.5, function()
				if stamp == fadeStamp then
					black.BackgroundTransparency = 1
				end
			end)
		elseif kind == "chaser" then
			local inFade = attr(RoundRules.ATTR_STATE) == "Teleport"
			local name = if type(b) == "string" then b else "?"
			if a == player then
				local show = if inFade then reveal else middle
				show:show("YOU ARE THE CHASER!", "Get close to a runner and your knife does the rest", CHASER_RED, 1.4)
			elseif inFade then
				reveal:show("RUN!", "The chaser is " .. name, RUNNER_CYAN, 1.2)
			else
				small:show(string.upper(name) .. " IS A CHASER NOW", nil, CHASER_RED, 1.4)
			end
		elseif kind == "go" then
			middle:show("GO!", nil, PlasticUi.GOLD, 0.7)
		elseif kind == "dodge" and type(a) == "table" then
			-- the runner's "PERFECT DODGE!" is over their head (PerfectDodge), not on the screen
			if a.chaser == player then
				middle:show("DODGED!", "Stunned for a moment", Color3.fromHex("C8CCD8"), 1.1)
			end
		elseif kind == "tag" and type(a) == "table" then
			if a.runner == player then
				middle:show("TAGGED!", "You're a chaser now. Get ready...", CHASER_RED, 1.6)
			elseif a.chaser == player then
				small:show("+1 TAG", nil, PlasticUi.GOLD, 0.8)
			end
		elseif kind == "fell" and type(a) == "table" then
			-- you were still on the red when it was cut (owner 2026-11-10: "make the red let players fall and become
			-- tagger")
			if a.who == player then
				if a.runner == true then
					middle:show("YOU FELL!", "You're a chaser now. Get ready...", CHASER_RED, 1.9)
				else
					middle:show("YOU FELL!", "Back on the map in a moment", CHASER_RED, 1.6)
				end
			end
		end
	end)

	---------------------------------------------------------------- every frame
	local lastPhase = 1
	local popAt = -math.huge
	RunService.PreRender:Connect(function()
		local now = os.clock()
		local state = attr(RoundRules.ATTR_STATE)
		local stateText = if type(state) == "string" then state else "Waiting"
		local phase = number(attr(RoundRules.ATTR_PHASE), 1)
		local inMatch = stateText == "Match" or stateText == "Cleanup"
		local shownPhase = if inMatch then phase else 1
		if shownPhase ~= lastPhase then
			lastPhase = shownPhase
			popAt = now
		end
		local enough = playersAndBots() >= R.MIN_PLAYERS
		status:set(RoundRules.status(stateText, phase, enough))

		local endsAt = number(attr(RoundRules.ATTR_ENDS_AT), 0)
		local length = number(attr(RoundRules.ATTR_LENGTH), 0)
		local left = if endsAt > 0 then math.max(endsAt - Workspace:GetServerTimeNow(), 0) else 0
		if endsAt > 0 then
			clock:set(RoundRules.clock(left))
		else
			clock:set(string.rep(".", 1 + math.floor(now * 2) % 3))
		end
		local color = RoundRules.phaseColor(shownPhase)
		fill.BackgroundColor3 = fill.BackgroundColor3:Lerp(color, 0.15)
		fill.Size = UDim2.fromScale(if length > 0 then math.clamp(1 - left / length, 0, 1) else 0, 1)
		local glintAge = now % 2.2
		glint.Visible = glintAge < 0.6
		glint.Position = UDim2.fromScale(-0.2 + 1.4 * (glintAge / 0.6), 0)

		-- the last 10 s of the match pulse red
		local urgent = stateText == "Match" and left <= 10 and endsAt > 0
		if urgent then
			local beat = 0.5 + 0.5 * math.sin(now * math.pi * 4)
			clock:setColor(Color3.new(1, 1, 1):Lerp(RED, beat))
		else
			clock:setColor(Color3.new(1, 1, 1))
		end
		-- a new phase pops the plate
		local popAge = now - popAt
		local pop = if popAge >= 0 and popAge < 0.35 then 1 + 0.18 * math.sin(math.pi * popAge / 0.35) else 1
		plateScale.Scale = pop * (if urgent then 1 + 0.03 * math.sin(now * math.pi * 4) else 1)

		local bob, tilt = PlasticUi.motion(0.65)
		local size = PlasticUi.screenScale()
		holder.Position = UDim2.new(0.5, tilt * 2, 0, TOP + bob)
		holder.Rotation = tilt * 0.4
		scale.Scale = size
		-- where it rests, for the pieces that keep clear of it (its bob counted in)
		local middleX = HudLayout.screen().X / 2
		HudLayout.report(
			"Timer",
			HudLayout.rect(
				middleX - WIDTH / 2 * size,
				TOP,
				middleX + WIDTH / 2 * size,
				TOP + TIMER_TALL * size + Config.Ui.BOB_PIXELS
			)
		)
	end)
end

return RoundHud
