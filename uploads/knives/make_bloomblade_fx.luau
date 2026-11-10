--!strict
-- Builds Bloomblade's own effects onto ServerStorage.Knives.Bloomblade (run in Studio's command bar, Edit mode; it
-- replaces the ones made before, so it can be run again after a change). Save the place afterwards.
--
-- Everything sits on FX_Blade, an invisible part over the blade, so the emitters spread along the whole blade. Every
-- emitter is off here; the client's KnifeFx turns them on:
--   * KnifeFx = "Idle": while a chaser holds the knife and isn't swinging (knife spec: violet aura glow, rising energy
--     flames, pink petals, blossoms, wisps, twinkles; the pulsing light is Knives.luau's BladeLight);
--   * KnifeFx = "Swing": while the slash's trail is on (petals shed off the blade, sparks, a glow smear).
-- Textures: the coin's white pictures (uploaded to the group, tinted here) and Roblox's own fire; the knife's own
-- effect textures can replace them later.

local ServerStorage = game:GetService("ServerStorage")

local GLOW = "rbxassetid://82782979316979"
local DOT = "rbxassetid://108069752069280"
local SPARKLE = "rbxassetid://113364152964594"
local FLARE = "rbxassetid://87826708506803"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local knife = ServerStorage:WaitForChild("Knives"):WaitForChild("Bloomblade") :: Model
local root = knife:WaitForChild("KnifeRoot") :: BasePart

local old = knife:FindFirstChild("FX_Blade")
if old then
	old:Destroy()
end

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function colors(...: string): ColorSequence
	local list = { ... }
	if #list == 1 then
		return ColorSequence.new(hex(list[1]))
	end
	local keys = {}
	for i, h in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), hex(h)))
	end
	return ColorSequence.new(keys)
end

local function numbers(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

-- the part the effects come from: the blade's own box (the blade runs from x 0 to 2.17, edge down)
local holder = Instance.new("Part")
holder.Name = "FX_Blade"
holder.Size = Vector3.new(2.1, 0.46, 0.14)
holder.CFrame = root.CFrame * CFrame.new(1.09, -0.17, 0)
holder.Transparency = 1
holder.Anchored = true
holder.CanCollide = false
holder.CanTouch = false
holder.CanQuery = false
holder.CastShadow = false
holder.Massless = true

local function emitter(name: string, kind: string, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LightInfluence = 0
	e.Speed = NumberRange.new(0)
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Enabled = false
	e:SetAttribute("KnifeFx", kind)
	e.Parent = holder
end

---------------------------------------------------------------- idle (held, not swinging)

-- the violet aura: soft glows hugging the blade
emitter("Aura", "Idle", {
	Texture = GLOW,
	Color = colors("B45CFF", "7A2AFF"),
	LightEmission = 0.35, -- low, so the stacked glows stay violet instead of washing out to white
	Brightness = 1.3,
	Size = numbers({ { 0, 1.1 }, { 0.5, 1.7 }, { 1, 1.4 } }),
	Transparency = numbers({ { 0, 1 }, { 0.3, 0.55 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.5, 0.8),
	Rate = 16,
	Rotation = NumberRange.new(0, 360),
	LockedToPart = true,
	ZOffset = -0.3,
})

-- the energy flames rising off the blade
emitter("Flames", "Idle", {
	Texture = FIRE,
	Color = colors("FF7AE0", "C45CFF", "7A2AFF"),
	LightEmission = 0.6,
	Brightness = 1.3,
	Size = numbers({ { 0, 0.75 }, { 0.6, 0.45 }, { 1, 0.1 } }),
	Transparency = numbers({ { 0, 0.25 }, { 0.6, 0.5 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.4, 0.65),
	Rate = 30,
	Speed = NumberRange.new(0.4, 1.2),
	SpreadAngle = Vector2.new(20, 20),
	EmissionDirection = Enum.NormalId.Top,
	Acceleration = Vector3.new(0, 7, 0),
	Drag = 1,
	Rotation = NumberRange.new(-20, 20),
	RotSpeed = NumberRange.new(-60, 60),
})

-- pink petals drifting off and down
emitter("Petals", "Idle", {
	Texture = DOT,
	Color = colors("FF9BE6", "FF6AD8", "FFB8EE"),
	LightEmission = 0.1,
	Brightness = 1.6,
	Size = numbers({ { 0, 0.34 }, { 1, 0.24 } }),
	Squash = NumberSequence.new(0.9),
	Transparency = numbers({ { 0, 1 }, { 0.1, 0 }, { 0.75, 0.1 }, { 1, 1 } }),
	Lifetime = NumberRange.new(1.2, 1.8),
	Rate = 7,
	Speed = NumberRange.new(0.6, 1.6),
	SpreadAngle = Vector2.new(180, 180),
	Acceleration = Vector3.new(0, -1.4, 0),
	Drag = 1.2,
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-200, 200),
})

-- blossoms: bright pink flowers of light opening and closing on the blade
emitter("Blossoms", "Idle", {
	Texture = FLARE,
	Color = colors("FFC8F4", "FF6AD8"),
	LightEmission = 1,
	Brightness = 2.5,
	Size = numbers({ { 0, 0 }, { 0.3, 1.3 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.5, 0.75),
	Rate = 4,
	Rotation = NumberRange.new(0, 90),
	RotSpeed = NumberRange.new(40, 90),
	LockedToPart = true,
})

-- wisps: thin violet streaks curling up
emitter("Wisps", "Idle", {
	Texture = GLOW,
	Color = colors("C870FF", "6A1AFF"),
	LightEmission = 1,
	Brightness = 2,
	Size = numbers({ { 0, 0.45 }, { 1, 0.15 } }),
	Squash = NumberSequence.new(1.6),
	Orientation = Enum.ParticleOrientation.VelocityParallel,
	Transparency = numbers({ { 0, 1 }, { 0.2, 0.35 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.8, 1.2),
	Rate = 8,
	Speed = NumberRange.new(1, 2.4),
	SpreadAngle = Vector2.new(35, 35),
	EmissionDirection = Enum.NormalId.Top,
	Acceleration = Vector3.new(0, 2, 0),
})

-- twinkles: little white-pink stars popping round it
emitter("Twinkles", "Idle", {
	Texture = SPARKLE,
	Color = colors("FFFFFF", "FFC2F2"),
	LightEmission = 1,
	Brightness = 2.5,
	Size = numbers({ { 0, 0 }, { 0.4, 0.5 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.4, 0.7),
	Rate = 12,
	Speed = NumberRange.new(0.3, 1.2),
	SpreadAngle = Vector2.new(180, 180),
	Rotation = NumberRange.new(0, 45),
})

---------------------------------------------------------------- the swing (while the trail is on)

-- petals shed off the blade along the swing
emitter("SwingPetals", "Swing", {
	Texture = DOT,
	Color = colors("FF9BE6", "FF6AD8", "FFB8EE"),
	LightEmission = 0.1,
	Brightness = 1.6,
	Size = numbers({ { 0, 0.42 }, { 1, 0.28 } }),
	Squash = NumberSequence.new(0.9),
	Transparency = numbers({ { 0, 0 }, { 0.7, 0.15 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.7, 1.1),
	Rate = 110,
	Speed = NumberRange.new(1.5, 4),
	SpreadAngle = Vector2.new(180, 180),
	Acceleration = Vector3.new(0, -2.5, 0),
	Drag = 2.5,
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-260, 260),
})

-- sparks flying off the edge
emitter("SwingSparks", "Swing", {
	Texture = SPARKLE,
	Color = colors("FFFFFF", "FF8AE6", "C45CFF"),
	LightEmission = 1,
	Brightness = 3,
	Size = numbers({ { 0, 0.55 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.25, 0.45),
	Rate = 80,
	Speed = NumberRange.new(3, 7),
	SpreadAngle = Vector2.new(180, 180),
	Drag = 4,
	Rotation = NumberRange.new(0, 45),
})

-- a glowing smear left along the swing's path
emitter("SwingGlow", "Swing", {
	Texture = GLOW,
	Color = colors("FF9BEA", "C45CFF"),
	LightEmission = 0.3,
	Brightness = 1.2,
	Size = numbers({ { 0, 1.8 }, { 1, 2.6 } }),
	Transparency = numbers({ { 0, 0.45 }, { 1, 1 } }),
	Lifetime = NumberRange.new(0.18, 0.28),
	Rate = 40,
	Rotation = NumberRange.new(0, 360),
})

holder.Parent = knife
print(`Bloomblade effects built: {#holder:GetChildren()} emitters on FX_Blade (save the place to keep them)`)
