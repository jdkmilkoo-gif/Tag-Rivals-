--!strict
-- Quests (design notes, Coins and economy): every player has 3 random quests in each of Daily, Weekly and Monthly.
-- This hands them out, counts them and pays them; the quest panel on each screen (QuestPanel) only draws what it's
-- sent and asks.
--   * A set is dealt afresh when its day, week or month turns over (QuestRules.period), also for someone playing
--     through the turn.
--   * Progress comes from the moments the rest of the server says (Progress.event); a finished quest waits for its
--     CLAIM button, then pays its coins.
--   * Reroll swaps one unfinished quest for another: one free daily reroll a day, then Robux (the developer products
--     in Config.Quests.REROLL_PRODUCTS; until those ids are filled in, the paid button stays hidden). A bought reroll
--     that can't be used at once is kept as a token on the save, so a purchase is never lost.
-- Everything a screen sends is checked here: the set's name, the quest's place in it, and whether it may be claimed
-- or swapped at all.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local PlayerData = require(script.Parent.PlayerData)
local Progress = require(script.Parent.Progress)

local Q = Config.Quests

local Quests = {}

type SetState = { period: number, list: { QuestRules.Entry }, freeUsed: number }

local rng = Random.new()
local dirty: { [Player]: boolean } = {} -- players whose screen needs their quests sent again
local pending: { [Player]: { set: string, index: number } } = {} -- the reroll a player is buying

local function random(n: number): number
	return rng:NextInteger(1, n)
end

local function isSet(value: unknown): boolean
	return value == "daily" or value == "weekly" or value == "monthly"
end

local function deal(set: QuestRules.SetName, period: number): SetState
	local list: { QuestRules.Entry } = {}
	for _, each in QuestRules.pick(set, Q.PER_SET, {}, random) do
		table.insert(list, { id = each.id, progress = 0, claimed = false })
	end
	return { period = period, list = list, freeUsed = 0 }
end

-- A player's sets, dealt afresh where their day, week or month has turned over (or a saved quest no longer exists).
-- Gives back whether anything changed.
local function refresh(profile: PlayerData.Profile): boolean
	local now = os.time()
	local changed = false
	for _, set in QuestRules.SETS do
		local period = QuestRules.period(set, now)
		local state = profile.quests[set]
		local good = type(state) == "table" and state.period == period and type(state.list) == "table"
		if good then
			for _, entry in state.list do
				if
					type(entry) ~= "table"
					or type(entry.id) ~= "string"
					or type(entry.progress) ~= "number"
					or not QuestRules.get(entry.id)
				then
					good = false
				end
			end
			good = good and #state.list == Q.PER_SET
		end
		if not good then
			profile.quests[set] = deal(set, period)
			changed = true
		end
	end
	return changed
end

-- What a player's screen is sent: their quests, their rerolls, and the server's clock.
local function snapshot(profile: PlayerData.Profile): any
	local sets = {}
	for _, set in QuestRules.SETS do
		local state = profile.quests[set] :: SetState
		local list = {}
		for i, entry in state.list do
			list[i] = { id = entry.id, progress = entry.progress, claimed = entry.claimed }
		end
		sets[set] = {
			list = list,
			free = if set == "daily" then math.max(Q.FREE_REROLLS - (state.freeUsed or 0), 0) else 0,
			tokens = profile.tokens[set] or 0,
			paid = (Q.REROLL_PRODUCTS :: any)[set] > 0, -- can a reroll be bought yet?
			price = (Q.REROLL_ROBUX :: any)[set],
		}
	end
	return { sets = sets, now = os.time() }
end

local function send(player: Player)
	local profile = PlayerData.get(player)
	if profile then
		refresh(profile)
		Progress.send(player, "quests", snapshot(profile))
	end
end

-- A moment happened to `player`: every unfinished quest that counts it moves on.
local function onEvent(player: Player, event: string, amount: number)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	refresh(profile)
	for _, set in QuestRules.SETS do
		local state = profile.quests[set] :: SetState
		for _, entry in state.list do
			local quest = QuestRules.get(entry.id)
			if quest and quest.event == event and not entry.claimed and entry.progress < quest.goal then
				entry.progress = math.min(entry.progress + amount, quest.goal)
				dirty[player] = true
				if entry.progress >= quest.goal then
					Progress.send(player, "questDone", quest.title, quest.reward)
				end
			end
		end
	end
end

local function entryAt(profile: PlayerData.Profile, set: unknown, index: unknown): (SetState?, QuestRules.Entry?)
	if not isSet(set) or type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > Q.PER_SET then
		return nil, nil
	end
	refresh(profile)
	local state = profile.quests[set :: string] :: SetState
	return state, state.list[index]
end

-- CLAIM: a finished quest pays its coins, once.
local function onClaim(player: Player, set: unknown, index: unknown)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local _, entry = entryAt(profile, set, index)
	local quest = if entry then QuestRules.get(entry.id) else nil
	if not entry or not quest or entry.claimed or entry.progress < quest.goal then
		return
	end
	entry.claimed = true
	Progress.addCoins(player, quest.reward, "QUEST")
	Progress.addXp(player, math.floor(quest.reward / 10))
	send(player)
end

-- Swaps quest `index` of `set` for another one the player doesn't have.
local function swap(profile: PlayerData.Profile, set: string, index: number): boolean
	local state = profile.quests[set] :: SetState
	local skip: { [string]: boolean } = {}
	for _, entry in state.list do
		skip[entry.id] = true
	end
	local new = QuestRules.pick(set :: QuestRules.SetName, 1, skip, random)[1]
	if not new then
		return false
	end
	state.list[index] = { id = new.id, progress = 0, claimed = false }
	return true
end

-- REROLL: the free one first (dailies), then a bought token, else the purchase prompt.
local function onReroll(player: Player, set: unknown, index: unknown)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local state, entry = entryAt(profile, set, index)
	local quest = if entry then QuestRules.get(entry.id) else nil
	if not state or not entry or not quest or entry.claimed or entry.progress >= quest.goal then
		return -- nothing to swap, or it's finished: claim it instead
	end
	local name = set :: string
	local place = index :: number
	if name == "daily" and (state.freeUsed or 0) < Q.FREE_REROLLS then
		if swap(profile, name, place) then
			state.freeUsed = (state.freeUsed or 0) + 1
		end
	elseif (profile.tokens[name] or 0) > 0 then
		if swap(profile, name, place) then
			profile.tokens[name] -= 1
		end
	else
		local product = (Q.REROLL_PRODUCTS :: any)[name]
		if type(product) == "number" and product > 0 then
			pending[player] = { set = name, index = place }
			MarketplaceService:PromptProductPurchase(player, product)
		end
		return
	end
	send(player)
end

-- A reroll was bought: a token for that set goes on the save, and the swap they were asking for is made at once.
local function onReceipt(info: any): Enum.ProductPurchaseDecision
	local set: string? = nil
	for name, product in Q.REROLL_PRODUCTS :: any do
		if product == info.ProductId and product > 0 then
			set = name
		end
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local profile = if player then PlayerData.get(player) else nil
	if not set or not player or not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receipt = tostring(info.PurchaseId)
	if table.find(profile.receipts, receipt) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	table.insert(profile.receipts, receipt)
	while #profile.receipts > 50 do
		table.remove(profile.receipts, 1)
	end
	profile.tokens[set] = (profile.tokens[set] or 0) + 1
	local wanted = pending[player]
	pending[player] = nil
	if wanted and wanted.set == set then
		refresh(profile)
		local state = profile.quests[set] :: SetState
		local entry = state.list[wanted.index]
		local quest = if entry then QuestRules.get(entry.id) else nil
		if entry and quest and not entry.claimed and entry.progress < quest.goal and swap(profile, set, wanted.index) then
			profile.tokens[set] -= 1
		end
	end
	send(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Quests.start()
	Progress.listen(onEvent)
	Progress.onClient("quests", send)
	Progress.onClient("claim", onClaim)
	Progress.onClient("reroll", onReroll)

	PlayerData.onLoaded(function(player, profile)
		refresh(profile)
		Progress.send(player, "quests", snapshot(profile))
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		pending[player] = nil
	end)

	local paid = false
	for _, product in Q.REROLL_PRODUCTS :: any do
		paid = paid or product > 0
	end
	if paid then
		-- (the game's only purchases so far; a shop's products will share this one handler)
		MarketplaceService.ProcessReceipt = onReceipt
	end

	-- progress goes to screens a couple of times a second at most, and sets turn over for players who play through
	-- midnight
	task.spawn(function()
		local sinceTurn = 0
		while true do
			task.wait(0.5)
			for player in dirty do
				dirty[player] = nil
				send(player)
			end
			sinceTurn += 0.5
			if sinceTurn >= 30 then
				sinceTurn = 0
				for _, player in Players:GetPlayers() do
					local profile = PlayerData.get(player)
					if profile and refresh(profile) then
						Progress.send(player, "quests", snapshot(profile))
					end
				end
			end
		end
	end)
end

return Quests
