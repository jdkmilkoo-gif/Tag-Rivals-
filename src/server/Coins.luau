--!strict
-- The coins on the arena (design notes, Coins and economy: the "Stars"; owner 2026-11-09: "now implement coins as a
-- pickup in the rounds"), the server's side. It only keeps a short list of spots; every screen draws the coins and
-- their effects itself (CoinFx), so nothing heavy crosses the network (owner: "make sure it doesnt lag the game at
-- all").
--   * During the match coins come in over time (owner: "should spawn over time"): the first FIRST s after GO!, then one
--     every EVERY s while fewer than CoinRules.maxAlive are on the map. Most land near the dangerous middle, never on
--     a strip that's about to be cut off, away from other coins and bodies.
--   * Touching one gives +2 coins (RoundCoins) and +1 to the speed stack (Stars: +0.2 top speed each, at most +10).
--     Your own screen says when you touch one, so it's instant; the server checks you really were near it. The server
--     also checks every body itself (Studio bots, and anyone whose word didn't arrive).
--   * A tagged runner loses their whole stack (owner); coins already picked up stay theirs.
--   * A cut drops the coins on the strip that went; the match's end clears the rest.
-- A coin picked up is the player's for good at once (Progress: their saved coins, a little XP, quests).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CoinRules = require(ReplicatedStorage.Shared.CoinRules)
local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Arena = require(script.Parent.Arena)
local History = require(script.Parent.History)
local Progress = require(script.Parent.Progress)

local C = Config.Coins

local Coins = {}

type Coin = { spot: Vector3, born: number }

local ROOT_HEIGHT = 3 -- studs from the floor's top to an R6 body's middle
local TICK = 0.1 -- s between the server's own checks
local CLAIMS_PER_SECOND = 12 -- a player's screen can't ask for more than this

local remote: RemoteEvent = nil :: any
local folder: Folder = nil :: any
local alive: { [number]: Coin } = {}
local count = 0
local nextId = 0
local running = false
local cap = C.ALIVE_BASE
local nextSpawnAt = math.huge
local rng = Random.new()
local claims: { [Player]: { at: number, n: number } } = {}

local function number(value: unknown): number
	return if type(value) == "number" then value else 0
end

local function bodiesInRound(): { { who: Instance, root: BasePart } }
	local list = {}
	local function add(who: Instance)
		if who:GetAttribute(RoundRules.ATTR_IN_ROUND) == true and who:GetAttribute(MoveRules.ATTR_FROZEN) ~= true then
			local root = History.rootOf(who)
			if root then
				table.insert(list, { who = who, root = root })
			end
		end
	end
	for _, player in Players:GetPlayers() do
		add(player)
	end
	local bots = Workspace:FindFirstChild("TagBots")
	if bots then
		for _, bot in bots:GetChildren() do
			if bot:IsA("Model") then
				add(bot)
			end
		end
	end
	return list
end

local function remove(id: number)
	if alive[id] then
		alive[id] = nil
		count -= 1
		folder:SetAttribute(CoinRules.key(id), nil)
	end
end

-- `who` picked coin `id` up: +2 coins and one more on the speed stack, and every screen hears it.
local function award(id: number, who: Instance)
	local coin = alive[id]
	if not coin then
		return
	end
	who:SetAttribute(MoveRules.ATTR_STARS, number(who:GetAttribute(MoveRules.ATTR_STARS)) + 1)
	who:SetAttribute(CoinRules.ATTR_ROUND_COINS, number(who:GetAttribute(CoinRules.ATTR_ROUND_COINS)) + C.VALUE)
	-- the word first, then the coin goes from the list (screens draw the pick-up rather than a plain vanish)
	remote:FireAllClients("take", id, who, coin.spot)
	remove(id)
	-- theirs for good (a bot is quietly ignored); the coin's own pop on screen already shows the +2
	Progress.addCoins(who, C.VALUE, "STAR", true)
	Progress.addXp(who, Config.Rewards.XP_STAR)
	Progress.addStat(who, "stars", 1)
	Progress.event(who, "star")
end

local function spawnOne()
	local center = Arena.center()
	local half = Arena.targetDiameter() / 2
	local safe = CoinRules.safeHalf(half, number(Workspace:GetAttribute(RoundRules.ATTR_CUT_RADIUS)))
	local taken: { Vector3 } = {}
	for _, coin in alive do
		table.insert(taken, coin.spot)
	end
	local bodies: { Vector3 } = {}
	for _, body in bodiesInRound() do
		table.insert(bodies, body.root.Position)
	end
	local spot = CoinRules.pickSpot(center, safe, taken, bodies, function()
		return rng:NextNumber()
	end)
	if not spot then
		return
	end
	nextId += 1
	alive[nextId] = { spot = spot, born = os.clock() }
	count += 1
	folder:SetAttribute(CoinRules.key(nextId), spot)
end

-- The server's own look: anyone in the round touching a coin (bots, and players whose screen didn't say).
local function sweep()
	if count == 0 then
		return
	end
	for _, body in bodiesInRound() do
		local position = body.root.Position
		for id, coin in alive do
			if
				CoinRules.flatDistance(position, coin.spot) <= C.RADIUS
				and math.abs(position.Y - (coin.spot.Y + ROOT_HEIGHT)) < 6
			then
				award(id, body.who)
			end
		end
	end
end

-- A player's screen says they touched coin `id`: it counts if the round is on, they're in it, and they really were near
-- it a moment ago (the server sees bodies a little late).
local function onClaim(player: Player, action: unknown, id: unknown)
	if action ~= "take" or type(id) ~= "number" or not running then
		return
	end
	local now = os.clock()
	local rate = claims[player]
	if not rate or now - rate.at > 1 then
		rate = { at = now, n = 0 }
		claims[player] = rate
	end
	rate.n += 1
	if rate.n > CLAIMS_PER_SECOND then
		return
	end
	local coin = alive[id]
	if not coin then
		return
	end
	if
		player:GetAttribute(RoundRules.ATTR_IN_ROUND) ~= true
		or player:GetAttribute(MoveRules.ATTR_FROZEN) == true
		or Workspace:GetAttribute(RoundRules.ATTR_STATE) ~= "Match"
	then
		return
	end
	local point = coin.spot + Vector3.new(0, ROOT_HEIGHT, 0)
	local gap = History.recentDistance(player, point, C.CLAIM_REWIND)
	if gap > C.RADIUS + C.CLAIM_SLACK then
		-- History may not have this body yet: its body now, with the same slack
		local root = History.rootOf(player)
		if not root or (root.Position - point).Magnitude > C.RADIUS + C.CLAIM_SLACK then
			return
		end
	end
	award(id, player)
end

-- The match started (Round): coins start coming in. `players` is how many are in the round.
function Coins.beginMatch(players: number)
	Coins.clear()
	running = true
	cap = CoinRules.maxAlive(players)
	nextSpawnAt = os.clock() + C.FIRST
end

-- The match is over (Round): no more coins, and the ones left go.
function Coins.endMatch()
	running = false
	nextSpawnAt = math.huge
	Coins.clear()
end

-- Every coin goes (screens let them pop away).
function Coins.clear()
	if count > 0 then
		remote:FireAllClients("clear")
	end
	for id in alive do
		remove(id)
	end
	table.clear(alive)
	count = 0
end

-- A cut (Round): the coins on the strip that went fall with it. `half` is the square's half-side after the cut.
function Coins.cut(half: number)
	local center = Arena.center()
	local fell: { number } = {}
	for id, coin in alive do
		if CoinRules.outside(coin.spot, center, half - 0.5) then
			table.insert(fell, id)
		end
	end
	if #fell > 0 then
		remote:FireAllClients("drop", fell)
		for _, id in fell do
			remove(id)
		end
	end
end

-- A new round for `who`: no coins yet and no speed stack.
function Coins.resetFor(who: Instance)
	who:SetAttribute(MoveRules.ATTR_STARS, 0)
	who:SetAttribute(CoinRules.ATTR_ROUND_COINS, 0)
end

-- `who` was tagged (or left the round): the speed stack goes (owner: "a runner who gets tagged loses their whole stack
-- and starts again at zero as a chaser"). The coins they picked up stay theirs.
function Coins.loseStack(who: Instance)
	who:SetAttribute(MoveRules.ATTR_STARS, 0)
end

-- Shares the coin's 3D model with every screen: the copy in ServerStorage.Pickups.Coin, else the uploaded model.
local function shareModel()
	local model: Instance? = nil
	local pickups = ServerStorage:FindFirstChild("Pickups")
	local stored = pickups and pickups:FindFirstChild("Coin")
	if stored then
		model = stored:Clone()
	else
		local ok, loaded = pcall(function()
			return game:GetService("InsertService"):LoadAsset(C.MODEL_ID)
		end)
		if ok and loaded then
			model = loaded:FindFirstChildWhichIsA("Model") or loaded
		else
			warn(`[{Config.GameName}] the coin's model didn't load ({loaded}); screens draw a plain coin`)
		end
	end
	if model then
		local link = model:FindFirstChildWhichIsA("PackageLink", true)
		if link then
			link:Destroy()
		end
		model.Name = CoinRules.MODEL
		model.Parent = ReplicatedStorage
	end
end

function Coins.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local found = remotes:FindFirstChild(CoinRules.REMOTE)
	if not found then
		found = Instance.new("RemoteEvent")
		found.Name = CoinRules.REMOTE
		found.Parent = remotes
	end
	remote = found :: RemoteEvent
	local made = Instance.new("Folder")
	made.Name = CoinRules.FOLDER
	made.Parent = ReplicatedStorage
	folder = made
	task.spawn(shareModel)

	remote.OnServerEvent:Connect(onClaim)
	Players.PlayerRemoving:Connect(function(player)
		claims[player] = nil
	end)

	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < TICK then
			return
		end
		since = 0
		if not running then
			return
		end
		local now = os.clock()
		if now >= nextSpawnAt then
			nextSpawnAt = now + C.EVERY
			if count < cap then
				spawnOne()
			end
		end
		sweep()
	end)
end

return Coins
