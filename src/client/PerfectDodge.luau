--!strict
-- The perfect dodge, from a runner's screen (owner 2026-11-09: "Introduce a prefect dodge, with like a small gold
-- animated star above when its a current window for a perfect dodge and the window should be pretty small for a
-- perfect dodge, then slows the tagger and make his screen monochrome for a little bit while hes stunned"):
--   * while you're a runner in the match, every frame this watches the chasers as drawn on your screen. The window is
--     open while one is just outside its reach of you (5.2 studs, or 7.5 while it's dashing) by no more than
--     Config.Dodge.WINDOW, and closing in (or dashing at you): about a tenth of a second at a sprint;
--   * while it's open, a small gold star spins and pulses over your head;
--   * dash while it's open (or a frame or two after) and your game tells the server, which checks it and stuns the
--     chaser (Tagging.perfectDodge): slowed, no dashing, no tagging. You get "PERFECT DODGE!" (RoundHud);
--   * a chaser who's been dodged sees the world in grey until the stun ends, fading back to colour.
--   * on the lobby, the practice dummy counts as a chaser while it lunges at you (PerfectDodge.practice), on your
--     screen only: the same window, the same star, the same words, but nothing is told to the server.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local MoveController = require(script.Parent.MoveController)
local PlasticUi = require(script.Parent.PlasticUi)
local TagFx = require(script.Parent.TagFx)

local O = Config.Dodge
local T = Config.Tag
local D = Config.Dash

local PerfectDodge = {}

local player = Players.LocalPlayer
local TagRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Tag") :: RemoteEvent

local lastGaps: { [Instance]: number } = {}
local closings: { [Instance]: number } = {}
local openAt = -math.huge -- os.clock() the window was last open
local openFor: Instance? = nil -- the chaser it was open for
local star: BillboardGui? = nil
local starShownAt = -math.huge
local dodgedAt = -math.huge -- os.clock() of your newest perfect dodge (the star bursts)
local grey: ColorCorrectionEffect? = nil
local practice: Model? = nil -- the lobby's practice dummy, while it's lunging at you
local practiceDodged: (() -> ())? = nil
local windowListeners: { () -> () } = {}

-- The practice dummy is lunging at you (`body`), or has stopped (nil). `dodged` is called if you perfect-dodge it.
function PerfectDodge.practice(body: Model?, dodged: (() -> ())?)
	practice = body
	practiceDodged = dodged
end

-- Hears each time the window opens and the gold star shows (Hints).
function PerfectDodge.onWindow(listener: () -> ())
	table.insert(windowListeners, listener)
end

local function bodyOf(who: Instance): Model?
	if who:IsA("Player") then
		return who.Character
	end
	return if who:IsA("Model") then who else nil
end

local function rootOf(who: Instance): BasePart?
	local body = bodyOf(who)
	local root = if body then body:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- Every chaser in the round, players and bots, but not one that's stunned (it can't tag).
local function chasers(now: number): { Instance }
	local list: { Instance } = {}
	local function consider(who: Instance)
		if who ~= player and who:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
			and MoveRules.role(who:GetAttribute(MoveRules.ATTR_ROLE)) == "Chaser"
			and not MoveRules.stunned(who, now)
		then
			table.insert(list, who)
		end
	end
	for _, other in Players:GetPlayers() do
		consider(other)
	end
	local bots = Workspace:FindFirstChild("TagBots")
	if bots then
		for _, bot in bots:GetChildren() do
			consider(bot)
		end
	end
	return list
end

-- The star over your head: a gold star with a black outline, spinning and pulsing, a soft glow behind it.
local function makeStar(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "TagRivalsDodgeStar"
	gui.Size = UDim2.fromScale(2.4, 2.4)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.ResetOnSpawn = false
	local glow = Instance.new("TextLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.5, 1.5)
	glow.Text = "★"
	glow.TextScaled = true
	glow.TextColor3 = Color3.fromHex("FFF1A8")
	glow.TextTransparency = 0.6
	glow.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Star"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "★"
	label.TextScaled = true
	label.TextColor3 = PlasticUi.GOLD
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function step(dt: number)
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	local mine = rootOf(player)
	local inRound = player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
	local inMatch = Workspace:GetAttribute(RoundRules.ATTR_STATE) == "Match"
		and inRound
		and MoveRules.role(player:GetAttribute(MoveRules.ATTR_ROLE)) ~= "Chaser"
	local dummy = if inRound then nil else practice
	local playing = inMatch or dummy ~= nil
	local open: Instance? = nil
	local openGap = math.huge
	if playing and mine then
		local seen: { [Instance]: boolean } = {}
		for _, chaser in if dummy then { dummy :: Instance } else chasers(serverNow) do
			local root = rootOf(chaser)
			if root then
				seen[chaser] = true
				local offset = root.Position - mine.Position
				local gap = Vector3.new(offset.X, 0, offset.Z).Magnitude
				-- how fast it's closing in, from how the gap shrinks (other bodies are drawn, not simulated, here)
				local last = lastGaps[chaser]
				local closing = closings[chaser] or 0
				if last and dt > 0 then
					closing += ((last - gap) / dt - closing) * math.min(dt * 20, 1)
				end
				lastGaps[chaser], closings[chaser] = gap, closing
				local dashAt = chaser:GetAttribute(MoveRules.ATTR_DASH_AT)
				local dashing = type(dashAt) == "number" and serverNow - dashAt < D.TIME + T.DASH_GRACE
				local reach = if dashing then T.DASH_REACH else T.REACH
				if gap > reach and gap <= reach + O.WINDOW and (closing >= O.MIN_CLOSING or dashing) and gap < openGap then
					open, openGap = chaser, gap
				end
			end
		end
		for chaser in lastGaps do
			if not seen[chaser] then
				lastGaps[chaser] = nil
				closings[chaser] = nil
			end
		end
	end
	if open then
		openAt = now
		openFor = open
	end

	-- the star: shown while the window is open (and the grace after), spinning and pulsing
	local gui = star
	if gui then
		local head = player.Character and player.Character:FindFirstChild("Head")
		local bursting = now - dodgedAt < 0.25
		local showing = (playing and now - openAt <= O.GRACE or bursting) and head ~= nil
		if showing and not gui.Enabled then
			starShownAt = now
			if not bursting then
				for _, listener in windowListeners do
					task.spawn(listener)
				end
			end
		end
		gui.Enabled = showing
		gui.Adornee = head
		if showing and not bursting then
			local age = now - starShownAt
			local pop = math.min(age / 0.08, 1)
			local pulse = 1 + 0.12 * math.sin(now * 30)
			local label = gui:FindFirstChild("Star") :: TextLabel
			local glow = gui:FindFirstChild("Glow") :: TextLabel
			label.Rotation = (now * 360) % 360
			label.Size = UDim2.fromScale(pop * pulse, pop * pulse)
			glow.Rotation = -(now * 200) % 360
			glow.Size = UDim2.fromScale(1.5 * pop * pulse, 1.5 * pop * pulse)
		end
	end

	-- the grey screen while a perfect dodge has you stunned
	local effect = grey
	if effect then
		local dodged = player:GetAttribute(MoveRules.ATTR_STUN_KIND) == "Dodged" and MoveRules.stunned(player, serverNow)
		local target = if dodged then -1 else 0
		local speed = if dodged then 1 / 0.08 else 1 / O.GREY_FADE
		local current = effect.Saturation
		if current ~= target then
			local stepSize = speed * dt
			effect.Saturation = if current < target then math.min(current + stepSize, target) else math.max(current - stepSize, target)
		end
		effect.Contrast = effect.Saturation * -0.15
		effect.Enabled = effect.Saturation < 0
	end
end

-- "PERFECT DODGE!" over a runner's head, on every screen: it pops, rises and fades.
local function headLabel(runner: Instance)
	local body = bodyOf(runner)
	local head = body and body:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "TagRivalsPerfectDodge"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(260, 60)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local words = PlasticUi.text({ name = "Words", size = 30, parent = gui, zIndex = 2 })
	words.root.Size = UDim2.fromScale(1, 1)
	words:set("PERFECT DODGE!")
	PlasticUi.shimmer(words.label, PlasticUi.GOLD, 0.7)
	local scale = Instance.new("UIScale")
	scale.Parent = words.root
	gui.Parent = player:WaitForChild("PlayerGui")
	local born = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.PreRender:Connect(function()
		local age = os.clock() - born
		if age >= O.LABEL_TIME or not head.Parent then
			connection:Disconnect()
			gui:Destroy()
			return
		end
		local x = age / O.LABEL_TIME
		local pop = if age < 0.15 then 0.5 + 0.7 * (age / 0.15) else 1.2 - 0.2 * math.min((age - 0.15) / 0.15, 1)
		scale.Scale = pop
		gui.StudsOffset = Vector3.new(0, 3 + 1.5 * x, 0)
		words.root.Rotation = -4 + 3 * math.sin(age * 12)
		words:setFade(if x > 0.7 then (x - 0.7) / 0.3 else 0)
	end)
end

function PerfectDodge.start()
	ReplicatedStorage.Remotes.Round.OnClientEvent:Connect(function(kind: string, info: any)
		if kind == "dodge" and type(info) == "table" and typeof(info.runner) == "Instance" then
			headLabel(info.runner)
			if info.runner == player then
				TagFx.shake(O.SHAKE)
				TagFx.fovPop(O.FOV_KICK)
				TagFx.edgeFlash(PlasticUi.GOLD)
			end
		end
	end)
	star = makeStar()
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "TagRivalsStunGrey"
	effect.Saturation = 0
	effect.Enabled = false
	effect.Parent = Lighting
	grey = effect
	-- a dash in the window goes further (Config.Dodge.DASH_DISTANCE)
	MoveController.setDashDistance(function(): number?
		if openFor and os.clock() - openAt <= O.GRACE then
			return O.DASH_DISTANCE
		end
		return nil
	end)
	-- your dash: a perfect dodge if the window is open (or only just shut)
	MoveController.onDash(function()
		local chaser = openFor
		if chaser and os.clock() - openAt <= O.GRACE then
			openAt = -math.huge
			dodgedAt = os.clock()
			if chaser == practice then
				-- practice: the same feel, but only on your screen
				headLabel(player)
				TagFx.shake(O.SHAKE * 0.6)
				TagFx.fovPop(O.FOV_KICK * 0.6)
				TagFx.edgeFlash(PlasticUi.GOLD)
				local dodged = practiceDodged
				if dodged then
					task.spawn(dodged)
				end
			else
				TagRemote:FireServer("dodge", chaser)
			end
			local gui = star
			if gui then
				-- the star bursts as you dodge
				local label = gui:FindFirstChild("Star") :: TextLabel
				label.Size = UDim2.fromScale(1.8, 1.8)
				TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
				task.delay(0.25, function()
					label.TextTransparency = 0
				end)
			end
		end
	end)
	RunService.PreRender:Connect(step)
end

return PerfectDodge
