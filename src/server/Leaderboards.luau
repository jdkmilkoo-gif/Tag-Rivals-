--!strict
-- The lobby's leaderboards (design notes, Lobby: "holographic leaderboards"; Config.Boards): six boards floating in a
-- ring in the lobby's middle, each ranking every player of the game by one saved number.
--   * Each number has its own ordered store. A player's numbers go there when they've changed (one board's worth
--     every REFRESH / 6 s) and when they leave. They only ever go up, so a late write can never lower one.
--   * Each board's top 10 is read in turn, one board every REFRESH / 6 s, so the reads are spread out. The players in
--     this server are mixed in with their numbers as they are right now, so a tag shows on the board at once.
--   * The server only publishes the rows (a short piece of text on each board's part); every screen draws its own
--     boards from them (LobbyBoards).
--   * Whoever tops a board wears its title over their head ("#1 TAGGER") instead of their level's.
--   * A Studio play-test never touches the stores: its boards rank the players in the test.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)
local PlayerData = require(script.Parent.PlayerData)
local Progress = require(script.Parent.Progress)

local B = Config.Boards
local L = Config.Lobby
local A = Config.Arena

local Leaderboards = {}

type Row = { id: number, name: string, value: number }
type Board = {
	stat: string,
	short: string,
	part: Part,
	store: OrderedDataStore?,
	stored: { Row }, -- the store's top rows, as last read
	shown: string, -- the rows as last published
}

local SHOW_EVERY = 5 -- s between looks at this server's players (no store is touched)
local MIN_BUDGET = 20 -- store requests kept spare: with fewer left, a write waits for the next turn

local boards: { Board } = {}
local names: { [number]: string } = {} -- user id: name, for players who aren't here
local written: { [number]: { [string]: number } } = {} -- user id: the numbers this server knows are in the stores
local titles: { [number]: string } = {}

local function statOf(profile: PlayerData.Profile, stat: string): number
	local value = profile.stats[stat]
	return if type(value) == "number" and value == value then math.max(math.floor(value), 0) else 0
end

-- The name the boards show for a user id (their display name while they're here, else their username).
local function nameOf(userId: number): string
	local here = Players:GetPlayerByUserId(userId)
	if here then
		return here.DisplayName
	end
	local known = names[userId]
	if known then
		return known
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		names[userId] = name
		return name
	end
	return "Player"
end

-- A board's rows right now: the store's top rows, with this server's players at their numbers as they are.
local function rowsOf(board: Board): { Row }
	local best: { [number]: Row } = {}
	for _, row in board.stored do
		best[row.id] = row
	end
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile then
			local value = statOf(profile, board.stat)
			local old = best[player.UserId]
			if value > 0 and (not old or value >= old.value) then
				best[player.UserId] = { id = player.UserId, name = player.DisplayName, value = value }
			end
		end
	end
	local rows: { Row } = {}
	for _, row in best do
		table.insert(rows, row)
	end
	table.sort(rows, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.id < b.id
	end)
	while #rows > B.SHOW do
		table.remove(rows)
	end
	return rows
end

-- Puts every board's rows on its part (only when they've changed), and hands out the #1 titles.
local function show()
	local newTitles: { [number]: string } = {}
	for _, board in boards do
		local rows = rowsOf(board)
		local list = {}
		for i, row in rows do
			list[i] = { n = row.name, v = row.value, u = row.id }
		end
		local ok, text = pcall(function()
			return HttpService:JSONEncode(list)
		end)
		if ok and text ~= board.shown then
			board.shown = text
			board.part:SetAttribute(ProgressRules.ATTR_BOARD_ROWS, text)
		end
		local top = rows[1]
		if top and not newTitles[top.id] then
			newTitles[top.id] = `#1 {board.short}`
		end
	end
	-- anyone here whose title came or went gets their name tag redone
	for _, player in Players:GetPlayers() do
		if titles[player.UserId] ~= newTitles[player.UserId] then
			titles[player.UserId] = newTitles[player.UserId]
			Progress.publish(player)
		end
	end
	titles = newTitles
end

local function budget(kind: Enum.DataStoreRequestType): number
	local ok, left = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return if ok and type(left) == "number" then left else 0
end

-- Raises a player's number on a board's store (never lowers it). Gives back whether the store has it now.
local function write(board: Board, userId: number, value: number): boolean
	local store = board.store
	if not store or userId <= 0 or value <= 0 then
		return true
	end
	if budget(Enum.DataStoreRequestType.UpdateAsync) < MIN_BUDGET then
		return false
	end
	local ok, problem = pcall(function()
		store:UpdateAsync(tostring(userId), function(old: any)
			local was = if type(old) == "number" then old else 0
			if value <= was then
				return nil -- it's there already (or more is)
			end
			return value
		end)
	end)
	if not ok then
		warn(`[{Config.GameName}] the {board.stat} board didn't take a number: {problem}`)
	end
	return ok
end

-- Reads a board's top rows from its store.
local function read(board: Board)
	local store = board.store
	if not store or budget(Enum.DataStoreRequestType.GetSortedAsync) < 2 then
		return
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, B.SHOW):GetCurrentPage()
	end)
	if not ok or type(page) ~= "table" then
		warn(`[{Config.GameName}] the {board.stat} board couldn't be read: {page}`)
		return
	end
	local rows: { Row } = {}
	for _, entry in page :: { any } do
		local id = tonumber(entry.key)
		if id and type(entry.value) == "number" and entry.value > 0 then
			table.insert(rows, { id = id, name = nameOf(id), value = entry.value })
		end
	end
	board.stored = rows
end

-- One board's turn: the numbers of everyone here that have gone up are written, then its top rows are read.
local function turn(board: Board)
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		local mine = written[player.UserId]
		if profile and mine then
			local value = statOf(profile, board.stat)
			if value > (mine[board.stat] or 0) and write(board, player.UserId, value) then
				mine[board.stat] = value
			end
		end
	end
	read(board)
end

local function build()
	local folder = Instance.new("Folder")
	folder.Name = ProgressRules.BOARDS
	local middle = A.CENTER + Vector3.new(0, L.HEIGHT, 0)
	for index, each in B.LIST do
		local angle = (index - 1) / #B.LIST * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = middle + out * B.RING + Vector3.new(0, B.LIFT + B.HEIGHT / 2, 0)
		local part = Instance.new("Part")
		part.Name = each.stat
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Size = Vector3.new(B.WIDTH, B.HEIGHT, 0.2)
		part.CFrame = CFrame.lookAt(position, position + out) -- its front looks out from the middle
		part.Material = Enum.Material.Glass
		part.Color = Color3.fromHex(each.color)
		part.Transparency = 0.8
		part:SetAttribute(ProgressRules.ATTR_BOARD_TITLE, each.name)
		part:SetAttribute(ProgressRules.ATTR_BOARD_COLOR, each.color)
		part:SetAttribute(ProgressRules.ATTR_BOARD_ROWS, "[]")
		part.Parent = folder
		local store: OrderedDataStore? = nil
		if PlayerData.isLive() then
			local ok, found = pcall(function()
				return DataStoreService:GetOrderedDataStore(B.STORE_PREFIX .. each.stat)
			end)
			if ok then
				store = found
			end
		end
		table.insert(boards, {
			stat = each.stat,
			short = each.short,
			part = part,
			store = store,
			stored = {},
			shown = "[]",
		})
	end
	folder.Parent = Workspace
end

function Leaderboards.start()
	build()
	Progress.setBoardTitles(function(userId: number): string?
		return titles[userId]
	end)

	PlayerData.onLoaded(function(player)
		written[player.UserId] = {}
	end)
	-- leaving: the last numbers go to the stores (a copy of them, as the save is let go of right after)
	PlayerData.onRelease(function(player, profile)
		local userId = player.UserId
		local mine = written[userId] or {}
		written[userId] = nil
		local last: { [string]: number } = {}
		for _, board in boards do
			last[board.stat] = statOf(profile, board.stat)
		end
		task.spawn(function()
			for _, board in boards do
				if last[board.stat] > (mine[board.stat] or 0) then
					write(board, userId, last[board.stat])
				end
			end
		end)
	end)

	task.spawn(function()
		local every = math.max(B.REFRESH / #boards, 6)
		local nextTurn = os.clock() + 3
		local index = 0
		while true do
			if os.clock() >= nextTurn then
				nextTurn = os.clock() + every
				index = index % #boards + 1
				local ok, problem = pcall(turn, boards[index])
				if not ok then
					warn(`[{Config.GameName}] a leaderboard's turn broke: {problem}`)
				end
			end
			local ok, problem = pcall(show)
			if not ok then
				warn(`[{Config.GameName}] the leaderboards couldn't be shown: {problem}`)
			end
			task.wait(SHOW_EVERY)
		end
	end)
end

return Leaderboards
