--!strict
-- Saving (design notes, Build plan step 2): what every player keeps between visits, loaded when they join and saved
-- while they play, when they leave and when the server shuts down. The rest of the server only ever reads and changes
-- the copy in memory (PlayerData.get); this is the only place that touches Roblox's DataStores.
--   * One save per player, under one key, so nothing can go half-saved.
--   * Only one server holds a player's save at a time (a "lock" inside the save, refreshed on every autosave). A
--     player who hops servers faster than their old server saves waits a few seconds for it; if the old server never
--     lets go (it crashed), its hold counts as dead after Config.Data.LOCK_STALE. This is what stops coins being
--     copied or lost by quick rejoining.
--   * Every call is retried with a growing wait, and a save that can't be loaded is never replaced by an empty one:
--     the player is asked to rejoin instead.
--   * Studio play-tests keep everything in memory only (Config.Data.STUDIO_SAVES), so tests never touch real saves.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)

local D = Config.Data

local VERSION = 1

export type Profile = {
	version: number,
	coins: number,
	xp: number, -- all the XP they've ever earned (ProgressRules.level turns it into a level)
	stats: { [string]: number }, -- ProgressRules.STATS
	quests: { [string]: any }, -- by set ("daily", "weekly", "monthly"): Quests keeps these
	codes: { [string]: boolean }, -- codes they've used
	login: { day: number, count: number }, -- the daily streak: the last day they were paid, and days in a row
	hints: { [string]: number }, -- first-minute hints they've had
	tokens: { [string]: number }, -- paid quest rerolls bought and not used yet, by set
	receipts: { string }, -- the newest purchases handled (so none is ever paid out twice)
	firstJoin: number,
}

local PlayerData = {}

local live = not RunService:IsStudio() or D.STUDIO_SAVES
local store: DataStore? = nil
local jobId = if game.JobId ~= "" then game.JobId else "studio"

local profiles: { [Player]: Profile } = {}
local held: { [number]: Profile } = {} -- by user id: the saves this server holds
local nextSave: { [Player]: number } = {}
local saving: { [number]: boolean } = {} -- user ids with a save on its way
local closing: { [Player]: boolean } = {} -- players whose last save is being made
local releasing = 0 -- how many of those are still going
local loadedCallbacks: { (player: Player, profile: Profile) -> () } = {}
local releaseCallbacks: { (player: Player, profile: Profile) -> () } = {}

local function fresh(): Profile
	local stats: { [string]: number } = {}
	for _, name in ProgressRules.STATS do
		stats[name] = 0
	end
	return {
		version = VERSION,
		coins = 0,
		xp = 0,
		stats = stats,
		quests = {},
		codes = {},
		login = { day = 0, count = 0 },
		hints = {},
		tokens = {},
		receipts = {},
		firstJoin = os.time(),
	}
end

local function count(value: any): number
	if type(value) == "number" and value == value and value >= 0 and value < 1e15 then
		return value
	end
	return 0
end

-- A stored save made whole: anything missing (a new player, or a field added since they last played) gets its
-- starting value, and anything that isn't what it should be is dropped.
local function reconcile(data: any): Profile
	local profile = fresh()
	if type(data) ~= "table" then
		return profile
	end
	profile.coins = math.floor(count(data.coins))
	profile.xp = math.floor(count(data.xp))
	if type(data.stats) == "table" then
		for name, value in data.stats do
			if type(name) == "string" then
				profile.stats[name] = count(value)
			end
		end
	end
	for _, field in { "quests", "codes", "hints", "tokens" } do
		if type(data[field]) == "table" then
			(profile :: any)[field] = data[field]
		end
	end
	if type(data.login) == "table" then
		profile.login = { day = count(data.login.day), count = count(data.login.count) }
	end
	if type(data.receipts) == "table" then
		for _, id in data.receipts do
			if type(id) == "string" and #profile.receipts < 50 then
				table.insert(profile.receipts, id)
			end
		end
	end
	if type(data.firstJoin) == "number" then
		profile.firstJoin = data.firstJoin
	end
	return profile
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, each in value do
		copy[key] = deepCopy(each)
	end
	return copy
end

-- Runs a DataStore call up to `tries` times, waiting longer after each failure. Gives back whether it worked.
local function withRetry(tries: number, what: string, call: () -> ()): boolean
	local wait = 1
	for attempt = 1, tries do
		local ok, problem = pcall(call)
		if ok then
			return true
		end
		warn(`[{Config.GameName}] {what} failed (try {attempt} of {tries}): {problem}`)
		if attempt < tries then
			task.wait(wait)
			wait = math.min(wait * 2, 8)
		end
	end
	return false
end

local function keyOf(userId: number): string
	return "u_" .. tostring(userId)
end

-- Takes hold of a player's save for this server and gives it back; nil when it couldn't be loaded (Roblox's storage is
-- down, or another server still holds it after every try).
local function claim(userId: number): Profile?
	local data = store
	if not data then
		return fresh()
	end
	for attempt = 1, D.LOAD_TRIES do
		local claimed: Profile? = nil
		local taken = false
		local ok = withRetry(3, "loading a save", function()
			data:UpdateAsync(keyOf(userId), function(old: any)
				claimed, taken = nil, false
				if type(old) == "table" and type(old.lock) == "table" then
					local lock = old.lock
					if lock.job ~= jobId and os.time() - count(lock.at) < D.LOCK_STALE then
						taken = true
						return nil -- another server has it: leave it alone
					end
				end
				local profile = reconcile(old)
				local stored = deepCopy(profile)
				stored.lock = { job = jobId, at = os.time() }
				claimed = profile
				return stored
			end)
		end)
		if not ok then
			return nil
		end
		if claimed then
			return claimed
		end
		if not taken then
			return nil
		end
		-- their last server is still saving: give it a moment
		if attempt < D.LOAD_TRIES then
			task.wait(2 + attempt)
		end
	end
	return nil
end

-- Writes a player's save. `release`: they're leaving, so this server lets go of it.
local function write(userId: number, profile: Profile, release: boolean): boolean
	local data = store
	if not data then
		return true
	end
	while saving[userId] do
		task.wait(0.2)
	end
	if not release and held[userId] ~= profile then
		return true -- they left while this autosave waited its turn: their last save has already gone
	end
	saving[userId] = true
	local ok = withRetry(if release then 5 else 2, "saving", function()
		data:UpdateAsync(keyOf(userId), function(old: any)
			if type(old) == "table" and type(old.lock) == "table" and old.lock.job ~= jobId then
				-- another server took this save over (ours looked dead to it): never write over its copy
				return nil
			end
			local stored = deepCopy(profile)
			stored.lock = if release then nil else { job = jobId, at = os.time() }
			return stored
		end)
	end)
	saving[userId] = nil
	return ok
end

-- The player's save, once it's loaded (nil before that, and after they've left).
function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

-- Calls `callback` for every player whose save loads from now on, and for everyone already loaded.
function PlayerData.onLoaded(callback: (player: Player, profile: Profile) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

-- Calls `callback` just before a leaving player's last save (last changes go in here).
function PlayerData.onRelease(callback: (player: Player, profile: Profile) -> ())
	table.insert(releaseCallbacks, callback)
end

-- Are saves real here (false in a Studio play-test, where everything stays in memory)?
function PlayerData.isLive(): boolean
	return live
end

local function load(player: Player)
	local userId = player.UserId
	while saving[userId] do
		task.wait(0.2) -- they left this same server a moment ago and its last save is still going
	end
	local profile = if live and userId > 0 then claim(userId) else fresh()
	if player.Parent ~= Players then
		-- left while loading: let go of the save again
		if profile and live and userId > 0 then
			write(userId, profile, true)
		end
		return
	end
	if not profile then
		player:Kick("Your Tag Rivals save couldn't be loaded just now. Please join again in a moment.")
		return
	end
	profiles[player] = profile
	held[userId] = profile
	nextSave[player] = os.clock() + D.AUTOSAVE * (0.5 + (userId % 100) / 200)
	for _, callback in loadedCallbacks do
		local ok, problem = pcall(callback, player, profile)
		if not ok then
			warn(`[{Config.GameName}] setting up {player.Name}'s save broke: {problem}`)
		end
	end
	player:SetAttribute(ProgressRules.ATTR_LOADED, true)
end

local function release(player: Player)
	local profile = profiles[player]
	if not profile or closing[player] then
		return
	end
	closing[player] = true
	releasing += 1
	for _, callback in releaseCallbacks do
		local ok, problem = pcall(callback, player, profile)
		if not ok then
			warn(`[{Config.GameName}] closing {player.Name}'s save broke: {problem}`)
		end
	end
	profiles[player] = nil
	nextSave[player] = nil
	if held[player.UserId] == profile then
		held[player.UserId] = nil
	end
	if live and player.UserId > 0 then
		write(player.UserId, profile, true)
	end
	closing[player] = nil
	releasing -= 1
end

function PlayerData.start()
	if live then
		local ok, found = pcall(function()
			return DataStoreService:GetDataStore(D.STORE)
		end)
		if ok then
			store = found
		else
			warn(`[{Config.GameName}] the DataStore couldn't be opened ({found}); nothing will be saved`)
			live = false
		end
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(release)

	-- autosaves, each player on their own beat so they never all save at once
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for player, profile in profiles do
				if now >= (nextSave[player] or 0) then
					nextSave[player] = now + D.AUTOSAVE
					if live and player.UserId > 0 then
						task.spawn(write, player.UserId, profile, false)
					end
				end
			end
		end
	end)

	-- the server is shutting down: everyone's last save, all at once, and wait for them
	game:BindToClose(function()
		if not live then
			return
		end
		for _, player in Players:GetPlayers() do
			task.spawn(release, player)
		end
		local started = os.clock()
		while (releasing > 0 or next(saving) ~= nil) and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return PlayerData
