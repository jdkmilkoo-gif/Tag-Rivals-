--!strict
-- The map being cut (design notes, Map size; owner 2026-11-09: "make the game warn 3 seconds before the map shrinks.
-- and whatever part of the map that shrinks that area should be red. and change the shrinking function as just like
-- cutting off a that part of the map"), drawn on this screen only:
--   * for the 3 s before each cut, the strip round the edge that's about to go glows red, pulsing faster as the cut
--     gets near, with a bright red line where the cut will fall and white arrows on it marching inward; players in
--     the round see the neon "MAP SHRINKING IN 3" banner count down under the timer (owner 2026-11-10: "Add these",
--     from the owner's picture: a red neon plate with chevrons either side, and "YOU'RE ON THE RED! MOVE IN!" under it
--     for anyone standing on the red);
--   * standing on the red flashes your screen's edges red;
--   * at the cut, the red strip breaks into pieces that tip over the edge and fall into the clouds, and the cut line
--     flashes white. (The server cuts the floor at the same moment; anyone still on the red falls with it and a runner
--     becomes a chaser, owner 2026-11-10: "make the red let players fall and become tagger"; TagController shakes the
--     camera.)
-- Everything is built once when the game starts (the red strip, its lines, the cut line's flash and a pool of
-- pieces) and only moved, shown and hidden after that, so nothing is made mid-round (a frame hitch at the first
-- warning was reported, 2026-11-09).
-- The server says a cut is coming with two Workspace attributes (RoundRules.ATTR_CUT_RADIUS and ATTR_CUT_AT), so a
-- screen that joins mid-warning shows it too, and says it happened with the Round remote's "shrink" (the shrink's
-- count, the half-side before, the half-side after).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)
local TagFx = require(script.Parent.TagFx)

local A = Config.Arena
local S = Config.Shrink
local NEON = Config.Neon

local ShrinkFx = {}

local player = Players.LocalPlayer
local RoundRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent

local RED = Color3.fromHex(S.CUT_COLOR)
local HOT = Color3.fromHex("FFF1F1") -- the cut line's white-hot flash
local WHITE = Color3.new(1, 1, 1)
local FLOOR = Color3.fromHex(A.FLOOR_COLOR)
local LINE = 0.45 -- studs across the bright line where the cut falls
local LIFT = 0.06 -- studs the red's top sits over the floor's top
local GLOW_THICK = 0.1 -- studs
local GLOW_OFFSET = CFrame.new(0, A.THICKNESS / 2 + LIFT - GLOW_THICK / 2, 0) -- a piece's red, from its middle
local GRAVITY = 80 -- studs/s² the cut pieces fall with
-- The banner sits just under the timer, first in the pop-ups' stack (HudLayout), drawn at the pop-ups' size (smaller
-- where it would reach the tag feed or the coin counter on a phone).
local TITLE_TEXT = 34
local HIDDEN = CFrame.new(0, -1000, 0) -- where pooled parts wait, see-through
local FLASH_TIME = 0.6 -- s the cut line's white-hot flash takes to fade through red
-- pieces built ahead: enough for the first cut of a full square (the strip breaks into pieces about PIECE long)
local POOL = 4 * math.ceil(A.SIZE / S.PIECE) + 4
local SUB_TEXT = 22
-- the banner at full size, in pixels: the plate's picture is 1024 x 200 with room round it for the glow, so drawn at
-- 512 x 100 its plate is about 478 x 66
local PLATE_WIDE, PLATE_TALL = 512, 100
local PLATE_SEEN_WIDE, PLATE_SEEN_TALL = 478, 66
local CHEVRON_WIDE, CHEVRON_TALL = 64, 80 -- a chevron's picture (128 x 160, the arrow about 60% of it)
local CHEVRON_STEP = 30 -- pixels between the chevrons of a group
local CHEVRONS = 3 -- either side
local BANNER_WIDE = PLATE_SEEN_WIDE + 2 * (6 + CHEVRON_STEP * (CHEVRONS - 1) + CHEVRON_WIDE * 0.6)
local SUB_TOP = (PLATE_TALL + PLATE_SEEN_TALL) / 2 + 2 -- the "YOU'RE ON THE RED!" line, under the plate
local WARN_TALL = SUB_TOP + SUB_TEXT + 6 - (PLATE_TALL - PLATE_SEEN_TALL) / 2
local RED_HEX = S.CUT_COLOR
-- the white arrows on the red strip: pixels a stud on their surfaces, and the size of one arrow (studs)
local ARROW_PPS = 8
local ARROW_TILE = Vector2.new(5, 6.25)
local ARROW_SPEED = 0.7 -- tiles a second they march inward (faster as the cut nears)

-- A flat box round the square's middle: its middle's offset, its size along x and z, and which way is out.
type Box = { offset: Vector3, sizeX: number, sizeZ: number, out: Vector3 }

-- A piece of the cut strip on its way down.
type Piece = {
	slab: BasePart,
	glow: BasePart,
	grid: Texture,
	start: Vector3,
	out: Vector3,
	axis: Vector3, -- it tips over the edge round this
	hinge: Vector3, -- its inner bottom edge, from its middle (it tips over round this)
	tip: number, -- radians/s it starts tipping at
	turn: number, -- radians/s it turns as it falls
	push: number, -- studs/s it drifts outward
	delay: number, -- s before it lets go
	born: number,
}

local fxFolder: Folder? = nil
local strips: { BasePart } = {} -- the red strip's four sides
-- white arrows on the red, one surface for each side, turned so they point inward
type Arrows = { part: BasePart, gui: SurfaceGui, image: ImageLabel, tile: number }
local arrows: { Arrows } = {}
local lines: { BasePart } = {} -- the red line where the cut will fall
local flashes: { BasePart } = {} -- the cut line's white-hot flash
local spare: { Piece } = {} -- pieces waiting, hidden
local pieces: { Piece } = {} -- pieces falling
local bandOuter: number? = nil -- the half-sides the red strip is drawn for (nil: hidden)
local bandInner: number? = nil
local bandCenter = Vector3.zero
local bandAt = 0
local pulse = 0
local flashAt = -math.huge
local lastFlash = -math.huge
local rng = Random.new()

local function folder(): Folder
	local existing = fxFolder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "ShrinkFx"
	made.Parent = Workspace
	fxFolder = made
	return made
end

local function flatPart(name: string, color: Color3, material: Enum.Material, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	return part
end

-- The strip round the edge between the half-sides `outer` (the edge now) and `inner` (the edge after the cut): the
-- far and near sides run the whole width, the left and right ones fit between them.
local function bandBoxes(outer: number, inner: number): { Box }
	local width = outer - inner
	local mid = (outer + inner) / 2
	return {
		{ offset = Vector3.new(0, 0, mid), sizeX = outer * 2, sizeZ = width, out = Vector3.zAxis },
		{ offset = Vector3.new(0, 0, -mid), sizeX = outer * 2, sizeZ = width, out = -Vector3.zAxis },
		{ offset = Vector3.new(mid, 0, 0), sizeX = width, sizeZ = inner * 2, out = Vector3.xAxis },
		{ offset = Vector3.new(-mid, 0, 0), sizeX = width, sizeZ = inner * 2, out = -Vector3.xAxis },
	}
end

-- The line where the cut falls, round the half-side `inner`.
local function lineBoxes(inner: number): { Box }
	local long = inner * 2 + LINE
	return {
		{ offset = Vector3.new(0, 0, inner), sizeX = long, sizeZ = LINE, out = Vector3.zAxis },
		{ offset = Vector3.new(0, 0, -inner), sizeX = long, sizeZ = LINE, out = -Vector3.zAxis },
		{ offset = Vector3.new(inner, 0, 0), sizeX = LINE, sizeZ = long, out = Vector3.xAxis },
		{ offset = Vector3.new(-inner, 0, 0), sizeX = LINE, sizeZ = long, out = -Vector3.xAxis },
	}
end

---------------------------------------------------------------- the red warning strip

-- A see-through part waiting out of sight.
local function hiddenPart(name: string, color: Color3, material: Enum.Material): Part
	local part = flatPart(name, color, material, Vector3.one, HIDDEN)
	part.Transparency = 1
	part.Parent = folder()
	return part
end

-- Puts `parts` (one for each of `boxes`) round `center` at height `y`.
local function lay(parts: { BasePart }, boxes: { Box }, center: Vector3, y: number, thick: number)
	for i, box in boxes do
		local part = parts[i]
		part.Size = Vector3.new(box.sizeX, thick, box.sizeZ)
		part.CFrame = CFrame.new(center.X + box.offset.X, y, center.Z + box.offset.Z)
	end
end

-- A see-through part with a surface of white arrows on its top that march along it (turned inward by showBand).
local function makeArrows(): Arrows
	local part = hiddenPart("CutArrows", WHITE, Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Arrows"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ARROW_PPS
	gui.ClipsDescendants = true
	gui.Enabled = false
	gui.Adornee = part
	local tile = ARROW_TILE.X * ARROW_PPS
	local image = Instance.new("ImageLabel")
	image.Name = "Chevrons"
	image.BackgroundTransparency = 1
	image.Image = NEON.CHEVRON_WHITE
	image.ImageColor3 = Color3.fromHex("FFE6EC")
	image.ScaleType = Enum.ScaleType.Tile
	image.TileSize = UDim2.fromOffset(tile, ARROW_TILE.Y * ARROW_PPS)
	image.Size = UDim2.new(1, tile * 2, 1, 0)
	image.Parent = gui
	gui.Parent = part
	return { part = part, gui = gui, image = image, tile = tile }
end

local function clearBand()
	for _, part in strips do
		part.Transparency = 1
	end
	for _, each in arrows do
		each.gui.Enabled = false
		each.part.CFrame = HIDDEN
	end
	for _, part in lines do
		part.Transparency = 1
	end
	bandOuter, bandInner = nil, nil
end

local function showBand(center: Vector3, outer: number, inner: number)
	local y = center.Y + LIFT - GLOW_THICK / 2
	local boxes = bandBoxes(outer, inner)
	lay(strips, boxes, center, y, GLOW_THICK)
	lay(lines, lineBoxes(inner), center, y + 0.02, GLOW_THICK + 0.04)
	-- the arrows: each side's surface turned so they point inward, across the strip (a top face's SurfaceGui runs
	-- its x along the part's -z, so the part looks inward: its -z is inward, its x runs along the strip)
	for i, box in boxes do
		local each = arrows[i]
		if each then
			local across = if math.abs(box.out.Z) > 0.5 then box.sizeZ else box.sizeX
			local along = if math.abs(box.out.Z) > 0.5 then box.sizeX else box.sizeZ
			local position = Vector3.new(center.X + box.offset.X, y + GLOW_THICK / 2 + 0.03, center.Z + box.offset.Z)
			each.part.Size = Vector3.new(along, 0.05, across)
			each.part.CFrame = CFrame.lookAt(position, position - box.out)
			each.gui.Enabled = true
		end
	end
	bandOuter, bandInner, bandCenter = outer, inner, center
	bandAt = os.clock()
	pulse = 0
end

---------------------------------------------------------------- the cut

-- A piece of floor (with the grid) and its red top, hidden, ready to fall.
local function makePiece(): Piece
	local slab = hiddenPart("CutPiece", FLOOR, A.FLOOR_MATERIAL)
	local grid = Instance.new("Texture")
	grid.Name = "Grid"
	grid.Texture = A.FLOOR_TEXTURE
	grid.Face = Enum.NormalId.Top
	grid.StudsPerTileU = A.FLOOR_TILE
	grid.StudsPerTileV = A.FLOOR_TILE
	grid.Color3 = Color3.new(0, 0, 0)
	grid.Transparency = 1
	grid.Parent = slab
	return {
		slab = slab,
		glow = hiddenPart("CutGlow", RED, Enum.Material.Neon),
		grid = grid,
		start = Vector3.zero,
		out = Vector3.zAxis,
		axis = Vector3.xAxis,
		hinge = Vector3.zero,
		tip = 0,
		turn = 0,
		push = 0,
		delay = 0,
		born = 0,
	}
end

local function putAway(piece: Piece)
	piece.slab.Transparency = 1
	piece.glow.Transparency = 1
	piece.grid.Transparency = 1
	piece.slab.CFrame = HIDDEN
	piece.glow.CFrame = HIDDEN
	table.insert(spare, piece)
end

-- The strip between `outer` and `inner` breaks into pieces that tip over the edge and fall away.
local function breakOff(center: Vector3, outer: number, inner: number)
	local width = outer - inner
	if width <= 0.05 then
		return
	end
	local now = os.clock()
	local y = center.Y - A.THICKNESS / 2
	for _, box in bandBoxes(outer, inner) do
		local alongX = math.abs(box.out.Z) > 0.5 -- the far and near strips run along x
		local length = if alongX then box.sizeX else box.sizeZ
		local count = math.max(1, math.round(length / S.PIECE))
		local each = length / count
		for i = 1, count do
			local along = -length / 2 + each * (i - 0.5)
			local offset = box.offset + (if alongX then Vector3.new(along, 0, 0) else Vector3.new(0, 0, along))
			local size = if alongX then Vector3.new(each, A.THICKNESS, width) else Vector3.new(width, A.THICKNESS, each)
			local start = Vector3.new(center.X + offset.X, y, center.Z + offset.Z)
			local piece = table.remove(spare) or makePiece() -- the pool ran out (or isn't built yet): one more
			piece.slab.Size = size
			piece.slab.CFrame = CFrame.new(start)
			piece.slab.Transparency = 0
			piece.grid.Transparency = A.FLOOR_TEXTURE_TRANSPARENCY
			piece.glow.Size = Vector3.new(size.X, GLOW_THICK, size.Z)
			piece.glow.CFrame = CFrame.new(start) * GLOW_OFFSET
			piece.glow.Transparency = 0.3
			piece.start = start
			piece.out = box.out
			piece.axis = Vector3.yAxis:Cross(box.out)
			piece.hinge = -box.out * (width / 2) - Vector3.new(0, A.THICKNESS / 2, 0)
			piece.tip = math.rad(rng:NextNumber(50, 120))
			piece.turn = math.rad(rng:NextNumber(-25, 25))
			piece.push = rng:NextNumber(4, 11)
			piece.delay = rng:NextNumber(0, 0.14)
			piece.born = now
			table.insert(pieces, piece)
		end
	end
end

-- The line where the cut fell flashes white-hot and fades through red (stepFlash).
local function flashCutLine(center: Vector3, inner: number)
	lay(flashes, lineBoxes(inner), center, center.Y + LIFT - GLOW_THICK / 2 + 0.02, GLOW_THICK + 0.04)
	flashAt = os.clock()
end

local function stepFlash(now: number)
	if flashAt == -math.huge then
		return
	end
	local x = math.max((now - flashAt) / FLASH_TIME, 0)
	if x >= 1 then
		flashAt = -math.huge
		for _, part in flashes do
			part.Transparency = 1
			part.CFrame = HIDDEN
		end
		return
	end
	local color = HOT:Lerp(RED, x)
	for _, part in flashes do
		part.Transparency = x * x -- fades slowly, then fast
		part.Color = color
	end
end

local function stepPieces(now: number)
	for i = #pieces, 1, -1 do
		local piece = pieces[i]
		local t = now - piece.born - piece.delay
		if t >= S.FALL_TIME then
			table.remove(pieces, i)
			putAway(piece)
		elseif t > 0 then
			local position = piece.start + piece.out * (piece.push * t) - Vector3.new(0, 0.5 * GRAVITY * t * t, 0)
			local tipped = CFrame.new(piece.hinge)
				* CFrame.fromAxisAngle(piece.axis, piece.tip * t + 2 * t * t)
				* CFrame.new(-piece.hinge)
			local cframe = CFrame.new(position) * CFrame.Angles(0, piece.turn * t, 0) * tipped
			piece.slab.CFrame = cframe
			piece.glow.CFrame = cframe * GLOW_OFFSET
			piece.glow.Transparency = math.clamp(0.3 + t / 0.7, 0.3, 1)
			local fade = math.clamp((t - (S.FALL_TIME - 0.45)) / 0.45, 0, 1)
			piece.slab.Transparency = fade
			piece.grid.Transparency = A.FLOOR_TEXTURE_TRANSPARENCY + (1 - A.FLOOR_TEXTURE_TRANSPARENCY) * fade
		end
	end
end

---------------------------------------------------------------- start

function ShrinkFx.start()
	-- the parts, built once (the pieces a few at a time, so joining doesn't hitch either)
	for _ = 1, 4 do
		table.insert(strips, hiddenPart("CutWarning", RED, Enum.Material.Neon))
		table.insert(lines, hiddenPart("CutLine", RED, Enum.Material.Neon))
		table.insert(flashes, hiddenPart("CutFlash", HOT, Enum.Material.Neon))
		table.insert(arrows, makeArrows())
	end
	task.spawn(function()
		for i = 1, POOL do
			table.insert(spare, makePiece())
			if i % 8 == 0 then
				task.wait()
			end
		end
	end)

	-- the banner under the timer (over the tag feed, like the other pop-ups)
	local gui = PlasticUi.screen("TagRivalsShrinkWarning", 5)
	local holder = Instance.new("Frame")
	holder.Name = "Warning"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(BANNER_WIDE, WARN_TALL)
	holder.Visible = false
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	-- everything is placed from the plate's middle (the holder's top is the plate's seen top)
	local plateMiddle = PLATE_SEEN_TALL / 2

	-- a soft glow behind the plate that breathes with the beat
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0, plateMiddle)
	glow.Size = UDim2.fromOffset(PLATE_WIDE * 1.08, PLATE_TALL * 1.3)
	glow.BackgroundTransparency = 1
	glow.Image = NEON.BANNER
	glow.ImageColor3 = Color3.fromHex("FF3A64")
	glow.ImageTransparency = 0.7
	glow.ZIndex = 1
	glow.Parent = holder

	local plate = Instance.new("ImageLabel")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.new(0.5, 0, 0, plateMiddle)
	plate.Size = UDim2.fromOffset(PLATE_WIDE, PLATE_TALL)
	plate.BackgroundTransparency = 1
	plate.Image = NEON.BANNER
	plate.ZIndex = 2
	plate.Parent = holder

	-- a light that sweeps across the plate's glass
	local clip = Instance.new("Frame")
	clip.Name = "SheenClip"
	clip.AnchorPoint = Vector2.new(0.5, 0.5)
	clip.Position = plate.Position
	clip.Size = UDim2.fromOffset(PLATE_SEEN_WIDE - 40, PLATE_SEEN_TALL - 10)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.ZIndex = 3
	clip.Parent = holder
	local sheen = Instance.new("ImageLabel")
	sheen.Name = "Sheen"
	sheen.AnchorPoint = Vector2.new(0.5, 0.5)
	sheen.Size = UDim2.new(0, 120, 1, 0)
	sheen.BackgroundTransparency = 1
	sheen.Image = NEON.SHEEN
	sheen.ImageColor3 = Color3.fromHex("FFC9D6")
	sheen.ImageTransparency = 0.8
	sheen.ZIndex = 3
	sheen.Parent = clip

	-- the chevrons either side, pointing in at the words; they light up one after another, marching inward
	local chevrons: { { image: ImageLabel, order: number } } = {}
	for side = -1, 1, 2 do
		for i = 1, CHEVRONS do
			local chevron = Instance.new("ImageLabel")
			chevron.Name = "Chevron"
			chevron.AnchorPoint = Vector2.new(0.5, 0.5)
			-- the outermost first (order 1), the one next to the plate last
			local fromPlate = PLATE_SEEN_WIDE / 2 + 6 + CHEVRON_WIDE * 0.3 + CHEVRON_STEP * (CHEVRONS - i)
			chevron.Position = UDim2.new(0.5, side * fromPlate, 0, plateMiddle)
			chevron.Size = UDim2.fromOffset(CHEVRON_WIDE, CHEVRON_TALL)
			chevron.BackgroundTransparency = 1
			chevron.Image = NEON.CHEVRON_RED
			chevron.Rotation = if side > 0 then 180 else 0 -- the right ones point left, in
			chevron.ZIndex = 2
			chevron.Parent = holder
			table.insert(chevrons, { image = chevron, order = i })
		end
	end

	local title = PlasticUi.text({ name = "Title", size = TITLE_TEXT, parent = holder, zIndex = 4 })
	title.root.AnchorPoint = Vector2.new(0.5, 0.5)
	title.root.Position = UDim2.new(0.5, 0, 0, plateMiddle - 1)
	title.root.Size = UDim2.fromOffset(PLATE_SEEN_WIDE - 40, TITLE_TEXT + 6)
	-- neon words: white going pink, a hot red edge instead of black, and a deep red glow under them
	local titleStroke = title.label:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = Color3.fromHex("FF2450")
		titleStroke.Thickness = 2.6
	end
	title.drop.TextColor3 = Color3.fromHex("8A0022")
	title.drop.Position = UDim2.fromOffset(0, 2)
	local dropStroke = title.drop:FindFirstChildOfClass("UIStroke")
	if dropStroke then
		dropStroke.Color = Color3.fromHex("FF1F4B")
		dropStroke.Thickness = 4
	end
	PlasticUi.shimmer(title.label, Color3.fromHex("FFE2EA"), 1.3)

	local sub = PlasticUi.text({ name = "Sub", size = SUB_TEXT, parent = holder, zIndex = 4 })
	sub.root.Position = UDim2.fromOffset(0, SUB_TOP - (PLATE_TALL - PLATE_SEEN_TALL) / 2)
	sub.root.Size = UDim2.new(1, 0, 0, SUB_TEXT + 4)
	sub.label.RichText = true
	sub.root.Visible = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local shown = 0 -- how far the banner has faded in (0 to 1)
	local shownCount: number? = nil
	local shownRed: boolean? = nil
	local redLit: boolean? = nil -- the word RED is lit (it blinks with the beat)
	local subShown = 0
	local popAt = -math.huge
	local march = 0

	local function setSub(lit: boolean)
		local color = if lit then "#" .. RED_HEX else "#FFFFFF"
		sub.label.Text = `YOU'RE ON THE <font color="{color}">RED</font>! MOVE IN!`
		sub.drop.Text = "YOU'RE ON THE RED! MOVE IN!"
	end

	RoundRemote.OnClientEvent:Connect(function(kind: string, _count: any, outer: any, inner: any)
		if kind ~= "shrink" then
			return
		end
		local center = Workspace:GetAttribute(MoveRules.ATTR_ARENA_CENTER)
		local middle = if typeof(center) == "Vector3" then center else bandCenter
		local before = if type(outer) == "number" then outer else bandOuter
		local after = if type(inner) == "number" then inner else bandInner
		clearBand()
		if before and after and before > after then
			breakOff(middle, before, after)
			flashCutLine(middle, after)
		end
	end)

	RunService.PreRender:Connect(function(dt: number)
		local now = os.clock()
		local center = Workspace:GetAttribute(MoveRules.ATTR_ARENA_CENTER)
		local radius = Workspace:GetAttribute(MoveRules.ATTR_ARENA_RADIUS)
		local cutRadius = Workspace:GetAttribute(RoundRules.ATTR_CUT_RADIUS)
		local cutAt = Workspace:GetAttribute(RoundRules.ATTR_CUT_AT)
		local warning = false
		if
			typeof(center) == "Vector3"
			and type(radius) == "number"
			and type(cutRadius) == "number"
			and type(cutAt) == "number"
			and cutAt > 0
			and cutRadius > 0
			and cutRadius < radius - 0.05
		then
			if bandOuter ~= radius or bandInner ~= cutRadius or bandCenter ~= center then
				showBand(center, radius, cutRadius)
			end
			-- the red pulses faster as the cut gets near
			local left = cutAt - Workspace:GetServerTimeNow()
			local urgency = 1 - math.clamp(left / S.WARN, 0, 1)
			pulse += dt * (1.6 + 4.4 * urgency)
			local beat = 0.5 + 0.5 * math.cos(pulse * math.pi * 2)
			local fadeIn = math.clamp((now - bandAt) / 0.25, 0, 1)
			for _, strip in strips do
				strip.Transparency = 1 - fadeIn * (0.45 + 0.3 * beat)
			end
			for _, line in lines do
				line.Transparency = 1 - fadeIn * (0.8 + 0.2 * beat)
			end

			-- the arrows on the red march inward, faster as the cut nears, and breathe with the beat
			march += dt * ARROW_SPEED * (1 + 2.5 * urgency)
			for _, each in arrows do
				each.image.Position = UDim2.fromOffset(-each.tile * (1 - march % 1), 0)
				each.image.ImageTransparency = 1 - fadeIn * (0.55 + 0.35 * beat)
			end

			-- on the red: your screen's edges flash red
			local onRed = false
			local body = player.Character
			local root = if body then body:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				if MoveRules.pastEdge(root.Position, center, cutRadius) then
					onRed = true
					if now - lastFlash > 0.45 then
						lastFlash = now
						TagFx.edgeFlash(RED)
					end
				end
			end

			-- the banner, for players in the round
			if player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true then
				warning = true
				local count = math.ceil(left - 1e-3)
				if count ~= shownCount then
					shownCount = count
					popAt = now
					title:set(if count >= 1 then "MAP SHRINKING IN " .. count else "MAP SHRINKING!")
				end
				shownRed = onRed
				-- the plate and its glow breathe with the beat; the chevrons chase inward
				glow.ImageTransparency = 0.82 - 0.3 * beat
				plate.ImageColor3 = WHITE:Lerp(Color3.fromHex("FFD0DA"), 1 - beat)
				local chase = now * (2.6 + 5 * urgency)
				for _, each in chevrons do
					local x = (chase - each.order) % CHEVRONS
					local lit = math.max(0, 1 - x / 1.4)
					each.image.ImageTransparency = 0.6 - 0.6 * lit
					each.image.ImageColor3 = WHITE:Lerp(Color3.fromHex("FFD6DE"), lit * 0.6)
				end
				local sweep = (now / 1.1) % 1.6
				sheen.Position = UDim2.new(-0.2 + sweep, 0, 0.5, 0)
				-- RED blinks with the beat
				local lit = beat > 0.5
				if onRed and lit ~= redLit then
					redLit = lit
					setSub(lit)
				end
			end
		elseif bandOuter then
			clearBand()
		end
		if not warning then
			shownCount, shownRed, redLit = nil, nil, nil
		end

		-- the banner fades in and out quickly, pops on every new number, shakes in its last second, and bobs with the
		-- timer; the line under it shows only while you're on the red
		shown = math.clamp(shown + (if warning then dt else -dt) / 0.15, 0, 1)
		subShown = math.clamp(subShown + (if warning and shownRed then dt else -dt) / 0.12, 0, 1)
		holder.Visible = shown > 0
		if shown <= 0 then
			HudLayout.unstack("Shrink")
		else
			title:setFade(1 - shown)
			sub.root.Visible = subShown > 0
			sub:setFade(1 - shown * subShown)
			plate.ImageTransparency = 1 - shown
			local popAge = now - popAt
			local pop = if popAge >= 0 and popAge < 0.3 then 1 + 0.22 * (1 - popAge / 0.3) ^ 2 else 1
			local bob, tilt = PlasticUi.motion(0.3)
			local size = HudLayout.popScale()
			local top = HudLayout.stack("Shrink", HudLayout.underTimer(), WARN_TALL * size)
			-- never wider than the room between the tag feed and the coin counter beside it
			local room = HudLayout.halfRoom(top, top + WARN_TALL * size)
			size = math.min(size, 2 * room / BANNER_WIDE)
			scale.Scale = size * pop
			local shake = if shownCount and shownCount <= 1 then math.sin(now * 70) * 1.5 else 0
			holder.Position = UDim2.new(0.5, tilt * 2 + shake, 0, top + bob)
			holder.Rotation = tilt * 0.4
		end

		if #pieces > 0 then
			stepPieces(now)
		end
		stepFlash(now)
	end)
end

return ShrinkFx
