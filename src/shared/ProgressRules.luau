--!strict
-- What a player keeps between visits, and the rules for it (design notes: Coins and economy, Levels and titles), kept
-- free of anything that needs a running game so they are easy to check. The server's Progress hands coins and XP out
-- with them; the screens read the same attributes.
--
-- How it gets to every screen: the server sets the attributes below on each Player (so name tags and the wallet read
-- them straight off), and the REMOTE carries the moments: coins paid ("coins"), a new level ("level"), your quests
-- ("quests"), a code's answer ("code"), the daily streak ("streak") and the round's payout ("payout").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local L = Config.Levels

local ProgressRules = {}

ProgressRules.REMOTE = "Progress" -- ReplicatedStorage.Remotes

-- Attributes the server sets on each Player.
ProgressRules.ATTR_LOADED = "DataLoaded" -- true once their save is in
ProgressRules.ATTR_COINS = "Coins" -- coins they own
ProgressRules.ATTR_LEVEL = "Level"
ProgressRules.ATTR_XP = "Xp" -- XP into their level
ProgressRules.ATTR_XP_NEED = "XpNeed" -- XP their level takes (0 at the top level)
ProgressRules.ATTR_TITLE = "Title"
ProgressRules.ATTR_STREAK = "SurviveStreak" -- rounds in a row they've survived
-- Player or bot: the coins on their head this round (the bounty); unset when there's none on them.
ProgressRules.ATTR_BOUNTY = "Bounty"
-- Hints a new player has had (Config.Hints): "HintDash", "HintChaser" (true once shown) and "HintDodge" (times shown).
ProgressRules.ATTR_HINT_DASH = "HintDash"
ProgressRules.ATTR_HINT_CHASER = "HintChaser"
ProgressRules.ATTR_HINT_DODGE = "HintDodge"

-- The lobby's show pieces (Leaderboards and LobbyExtras make them on the server; every screen draws on them).
ProgressRules.BOARDS = "LobbyBoards" -- Workspace folder: one part a leaderboard
ProgressRules.ATTR_BOARD_TITLE = "BoardTitle" -- a board part: its heading ("MOST TAGS")
ProgressRules.ATTR_BOARD_COLOR = "BoardColor" -- hex
ProgressRules.ATTR_BOARD_ROWS = "BoardRows" -- its rows, best first, as JSON: [{ n = name, v = value, u = user id }]
ProgressRules.EXTRAS = "LobbyExtras" -- Workspace folder: the pedestals, their statues and the practice dummy
ProgressRules.ATTR_PLACE = "Place" -- a pedestal or a statue: 1, 2 or 3
ProgressRules.DUMMY = "PracticeDummy" -- the dummy's body, in the extras folder
ProgressRules.DUMMY_RING = "PracticeRing" -- the ring on the glass round it

-- The saved numbers (a player's stats). The lobby's leaderboards rank by some of them (Config.Boards).
ProgressRules.STATS = table.freeze({
	"tags", -- runners tagged, all time (real players only: tags on bots don't count)
	"survives", -- full matches survived
	"clutches", -- last man standing and survived
	"streak", -- rounds in a row survived, right now
	"bestStreak",
	"bestRoundTags", -- most tags in one round
	"coinsEarned", -- every coin ever earned
	"rounds", -- rounds played to the end
	"dodges", -- perfect dodges
	"stars", -- coins picked up on the map
	"bounties", -- bounties collected or kept
})

-- XP it takes to go from `level` to the next (0 at the top level).
function ProgressRules.xpNeed(level: number): number
	if level >= L.MAX then
		return 0
	end
	return L.XP_BASE + L.XP_STEP * (math.max(level, 1) - 1)
end

-- The level `totalXp` makes, the XP into it and the XP it takes.
function ProgressRules.level(totalXp: number): (number, number, number)
	local level = 1
	local left = math.max(totalXp, 0)
	while level < L.MAX do
		local need = ProgressRules.xpNeed(level)
		if left < need then
			return level, left, need
		end
		left -= need
		level += 1
	end
	return L.MAX, 0, 0
end

-- Coins a player gets for reaching `level`.
function ProgressRules.levelCoins(level: number): number
	return L.LEVEL_COINS + L.LEVEL_COINS_STEP * math.max(level, 1)
end

-- The title worn at `level`.
function ProgressRules.title(level: number): string
	local title = L.TITLES[1].title
	for _, step in L.TITLES do
		if level >= step.level then
			title = step.title
		end
	end
	return title
end

-- "1,240" for 1240.
function ProgressRules.commas(value: number): string
	local text = tostring(math.floor(math.abs(value) + 0.5))
	local out = ""
	while #text > 3 do
		out = "," .. string.sub(text, -3) .. out
		text = string.sub(text, 1, -4)
	end
	return (if value < 0 then "-" else "") .. text .. out
end

-- "1.2K", "3.4M" for big numbers on small boards; small ones as they are.
function ProgressRules.short(value: number): string
	local n = math.floor(math.abs(value) + 0.5)
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	return ProgressRules.commas(n)
end

-- "1:05" for seconds of a match; "2:00" and the like.
function ProgressRules.clock(seconds: number): string
	local whole = math.max(math.floor(seconds + 0.5), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return ProgressRules
