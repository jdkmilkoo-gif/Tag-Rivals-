--!strict
-- Tagging from your own screen (design notes, Round flow; owner 2026-11-09: "no tag button. When a chaser gets close
-- enough, they automatically do a knife slash animation and VFX, and the runner is tagged"):
--   * once you're a chaser in the round, you draw the knife off your back and hold it (the server moves it to your
--     hand; your screen plays the draw and the hold, which only moves the right arm, so the run keeps going);
--   * every frame, while the match is on, any runner drawn within reach of you (5.2 studs between the bodies'
--     middles, 7.5 during your dash's burst) gets a slash: the slash animation, the blade's trail and the hit burst
--     straight away, and a claim to the server with what your screen saw (the runner's spot, yours, and the moment
--     of the runner's own clock Chrono drew them at). The server checks it (Tagging) and tells everyone;
--   * on a computer a chaser can also left-click to stab (owner 2026-11-09: "you can click to stab too btw, but only
--     pc"): the stab reaches a little further (6.5 studs) but only straight ahead (60 degrees either side of where you
--     face), every 0.6 s. A stab that reaches nobody still shows on every screen;
--   * every screen draws every chaser's slash (its trail and swing effects, KnifeFx), and on a tag: the runner's
--     white-and-red glow, the hit burst, and for the chaser the crimson screen edges and a quick FOV pop. A shrink
--     shakes the camera.
-- Held knives' own idle effects and pulsing light are KnifeFx's.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ChronoSetup = require(ReplicatedStorage.Shared.ChronoSetup)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local InputMode = require(script.Parent.InputMode)
local KnifeFx = require(script.Parent.KnifeFx)
local MoveController = require(script.Parent.MoveController)
local TagFx = require(script.Parent.TagFx)

local N = Config.Anim
local K = Config.Knife
local T = Config.Tag
local D = Config.Dash

local TagController = {}

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TagRemote = Remotes:WaitForChild("Tag") :: RemoteEvent
local RoundRemote = Remotes:WaitForChild("Round") :: RemoteEvent

type Tracks = {
	equip: AnimationTrack?,
	hold: AnimationTrack?,
	slashes: { AnimationTrack },
	stab: AnimationTrack?,
}

local tracks: Tracks? = nil
local armed = false -- holding the knife (a chaser in the round)
local lastSlash = -math.huge
local lastStab = -math.huge
local slashIndex = 0
local claimedAt: { [Instance]: number } = {}
local predicted: { [Instance]: number } = {} -- runners this screen already drew a hit on
local studioIds: { [string]: string }? = nil

local function animationId(value: unknown): string?
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	elseif type(value) == "string" and value ~= "" and value ~= "0" then
		return if string.find(value, "^%d+$") then "rbxassetid://" .. value else value
	end
	return nil
end

-- Studio only: temporary ids for the knife animations MoveServer shared (until they're uploaded).
local function studioId(name: string): string?
	if not RunService:IsStudio() then
		return nil
	end
	if not studioIds then
		local found: { [string]: string } = {}
		local folder = ReplicatedStorage:WaitForChild("StudioAnimations", 5)
		local names = { N.STUDIO_KNIFE_EQUIP, N.STUDIO_KNIFE_HOLD, N.STUDIO_KNIFE_STAB }
		for _, each in N.STUDIO_KNIFE_SLASHES do
			table.insert(names, each)
		end
		for _, each in names do
			local sequence = folder and folder:FindFirstChild(each)
			if sequence and sequence:IsA("KeyframeSequence") then
				local ok, id = pcall(function()
					return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
				end)
				if ok and id then
					found[each] = id
				end
			end
		end
		studioIds = found
	end
	return (studioIds :: { [string]: string })[name]
end

local function load(animator: Animator, name: string, id: string?, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	if not id then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		warn(`[{Config.GameName}] could not load the {name} animation ({id}): {track}`)
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

local function onCharacter(character: Model)
	tracks = nil
	armed = false
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local animator = humanoid and humanoid:WaitForChild("Animator", 10) :: Animator?
	if not animator or player.Character ~= character then
		return
	end
	local slashes: { AnimationTrack } = {}
	for i, studioName in N.STUDIO_KNIFE_SLASHES do
		local track = load(
			animator,
			"KnifeSlash" .. i,
			animationId(N.KnifeSlashAnimationIds[i]) or studioId(studioName),
			Enum.AnimationPriority.Action2,
			false
		)
		if track then
			table.insert(slashes, track)
		end
	end
	tracks = {
		equip = load(
			animator,
			"KnifeEquip",
			animationId(N.KnifeEquipAnimationId) or studioId(N.STUDIO_KNIFE_EQUIP),
			Enum.AnimationPriority.Action2,
			false
		),
		hold = load(
			animator,
			"KnifeHold",
			animationId(N.KnifeHoldAnimationId) or studioId(N.STUDIO_KNIFE_HOLD),
			Enum.AnimationPriority.Action,
			true
		),
		slashes = slashes,
		stab = load(
			animator,
			"KnifeStab",
			animationId(N.KnifeStabAnimationId) or studioId(N.STUDIO_KNIFE_STAB),
			Enum.AnimationPriority.Action2,
			false
		),
	}
end

local function inRound(who: Instance): boolean
	return who:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
end

local function roleOf(who: Instance): string
	return MoveRules.role(who:GetAttribute(MoveRules.ATTR_ROLE))
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

-- Draw the knife and hold it, or put the hold away.
local function setArmed(on: boolean)
	local t = tracks
	if not t then
		armed = false -- the body's animations aren't loaded yet: try again next frame
		return
	end
	if armed == on then
		return
	end
	armed = on
	if on then
		if t.equip then
			t.equip:Play(0.05, 1, 1.4)
		end
		if t.hold then
			t.hold:Play(0.25)
		end
	else
		if t.hold then
			t.hold:Stop(0.2)
		end
		if t.equip then
			t.equip:Stop(0.1)
		end
	end
end

-- Everyone the round could tag: players and Studio bots in the round, still runners.
local function targets(): { Instance }
	local list: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and inRound(other) and roleOf(other) ~= "Chaser"
			and not MoveRules.safe(other, Workspace:GetServerTimeNow())
		then
			table.insert(list, other)
		end
	end
	local bots = Workspace:FindFirstChild("TagBots")
	if bots then
		for _, bot in bots:GetChildren() do
			if inRound(bot) and roleOf(bot) ~= "Chaser" and not MoveRules.safe(bot, Workspace:GetServerTimeNow()) then
				table.insert(list, bot)
			end
		end
	end
	return list
end

local function slash(target: Instance, targetRoot: BasePart, myRoot: BasePart, dashing: boolean)
	local now = os.clock()
	lastSlash = now
	claimedAt[target] = now
	local t = tracks
	if t and #t.slashes > 0 then
		slashIndex = slashIndex % #t.slashes + 1
		local track = t.slashes[slashIndex]
		track:Play(0.04, 1, K.SLASH_SPEED)
		task.delay(K.SLASH_TIME, function()
			if track.IsPlaying then
				track:Stop(0.2)
			end
		end)
	end
	local body = player.Character
	if body then
		KnifeFx.swing(body)
	end
	local seen = targetRoot.Position
	local mine = myRoot.Position
	TagFx.hitBurst(seen + Vector3.new(0, 0.5, 0), (seen - mine) * Vector3.new(1, 0, 1))
	predicted[target] = now
	local seenAt = if target:IsA("Player") then ChronoSetup.renderTime(target) else nil
	TagRemote:FireServer(target, seen, mine, seenAt, dashing)
end

-- The way your body faces, flat.
local function facing(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

-- A left-click stab (computers only): the stab plays, and the nearest runner straight ahead within reach is claimed.
local function stab()
	local character = player.Character
	local myRoot = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not character or not myRoot then
		return
	end
	if not inRound(player) or roleOf(player) ~= "Chaser" then
		return
	end
	if Workspace:GetAttribute(RoundRules.ATTR_STATE) ~= "Match" or player:GetAttribute(MoveRules.ATTR_FROZEN) == true then
		return
	end
	if MoveRules.stunned(player, Workspace:GetServerTimeNow()) then
		return
	end
	local now = os.clock()
	if now - lastStab < T.STAB_GAP then
		return
	end
	lastStab = now
	lastSlash = now -- no automatic slash on top of the stab
	local t = tracks
	if t and t.stab then
		t.stab:Play(0.03, 1, K.STAB_SPEED)
	end
	KnifeFx.swing(character, true)

	local state = MoveController.state
	local dashing = state.dashing or now - state.dashAt < D.TIME + T.DASH_GRACE
	local reach = math.max(T.STAB_REACH, if dashing then T.DASH_REACH else T.REACH)
	local ahead = facing(myRoot)
	local cone = math.cos(math.rad(T.STAB_CONE))
	local mine = myRoot.Position
	local best: Instance? = nil
	local bestRoot: BasePart? = nil
	local bestGap = math.huge
	for _, target in targets() do
		local root = rootOf(target)
		if root then
			local offset = Vector3.new(root.Position.X - mine.X, 0, root.Position.Z - mine.Z)
			local gap = offset.Magnitude
			local inFront = gap < 1.5 or offset.Unit:Dot(ahead) >= cone
			if gap <= reach and inFront and math.abs(root.Position.Y - mine.Y) < 6 and gap < bestGap then
				best, bestRoot, bestGap = target, root, gap
			end
		end
	end
	if not best or not bestRoot then
		TagRemote:FireServer("swing")
		return
	end
	claimedAt[best] = now
	local seen = bestRoot.Position
	TagFx.hitBurst(seen + Vector3.new(0, 0.5, 0), ahead)
	predicted[best] = now
	local seenAt = if best:IsA("Player") then ChronoSetup.renderTime(best) else nil
	TagRemote:FireServer(best, seen, mine, seenAt, dashing, true)
end

local function step()
	local character = player.Character
	local myRoot = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local inMatch = Workspace:GetAttribute(RoundRules.ATTR_STATE) == "Match"
	local chasing = inRound(player) and roleOf(player) == "Chaser" and myRoot ~= nil
	setArmed(chasing)

	local now = os.clock()
	if not chasing or not inMatch or not myRoot or player:GetAttribute(MoveRules.ATTR_FROZEN) == true then
		return
	end
	-- stunned (just tagged, or perfect-dodged): no slashing
	if MoveRules.stunned(player, Workspace:GetServerTimeNow()) then
		return
	end
	if now - lastSlash < T.SLASH_GAP then
		return
	end
	local state = MoveController.state
	local dashing = state.dashing or now - state.dashAt < D.TIME + T.DASH_GRACE
	local reach = if dashing then T.DASH_REACH else T.REACH
	local mine = myRoot.Position
	local best: Instance? = nil
	local bestRoot: BasePart? = nil
	local bestGap = math.huge
	for _, target in targets() do
		local root = rootOf(target)
		if root and now - (claimedAt[target] or -math.huge) >= T.TARGET_GAP then
			local gap = (Vector3.new(root.Position.X - mine.X, 0, root.Position.Z - mine.Z)).Magnitude
			if gap <= reach and math.abs(root.Position.Y - mine.Y) < 6 and gap < bestGap then
				best, bestRoot, bestGap = target, root, gap
			end
		end
	end
	if best and bestRoot then
		slash(best, bestRoot, myRoot, dashing)
	end
end

local function onRound(kind: string, a: any, b: any)
	if kind == "slash" then
		-- another chaser's slash or stab (yours drew already)
		if a ~= player and typeof(a) == "Instance" then
			local body = bodyOf(a)
			if body then
				KnifeFx.swing(body, b == "stab")
			end
		end
	elseif kind == "tag" and type(a) == "table" then
		local info = a
		local runnerBody = if typeof(info.runner) == "Instance" then bodyOf(info.runner) else nil
		if runnerBody then
			TagFx.outline(runnerBody)
		end
		local mine = info.chaser == player
		local drawn = predicted[info.runner]
		if not (mine and drawn and os.clock() - drawn < 1.5) then
			local root = if typeof(info.runner) == "Instance" then rootOf(info.runner) else nil
			local at = if root then root.Position else info.at
			if typeof(at) == "Vector3" then
				TagFx.hitBurst(at + Vector3.new(0, 0.5, 0), nil)
			end
		end
		if mine then
			TagFx.edgeFlash()
			TagFx.fovPop(T.FOV_POP)
			TagFx.shake(T.TAG_SHAKE)
		elseif info.runner == player then
			TagFx.edgeFlash()
			TagFx.fovPop(T.FOV_POP * 0.6)
		end
	elseif kind == "fell" and type(a) == "table" then
		if a.who == player then
			TagFx.edgeFlash()
			TagFx.shake(T.TAG_SHAKE)
		end
	elseif kind == "shrink" and type(a) == "number" then
		TagFx.shake(RoundRules.shakeFor(a))
		TagFx.fovPop(T.FOV_POP * 0.5)
	end
end

function TagController.start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RoundRemote.OnClientEvent:Connect(onRound)
	RunService.Heartbeat:Connect(step)
	-- left-click stabs, on a computer only (owner: "only pc"); not when the click was on a button
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if InputMode.get() == "Keyboard" then
			stab()
		end
	end)
end

return TagController
