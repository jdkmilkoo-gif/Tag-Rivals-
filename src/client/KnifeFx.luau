--!strict
-- The knife's own effects, drawn on this screen only (the knife spec; owner 2026-11-10: the knife showed no effects,
-- "Epic VFX big and clearly visible"):
--   * held: while a chaser holds their knife and isn't swinging, its idle effects run (Bloomblade: a violet aura,
--     rising energy flames, pink petals, blossoms, wisps and twinkles) and the blade's light pulses on a 2.6 s beat.
--     On a runner's back they're all off; knives further than Config.Knife.IDLE_RANGE from the camera keep them off;
--   * the swing (a slash or a stab, every chaser's, bots too): the blade's trail and its swing effects (Bloomblade:
--     petals shed off the blade, sparks, a glowing smear) run for the swing, and the idle effects pause till it's done.
--     A knife further than IDLE_RANGE away swings with its trail only.
-- Every knife model carries its own effects, made in Studio on its FX_Blade part (Bloomblade's by
-- uploads/knives/make_bloomblade_fx.luau): emitters with the attribute KnifeFx = "Idle" or "Swing", all off in the
-- model. This only turns them on and off. Knives.luau gives every knife its trail and light.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local K = Config.Knife

local KnifeFx = {}

local KNIFE_NAME = "Knife" -- the knife's name inside a body (Knives.MODEL_NAME)

type Fx = {
	idle: { ParticleEmitter },
	swing: { ParticleEmitter },
	trail: Trail?,
	light: PointLight?,
	idleOn: boolean?, -- nil until first set, so the first look always sets the emitters
	swingStamp: number,
	swingUntil: number, -- os.clock() the idle effects may come back
}

local known: { [Model]: Fx } = setmetatable({}, { __mode = "k" }) :: any

local function setAll(list: { ParticleEmitter }, on: boolean)
	for _, each in list do
		each.Enabled = on
	end
end

-- A knife's effects (looked up once per knife).
local function fxOf(knife: Model): Fx
	local found = known[knife]
	if found then
		return found
	end
	local fx: Fx = {
		idle = {},
		swing = {},
		trail = nil,
		light = nil,
		idleOn = nil,
		swingStamp = 0,
		swingUntil = -math.huge,
	}
	for _, each in knife:GetDescendants() do
		if each:IsA("ParticleEmitter") then
			local kind = each:GetAttribute("KnifeFx")
			if kind == "Idle" then
				table.insert(fx.idle, each)
			elseif kind == "Swing" then
				table.insert(fx.swing, each)
			end
		elseif each:IsA("Trail") and each.Name == "SlashTrail" then
			fx.trail = each
		elseif each:IsA("PointLight") and each.Name == "BladeLight" then
			fx.light = each
		end
	end
	known[knife] = fx
	return fx
end

local function knifeOf(body: Model): Model?
	local knife = body:FindFirstChild(KNIFE_NAME)
	return if knife and knife:IsA("Model") then knife else nil
end

local function setSwing(fx: Fx, on: boolean, particles: boolean)
	local trail = fx.trail
	if trail then
		trail.Enabled = on
	end
	if particles or not on then
		setAll(fx.swing, on)
	end
end

-- Whether `knife` is close enough to this screen's camera for its particles.
local function isNear(knife: Model): boolean
	local camera = Workspace.CurrentCamera
	local root = knife.PrimaryPart
	return camera ~= nil and root ~= nil and (root.Position - camera.CFrame.Position).Magnitude <= K.IDLE_RANGE
end

-- The swing on `body`'s knife (a slash, or a stab's thrust when `stab`): the trail and swing effects for the swing
-- (a far-away knife only its trail), the idle effects paused meanwhile.
function KnifeFx.swing(body: Model, stab: boolean?)
	local knife = knifeOf(body)
	if not knife then
		return
	end
	local fx = fxOf(knife)
	local particles = isNear(knife)
	local on = if stab then K.STAB_TRAIL_ON else K.TRAIL_ON
	local off = if stab then K.STAB_TRAIL_OFF else K.TRAIL_OFF
	fx.swingStamp += 1
	local stamp = fx.swingStamp
	fx.swingUntil = os.clock() + off
	if fx.idleOn ~= false then
		fx.idleOn = false
		setAll(fx.idle, false)
	end
	task.delay(on, function()
		if fx.swingStamp == stamp then
			setSwing(fx, true, particles)
		end
	end)
	task.delay(off, function()
		if fx.swingStamp == stamp then
			setSwing(fx, false, particles)
		end
	end)
end

-- One body's knife this frame: idle effects on while held, near and not swinging; the light pulsing while held.
local function look(body: Model, now: number, eye: Vector3, glow: number)
	local knife = knifeOf(body)
	local root = if knife then knife.PrimaryPart else nil
	if not knife or not root then
		return
	end
	local fx = fxOf(knife)
	local held = body:GetAttribute("KnifeInHand") == true
	local near = (root.Position - eye).Magnitude <= K.IDLE_RANGE
	local idle = held and near and now >= fx.swingUntil
	if fx.idleOn ~= idle then
		fx.idleOn = idle
		setAll(fx.idle, idle)
	end
	local light = fx.light
	if light then
		light.Brightness = if held and near then glow else 0
	end
end

local function step()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local eye = camera.CFrame.Position
	local glow = K.LIGHT_BRIGHTNESS + K.LIGHT_PULSE * math.sin(now * math.pi * 2 / K.LIGHT_BEAT)
	for _, other in Players:GetPlayers() do
		local body = other.Character
		if body then
			look(body, now, eye, glow)
		end
	end
	local bots = Workspace:FindFirstChild("TagBots") -- Studio's test bots
	if bots then
		for _, bot in bots:GetChildren() do
			if bot:IsA("Model") then
				look(bot, now, eye, glow)
			end
		end
	end
end

function KnifeFx.start()
	RunService.Heartbeat:Connect(step)
end

return KnifeFx
