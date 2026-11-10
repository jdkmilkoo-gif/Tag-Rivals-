--!strict
-- Checking tags (design notes, Round flow: no button, no tool; a chaser who gets close enough slashes automatically
-- and the runner is tagged; "Server checks the tag against where the runner was on the chaser's screen").
-- The chaser's screen claims a tag the moment it draws a runner within reach (TagController): the runner it saw, where
-- it drew them, where its own body was, the moment of the runner's own clock it drew them at (Chrono), and whether
-- it was dashing. Here the claim is checked:
--   * the round is on, the claimer is a chaser in it and the target a runner in it;
--   * the claimed gap is within reach: 5.2 studs, 6.5 for a click-stab (PC), or 7.5 during a dash the server saw just
--     before (plus REACH_SLACK);
--   * the runner really was where the chaser drew them: History's copy of the runner around that moment (Chrono's, by
--     the runner's clock), or the server's own copy over the last moments (the chaser's ping plus a little);
--   * the chaser really was where it says: the newest moments of History's copy of the chaser.
-- A claim the server's history hasn't caught up with yet waits up to HIT_WAIT. Then Round.tag makes it count.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local History = require(script.Parent.History)
local Round = require(script.Parent.Round)

local T = Config.Tag
local D = Config.Dash

local Tagging = {}

type Claim = {
	chaser: Player,
	target: Instance,
	seen: Vector3,
	own: Vector3,
	seenAt: number?,
	dash: boolean,
	stab: boolean,
	until_: number,
}

local pending: { Claim } = {}
local lastClaim: { [Player]: number } = {}
local lastSwing: { [Player]: number } = {}
local botFolder: () -> Instance? = function()
	return nil
end

local function finiteVector(v: unknown): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e6
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- A target the claim may name: a player, or one of the Studio bots.
local function validTarget(target: unknown): boolean
	if typeof(target) ~= "Instance" then
		return false
	end
	if target:IsA("Player") then
		return target.Parent == Players
	end
	local folder = botFolder()
	return folder ~= nil and target:IsA("Model") and target.Parent == folder
end

-- Did the server see this chaser dash just before the claim (its reach is bigger for the burst)?
local function dashedLately(chaser: Player, rewind: number): boolean
	local at = chaser:GetAttribute(MoveRules.ATTR_DASH_AT)
	if type(at) ~= "number" then
		return false
	end
	return Workspace:GetServerTimeNow() - at <= D.TIME + T.DASH_GRACE + rewind
end

-- true: it counts; false: it can never count; nil: not yet (the history may still catch up).
local function check(claim: Claim): boolean?
	if Round.state() ~= "Match" then
		return false
	end
	local chaser, target = claim.chaser, claim.target
	if not Round.isContestant(chaser) or not Round.isContestant(target) then
		return false
	end
	if Round.roleOf(chaser) ~= "Chaser" or Round.roleOf(target) == "Chaser" then
		return false
	end
	if MoveRules.stunned(chaser, Workspace:GetServerTimeNow()) then
		return false
	end
	local rewind = math.min(T.REWIND_BASE + chaser:GetNetworkPing(), T.REWIND_MAX)
	local reach = if claim.dash and dashedLately(chaser, rewind) then T.DASH_REACH else T.REACH
	if claim.stab then
		reach = math.max(reach, T.STAB_REACH)
	end
	if (flat(claim.own) - flat(claim.seen)).Magnitude > reach + T.REACH_SLACK then
		return false
	end
	-- the moment of the runner's clock the chaser drew them at: only within the history the server has of them
	local seenAt = claim.seenAt
	if seenAt and target:IsA("Player") then
		local newest = History.newestStamp(target)
		if not newest or seenAt > newest + 0.1 or seenAt < newest - T.REWIND_MAX - 0.5 then
			seenAt = nil
		end
	else
		seenAt = nil
	end
	local seenOk = History.distance(target, claim.seen, seenAt, T.SEEN_WINDOW, rewind) <= T.SEEN_SLACK
	local ownOk = History.recentDistance(chaser, claim.own, rewind) <= T.OWN_SLACK
	if seenOk and ownOk then
		return true
	end
	return nil
end

local function settle(claim: Claim): boolean
	local verdict = check(claim)
	if verdict == true then
		Round.tag(claim.chaser, claim.target, claim.dash)
		return true
	elseif verdict == false then
		return true
	end
	return os.clock() >= claim.until_ -- out of time: a miss
end

-- A click-stab that reached nobody: every screen still draws it.
local function onSwing(chaser: Player)
	local now = os.clock()
	if now - (lastSwing[chaser] or -math.huge) < T.STAB_GAP * 0.5 then
		return
	end
	lastSwing[chaser] = now
	if Round.state() == "Match" and Round.roleOf(chaser) == "Chaser" and Round.isContestant(chaser) then
		Round.slashed(chaser, "stab")
	end
end

---------------------------------------------------------------- the perfect dodge

local lastDodge: { [Instance]: number } = {} -- runner: os.clock() of its newest perfect dodge
local stunEnds: { [Instance]: number } = {} -- chaser: os.clock() its newest dodge stun ends

-- `runner` perfect-dodged `chaser` (design notes; owner 2026-11-09): the chaser is stunned (slowed, no dashing, no
-- tagging, a grey screen), and every screen hears it. Checks the cooldowns; gives back whether it counted.
function Tagging.perfectDodge(runner: Instance, chaser: Instance): boolean
	if Round.state() ~= "Match" or not Round.isContestant(runner) or not Round.isContestant(chaser) then
		return false
	end
	if Round.roleOf(chaser) ~= "Chaser" or Round.roleOf(runner) == "Chaser" then
		return false
	end
	local now = os.clock()
	if now - (lastDodge[runner] or -math.huge) < Config.Dodge.COOLDOWN then
		return false
	end
	if now < (stunEnds[chaser] or -math.huge) + Config.Dodge.IMMUNE then
		return false
	end
	lastDodge[runner] = now
	stunEnds[chaser] = now + Config.Dodge.STUN
	Round.stun(chaser, Config.Dodge.STUN, Config.Dodge.SLOW, "Dodged")
	local now2 = Workspace:GetServerTimeNow()
	runner:SetAttribute(MoveRules.ATTR_SAFE_UNTIL, now2 + Config.Dodge.INVINCIBLE)
	runner:SetAttribute(MoveRules.ATTR_BOOST_FACTOR, Config.Dodge.BOOST)
	runner:SetAttribute(MoveRules.ATTR_BOOST_UNTIL, now2 + Config.Dodge.BOOST_TIME)
	Round.dodged(runner, chaser)
	return true
end

-- A runner's screen says it dashed in the perfect-dodge window of `chaser`: the server checks the runner really just
-- dashed and the two were close enough (its own copy of the bodies, plus slack), then makes it count.
local function onDodge(runner: Player, chaser: unknown)
	if not validTarget(chaser) then
		return
	end
	local who = chaser :: Instance
	local dashAt = runner:GetAttribute(MoveRules.ATTR_DASH_AT)
	local rewind = math.min(T.REWIND_BASE + runner:GetNetworkPing(), T.REWIND_MAX)
	if type(dashAt) ~= "number" or Workspace:GetServerTimeNow() - dashAt > rewind + 0.2 then
		return
	end
	local mine, theirs = History.rootOf(runner), History.rootOf(who)
	if not mine or not theirs then
		return
	end
	local gap = (flat(mine.Position) - flat(theirs.Position)).Magnitude
	if gap > T.DASH_REACH + Config.Dodge.WINDOW + Config.Dodge.SLACK + 8 then
		return
	end
	Tagging.perfectDodge(runner, who)
end

local function onClaim(
	chaser: Player,
	target: unknown,
	seen: unknown,
	own: unknown,
	seenAt: unknown,
	dash: unknown,
	stab: unknown
)
	if target == "swing" then
		onSwing(chaser)
		return
	elseif target == "dodge" then
		onDodge(chaser, seen) -- here the player is the runner, and the second value the chaser it dodged
		return
	end
	if not validTarget(target) or not finiteVector(seen) or not finiteVector(own) then
		return
	end
	local now = os.clock()
	if now - (lastClaim[chaser] or -math.huge) < 0.1 then
		return
	end
	lastClaim[chaser] = now
	if Round.state() ~= "Match" or Round.roleOf(chaser) ~= "Chaser" or not Round.isContestant(chaser) then
		return
	end
	-- every screen draws the slash, whether or not it lands
	Round.slashed(chaser, if stab == true then "stab" else "slash")
	local claim: Claim = {
		chaser = chaser,
		target = target :: Instance,
		seen = seen :: Vector3,
		own = own :: Vector3,
		seenAt = if type(seenAt) == "number" and seenAt == seenAt then seenAt else nil,
		dash = dash == true,
		stab = stab == true,
		until_ = now + T.HIT_WAIT,
	}
	if not settle(claim) then
		table.insert(pending, claim)
	end
end

function Tagging.start(bots: () -> Instance?)
	botFolder = bots
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local found = remotes:FindFirstChild("Tag")
	if not found then
		found = Instance.new("RemoteEvent")
		found.Name = "Tag"
		found.Parent = remotes
	end
	(found :: RemoteEvent).OnServerEvent:Connect(onClaim)
	Players.PlayerRemoving:Connect(function(player)
		lastClaim[player] = nil
		lastSwing[player] = nil
		lastDodge[player] = nil
		stunEnds[player] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local kept = 0
		for i = 1, #pending do
			local claim = pending[i]
			if not settle(claim) then
				kept += 1
				pending[kept] = claim
			end
		end
		for i = #pending, kept + 1, -1 do
			pending[i] = nil
		end
	end)
end

return Tagging
