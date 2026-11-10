--!strict
-- Heads turn to where each player's camera looks (owner 2026-11-09: "i want the players head to turn wehre ever the
-- camera is facing, then the players body lags behind"). Your own head follows your camera at once, every frame,
-- within HEAD_YAW_MAX either side of your body and HEAD_PITCH_MAX up and down; the body catches up with its small lag
-- (CameraSteer). So everyone sees where you look, your game sends that to the server HEAD_SEND_RATE times a second
-- (LookServer puts it on your body) and every screen eases the other heads toward it.
-- The head is turned by the R6 neck joint's C0, on top of whatever the animations do.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local C = Config.Camera

local HeadLook = {}

local player = Players.LocalPlayer
local LookRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Look") :: UnreliableRemoteEvent

local ATTR_YAW = "LookYaw" -- on a body: degrees the head turns from the body (+ left), set by the server
local ATTR_PITCH = "LookPitch" -- degrees up (+) or down

type Neck = { joint: Motor6D, base: CFrame, yaw: number, pitch: number }
local necks: { [Model]: Neck } = {}
local lastSent = -math.huge
local sentYaw, sentPitch = 0, 0

local function neckOf(character: Model): Neck?
	local known = necks[character]
	if known and known.joint.Parent then
		return known
	end
	local torso = character:FindFirstChild("Torso")
	local joint = torso and torso:FindFirstChild("Neck")
	if not joint or not joint:IsA("Motor6D") then
		return nil
	end
	local neck = { joint = joint, base = joint.C0, yaw = 0, pitch = 0 }
	necks[character] = neck
	return neck
end

local function yawOf(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- Turns a head: `yaw` degrees from the body (+ left) and `pitch` degrees up.
local function pose(neck: Neck, yaw: number, pitch: number)
	neck.yaw, neck.pitch = yaw, pitch
	-- in the R6 neck's own frame the head turns round its Z axis and nods round its X axis
	neck.joint.C0 = neck.base * CFrame.Angles(math.rad(-pitch), 0, math.rad(yaw))
end

local function step(dt: number)
	-- your own head: straight to where the camera looks
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if camera and character and root then
		local neck = neckOf(character)
		if neck then
			local look = camera.CFrame.LookVector
			local yaw = math.deg(wrap(yawOf(look) - yawOf(root.CFrame.LookVector)))
			yaw = math.clamp(yaw, -C.HEAD_YAW_MAX, C.HEAD_YAW_MAX)
			local pitch = math.clamp(math.deg(math.asin(math.clamp(look.Y, -1, 1))), -C.HEAD_PITCH_MAX, C.HEAD_PITCH_MAX)
			pose(neck, yaw, pitch)
			local now = os.clock()
			local changed = math.abs(yaw - sentYaw) > 2 or math.abs(pitch - sentPitch) > 2
			if changed and now - lastSent >= 1 / C.HEAD_SEND_RATE then
				lastSent = now
				sentYaw, sentPitch = yaw, pitch
				LookRemote:FireServer(math.floor(yaw + 0.5), math.floor(pitch + 0.5))
			end
		end
	end
	-- everyone else's: eased toward what the server last said
	local ease = 1 - math.exp(-C.HEAD_EASE * dt)
	for _, other in Players:GetPlayers() do
		local body = other.Character
		if other ~= player and body then
			local neck = neckOf(body)
			local yaw = body:GetAttribute(ATTR_YAW)
			local pitch = body:GetAttribute(ATTR_PITCH)
			if neck and type(yaw) == "number" and type(pitch) == "number" then
				pose(neck, neck.yaw + (yaw - neck.yaw) * ease, neck.pitch + (pitch - neck.pitch) * ease)
			end
		end
	end
	for body in necks do
		if not body.Parent then
			necks[body] = nil
		end
	end
end

function HeadLook.start()
	-- after the camera and the body's turn, so the head matches this frame's view
	RunService:BindToRenderStep("TagRivalsHeadLook", Enum.RenderPriority.Camera.Value + 2, step)
end

return HeadLook
