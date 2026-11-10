--!strict
-- The round's rules (design notes, Round flow and Map size), kept free of anything that needs a running game so they
-- are easy to check. The server's Round runs the round with them; the screens read the same attributes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local R = Config.Round
local S = Config.Shrink

local RoundRules = {}

export type State = "Waiting" | "Intermission" | "Teleport" | "Match" | "Cleanup"

-- Attributes the server sets.
RoundRules.ATTR_STATE = "RoundState" -- Workspace: one of the States
RoundRules.ATTR_ENDS_AT = "RoundEndsAt" -- Workspace: server time the current state ends (0: it doesn't)
RoundRules.ATTR_LENGTH = "RoundStateLength" -- Workspace: how long the current state lasts, s
RoundRules.ATTR_PHASE = "RoundPhase" -- Workspace: 1, 2, 3, or 4 for Last Man Standing
RoundRules.ATTR_RUNNERS_LEFT = "RunnersLeft" -- Workspace
RoundRules.ATTR_RUNNERS_START = "RunnersAtStart" -- Workspace
RoundRules.ATTR_SHRINKS = "Shrinks" -- Workspace: shrinks so far this round
-- A cut on its way (Config.Shrink.WARN s of warning; every screen turns the strip that's going red): the half-side the
-- square is about to be cut to, and the server time of the cut. Both 0 when none is coming.
RoundRules.ATTR_CUT_RADIUS = "CutRadius" -- Workspace
RoundRules.ATTR_CUT_AT = "CutAt" -- Workspace
RoundRules.ATTR_IN_ROUND = "InRound" -- Player or bot: playing in this round (not waiting in the lobby)
RoundRules.ATTR_ROUND_TAGS = "RoundTags" -- Player or bot: runners they tagged this round
RoundRules.ATTR_ALPHA = "Alpha" -- Player or bot: picked as the first chaser this round
RoundRules.ATTR_BOT = "TagBot" -- bot models: true (Studio only)
RoundRules.ATTR_NAME = "ShownName" -- bot models: the name screens show
RoundRules.ATTR_STUDIO_BOTS = "StudioBots" -- Workspace (Studio only): how many bots the tester wants

-- Phase by players left (owner): 2 once a third of the starting runners are tagged, 3 at two thirds, 4 (Last Man
-- Standing) with one runner left. A round that starts with one runner stays in phase 1 (there's no "last" of one).
function RoundRules.phase(runnersAtStart: number, runnersLeft: number): number
	if runnersAtStart >= 2 and runnersLeft <= 1 then
		return 4
	end
	local tagged = runnersAtStart - runnersLeft
	if tagged * 3 >= runnersAtStart * 2 and tagged > 0 then
		return 3
	elseif tagged * 3 >= runnersAtStart and tagged > 0 then
		return 2
	end
	return 1
end

-- How many runners are left when the runners get the last-runner speeds (0: never this round).
function RoundRules.fastRunners(runnersAtStart: number): number
	return math.clamp(math.floor(runnersAtStart * R.FAST_RUNNERS_SHARE + 1e-6), 0, R.FAST_RUNNERS_MAX)
end

-- A runner's role with `runnersLeft` still running.
function RoundRules.runnerRole(runnersAtStart: number, runnersLeft: number): string
	if runnersLeft <= RoundRules.fastRunners(runnersAtStart) then
		return "LastRunner"
	end
	return "Runner"
end

-- Studs/s everyone's walk and sprint start the round with, for `players` in it (Claude's pick of formula).
function RoundRules.startSpeed(players: number): number
	return math.clamp((players - R.START_SPEED_FROM) * R.START_SPEED_PER_PLAYER, 0, R.START_SPEED_MAX)
end

-- The square's side after a shrink that takes `share` of it off (never under MIN_DIAMETER).
function RoundRules.shrunk(diameter: number, share: number): number
	return math.max(diameter * (1 - share), S.MIN_DIAMETER)
end

-- The camera shake's strength for the `count`th shrink of the round (stronger every time, capped).
function RoundRules.shakeFor(count: number): number
	return math.min(S.SHAKE_FIRST + S.SHAKE_STEP * math.max(count - 1, 0), S.SHAKE_MAX)
end

-- Where runner `index` of `count` spawns: spread round the circle at RUNNER_RING of its radius, each with a little
-- jitter (`jitter` gives a number from -1 to 1), facing the middle.
function RoundRules.runnerSpot(
	index: number,
	count: number,
	center: Vector3,
	radius: number,
	startAngle: number,
	jitter: () -> number
): CFrame
	local step = math.pi * 2 / math.max(count, 1)
	local angle = startAngle + (index - 1) * step + jitter() * step * 0.25
	local distance = radius * math.clamp(R.RUNNER_RING + jitter() * R.RUNNER_JITTER, 0.3, 0.92)
	local position = center + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)
	return CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
end

-- The timer's text: "1:30", "0:09".
function RoundRules.clock(seconds: number): string
	local whole = math.max(math.ceil(seconds - 1e-3), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- The status line over the timer.
function RoundRules.status(state: string, phase: number, enoughPlayers: boolean): string
	if state == "Intermission" then
		return "INTERMISSION"
	elseif state == "Teleport" then
		return "GET READY"
	elseif state == "Match" then
		return if phase >= 4 then "LAST MAN STANDING" else "THE SWARM IS LOOSE!"
	elseif state == "Cleanup" then
		return "ROUND OVER"
	end
	return if enoughPlayers then "STARTING SOON" else "WAITING FOR PLAYERS"
end

-- The colour of the timer's bar in a phase (1 to 4).
function RoundRules.phaseColor(phase: number): Color3
	return Color3.fromHex(R.PHASE_COLORS[math.clamp(phase, 1, #R.PHASE_COLORS)])
end

-- A random pick from `list`, never `avoid` when there's another choice (the chaser isn't the same twice running).
function RoundRules.pick<T>(list: { T }, avoid: T?, random: (number) -> number): T?
	if #list == 0 then
		return nil
	end
	local choices = list
	if avoid ~= nil and #list > 1 then
		choices = {}
		for _, each in list do
			if each ~= avoid then
				table.insert(choices, each)
			end
		end
	end
	return choices[random(#choices)]
end

return RoundRules
