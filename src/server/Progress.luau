--!strict
-- Coins, XP, levels, titles and stats (design notes: Coins and economy, Levels and titles): the one place that
-- changes what a player owns. Everything else on the server asks it to (Progress.addCoins, addXp, addStat), so the
-- rules stay in one spot and nothing on a player's screen can ever set a number.
--   * Each change goes into the player's save (PlayerData) and onto their Player's attributes (ProgressRules names
--     them), which is what name tags, the wallet and the pedestals read.
--   * The Progress remote carries the moments to a player's screen ("coins", "level", "streak", ...) and brings their
--     requests back (Progress.onClient): every request is checked for its kind and held to a few a second.
--   * Moments that quests count ("tag", "survive", "dash", ...) are said through Progress.event; Quests listens.
--   * The first join of each day pays the daily streak (Config.Streak).
-- A bot handed to any of these is quietly ignored, so the round doesn't have to tell bots from players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)
local PlayerData = require(script.Parent.PlayerData)

local Progress = {}

type Handler = (player: Player, ...any) -> ()
type Listener = (player: Player, event: string, amount: number) -> ()
type Bucket = { tokens: number, at: number }

local REQUESTS_PER_SECOND = 3 -- of each kind, per player
local REQUEST_BURST = 6

local remote: RemoteEvent = nil :: any
local handlers: { [string]: Handler } = {}
local listeners: { Listener } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}
local boardTitle: (userId: number) -> string? = function()
	return nil
end

local function profileOf(who: Instance): (Player?, PlayerData.Profile?)
	if not who:IsA("Player") then
		return nil, nil
	end
	local profile = PlayerData.get(who)
	if not profile then
		return nil, nil
	end
	return who, profile
end

-- Puts a player's numbers on their Player, for every screen to read.
function Progress.publish(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local level, into, need = ProgressRules.level(profile.xp)
	player:SetAttribute(ProgressRules.ATTR_COINS, profile.coins)
	player:SetAttribute(ProgressRules.ATTR_LEVEL, level)
	player:SetAttribute(ProgressRules.ATTR_XP, into)
	player:SetAttribute(ProgressRules.ATTR_XP_NEED, need)
	player:SetAttribute(ProgressRules.ATTR_TITLE, boardTitle(player.UserId) or ProgressRules.title(level))
	player:SetAttribute(ProgressRules.ATTR_STREAK, profile.stats.streak or 0)
end

-- Tells one player's screen something (a "kind" and whatever goes with it).
function Progress.send(player: Player, kind: string, ...: any)
	if remote and player.Parent == Players then
		remote:FireClient(player, kind, ...)
	end
end

-- Handles one kind of request from players' screens. The handler must check everything it's given.
function Progress.onClient(kind: string, handler: Handler)
	handlers[kind] = handler
end

-- Hears every moment said through Progress.event (Quests).
function Progress.listen(listener: Listener)
	table.insert(listeners, listener)
end

-- Where a leaderboard title comes from (Leaderboards): it wins over the level's title.
function Progress.setBoardTitles(source: (userId: number) -> string?)
	boardTitle = source
end

-- Gives `who` coins (never takes: see Progress.spend). `source` is a short word for where they came from ("TAG",
-- "QUEST", ...), shown in the pop-up on their screen; `quiet` skips the pop-up (something else already shows it).
function Progress.addCoins(who: Instance, amount: number, source: string, quiet: boolean?)
	local player, profile = profileOf(who)
	if not player or not profile or amount ~= amount or amount <= 0 then
		return
	end
	local whole = math.floor(amount)
	profile.coins += whole
	profile.stats.coinsEarned = (profile.stats.coinsEarned or 0) + whole
	player:SetAttribute(ProgressRules.ATTR_COINS, profile.coins)
	if not quiet then
		Progress.send(player, "coins", whole, source, profile.coins)
	end
end

-- Takes coins if `who` has them; gives back whether it did.
function Progress.spend(who: Instance, amount: number): boolean
	local player, profile = profileOf(who)
	if not player or not profile or amount ~= amount or amount < 0 then
		return false
	end
	local whole = math.ceil(amount)
	if profile.coins < whole then
		return false
	end
	profile.coins -= whole
	player:SetAttribute(ProgressRules.ATTR_COINS, profile.coins)
	return true
end

-- Gives `who` XP. Each new level pays coins and is told to their screen.
function Progress.addXp(who: Instance, amount: number)
	local player, profile = profileOf(who)
	if not player or not profile or amount ~= amount or amount <= 0 then
		return
	end
	local before = ProgressRules.level(profile.xp)
	profile.xp += math.floor(amount)
	local after = ProgressRules.level(profile.xp)
	for level = before + 1, after do
		local coins = ProgressRules.levelCoins(level)
		Progress.addCoins(player, coins, "LEVEL UP", true)
		Progress.send(player, "level", level, ProgressRules.title(level), coins)
	end
	Progress.publish(player)
end

-- A saved number of `who`'s (0 for a bot, or before their save is in).
function Progress.stat(who: Instance, name: string): number
	local _, profile = profileOf(who)
	return if profile then profile.stats[name] or 0 else 0
end

-- Adds to a saved number; gives back what it is now.
function Progress.addStat(who: Instance, name: string, amount: number): number
	local player, profile = profileOf(who)
	if not player or not profile then
		return 0
	end
	local value = (profile.stats[name] or 0) + amount
	profile.stats[name] = value
	return value
end

-- Sets a saved number.
function Progress.setStat(who: Instance, name: string, value: number)
	local player, profile = profileOf(who)
	if player and profile then
		profile.stats[name] = value
		if name == "streak" then
			player:SetAttribute(ProgressRules.ATTR_STREAK, value)
		end
	end
end

-- Raises a saved number to `value` if that's more (a best).
function Progress.maxStat(who: Instance, name: string, value: number)
	local _, profile = profileOf(who)
	if profile and value > (profile.stats[name] or 0) then
		profile.stats[name] = value
	end
end

-- Says a moment quests may count ("tag", "survive", "dash", ...; QuestRules lists them).
function Progress.event(who: Instance, name: string, amount: number?)
	local player, profile = profileOf(who)
	if not player or not profile then
		return
	end
	for _, listener in listeners do
		local ok, problem = pcall(listener, player, name, amount or 1)
		if not ok then
			warn(`[{Config.GameName}] a quest listener broke on "{name}": {problem}`)
		end
	end
end

-- May this player's request of this kind go through right now (a few a second, no more)?
local function allow(player: Player, kind: string): boolean
	local now = os.clock()
	local mine = buckets[player]
	if not mine then
		mine = {}
		buckets[player] = mine
	end
	local bucket = mine[kind]
	if not bucket then
		bucket = { tokens = REQUEST_BURST, at = now }
		mine[kind] = bucket
	end
	bucket.tokens = math.min(REQUEST_BURST, bucket.tokens + (now - bucket.at) * REQUESTS_PER_SECOND)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- The first join of the day pays the daily streak: a day more than yesterday's, or back to day 1 after a missed day.
local function payStreak(player: Player, profile: PlayerData.Profile)
	local today = os.time() // 86400
	if profile.login.day == today then
		return
	end
	local days = if profile.login.day == today - 1 then profile.login.count + 1 else 1
	profile.login = { day = today, count = days }
	local rewards = Config.Streak.REWARDS
	local coins = rewards[math.min(days, #rewards)]
	Progress.addCoins(player, coins, "DAILY BONUS", true)
	-- their screen is still loading: tell it in a moment
	task.delay(6, function()
		Progress.send(player, "streak", days, coins)
	end)
end

local HINT_ATTRIBUTES = {
	dash = ProgressRules.ATTR_HINT_DASH,
	chaser = ProgressRules.ATTR_HINT_CHASER,
	dodge = ProgressRules.ATTR_HINT_DODGE,
}

local function publishHints(player: Player, profile: PlayerData.Profile)
	player:SetAttribute(ProgressRules.ATTR_HINT_DASH, (profile.hints.dash or 0) > 0)
	player:SetAttribute(ProgressRules.ATTR_HINT_CHASER, (profile.hints.chaser or 0) > 0)
	player:SetAttribute(ProgressRules.ATTR_HINT_DODGE, profile.hints.dodge or 0)
end

function Progress.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local found = remotes:FindFirstChild(ProgressRules.REMOTE)
	if not found then
		found = Instance.new("RemoteEvent")
		found.Name = ProgressRules.REMOTE
		found.Parent = remotes
	end
	remote = found :: RemoteEvent

	remote.OnServerEvent:Connect(function(player: Player, kind: unknown, ...: any)
		if type(kind) ~= "string" then
			return
		end
		local handler = handlers[kind]
		if not handler or not allow(player, kind) or not PlayerData.get(player) then
			return
		end
		local ok, problem = pcall(handler, player, ...)
		if not ok then
			warn(`[{Config.GameName}] a "{kind}" request from {player.Name} broke: {problem}`)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	-- a new player's screen says which first-minute hint it has just shown, so it's never shown twice
	Progress.onClient("hint", function(player: Player, key: unknown)
		local profile = PlayerData.get(player)
		if not profile or type(key) ~= "string" or HINT_ATTRIBUTES[key] == nil then
			return
		end
		profile.hints[key] = math.min((profile.hints[key] or 0) + 1, 99)
		publishHints(player, profile)
	end)

	PlayerData.onLoaded(function(player, profile)
		payStreak(player, profile)
		publishHints(player, profile)
		Progress.publish(player)
	end)
end

return Progress
