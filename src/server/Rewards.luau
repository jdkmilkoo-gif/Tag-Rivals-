--!strict
-- What a round pays (design notes, Coins and economy) and what it's remembered for. The round tells this each moment
-- (a tag, a fall, a shrink, a perfect dodge, the end) and it does the rest:
--   * coins: +5 for each tag, paid at once; at the end +30 for every runner who survived, +50 more for the last runner
--     standing, +15 for a runner who lasted past phase 1 before being tagged. Coins picked up on the map are paid as
--     they're picked up (Coins);
--   * the bounty (Bounty): to the chaser who tags the wanted runner, or to the wanted runner if they survive;
--   * XP for all of it (Config.Rewards), which makes levels;
--   * the saved stats the lobby's leaderboards rank by: tags, survivor wins, clutches, the survival streak, most tags
--     in a round. Tags on bots pay coins and count for quests but never for the leaderboard stats;
--   * the moments quests count (Progress.event);
--   * each player's own payout and record for the victory screen (design notes: "Post-match record board").
-- A runner who leaves mid-match loses their survival streak, so nobody keeps a streak (or dodges a bounty) by quitting.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CoinRules = require(ReplicatedStorage.Shared.CoinRules)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Bounty = require(script.Parent.Bounty)
local History = require(script.Parent.History)
local PlayerData = require(script.Parent.PlayerData)
local Progress = require(script.Parent.Progress)

local W = Config.Rewards

local Rewards = {}

type Record = {
	startedRunner: boolean,
	alpha: boolean, -- picked as the round's first chaser
	outAt: number?, -- s into the match they stopped being a runner (tagged or fell)
	lastedPhase1: boolean, -- still a runner when phase 2 began
	firstTagAt: number?, -- s into the match of their first tag
	tags: number,
	playerTags: number, -- of those, real players
	dashTags: number,
	coins: number, -- coins this round has paid them so far (tags, bounty), on top of the ones they picked up
	xp: number,
	bounty: number, -- bounty coins they took or kept
}

export type Line = { label: string, coins: number }
export type Payout = {
	lines: { Line },
	total: number,
	xp: number,
	record: {
		role: string, -- "Runner" or "Chaser": what they ended the round as
		survived: boolean,
		clutch: boolean,
		time: number, -- s they lasted as a runner
		matchTime: number,
		stars: number,
		starsMax: number,
		tags: number,
		firstTag: number?,
		alpha: boolean,
		dashTags: number,
	},
}

local records: { [Instance]: Record } = {}
local matchStart = 0
local matchOn = false
local nameOf: (who: Instance) -> string = function(who)
	return who.Name
end
local announce: (kind: string, info: any) -> () = function() end

local function isBot(who: Instance): boolean
	return not who:IsA("Player")
end

local function roleOf(who: Instance): string
	return MoveRules.role(who:GetAttribute(MoveRules.ATTR_ROLE))
end

local function pay(who: Instance, record: Record, coins: number, source: string, quiet: boolean?)
	record.coins += coins
	Progress.addCoins(who, coins, source, quiet)
end

local function xp(who: Instance, record: Record, amount: number)
	record.xp += amount
	Progress.addXp(who, amount)
end

-- A bot's survival streak lives on its body (a player's is saved, and Progress keeps the attribute).
local function setStreak(who: Instance, value: number)
	if isBot(who) then
		who:SetAttribute(ProgressRules.ATTR_STREAK, value)
	else
		Progress.setStat(who, "streak", value)
	end
end

local function streakOf(who: Instance): number
	local value = who:GetAttribute(ProgressRules.ATTR_STREAK)
	return if type(value) == "number" then value else 0
end

---------------------------------------------------------------- the first-minute funnel

-- For brand-new players only (no round finished before this visit), the steps of their first minutes go to Roblox's
-- funnel chart (Creator Dashboard > Analytics > Funnels), so the owner can see where new players drop out.
local FUNNEL = { "Joined", "First round started", "First dash", "First round finished", "Second round finished" }
local funnelStep: { [Player]: number } = {}

local function funnel(player: Player, step: number)
	local at = funnelStep[player]
	if not at or step <= at then
		return
	end
	funnelStep[player] = step
	if RunService:IsStudio() then
		return
	end
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, FUNNEL[step])
	end)
end

---------------------------------------------------------------- the round's moments

-- The fade: roles are set. Picks who's wanted and starts everyone's record.
function Rewards.roundStarted(contestants: { Instance }, chaser: Instance)
	table.clear(records)
	matchOn = false
	local runners: { Instance } = {}
	for _, who in contestants do
		local startedRunner = who ~= chaser
		records[who] = {
			startedRunner = startedRunner,
			alpha = who == chaser,
			outAt = nil,
			lastedPhase1 = false,
			firstTagAt = nil,
			tags = 0,
			playerTags = 0,
			dashTags = 0,
			coins = 0,
			xp = 0,
			bounty = 0,
		}
		if startedRunner then
			table.insert(runners, who)
		end
		if who:IsA("Player") then
			funnel(who, 2)
		end
	end
	local wanted, amount = Bounty.pick(runners, #contestants)
	if wanted then
		announce("bounty", { who = wanted, name = nameOf(wanted), amount = amount })
	end
end

-- GO!
function Rewards.matchStarted()
	matchStart = os.clock()
	matchOn = true
end

-- `runner` stopped being a runner at `phase` (the phase just before it happened).
local function out(runner: Instance, phase: number)
	local record = records[runner]
	if record and record.startedRunner and not record.outAt then
		record.outAt = os.clock() - matchStart
		record.lastedPhase1 = phase >= 2
	end
end

-- `chaser` tagged `runner` (the round has already made it count). `phase` is the phase just before the tag.
function Rewards.tagged(chaser: Instance, runner: Instance, dash: boolean, phase: number)
	out(runner, phase)
	setStreak(runner, 0)
	local record = records[chaser]
	if record then
		record.tags += 1
		record.firstTagAt = record.firstTagAt or (os.clock() - matchStart)
		if dash then
			record.dashTags += 1
		end
		pay(chaser, record, W.TAG, "TAG")
		xp(chaser, record, W.XP_TAG)
		if not isBot(runner) then
			record.playerTags += 1
			Progress.addStat(chaser, "tags", 1)
		end
		Progress.event(chaser, "tag")
		if dash then
			Progress.event(chaser, "dashTag")
		end
	end
	local worth = Bounty.out(runner)
	if worth > 0 then
		if record then
			record.bounty += worth
			pay(chaser, record, worth, "BOUNTY")
			xp(chaser, record, Config.Bounty.XP)
			Progress.addStat(chaser, "bounties", 1)
			Progress.event(chaser, "bounty")
		end
		announce("bountyEnd", {
			kind = "tagged",
			who = runner,
			name = nameOf(runner),
			by = chaser,
			byName = nameOf(chaser),
			amount = worth,
		})
	end
end

-- `who` fell off a cut strip. A runner who falls is out (nobody gets the tag, and nobody gets their bounty).
function Rewards.fell(who: Instance, wasRunner: boolean, phase: number)
	if not wasRunner then
		return
	end
	out(who, phase)
	setStreak(who, 0)
	local worth = Bounty.out(who)
	if worth > 0 then
		announce("bountyEnd", { kind = "lost", who = who, name = nameOf(who), amount = worth })
	end
end

-- A shrink went by: the bounty on a runner who's still running grows.
function Rewards.shrunk()
	local wanted = Bounty.current()
	if wanted and roleOf(wanted) ~= "Chaser" then
		local amount = Bounty.grow()
		announce("bountyUp", { who = wanted, name = nameOf(wanted), amount = amount })
	end
end

-- `runner` perfect-dodged a chaser.
function Rewards.dodged(runner: Instance)
	local record = records[runner]
	if record then
		xp(runner, record, W.XP_DODGE)
	end
	Progress.addStat(runner, "dodges", 1)
	Progress.event(runner, "dodge")
end

-- The match is over (`winner`: "Runners", "Chasers" or "None"). Pays the end-of-round coins, updates everyone's stats,
-- and gives back each player's payout for their victory screen.
function Rewards.matchEnded(winner: string, contestants: { Instance }, phase: number): { [Player]: Payout }
	local matchTime = if matchOn then os.clock() - matchStart else 0
	matchOn = false
	local counted = winner ~= "None" -- a round that fell apart (players left) pays what was earned, nothing more
	local payouts: { [Player]: Payout } = {}

	-- the wanted runner who's still running keeps their own bounty
	local wanted, worth = Bounty.current()
	if wanted and counted and roleOf(wanted) ~= "Chaser" then
		local record = records[wanted]
		if record then
			record.bounty += worth
			pay(wanted, record, worth, "BOUNTY", true)
			xp(wanted, record, Config.Bounty.XP)
			Progress.addStat(wanted, "bounties", 1)
			Progress.event(wanted, "bounty")
		end
		announce("bountyEnd", { kind = "kept", who = wanted, name = nameOf(wanted), amount = worth })
	end
	Bounty.clear()

	for _, who in contestants do
		local record = records[who]
		if record and who.Parent ~= nil then
			local survived = record.startedRunner and not record.outAt and roleOf(who) ~= "Chaser"
			local clutch = survived and phase >= 4
			local lines: { Line } = {}
			local function line(label: string, coins: number, alreadyPaid: boolean?)
				if coins > 0 then
					table.insert(lines, { label = label, coins = coins })
					if not alreadyPaid then
						pay(who, record, coins, label, true)
					end
				end
			end
			local picked = who:GetAttribute(CoinRules.ATTR_ROUND_COINS)
			local pickedCoins = if type(picked) == "number" then picked else 0
			if counted then
				if survived then
					line("SURVIVED", W.SURVIVE)
					xp(who, record, W.XP_SURVIVE)
					if clutch then
						line("LAST MAN STANDING", W.CLUTCH)
						xp(who, record, W.XP_CLUTCH)
					end
				elseif record.lastedPhase1 then
					line("OUTLASTED PHASE 1", W.PHASE1)
					xp(who, record, W.XP_PHASE1)
				end
				xp(who, record, W.XP_ROUND)
			end
			if record.tags > 0 then
				line(if record.tags == 1 then "1 TAG" else `{record.tags} TAGS`, record.tags * W.TAG, true)
			end
			line("BOUNTY", record.bounty, true)
			line("COINS PICKED UP", pickedCoins, true)

			-- the saved stats and the moments quests count
			if counted then
				Progress.addStat(who, "rounds", 1)
				Progress.event(who, "round")
				Progress.maxStat(who, "bestRoundTags", record.playerTags)
				if survived then
					setStreak(who, streakOf(who) + 1)
					Progress.addStat(who, "survives", 1)
					Progress.maxStat(who, "bestStreak", streakOf(who))
					Progress.event(who, "survive")
					Progress.event(who, "phase1")
					if clutch then
						Progress.addStat(who, "clutches", 1)
						Progress.event(who, "clutch")
					end
				elseif record.lastedPhase1 then
					Progress.event(who, "phase1")
				end
			end

			if who:IsA("Player") then
				Progress.publish(who)
				-- their first finished round, then their second (a step is only ever said once)
				local step = funnelStep[who]
				if step then
					funnel(who, if step >= 4 then 5 else 4)
				end
				payouts[who] = {
					lines = lines,
					total = record.coins + pickedCoins,
					xp = record.xp,
					record = {
						role = if roleOf(who) == "Chaser" then "Chaser" else "Runner",
						survived = survived,
						clutch = clutch,
						time = if survived then matchTime else (record.outAt or 0),
						matchTime = matchTime,
						stars = pickedCoins // Config.Coins.VALUE,
						starsMax = Config.Move.STAR_SPEED_MAX // Config.Move.STAR_SPEED,
						tags = record.tags,
						firstTag = record.firstTagAt,
						alpha = record.alpha,
						dashTags = record.dashTags,
					},
				}
			end
		end
	end
	return payouts
end

-- The round is cleared away (back to the lobby).
function Rewards.roundCleared()
	matchOn = false
	Bounty.clear()
	table.clear(records)
end

---------------------------------------------------------------- dashes (for quests)

-- A player dashed. In a match that's a "dash", and for a runner with a chaser close it's a "closeDash" too.
local function onDash(player: Player)
	if funnelStep[player] == 2 then
		funnel(player, 3) -- their first dash once their first round has begun
	end
	if not matchOn or player:GetAttribute(RoundRules.ATTR_IN_ROUND) ~= true then
		return
	end
	if Workspace:GetAttribute(RoundRules.ATTR_STATE) ~= "Match" then
		return
	end
	Progress.event(player, "dash")
	if roleOf(player) == "Chaser" then
		return
	end
	local mine = History.rootOf(player)
	if not mine then
		return
	end
	for who in records do
		if who ~= player and who.Parent ~= nil and roleOf(who) == "Chaser" then
			local theirs = History.rootOf(who)
			if theirs and CoinRules.flatDistance(mine.Position, theirs.Position) <= Config.Quests.CLOSE_RANGE then
				Progress.event(player, "closeDash")
				return
			end
		end
	end
end

-- `name` gives the name screens show for a player or bot; `say` sends a moment to every screen (the Round remote).
function Rewards.start(name: (who: Instance) -> string, say: (kind: string, info: any) -> ())
	nameOf = name
	announce = say

	local function onPlayer(player: Player)
		player:GetAttributeChangedSignal(MoveRules.ATTR_DASH_COUNT):Connect(function()
			onDash(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	PlayerData.onLoaded(function(player, profile)
		-- the funnel is for players on their very first visit
		if (profile.stats.rounds or 0) == 0 then
			funnelStep[player] = 0
			funnel(player, 1)
		end
	end)

	-- leaving mid-match as a runner ends the survival streak, and a bounty on them is gone
	PlayerData.onRelease(function(player, profile)
		local record = records[player]
		if record and matchOn and record.startedRunner and not record.outAt then
			profile.stats.streak = 0
		end
		local worth = Bounty.out(player)
		if worth > 0 then
			announce("bountyEnd", { kind = "lost", who = player, name = nameOf(player), amount = worth })
		end
		records[player] = nil
		funnelStep[player] = nil
	end)
end

return Rewards
