--!strict
-- Codes (owner 2026-11-13: "add a codes system"): a player types a code into the CODES box and gets its coins, once.
-- The codes and what they pay are in Config.Codes.LIST (add a line there for a new one). Each player's used codes are
-- kept on their save, so a code can't be used twice, on any server. The box on the screen (CodesPanel) only sends the
-- text; everything is decided here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)
local Progress = require(script.Parent.Progress)

local C = Config.Codes

local Codes = {}

local lastTry: { [Player]: number } = {}

-- Has a code with this `expires` date ("2026-12-31") run out? It works through the end of that day (UTC).
local function expired(expires: unknown): boolean
	if type(expires) ~= "string" then
		return false
	end
	local year, month, day = string.match(expires, "^(%d+)-(%d+)-(%d+)$")
	if not year then
		return false
	end
	local today = os.date("!*t") :: any
	local now = today.year * 10000 + today.month * 100 + today.day
	local last = (tonumber(year) :: number) * 10000 + (tonumber(month) :: number) * 100 + (tonumber(day) :: number)
	return now > last
end

-- The text a player typed, as a code: capitals, and only letters and numbers.
local function tidy(text: string): string
	local code = string.upper(string.sub(text, 1, C.MAX_LENGTH * 2))
	code = string.gsub(code, "[^A-Z0-9]", "")
	return string.sub(code, 1, C.MAX_LENGTH)
end

local function onCode(player: Player, text: unknown)
	local profile = PlayerData.get(player)
	if not profile or type(text) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastTry[player] or -math.huge) < C.COOLDOWN then
		Progress.send(player, "code", false, "Slow down a moment")
		return
	end
	lastTry[player] = now
	local code = tidy(text)
	local entry = (C.LIST :: any)[code]
	if code == "" or type(entry) ~= "table" then
		Progress.send(player, "code", false, "That code doesn't exist")
		return
	end
	if expired(entry.expires) then
		Progress.send(player, "code", false, "That code has run out")
		return
	end
	if profile.codes[code] then
		Progress.send(player, "code", false, "You've already used that code")
		return
	end
	profile.codes[code] = true
	local coins = if type(entry.coins) == "number" then math.floor(entry.coins) else 0
	if coins > 0 then
		Progress.addCoins(player, coins, "CODE")
	end
	Progress.send(player, "code", true, `+{coins} coins!`)
end

function Codes.start()
	Progress.onClient("code", onCode)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
	end)
end

return Codes
