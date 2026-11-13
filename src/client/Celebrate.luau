--!strict
-- The end of a match (design notes, Victory screen): while everyone is held still, the winning side cheers or dances
-- and the rest slump. Each player's own game plays it on their own body (Roblox shows it to everyone); the bots do
-- the same on the server (BotAnim). It stops when the round sends everyone back to the lobby. Roblox's own R6 emotes
-- (Config.Celebrate).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)

local E = Config.Celebrate

local Celebrate = {}

local player = Players.LocalPlayer
local playing: AnimationTrack? = nil

local function stop()
	local track = playing
	if track then
		playing = nil
		track:Stop(0.25)
		track:Destroy()
	end
end

local function play(id: string)
	stop()
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	if not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action3
		track.Looped = true
		track:Play(0.25)
		playing = track
	end
end

function Celebrate.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: unknown, result: any)
		if kind ~= "victory" or type(result) ~= "table" or result.winner == "None" then
			return
		end
		if player:GetAttribute(RoundRules.ATTR_IN_ROUND) ~= true then
			return
		end
		local chaser = MoveRules.role(player:GetAttribute(MoveRules.ATTR_ROLE)) == "Chaser"
		if chaser == (result.winner == "Chasers") then
			play(if math.random() < 0.5 then E.CHEER else E.DANCE[math.random(1, #E.DANCE)])
		else
			play(E.SLUMP)
		end
	end)
	-- back to the lobby (or a new body): it's over
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= 0.2 then
			since = 0
			if playing and Workspace:GetAttribute(RoundRules.ATTR_STATE) ~= "Cleanup" then
				stop()
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		playing = nil
	end)
end

return Celebrate
