--!strict
-- Studio-only test bots, so one person can play a whole round in a Studio play-test (never in a live game). Each is a
-- plain R6 body in Workspace.TagBots that the round treats like a player: it wears the knife, gets a role, spawns
-- with everyone, runs with the real animations (BotAnim), and screens can tag it. A test starts with
-- Config.Dev.STUDIO_BOTS bots; the TEST BOTS panel (DevBotsPanel) changes how many, 0 to BOTS_MAX, at once.
-- They play like players (owner 2026-11-09: "can u make the bots smarter, they can use dashes"), a little slower so
-- a person can still win:
--   * every bot has the players' dash: 2 charges, each refilling in 1.5 s, the same 10 studs in 0.15 s, with the same
--     afterimages on every screen (the dash attributes a player's dash sets);
--   * a runner bot keeps an eye on every chaser near it, weighting the closest most, and runs away from them while
--     keeping off the edges and out of the corners (near an edge it slides along it instead of into it). When a chaser
--     gets close and is closing in, or dashes at it, it jukes: a sidestep dash across the chaser's line, away from the
--     nearest edge, after a short human-like reaction;
--   * a chaser bot picks a runner (the nearest, but one no other chaser is already after when it can), runs to cut it
--     off (where the runner will be, not where it is), and dashes once it's in dash range (the dash reach is 7.5);
--   * a chaser bot slashes and tags whoever it reaches, like a player's auto slash;
--   * stuns hold them like players (a new chaser stands still for a moment; a dodged one is slowed), and a runner bot
--     whose juke lands in the perfect-dodge window perfect-dodges its chaser.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local BotAnim = require(script.Parent.BotAnim)

local A = Config.Arena
local T = Config.Tag
local D = Config.Dash
local B = Config.Bots

local DevBots = {}

type Brain = {
	charge: number, -- dash charges, as MoveRules counts them
	lastDash: number, -- os.clock() of its newest dash
	dashUntil: number,
	dashDir: Vector3,
	dashSpeed: number, -- studs/s of the dash under way (a perfect dodge's is longer)
	exitSpeed: number, -- the speed it comes out of a dash with, easing back down
	wander: Vector3?,
	target: Instance?,
	targetSince: number,
	lastSlash: number,
	reactAt: number, -- when a juke it's decided on goes off (a short reaction time)
	jukeDir: Vector3?,
}

local folder: Folder? = nil
local wanted = Config.Dev.STUDIO_BOTS
local rng = Random.new()
local brains: { [Model]: Brain } = {}
local onTag: (chaser: Instance, runner: Instance, dash: boolean) -> boolean = function()
	return false
end
local onSlash: (chaser: Instance) -> () = function() end
local onDodge: (runner: Instance, chaser: Instance) -> boolean = function()
	return false
end

local BODY_COLORS = { "FF8AE6", "2EE6FF", "FFD23A", "7CFF6B", "B98CFF", "FF9F43" }

local function makeBot(name: string, index: number): Model?
	local description = Instance.new("HumanoidDescription")
	local color = Color3.fromHex(BODY_COLORS[(index - 1) % #BODY_COLORS + 1])
	description.HeadColor = Color3.fromHex("F2D2B6")
	description.TorsoColor = color
	description.LeftArmColor = Color3.fromHex("F2D2B6")
	description.RightArmColor = Color3.fromHex("F2D2B6")
	description.LeftLegColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	description.RightLegColor = color:Lerp(Color3.new(0, 0, 0), 0.4)
	local ok, body = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if not ok or not body then
		warn(`[{Config.GameName}] could not make a test bot: {body}`)
		return nil
	end
	local model = body :: Model
	model.Name = name
	model:SetAttribute(RoundRules.ATTR_BOT, true)
	model:SetAttribute(RoundRules.ATTR_NAME, name)
	model:SetAttribute(MoveRules.ATTR_ROLE, "Runner")
	model:SetAttribute(MoveRules.ATTR_DASH_COUNT, 0)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = name
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		local animate = model:FindFirstChild("Animate")
		if animate then
			animate:Destroy()
		end
	end
	return model
end

function DevBots.list(): { Model }
	local list: { Model } = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				table.insert(list, child)
			end
		end
	end
	return list
end

-- A name no bot has yet.
local function freeName(): (string, number)
	local taken: { [string]: boolean } = {}
	for _, bot in DevBots.list() do
		taken[bot.Name] = true
	end
	for i, name in Config.Dev.BOT_NAMES do
		if not taken[name] then
			return name, i
		end
	end
	local i = #Config.Dev.BOT_NAMES + 1
	while taken["Bot " .. i] do
		i += 1
	end
	return "Bot " .. i, i
end

local syncing = false

-- Makes or removes bots until there are as many as wanted. Spare bots that aren't playing go first; one in the round
-- goes too if it must (the round carries on without it).
function DevBots.sync()
	local holder = folder
	if not holder or syncing then
		return
	end
	syncing = true
	while #DevBots.list() < wanted do
		local name, index = freeName()
		local bot = makeBot(name, index)
		if not bot then
			break
		end
		bot.Parent = holder
		local root = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root:SetNetworkOwner(nil)
		end
		BotAnim.add(bot)
	end
	local list = DevBots.list()
	table.sort(list, function(a, b)
		local aIn = a:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
		local bIn = b:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
		if aIn ~= bIn then
			return not aIn -- not playing first
		end
		return a.Name > b.Name
	end)
	for i = 1, #list - wanted do
		list[i]:Destroy()
	end
	syncing = false
end

-- How many bots the tester wants (0 to BOTS_MAX); bots are made or removed at once.
function DevBots.setWanted(count: number)
	wanted = math.clamp(math.floor(count), 0, Config.Dev.BOTS_MAX)
	Workspace:SetAttribute(RoundRules.ATTR_STUDIO_BOTS, wanted)
	task.spawn(DevBots.sync)
end

local function brainOf(bot: Model): Brain
	local brain = brains[bot]
	if not brain then
		brain = {
			charge = D.MAX_CHARGES,
			lastDash = -math.huge,
			dashUntil = 0,
			dashSpeed = MoveRules.dashSpeed(),
			dashDir = Vector3.new(0, 0, -1),
			exitSpeed = 0,
			wander = nil,
			target = nil,
			targetSince = 0,
			lastSlash = -math.huge,
			reactAt = math.huge,
			jukeDir = nil,
		}
		brains[bot] = brain
	end
	return brain
end

function DevBots.place(bot: Model, spot: CFrame)
	bot:PivotTo(spot)
	local root = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	local brain = brainOf(bot)
	brain.wander = nil
	brain.target = nil
	brain.charge = D.MAX_CHARGES
	brain.dashUntil = 0
	brain.jukeDir = nil
	brain.reactAt = math.huge
end

function DevBots.folder(): Instance?
	return folder
end

local function rootOf(who: Instance): BasePart?
	local model = if who:IsA("Player") then who.Character else who
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unit(v: Vector3): Vector3
	return if v.Magnitude > 1e-4 then v.Unit else Vector3.zero
end

type Body = { who: Instance, root: BasePart, role: string, dashAt: number }

-- Everyone in the round with a body: players and bots, with their role and when they last dashed (server time).
local function contestants(): { Body }
	local list: { Body } = {}
	local function add(who: Instance)
		if who:GetAttribute(RoundRules.ATTR_IN_ROUND) == true then
			local root = rootOf(who)
			if root then
				local dashAt = who:GetAttribute(MoveRules.ATTR_DASH_AT)
				table.insert(list, {
					who = who,
					root = root,
					role = MoveRules.role(who:GetAttribute(MoveRules.ATTR_ROLE)),
					dashAt = if type(dashAt) == "number" then dashAt else -math.huge,
				})
			end
		end
	end
	for _, player in Players:GetPlayers() do
		add(player)
	end
	for _, bot in DevBots.list() do
		add(bot)
	end
	return list
end

-- Starts a dash the way `direction` points (flat), if a charge is ready. Sets the same attributes a player's dash does,
-- so every screen draws its afterimages.
local function dash(bot: Model, brain: Brain, direction: Vector3, distance: number?): boolean
	local now = os.clock()
	if now - brain.lastDash < D.MIN_GAP or not MoveRules.canSpend(brain.charge) then
		return false
	end
	if MoveRules.stunned(bot, Workspace:GetServerTimeNow()) then
		return false
	end
	local dir = unit(flat(direction))
	if dir.Magnitude < 0.5 then
		return false
	end
	brain.charge = MoveRules.spend(brain.charge)
	brain.lastDash = now
	brain.dashUntil = now + D.TIME
	brain.dashSpeed = (distance or D.DISTANCE) / D.TIME
	brain.dashDir = dir
	local count = bot:GetAttribute(MoveRules.ATTR_DASH_COUNT)
	bot:SetAttribute(MoveRules.ATTR_DASH_DIR, dir)
	bot:SetAttribute(MoveRules.ATTR_DASH_AT, Workspace:GetServerTimeNow())
	bot:SetAttribute(MoveRules.ATTR_DASH_COUNT, (if type(count) == "number" then count else 0) + 1)
	BotAnim.dash(bot, dir)
	return true
end

-- A push away from the square's edges, growing as the bot gets near one (corners push on both axes).
local function edgePush(position: Vector3, middle: Vector3, half: number): Vector3
	local push = Vector3.zero
	local start = half - B.EDGE_COMFORT
	local dx, dz = position.X - middle.X, position.Z - middle.Z
	if math.abs(dx) > start then
		push -= Vector3.new(math.sign(dx) * (math.abs(dx) - start) / B.EDGE_COMFORT, 0, 0)
	end
	if math.abs(dz) > start then
		push -= Vector3.new(0, 0, math.sign(dz) * (math.abs(dz) - start) / B.EDGE_COMFORT)
	end
	return push
end

-- While a cut is on its way, the half-side of what will be left (runner bots treat the red strip as off the map, so
-- they get off it); else `half`.
local function safeHalf(half: number): number
	local cut = Workspace:GetAttribute(RoundRules.ATTR_CUT_RADIUS)
	return if type(cut) == "number" and cut > 0 then math.min(half, cut) else half
end

-- Runs a runner bot: away from the chasers near it, off the edges, juking when one closes in or dashes at it.
local function runAway(bot: Model, brain: Brain, root: BasePart, everyone: { Body }, middle: Vector3, half: number): Vector3
	local position = root.Position
	local away = Vector3.zero
	local nearest: Body? = nil
	local nearestGap = math.huge
	for _, other in everyone do
		if other.role == "Chaser" and other.who ~= bot then
			local offset = flat(position - other.root.Position)
			local gap = offset.Magnitude
			if gap < B.THREAT_RANGE then
				-- closer chasers count far more
				away += unit(offset) * (1 / math.max(gap, 2)) ^ 1.5
				if gap < nearestGap then
					nearestGap, nearest = gap, other
				end
			end
		end
	end
	local now = os.clock()
	local push = edgePush(position, middle, half)
	if not nearest then
		-- nobody close: drift about the middle of the square
		local goal = brain.wander
		if not goal or flat(goal - position).Magnitude < 6 then
			goal = middle
				+ Vector3.new(rng:NextNumber(-1, 1) * half * 0.6, 0, rng:NextNumber(-1, 1) * half * 0.6)
			brain.wander = goal
		end
		return unit(flat((goal :: Vector3) - position) + push * 2)
	end
	brain.wander = nil
	local threat = nearest :: Body
	local direction = unit(away) + push * 1.6
	-- running into an edge: slide along it, the way that leads away from the chaser
	if push.Magnitude > 0.2 then
		local along = Vector3.new(-push.Z, 0, push.X)
		if along.Magnitude > 1e-3 then
			along = along.Unit
			if along:Dot(unit(away)) < 0 then
				along = -along
			end
			direction += along * push.Magnitude * 1.5
		end
	end

	-- a juke: sidestep across the chaser's line when it's closing in, or when it dashes at us
	local closing = flat(threat.root.AssemblyLinearVelocity - root.AssemblyLinearVelocity):Dot(unit(flat(position - threat.root.Position)))
	local chaserDashed = Workspace:GetServerTimeNow() - threat.dashAt < 0.2
	local danger = (nearestGap < B.JUKE_RANGE and closing > 4) or (chaserDashed and nearestGap < D.DISTANCE + T.DASH_REACH + 2)
	if danger and brain.jukeDir == nil and MoveRules.canSpend(brain.charge) and rng:NextNumber() < B.JUKE_CHANCE then
		local line = unit(flat(position - threat.root.Position))
		local side = Vector3.new(-line.Z, 0, line.X)
		-- the side away from the edges (and a little away from the chaser)
		if side:Dot(push) < 0 or (push.Magnitude < 0.05 and rng:NextNumber() < 0.5) then
			side = -side
		end
		brain.jukeDir = unit(side + line * 0.35)
		brain.reactAt = now + rng:NextNumber(B.REACTION_MIN, B.REACTION_MAX)
	end
	if brain.jukeDir and now >= brain.reactAt then
		-- a perfect dodge if the dash goes off in the window: the chaser just outside its reach, closing in (and then
		-- the dash goes further)
		local gap = flat(position - threat.root.Position).Magnitude
		local reach = if Workspace:GetServerTimeNow() - threat.dashAt < D.TIME + T.DASH_GRACE then T.DASH_REACH else T.REACH
		local perfect = gap > reach
			and gap <= reach + Config.Dodge.WINDOW
			and (closing >= Config.Dodge.MIN_CLOSING or chaserDashed)
		if dash(bot, brain, brain.jukeDir :: Vector3, if perfect then Config.Dodge.DASH_DISTANCE else nil) and perfect then
			onDodge(bot, threat.who)
		end
		brain.jukeDir = nil
		brain.reactAt = math.huge
	end
	return unit(direction)
end

-- Picks the runner a chaser bot goes after: the nearest, but one no other chaser bot is after when there's a choice;
-- sticks with it for a moment unless another is much nearer.
local function pickTarget(bot: Model, brain: Brain, root: BasePart, everyone: { Body }): Body?
	local position = root.Position
	local chased: { [Instance]: boolean } = {}
	for other, otherBrain in brains do
		if other ~= bot and otherBrain.target then
			chased[otherBrain.target :: Instance] = true
		end
	end
	local best: Body? = nil
	local bestScore = math.huge
	local current: Body? = nil
	for _, other in everyone do
		if other.role ~= "Chaser" then
			local gap = flat(other.root.Position - position).Magnitude
			local score = gap + (if chased[other.who] then B.SHARE_PENALTY else 0)
			if score < bestScore then
				best, bestScore = other, score
			end
			if other.who == brain.target then
				current = other
			end
		end
	end
	local now = os.clock()
	if current and best and current ~= best and now - brain.targetSince < B.TARGET_HOLD then
		local currentGap = flat(current.root.Position - position).Magnitude
		if currentGap < bestScore * 1.5 then
			return current
		end
	end
	if best and best.who ~= brain.target then
		brain.target = best.who
		brain.targetSince = now
	end
	return best
end

-- Runs a chaser bot: cuts its runner off and dashes in when it's in range; tags whoever it reaches.
local function hunt(bot: Model, brain: Brain, root: BasePart, everyone: { Body }, speed: number): Vector3
	local position = root.Position
	local now = os.clock()
	local dashing = now < brain.dashUntil + T.DASH_GRACE
	-- tag whoever's within reach (the dash reach during a dash); never while stunned
	local reach = if dashing then T.DASH_REACH else T.REACH
	if now - brain.lastSlash > B.SLASH_GAP and not MoveRules.stunned(bot, Workspace:GetServerTimeNow()) then
		for _, other in everyone do
			if other.role ~= "Chaser" and flat(other.root.Position - position).Magnitude <= reach
				and not MoveRules.safe(other.who, Workspace:GetServerTimeNow())
			then
				brain.lastSlash = now
				onSlash(bot)
				BotAnim.slash(bot)
				onTag(bot, other.who, dashing)
				break
			end
		end
	end
	local target = pickTarget(bot, brain, root, everyone)
	if not target then
		brain.target = nil
		return Vector3.zero
	end
	local theirs = target.root.Position
	local gap = flat(theirs - position).Magnitude
	-- where it'll be by the time we get there (a little less than all the way, so we don't overshoot a turn)
	local lead = math.clamp(gap / math.max(speed, 1), 0, B.LEAD_MAX) * B.LEAD_SHARE
	local aim = theirs + flat(target.root.AssemblyLinearVelocity) * lead
	local direction = unit(flat(aim - position))
	-- dash in once the dash and its reach cover the gap to where it's going
	local soon = theirs + flat(target.root.AssemblyLinearVelocity) * D.TIME
	local dashGap = flat(soon - position).Magnitude
	if dashGap <= D.DISTANCE + T.DASH_REACH - 1 and dashGap > T.REACH and rng:NextNumber() < B.DASH_CHANCE then
		dash(bot, brain, flat(soon - position))
	end
	return direction
end

local function think(bot: Model, brain: Brain, everyone: { Body }, dt: number)
	local humanoid = bot:FindFirstChildOfClass("Humanoid")
	local root = rootOf(bot)
	if not humanoid or not root then
		return
	end
	brain.charge = MoveRules.refill(brain.charge, dt)
	local role = MoveRules.role(bot:GetAttribute(MoveRules.ATTR_ROLE))
	-- (coins speed bots up too)
	local walk, sprint = MoveRules.topSpeeds(role, MoveRules.tagBonus(role), bot:GetAttribute(MoveRules.ATTR_STARS))
	local position = root.Position
	local playing = bot:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
	local state = Workspace:GetAttribute(RoundRules.ATTR_STATE)
	local now = os.clock()

	-- fell off a cut strip: no steering (and no invisible wall) until the round puts it back
	if bot:GetAttribute(MoveRules.ATTR_FALLING) ~= nil then
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero)
		brain.dashUntil = 0
		return
	end
	if bot:GetAttribute(MoveRules.ATTR_FROZEN) == true or (playing and state ~= "Match") then
		humanoid.WalkSpeed = 0
		humanoid:Move(Vector3.zero)
		return
	end

	-- in a dash: hold its speed and way
	if now < brain.dashUntil then
		local dashSpeed = brain.dashSpeed
		humanoid.WalkSpeed = dashSpeed
		humanoid:Move(brain.dashDir)
		root.AssemblyLinearVelocity = brain.dashDir * dashSpeed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		brain.exitSpeed = sprint + D.EXIT_EXTRA
		return
	end

	if not playing then
		-- wander about the lobby at a walk
		local goal = brain.wander
		if not goal or flat(goal - position).Magnitude < 3 then
			local angle = rng:NextNumber() * math.pi * 2
			local distance = Config.Lobby.RADIUS * 0.7 * math.sqrt(rng:NextNumber())
			goal = Vector3.new(A.CENTER.X + math.cos(angle) * distance, position.Y, A.CENTER.Z + math.sin(angle) * distance)
			brain.wander = goal
		end
		humanoid.WalkSpeed = walk * 0.5
		humanoid:Move(unit(flat((goal :: Vector3) - position)))
		return
	end

	local center = Workspace:GetAttribute(MoveRules.ATTR_ARENA_CENTER)
	local radius = Workspace:GetAttribute(MoveRules.ATTR_ARENA_RADIUS)
	local middle = if typeof(center) == "Vector3" then center else A.CENTER
	local half = if type(radius) == "number" then radius else A.SIZE / 2
	-- the invisible wall, for bots (players' own games keep themselves in)
	local fixed, outward = MoveRules.clampToArena(position, middle, half, A.EDGE_MARGIN)
	if outward then
		bot:PivotTo(bot:GetPivot() + (fixed - position))
		position = fixed
	end

	local pace = if role == "Chaser" then B.CHASER_PACE else B.RUNNER_PACE
	-- a stun slows it (or holds it still) like a player
	local top = sprint * pace * MoveRules.speedShare(bot, Workspace:GetServerTimeNow())
	-- out of a dash a little faster, easing back down
	brain.exitSpeed = math.max(brain.exitSpeed - D.EXIT_EXTRA * 4 * dt, 0)
	humanoid.WalkSpeed = math.max(top, brain.exitSpeed)
	local direction = if role == "Chaser"
		then hunt(bot, brain, root, everyone, top)
		else runAway(bot, brain, root, everyone, middle, safeHalf(half))
	humanoid:Move(direction)
end

-- Starts the bots (Studio only; does nothing in a live game). `tag` and `slash` are the round's.
function DevBots.start(
	tag: (chaser: Instance, runner: Instance, dash: boolean) -> boolean,
	slash: (chaser: Instance) -> (),
	dodge: (runner: Instance, chaser: Instance) -> boolean
): boolean
	if not RunService:IsStudio() or Config.Dev.BOTS_MAX <= 0 then
		return false
	end
	onTag, onSlash, onDodge = tag, slash, dodge
	local holder = Instance.new("Folder")
	holder.Name = "TagBots"
	holder.Parent = Workspace
	folder = holder
	Workspace:SetAttribute(RoundRules.ATTR_STUDIO_BOTS, wanted)
	-- the TEST BOTS panel's - and + (Studio only)
	local dev = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Dev") :: RemoteEvent
	dev.OnServerEvent:Connect(function(_, action, value)
		if action == "bots" and type(value) == "number" and value == value then
			DevBots.setWanted(value)
		end
	end)
	-- seconds each bot has gone without thinking (it thinks every other frame, below)
	local owed: { [Model]: number } = {}
	holder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			brains[child] = nil
			owed[child] = nil
		end
	end)
	BotAnim.start()
	-- decisions: a dashing bot every frame (it holds the dash's speed and way); the rest take turns, half of them a
	-- frame (a body keeps walking the way it was last sent). A Studio test runs the server and every bot on the same
	-- computer as your screen, so this keeps the frame rate up (owner 2026-11-09: "a consistent 60 fps").
	local turn = 0
	RunService.Heartbeat:Connect(function(dt: number)
		turn += 1
		local everyone = contestants()
		local now = os.clock()
		for index, bot in DevBots.list() do
			local brain = brainOf(bot)
			local due = (owed[bot] or 0) + dt
			if now < brain.dashUntil + 0.05 or (index + turn) % 2 == 0 then
				owed[bot] = 0
				think(bot, brain, everyone, due)
			else
				owed[bot] = due
			end
		end
	end)
	return true
end

return DevBots
