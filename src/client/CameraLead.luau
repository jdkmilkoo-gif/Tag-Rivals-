--!strict
-- The camera looks a little ahead of where you're running (design notes, Camera: "leads a little ahead of where you're
-- moving (about 3.5 studs)"; owner 2026-11-09, Huss Valley's "predictive directional lead offset": sprint diagonally
-- left and the camera smoothly pans a few studs left, so you see more of what you're running into on the open circle).
-- Right after Roblox's camera moves each frame, the view slides along your flat running direction: LEAD studs at your
-- sprint speed, less when slower, easing into each change of direction. Only the view's position moves (never where it
-- looks), so the next frame's camera starts clean.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveController = require(script.Parent.MoveController)

local C = Config.Camera

local CameraLead = {}

local player = Players.LocalPlayer
local lead = Vector3.zero

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local target = Vector3.zero
	if root and MoveController.state.alive then
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = flat.Magnitude
		if speed > 1 then
			local share = math.clamp(speed / math.max(MoveController.state.sprintTop, 1), 0, 1)
			target = flat.Unit * C.LEAD * share
		end
	end
	lead += (target - lead) * (1 - math.exp(-C.LEAD_SPRING * dt))
	if camera and lead.Magnitude > 1e-3 then
		camera.CFrame += lead
	end
end

function CameraLead.start()
	RunService:BindToRenderStep("TagRivalsCameraLead", Enum.RenderPriority.Camera.Value + 1, step)
end

return CameraLead
