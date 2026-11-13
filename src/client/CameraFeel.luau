--!strict
-- How the camera feels at speed (design notes, Camera): the view widens with your speed (70 standing, about 85
-- sprinting, a little more as the speed bonuses stack), a dash punches it out to about 103 for a moment and eases
-- back, and a sideways dash tilts the view 2-3 degrees the other way. On every step the view shakes a little (owner
-- 2026-11-09: "on every step the camers sublty shakes"): a quick dip and a tiny roll toward the foot that landed,
-- stronger the faster you go (CharacterAnim.onStep). Roblox's own camera still does the following; this runs right
-- after it each frame. In a dash the view also falls a couple of studs behind you and springs back
-- (Config.DashLag; design notes, Camera: "lags a few studs during a dash, then springs back").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local CharacterAnim = require(script.Parent.CharacterAnim)
local MoveController = require(script.Parent.MoveController)

local C = Config.Camera
local G = Config.DashLag

local CameraFeel = {}

local baseFov = C.FOV_STAND
local dashSide = 0 -- -1 the dash went left on screen, 1 right, 0 straight
local dashWay = Vector3.zero -- the flat way the newest dash went
local stepAt = -math.huge
local stepStrength = 0
local stepSide = 1

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The view's width for a flat speed, before any dash.
local function fovForSpeed(speed: number, walkTop: number, sprintTop: number): number
	if speed <= walkTop then
		return C.FOV_STAND + (C.FOV_WALK - C.FOV_STAND) * math.clamp(speed / math.max(walkTop, 1), 0, 1)
	elseif speed <= sprintTop then
		local share = (speed - walkTop) / math.max(sprintTop - walkTop, 1)
		return C.FOV_WALK + (C.FOV_SPRINT - C.FOV_WALK) * share
	end
	return math.min(C.FOV_SPRINT + (speed - sprintTop) * 0.5, C.FOV_FAST_MAX)
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local state = MoveController.state
	-- in a dash, the speed-based part stays at a sprint; the punch below does the rest
	local speed = if state.dashing then state.sprintTop else state.speed
	local target = fovForSpeed(speed, state.walkTop, state.sprintTop)
	baseFov += (target - baseFov) * (1 - math.exp(-C.FOV_SPRING * dt))

	local age = os.clock() - state.dashAt
	local punch = 0
	if age >= 0 and age < C.DASH_FOV_RISE + C.DASH_FOV_BACK then
		if age < C.DASH_FOV_RISE then
			punch = C.DASH_FOV * smooth(age / C.DASH_FOV_RISE)
		else
			punch = C.DASH_FOV * (1 - smooth((age - C.DASH_FOV_RISE) / C.DASH_FOV_BACK))
		end
	end
	camera.FieldOfView = math.clamp(baseFov + punch, 1, 120)

	if age >= 0 and age < C.DASH_ROLL_BACK and dashSide ~= 0 then
		local rise = math.clamp(age / 0.04, 0, 1)
		local roll = -dashSide * C.DASH_ROLL * rise * (1 - smooth(age / C.DASH_ROLL_BACK))
		camera.CFrame *= CFrame.Angles(0, 0, math.rad(roll))
	end

	-- the dash lag: the view falls behind along the dash, then springs back to you
	if age >= 0 and age < G.RISE + G.BACK and dashWay.Magnitude > 0.5 then
		local behind = if age < G.RISE
			then smooth(age / G.RISE)
			else 1 - smooth((age - G.RISE) / G.BACK)
		camera.CFrame -= dashWay * (G.STUDS * behind)
	end

	-- the step shake: down and back up over STEP_TIME, rolling a touch toward the foot that landed
	local stepAge = os.clock() - stepAt
	if stepAge >= 0 and stepAge < C.STEP_TIME then
		local bump = math.sin(math.pi * stepAge / C.STEP_TIME) * stepStrength
		camera.CFrame *= CFrame.new(0, -C.STEP_DIP * bump, 0) * CFrame.Angles(0, 0, math.rad(C.STEP_ROLL * bump * stepSide))
	end
end

function CameraFeel.start()
	MoveController.onDash(function(direction: Vector3)
		local flat = Vector3.new(direction.X, 0, direction.Z)
		dashWay = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
		local camera = Workspace.CurrentCamera
		if not camera then
			dashSide = 0
			return
		end
		local right = camera.CFrame.RightVector
		local sideways = Vector3.new(right.X, 0, right.Z).Unit:Dot(direction)
		dashSide = if sideways > 0.5 then 1 elseif sideways < -0.5 then -1 else 0
	end)
	CharacterAnim.onStep(function(strength: number, side: number)
		stepAt = os.clock()
		stepStrength = strength
		stepSide = side
	end)
	RunService:BindToRenderStep("TagRivalsCameraFeel", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraFeel
