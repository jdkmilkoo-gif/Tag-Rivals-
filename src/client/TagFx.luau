--!strict
-- The tag and shrink effects, drawn on this screen only (design notes, Round flow, Map size and Camera):
--   * the hit burst where a runner is tagged, in the knife's colours (Bloomblade's "Sakura Bloom": a pink flash, a
--     star flare and light, two rings, a violet bloom, a burst of petals and sparks; the coin's white pictures, tinted,
--     stand in for the knife's own until the cosmetics thread's effect textures are uploaded). Big on purpose (owner
--     2026-11-10: "Epic VFX big and clearly visible"). The knife's own trail and effects are KnifeFx's;
--   * the tagged runner glows white and red (owner);
--   * the chaser's screen edges flash crimson (owner), and the view pops out a little (owner: "Tag/shrink: quick FOV
--     pop");
--   * a shrink shakes the camera: a sharp snap, then a rumble that fades over 0.8 s, stronger every shrink (owner).
-- The camera's shake and pop are added after CameraFeel each frame, so the two never fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlasticUi = require(script.Parent.PlasticUi)

local K = Config.Knife
local S = Config.Shrink
local T = Config.Tag

local TagFx = {}

local player = Players.LocalPlayer

-- The coin's white pictures (uploaded to the group), tinted; the knife's own effect textures replace these once
-- uploaded.
local IMG = Config.Coins.IMAGES
local TEX_SPARK = IMG.SPARKLE
local TEX_GLOW = IMG.GLOW
local TEX_FLARE = IMG.FLARE
local TEX_RING = IMG.RING
local TEX_RING_SOFT = IMG.RING_SOFT
local TEX_PETAL = IMG.DOT -- squashed into a petal

local PINK_A = Color3.fromHex(K.SLASH_COLOR_A)
local VIOLET = Color3.fromHex(K.SLASH_COLOR_B)
local DEEP = Color3.fromHex(K.SLASH_COLOR_C)
local PETALS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FFB4EE")),
	ColorSequenceKeypoint.new(0.35, Color3.fromHex("FF8AE0")),
	ColorSequenceKeypoint.new(0.7, Color3.fromHex("FFD6F6")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("F0A0FF")),
})
local CRIMSON = Color3.fromHex("D3132F")

local fxFolder: Folder? = nil
local edges: { Frame } = {}
local edgeAt = -math.huge
local edgeColor = CRIMSON
local shakeAt = -math.huge
local shakeStrength = 0
local shakeDir = Vector3.new(1, 0, 0)
local popAt = -math.huge
local popAmount = 0
local rng = Random.new()

local function folder(): Folder
	local existing = fxFolder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "TagFx"
	made.Parent = Workspace
	fxFolder = made
	return made
end

---------------------------------------------------------------- the hit burst

local function emitter(parent: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Enabled = false
	e.LightInfluence = 0
	e.LockedToPart = false
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function fadeSequence(fadeIn: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(fadeIn, 0),
		NumberSequenceKeypoint.new(0.6, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- The burst where a runner is tagged. `along`: the way the swing went (flat), for the petals.
function TagFx.hitBurst(position: Vector3, along: Vector3?)
	local holder = Instance.new("Part")
	holder.Name = "HitBurst"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	local direction = if along and along.Magnitude > 1e-3 then along.Unit else Vector3.new(0, 0, -1)
	holder.CFrame = CFrame.lookAt(position, position + direction)
	local at = Instance.new("Attachment")
	at.Parent = holder

	local flash = emitter(at, {
		Texture = TEX_GLOW,
		Color = ColorSequence.new(Color3.fromHex("FFD6F6"), PINK_A),
		Lifetime = NumberRange.new(0.3),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new(0, 1),
		Speed = NumberRange.new(0),
		LightEmission = 0.7,
		Brightness = 2.5,
	})
	local star = emitter(at, {
		Texture = TEX_FLARE,
		Color = ColorSequence.new(Color3.fromHex("FFFFFF"), PINK_A),
		Lifetime = NumberRange.new(0.35),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2),
			NumberSequenceKeypoint.new(0.25, 7.5),
			NumberSequenceKeypoint.new(1, 4.5),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 45),
		LightEmission = 1,
		Brightness = 3,
	})
	local ring = emitter(at, {
		Texture = TEX_RING,
		Color = ColorSequence.new(Color3.fromHex("D080FF")),
		Lifetime = NumberRange.new(0.45),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 11) }),
		Transparency = NumberSequence.new(0.05, 1),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		Brightness = 3,
	})
	local softRing = emitter(at, {
		Texture = TEX_RING_SOFT,
		Color = ColorSequence.new(PINK_A),
		Lifetime = NumberRange.new(0.7),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 8) }),
		Transparency = NumberSequence.new(0.2, 1),
		Speed = NumberRange.new(0),
		LightEmission = 1,
		Brightness = 2,
	})
	local petals = emitter(at, {
		Texture = TEX_PETAL,
		Color = PETALS,
		Lifetime = NumberRange.new(1.2, 1.9),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.35) }),
		Squash = NumberSequence.new(0.9),
		Transparency = fadeSequence(0.06),
		Speed = NumberRange.new(6, 15),
		SpreadAngle = Vector2.new(100, 100),
		EmissionDirection = Enum.NormalId.Front,
		Drag = 3.5,
		Acceleration = Vector3.new(0, -1.6, 0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-260, 260),
		LightEmission = 0.3,
		Brightness = 2.5,
	})
	local sparks = emitter(at, {
		Texture = TEX_SPARK,
		Color = ColorSequence.new(Color3.fromHex("FFD0F6"), Color3.fromHex("C040FF")),
		Lifetime = NumberRange.new(0.35, 0.65),
		Size = NumberSequence.new(0.7, 0),
		Speed = NumberRange.new(8, 20),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Acceleration = Vector3.new(0, -6.5, 0),
		Rotation = NumberRange.new(0, 45),
		LightEmission = 1,
		Brightness = 5,
	})
	local bloom = emitter(at, {
		Texture = TEX_GLOW,
		Color = ColorSequence.new(Color3.fromHex("DD7AFF"), DEEP),
		Lifetime = NumberRange.new(0.9),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.3, 5),
			NumberSequenceKeypoint.new(1, 5.5),
		}),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
		Speed = NumberRange.new(0),
		RotSpeed = NumberRange.new(34),
		LightEmission = 0.5,
		Brightness = 2,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("FF7AE0")
	light.Brightness = 6
	light.Range = 14
	light.Parent = at

	holder.Parent = folder()
	flash:Emit(2)
	star:Emit(1)
	ring:Emit(1)
	softRing:Emit(1)
	bloom:Emit(1)
	petals:Emit(60)
	sparks:Emit(40)
	TweenService:Create(light, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	task.delay(2.2, function()
		holder:Destroy()
	end)
end

---------------------------------------------------------------- the tagged runner's glow

-- The tagged runner glows white and red, fading into the red chaser outline (ChaserOutline draws it; this marks the
-- moment, on this screen only).
function TagFx.outline(body: Model)
	body:SetAttribute("TaggedFlashAt", os.clock())
end

---------------------------------------------------------------- the screen and the camera

-- The screen's edges flash (crimson by default) and fade.
function TagFx.edgeFlash(color: Color3?)
	edgeAt = os.clock()
	edgeColor = color or CRIMSON
end

-- The view pops out by `degrees` and eases back.
function TagFx.fovPop(degrees: number)
	popAt = os.clock()
	popAmount = degrees
end

-- A snap, then a rumble that fades (a shrink). `strength` ~0.25 to 1.2.
function TagFx.shake(strength: number)
	shakeAt = os.clock()
	shakeStrength = strength
	local angle = rng:NextNumber() * math.pi * 2
	shakeDir = Vector3.new(math.cos(angle), math.sin(angle), 0)
end

local function makeEdges(gui: ScreenGui)
	-- four strips, each fading from the edge inward
	local specs = {
		{ anchor = Vector2.new(0, 0), size = UDim2.new(1, 0, 0.22, 0), rotation = 90 },
		{ anchor = Vector2.new(0, 1), size = UDim2.new(1, 0, 0.22, 0), rotation = -90 },
		{ anchor = Vector2.new(0, 0), size = UDim2.new(0.16, 0, 1, 0), rotation = 0 },
		{ anchor = Vector2.new(1, 0), size = UDim2.new(0.16, 0, 1, 0), rotation = 180 },
	}
	for i, spec in specs do
		local strip = Instance.new("Frame")
		strip.Name = "Edge" .. i
		strip.BorderSizePixel = 0
		strip.AnchorPoint = spec.anchor
		strip.Position = UDim2.fromScale(spec.anchor.X, spec.anchor.Y)
		strip.Size = spec.size
		strip.BackgroundColor3 = CRIMSON
		strip.BackgroundTransparency = 1
		local fade = Instance.new("UIGradient")
		fade.Rotation = spec.rotation
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = strip
		strip.Parent = gui
		table.insert(edges, strip)
	end
end

local function cameraStep()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	-- the FOV pop: out fast, back over 0.35 s
	local popAge = now - popAt
	if popAge >= 0 and popAge < 0.4 then
		local x = popAge / 0.4
		local amount = if x < 0.12 then popAmount * (x / 0.12) else popAmount * (1 - (x - 0.12) / 0.88) ^ 2
		camera.FieldOfView = math.clamp(camera.FieldOfView + amount, 1, 120)
	end
	-- the shake: a sharp snap for 0.07 s, then the rumble fading over RUMBLE_TIME
	local age = now - shakeAt
	if age >= 0 and age < S.RUMBLE_TIME + 0.07 then
		local offset: Vector3
		local roll: number
		if age < 0.07 then
			local k = shakeStrength * (1 - age / 0.07)
			offset = shakeDir * 0.7 * k
			roll = 1.5 * k * shakeDir.X
		else
			local fade = 1 - (age - 0.07) / S.RUMBLE_TIME
			local k = shakeStrength * fade * fade
			offset = Vector3.new(math.noise(age * 22, 1.7), math.noise(age * 22, 7.3), 0) * 0.5 * k
			roll = math.noise(age * 18, 3.1) * 1.2 * k
		end
		camera.CFrame *= CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(roll))
	end
	-- the edge flash
	local flashAge = now - edgeAt
	local see = if flashAge >= 0 and flashAge < T.FLASH_TIME then 0.15 + 0.85 * (flashAge / T.FLASH_TIME) else 1
	for _, strip in edges do
		strip.BackgroundTransparency = see
		strip.BackgroundColor3 = edgeColor
	end
end

function TagFx.start()
	local gui = PlasticUi.screen("TagRivalsEdgeFlash", 8)
	makeEdges(gui)
	gui.Parent = player:WaitForChild("PlayerGui")
	RunService:BindToRenderStep("TagRivalsTagFx", Enum.RenderPriority.Camera.Value + 2, cameraStep)
end

return TagFx
