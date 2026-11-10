--!strict
-- Your own body's movement (design notes, Movement):
--   * walk; hold Shift to sprint (always on with touch; L2 held or L3 clicked on a controller); no dead-stop; never
--     sprinting backwards (S, S+A, S+D);
--   * Space (A or R1 on a controller, the Dash button on touch) dashes the way you're holding, or forward when you hold
--     nothing. 2 charges, each refilling in 1 s, one after another; with none left Space does nothing. Never a jump;
--   * top speeds come from your role (Runner / Chaser / LastRunner, set by the server), plus the tag speed-up and your
--     stars. You speed up towards them rather than snapping, and acceleration rises with the speed;
--   * the invisible wall at the arena's edge keeps your body inside the square;
--   * if you're still on the red strip when it's cut off, you fall with it (owner 2026-11-10: "make the red let players
--     fall and become tagger"): your game lets go of your body (no wall, no walking, no dashing), nudges it clear of
--     the edge and lets it drop; the round makes you a chaser and puts you back (Round);
--   * while the round freezes you (the Frozen attribute: the fade to black, the victory screen) you stand still, can't
--     dash, and speed-ups don't show (the round's start speed and a new role aren't a "SPEED UP!").
-- Other scripts read MoveController.state and listen with onDash, onEmpty and onSpeedUp.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local InputMode = require(script.Parent.InputMode)

local M = Config.Move
local D = Config.Dash
local A = Config.Arena

local DashRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Dash") :: RemoteEvent
local RoundRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent
local S = Config.Shrink
local FALL_LETGO = 6 -- s: if the round never puts you back (a lost message), your game takes your body back anyway

export type State = {
	alive: boolean,
	role: string,
	sprinting: boolean,
	speed: number, -- your body's flat speed right now, studs/s
	walkTop: number,
	sprintTop: number,
	charge: number, -- dash charges, 0 to MAX_CHARGES (whole charges plus the one refilling)
	dashing: boolean,
	dashAt: number, -- os.clock() of your newest dash (-inf: none yet)
	dashDir: Vector3,
	dashSpeed: number, -- studs/s of the dash under way (a perfect dodge's dash is longer)
}

local MoveController = {}

local player = Players.LocalPlayer

local state: State = {
	alive = false,
	role = "Runner",
	sprinting = false,
	speed = 0,
	walkTop = M.SPEEDS.Runner.walk,
	sprintTop = M.SPEEDS.Runner.sprint,
	charge = D.MAX_CHARGES,
	dashing = false,
	dashAt = -math.huge,
	dashDir = Vector3.new(0, 0, -1),
	dashSpeed = MoveRules.dashSpeed(),
}
MoveController.state = state

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local sprintHeld = false -- Shift or L2 held
local sprintToggled = false -- L3 clicked on
local running = 0 -- the speed you've worked up to (the Humanoid's WalkSpeed outside a dash)
local dashEndsAt = 0
local lastSprintTop: number? = nil -- nil right after a new body, so spawning never shows SPEED UP!
local fallingSince: number? = nil -- os.clock() your body went over the edge of a cut strip (nil: it didn't)

local dashListeners: { (direction: Vector3) -> () } = {}
local dashDistanceFor: (() -> number?)? = nil -- says how far the next dash goes (nil: the normal DISTANCE)

-- Lets another script say how far a dash goes when it starts (PerfectDodge: a perfect dodge's dash is longer).
function MoveController.setDashDistance(provider: () -> number?)
	dashDistanceFor = provider
end
local emptyListeners: { () -> () } = {}
local speedUpListeners: { (from: number, to: number) -> () } = {}

local function fire(list: { any }, ...: any)
	for _, listener in list do
		task.spawn(listener, ...)
	end
end

-- Your dash, the moment it starts: its flat direction.
function MoveController.onDash(listener: (direction: Vector3) -> ())
	table.insert(dashListeners, listener)
end

-- You pressed dash with no charge left.
function MoveController.onEmpty(listener: () -> ())
	table.insert(emptyListeners, listener)
end

-- Your sprint top speed went up (a tag, a star, a faster role): from and to, studs/s.
function MoveController.onSpeedUp(listener: (from: number, to: number) -> ())
	table.insert(speedUpListeners, listener)
end

local function isFrozen(): boolean
	return player:GetAttribute(MoveRules.ATTR_FROZEN) == true
end

-- Are you falling off a cut strip (your own game let go of your body, or the round says you fell)?
function MoveController.isFalling(): boolean
	local since = fallingSince
	if since and os.clock() - since > FALL_LETGO then
		fallingSince = nil
		since = nil
	end
	return since ~= nil or player:GetAttribute(MoveRules.ATTR_FALLING) ~= nil
end

-- The strip round the edge was just cut off, leaving the square `half` studs from its middle to an edge: if your body
-- is still on it, it goes over the edge (nudged clear so it doesn't catch, pushed outward) and falls.
local function onCut(half: number)
	local h, root = humanoid, rootPart
	if not h or not root or h.Health <= 0 or fallingSince then
		return
	end
	if player:GetAttribute(RoundRules.ATTR_IN_ROUND) ~= true then
		return
	end
	if Workspace:GetAttribute(RoundRules.ATTR_STATE) ~= "Match" then
		return
	end
	local center = Workspace:GetAttribute(MoveRules.ATTR_ARENA_CENTER)
	if typeof(center) ~= "Vector3" then
		return
	end
	local out, past = MoveRules.pastEdge(root.Position, center, half)
	if not out then
		return
	end
	fallingSince = os.clock()
	state.dashing = false
	dashEndsAt = 0
	running = 0
	if past < S.FALL_CLEAR then
		root.CFrame += out * (S.FALL_CLEAR - past)
	end
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = out * S.FALL_PUSH + Vector3.new(0, math.min(velocity.Y, 0), 0)
	h:ChangeState(Enum.HumanoidStateType.Freefall)
end

local function wantsSprint(): boolean
	return sprintHeld or sprintToggled or InputMode.isTouch()
end

-- Are you moving backwards, away from where the camera looks (S, S+A, S+D)? You can't sprint backwards (owner
-- 2026-11-09: "if the player is walking backwards like holding s and s+A and s+d, they cant sprint").
local function goingBackwards(direction: Vector3): boolean
	local camera = Workspace.CurrentCamera
	-- only in a round (the camera steers you there); on the lobby your body turns the way you walk
	if not camera or direction.Magnitude < 0.05 or player:GetAttribute("InRound") ~= true then
		return false
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return false
	end
	return Vector3.new(direction.X, 0, direction.Z).Unit:Dot(flat.Unit) < -0.2
end

-- Dashes now if a charge is ready. Gives back whether it dashed.
function MoveController.dash(): boolean
	local h, root = humanoid, rootPart
	if not h or not root or h.Health <= 0 or isFrozen() or MoveController.isFalling() then
		return false
	end
	-- stunned (just tagged, or perfect-dodged): no dashing
	if MoveRules.stunned(player, Workspace:GetServerTimeNow()) then
		return false
	end
	local now = os.clock()
	if now - state.dashAt < D.MIN_GAP then
		return false
	end
	if not MoveRules.canSpend(state.charge) then
		fire(emptyListeners)
		return false
	end
	state.charge = MoveRules.spend(state.charge)
	local direction = MoveRules.dashDirection(h.MoveDirection, root.CFrame.LookVector)
	state.dashing = true
	state.dashAt = now
	state.dashDir = direction
	local provider = dashDistanceFor
	local distance = if provider then provider() else nil
	state.dashSpeed = (distance or D.DISTANCE) / D.TIME
	dashEndsAt = now + D.TIME
	DashRemote:FireServer(direction)
	fire(dashListeners, direction)
	return true
end

---------------------------------------------------------------- every frame

-- After Roblox's controls have read the keys this frame (they run at the Input priority), so our Move wins in a dash.
local function updateSpeed(dt: number)
	local role = MoveRules.role(player:GetAttribute(MoveRules.ATTR_ROLE))
	local walkTop, sprintTop = MoveRules.topSpeeds(
		role,
		MoveRules.tagBonus(role),
		player:GetAttribute(MoveRules.ATTR_STARS)
	)
	local frozen = isFrozen()
	if lastSprintTop and sprintTop > lastSprintTop + 0.01 and not frozen then
		fire(speedUpListeners, lastSprintTop, sprintTop)
	end
	lastSprintTop = sprintTop
	-- a stun slows you (or holds you still) for a moment; the speed-up call-out goes by your unslowed speed
	local share = MoveRules.speedShare(player, Workspace:GetServerTimeNow())
	walkTop, sprintTop = walkTop * share, sprintTop * share
	state.role, state.walkTop, state.sprintTop = role, walkTop, sprintTop
	state.charge = MoveRules.refill(state.charge, dt)

	local h, root = humanoid, rootPart
	if not h or not root or h.Health <= 0 then
		state.alive = false
		state.sprinting = false
		return
	end
	state.alive = true
	local velocity = root.AssemblyLinearVelocity
	state.speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if frozen or share <= 0 or MoveController.isFalling() then
		state.sprinting = false
		state.dashing = false
		dashEndsAt = 0
		running = 0
		h.WalkSpeed = 0
		return
	end

	local now = os.clock()
	local moving = h.MoveDirection.Magnitude > 0.05
	if now < dashEndsAt then
		state.sprinting = true
		h:Move(state.dashDir, false)
		h.WalkSpeed = state.dashSpeed
		return
	end
	if state.dashing then
		-- out of the dash a little faster than you run, easing back down
		state.dashing = false
		running = (if wantsSprint() then sprintTop else walkTop) + D.EXIT_EXTRA
	end
	state.sprinting = moving and wantsSprint() and not goingBackwards(h.MoveDirection)
	if not moving then
		running = walkTop * M.START_SHARE
	else
		local target = if state.sprinting then sprintTop else walkTop
		running = MoveRules.ramp(math.max(running, walkTop * M.START_SHARE), target, MoveRules.accel(role, sprintTop), dt)
	end
	h.WalkSpeed = running
end

-- Before physics: in a dash, hold the dash's speed exactly (the Humanoid alone takes a few frames to reach it).
local function holdDash()
	local root = rootPart
	if not root or not state.dashing or os.clock() >= dashEndsAt then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = state.dashDir * state.dashSpeed + Vector3.new(0, velocity.Y, 0)
end

-- After physics: the invisible wall. Only near the floor, so the lobby above the circle is free.
local function keepInside()
	local h, root = humanoid, rootPart
	if not h or not root or h.Health <= 0 or MoveController.isFalling() then
		return
	end
	local center = Workspace:GetAttribute(MoveRules.ATTR_ARENA_CENTER)
	local radius = Workspace:GetAttribute(MoveRules.ATTR_ARENA_RADIUS)
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" then
		return
	end
	local position = root.Position
	if math.abs(position.Y - center.Y) > A.WALL_HEIGHT then
		return
	end
	local fixed, outward = MoveRules.clampToArena(position, center, radius, A.EDGE_MARGIN)
	if outward then
		root.CFrame += fixed - position
		local velocity = root.AssemblyLinearVelocity
		local out = velocity:Dot(outward)
		if out > 0 then
			root.AssemblyLinearVelocity = velocity - outward * out
		end
	end
end

---------------------------------------------------------------- bodies and keys

local function onCharacter(character: Model)
	local h = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not h or not root or player.Character ~= character then
		return
	end
	humanoid, rootPart = h, root
	-- Your own game runs your body, so no-jumping has to be set here too.
	h.UseJumpPower = false
	h.JumpHeight = 0
	h:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	state.charge = D.MAX_CHARGES
	state.dashing = false
	state.dashAt = -math.huge
	dashEndsAt = 0
	running = 0
	lastSprintTop = nil
	fallingSince = nil
end

local function onDashAction(_: string, inputState: Enum.UserInputState, _input: InputObject)
	if inputState == Enum.UserInputState.Begin then
		MoveController.dash()
	end
	-- Swallowed, so Roblox's jump never sees Space or A.
	return Enum.ContextActionResult.Sink
end

local function onSprintAction(_: string, inputState: Enum.UserInputState, input: InputObject)
	if input.KeyCode == Enum.KeyCode.ButtonL3 then
		if inputState == Enum.UserInputState.Begin then
			sprintToggled = not sprintToggled
		end
	else
		sprintHeld = inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.Change
	end
	return Enum.ContextActionResult.Sink
end

function MoveController.start()
	-- Above Roblox's own bindings (jump and shift lock sit at Medium), so these win.
	local priority = Enum.ContextActionPriority.High.Value
	ContextActionService:BindActionAtPriority(
		"TagRivalsDash",
		onDashAction,
		false,
		priority,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonR1
	)
	ContextActionService:BindActionAtPriority(
		"TagRivalsSprint",
		onSprintAction,
		false,
		priority,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.ButtonL2,
		Enum.KeyCode.ButtonL3
	)
	-- Alt-tabbing away while holding Shift never sends its release.
	UserInputService.WindowFocusReleased:Connect(function()
		sprintHeld = false
	end)

	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function(character)
		if humanoid and humanoid.Parent == character then
			humanoid, rootPart = nil, nil
		end
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	RunService:BindToRenderStep("TagRivalsMove", Enum.RenderPriority.Input.Value + 1, updateSpeed)
	RunService.PreSimulation:Connect(holdDash)
	RunService.PostSimulation:Connect(keepInside)
	-- a cut: the Round remote's "shrink" says the half-side before and after (Round)
	RoundRemote.OnClientEvent:Connect(function(kind: string, _count: any, _outer: any, inner: any)
		if kind == "shrink" and type(inner) == "number" then
			onCut(inner)
		end
	end)
end

return MoveController
