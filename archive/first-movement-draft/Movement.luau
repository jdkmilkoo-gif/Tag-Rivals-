-- Sprint, stamina and dash for the local player.
-- PC: hold Left Shift to sprint, Q to dash (shift lock stays on Right Shift).
-- Phone/tablet: Sprint button (tap to turn on/off) and Dash button.
-- Controller: click the left stick to sprint, X to dash.
-- The server can change a player's speed with the "SpeedMultiplier" attribute on their Player (1 = normal, 0 = frozen).
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Settings = Config.Movement
local player = Players.LocalPlayer

local SPRINT_ACTION = "TagRivalsSprint"
local DASH_ACTION = "TagRivalsDash"
-- Above the shift lock binding (Medium), so Left Shift sprints instead of toggling shift lock.
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value
local BUTTON_ON_COLOR = Color3.fromRGB(120, 255, 150)
local BUTTON_OFF_COLOR = Color3.new(1, 1, 1)

local Movement = {}

local stamina = Settings.MaxStamina
local exhausted = false
local wantsSprint = false
local sprintIsToggle = false -- touch and controller toggle sprint; the keyboard holds it
local sprinting = false
local lastSprintAt = 0
local dashReadyAt = 0
local dashEndsAt = 0

local humanoid = nil
local rootPart = nil
local sprintTrack = nil

local function speedMultiplier()
	local value = player:GetAttribute("SpeedMultiplier")
	if typeof(value) == "number" then
		return math.max(value, 0)
	end
	return 1
end

local function isAlive()
	return humanoid ~= nil
		and humanoid.Parent ~= nil
		and humanoid.Health > 0
		and rootPart ~= nil
		and rootPart.Parent ~= nil
end

local function isOnGround()
	local state = humanoid:GetState()
	return state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics
end

local function animationIdText(id)
	if typeof(id) == "number" and id > 0 then
		return `rbxassetid://{id}`
	elseif typeof(id) == "string" and id ~= "" and id ~= "0" then
		return if string.find(id, "^%d+$") then `rbxassetid://{id}` else id
	end
	return nil
end

local function updateSprintButton()
	local button = ContextActionService:GetButton(SPRINT_ACTION)
	if button then
		button.ImageColor3 = if wantsSprint and sprintIsToggle then BUTTON_ON_COLOR else BUTTON_OFF_COLOR
	end
end

local function stopSprintTrack()
	if sprintTrack and sprintTrack.IsPlaying then
		sprintTrack:Stop(0.2)
	end
end

local function loadSprintTrack()
	sprintTrack = nil
	local id = animationIdText(Settings.SprintAnimationId)
	if not id then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		warn(`[{Config.GameName}] The sprint animation is made for R6, but this character is not R6. Skipping it.`)
		return
	end
	local animator = humanoid:WaitForChild("Animator", 5)
	if not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok then
		result.Priority = Enum.AnimationPriority.Movement
		result.Looped = true
		sprintTrack = result
	else
		warn(`[{Config.GameName}] Could not load the sprint animation {id}: {result}`)
	end
end

local function dash()
	if not isAlive() then
		return
	end
	local now = os.clock()
	if now < dashReadyAt then
		return
	end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Seated or state == Enum.HumanoidStateType.Dead then
		return
	end
	local multiplier = speedMultiplier()
	if multiplier <= 0 then
		return
	end

	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = rootPart.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		return
	end
	direction = direction.Unit

	dashReadyAt = now + Settings.DashCooldown
	dashEndsAt = now + Settings.DashDuration

	local attachment = rootPart:FindFirstChild("RootAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "RootAttachment"
		attachment.Parent = rootPart
	end

	-- Pushes sideways only, so gravity still works during the dash.
	local push = Instance.new("LinearVelocity")
	push.Name = "TagRivalsDash"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Settings.DashSpeed * multiplier
	push.MaxForce = math.huge
	push.Parent = rootPart
	Debris:AddItem(push, Settings.DashDuration)
end

local function onSprintAction(_actionName, inputState, inputObject)
	if inputObject.UserInputType == Enum.UserInputType.Keyboard then
		sprintIsToggle = false
		wantsSprint = inputState == Enum.UserInputState.Begin
	elseif inputState == Enum.UserInputState.Begin then
		sprintIsToggle = true
		wantsSprint = not wantsSprint
	end
	updateSprintButton()
	return Enum.ContextActionResult.Sink
end

local function onDashAction(_actionName, inputState)
	if inputState == Enum.UserInputState.Begin then
		dash()
	end
	return Enum.ContextActionResult.Sink
end

local function onCharacterAdded(character)
	local newHumanoid = character:WaitForChild("Humanoid")
	local newRootPart = character:WaitForChild("HumanoidRootPart")
	if player.Character ~= character then
		return
	end
	stopSprintTrack()
	humanoid = newHumanoid
	rootPart = newRootPart
	stamina = Settings.MaxStamina
	exhausted = false
	sprinting = false
	dashReadyAt = 0
	dashEndsAt = 0
	humanoid.WalkSpeed = Settings.WalkSpeed * speedMultiplier()
	loadSprintTrack()
end

local function onCharacterRemoving()
	stopSprintTrack()
	humanoid = nil
	rootPart = nil
	sprintTrack = nil
end

local function step(dt)
	local now = os.clock()
	local alive = isAlive()
	local moving = alive and humanoid.MoveDirection.Magnitude > 0.1

	if exhausted and stamina >= Settings.MinStaminaToSprint then
		exhausted = false
	end
	sprinting = wantsSprint and moving and not exhausted and stamina > 0

	if sprinting then
		stamina = math.max(stamina - Settings.SprintDrainPerSecond * dt, 0)
		lastSprintAt = now
		if stamina <= 0 then
			exhausted = true
			if sprintIsToggle then
				wantsSprint = false
				updateSprintButton()
			end
		end
	elseif now - lastSprintAt >= Settings.RegenDelay then
		stamina = math.min(stamina + Settings.RegenPerSecond * dt, Settings.MaxStamina)
	end

	if alive then
		local speed = (if sprinting then Settings.SprintSpeed else Settings.WalkSpeed) * speedMultiplier()
		if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
			humanoid.WalkSpeed = speed
		end
		if sprintTrack then
			local shouldPlay = sprinting and isOnGround()
			if shouldPlay and not sprintTrack.IsPlaying then
				sprintTrack:Play(0.15, 1, Settings.SprintAnimationSpeed)
			elseif not shouldPlay and sprintTrack.IsPlaying then
				sprintTrack:Stop(0.2)
			end
		end
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local targetFov = Settings.BaseFov
		if now < dashEndsAt then
			targetFov = Settings.DashFov
		elseif sprinting then
			targetFov = Settings.SprintFov
		end
		local alpha = 1 - math.exp(-Settings.FovResponsiveness * dt)
		camera.FieldOfView += (targetFov - camera.FieldOfView) * alpha
	end
end

-- Read by the HUD every frame.
function Movement.GetState()
	return {
		Stamina = stamina,
		MaxStamina = Settings.MaxStamina,
		Exhausted = exhausted,
		Sprinting = sprinting,
		DashCooldownLeft = math.max(dashReadyAt - os.clock(), 0),
		DashCooldown = Settings.DashCooldown,
	}
end

function Movement.Start()
	ContextActionService:BindActionAtPriority(
		SPRINT_ACTION,
		onSprintAction,
		true,
		ACTION_PRIORITY,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:BindActionAtPriority(
		DASH_ACTION,
		onDashAction,
		true,
		ACTION_PRIORITY,
		Enum.KeyCode.Q,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:SetTitle(SPRINT_ACTION, "Sprint")
	ContextActionService:SetTitle(DASH_ACTION, "Dash")

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(onCharacterRemoving)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	RunService.RenderStepped:Connect(step)
end

return Movement
