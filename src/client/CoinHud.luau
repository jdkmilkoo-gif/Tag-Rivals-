--!strict
-- The coin counter and the pick-up's screen effects (design notes, UI and Star pickup feel; the 'Tag Rivals Coin'
-- preview), in Huss Zero's style:
--   * the counter sits on the right side, just under the screen's middle (owner 2026-11-09: "put the coin ui below the
--     middle of the right side"): a gold plastic plate with the coin and your coins this round, and a blue tag under it
--     with the speed the coins give you ("+4.6 SPEED"). It shows while you're in a round, sliding in from the right;
--     on a phone it's lifted to just above the Dash button, and kept clear of the runner counter (a little smaller if
--     it has to be, HudLayout);
--   * picking a coin up: "+2" pops where the coin was, a little coin flies from there to the counter with a sparkle
--     trail, and when it lands the counter punches 20% bigger and ticks up, a shine sweeps it, the speed tag glows, and
--     faint white wind lines flash at the screen's edges.
-- CoinFx calls CoinHud.collect when you pick one up (on your own screen, at once). The numbers follow your RoundCoins
-- and Stars attributes, so a pick-up the server turns down never counts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CoinRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CoinRules"))
local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)

local C = Config.Coins
local U_BOB = Config.Ui.BOB_PIXELS

local CoinHud = {}

local player = Players.LocalPlayer

-- Sizes at full scale (pixels)
local COUNTER_W, COUNTER_H = 156, 62
local TAG_W, TAG_H = 156, 34
local GAP = 6
local ICON = 46
local TALL = COUNTER_H + GAP + TAG_H
local SQUEEZE_MIN = 0.7 -- on a cramped phone it's drawn at least this share of its size
local FLY_TIME = 0.5 -- s a coin takes to fly to the counter
local POP_TIME = 0.95 -- s the "+2" shows
local PUNCH_TIME = 0.38
local SHINE_TIME = 0.45
local GLOW_TIME = 0.52
local WIND_TIME = 0.38
local TRAIL_LIFE = 0.32
local TRAIL_EVERY = 1 / 40 -- s between two trail sparks

local GOLD_TEXT = Color3.fromHex("FFD23A")
local TRAIL_GOLD = Color3.fromHex("FFD34D")

type Flyer = { image: ImageLabel, from: Vector2, t: number, trail: number, live: boolean }
type Pop = { text: PlasticUi.Text, at: Vector2, t: number, live: boolean }
type Spark = { image: ImageLabel, at: Vector2, drift: Vector2, t: number, live: boolean }

local gui: ScreenGui = nil :: any
local holder: Frame = nil :: any
local holderScale: UIScale = nil :: any
local counterRoot: Frame = nil :: any
local counterScale: UIScale = nil :: any
local icon: ImageLabel = nil :: any
local countText: PlasticUi.Text = nil :: any
local shine: Frame = nil :: any
local shineGradient: UIGradient = nil :: any
local speedText: PlasticUi.Text = nil :: any
local speedGlow: Frame = nil :: any
local speedHalo: UIStroke = nil :: any
local layer: Frame = nil :: any
local windLines: { Frame } = {}

local flyers: { Flyer } = {}
local pops: { Pop } = {}
local sparks: { Spark } = {}
local flying = 0
local shown = 0
local shownBonus = 0
local punchAt = -math.huge
local shineAt = -math.huge
local glowAt = -math.huge
local windAt = -math.huge
local effectsIdle = true -- nothing flying, popping or blowing (the frame's step skips the effects)
local slide = 1 -- 0 on screen, 1 off to the right

local function number(value: unknown): number
	return if type(value) == "number" then value else 0
end

local function actualCoins(): number
	return number(player:GetAttribute(CoinRules.ATTR_ROUND_COINS))
end

local function speedBonus(): number
	return MoveRules.starBonus(player:GetAttribute(MoveRules.ATTR_STARS))
end

local function showing(): boolean
	if player:GetAttribute(RoundRules.ATTR_IN_ROUND) ~= true then
		return false
	end
	local state = Workspace:GetAttribute(RoundRules.ATTR_STATE)
	return state == "Teleport" or state == "Match" or state == "Cleanup"
end

local function punch()
	punchAt = os.clock()
	shineAt = os.clock()
end

local function setCount(value: number)
	shown = value
	countText:set(tostring(math.floor(value + 0.5)))
end

-- The numbers follow the attributes; while coins are still flying in, the counter waits for them to land.
local function syncCount()
	local actual = actualCoins()
	if flying > 0 and actual >= shown then
		return
	end
	if actual > shown then
		punch()
	end
	setCount(actual)
end

local function syncSpeed()
	local bonus = speedBonus()
	if bonus > shownBonus + 1e-3 then
		glowAt = os.clock()
	end
	shownBonus = bonus
	speedText:set(CoinRules.speedText(bonus))
end

---------------------------------------------------------------- pooled pieces

local function freeFlyer(): Flyer
	for _, f in flyers do
		if not f.live then
			return f
		end
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Flyer"
	image.BackgroundTransparency = 1
	image.Image = C.IMAGES.ICON
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Size = UDim2.fromOffset(40, 40)
	image.ZIndex = 3
	image.Visible = false
	image.Parent = layer
	local f: Flyer = { image = image, from = Vector2.zero, t = 0, trail = 0, live = false }
	table.insert(flyers, f)
	return f
end

local function freePop(): Pop
	for _, p in pops do
		if not p.live then
			return p
		end
	end
	local text = PlasticUi.text({ name = "Plus", size = 38, parent = layer, color = GOLD_TEXT, zIndex = 4 })
	text.root.AnchorPoint = Vector2.new(0.5, 0.5)
	text.root.Size = UDim2.fromOffset(120, 50)
	text.root.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = text.root
	local p: Pop = { text = text, at = Vector2.zero, t = 0, live = false }
	table.insert(pops, p)
	return p
end

local function freeSpark(): Spark?
	for _, s in sparks do
		if not s.live then
			return s
		end
	end
	if #sparks >= 40 then
		return nil
	end
	local image = Instance.new("ImageLabel")
	image.Name = "Trail"
	image.BackgroundTransparency = 1
	image.Image = C.IMAGES.DOT
	image.ImageColor3 = TRAIL_GOLD
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.ZIndex = 2
	image.Visible = false
	image.Parent = layer
	local s: Spark = { image = image, at = Vector2.zero, drift = Vector2.zero, t = 0, live = false }
	table.insert(sparks, s)
	return s
end

---------------------------------------------------------------- you picked one up

-- You picked up the coin at `worldPosition`: "+2" pops there and a coin flies from there to the counter.
function CoinHud.collect(worldPosition: Vector3)
	if not gui then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local point, onScreen = camera:WorldToViewportPoint(worldPosition)
	local at = Vector2.new(point.X, point.Y)
	if not onScreen or point.Z <= 0 then
		-- behind you: it comes in from the bottom middle
		local size = camera.ViewportSize
		at = Vector2.new(size.X * 0.5, size.Y * 0.85)
	end
	local pop = freePop()
	pop.at = at
	pop.t = 0
	pop.live = true
	pop.text:set("+" .. tostring(C.VALUE))
	pop.text.root.Visible = true

	local flyer = freeFlyer()
	flyer.from = at
	flyer.t = 0
	flyer.trail = 0
	flyer.live = true
	flyer.image.Visible = true
	flying += 1
	windAt = os.clock()
	effectsIdle = false
end

---------------------------------------------------------------- building

local function buildWind(side: number)
	-- three faint white lines near one edge (side 0 left, 1 right)
	for k = 1, 3 do
		local line = Instance.new("Frame")
		line.Name = "Wind"
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = 1
		line.AnchorPoint = Vector2.new(side, 0.5)
		local inset = (k - 1) * 0.022 + 0.008
		line.Position = UDim2.new(if side == 0 then inset else 1 - inset, 0, 0.5 + (k - 2) * 0.06, 0)
		line.Size = UDim2.new(0, 2, 0.55 - (k - 1) * 0.12, 0)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = line
		line.ZIndex = 1
		line.Parent = layer
		table.insert(windLines, line)
	end
end

local function build()
	gui = PlasticUi.screen("TagRivalsCoins", 6)

	holder = Instance.new("Frame")
	holder.Name = "CoinCounter"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Size = UDim2.fromOffset(COUNTER_W, COUNTER_H + GAP + TAG_H)
	holder.Visible = false
	holder.ZIndex = 1
	holder.Parent = gui
	holderScale = Instance.new("UIScale")
	holderScale.Parent = holder

	-- the gold counter: the coin and your coins this round
	local counter = PlasticUi.block({
		name = "Counter",
		width = COUNTER_W,
		height = COUNTER_H,
		color = PlasticUi.GOLD,
		parent = holder,
	})
	counterRoot = counter.root
	counterRoot.AnchorPoint = Vector2.new(0.8, 0.5)
	counterRoot.Position = UDim2.fromOffset(COUNTER_W * 0.8, COUNTER_H / 2)
	counterScale = Instance.new("UIScale")
	counterScale.Parent = counterRoot

	icon = Instance.new("ImageLabel")
	icon.Name = "Coin"
	icon.BackgroundTransparency = 1
	icon.Image = C.IMAGES.ICON
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 6, 0.5, 0)
	icon.Size = UDim2.fromOffset(ICON, ICON)
	icon.ZIndex = 4
	icon.Parent = counter.face

	countText = PlasticUi.text({
		name = "Count",
		size = 34,
		parent = counter.face,
		zIndex = 4,
		align = Enum.TextXAlignment.Right,
	})
	countText.root.Position = UDim2.fromOffset(ICON + 10, 0)
	countText.root.Size = UDim2.new(1, -(ICON + 24), 1, 0)

	-- the shine that sweeps it when a coin lands
	shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.25
	shine.Size = UDim2.fromScale(1, 1)
	shine.ZIndex = 6
	shine.Visible = false
	shine.Parent = counter.face
	shineGradient = Instance.new("UIGradient")
	shineGradient.Rotation = 15
	shineGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 1),
		NumberSequenceKeypoint.new(0.47, 0.1),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	shineGradient.Parent = shine

	-- the blue tag: the speed your coins give you
	local tag = PlasticUi.block({
		name = "Speed",
		width = TAG_W,
		height = TAG_H,
		color = PlasticUi.PANEL,
		parent = holder,
		depth = 5,
	})
	tag.root.AnchorPoint = Vector2.new(1, 0)
	tag.root.Position = UDim2.new(1, 0, 0, COUNTER_H + GAP)
	speedText = PlasticUi.text({ name = "Bonus", size = 19, parent = tag.face, zIndex = 4 })
	speedText.root.Size = UDim2.fromScale(1, 1)
	speedGlow = Instance.new("Frame")
	speedGlow.Name = "Glow"
	speedGlow.BorderSizePixel = 0
	speedGlow.BackgroundColor3 = Color3.fromHex("BFE3FF")
	speedGlow.BackgroundTransparency = 1
	speedGlow.Size = UDim2.fromScale(1, 1)
	speedGlow.ZIndex = 3
	speedGlow.Parent = tag.face
	-- a soft blue halo round the tag (its own frame: the tag's outline already has the side's stroke)
	local haloFrame = Instance.new("Frame")
	haloFrame.Name = "Halo"
	haloFrame.BackgroundTransparency = 1
	haloFrame.Size = UDim2.fromScale(1, 1)
	haloFrame.ZIndex = 0
	haloFrame.Parent = tag.root
	speedHalo = Instance.new("UIStroke")
	speedHalo.Color = Color3.fromHex("78BEFF")
	speedHalo.Thickness = 0
	speedHalo.Transparency = 1
	speedHalo.Parent = haloFrame

	-- flyers, "+2"s, trail sparks and wind lines, over everything
	layer = Instance.new("Frame")
	layer.Name = "Effects"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 10
	layer.Parent = gui
	buildWind(0)
	buildWind(1)

	setCount(actualCoins())
	syncSpeed()
	gui.Parent = player:WaitForChild("PlayerGui")
end

---------------------------------------------------------------- every frame

-- 0 to 1 eased
local function smooth(u: number): number
	return u * u * (3 - 2 * u)
end

local function stepEffects(dt: number, scale: number)
	if effectsIdle then
		return
	end
	local busy = false
	-- where the coins fly to: the counter's coin (read only while one flies: reading where it is makes the screen
	-- lay itself out again, which costs a lot every frame)
	local target: Vector2? = nil
	for _, f in flyers do
		if f.live then
			busy = true
			if not target then
				-- the coin's middle on this screen's layer (absolute positions count from under Roblox's top bar, the
				-- layer from the screen's top, so take the layer's own position off)
				target = icon.AbsolutePosition - layer.AbsolutePosition + icon.AbsoluteSize / 2
			end
			local goal = target :: Vector2
			f.t += dt
			local u = math.min(f.t / FLY_TIME, 1)
			local e = smooth(u) * 0.35 + u * u * 0.65
			local control = Vector2.new((f.from.X + goal.X) / 2 - 40 * scale, math.min(f.from.Y, goal.Y) - 120 * scale)
			local a, b, c = (1 - e) * (1 - e), 2 * (1 - e) * e, e * e
			local at = f.from * a + control * b + goal * c
			f.image.Position = UDim2.fromOffset(at.X, at.Y)
			local size = 40 * scale * (1.25 - 0.4 * e)
			f.image.Size = UDim2.fromOffset(size, size)
			f.image.Rotation = u * 540
			f.trail += dt
			while f.trail >= TRAIL_EVERY and u < 0.97 do
				f.trail -= TRAIL_EVERY
				local s = freeSpark()
				if s then
					s.at = at
					s.drift = Vector2.new((math.random() * 2 - 1) * 8, (math.random() * 2 - 1) * 8) * scale
					s.t = 0
					s.live = true
					s.image.Visible = true
				end
			end
			if u >= 1 then
				f.live = false
				f.image.Visible = false
				flying = math.max(flying - 1, 0)
				-- it landed: the counter ticks up (never past what the server says you have)
				local actual = actualCoins()
				local landed = if flying == 0 then actual else math.min(shown + C.VALUE, actual)
				if landed > shown then
					setCount(landed)
				end
				punch()
			end
		end
	end
	for _, s in sparks do
		if s.live then
			busy = true
			s.t += dt
			local u = s.t / TRAIL_LIFE
			if u >= 1 then
				s.live = false
				s.image.Visible = false
			else
				local at = s.at + s.drift * u
				local size = 10 * scale * (1.4 - 1.2 * u)
				s.image.Position = UDim2.fromOffset(at.X, at.Y)
				s.image.Size = UDim2.fromOffset(size, size)
				s.image.ImageTransparency = 0.1 + 0.9 * u
			end
		end
	end
	for _, p in pops do
		if p.live then
			busy = true
			p.t += dt
			local u = p.t / POP_TIME
			if u >= 1 then
				p.live = false
				p.text.root.Visible = false
			else
				-- pops big, settles, rises and fades (the preview's keyframes)
				local rise, size, fade
				if u < 0.16 then
					local k = u / 0.16
					rise, size, fade = -10 * k, 0.3 + 1.05 * k, 1 - k
				elseif u < 0.6 then
					local k = (u - 0.16) / 0.44
					rise, size, fade = -10 - 24 * smooth(k), 1.35 - 0.35 * smooth(k), 0
				else
					local k = (u - 0.6) / 0.4
					rise, size, fade = -34 - 30 * k, 1 - 0.05 * k, k
				end
				p.text.root.Position = UDim2.fromOffset(p.at.X, p.at.Y - (30 - rise) * scale)
				p.text.root.Rotation = -4
				local uiScale = p.text.root:FindFirstChildOfClass("UIScale")
				if uiScale then
					uiScale.Scale = size * scale
				end
				p.text:setFade(fade)
			end
		end
	end
	-- the wind lines at the edges
	local w = (os.clock() - windAt) / WIND_TIME
	if w >= 0 and w < 1.2 then
		busy = true
		local see = if w >= 1 then 1 elseif w < 0.25 then 1 - 0.5 * (w / 0.25) else 0.5 + 0.5 * ((w - 0.25) / 0.75)
		for _, line in windLines do
			line.BackgroundTransparency = see
		end
	end
	if not busy then
		for _, line in windLines do
			line.BackgroundTransparency = 1
		end
		effectsIdle = true
	end
end

local function stepCounter(now: number)
	-- the punch: 20% bigger and a little turned, back with a wobble
	local p = (now - punchAt) / PUNCH_TIME
	if p >= 0 and p < 1 then
		local s, r
		if p < 0.33 then
			local k = p / 0.33
			s, r = 1.2 - 0.25 * k, -3 + 3 * k
		elseif p < 0.66 then
			local k = (p - 0.33) / 0.33
			s, r = 0.95 + 0.08 * k, 0
		else
			local k = (p - 0.66) / 0.34
			s, r = 1.03 - 0.03 * k, 0
		end
		counterScale.Scale = s
		counterRoot.Rotation = r
	elseif counterScale.Scale ~= 1 then
		counterScale.Scale = 1
		counterRoot.Rotation = 0
	end
	-- the shine sweeping across
	local sh = (now - shineAt) / SHINE_TIME
	if sh >= 0 and sh < 1 then
		shine.Visible = true
		shineGradient.Offset = Vector2.new(0.9 - 1.8 * sh, 0)
	elseif shine.Visible then
		shine.Visible = false
	end
	-- the speed tag glowing
	local g = (now - glowAt) / GLOW_TIME
	if g >= 0 and g < 1 then
		local k = 1 - g
		speedGlow.BackgroundTransparency = 1 - 0.55 * k * k
		speedHalo.Thickness = 3 + 6 * k
		speedHalo.Transparency = 1 - 0.8 * k
	elseif speedGlow.BackgroundTransparency < 1 then
		speedGlow.BackgroundTransparency = 1
		speedHalo.Transparency = 1
	end
end

-- Where the counter rests on this screen: its top (pixels down) and how big it's drawn. Just under the middle of the
-- right side; with the phone Dash button showing, lifted to just above its plate, and if that brings it up against the
-- runner counter, squeezed a little between the two.
local function placement(screen: Vector2, scale: number): (number, number)
	local top = screen.Y * 0.5 + C.HUD_MIDDLE_GAP * scale
	local dash = HudLayout.get("DashButton")
	if not dash then
		return top, scale
	end
	local floor = dash.top - HudLayout.GAP
	top = math.min(top, floor - TALL * scale)
	local runners = HudLayout.get("Runners")
	local left = screen.X - C.HUD_EDGE - COUNTER_W * scale
	if runners and left < runners.right + HudLayout.GAP then
		local ceiling = runners.bottom + HudLayout.GAP
		if top < ceiling then
			return ceiling, scale * math.max((floor - ceiling) / (TALL * scale), SQUEEZE_MIN)
		end
	end
	return top, scale
end

function CoinHud.start()
	build()
	player:GetAttributeChangedSignal(CoinRules.ATTR_ROUND_COINS):Connect(syncCount)
	player:GetAttributeChangedSignal(MoveRules.ATTR_STARS):Connect(syncSpeed)

	RunService.PreRender:Connect(function(dt: number)
		local now = os.clock()
		local on = showing()
		slide += ((if on then 0 else 1) - slide) * (1 - math.exp(-10 * dt))
		local visible = slide < 0.995
		holder.Visible = visible
		local scale = PlasticUi.screenScale()
		local screen = HudLayout.screen()
		local top, size = placement(screen, scale)
		-- where it rests, for the pieces that keep clear of it (the runner counter, the tag feed)
		HudLayout.report(
			"Coin",
			if on
				then HudLayout.rect(
					screen.X - C.HUD_EDGE - COUNTER_W * size,
					top - U_BOB,
					screen.X - C.HUD_EDGE,
					top + TALL * size + U_BOB
				)
				else nil
		)
		if visible then
			holderScale.Scale = size
			local bob, tilt = PlasticUi.motion(0.35)
			holder.Position = UDim2.new(1, -C.HUD_EDGE + slide * (COUNTER_W + 40) * size, 0, top + bob)
			holder.Rotation = tilt
			stepCounter(now)
		end
		stepEffects(dt, scale)
	end)
end

return CoinHud
