--!strict
-- The bots' animations, so they look like players instead of sliding about stiff (owner 2026-11-09: "can u make the
-- bots smarter"): the same idle, walk and sprint as a player's body, blended by speed and played faster as they run
-- faster; a dash animation on every dash; for a chaser bot, the knife hold, and a slash when it tags; and at the end
-- of a match a cheer or a dance for the winners and a slump for the rest (Config.Celebrate).
-- Played on the server (the bots are the server's), so every screen sees them. Uses the uploaded animation ids in
-- Config.Anim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)

local N = Config.Anim
local K = Config.Knife

local BotAnim = {}

type Set = {
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	run: AnimationTrack?,
	hold: AnimationTrack?,
	slashes: { AnimationTrack },
	dashes: { AnimationTrack },
	slashIndex: number,
	dashIndex: number,
	holding: boolean,
	animator: Animator,
	party: AnimationTrack?, -- the celebration playing now
}

local sets: { [Model]: Set } = {}
local MIN_WEIGHT = 0.0001

local function animationId(value: unknown): string?
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	elseif type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function load(animator: Animator, value: unknown, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local id = animationId(value)
	if not id then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = priority
	track.Looped = looped
	return track
end

-- Gets a bot's animations ready (call once, after it's in the world).
function BotAnim.add(bot: Model)
	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local made = Instance.new("Animator")
		made.Parent = humanoid
		animator = made
	end
	local a = animator :: Animator
	local set: Set = {
		idle = load(a, N.IdleAnimationId, Enum.AnimationPriority.Movement, true),
		walk = load(a, N.WalkAnimationId, Enum.AnimationPriority.Movement, true),
		run = load(a, N.SprintAnimationId, Enum.AnimationPriority.Movement, true),
		hold = load(a, N.KnifeHoldAnimationId, Enum.AnimationPriority.Action, true),
		slashes = {},
		dashes = {},
		slashIndex = 0,
		dashIndex = 0,
		holding = false,
		animator = a,
		party = nil,
	}
	for _, value in N.KnifeSlashAnimationIds do
		local track = load(a, value, Enum.AnimationPriority.Action2, false)
		if track then
			table.insert(set.slashes, track)
		end
	end
	for _, value in N.DashAnimationIds do
		local track = load(a, value, Enum.AnimationPriority.Action, false)
		if track then
			table.insert(set.dashes, track)
		end
	end
	for _, track in { set.idle, set.walk, set.run } do
		if track then
			track:Play(0, MIN_WEIGHT, 1)
		end
	end
	sets[bot] = set
end

-- A dash: one of the forward dashes, taking turns, squeezed into the dash's time as a player's is.
function BotAnim.dash(bot: Model, _direction: Vector3)
	local set = sets[bot]
	if not set or #set.dashes == 0 then
		return
	end
	set.dashIndex = set.dashIndex % #set.dashes + 1
	local track = set.dashes[set.dashIndex]
	local length = if track.Length > 0 then track.Length else 0.7
	track:Play(N.DASH_FADE_IN, 1, length / N.DASH_ANIM_TIME)
	task.delay(math.max(N.DASH_ANIM_TIME - N.DASH_FADE_OUT, 0), function()
		if track.IsPlaying then
			track:Stop(N.DASH_FADE_OUT)
		end
	end)
end

-- A slash (a chaser bot tagging), the two slashes taking turns.
function BotAnim.slash(bot: Model)
	local set = sets[bot]
	if not set or #set.slashes == 0 then
		return
	end
	set.slashIndex = set.slashIndex % #set.slashes + 1
	local track = set.slashes[set.slashIndex]
	track:Play(0.04, 1, K.SLASH_SPEED)
	task.delay(K.SLASH_TIME, function()
		if track.IsPlaying then
			track:Stop(0.2)
		end
	end)
end

-- The match is over: a winner cheers or dances, anyone else slumps. Roblox's own R6 emotes (Config.Celebrate).
function BotAnim.celebrate(bot: Model, won: boolean)
	local set = sets[bot]
	if not set then
		return
	end
	BotAnim.calm(bot)
	local E = Config.Celebrate
	local id: string
	if not won then
		id = E.SLUMP
	elseif math.random() < 0.5 then
		id = E.CHEER
	else
		id = E.DANCE[math.random(1, #E.DANCE)]
	end
	local track = load(set.animator, id, Enum.AnimationPriority.Action3, true)
	if track then
		set.party = track
		track:Play(0.25)
	end
end

-- Back to normal (the round moved the bot somewhere new).
function BotAnim.calm(bot: Model)
	local set = sets[bot]
	local track = if set then set.party else nil
	if set and track then
		set.party = nil
		track:Stop(0.2)
		track:Destroy()
	end
end

-- Blends idle, walk and sprint by speed, and holds the knife while chasing (a few times a second is plenty).
local function update()
	for bot, set in sets do
		if not bot.Parent then
			sets[bot] = nil
			continue
		end
		local root = bot:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local idleW = math.clamp(1 - speed / 3, 0, 1)
		local runShare = math.clamp((speed - 18) / 8, 0, 1)
		local walkW = (1 - idleW) * (1 - runShare)
		local runW = (1 - idleW) * runShare
		if set.idle then
			set.idle:AdjustWeight(math.max(idleW, MIN_WEIGHT), 0.15)
		end
		if set.walk then
			set.walk:AdjustWeight(math.max(walkW, MIN_WEIGHT), 0.15)
			set.walk:AdjustSpeed(math.clamp(speed / N.WALK_REF, 0.5, N.MAX_RATE))
		end
		if set.run then
			set.run:AdjustWeight(math.max(runW, MIN_WEIGHT), 0.15)
			set.run:AdjustSpeed(math.clamp(speed / N.RUN_REF, 0.5, N.MAX_RATE))
		end
		local chasing = bot:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
			and MoveRules.role(bot:GetAttribute(MoveRules.ATTR_ROLE)) == "Chaser"
		if set.hold and chasing ~= set.holding then
			set.holding = chasing
			if chasing then
				set.hold:Play(0.2)
			else
				set.hold:Stop(0.2)
			end
		end
	end
end

function BotAnim.start()
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= 0.1 then
			since = 0
			update()
		end
	end)
end

return BotAnim
