--!strict
-- Passes on where each player looks (HeadLook): their game sends the head's turn a few times a second, and this puts it
-- on their body (LookYaw, LookPitch, whole degrees) so every other screen can turn that head. Numbers are checked and
-- clamped, and a player can't send more than about 20 a second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local C = Config.Camera

local LookServer = {}

local lastAt: { [Player]: number } = {}

local function number(value: unknown, limit: number): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(math.floor(value + 0.5), -limit, limit)
end

function LookServer.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local found = remotes:FindFirstChild("Look")
	if not found then
		found = Instance.new("UnreliableRemoteEvent")
		found.Name = "Look"
		found.Parent = remotes
	end
	(found :: UnreliableRemoteEvent).OnServerEvent:Connect(function(player: Player, yaw: unknown, pitch: unknown)
		local now = os.clock()
		if now - (lastAt[player] or -math.huge) < 0.045 then
			return
		end
		lastAt[player] = now
		local y = number(yaw, C.HEAD_YAW_MAX)
		local p = number(pitch, C.HEAD_PITCH_MAX)
		local character = player.Character
		if y and p and character then
			character:SetAttribute("LookYaw", y)
			character:SetAttribute("LookPitch", p)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAt[player] = nil
	end)
end

return LookServer
