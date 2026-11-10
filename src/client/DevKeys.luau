--!strict
-- Test keys for trying the movement in Studio before rounds exist (Studio only; the server ignores them in a live game):
--   1 Runner, 2 Chaser, 3 Last runner (the speeds by role)
--   T fake a tag (everyone gets the tag speed-up), Y +5 stars, 0 back to the start
--   U pretend to be on a phone (sprint always on, the Dash button shows)
--   N skip ahead in the round (end the intermission now, or end the match now)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local InputMode = require(script.Parent.InputMode)

local DevRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Dev") :: RemoteEvent

local DevKeys = {}

local ACTIONS: { [Enum.KeyCode]: { string } } = {
	[Enum.KeyCode.One] = { "role", "Runner" },
	[Enum.KeyCode.Two] = { "role", "Chaser" },
	[Enum.KeyCode.Three] = { "role", "LastRunner" },
	[Enum.KeyCode.T] = { "tag" },
	[Enum.KeyCode.Y] = { "stars" },
	[Enum.KeyCode.Zero] = { "reset" },
	[Enum.KeyCode.N] = { "skip" },
}

function DevKeys.start()
	if not RunService:IsStudio() then
		return
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.U then
			InputMode.setForced(not InputMode.isForced())
			print(`[{Config.GameName}] phone mode {if InputMode.isForced() then "on" else "off"}`)
			return
		end
		local action = ACTIONS[input.KeyCode]
		if action then
			DevRemote:FireServer(action[1], action[2])
		end
	end)
	print(`[{Config.GameName}] Studio test keys: 1 Runner, 2 Chaser, 3 Last runner, T fake a tag, Y +5 stars, 0 reset, U phone mode, N skip ahead in the round`)
end

return DevKeys
