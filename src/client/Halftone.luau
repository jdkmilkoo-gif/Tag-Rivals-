--!strict
-- Moving halftone dots on the plastic faces, copied from Huss Zero (its Halftone; owner 2026-11-09: "copy dis Ui Style
-- from Huss Zero"): a grid of dots that swell and shrink in a wave rolling down and to the right, strongest at the
-- face's foot and fading out toward its top, black on bright faces and white on dark plates, faint so the words read.
-- Every face moves at its own uneven pace (none in step), DOT_FPS times a second. Numbers in Config.Ui.
-- Drawn from one picture (Config.Ui.DOT_SHEET; owner 2026-11-09: "can u adjust the game so its has a consistent 60
-- fps"): the wave repeats every DOT_CELLS dots, so one 8x8-dot tile of it, drawn at SHEET_FRAMES steps through the
-- wave, covers any face. A face is a few tiles; moving the wave on is picking the next step's tile. (It used to be one
-- small Frame a dot, about 640 on screen resized 15 times a second, the biggest cost on the screen.)
-- How a screen uses it:
--   local dots = Halftone.dots(face, { width = 120, height = 60, cover = 0.5 })  -- nil when the face is too small
--   if dots then Halftone.paint(dots, faceColour) end

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local U = Config.Ui
local TAU = 2 * math.pi

-- The picture's layout (uploads/ui/HalftoneSheet.png, drawn by make_halftone_sheet.py): SHEET_FRAMES tiles of
-- DOT_CELLS x DOT_CELLS dots, SHEET_COLS across, SHEET_CELL pixels a dot.
local SHEET_FRAMES = 32
local SHEET_COLS = 8
local SHEET_CELL = 14

export type Field = {
	holder: Frame,
	tiles: { ImageLabel },
	frame: number, -- the wave's step shown now (0 to SHEET_FRAMES - 1)
	pace: { time: number, offset: number, swingTime: number, seed: number },
}

export type Options = {
	width: number, -- the face's size in pixels at full size
	height: number,
	cover: number?, -- dots on only this lower share of the face (1: all of it)
	zIndex: number?,
}

local Halftone = {}

local fields: { Field } = {}
local rng = Random.new()
local started = false

-- How far through its wave a face on `pace` is at `seconds` (it speeds up and slows down on its own slow cycle).
local function phaseAt(seconds: number, pace: { time: number, offset: number, swingTime: number, seed: number }): number
	local w = TAU / pace.swingTime
	local swing = 0.6
	return seconds / pace.time + pace.offset - swing / (pace.time * w) * math.cos(w * seconds + pace.seed)
end

-- Is this on screen: its ScreenGui switched on and every frame above it visible? (Hidden panels' dots don't move.)
local function onScreen(holder: GuiObject): boolean
	local node: Instance? = holder
	while node do
		if node:IsA("LayerCollector") then
			return (node :: LayerCollector).Enabled
		elseif node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return false
end

-- Shows step `frame` of the wave on every tile of `field`.
local function show(field: Field, frame: number)
	field.frame = frame
	local size = U.DOT_CELLS * SHEET_CELL
	local corner = Vector2.new((frame % SHEET_COLS) * size, math.floor(frame / SHEET_COLS) * size)
	for _, tile in field.tiles do
		tile.ImageRectOffset = corner
	end
end

local function step()
	local now = os.clock()
	local alive = 0
	for index = 1, #fields do
		local field = fields[index]
		if field.holder.Parent then
			alive += 1
			fields[alive] = field
			if onScreen(field.holder) then
				-- the wave is cos(2 pi (along / DOT_CELLS - phase)); the picture's step k is phase k / SHEET_FRAMES
				local phase = phaseAt(now, field.pace)
				local frame = math.floor((phase - math.floor(phase)) * SHEET_FRAMES) % SHEET_FRAMES
				if frame ~= field.frame then
					show(field, frame)
				end
			end
		end
	end
	for index = #fields, alive + 1, -1 do
		fields[index] = nil
	end
end

local function start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ U.DOT_SHEET })
		end)
	end)
	local since = 0
	RunService.PreRender:Connect(function(dt)
		since += dt
		if since >= 1 / U.DOT_FPS then
			since = 0
			step()
		end
	end)
end

-- Dots over `face` (sized `options.width` x `options.height` pixels at full size). nil when it's too small for them.
function Halftone.dots(face: GuiObject, options: Options): Field?
	local spacing = U.DOT_SPACING
	local cells = U.DOT_CELLS
	local cover = math.clamp(options.cover or 1, 0, 1)
	local cols = math.floor(options.width / spacing)
	local rows = math.floor(options.height * cover / spacing)
	if options.width < U.DOT_MIN_PX or options.height < U.DOT_MIN_PX or cols < 1 or rows < 1 then
		return nil
	end
	start()

	local holder = Instance.new("Frame")
	holder.Name = "Halftone"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = options.zIndex or 1

	-- the dots sit centred across the face and down to its foot, as before, in tiles of up to cells x cells dots
	local left = (options.width - cols * spacing) / 2
	local top = options.height - rows * spacing
	local tiles: { ImageLabel } = {}
	for ty = 0, math.ceil(rows / cells) - 1 do
		local tall = math.min(cells, rows - ty * cells)
		-- the extra see-through toward the top, by dot row (none at the face's foot)
		local fadeTop = U.DOT_FADE_TOP * (1 - (ty * cells) / rows)
		local fadeFoot = U.DOT_FADE_TOP * (1 - (ty * cells + tall) / rows)
		for tx = 0, math.ceil(cols / cells) - 1 do
			local wide = math.min(cells, cols - tx * cells)
			local tile = Instance.new("ImageLabel")
			tile.Name = "Dots"
			tile.BackgroundTransparency = 1
			tile.BorderSizePixel = 0
			tile.Image = U.DOT_SHEET
			tile.ImageRectSize = Vector2.new(wide * SHEET_CELL, tall * SHEET_CELL)
			tile.Position = UDim2.fromOffset(left + tx * cells * spacing, top + ty * cells * spacing)
			tile.Size = UDim2.fromOffset(wide * spacing, tall * spacing)
			tile.ZIndex = holder.ZIndex
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new(fadeTop, fadeFoot)
			fade.Parent = tile
			tile.Parent = holder
			table.insert(tiles, tile)
		end
	end
	holder.Parent = face

	local field: Field = {
		holder = holder,
		tiles = tiles,
		frame = -1,
		pace = {
			time = U.DOT_WAVE_TIME * (0.7 + 0.8 * rng:NextNumber()),
			offset = rng:NextNumber(),
			swingTime = 2.5 + 4.5 * rng:NextNumber(),
			seed = rng:NextNumber() * TAU,
		},
	}
	show(field, 0)
	table.insert(fields, field)
	Halftone.paint(field, Color3.new(1, 1, 1))
	return field
end

-- Colours a face's dots for its colour: white on a dark plate, black on anything brighter. `see` (0 to 1) fades them
-- out with the face.
function Halftone.paint(field: Field, faceColor: Color3, see: number?)
	local bright = 0.299 * faceColor.R + 0.587 * faceColor.G + 0.114 * faceColor.B
	local dark = bright < U.DOT_DARK_FACE
	local base = if dark then U.DOT_WHITE_SEE else U.DOT_BLACK_SEE
	local color = if dark then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
	local strongest = 1 - (1 - base) * (1 - math.clamp(see or 0, 0, 1))
	for _, tile in field.tiles do
		tile.ImageColor3 = color
		tile.ImageTransparency = strongest
	end
end

return Halftone
