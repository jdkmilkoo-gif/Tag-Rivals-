--!strict
-- Steering with the camera in a round, Huss Valley style (owner 2026-11-09: "the camera like a flashlight attached to
-- your chest": wherever you point it is the only way you run forward). On every device, while you're playing a round:
--   * only you turn the camera (the mouse, the right stick, dragging on a phone); moving never turns it. It sits over
--     your right shoulder (SHOULDER_OFFSET, in the camera's own frame; owner: "give it an offset like the over the
--     shoulder"), sliding over as the round starts and back as it ends;
--   * the keys move you relative to the camera: W into the screen, S back, A and D sideways. Your running direction
--     follows the camera with a small elastic lag (owner: "not instantly, its like some small elastic lag"), so holding
--     W and panning the camera runs you round a smooth arc, and a fast flick drifts a little, like a turn on ice;
--   * your body turns after the camera with the same kind of lag: standing still, it spins on the spot to face the new
--     way; running forward it faces where you run; sideways it turns only partly toward where you run (SIDE_TWIST,
--     owner: "the visual body turn shouldnt be completely because it would look unnatural"); backwards it keeps facing
--     forward (a little twist on the back diagonals) and you can't sprint (MoveController);
--   * your head turns at once to where the camera looks (HeadLook);
--   * PC: the mouse is held in the middle of the screen and hidden.
-- On the lobby it's Roblox's ordinary free camera (owner: "in the lobby just keep it free camera"): the mouse is free,
-- right-drag turns the camera, and your body turns the way you walk.
-- Roblox's own turning (AutoRotate) is off while this steers. Roblox's shift lock isn't used.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local InputMode = require(script.Parent.InputMode)
local MoveController = require(script.Parent.MoveController)

local C = Config.Camera

local CameraSteer = {}

local player = Players.LocalPlayer

local mouseHeld = false -- the mouse is held in the middle right now
local steering = false -- we're turning the body (Roblox's own turning is off)
local bodyYaw: number? = nil -- the way the body faces (eases toward its target)
local steerDir = Vector3.zero -- the way you run (eases toward the way the keys and camera ask)
local shoulder = 0 -- the shoulder offset now, eased toward SHOULDER_OFFSET or 0

-- Are we steering: playing in a round (not on the lobby)?
function CameraSteer.active(): boolean
	return player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
end

-- A flat direction's turn: 0 looking down -Z, positive turning left.
local function yawOf(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function humanoidAndRoot(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and humanoid.Health > 0 and root then
		return humanoid, root
	end
	return nil, nil
end

-- The keys or stick you're holding, in the camera's frame (x right, z back: W is (0, 0, -1)). Roblox's controls turn
-- them into the Humanoid's MoveDirection just before this runs each frame (camera-relative), so it's read from there.
local function moveInput(humanoid: Humanoid, cameraYaw: number): Vector3
	local direction = humanoid.MoveDirection
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.05 then
		return Vector3.zero
	end
	return CFrame.Angles(0, cameraYaw, 0):VectorToObjectSpace(flat)
end

-- How far (degrees, + to the right) the body turns from the camera's way for this input.
local function twistFor(input: Vector3): number
	if input.Magnitude < 0.05 then
		return 0
	end
	local angle = math.deg(math.atan2(input.X, -input.Z)) -- 0 forward, 90 right, -90 left, 180 back
	if math.abs(angle) <= 90 then
		-- forward and sideways: toward where you run, never more than SIDE_TWIST
		return math.clamp(angle, -C.SIDE_TWIST, C.SIDE_TWIST)
	end
	-- backwards: facing forward, the back diagonals twist a little so you back away into them
	local fromBack = angle - (if angle > 0 then 180 else -180)
	return math.clamp(fromBack, -C.BACK_TWIST, C.BACK_TWIST)
end

-- Gives the body back to Roblox's own turning (on the lobby, or without a body).
local function stopSteering(humanoid: Humanoid?)
	if steering then
		steering = false
		if humanoid then
			humanoid.AutoRotate = true
		end
	end
	bodyYaw = nil
	steerDir = Vector3.zero
end

-- After Roblox's controls and our speed (MoveController): the way you run and the way your body faces.
local function steer(dt: number)
	local camera = Workspace.CurrentCamera
	local humanoid, root = humanoidAndRoot()
	if not camera or not humanoid or not root or not CameraSteer.active() then
		stopSteering(humanoid)
		return
	end
	steering = true
	if humanoid.AutoRotate then
		humanoid.AutoRotate = false
	end
	local look = camera.CFrame.LookVector
	if Vector3.new(look.X, 0, look.Z).Magnitude < 1e-3 then
		return
	end
	local cameraYaw = yawOf(look)
	local input = moveInput(humanoid, cameraYaw)

	-- the way you run: the camera-relative way you ask, followed with a small lag
	local desired = Vector3.zero
	if input.Magnitude > 0.05 then
		desired = CFrame.Angles(0, cameraYaw, 0):VectorToWorldSpace(input)
		if desired.Magnitude > 1 then
			desired = desired.Unit
		end
	end
	if desired.Magnitude < 0.05 then
		steerDir = Vector3.zero
	elseif steerDir.Magnitude < 0.05 then
		steerDir = desired -- starting off: straight away, no lag
	else
		steerDir = steerDir:Lerp(desired, 1 - math.exp(-C.STEER_FOLLOW * dt))
	end
	if not MoveController.state.dashing then -- a dash holds its own way (MoveController)
		humanoid:Move(steerDir, false)
	end

	-- the way your body faces: after the camera (twisted by how you move), with a small lag
	local target = cameraYaw - math.rad(twistFor(input))
	local current = bodyYaw or yawOf(root.CFrame.LookVector)
	current += wrap(target - current) * (1 - math.exp(-C.BODY_FOLLOW * dt))
	bodyYaw = current
	local position = root.Position
	root.CFrame = CFrame.new(position) * CFrame.Angles(0, current, 0)
end

-- The mouse: held in the middle and hidden on a PC while steering; free otherwise.
local function holdMouse(on: boolean)
	if on then
		mouseHeld = true
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	elseif mouseHeld then
		mouseHeld = false
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		UserInputService.MouseIconEnabled = true
	end
end

local function mouseShouldBeHeld(): boolean
	return InputMode.get() == "Keyboard" and CameraSteer.active()
end

-- The way your body faces now (nil while not steering).
function CameraSteer.bodyYaw(): number?
	return bodyYaw
end

function CameraSteer.start()
	-- an older version of the lock used Roblox's camera-relative turning; this turns the body instead
	local settings = UserSettings():GetService("UserGameSettings")
	if settings.RotationType ~= Enum.RotationType.MovementRelative then
		settings.RotationType = Enum.RotationType.MovementRelative
	end

	RunService:BindToRenderStep("TagRivalsSteer", Enum.RenderPriority.Input.Value + 2, steer)
	-- the mouse, before the camera (so it turns with it this frame) and after it (in case the camera scripts let go)
	RunService:BindToRenderStep("TagRivalsCameraSteer", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
		holdMouse(mouseShouldBeHeld())
		local target = if CameraSteer.active() then C.SHOULDER_OFFSET else 0
		shoulder += (target - shoulder) * (1 - math.exp(-C.SHOULDER_EASE * dt))
		if math.abs(shoulder) < 1e-3 and target == 0 then
			shoulder = 0
		end
	end)
	-- right after the camera: over the shoulder (in the camera's own frame), and the mouse again
	RunService:BindToRenderStep("TagRivalsCameraSteerAfter", Enum.RenderPriority.Camera.Value + 1, function()
		if shoulder ~= 0 then
			local camera = Workspace.CurrentCamera
			if camera then
				camera.CFrame *= CFrame.new(shoulder, 0, 0)
			end
		end
		holdMouse(mouseShouldBeHeld())
	end)
end

return CameraSteer
