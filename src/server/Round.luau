--!strict
-- The round (design notes, Round flow), over and over:
--   Waiting       fewer than MIN_PLAYERS: everyone waits on the glass lobby above the circle.
--   Intermission  30 s on the lobby, watching the circle below (Config.Round.INTERMISSION).
--   Teleport      2 s: every screen fades to black; in the dark the chaser is picked (never the same one twice running
--                 when there's a choice), the square is reset to its full 250 a side, the starting speed set
--                 by the player count, and everyone gets a fresh body: runners spread round the circle, the chaser in
--                 the middle with the knife in hand. Everyone is frozen until the match starts.
--   Match         2 min. Tagged runners become chasers. Every tag speeds everyone up a little; every 30 s the square
--                 shrinks 10%: for 3 s the strip round the edge that's going glows red with a countdown, then it's
--                 cut off and falls away, and anyone still on it falls too: a runner who falls becomes a chaser
--                 (owner 2026-11-10: "make the red let players fall and become tagger"). Phases go by runners left.
--                 Ends early when no runner is left.
--   Cleanup       5 s: everyone frozen, no more tagging, the victory screen; then everyone goes back to the lobby.
-- Players joining mid-round wait on the lobby. Bots fill a round that's short of players (DevBots).
-- What each moment pays (coins, XP, the bounty, quests, the saved stats) is Rewards' job: this only tells it.
-- Every screen reads the round from Workspace and player attributes (RoundRules names them) and hears the moments
-- (the fade, the chaser, a tag, a shrink, the result) on the Round remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Arena = require(script.Parent.Arena)
local Coins = require(script.Parent.Coins)
local History = require(script.Parent.History)
local Knives = require(script.Parent.Knives)
local Lobby = require(script.Parent.Lobby)
local MoveServer = require(script.Parent.MoveServer)
local Rewards = require(script.Parent.Rewards)

local R = Config.Round
local S = Config.Shrink

-- The bots, when there are any (DevBots).
export type Bots = {
	list: () -> { Model },
	sync: () -> (), -- makes or removes bots until there are as many as the round wants
	place: (bot: Model, spot: CFrame) -> (),
	celebrate: (winner: string) -> (), -- the match is over: the winners among them cheer
}

export type TagInfo = {
	chaser: Instance,
	runner: Instance,
	chaserName: string,
	runnerName: string,
	dash: boolean,
	at: Vector3?,
}

local Round = {}

local remote: RemoteEvent = nil :: any
local state: RoundRules.State = "Waiting"
local contestants: { Instance } = {}
local spots: { [Player]: CFrame } = {}
local runnersAtStart = 0
local lastChaser: Instance? = nil
local shrinkCount = 0
local matchStart = 0
local respawn: (player: Player) -> () = function() end
local bots: Bots? = nil
local rng = Random.new()
local placedAt: { [Instance]: number } = {} -- os.clock() each one was last sent somewhere (their body may be building)
local falling: { [Instance]: number } = {} -- who fell off a cut strip and isn't back yet: os.clock() they fell
local skip = false -- Studio test key N: skip ahead (the intermission, or the match)

local ATTR_IN = RoundRules.ATTR_IN_ROUND

---------------------------------------------------------------- who's who

local function inGame(who: Instance): boolean
	if who:IsA("Player") then
		return who.Parent == Players
	end
	return who.Parent ~= nil
end

local function bodyOf(who: Instance): Model?
	if who:IsA("Player") then
		return who.Character
	end
	return if who:IsA("Model") then who else nil
end

function Round.nameOf(who: Instance): string
	if who:IsA("Player") then
		return who.DisplayName
	end
	local shown = who:GetAttribute(RoundRules.ATTR_NAME)
	return if type(shown) == "string" then shown else who.Name
end

function Round.roleOf(who: Instance): string
	return MoveRules.role(who:GetAttribute(MoveRules.ATTR_ROLE))
end

function Round.state(): RoundRules.State
	return state
end

-- Is `who` playing in the round under way?
function Round.isContestant(who: Instance): boolean
	return table.find(contestants, who) ~= nil
end

-- Every player, and every bot.
local function everyone(): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		table.insert(list, player)
	end
	if bots then
		for _, bot in bots.list() do
			table.insert(list, bot)
		end
	end
	return list
end

local function setRole(who: Instance, role: string)
	who:SetAttribute(MoveRules.ATTR_ROLE, MoveRules.role(role))
	local body = bodyOf(who)
	if body then
		Knives.wear(body, role == "Chaser" and who:GetAttribute(ATTR_IN) == true)
	end
end

local function setFrozen(who: Instance, on: boolean)
	who:SetAttribute(MoveRules.ATTR_FROZEN, on)
end

local function runners(): { Instance }
	local list: { Instance } = {}
	for _, who in contestants do
		if inGame(who) and Round.roleOf(who) ~= "Chaser" then
			table.insert(list, who)
		end
	end
	return list
end

local function chasers(): { Instance }
	local list: { Instance } = {}
	for _, who in contestants do
		if inGame(who) and Round.roleOf(who) == "Chaser" then
			table.insert(list, who)
		end
	end
	return list
end

local function dropLeavers(): boolean
	local kept: { Instance } = {}
	for _, who in contestants do
		if inGame(who) then
			table.insert(kept, who)
		end
	end
	local changed = #kept ~= #contestants
	contestants = kept
	return changed
end

-- Runners left, the phase, and the runners' speeds (the last few get the last-runner speeds).
local function refreshRunners()
	local list = runners()
	Workspace:SetAttribute(RoundRules.ATTR_RUNNERS_LEFT, #list)
	Workspace:SetAttribute(RoundRules.ATTR_PHASE, RoundRules.phase(runnersAtStart, #list))
	local role = RoundRules.runnerRole(runnersAtStart, #list)
	for _, who in list do
		if Round.roleOf(who) ~= role then
			setRole(who, role)
		end
	end
end

-- The phase right now (1 to 4).
local function phaseNow(): number
	local phase = Workspace:GetAttribute(RoundRules.ATTR_PHASE)
	return if type(phase) == "number" then phase else 1
end

-- Tells Rewards a moment of the round. A problem in there must never stop the round itself.
local function reward(moment: string, ...: any)
	local ok, problem = pcall((Rewards :: any)[moment], ...)
	if not ok then
		warn(`[{Config.GameName}] rewards broke on "{moment}": {problem}`)
	end
end

local function setState(newState: RoundRules.State, length: number)
	state = newState
	Workspace:SetAttribute(RoundRules.ATTR_STATE, newState)
	Workspace:SetAttribute(RoundRules.ATTR_LENGTH, length)
	Workspace:SetAttribute(RoundRules.ATTR_ENDS_AT, if length > 0 then Workspace:GetServerTimeNow() + length else 0)
end

local function randomInteger(n: number): number
	return rng:NextInteger(1, n)
end

local function shuffled<T>(list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- A fresh body at `spot` (players), or the bot moved there.
local function place(who: Instance, spot: CFrame)
	placedAt[who] = os.clock()
	if who:IsA("Player") then
		spots[who] = spot
		respawn(who)
	elseif bots and who:IsA("Model") then
		bots.place(who, spot)
		Knives.wear(who, Round.roleOf(who) == "Chaser" and who:GetAttribute(ATTR_IN) == true)
	end
end

---------------------------------------------------------------- spawning (Spawner asks)

-- Where a new body of `player` stands: their spot in the round, else anywhere on the circle while they're playing,
-- else the lobby.
function Round.spotFor(player: Player): CFrame
	if player:GetAttribute(ATTR_IN) == true and (state == "Teleport" or state == "Match" or state == "Cleanup") then
		local spot = spots[player]
		spots[player] = nil
		return spot or Arena.randomSpawn()
	end
	return Lobby.randomSpawn()
end

-- A new body gets its knife: on the back, or in the hand for a chaser in the round.
function Round.prepareCharacter(player: Player, character: Model)
	Knives.wear(character, player:GetAttribute(ATTR_IN) == true and Round.roleOf(player) == "Chaser")
end

---------------------------------------------------------------- shrinking and tagging

-- No cut on its way (none coming, or the match is over): every screen drops the red.
local function clearCut()
	Workspace:SetAttribute(RoundRules.ATTR_CUT_RADIUS, 0)
	Workspace:SetAttribute(RoundRules.ATTR_CUT_AT, 0)
end

-- A cut is coming in `seconds` (owner 2026-11-09: "make the game warn 3 seconds before the map shrinks. and whatever
-- part of the map that shrinks that area should be red"): every screen turns the strip that's going red and counts
-- down (ShrinkFx). Gives back the side the square will be cut to, or nil when it can't get any smaller.
local function warnCut(share: number, seconds: number): number?
	local side = RoundRules.shrunk(Arena.targetDiameter(), share)
	if side >= Arena.targetDiameter() - 0.01 then
		return nil
	end
	Workspace:SetAttribute(RoundRules.ATTR_CUT_RADIUS, side / 2)
	Workspace:SetAttribute(RoundRules.ATTR_CUT_AT, Workspace:GetServerTimeNow() + math.max(seconds, 0))
	return side
end

-- Somewhere near the middle of the square, facing any way: where someone who fell comes back.
local function spotNearMiddle(): CFrame
	local center = Arena.center()
	local reach = Arena.radius() * S.FALL_SPAWN_SHARE
	local position = center + Vector3.new(rng:NextNumber(-reach, reach), 3, rng:NextNumber(-reach, reach))
	return CFrame.new(position) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
end

-- `who` fell off a cut strip (owner 2026-11-10: "make the red let players fall and become tagger"). A runner becomes a
-- chaser with the knife in hand and loses their coins' speed (like a tag, but nobody gets the tag and nobody speeds
-- up); every screen hears it; a moment later (S.FALL_BACK, long enough to watch yourself drop into the clouds) they're
-- back on the square near the middle, and a new chaser stands still there for a moment like a tagged runner. A chaser
-- who falls just comes back.
local function fell(who: Instance)
	if falling[who] or state ~= "Match" or not Round.isContestant(who) or not inGame(who) then
		return
	end
	local stamp = os.clock()
	falling[who] = stamp
	who:SetAttribute(MoveRules.ATTR_FALLING, Workspace:GetServerTimeNow())
	local wasRunner = Round.roleOf(who) ~= "Chaser"
	local phaseBefore = phaseNow()
	if wasRunner then
		setRole(who, "Chaser")
		Coins.loseStack(who)
		who:SetAttribute("TaggedAt", os.clock() - matchStart)
		refreshRunners()
	end
	remote:FireAllClients("fell", { who = who, name = Round.nameOf(who), runner = wasRunner })
	reward("fell", who, wasRunner, phaseBefore)
	task.delay(S.FALL_BACK, function()
		if falling[who] ~= stamp then
			return
		end
		falling[who] = nil
		who:SetAttribute(MoveRules.ATTR_FALLING, nil)
		if not inGame(who) or who:GetAttribute(ATTR_IN) ~= true or (state ~= "Match" and state ~= "Cleanup") then
			return
		end
		place(who, spotNearMiddle())
		if wasRunner and state == "Match" then
			Round.stun(who, Config.Tag.NEW_CHASER_STUN, 0, "Tagged")
		end
	end)
end

-- Anyone in the match whose body has dropped under the floor fell (players' own games let go of their bodies when the
-- strip they're on is cut, MoveController; bots are let go by dropBots).
local function watchFalls()
	local floorY = Arena.center().Y
	local now = os.clock()
	for _, who in contestants do
		if not falling[who] and now - (placedAt[who] or -math.huge) > 1 then
			local root = History.rootOf(who)
			if root and root.Position.Y < floorY - S.FALL_DETECT then
				fell(who)
			end
		end
	end
end

-- Bots still on the strip that's just been cut (outside the square `half` studs from its middle to an edge) go over
-- the edge: nudged clear of it and let go (DevBots stops steering a falling bot), so they drop with the floor.
local function dropBots(half: number)
	local center = Arena.center()
	for _, who in contestants do
		if who:IsA("Model") and inGame(who) and not falling[who] then
			local root = History.rootOf(who)
			if root then
				local out, past = MoveRules.pastEdge(root.Position, center, half)
				if out then
					if past < S.FALL_CLEAR then
						who:PivotTo(who:GetPivot() + out * (S.FALL_CLEAR - past))
					end
					root.AssemblyLinearVelocity = out * S.FALL_PUSH
					fell(who)
				end
			end
		end
	end
end

-- Cuts the square down to `side` (owner: "change the shrinking function as just like cutting off a that part of the
-- map"): every screen drops the strip round the edge into the clouds and shakes, and anyone still on it falls with it
-- (owner 2026-11-10: "make the red let players fall and become tagger"; it used to push them onto what's left).
local function cut(side: number)
	local before = Arena.targetDiameter()
	clearCut()
	if side >= before - 0.01 then
		return
	end
	shrinkCount += 1
	Workspace:SetAttribute(RoundRules.ATTR_SHRINKS, shrinkCount)
	Workspace:SetAttribute(MoveRules.ATTR_LAST_CUT_AT, Workspace:GetServerTimeNow())
	Arena.cutTo(side)
	Coins.cut(side / 2) -- coins on the strip that went fall with it
	remote:FireAllClients("shrink", shrinkCount, before / 2, side / 2)
	dropBots(side / 2)
	reward("shrunk") -- a bounty still running grows
end

-- A cut with no warning that takes `share` off the side (a tag's, when Config.Shrink.PER_TAG is on).
local function shrink(share: number)
	cut(RoundRules.shrunk(Arena.targetDiameter(), share))
end

-- `chaser` tagged `runner` (checked already by Tagging, or a Studio bot's own tag). The runner becomes a chaser with
-- the knife in hand, everyone speeds up, the circle shrinks, every screen hears it. Gives back whether it counted.
function Round.tag(chaser: Instance, runner: Instance, dash: boolean): boolean
	if state ~= "Match" or chaser == runner or not Round.isContestant(chaser) or not Round.isContestant(runner) then
		return false
	end
	if not inGame(chaser) or not inGame(runner) then
		return false
	end
	if Round.roleOf(chaser) ~= "Chaser" or Round.roleOf(runner) == "Chaser" then
		return false
	end
	-- a stunned chaser can't tag (just tagged itself, or perfect-dodged)
	if MoveRules.stunned(chaser, Workspace:GetServerTimeNow()) then
		return false
	end
	-- a runner who's just perfect-dodged can't be tagged for a moment
	if MoveRules.safe(runner, Workspace:GetServerTimeNow()) then
		return false
	end
	local phaseBefore = phaseNow()
	setRole(runner, "Chaser")
	Coins.loseStack(runner) -- coins: a tagged runner loses their whole speed stack (owner)
	-- the new chaser stands still for a moment before it can chase (owner: "do the stun before tagging")
	Round.stun(runner, Config.Tag.NEW_CHASER_STUN, 0, "Tagged")
	local tags = chaser:GetAttribute(RoundRules.ATTR_ROUND_TAGS)
	chaser:SetAttribute(RoundRules.ATTR_ROUND_TAGS, (if type(tags) == "number" then tags else 0) + 1)
	runner:SetAttribute("TaggedAt", os.clock() - matchStart)
	MoveServer.addTag()
	refreshRunners()
	local root = History.rootOf(runner)
	local info: TagInfo = {
		chaser = chaser,
		runner = runner,
		chaserName = Round.nameOf(chaser),
		runnerName = Round.nameOf(runner),
		dash = dash,
		at = if root then root.Position else nil,
	}
	remote:FireAllClients("tag", info)
	reward("tagged", chaser, runner, dash, phaseBefore)
	if S.PER_TAG > 0 then
		shrink(S.PER_TAG)
	end
	return true
end

-- Stuns `who` (a player or a bot) for `seconds`: no dashing or tagging, speed times `slow` (0: standing still).
-- `kind` is "Tagged" or "Dodged" (screens show a dodged chaser's stun in grey).
function Round.stun(who: Instance, seconds: number, slow: number, kind: string)
	who:SetAttribute(MoveRules.ATTR_SLOW_FACTOR, slow)
	who:SetAttribute(MoveRules.ATTR_STUN_KIND, kind)
	who:SetAttribute(MoveRules.ATTR_STUN_UNTIL, Workspace:GetServerTimeNow() + seconds)
end

-- A runner perfect-dodged a chaser (checked already by Tagging, or a Studio bot's own dodge): every screen hears it.
function Round.dodged(runner: Instance, chaser: Instance)
	remote:FireAllClients("dodge", {
		runner = runner,
		chaser = chaser,
		runnerName = Round.nameOf(runner),
		chaserName = Round.nameOf(chaser),
	})
	reward("dodged", runner)
end

-- A chaser slashed or stabbed (whether or not it lands): every screen draws it. `kind`: "slash" (default) or "stab".
function Round.slashed(chaser: Instance, kind: string?)
	remote:FireAllClients("slash", chaser, if kind == "stab" then "stab" else "slash")
end

---------------------------------------------------------------- the round's steps

local function backToLobby(who: Instance)
	falling[who] = nil
	who:SetAttribute(MoveRules.ATTR_FALLING, nil)
	who:SetAttribute(ATTR_IN, false)
	who:SetAttribute(MoveRules.ATTR_STUN_UNTIL, nil)
	who:SetAttribute(RoundRules.ATTR_ROUND_TAGS, 0)
	who:SetAttribute(RoundRules.ATTR_ALPHA, false)
	Coins.loseStack(who)
	setFrozen(who, false)
	setRole(who, "Runner")
	place(who, Lobby.randomSpawn())
end

local function endRound()
	Coins.endMatch()
	reward("roundCleared")
	for _, who in contestants do
		if inGame(who) then
			backToLobby(who)
		end
	end
	contestants = {}
	table.clear(spots)
	table.clear(falling)
	runnersAtStart = 0
	MoveServer.resetTags(0)
	Workspace:SetAttribute(RoundRules.ATTR_RUNNERS_LEFT, 0)
	Workspace:SetAttribute(RoundRules.ATTR_RUNNERS_START, 0)
	Workspace:SetAttribute(RoundRules.ATTR_PHASE, 1)
	Workspace:SetAttribute(RoundRules.ATTR_SHRINKS, 0)
	clearCut()
	Arena.setDiameter(MoveRules.arenaDiameter(#everyone()))
end

-- Waits until `seconds` have passed; false straight away if `keepGoing` turns false meanwhile.
local function hold(seconds: number, keepGoing: () -> boolean): boolean
	local ends = os.clock() + seconds
	skip = false
	while os.clock() < ends and not skip do
		task.wait(0.1)
		if not keepGoing() then
			return false
		end
	end
	skip = false
	return true
end

local function enoughPlayers(): boolean
	return #everyone() >= R.MIN_PLAYERS
end

-- The fade to black, the chaser picked in it, everyone spawned. False if too many left meanwhile.
local function teleport(): boolean
	setState("Teleport", R.TELEPORT)
	local ends = os.clock() + R.TELEPORT
	contestants = everyone()
	for _, who in contestants do
		who:SetAttribute(ATTR_IN, true)
		who:SetAttribute(RoundRules.ATTR_ROUND_TAGS, 0)
		who:SetAttribute(RoundRules.ATTR_ALPHA, false)
		who:SetAttribute("TaggedAt", nil)
		Coins.resetFor(who) -- no coins and no speed stack yet
		setFrozen(who, true)
	end
	remote:FireAllClients("fade", R.FADE_IN, R.TELEPORT)
	task.wait(R.FADE_IN)

	-- the screens are black now
	dropLeavers()
	if #contestants < R.MIN_PLAYERS then
		return false
	end
	local chaser = RoundRules.pick(contestants, lastChaser, randomInteger) :: Instance
	lastChaser = chaser
	chaser:SetAttribute(RoundRules.ATTR_ALPHA, true)
	runnersAtStart = #contestants - 1
	Workspace:SetAttribute(RoundRules.ATTR_RUNNERS_START, runnersAtStart)
	shrinkCount = 0
	Workspace:SetAttribute(RoundRules.ATTR_SHRINKS, 0)
	Workspace:SetAttribute(MoveRules.ATTR_LAST_CUT_AT, 0)
	clearCut()
	MoveServer.resetTags(RoundRules.startSpeed(#contestants))
	Arena.setDiameter(MoveRules.arenaDiameter(#contestants))

	local center = Arena.center()
	local radius = Arena.radius()
	local runnerRole = RoundRules.runnerRole(runnersAtStart, runnersAtStart)
	local startAngle = rng:NextNumber() * math.pi * 2
	local function jitter(): number
		return rng:NextNumber() * 2 - 1
	end
	local index = 0
	for _, who in shuffled(contestants) do
		if who == chaser then
			setRole(who, "Chaser")
			local yaw = CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
			place(who, CFrame.new(center + Vector3.new(0, 3, 0)) * yaw)
		else
			index += 1
			setRole(who, runnerRole)
			place(who, RoundRules.runnerSpot(index, runnersAtStart, center, radius, startAngle, jitter))
		end
	end
	refreshRunners()
	remote:FireAllClients("chaser", chaser, Round.nameOf(chaser))
	reward("roundStarted", contestants, chaser) -- who's wanted this round

	task.wait(math.max(ends - os.clock(), 0))
	return true
end

-- The match. Gives back who won: "Runners", "Chasers", or "None" (too many players left).
local function match(): string
	setState("Match", R.MATCH)
	matchStart = os.clock()
	for _, who in contestants do
		setFrozen(who, false)
	end
	remote:FireAllClients("go")
	reward("matchStarted")
	Coins.beginMatch(#contestants) -- coins start coming in over the match
	local nextShrink = matchStart + S.EVERY
	local warned = false -- the next cut's warning is up
	local cutTo: number? = nil -- the side the square is about to be cut to
	local ends = matchStart + R.MATCH
	skip = false
	while os.clock() < ends and not skip do
		task.wait(0.1)
		if dropLeavers() then
			-- every chaser left: a runner takes over
			if #chasers() == 0 then
				local list = runners()
				if #list >= 2 then
					local new = RoundRules.pick(list, nil, randomInteger) :: Instance
					setRole(new, "Chaser")
					new:SetAttribute(RoundRules.ATTR_ALPHA, true)
					remote:FireAllClients("chaser", new, Round.nameOf(new))
				end
			end
			refreshRunners()
		end
		if #contestants < R.MIN_PLAYERS or #chasers() == 0 then
			return "None"
		end
		if #runners() == 0 then
			return "Chasers"
		end
		-- WARN s before each cut, the strip that's going turns red on every screen; then it's cut off
		if not warned and os.clock() >= nextShrink - S.WARN and nextShrink < ends - 1 then
			warned = true
			cutTo = warnCut(S.SHARE, nextShrink - os.clock())
		end
		if os.clock() >= nextShrink and nextShrink < ends - 1 then
			nextShrink += S.EVERY
			warned = false
			cut(cutTo or RoundRules.shrunk(Arena.targetDiameter(), S.SHARE))
			cutTo = nil
		end
	end
	return "Runners"
end

-- No more tagging; the result on every screen; then back to the lobby.
local function cleanup(winner: string)
	setState("Cleanup", R.CLEANUP)
	Coins.endMatch()
	clearCut()
	local survivors: { string } = {}
	local top: { { name: string, tags: number, alpha: boolean } } = {}
	for _, who in contestants do
		setFrozen(who, true)
		if inGame(who) then
			if Round.roleOf(who) == "Chaser" then
				local tags = who:GetAttribute(RoundRules.ATTR_ROUND_TAGS)
				table.insert(top, {
					name = Round.nameOf(who),
					tags = if type(tags) == "number" then tags else 0,
					alpha = who:GetAttribute(RoundRules.ATTR_ALPHA) == true,
				})
			else
				table.insert(survivors, Round.nameOf(who))
			end
		end
	end
	table.sort(top, function(a, b)
		if a.tags ~= b.tags then
			return a.tags > b.tags
		end
		return a.name < b.name
	end)
	while #top > 5 do
		table.remove(top)
	end
	remote:FireAllClients("victory", { winner = winner, survivors = survivors, chasers = top })
	if bots then
		bots.celebrate(winner)
	end
	-- what the round paid each player, and their record, for their own victory screen
	local ok, payouts = pcall(Rewards.matchEnded, winner, contestants, phaseNow())
	if ok then
		for player, payout in payouts do
			if player.Parent == Players then
				remote:FireClient(player, "payout", payout)
			end
		end
	else
		warn(`[{Config.GameName}] rewards broke at the end of the match: {payouts}`)
	end
	task.wait(R.CLEANUP)
end

local function playOnce()
	if bots then
		bots.sync()
	end
	if not enoughPlayers() then
		setState("Waiting", 0)
		repeat
			task.wait(0.5)
			if bots then
				bots.sync() -- a lone player gets bots to play with
			end
		until enoughPlayers()
	end
	setState("Intermission", R.INTERMISSION)
	if not hold(R.INTERMISSION, enoughPlayers) then
		return
	end
	if teleport() then
		cleanup(match())
	end
	endRound()
end

-- Anyone not playing who ends up off the lobby (a fall through, a glitch) goes back up.
local function watchLobby()
	if state == "Teleport" then
		return
	end
	for _, who in everyone() do
		if who:GetAttribute(ATTR_IN) ~= true and os.clock() - (placedAt[who] or -math.huge) > 3 then
			local root = History.rootOf(who)
			if root and not Lobby.isUp(root.Position) then
				place(who, Lobby.randomSpawn())
			end
		end
	end
end

function Round.start(respawnPlayer: (player: Player) -> (), studioBots: Bots?)
	respawn = respawnPlayer
	bots = studioBots
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local found = remotes:FindFirstChild("Round")
	if not found then
		found = Instance.new("RemoteEvent")
		found.Name = "Round"
		found.Parent = remotes
	end
	remote = found :: RemoteEvent
	Arena.manage()
	local started, problem = pcall(Rewards.start, Round.nameOf, function(kind: string, info: any)
		remote:FireAllClients(kind, info)
	end)
	if not started then
		warn(`[{Config.GameName}] rewards didn't start: {problem}`)
	end
	setState("Waiting", 0)
	if RunService:IsStudio() then
		local dev = remotes:FindFirstChild("Dev")
		if dev and dev:IsA("RemoteEvent") then
			dev.OnServerEvent:Connect(function(_, action)
				if action == "skip" then
					skip = true
				end
			end)
		end
	end
	refreshRunners()

	Players.PlayerRemoving:Connect(function(player)
		spots[player] = nil
		placedAt[player] = nil
		if lastChaser == player then
			lastChaser = nil
		end
	end)

	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		if state == "Match" then
			watchFalls()
		end
		since += dt
		if since >= 0.5 then
			since = 0
			watchLobby()
		end
	end)

	task.spawn(function()
		while true do
			local ok, problem = pcall(playOnce)
			if not ok then
				warn(`[{Config.GameName}] the round broke: {problem}`)
				pcall(endRound)
				task.wait(1)
			end
		end
	end)
end

return Round
