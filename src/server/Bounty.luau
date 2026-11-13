--!strict
-- The bounty (owner 2026-11-13: "Add a Bounty system"). Each round with enough players, one runner is WANTED: the one
-- on the longest run of survived rounds (picked among the runners at random when it's a tie, or when nobody has a
-- run going). The coins on their head show over it on every screen (the Bounty attribute; NameTags draws it).
--   * The chaser who tags them takes the bounty.
--   * It grows at every shrink they're still running at.
--   * If they survive the match, they keep it themselves.
--   * If they fall off a cut strip, nobody gets it.
-- A bot can be wanted (tagging it pays the same); a bot that collects or keeps one just ends it. Rewards runs this
-- from the round's moments and pays whoever it says. Numbers in Config.Bounty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)

local B = Config.Bounty

local Bounty = {}

local wanted: Instance? = nil
local amount = 0
local rng = Random.new()

local function streakOf(who: Instance): number
	local value = who:GetAttribute(ProgressRules.ATTR_STREAK)
	return if type(value) == "number" then value else 0
end

-- Nobody is wanted any more.
function Bounty.clear()
	local who = wanted
	if who then
		who:SetAttribute(ProgressRules.ATTR_BOUNTY, nil)
	end
	wanted = nil
	amount = 0
end

-- A new round: picks who's wanted among `runners` (`players` is everyone in the round). Gives back who and for how
-- much, or nil when the round is too small for a bounty.
function Bounty.pick(runners: { Instance }, players: number): (Instance?, number)
	Bounty.clear()
	if players < B.MIN_PLAYERS or #runners == 0 then
		return nil, 0
	end
	local best = 0
	for _, who in runners do
		best = math.max(best, streakOf(who))
	end
	local top: { Instance } = {}
	for _, who in runners do
		if streakOf(who) == best then
			table.insert(top, who)
		end
	end
	local who = top[rng:NextInteger(1, #top)]
	wanted = who
	amount = math.min(B.BASE + B.PER_STREAK * best, B.MAX)
	who:SetAttribute(ProgressRules.ATTR_BOUNTY, amount)
	return who, amount
end

-- Who's wanted right now, and for how much.
function Bounty.current(): (Instance?, number)
	return wanted, amount
end

-- A shrink went by with the wanted runner still running: the bounty grows. Gives back the new amount (0: no bounty).
function Bounty.grow(): number
	local who = wanted
	if not who then
		return 0
	end
	amount = math.min(amount + B.PER_SHRINK, B.MAX)
	who:SetAttribute(ProgressRules.ATTR_BOUNTY, amount)
	return amount
end

-- `who` stopped being a runner (tagged, fell, or left). If they were the wanted one the bounty ends: gives back what
-- it was worth (0 if they weren't).
function Bounty.out(who: Instance): number
	if who ~= wanted then
		return 0
	end
	local worth = amount
	Bounty.clear()
	return worth
end

return Bounty
