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
local Round = require(script.Round)
local Spawner = require(script.Spawner)
local Tagging = require(script.Tagging)

ChronoSetup.start()
Arena.build()
Lobby.build()
MoveServer.start(Spawner.respawn)
LookServer.start()

local studioBots = DevBots.start(function(chaser, runner, dash)
	return Round.tag(chaser, runner, dash)
end, Round.slashed, Tagging.perfectDodge)
local function botFolder()
	return DevBots.folder()
end

History.start(botFolder)
Tagging.start(botFolder)
Coins.start()
Round.start(Spawner.respawn, if studioBots then DevBots else nil)
Spawner.start(Round.spotFor, function(player, character)
	MoveServer.prepareCharacter(player, character)
	Round.prepareCharacter(player, character)
end)

print(`[{Config.GameName}] server scripts loaded (synced by Rojo)`)
