-- Tag Rivals server entry point. Server systems get started from here as they are built.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ChronoSetup = require(ReplicatedStorage.Shared.ChronoSetup)
local Coins = require(script.Coins)
local Arena = require(script.Arena)
local DevBots = require(script.DevBots)
local History = require(script.History)
local LookServer = require(script.LookServer)
local Lobby = require(script.Lobby)
local MoveServer = require(script.MoveServer)
local PlayerData = require(script.PlayerData)
local Progress = require(script.Progress)
local Round = require(script.Round)
local Spawner = require(script.Spawner)
local Tagging = require(script.Tagging)

-- Starts one of the systems round the round (saving, quests, the lobby's extras). A problem in one of them is said in
-- the output and must never stop the round itself from running.
local function begin(name: string, start: (...any) -> ...any, ...: any)
	local ok, problem = pcall(start, ...)
	if not ok then
		warn(`[{Config.GameName}] {name} didn't start: {problem}`)
	end
end

-- The same for a system the round doesn't need at all, by its name here: it's only loaded now, so even a mistake in
-- its own file can't stop the server.
local function beginExtra(name: string, ...: any)
	local module = script:FindFirstChild(name)
	begin(name, function(...: any)
		if not module or not module:IsA("ModuleScript") then
			error("it isn't there")
		end
		local loaded = (require :: any)(module)
		loaded.start(...)
	end, ...)
end

ChronoSetup.start()
Arena.build()
Lobby.build()
-- coins, XP and levels: before anything that pays (the round's rewards, the coins on the map, quests, codes)
begin("progress", Progress.start)
beginExtra("Quests")
beginExtra("Codes")
MoveServer.start(Spawner.respawn)
LookServer.start()

-- bots: the tester's in Studio, the fill-in bots in a quiet live server
local haveBots = DevBots.start(function(chaser, runner, dash)
	return Round.tag(chaser, runner, dash)
end, Round.slashed, Tagging.perfectDodge)
local function botFolder()
	return DevBots.folder()
end

History.start(botFolder)
Tagging.start(botFolder)
Coins.start()
Round.start(Spawner.respawn, if haveBots then DevBots else nil)
Spawner.start(Round.spotFor, function(player, character)
	MoveServer.prepareCharacter(player, character)
	Round.prepareCharacter(player, character)
end)
beginExtra("Leaderboards")
beginExtra("LobbyExtras", Spawner.descriptionOf)
-- saves last: everything above is listening by the time the first one loads
begin("saving", PlayerData.start)

print(`[{Config.GameName}] server scripts loaded (synced by Rojo)`)
