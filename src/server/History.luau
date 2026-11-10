--!strict
-- Every body's last couple of seconds of spots, so a tag can be checked against where the runner was on the chaser's
-- screen (design notes, Round flow; the rule from Huss Zero's hitbox notes: never compare the server's body now with
-- the chaser's moment). Two copies a body:
--   chrono  Chrono's spots as they arrive, timed by the body owner's own clock: the same clock the chaser's screen
--           draws them by, so the chaser's view moment looks up exactly what they saw (players only);
--   native  the server's own copy of the body, timed by the server's clock (players and Studio bots), the fallback.
-- A new body starts both afresh.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ChronoSetup = require(ReplicatedStorage.Shared.ChronoSetup)
local Config = require(ReplicatedStorage.Shared.Config)

local KEEP = Config.Net.HISTORY_TIME

type Sample = { t: number, p: Vector3 }
type Track = {
	root: BasePart?,
	chrono: { Sample },
	native: { Sample },
	stamp: number, -- newest Chrono stamp taken
}

local History = {}

local tracks: { [Instance]: Track } = {}
local botFolder: () -> Instance? = function()
	return nil
end

-- The body's root part of a player or a bot model.
function History.rootOf(who: Instance): BasePart?
	local model = if who:IsA("Player") then who.Character else who
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function push(list: { Sample }, t: number, p: Vector3)
	local last = list[#list]
	if last and t <= last.t then
		return
	end
	table.insert(list, { t = t, p = p })
	local cutoff = t - KEEP
	local drop = 0
	while list[drop + 1] and list[drop + 1].t < cutoff do
		drop += 1
	end
	if drop > 0 then
		table.move(list, drop + 1, #list, 1)
		for i = #list - drop + 1, #list do
			list[i] = nil
		end
	end
end

local function trackOf(who: Instance): Track
	local track = tracks[who]
	if not track then
		track = { root = nil, chrono = {}, native = {}, stamp = -math.huge }
		tracks[who] = track
	end
	return track
end

local function sample(who: Instance, now: number)
	local track = trackOf(who)
	local root = History.rootOf(who)
	if root ~= track.root then
		track.root = root
		table.clear(track.chrono)
		table.clear(track.native)
		track.stamp = -math.huge
	end
	if not root then
		return
	end
	push(track.native, now, root.Position)
	if who:IsA("Player") then
		local stamp, cframe = ChronoSetup.latest(who)
		if stamp and cframe and stamp > track.stamp then
			track.stamp = stamp
			push(track.chrono, stamp, cframe.Position)
		end
	end
end

local function step()
	local now = Workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		sample(player, now)
	end
	local folder = botFolder()
	if folder then
		for _, bot in folder:GetChildren() do
			sample(bot, now)
		end
	end
end

-- The distance from `point` to a segment.
local function toSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local length2 = ab:Dot(ab)
	if length2 < 1e-8 then
		return (point - a).Magnitude
	end
	local t = math.clamp((point - a):Dot(ab) / length2, 0, 1)
	return (point - (a + ab * t)).Magnitude
end

-- The closest `point` comes to the path in `list` between times `t0` and `t1`: every stretch between two samples that
-- overlaps that time, so a moment between two samples is covered. math.huge when the list has none of that time.
local function closest(list: { Sample }, point: Vector3, t0: number, t1: number): number
	local best = math.huge
	for i, a in list do
		if a.t > t1 then
			break
		end
		local b = list[i + 1]
		if b and b.t >= t0 then
			best = math.min(best, toSegment(point, a.p, b.p))
		elseif not b and a.t >= t0 then
			best = math.min(best, (point - a.p).Magnitude)
		end
	end
	return best
end

-- How close `point` comes to where `who` was: on Chrono's copy around their own clock's `seenAt` (± `window`), and on
-- the server's copy over the last `rewind` seconds. The nearer of the two.
function History.distance(who: Instance, point: Vector3, seenAt: number?, window: number, rewind: number): number
	local track = tracks[who]
	if not track then
		return math.huge
	end
	local best = math.huge
	if seenAt then
		best = closest(track.chrono, point, seenAt - window, seenAt + window)
	end
	local now = Workspace:GetServerTimeNow()
	return math.min(best, closest(track.native, point, now - rewind, now))
end

-- How close `point` comes to `who`'s newest spots: the last `rewind` seconds of both copies (Chrono's counted back
-- from its newest stamp). For a chaser's own claimed spot.
function History.recentDistance(who: Instance, point: Vector3, rewind: number): number
	local track = tracks[who]
	if not track then
		return math.huge
	end
	local best = math.huge
	if track.stamp > -math.huge then
		best = closest(track.chrono, point, track.stamp - rewind, track.stamp)
	end
	local now = Workspace:GetServerTimeNow()
	return math.min(best, closest(track.native, point, now - rewind, now))
end

-- `who`'s newest Chrono stamp (their own clock), nil when none.
function History.newestStamp(who: Instance): number?
	local track = tracks[who]
	if track and track.stamp > -math.huge then
		return track.stamp
	end
	return nil
end

-- Starts keeping everyone's past. `bots` gives the folder of Studio bots (or nil).
function History.start(bots: () -> Instance?)
	botFolder = bots
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
end

-- Forgets a bot that's gone.
function History.forget(who: Instance)
	tracks[who] = nil
end

return History
