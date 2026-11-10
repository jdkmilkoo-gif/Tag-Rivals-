--!strict
-- Movement rules shared by the server and every player's game (design notes, Movement and Map size), kept free of
-- anything that needs a running game so they are easy to check. MoveController moves your body with them, MoveServer
-- checks dashes with them, and the HUD reads the charges with them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local M = Config.Move
local D = Config.Dash
local A = Config.Arena

local MoveRules = {}

-- Attributes the server sets (your own screen sets its own copy of the dash ones at once).
MoveRules.ATTR_ROLE = "Role" -- Player: "Runner", "Chaser" or "LastRunner"
MoveRules.ATTR_STARS = "Stars" -- Player: stars picked up this round
MoveRules.ATTR_DASH_COLOR = "DashColor" -- Player: hex colour of the equipped trail (unset: by role)
MoveRules.ATTR_DASH_AT = "DashAt" -- Player: server time of the newest dash
MoveRules.ATTR_DASH_DIR = "DashDir" -- Player: flat direction of the newest dash
MoveRules.ATTR_DASH_COUNT = "DashCount" -- Player: dashes so far (every screen draws each new one once)
MoveRules.ATTR_TAG_BONUS = "TagSpeedBonus" -- Workspace: studs/s runners have gained from tags this round
MoveRules.ATTR_CHASER_TAG_BONUS = "ChaserTagBonus" -- Workspace: studs/s chasers have gained (each tag less than the last)

-- The tag speed-up `role` gets right now (read from Workspace).
function MoveRules.tagBonus(role: unknown): number
	local name = if MoveRules.role(role) == "Chaser" then MoveRules.ATTR_CHASER_TAG_BONUS else MoveRules.ATTR_TAG_BONUS
	local value = game:GetService("Workspace"):GetAttribute(name)
	return if type(value) == "number" then value else 0
end
MoveRules.ATTR_TAGS = "TagCount" -- Workspace: tags so far this round
MoveRules.ATTR_ARENA_CENTER = "ArenaCenter" -- Workspace: the middle of the floor's top (Vector3)
MoveRules.ATTR_ARENA_RADIUS = "ArenaRadius" -- Workspace: half the square's side in studs (middle to an edge)
MoveRules.ATTR_FROZEN = "Frozen" -- Player: true while the round holds everyone still (the fade, the victory screen)
-- Fell off a cut strip (owner 2026-11-10: "make the red let players fall and become tagger"): Player or bot, the server
-- time it fell, set by the round until it's back on the square (nil the rest of the time).
MoveRules.ATTR_FALLING = "FallingAt"
MoveRules.ATTR_LAST_CUT_AT = "LastCutAt" -- Workspace: server time of the newest cut (0: none this round)
-- A stun (Player or bot body; set by the server): until StunUntil (server time) you can't dash or tag, and your speed is
-- times SlowFactor (0: you stand still). StunKind says why: "Tagged" (just became a chaser) or "Dodged" (a runner
-- perfect-dodged you: your screen goes grey).
MoveRules.ATTR_STUN_UNTIL = "StunUntil"
MoveRules.ATTR_SLOW_FACTOR = "SlowFactor"
MoveRules.ATTR_STUN_KIND = "StunKind"
MoveRules.ATTR_SAFE_UNTIL = "SafeUntil" -- Player or bot body: server time until which it can't be tagged (a perfect dodge)
MoveRules.ATTR_BOOST_UNTIL = "BoostUntil" -- Player or bot body: server time until which its speed is times BoostFactor
MoveRules.ATTR_BOOST_FACTOR = "BoostFactor"

-- Can `who` not be tagged at server time `now` (just perfect-dodged)?
function MoveRules.safe(who: Instance, now: number): boolean
	local untilTime = who:GetAttribute(MoveRules.ATTR_SAFE_UNTIL)
	return type(untilTime) == "number" and now < untilTime
end


local function finite(value: unknown): number
	if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return 0
end

-- A role name, falling back to Runner for anything unknown.
function MoveRules.role(value: unknown): string
	if type(value) == "string" and M.SPEEDS[value] ~= nil then
		return value
	end
	return "Runner"
end

-- Studs/s of top speed from stars: STAR_SPEED each, never past STAR_SPEED_MAX.
function MoveRules.starBonus(stars: unknown): number
	return math.min(math.max(finite(stars), 0) * M.STAR_SPEED, M.STAR_SPEED_MAX)
end

-- Walk and sprint top speeds for a role, with the tag speed-up and the star bonus added to both.
function MoveRules.topSpeeds(role: unknown, tagBonus: unknown, stars: unknown): (number, number)
	local base = M.SPEEDS[MoveRules.role(role)]
	local bonus = math.max(finite(tagBonus), 0) + MoveRules.starBonus(stars)
	return base.walk + bonus, base.sprint + bonus
end

-- How fast you speed up (studs/s every second) when your sprint top speed is `sprintTop`: ACCEL at the role's base
-- speed, growing in step as the speed bonuses raise it (owner: acceleration goes up with the speed).
function MoveRules.accel(role: unknown, sprintTop: number): number
	local base = M.SPEEDS[MoveRules.role(role)]
	return M.ACCEL * math.max(sprintTop / base.sprint, 1)
end

-- Your running speed `dt` s later: up towards `target` at `accel`, or down towards it at DECEL (scaled the same way).
function MoveRules.ramp(current: number, target: number, accel: number, dt: number): number
	if current < target then
		return math.min(current + accel * dt, target)
	end
	return math.max(current - M.DECEL * (accel / M.ACCEL) * dt, target)
end

-- Is `who` (a Player or a bot body) stunned at server time `now`?
function MoveRules.stunned(who: Instance, now: number): boolean
	local untilTime = who:GetAttribute(MoveRules.ATTR_STUN_UNTIL)
	return type(untilTime) == "number" and now < untilTime
end

-- The share of their speed `who` has at server time `now` (1 unless stunned).
function MoveRules.speedShare(who: Instance, now: number): number
	if not MoveRules.stunned(who, now) then
		-- a perfect dodge's burst of speed
		local boostUntil = who:GetAttribute(MoveRules.ATTR_BOOST_UNTIL)
		local boost = who:GetAttribute(MoveRules.ATTR_BOOST_FACTOR)
		if type(boostUntil) == "number" and now < boostUntil and type(boost) == "number" then
			return math.clamp(boost, 1, 2)
		end
		return 1
	end
	local factor = who:GetAttribute(MoveRules.ATTR_SLOW_FACTOR)
	return if type(factor) == "number" then math.clamp(factor, 0, 1) else 1
end

---------------------------------------------------------------- dash

-- How fast a dash moves (studs/s): DISTANCE over TIME.
function MoveRules.dashSpeed(): number
	return D.DISTANCE / D.TIME
end

-- The flat way a dash goes: the way you're holding, or the way you face when you hold nothing.
function MoveRules.dashDirection(move: Vector3, facing: Vector3): Vector3
	local flat = Vector3.new(move.X, 0, move.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(facing.X, 0, facing.Z)
	end
	if flat.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- Dash charges (owner: 2 charges, each refilling in 1 s, like Huss Zero). The charge is a number from 0 to
-- MAX_CHARGES: whole charges plus the one refilling. It refills one charge every RECHARGE s, one after another.

-- The charge `dt` s later, refilled (never past MAX_CHARGES).
function MoveRules.refill(charge: number, dt: number): number
	return math.clamp(finite(charge) + math.max(finite(dt), 0) / D.RECHARGE, 0, D.MAX_CHARGES)
end

-- Is there a whole charge to spend? (`slack`: a share of a charge forgiven, the server's allowance for bunching)
function MoveRules.canSpend(charge: number, slack: number?): boolean
	return finite(charge) >= 1 - (slack or 0) - 1e-6
end

-- The charge after a dash spends one (never below 0).
function MoveRules.spend(charge: number): number
	return math.max(finite(charge) - 1, 0)
end

-- How full charge cell `i` (1 to MAX_CHARGES) is, 0 to 1.
function MoveRules.cellFill(charge: number, i: number): number
	return math.clamp(finite(charge) - (i - 1), 0, 1)
end

-- Seconds until the next whole charge is back (nil when every charge is full).
function MoveRules.nextChargeIn(charge: number): number?
	local c = finite(charge)
	if c >= D.MAX_CHARGES - 1e-6 then
		return nil
	end
	return (1 - (c - math.floor(c))) * D.RECHARGE
end

-- The server's check of a dash at server time `t`: the charge it had at `last` (nil: never dashed, full), refilled
-- since with SEND_SLACK s extra (messages bunch). Gives back whether it counts and the charge after it.
function MoveRules.serverSpend(charge: number?, last: number?, t: number): (boolean, number)
	if charge == nil or last == nil then
		return true, D.MAX_CHARGES - 1
	end
	if t - last < D.MIN_GAP * 0.5 then -- half the gap: two messages can arrive close together
		return false, charge
	end
	local now = MoveRules.refill(charge, t - last + D.SEND_SLACK)
	if not MoveRules.canSpend(now) then
		return false, MoveRules.refill(charge, t - last)
	end
	return true, MoveRules.spend(MoveRules.refill(charge, t - last))
end

-- The colour of a player's dash: their equipped trail's colour when set, else cyan for runners and red for chasers.
function MoveRules.dashColor(role: unknown, custom: unknown): Color3
	if type(custom) == "string" then
		local ok, color = pcall(Color3.fromHex, custom)
		if ok then
			return color
		end
	end
	if MoveRules.role(role) == "Chaser" then
		return Color3.fromHex(D.CHASER_COLOR)
	end
	return Color3.fromHex(D.RUNNER_COLOR)
end

---------------------------------------------------------------- arena

-- The square's side at a round's start: always Config.Arena.SIZE (owner: "a permanent 250 x 250 square"), whatever the
-- player count.
function MoveRules.arenaDiameter(_players: number): number
	return A.SIZE
end

-- Keeps a body inside the square (the invisible wall): `radius` is half its side, and the wall stands `margin` inside
-- each edge. When `position` is past it, gives back the nearest spot inside and the outward direction there; else the
-- same position and nil.
function MoveRules.clampToArena(position: Vector3, center: Vector3, radius: number, margin: number): (Vector3, Vector3?)
	local limit = math.max(radius - margin, 0)
	local dx, dz = position.X - center.X, position.Z - center.Z
	local cx, cz = math.clamp(dx, -limit, limit), math.clamp(dz, -limit, limit)
	if cx == dx and cz == dz then
		return position, nil
	end
	local outward = Vector3.new(dx - cx, 0, dz - cz)
	outward = if outward.Magnitude > 1e-6 then outward.Unit else Vector3.new(1, 0, 0)
	return Vector3.new(center.X + cx, position.Y, center.Z + cz), outward
end

-- Is a body at `position` standing past the edge of the square `half` studs from its middle to an edge (on a strip
-- that's being cut off; near the floor only, not up on the lobby)? Gives back the way off the edge (along x or z,
-- whichever it's further past) and how far past the edge it is; nil when it's on the square.
function MoveRules.pastEdge(position: Vector3, center: Vector3, half: number): (Vector3?, number)
	local offset = position - center
	if math.abs(offset.Y) > A.WALL_HEIGHT then
		return nil, 0
	end
	local ax, az = math.abs(offset.X), math.abs(offset.Z)
	local past = math.max(ax, az) - half
	if past <= 0 then
		return nil, 0
	end
	local out = if ax >= az
		then Vector3.new(if offset.X >= 0 then 1 else -1, 0, 0)
		else Vector3.new(0, 0, if offset.Z >= 0 then 1 else -1)
	return out, past
end

return MoveRules
