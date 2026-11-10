--!strict
-- Your own body's animations (design notes, Movement): idle, walk and sprint all play at once and their weights blend
-- by your speed, so one never snaps into the next (owner 2026-11-09: "find a walking animation from the same creator,
-- and blend those together"). While the walk and the sprint blend, the sprint is held at the same point of its stride
-- as the walk (each foot landing together), so the legs never fight. Both cycles speed up with your speed so feet
-- don't slide, the sprint more than the walk (owner: "play the sprinting animation faster"). Played on your own screen,
-- Roblox shows them to everyone. Roblox's own Animate script is removed (MoveServer).
-- The cycles are Config.Anim.WalkAnimationId and SprintAnimationId once uploaded. Until then a Studio play-test plays
-- them straight from their KeyframeSequences (MoveServer shares the ones in ServerStorage.Animations: TagRivals_Run,
-- TagRivals_Walk and the rest, see Config.Anim), and a live game falls back to Roblox's own walk.
-- Every time a foot lands, CharacterAnim.onStep tells the camera (the step shake).
-- Dashes and the idle (owner 2026-11-09: "i have installed a dash animation pack ... implement those animations"):
-- the idle is the pack's own; every dash plays a dash animation on top of the running, squeezed into DASH_ANIM_TIME. A
-- dash roughly the way you face plays one of the pack's three forward dashes, a different one from the last (owner: "use
-- all of them"); a dash off to one side is a sidestep: the left or right dash plays and your body keeps facing the same
-- way while it lasts.
-- Knife slashes and emotes go on top later at the Action priority.

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveController = require(script.Parent.MoveController)

local N = Config.Anim

-- One walk or sprint cycle: its id, how fast its feet move at normal speed, and where in it each foot lands.
type Cycle = { name: string, id: string, ref: number, steps: { number } }
type Layer = { track: AnimationTrack, weight: number, cycle: Cycle? }

local CharacterAnim = {}

type Studio = {
	walks: { Cycle },
	runs: { Cycle },
	dashes: { { name: string, id: string } },
	singles: { [string]: string }, -- KeyframeSequence name: temporary id (dash left/right, idle)
}
type DashKind = "forward" | "left" | "right"

local player = Players.LocalPlayer
local layers: { idle: Layer, walk: Layer, run: Layer }? = nil
local rootPart: BasePart? = nil
local currentAnimator: Animator? = nil
local currentHumanoid: Humanoid? = nil
local studio: Studio? = nil -- Studio only: the shared animations
local sideTracks: { [string]: AnimationTrack } = {} -- "left" and "right"
local forwardTracks: { AnimationTrack } = {} -- every forward dash, each dash a different one from the last
local lastForward = 0
local playingDash: AnimationTrack? = nil
local dashCount = 0
local rng = Random.new()
local lastPhase: number? = nil -- where the leading cycle was last frame (for spotting a foot landing)
local stepListeners: { (strength: number, side: number) -> () } = {}
local stepSide = 1

local MIN_WEIGHT = 0.0001 -- a track at exactly 0 counts as stopped; this keeps every cycle running in step

-- A foot landed: how strong the step is (a walking step is lighter than a sprinting one) and which foot (1 or -1).
function CharacterAnim.onStep(listener: (strength: number, side: number) -> ())
	table.insert(stepListeners, listener)
end

-- An animation id from a number or text ("123", "rbxassetid://123"); nil for 0 or "".
local function animationId(value: unknown): string?
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	elseif type(value) == "string" and value ~= "" and value ~= "0" then
		return if string.find(value, "^%d+$") then "rbxassetid://" .. value else value
	end
	return nil
end

-- Where in a KeyframeSequence (shares of it) the two feet land: the two ends of the right leg's swing.
local function stepsOf(sequence: KeyframeSequence): { number }
	local length, maxAt, minAt, maxZ, minZ = 0, 0, 0, -math.huge, math.huge
	local keyframes = sequence:GetKeyframes()
	for _, keyframe in keyframes do
		length = math.max(length, (keyframe :: Keyframe).Time)
	end
	for _, keyframe in keyframes do
		for _, pose in keyframe:GetDescendants() do
			if pose:IsA("Pose") and pose.Name == "Right Leg" then
				local _, _, z = pose.CFrame:ToEulerAnglesXYZ()
				local time = (keyframe :: Keyframe).Time
				if z > maxZ then
					maxZ, maxAt = z, time
				end
				if z < minZ then
					minZ, minAt = z, time
				end
			end
		end
	end
	if length <= 0 then
		return { 0.25, 0.75 }
	end
	return { maxAt / length, minAt / length }
end

-- Studio only: a temporary id (and for walks and runs, its foot landings) for each animation MoveServer shared.
local function getStudio(): Studio
	if studio then
		return studio
	end
	local found: Studio = { walks = {}, runs = {}, dashes = {}, singles = {} }
	if RunService:IsStudio() then
		local folder = ReplicatedStorage:WaitForChild("StudioAnimations", 5)
		local function register(name: string): (string?, KeyframeSequence?)
			local sequence = folder and folder:FindFirstChild(name)
			if sequence and sequence:IsA("KeyframeSequence") then
				local ok, id = pcall(function()
					return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
				end)
				if ok and id then
					return id, sequence
				end
			end
			return nil, nil
		end
		local function collect(names: { string }, ref: number, into: { Cycle })
			for _, name in names do
				local id, sequence = register(name)
				if id and sequence then
					table.insert(into, { name = name, id = id, ref = ref, steps = stepsOf(sequence) })
				end
			end
		end
		collect({ N.STUDIO_WALK }, N.WALK_REF, found.walks)
		collect({ N.STUDIO_RUN }, N.RUN_REF, found.runs)
		for _, name in N.STUDIO_DASHES do
			local id = register(name)
			if id then
				table.insert(found.dashes, { name = name, id = id })
			end
		end
		for _, name in { N.STUDIO_DASH_LEFT, N.STUDIO_DASH_RIGHT, N.STUDIO_IDLE } do
			local id = register(name)
			if id then
				found.singles[name] = id
			end
		end
	end
	studio = found
	return found
end

-- The idle: the uploaded one, else (in Studio) the pack's, else Roblox's own.
local function idleId(): string
	return animationId(N.IdleAnimationId) or getStudio().singles[N.STUDIO_IDLE] or N.IDLE
end

-- A sidestep animation's id (nil: none to play): the uploaded one, else (in Studio) the shared one.
local function sideId(kind: DashKind): string?
	if kind == "left" then
		return animationId(N.DashLeftAnimationId) or getStudio().singles[N.STUDIO_DASH_LEFT]
	end
	return animationId(N.DashRightAnimationId) or getStudio().singles[N.STUDIO_DASH_RIGHT]
end

-- The forward dashes' ids (all of them are used): the uploaded ones, else (in Studio) the shared ones.
local function forwardIds(): { string }
	local ids = {}
	for _, value in N.DashAnimationIds do
		local id = animationId(value)
		if id then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		for _, dash in getStudio().dashes do
			table.insert(ids, dash.id)
		end
	end
	return ids
end

-- The walk cycle: the uploaded one, else (in Studio) the chosen shared walk, else Roblox's own walk.
local function walkCycle(): Cycle
	local uploaded = animationId(N.WalkAnimationId)
	if uploaded then
		return { name = "Walk", id = uploaded, ref = N.WALK_REF, steps = N.WALK_STEPS }
	end
	local walks = getStudio().walks
	if #walks > 0 then
		return walks[1]
	end
	return { name = "Roblox walk", id = N.ROBLOX_WALK, ref = N.ROBLOX_WALK_REF, steps = { 0.25, 0.75 } }
end

-- The sprint cycle: the uploaded one, else (in Studio) the chosen shared run, else the walk cycle.
local function runCycle(): Cycle
	local uploaded = animationId(N.SprintAnimationId)
	if uploaded then
		return { name = "Sprint", id = uploaded, ref = N.RUN_REF, steps = N.RUN_STEPS }
	end
	local runs = getStudio().runs
	if #runs > 0 then
		return runs[1]
	end
	local walk = walkCycle()
	return { name = walk.name, id = walk.id, ref = walk.ref * N.RUN_REF / N.WALK_REF, steps = walk.steps }
end

local function load(animator: Animator, name: string, id: string, startWeight: number): AnimationTrack?
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
	track.Priority = Enum.AnimationPriority.Movement
	track.Looped = true
	track:Play(0, math.max(startWeight, MIN_WEIGHT), 1)
	return track
end

local function stopAll()
	if layers then
		for _, layer in layers :: any do
			layer.track:Stop(0.2)
		end
	end
	layers = nil
	for _, track in sideTracks do
		track:Stop(0)
	end
	for _, track in forwardTracks do
		track:Stop(0)
	end
	table.clear(sideTracks)
	table.clear(forwardTracks)
	lastForward = 0
	playingDash = nil
end

-- One dash animation as a one-shot on top of the running (Action priority), not playing yet.
local function loadDash(animator: Animator, name: string, id: string): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		return track
	end
	warn(`[{Config.GameName}] could not load the {name} animation ({id}): {track}`)
	return nil
end

local function onCharacter(character: Model)
	stopAll()
	rootPart = nil
	lastPhase = nil
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root or player.Character ~= character then
		return
	end
	-- In case a body ever arrives with Roblox's own Animate script, it goes (it would fight these).
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local animator = humanoid:WaitForChild("Animator", 10) :: Animator?
	if not animator or player.Character ~= character then
		return
	end
	local walk, run = walkCycle(), runCycle()
	local idleTrack = load(animator, "Idle", idleId(), 1)
	local walkTrack = load(animator, "Walk", walk.id, 0)
	local runTrack = load(animator, "Sprint", run.id, 0)
	if not idleTrack or not walkTrack or not runTrack then
		return
	end
	layers = {
		idle = { track = idleTrack, weight = 1 },
		walk = { track = walkTrack, weight = 0, cycle = walk },
		run = { track = runTrack, weight = 0, cycle = run },
	}
	rootPart = root
	currentAnimator = animator
	currentHumanoid = humanoid
	-- the dashes are loaded now, so the first one plays at once
	for index, id in forwardIds() do
		local track = loadDash(animator, "DashForward" .. index, id)
		if track then
			table.insert(forwardTracks, track)
		end
	end
	for _, kind in { "left", "right" } :: { DashKind } do
		local id = sideId(kind)
		local track = if id then loadDash(animator, "Dash" .. kind, id) else nil
		if track then
			sideTracks[kind] = track
		end
	end
end

-- The next forward dash: a random one of them, never the same as the last.
local function nextForward(): AnimationTrack?
	local count = #forwardTracks
	if count == 0 then
		return nil
	end
	local index = rng:NextInteger(1, count)
	if count > 1 and index == lastForward then
		index = index % count + 1
	end
	lastForward = index
	return forwardTracks[index]
end

-- A dash just started the way `direction` points: plays the forward dash or a sidestep (see the top).
local function onDash(direction: Vector3)
	local root, humanoid = rootPart, currentHumanoid
	if not root or not humanoid then
		return
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local kind: DashKind = "forward"
	if look.Magnitude > 1e-3 then
		look = look.Unit
		local angle = math.deg(math.acos(math.clamp(look:Dot(direction), -1, 1)))
		if angle >= N.SIDE_MIN and angle <= N.SIDE_MAX then
			-- the way round from your facing to the dash: up means it's to your left
			kind = if look:Cross(direction).Y > 0 then "left" else "right"
		end
	end
	local sidestep = kind ~= "forward" and sideTracks[kind] ~= nil
	local track = if sidestep then sideTracks[kind] else nextForward()
	if not track then
		return
	end
	if playingDash and playingDash ~= track then
		playingDash:Stop(0.05)
	end
	playingDash = track
	dashCount += 1
	local thisDash = dashCount
	local length = if track.Length > 0 then track.Length else 0.7
	track:Play(N.DASH_FADE_IN, 1, length / N.DASH_ANIM_TIME)
	task.delay(math.max(N.DASH_ANIM_TIME - N.DASH_FADE_OUT, 0), function()
		if dashCount == thisDash and playingDash == track then
			track:Stop(N.DASH_FADE_OUT)
			playingDash = nil
		end
	end)
	-- a sidestep keeps your body facing the same way while it lasts
	if sidestep then
		humanoid.AutoRotate = false
		task.delay(N.SIDESTEP_HOLD, function()
			if dashCount == thisDash and humanoid.Parent then
				humanoid.AutoRotate = true
			end
		end)
	else
		humanoid.AutoRotate = true
	end
end


local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local function phaseOf(track: AnimationTrack): number
	local length = track.Length
	if length <= 0 then
		return 0
	end
	return (track.TimePosition / length) % 1
end

-- Whether `step` (a share of the cycle) lies between `from` and `to`, the cycle having moved on from one to the other.
local function crossed(from: number, to: number, step: number): boolean
	if to >= from then
		return step > from and step <= to
	end
	return step > from or step <= to -- wrapped round the end of the cycle
end

local function step(dt: number)
	local current, root = layers, rootPart
	if not current or not root or not root.Parent then
		return
	end
	local state = MoveController.state
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	-- A dash is far faster than running: the legs show a fast sprint, not a blur.
	local legSpeed = math.min(speed, state.sprintTop + 4)

	local moveShare = smoothstep(N.MOVING, N.MOVING + 3, speed)
	local sprintShare = if state.dashing
		then 1
		else math.clamp((legSpeed - state.walkTop) / math.max(state.sprintTop - state.walkTop, 1), 0, 1)
	local targets = {
		idle = 1 - moveShare,
		walk = moveShare * (1 - sprintShare),
		run = moveShare * sprintShare,
	}
	local blend = 1 - math.exp(-N.BLEND * dt)
	for name, layer in current :: any do
		layer.weight += (targets[name] - layer.weight) * blend
		layer.track:AdjustWeight(math.max(layer.weight, MIN_WEIGHT), 0)
	end

	local walk, run = current.walk, current.run
	local walkCycleNow = walk.cycle :: Cycle
	local runCycleNow = run.cycle :: Cycle
	walk.track:AdjustSpeed(math.min(math.max(legSpeed, 1) / walkCycleNow.ref, N.MAX_RATE))
	run.track:AdjustSpeed(math.min(math.max(legSpeed, 1) / runCycleNow.ref, N.MAX_RATE))

	-- The leading cycle sets the stride; while both show, the other is held at the same point of it (each foot
	-- landing together), so blending never makes the legs fight.
	local runLeads = run.weight >= walk.weight
	local lead = if runLeads then run else walk
	local follow = if runLeads then walk else run
	local leadCycle = lead.cycle :: Cycle
	local followCycle = follow.cycle :: Cycle
	local phase = phaseOf(lead.track)
	if follow.weight > 0.02 and follow.track.Length > 0 then
		local followPhase = (phase - leadCycle.steps[1] + followCycle.steps[1]) % 1
		follow.track.TimePosition = followPhase * follow.track.Length
	end

	-- A foot landing: the leading cycle passing one of its landing points while you're on the ground and moving.
	local previous = lastPhase
	lastPhase = phase
	if previous and moveShare > 0.5 and not state.dashing then
		for _, landing in leadCycle.steps do
			if crossed(previous, phase, landing) then
				stepSide = -stepSide
				-- a walking step is lighter than a sprinting one, and both grow with your speed
				local gait = Config.Camera.STEP_WALK_SHARE + (1 - Config.Camera.STEP_WALK_SHARE) * sprintShare
				local strength = gait * math.clamp(legSpeed / math.max(state.sprintTop, 1), 0.4, 1.3)
				for _, listener in stepListeners do
					task.spawn(listener, strength, stepSide)
				end
			end
		end
	end
end

function CharacterAnim.start()
	MoveController.onDash(onDash)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RunService.PreRender:Connect(step)
end

return CharacterAnim
