--!strict
-- The scenery round the arena (owner 2026-11-10: "like the back ground too", the neon sky city in the owner's
-- pictures), far out in the purple sunset sky (Lighting > Sky, Config.Neon.SKY), drawn on this screen only:
--   * glowing highways on tall pillars that fade down into the clouds, with cyan edge lights, pink light under their
--     edges, signs of amber chevrons marching along their sides and streaks of light racing along them;
--   * floating cities on rock islands with pink neon rims: dark towers with neon window strips, bands and blinking
--     antennas;
--   * over the biggest city, a huge glowing halo ring with lights running round it, and a cyan beam of light;
--   * small floating platforms with cyan rims bobbing round the arena, and now and then a pink shooting star.
-- Everything is plain parts (no collisions, no shadows, nothing anyone can touch) built a few at a time when the game
-- starts, so joining doesn't hitch; only a few dozen of them move each frame (the light streaks, the ring's lights,
-- the platforms, the shooting star) and the signs' arrows slide, so it stays at 60 FPS. Where everything stands is
-- laid out here (the arena's middle is Config.Arena.CENTER, its edges 125 studs out); Claude's picks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local NEON = Config.Neon

local Backdrop = {}

local rng = Random.new(20261110) -- the same city every time

local CYAN = Color3.fromHex("35E9FF")
local PINK = Color3.fromHex("FF3D9A")
local MAGENTA = Color3.fromHex("FF5FD2")
local VIOLET = Color3.fromHex("B26BFF")
local BLUE = Color3.fromHex("5A7DFF")
local AMBER = Color3.fromHex("FFB52E")
local LAVENDER = Color3.fromHex("ECD6FF")
local DECK = Color3.fromHex("1C1838")
local ROCK = Color3.fromHex("2A1A4A")
local TOWER = Color3.fromHex("151A40")
local SIGN = Color3.fromHex("0C0A1C")

local PARTS_A_FRAME = 60 -- parts built before letting a frame go by
local SIGN_PPS = 4 -- pixels a stud on the signs' surfaces

local folder: Folder = nil :: any
local built = 0

-- An anchored part nothing can touch, that casts no shadow.
local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	built += 1
	if built % PARTS_A_FRAME == 0 then
		task.wait()
	end
	return p
end

local function neon(name: string, size: Vector3, cframe: CFrame, color: Color3, transparency: number?): Part
	local p = part(name, size, cframe, color, Enum.Material.Neon)
	p.Transparency = transparency or 0
	return p
end

-- A cylinder standing up (Roblox's cylinders lie along x).
local function disc(name: string, diameter: number, height: number, at: Vector3, color: Color3, material: Enum.Material?): Part
	local p = part(name, Vector3.new(height, diameter, diameter), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

---------------------------------------------------------------- things that move

type Streak = { part: BasePart, from: Vector3, along: Vector3, length: number, speed: number, at: number }
type Bobber = { part: BasePart, base: CFrame, phase: number, height: number }
type Runner = { part: BasePart, angle: number, speed: number }
type Scroller = { image: ImageLabel, tile: number, speed: number, at: number }
type Blinker = { part: BasePart, phase: number }

local streaks: { Streak } = {}
local bobbers: { Bobber } = {}
local ringLights: { Runner } = {}
local scrollers: { Scroller } = {}
local blinkers: { Blinker } = {}
local ring: { center: CFrame, radius: number }? = nil
local beams: { BasePart } = {}

---------------------------------------------------------------- the highways

-- A sign along a highway's side: dark, a pink neon edge, amber chevrons marching along it (a SurfaceGui that ignores
-- the light, so it glows at dusk).
local function sign(cframe: CFrame, length: number, tall: number, face: Enum.NormalId)
	local board = part("Sign", Vector3.new(length, tall, 1), cframe, SIGN)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Chevrons"
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 2.2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PPS
	gui.ClipsDescendants = true
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = SIGN
	back.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = PINK
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = back
	back.Parent = gui
	-- big chevrons, as tall as the sign, a little apart
	local tileTall = tall * SIGN_PPS * 1.05
	local tile = tileTall * 0.62
	local image = Instance.new("ImageLabel")
	image.Name = "Arrows"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0, 0.5)
	image.Position = UDim2.fromScale(0, 0.5)
	image.Size = UDim2.new(1, tile * 2, 0, tileTall)
	image.Image = NEON.CHEVRON_AMBER
	image.ScaleType = Enum.ScaleType.Tile
	image.TileSize = UDim2.fromOffset(tile, tileTall)
	image.Parent = back
	gui.Parent = board
	table.insert(scrollers, { image = image, tile = tile, speed = 1.1 + rng:NextNumber() * 0.4, at = rng:NextNumber() })
end

-- A highway from `from` to `to` (its deck's top middle at each end), `wide` studs across, signs on the side that faces
-- `toward`.
local function highway(from: Vector3, to: Vector3, wide: number, toward: Vector3)
	local along = (to - from).Unit
	local length = (to - from).Magnitude
	local side = along:Cross(Vector3.yAxis).Unit -- one side of the deck
	if side:Dot(toward - from) < 0 then
		side = -side -- the side facing `toward`
	end
	local look = CFrame.fromMatrix(Vector3.zero, along, Vector3.yAxis)
	local segment = 300
	local count = math.ceil(length / segment)
	local each = length / count
	local deckThick = 3
	for i = 1, count do
		local middle = from + along * (each * (i - 0.5))
		local deckAt = CFrame.new(middle - Vector3.new(0, deckThick / 2, 0)) * look.Rotation
		part("Deck", Vector3.new(each + 0.2, deckThick, wide), deckAt, DECK, Enum.Material.Metal)
		for s = -1, 1, 2 do
			local edge = side * (s * wide / 2)
			-- a low dark rail with cyan lights along its top, and pink light along the deck's underside
			part("Rail", Vector3.new(each, 2.4, 0.6), CFrame.new(middle + edge * 0.98 + Vector3.new(0, 1.2, 0)) * look.Rotation, DECK)
			neon("EdgeLight", Vector3.new(each, 0.5, 0.7), CFrame.new(middle + edge * 0.98 + Vector3.new(0, 2.5, 0)) * look.Rotation, CYAN)
			neon("UnderGlow", Vector3.new(each, 0.6, 0.6), CFrame.new(middle + edge + Vector3.new(0, -deckThick - 0.3, 0)) * look.Rotation, PINK)
		end
		-- a sign on the side that faces the arena
		local signAt = CFrame.fromMatrix(middle + side * (wide / 2 + 0.8) + Vector3.new(0, -deckThick / 2 - 1, 0), along, Vector3.yAxis)
		-- the board's +z is along:Cross(y); its face towards `side` is Back (+z) or Front (-z)
		local face = if along:Cross(Vector3.yAxis):Dot(side) > 0 then Enum.NormalId.Back else Enum.NormalId.Front
		sign(signAt, each * 0.45, 11, face)
		-- a pillar at every other joint, fading down into the clouds
		if i % 2 == 1 then
			local base = from + along * (each * (i - 1) + 4) - Vector3.new(0, deckThick, 0)
			local heights = { 160, 160, 200 }
			local fades = { 0, 0.35, 0.7 }
			local top = base
			for k = 1, 3 do
				local h = heights[k]
				local at = CFrame.new(top - Vector3.new(0, h / 2, 0)) * look.Rotation
				local pillar = part("Pillar", Vector3.new(9, h, 9), at, DECK, Enum.Material.Metal)
				pillar.Transparency = fades[k]
				neon("PillarLight", Vector3.new(1, h, 0.4), at * CFrame.new(0, 0, side:Dot(look.ZVector) * 4.6), CYAN, math.min(fades[k] + 0.1, 0.9))
				top -= Vector3.new(0, h, 0)
			end
		end
	end
	-- streaks of light racing along it, both ways
	for k = 1, 6 do
		local lane = (if k % 2 == 0 then 1 else -1) * wide * 0.22
		local color = if k % 3 == 0 then Color3.new(1, 1, 1) elseif k % 2 == 0 then PINK else CYAN
		local streak = neon("Streak", Vector3.new(9, 0.7, 1.4), CFrame.new(from), color)
		local dir = if k % 2 == 0 then 1 else -1
		table.insert(streaks, {
			part = streak,
			from = (if dir > 0 then from else to) + side * lane + Vector3.new(0, 0.6, 0),
			along = along * dir,
			length = length,
			speed = 120 + rng:NextNumber() * 60,
			at = rng:NextNumber() * length,
		})
	end
end

---------------------------------------------------------------- the cities

-- A floating island `radius` studs across its top, at `at` (its top's middle), with towers in `palette`.
local function city(at: Vector3, radius: number, towers: number, tallest: number, palette: { Color3 })
	disc("Island", radius * 2, 14, at - Vector3.new(0, 7, 0), ROCK, Enum.Material.Slate)
	disc("Island", radius * 1.5, 45, at - Vector3.new(0, 14 + 22, 0), ROCK, Enum.Material.Slate)
	disc("Island", radius * 0.8, 70, at - Vector3.new(0, 59 + 35, 0), ROCK, Enum.Material.Slate)
	local rim = disc("Rim", radius * 2 + 4, 1.6, at - Vector3.new(0, 1, 0), MAGENTA, Enum.Material.Neon)
	rim.Transparency = 0.1
	for _ = 1, towers do
		local r = radius * 0.78 * math.sqrt(rng:NextNumber())
		local angle = rng:NextNumber() * math.pi * 2
		local spot = at + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		-- taller towards the middle
		local tall = tallest * (0.25 + 0.75 * (1 - r / radius) * rng:NextNumber(0.5, 1))
		local wide = rng:NextNumber(14, 34)
		local deep = wide * rng:NextNumber(0.7, 1.2)
		local yaw = CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
		local body = CFrame.new(spot + Vector3.new(0, tall / 2, 0)) * yaw
		part("Tower", Vector3.new(wide, tall, deep), body, TOWER)
		local color = palette[rng:NextInteger(1, #palette)]
		-- window strips up two faces
		neon("Windows", Vector3.new(wide * 0.12, tall * 0.86, 0.3), body * CFrame.new(-wide * 0.22, 0, -deep / 2 - 0.1), color)
		neon("Windows", Vector3.new(0.3, tall * 0.86, deep * 0.12), body * CFrame.new(wide / 2 + 0.1, 0, deep * 0.2), color)
		-- a cap, sometimes a band round it, sometimes an antenna with a blinking light
		neon("Cap", Vector3.new(wide + 0.6, 1.2, deep + 0.6), body * CFrame.new(0, tall / 2 + 0.6, 0), color)
		if rng:NextNumber() < 0.5 then
			neon("Band", Vector3.new(wide + 0.5, 1.4, deep + 0.5), body * CFrame.new(0, tall * rng:NextNumber(0.1, 0.35), 0), palette[rng:NextInteger(1, #palette)])
		end
		if rng:NextNumber() < 0.35 then
			neon("Antenna", Vector3.new(0.7, 26, 0.7), body * CFrame.new(0, tall / 2 + 13, 0), LAVENDER)
			local light = neon("Blink", Vector3.new(2.4, 2.4, 2.4), body * CFrame.new(0, tall / 2 + 27, 0), PINK)
			table.insert(blinkers, { part = light, phase = rng:NextNumber() })
		end
	end
end

-- The halo ring over the big city: `radius` studs, tipped towards the arena, glowing lavender with a violet haze, and
-- bright lights running round it.
local function halo(center: Vector3, radius: number)
	local tip = CFrame.new(center) * CFrame.Angles(math.rad(14), 0, math.rad(6))
	local count = 40
	local step = math.pi * 2 / count
	local length = 2 * radius * math.sin(step / 2) + 1.5
	for i = 0, count - 1 do
		local angle = i * step
		local around = tip * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -radius)
		neon("Halo", Vector3.new(length, 8, 5), around, LAVENDER)
		neon("HaloHaze", Vector3.new(length + 2, 20, 2), around * CFrame.new(0, 0, -3), VIOLET, 0.72)
	end
	ring = { center = tip, radius = radius }
	for i = 1, 4 do
		local light = neon("HaloLight", Vector3.new(16, 11, 7), tip, Color3.new(1, 1, 1))
		table.insert(ringLights, { part = light, angle = i * math.pi / 2, speed = 0.22 })
	end
end

-- A beam of light from the big city up into the sky.
local function beam(at: Vector3)
	local height = 1900
	local core = disc("Beam", 14, height, at + Vector3.new(0, height / 2, 0), Color3.fromHex("8FF6FF"), Enum.Material.Neon)
	core.Transparency = 0.35
	local haze = disc("BeamHaze", 46, height, at + Vector3.new(0, height / 2, 0), CYAN, Enum.Material.Neon)
	haze.Transparency = 0.86
	table.insert(beams, core)
	table.insert(beams, haze)
end

-- A small floating platform with a cyan rim and two lamps, bobbing.
local function platform(at: Vector3, diameter: number)
	local phase = rng:NextNumber() * math.pi * 2
	local height = rng:NextNumber(2, 5)
	local function bob(p: BasePart)
		table.insert(bobbers, { part = p, base = p.CFrame, phase = phase, height = height })
	end
	bob(disc("Platform", diameter, 4, at, DECK, Enum.Material.Metal))
	bob(disc("PlatformRim", diameter + 1.5, 1, at + Vector3.new(0, 1.6, 0), CYAN, Enum.Material.Neon))
	bob(disc("PlatformGlow", diameter * 0.55, 1, at - Vector3.new(0, 2.4, 0), MAGENTA, Enum.Material.Neon))
	for k = 1, 2 do
		local angle = k * math.pi + phase
		local lamp = at + Vector3.new(math.cos(angle) * diameter * 0.3, 3.5, math.sin(angle) * diameter * 0.3)
		bob(neon("Lamp", Vector3.new(1.6, 3, 1.6), CFrame.new(lamp), LAVENDER))
	end
end

---------------------------------------------------------------- the shooting star

local meteor: BasePart? = nil
local meteorFrom = Vector3.zero
local meteorDir = Vector3.xAxis
local meteorAt = -math.huge
local nextMeteor = 4
local METEOR_TIME = 0.9
local METEOR_SPEED = 1400

local function launchMeteor(now: number)
	local p = meteor
	if not p then
		return
	end
	local angle = rng:NextNumber() * math.pi * 2
	local distance = rng:NextNumber(1400, 1900)
	meteorFrom = Config.Arena.CENTER + Vector3.new(math.cos(angle) * distance, rng:NextNumber(600, 900), math.sin(angle) * distance)
	local sideways = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * (if rng:NextNumber() < 0.5 then 1 else -1)
	meteorDir = (sideways + Vector3.new(0, -0.45, 0)).Unit
	meteorAt = now
	nextMeteor = now + rng:NextNumber(5, 10)
end

---------------------------------------------------------------- every frame

local function step(dt: number)
	local now = os.clock()
	for _, s in streaks do
		s.at = (s.at + s.speed * dt) % s.length
		s.part.CFrame = CFrame.lookAt(s.from + s.along * s.at, s.from + s.along * (s.at + 1)) * CFrame.Angles(0, math.rad(90), 0)
	end
	for _, b in bobbers do
		b.part.CFrame = b.base + Vector3.new(0, math.sin(now * 0.7 + b.phase) * b.height, 0)
	end
	local halo = ring
	if halo then
		for _, light in ringLights do
			light.angle += light.speed * dt
			light.part.CFrame = halo.center * CFrame.Angles(0, light.angle, 0) * CFrame.new(0, 0, -halo.radius - 0.5)
		end
	end
	for _, s in scrollers do
		s.at = (s.at + s.speed * dt) % 1
		s.image.Position = UDim2.new(0, -s.tile * (1 - s.at), 0.5, 0)
	end
	for _, b in blinkers do
		b.part.Transparency = if (now * 0.9 + b.phase) % 1 < 0.5 then 0 else 0.85
	end
	-- the beam breathes
	if beams[1] then
		local breath = 0.5 + 0.5 * math.sin(now * 1.3)
		beams[1].Transparency = 0.3 + 0.15 * breath
		if beams[2] then
			beams[2].Transparency = 0.84 + 0.06 * breath
		end
	end
	-- a shooting star now and then
	local p = meteor
	if p then
		if now >= nextMeteor then
			launchMeteor(now)
		end
		local t = now - meteorAt
		if t < METEOR_TIME then
			local head = meteorFrom + meteorDir * (METEOR_SPEED * t)
			p.CFrame = CFrame.lookAt(head, head + meteorDir)
			p.Transparency = math.clamp(t / METEOR_TIME, 0, 1) ^ 2
		elseif p.Transparency < 1 then
			p.Transparency = 1
		end
	end
end

---------------------------------------------------------------- start

-- The purple sunset sky, on this screen (the place's Lighting > Sky is set to it too, default.project.json; this makes
-- sure every screen shows it whatever the place file has).
local function useSky()
	local Lighting = game:GetService("Lighting")
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		local made = Instance.new("Sky")
		made.Parent = Lighting
		sky = made
	end
	local s = sky :: Sky
	s.SkyboxBk = NEON.SKY.Bk
	s.SkyboxDn = NEON.SKY.Dn
	s.SkyboxFt = NEON.SKY.Ft
	s.SkyboxLf = NEON.SKY.Lf
	s.SkyboxRt = NEON.SKY.Rt
	s.SkyboxUp = NEON.SKY.Up
	s.CelestialBodiesShown = false
end

function Backdrop.start()
	useSky()
	folder = Instance.new("Folder")
	folder.Name = "Backdrop"
	folder.Parent = Workspace
	local center = Config.Arena.CENTER
	task.spawn(function()
		-- the highways: one low along the far side, one higher crossing over it on the right, one far behind
		highway(center + Vector3.new(-1500, -32, -360), center + Vector3.new(1500, -32, -360), 26, center)
		highway(center + Vector3.new(440, 16, 1500), center + Vector3.new(440, 16, -1500), 26, center)
		highway(center + Vector3.new(-1500, -80, 640), center + Vector3.new(700, -80, 1480), 22, center)
		-- the big city with its halo ring and beam, out past the far highway where the sun went down; three smaller
		-- ones round the rest of the sky
		local big = center + Vector3.new(-80, -50, -1250)
		city(big, 230, 18, 420, { CYAN, BLUE, MAGENTA, VIOLET })
		halo(big + Vector3.new(0, 430, 0), 420)
		beam(big + Vector3.new(0, 40, 0))
		city(center + Vector3.new(1450, -120, 250), 170, 12, 300, { MAGENTA, PINK, VIOLET })
		city(center + Vector3.new(-1380, -95, -320), 160, 12, 280, { CYAN, BLUE, VIOLET })
		city(center + Vector3.new(260, -160, 1550), 200, 14, 340, { CYAN, MAGENTA, LAVENDER })
		-- floating platforms round the arena
		for k = 1, 6 do
			local angle = (k / 6) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
			local distance = rng:NextNumber(260, 420)
			local at = center + Vector3.new(math.cos(angle) * distance, rng:NextNumber(-70, 10), math.sin(angle) * distance)
			platform(at, rng:NextNumber(34, 60))
		end
		local star = neon("ShootingStar", Vector3.new(2.2, 2.2, 140), CFrame.new(0, -5000, 0), Color3.fromHex("FF8AD8"))
		star.Transparency = 1
		meteor = star
		RunService.PreRender:Connect(step)
	end)
end

return Backdrop
