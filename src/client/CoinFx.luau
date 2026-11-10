--!strict
-- The coins on the arena, drawn on this screen only (design notes, Coins and economy and Star pickup feel; the 'Tag
-- Rivals Coin' preview; owner 2026-11-09: "now implement coins as a pickup in the rounds eith that coin in the
-- artifacts", "make sure it doesnt lag the game at all"):
--   * the coin: the preview's gold coin with a faceted 4-point star on both faces (3 MeshParts, one model shared by
--     every coin), hovering at chest height, bobbing, turning once every 4 s and rocking a little;
--   * round it: a soft gold glow that breathes, gold dust rising, twinkles popping on its rim, a light on the floor and
--     a turning dashed ring under it so you can spot it from far away;
--   * a new coin pops in with a fast spin, a light beam from the floor and a ring;
--   * a pick-up: the coin squashes and snaps toward whoever took it, a white-gold flash and light, 12 gold sparkles,
--     spark streaks, glitter hanging in the air, a ring in the air and two on the floor. Yours also pops "+2" and flies
--     a coin to the counter (CoinHud);
--   * coins on a strip that's cut off fall with it; at the match's end the rest pop away.
-- Light by design: the server only sends spots; every coin's pieces are made once and reused; all coins move in one
-- BulkMoveTo a frame; the burst is a few shared emitters fired with Emit; coins far from your camera stop their dust
-- and twinkles; no lights stay on (only a short flash on a pick-up).
-- Your own screen tells the server when you touch a coin, so a pick-up shows at once; the server checks it, and the
-- counter only counts what the server gives.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CoinRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CoinRules"))
local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local CoinHud = require(script.Parent.CoinHud)

local C = Config.Coins
local IMG = C.IMAGES

local CoinFx = {}

local player = Players.LocalPlayer

type State = "spawn" | "idle" | "snap" | "drop" | "vanish"

type Visual = {
	id: number,
	spot: Vector3,
	model: Model,
	parts: { BasePart },
	sizes: { Vector3 },
	offsets: { CFrame },
	plate: Part,
	plateGui: SurfaceGui,
	pool: ImageLabel,
	ring: ImageLabel,
	glow: BillboardGui,
	glowImage: ImageLabel,
	dust: ParticleEmitter,
	twinkleAt: Attachment,
	twinkle: ParticleEmitter,
	state: State,
	t: number,
	angle: number,
	phase: number,
	nextTwinkle: number,
	target: Vector3?,
	lastScale: number,
	fall: number,
	fallSpeed: number,
	near: boolean,
}

-- A short-lived floor ring, light beam or light flash.
type Effect = {
	kind: "ring" | "beam" | "light",
	t: number,
	life: number,
	delay: number,
	from: number,
	to: number,
	see: number,
	image: ImageLabel?,
	part: Part?,
	beam: Beam?,
	bottom: Attachment?,
	top: Attachment?,
	light: PointLight?,
	strength: number,
	busy: boolean,
}

local GOLD = Color3.fromHex(C.GLOW_COLOR)
local GOLDS = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FFE58A")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("FFD24A")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("FFAE1A")),
})
local SPARK_GOLDS = ColorSequence.new(Color3.fromHex("FFD24A"), Color3.fromHex("FF9A12"))
local WHITE = Color3.new(1, 1, 1)
local HIDDEN = CFrame.new(0, -1000, 0)
local ROOT_HEIGHT = 3 -- studs from the floor's top to an R6 body's middle
local RING_PLATE = 8 -- studs across a pick-up floor ring's plate
local TURN = math.pi * 2 / C.TURN_TIME
local DROP_TIME = 1.2 -- s a coin on a cut strip takes to fall away
local VANISH_TIME = 0.25
local CLAIM_WAIT = 1.5 -- s before a pick-up the server didn't give puts the coin back
local GUI_HZ = 20 -- times a second the glow, floor light and ring change (they move smoothly enough)

local folder: Folder? = nil -- ReplicatedStorage.ArenaCoins
local remote: RemoteEvent? = nil
local fxFolder: Folder = nil :: any
local template: { { part: BasePart, offset: CFrame } } = {}
local visuals: { [number]: Visual } = {}
local spare: { Visual } = {}
local effects: { Effect } = {}
local claimed: { [number]: number } = {} -- coins you touched that the server hasn't answered: when
local mine: { [number]: boolean } = {} -- coins you touched (the server's "take" for them is already drawn)
local clock = 0
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local burstAt: Attachment = nil :: any
local burst: { { emitter: ParticleEmitter, count: number } } = {}
local spawnAt: Attachment = nil :: any
local spawnSparks: ParticleEmitter = nil :: any
local nearCheck = 0
local guiSince = 0
local rng = Random.new()

local function number(value: unknown): number
	return if type(value) == "number" then value else 0
end

local function fade(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function emitter(props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 2
	e.Speed = NumberRange.new(0)
	e.SpreadAngle = Vector2.new(0, 0)
	e.ZOffset = 0.5
	for key, value in props do
		(e :: any)[key] = value
	end
	return e
end

local function hiddenPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = HIDDEN
	return part
end

---------------------------------------------------------------- the coin's model

-- The coin's three meshes from ReplicatedStorage.CoinModel, coloured as the preview; a plain gold disc if the model
-- isn't there.
local function loadTemplate()
	local model = ReplicatedStorage:WaitForChild(CoinRules.MODEL, 10)
	local looks = {
		CoinRim = { color = C.RIM_COLOR, material = Enum.Material.Foil },
		CoinField = { color = C.FIELD_COLOR, material = Enum.Material.Foil },
		CoinStar = { color = C.STAR_COLOR, material = Enum.Material.Neon },
	}
	if model then
		for name, look in looks do
			local found = model:FindFirstChild(name, true)
			if found and found:IsA("BasePart") then
				local part = found:Clone()
				for _, child in part:GetChildren() do
					child:Destroy()
				end
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Color = Color3.fromHex(look.color)
				part.Material = look.material
				table.insert(template, { part = part, offset = CFrame.identity })
			end
		end
		-- the rim first: twinkles sit on it
		table.sort(template, function(a, b)
			return a.part.Name == "CoinRim" and b.part.Name ~= "CoinRim"
		end)
	end
	if #template == 0 then
		warn(`[{Config.GameName}] the coin's model is missing; drawing a plain gold coin`)
		local disc = Instance.new("Part")
		disc.Name = "CoinRim"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.3, 2, 2)
		disc.Anchored = true
		disc.CanCollide = false
		disc.CanQuery = false
		disc.CanTouch = false
		disc.CastShadow = false
		disc.Color = Color3.fromHex(C.RIM_COLOR)
		disc.Material = Enum.Material.Foil
		-- a cylinder's round faces look along X; the coin's along Z
		table.insert(template, { part = disc, offset = CFrame.Angles(0, math.pi / 2, 0) })
	end
end

---------------------------------------------------------------- one coin's pieces (made once, reused)

local function newVisual(): Visual
	local model = Instance.new("Model")
	model.Name = "Coin"
	local parts, sizes, offsets = {}, {}, {}
	for _, each in template do
		local part = each.part:Clone()
		part.CFrame = HIDDEN
		part.Parent = model
		table.insert(parts, part)
		table.insert(sizes, part.Size)
		table.insert(offsets, each.offset)
	end
	local rim = parts[1]

	-- the floor under it: a light pool and the turning dashed ring, glowing (LightInfluence 0)
	local plate = hiddenPart("Floor", Vector3.new(3.4, 0.05, 3.4))
	plate.Parent = model
	local plateGui = Instance.new("SurfaceGui")
	plateGui.Face = Enum.NormalId.Top
	plateGui.LightInfluence = 0
	plateGui.Brightness = 1.6
	plateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	plateGui.PixelsPerStud = 40
	plateGui.ZOffset = 1
	plateGui.Enabled = false
	plateGui.Parent = plate
	local pool = Instance.new("ImageLabel")
	pool.Name = "Pool"
	pool.BackgroundTransparency = 1
	pool.Image = IMG.GLOW
	pool.ImageColor3 = Color3.fromHex(C.POOL_COLOR)
	pool.Size = UDim2.fromScale(1, 1)
	pool.Parent = plateGui
	local ring = Instance.new("ImageLabel")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Image = IMG.DASH_RING
	ring.ImageColor3 = Color3.fromHex(C.RING_COLOR)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.88, 0.88)
	ring.Parent = plateGui

	-- gold dust rising from round its foot
	local dust = emitter({
		Name = "Dust",
		Texture = IMG.DOT,
		Rate = 7,
		Lifetime = NumberRange.new(1.1, 1.8),
		Speed = NumberRange.new(1.1, 1.9),
		EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = fade({ { 0, 0.16 }, { 1, 0.05 } }),
		Transparency = fade({ { 0, 1 }, { 0.15, 0.1 }, { 0.7, 0.3 }, { 1, 1 } }),
		Color = GOLDS,
		Drag = 0.3,
		Enabled = false,
	})
	dust.Parent = plate

	-- the glow round the coin
	local glow = Instance.new("BillboardGui")
	glow.Name = "Glow"
	glow.Size = UDim2.fromScale(3.2, 3.2)
	glow.LightInfluence = 0
	glow.Brightness = 1.4
	glow.MaxDistance = C.FAR * 1.6
	glow.Adornee = rim
	glow.Enabled = false
	glow.Parent = rim
	local glowImage = Instance.new("ImageLabel")
	glowImage.BackgroundTransparency = 1
	glowImage.Image = IMG.GLOW
	glowImage.ImageColor3 = GOLD
	glowImage.Size = UDim2.fromScale(1, 1)
	glowImage.Parent = glow

	-- twinkles popping on the rim, one at a time
	local twinkleAt = Instance.new("Attachment")
	twinkleAt.Name = "Twinkle"
	twinkleAt.Parent = rim
	local twinkle = emitter({
		Name = "Twinkle",
		Texture = IMG.SPARKLE,
		Lifetime = NumberRange.new(0.32, 0.45),
		Size = fade({ { 0, 0 }, { 0.4, 0.6 }, { 1, 0 } }),
		Rotation = NumberRange.new(-20, 20),
		RotSpeed = NumberRange.new(60, 120),
		Color = ColorSequence.new(Color3.fromHex("FFF4CC")),
		Brightness = 3,
	})
	twinkle.Parent = twinkleAt

	model.Parent = fxFolder
	return {
		id = 0,
		spot = Vector3.zero,
		model = model,
		parts = parts,
		sizes = sizes,
		offsets = offsets,
		plate = plate,
		plateGui = plateGui,
		pool = pool,
		ring = ring,
		glow = glow,
		glowImage = glowImage,
		dust = dust,
		twinkleAt = twinkleAt,
		twinkle = twinkle,
		state = "idle",
		t = 0,
		angle = 0,
		phase = 0,
		nextTwinkle = 0,
		target = nil,
		lastScale = 1,
		fall = 0,
		fallSpeed = 0,
		near = true,
	}
end

local function setScale(v: Visual, scale: number, squash: number)
	if math.abs(scale - v.lastScale) < 1e-3 and squash == 1 then
		return
	end
	v.lastScale = scale
	local s = math.max(scale, 0.02)
	for i, part in v.parts do
		local base = v.sizes[i]
		part.Size = Vector3.new(base.X * s, base.Y * s, base.Z * s * squash)
	end
end

local function setNear(v: Visual, near: boolean)
	v.near = near
	local live = v.state == "idle" or v.state == "spawn"
	v.dust.Enabled = near and live
end

-- Back to the spares: hidden underground, everything off.
local function release(v: Visual)
	visuals[v.id] = nil
	v.dust.Enabled = false
	v.glow.Enabled = false
	v.plateGui.Enabled = false
	setScale(v, 1, 1)
	for _, part in v.parts do
		part.CFrame = HIDDEN
	end
	v.plate.CFrame = HIDDEN
	table.insert(spare, v)
end

local function pieces(): Visual
	local v = table.remove(spare)
	return v or newVisual()
end

---------------------------------------------------------------- short effects (pooled)

local function freeEffect(kind: "ring" | "beam" | "light"): Effect
	for _, e in effects do
		if not e.busy and e.kind == kind then
			return e
		end
	end
	local e: Effect = {
		kind = kind,
		t = 0,
		life = 1,
		delay = 0,
		from = 0,
		to = 1,
		see = 0,
		strength = 0,
		busy = false,
	}
	if kind == "ring" then
		local part = hiddenPart("FloorRing", Vector3.new(RING_PLATE, 0.05, RING_PLATE))
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 32
		gui.ZOffset = 2
		gui.Parent = part
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Parent = gui
		part.Parent = fxFolder
		e.part = part
		e.image = image
	elseif kind == "beam" then
		local bottom = Instance.new("Attachment")
		bottom.Parent = Workspace.Terrain
		local top = Instance.new("Attachment")
		top.Parent = Workspace.Terrain
		local beam = Instance.new("Beam")
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Texture = IMG.BEAM
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Brightness = 2
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = 1.9
		beam.Width1 = 1.5
		beam.Color = ColorSequence.new(Color3.fromHex("FFC738"), Color3.fromHex("FFF4BF"))
		beam.Enabled = false
		beam.Parent = bottom
		e.beam = beam
		e.bottom = bottom
		e.top = top
	else
		local at = Instance.new("Attachment")
		at.Parent = Workspace.Terrain
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex("FFC040")
		light.Range = 12
		light.Brightness = 0
		light.Shadows = false
		light.Enabled = false
		light.Parent = at
		e.light = light
	end
	table.insert(effects, e)
	return e
end

-- An expanding ring on the floor at `spot`: from `from` to `to` studs across over `life` s.
local function floorRing(
	spot: Vector3,
	from: number,
	to: number,
	life: number,
	color: Color3,
	see: number,
	image: string,
	delay: number?
)
	local e = freeEffect("ring")
	e.busy = true
	e.t = -(delay or 0)
	e.life = life
	e.from, e.to, e.see = from, to, see
	local part = e.part :: Part
	local img = e.image :: ImageLabel
	img.Image = image
	img.ImageColor3 = color
	img.ImageTransparency = 1
	part.CFrame = CFrame.new(spot + Vector3.new(0, 0.04, 0))
end

local function lightFlash(at: Vector3, strength: number, life: number)
	local e = freeEffect("light")
	e.busy = true
	e.t = 0
	e.life = life
	e.strength = strength
	local light = e.light :: PointLight
	local holder = light.Parent :: Attachment
	holder.WorldPosition = at
	light.Enabled = true
end

local function lightBeam(spot: Vector3)
	local e = freeEffect("beam")
	e.busy = true
	e.t = 0
	e.life = 0.55
	local beam = e.beam :: Beam
	local bottom = e.bottom :: Attachment
	local top = e.top :: Attachment
	bottom.WorldPosition = spot + Vector3.new(0, 0.1, 0)
	top.WorldPosition = spot + Vector3.new(0, 9, 0)
	beam.Enabled = true
end

local function stepEffects(dt: number)
	for _, e in effects do
		if e.busy then
			e.t += dt
			local u = e.t / e.life
			if e.kind == "ring" then
				local img = e.image :: ImageLabel
				if u >= 1 then
					e.busy = false
					img.ImageTransparency = 1
					local part = e.part :: Part
					part.CFrame = HIDDEN
				elseif u >= 0 then
					local eased = 1 - (1 - u) ^ 3
					local across = (e.from + (e.to - e.from) * eased) / RING_PLATE
					img.Size = UDim2.fromScale(across, across)
					img.ImageTransparency = 1 - (1 - e.see) * (1 - u) ^ 1.3
				end
			elseif e.kind == "beam" then
				local beam = e.beam :: Beam
				if u >= 1 then
					e.busy = false
					beam.Enabled = false
				else
					local a = math.sin(math.pi * math.min(1, u * 1.4)) * (1 - u)
					beam.Transparency = NumberSequence.new(1 - 0.9 * a)
					beam.Width0 = 1.9 * (1 - 0.5 * u)
					beam.Width1 = 1.5 * (1 - 0.5 * u)
				end
			else
				local light = e.light :: PointLight
				if u >= 1 then
					e.busy = false
					light.Enabled = false
				else
					light.Brightness = e.strength * (1 - u) ^ 2
				end
			end
		end
	end
end

---------------------------------------------------------------- the bursts (a few shared emitters, fired with Emit)

local function buildBursts()
	burstAt = Instance.new("Attachment")
	burstAt.Name = "CoinBurst"
	burstAt.Parent = Workspace.Terrain
	local function add(count: number, props: { [string]: any })
		local e = emitter(props)
		e.Parent = burstAt
		table.insert(burst, { emitter = e, count = count })
	end
	-- the white-gold flash
	add(1, {
		Texture = IMG.GLOW,
		Lifetime = NumberRange.new(0.22),
		Size = fade({ { 0, 0.8 }, { 1, 2.6 } }),
		Color = ColorSequence.new(Color3.fromHex("FFD257")),
		Transparency = fade({ { 0, 0.2 }, { 1, 1 } }),
	})
	add(1, {
		Texture = IMG.FLARE,
		Lifetime = NumberRange.new(0.2),
		Size = fade({ { 0, 3.8 }, { 1, 1.2 } }),
		Color = ColorSequence.new(Color3.fromHex("FFF0B8")),
		Rotation = NumberRange.new(10),
		RotSpeed = NumberRange.new(110),
		Transparency = fade({ { 0, 0 }, { 1, 1 } }),
		Brightness = 3,
	})
	add(1, {
		Texture = IMG.DOT,
		Lifetime = NumberRange.new(0.13),
		Size = fade({ { 0, 1.5 }, { 1, 0.4 } }),
		Color = ColorSequence.new(WHITE),
		Transparency = fade({ { 0, 0 }, { 1, 1 } }),
		Brightness = 3,
	})
	add(1, {
		Texture = IMG.SPARKLE,
		Lifetime = NumberRange.new(0.22),
		Size = fade({ { 0, 0.6 }, { 1, 2 } }),
		Color = ColorSequence.new(WHITE),
		Rotation = NumberRange.new(45),
		Transparency = fade({ { 0, 0 }, { 1, 1 } }),
	})
	-- 12 gold sparkles thrown out
	add(12, {
		Texture = IMG.SPARKLE,
		Lifetime = NumberRange.new(0.5, 0.75),
		Speed = NumberRange.new(4.5, 7.5),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3.2,
		Acceleration = Vector3.new(0, -2.5, 0),
		Size = fade({ { 0, 0.5 }, { 1, 0.12 } }),
		Rotation = NumberRange.new(-25, 25),
		RotSpeed = NumberRange.new(-340, 340),
		Color = SPARK_GOLDS,
		Transparency = fade({ { 0, 0 }, { 0.6, 0.1 }, { 1, 1 } }),
		Brightness = 2.5,
	})
	-- spark streaks, stretched along their flight
	add(9, {
		Texture = IMG.DOT,
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(8, 13),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Acceleration = Vector3.new(0, -3, 0),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = fade({ { 0, 2.2 }, { 1, 1.4 } }),
		Size = fade({ { 0, 0.22 }, { 1, 0.08 } }),
		Color = ColorSequence.new(Color3.fromHex("FFF2C0"), Color3.fromHex("FFB020")),
		Transparency = fade({ { 0, 0 }, { 1, 1 } }),
		Brightness = 3,
	})
	-- glitter hanging in the air
	add(10, {
		Texture = IMG.FLARE,
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(2, 4.5),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 9,
		Size = fade({ { 0, 0 }, { 0.3, 0.55 }, { 0.6, 0.25 }, { 1, 0 } }),
		RotSpeed = NumberRange.new(100, 140),
		Color = ColorSequence.new(WHITE, Color3.fromHex("FFD24A")),
		Brightness = 3,
	})
	-- a ring in the air
	add(1, {
		Texture = IMG.RING_SOFT,
		Lifetime = NumberRange.new(0.38),
		Size = fade({ { 0, 0.5 }, { 1, 3.6 } }),
		Color = ColorSequence.new(Color3.fromHex("FFD257")),
		Transparency = fade({ { 0, 0.1 }, { 1, 1 } }),
	})

	-- a new coin: sparkles rising round it
	spawnAt = Instance.new("Attachment")
	spawnAt.Name = "CoinSpawn"
	spawnAt.Parent = Workspace.Terrain
	spawnSparks = emitter({
		Texture = IMG.SPARKLE,
		Lifetime = NumberRange.new(0.45, 0.65),
		Speed = NumberRange.new(3.5, 5),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(28, 28),
		Drag = 1.5,
		Size = fade({ { 0, 0.4 }, { 1, 0.1 } }),
		RotSpeed = NumberRange.new(150, 200),
		Color = GOLDS,
		Transparency = fade({ { 0, 0 }, { 1, 1 } }),
		Brightness = 2.5,
	})
	spawnSparks.Parent = spawnAt
end

local function burstAtPoint(at: Vector3)
	burstAt.WorldPosition = at
	for _, each in burst do
		each.emitter:Emit(each.count)
	end
	local floor = Vector3.new(at.X, at.Y - C.HOVER, at.Z)
	floorRing(floor, 1, 6, 0.45, Color3.fromHex("FFCF4D"), 0.1, IMG.RING)
	floorRing(floor, 0.6, 3.6, 0.35, WHITE, 0.4, IMG.RING_SOFT, 0.05)
	lightFlash(at, 6, 0.3)
end

---------------------------------------------------------------- coins coming and going

local function coinPosition(v: Visual): Vector3
	return v.spot + Vector3.new(0, C.HOVER + math.sin(clock * C.BOB_SPEED + v.phase) * C.BOB + v.fall, 0)
end

local function show(v: Visual, quiet: boolean)
	v.state = if quiet then "idle" else "spawn"
	v.t = 0
	v.fall = 0
	v.fallSpeed = 0
	v.target = nil
	v.angle = rng:NextNumber() * math.pi * 2
	v.phase = rng:NextNumber() * math.pi * 2
	v.nextTwinkle = 0.2 + rng:NextNumber() * 0.6
	v.lastScale = -1
	setScale(v, if quiet then 1 else 0.02, 1)
	v.plate.CFrame = CFrame.new(v.spot + Vector3.new(0, 0.03, 0))
	v.plateGui.Enabled = true
	v.glow.Enabled = true
	setNear(v, v.near)
end

-- Coin `id` at `spot` shows up (`quiet`: already there, no pop).
local function add(id: number, spot: Vector3, quiet: boolean)
	if visuals[id] then
		return
	end
	local v = pieces()
	v.id = id
	v.spot = spot
	visuals[id] = v
	show(v, quiet)
	if not quiet then
		lightBeam(spot)
		floorRing(spot, 0.4, 4.2, 0.5, Color3.fromHex("FFD257"), 0.2, IMG.RING)
		spawnAt.WorldPosition = spot + Vector3.new(0, 0.3, 0)
		spawnSparks:Emit(10)
	end
end

local function leaveFloor(v: Visual)
	v.plateGui.Enabled = false
	v.dust.Enabled = false
end

-- Coin `id` is picked up by someone whose body is at `toward` (its middle): it snaps toward them and bursts.
local function snap(id: number, toward: Vector3?)
	local v = visuals[id]
	if not v or v.state == "snap" or v.state == "drop" then
		return
	end
	local at = coinPosition(v)
	v.state = "snap"
	v.t = 0
	v.target = toward
	leaveFloor(v)
	burstAtPoint(at)
end

local function bodyMiddle(who: Instance?): Vector3?
	if not who then
		return nil
	end
	local model = if who:IsA("Player") then who.Character else who
	local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- You touched coin `id`: shown at once, and the server is told.
local function claim(v: Visual, root: BasePart)
	local id = v.id
	claimed[id] = os.clock()
	mine[id] = true
	local at = coinPosition(v)
	snap(id, root.Position)
	CoinHud.collect(at)
	if remote then
		remote:FireServer("take", id)
	end
end

local function onTake(id: unknown, who: unknown, spot: unknown)
	if type(id) ~= "number" then
		return
	end
	claimed[id] = nil
	if who == player then
		if mine[id] then
			mine[id] = nil -- drawn already
			return
		end
		-- the server saw you touch it first
		local v = visuals[id]
		local at = if v
			then coinPosition(v)
			elseif typeof(spot) == "Vector3" then spot + Vector3.new(0, C.HOVER, 0)
			else nil
		if v then
			snap(id, bodyMiddle(player))
		elseif at then
			burstAtPoint(at)
		end
		if at then
			CoinHud.collect(at)
		end
		return
	end
	mine[id] = nil
	if visuals[id] then
		snap(id, bodyMiddle(if typeof(who) == "Instance" then who else nil))
	end
end

local function onDrop(ids: unknown)
	if type(ids) ~= "table" then
		return
	end
	for _, id in ids :: { any } do
		local v = if type(id) == "number" then visuals[id] else nil
		if v and v.state ~= "snap" then
			v.state = "drop"
			v.t = 0
			v.fallSpeed = 4
			leaveFloor(v)
		end
	end
end

local function vanish(v: Visual)
	if v.state == "snap" or v.state == "drop" or v.state == "vanish" then
		return
	end
	v.state = "vanish"
	v.t = 0
	leaveFloor(v)
end

local function onClear()
	for _, v in visuals do
		vanish(v)
	end
	table.clear(claimed)
	table.clear(mine)
end

-- The coin's attribute changed: a new coin, or one gone. A gone one with no word on why (a "take" or "drop" usually
-- comes first) pops away a moment later.
local function onAttribute(key: string)
	local id = CoinRules.idOf(key)
	if not id or not folder then
		return
	end
	local spot = folder:GetAttribute(key)
	if typeof(spot) == "Vector3" then
		if not claimed[id] then
			add(id, spot, false)
		end
		return
	end
	claimed[id] = nil
	task.delay(0.3, function()
		local v = visuals[id]
		if
			v
			and v.id == id
			and (v.state == "idle" or v.state == "spawn")
			and folder
			and folder:GetAttribute(key) == nil
		then
			vanish(v)
		end
	end)
end

---------------------------------------------------------------- every frame

local function elastic(u: number): number
	if u <= 0 then
		return 0
	elseif u >= 1 then
		return 1
	end
	return 2 ^ (-10 * u) * math.sin((u * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

local function canPickUp(): boolean
	return Workspace:GetAttribute(RoundRules.ATTR_STATE) == "Match"
		and player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
		and player:GetAttribute(MoveRules.ATTR_FROZEN) ~= true
end

local function step(dt: number)
	clock += dt
	if next(visuals) ~= nil then
		-- the glow, the floor light and the ring change GUI_HZ times a second, not every frame (each change redraws
		-- the coin's floor picture and glow)
		guiSince += dt
		local guiDue = guiSince >= 1 / GUI_HZ
		if guiDue then
			guiSince = 0
		end
		-- once in a while: which coins are near your camera (only those keep their dust and twinkles)
		nearCheck -= dt
		if nearCheck <= 0 then
			nearCheck = 0.5
			local camera = Workspace.CurrentCamera
			local eye = if camera then camera.CFrame.Position else Vector3.zero
			for _, v in visuals do
				local near = (v.spot - eye).Magnitude < C.FAR
				if near ~= v.near then
					setNear(v, near)
				end
			end
		end

		-- your own pick-ups
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local picking = root ~= nil and canPickUp()

		table.clear(moveParts)
		table.clear(moveFrames)
		local pulseClock = clock * 2.4
		for id, v in visuals do
			v.t += dt
			local scale, squash, extraSpin, lift = 1, 1, 0, 0
			local state = v.state
			if state == "spawn" then
				local u = math.min(1, v.t / C.SPAWN_TIME)
				scale = elastic(u)
				extraSpin = 22 * (1 - u) * (1 - u)
				if u >= 1 then
					v.state = "idle"
				end
			elseif state == "snap" then
				local u = math.min(1, v.t / C.SNAP_TIME)
				scale = if u < 0.35 then 1 + 0.3 * (u / 0.35) else 1.3 * (1 - (u - 0.35) / 0.65) ^ 2
				squash = 0.8
				extraSpin = 26
				lift = 0.5 * u
				if u >= 1 then
					release(v)
					continue
				end
			elseif state == "drop" then
				v.fallSpeed += 60 * dt
				v.fall -= v.fallSpeed * dt
				extraSpin = 8
				scale = 1 - 0.6 * math.min(1, v.t / DROP_TIME)
				if v.t >= DROP_TIME then
					release(v)
					continue
				end
			elseif state == "vanish" then
				local u = math.min(1, v.t / VANISH_TIME)
				scale = (1 - u) * (1 + 0.2 * math.sin(u * math.pi))
				extraSpin = 18
				if u >= 1 then
					release(v)
					continue
				end
			end
			v.angle += (TURN + extraSpin) * dt
			local bob = math.sin(clock * C.BOB_SPEED + v.phase) * C.BOB
			local position = v.spot + Vector3.new(0, C.HOVER + bob + lift + v.fall, 0)
			if state == "snap" and v.target then
				position = position:Lerp(v.target :: Vector3, math.min(1, v.t / C.SNAP_TIME) * 0.55)
			end
			local frame = CFrame.new(position)
				* CFrame.Angles(0, v.angle, 0)
				* CFrame.Angles(0, 0, math.rad(C.TILT) * math.sin(clock * 1.3 + v.phase))
			setScale(v, scale, squash)
			for i, part in v.parts do
				table.insert(moveParts, part)
				table.insert(moveFrames, frame * v.offsets[i])
			end

			if state == "idle" or state == "spawn" then
				-- the glow breathes with the bob; the floor light follows the height; the ring turns
				if v.near and (guiDue or state == "spawn") then
					local pulse = 0.5 + 0.5 * math.sin(pulseClock + v.phase)
					local shown = math.min(scale, 1)
					v.glowImage.ImageTransparency = 1 - (0.42 + 0.2 * pulse) * shown
					local across = 3 + 0.35 * pulse
					v.glow.Size = UDim2.fromScale(across, across)
					v.pool.ImageTransparency = 1 - math.clamp((0.42 - bob * 0.5) * shown, 0, 1)
					v.ring.Rotation = math.deg(clock * 0.6 + v.phase)
					v.ring.ImageTransparency = 1 - (0.4 + 0.2 * pulse) * shown
				end
				if v.near then
					-- a twinkle on the rim now and then
					v.nextTwinkle -= dt
					if v.nextTwinkle <= 0 then
						v.nextTwinkle = 0.35 + rng:NextNumber() * 0.55
						local a = rng:NextNumber() * math.pi * 2
						v.twinkleAt.Position =
							Vector3.new(math.cos(a) * 0.97, math.sin(a) * 0.97, (rng:NextNumber() - 0.5) * 0.2)
						v.twinkle:Emit(1)
					end
				end
				-- did you touch it?
				if picking and root then
					local body = root.Position
					if
						CoinRules.flatDistance(body, v.spot) <= C.RADIUS
						and math.abs(body.Y - (v.spot.Y + ROOT_HEIGHT)) < 6
					then
						claim(v, root)
					end
				end
			end
		end
		if #moveParts > 0 then
			Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	-- a pick-up the server didn't give (someone else was first, or it was too far): the coin comes back
	for id, at in claimed do
		if os.clock() - at > CLAIM_WAIT then
			claimed[id] = nil
			mine[id] = nil
			local spot = folder and folder:GetAttribute(CoinRules.key(id))
			if typeof(spot) == "Vector3" and not visuals[id] then
				add(id, spot, true)
			end
		end
	end

	stepEffects(dt)
end

function CoinFx.start()
	local made = Instance.new("Folder")
	made.Name = "CoinFx"
	made.Parent = Workspace
	fxFolder = made
	buildBursts()
	task.spawn(function()
		loadTemplate()
		local found = ReplicatedStorage:WaitForChild(CoinRules.FOLDER)
		folder = found :: Folder
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local r = remotes:WaitForChild(CoinRules.REMOTE) :: RemoteEvent
		remote = r
		-- a few spare coins made ahead, so the first ones don't hitch
		for _ = 1, 6 do
			local v = newVisual()
			table.insert(spare, v)
		end
		-- coins already on the map (joining mid-round): no pop
		for key, value in (folder :: Folder):GetAttributes() do
			local id = CoinRules.idOf(key)
			if id and typeof(value) == "Vector3" then
				add(id, value, true)
			end
		end
		(folder :: Folder).AttributeChanged:Connect(onAttribute)
		r.OnClientEvent:Connect(function(action, a, b, c)
			if action == "take" then
				onTake(a, b, c)
			elseif action == "drop" then
				onDrop(a)
			elseif action == "clear" then
				onClear()
			end
		end)
		RunService.PreRender:Connect(step)
	end)
end

return CoinFx
