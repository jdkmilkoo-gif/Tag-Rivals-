--!strict
-- The screens' style, copied from Huss Zero (owner 2026-11-09: "copy dis Ui Style from Huss Zero"; its PlasticUi and
-- FlatView's dressed faces):
--   * words: Montserrat Bold Italic, white or gold, a thick black outline and a black drop under them (PlasticUi.text);
--   * chunky square plastic (PlasticUi.block): a face lit lighter at the top and darker at its foot, a white shine over
--     its top half, a darker side layer under it, a black outline, a soft shadow, and moving halftone dots. A pressed
--     button sinks its face onto its side;
--   * dark indigo plates with diagonal stripes that scroll (PlasticUi.stripedPlate), and a glint that sweeps across
--     gold words (PlasticUi.shimmer): the textures move too (owner 2026-11-09: "and the texture also animated");
--   * panels bob gently and tilt as the camera turns (PlasticUi.motion).
-- Numbers in Config.Ui.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Halftone = require(script.Parent.Halftone)

local U = Config.Ui

export type Text = {
	root: Frame, -- place and size this
	label: TextLabel,
	drop: TextLabel,
	set: (self: Text, text: string) -> (),
	setColor: (self: Text, color: Color3) -> (),
	setFade: (self: Text, transparency: number) -> (),
}

export type TextProps = {
	name: string,
	size: number, -- TextSize at full size
	parent: Instance?,
	color: Color3?,
	align: Enum.TextXAlignment?,
	zIndex: number?,
}

export type Block = {
	root: Frame, -- the holder the caller places and sizes
	side: Frame,
	face: Frame,
	gloss: Frame,
	dots: Halftone.Field?,
	depth: number,
	setPressed: (self: Block, on: boolean) -> (),
	setColor: (self: Block, color: Color3) -> (),
}

export type BlockProps = {
	name: string,
	width: number, -- pixels at full size
	height: number,
	color: Color3,
	parent: Instance?,
	depth: number?,
	dots: boolean?, -- moving halftone dots on the face (default true)
	dotsCover: number?, -- dots on only this lower share of the face
}

local PlasticUi = {}

PlasticUi.FONT = Font.new(U.FONT_FAMILY, (Enum.FontWeight :: any)[U.FONT_WEIGHT], (Enum.FontStyle :: any)[U.FONT_STYLE])
PlasticUi.OUTLINE_COLOR = Color3.fromHex(U.OUTLINE_COLOR)
PlasticUi.PANEL = Color3.fromHex(U.PANEL_COLOR)
PlasticUi.GOLD = Color3.fromHex(U.GOLD_COLOR)
PlasticUi.PLATE = Color3.fromHex(U.PLATE_COLOR)
PlasticUi.DONE = Color3.fromHex(U.DONE_COLOR)

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local SIDE_DARKEN = 0.38 -- how much darker the side layer is than the face

local function brightness(color: Color3): number
	return 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
end

local function times(color: Color3, k: number): Color3
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

function PlasticUi.darker(color: Color3, amount: number): Color3
	return color:Lerp(BLACK, amount)
end

-- A black square-cornered outline round `parent`.
function PlasticUi.outline(parent: Instance, thickness: number, mode: Enum.ApplyStrokeMode?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = PlasticUi.OUTLINE_COLOR
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = if mode == Enum.ApplyStrokeMode.Contextual
		then Enum.LineJoinMode.Round
		else Enum.LineJoinMode.Miter
	stroke.Parent = parent
	return stroke
end

---------------------------------------------------------------- words

local function textLabel(name: string, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = PlasticUi.FONT
	label.TextSize = size
	label.Size = UDim2.fromScale(1, 1)
	label.Text = ""
	PlasticUi.outline(label, math.max(1.5, size * U.TEXT_OUTLINE), Enum.ApplyStrokeMode.Contextual)
	return label
end

-- Words in the bold italic font with a black outline and a black drop under them.
function PlasticUi.text(props: TextProps): Text
	local root = Instance.new("Frame")
	root.Name = props.name
	root.BackgroundTransparency = 1
	root.ZIndex = props.zIndex or 1

	local drop = textLabel("Drop", props.size)
	drop.TextColor3 = BLACK
	drop.Position = UDim2.fromOffset(0, math.max(1, props.size * U.TEXT_DROP))
	drop.ZIndex = root.ZIndex
	drop.Parent = root

	local label = textLabel("Label", props.size)
	label.TextColor3 = props.color or WHITE
	label.ZIndex = root.ZIndex + 1
	label.Parent = root

	if props.align then
		drop.TextXAlignment = props.align
		label.TextXAlignment = props.align
	end

	local text = { root = root, label = label, drop = drop } :: any
	function text.set(_self: Text, value: string)
		label.Text = value
		drop.Text = value
	end
	function text.setColor(_self: Text, color: Color3)
		label.TextColor3 = color
	end
	function text.setFade(_self: Text, transparency: number)
		for _, each in { label, drop } do
			each.TextTransparency = transparency
			local stroke = each:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = transparency
			end
		end
	end
	root.Parent = props.parent
	return text :: Text
end

---------------------------------------------------------------- plastic

-- Lights a face: lighter at the top, a little darker in the middle, darker again at its foot (FlatView's dress).
local function faceShading(color: Color3): ColorSequence
	local top = color:Lerp(WHITE, U.FACE_LIGHT * brightness(color))
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(0.5, times(top, U.FACE_MID)),
		ColorSequenceKeypoint.new(1, times(top, U.FACE_MID * U.FACE_BOTTOM)),
	})
end

function PlasticUi.block(props: BlockProps): Block
	local depth = props.depth or U.DEPTH

	local root = Instance.new("Frame")
	root.Name = props.name
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(props.width, props.height)

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = BLACK
	shadow.BackgroundTransparency = U.SHADOW_SEE
	shadow.BorderSizePixel = 0
	shadow.Position = UDim2.fromOffset(0, U.SHADOW_DROP)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.ZIndex = 1
	shadow.Parent = root

	local side = Instance.new("Frame")
	side.Name = "Side"
	side.BorderSizePixel = 0
	side.Position = UDim2.fromOffset(0, depth)
	side.Size = UDim2.new(1, 0, 1, -depth)
	side.ZIndex = 2
	PlasticUi.outline(side, U.OUTLINE)
	side.Parent = root

	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BackgroundColor3 = WHITE -- the shading gradient carries the colour
	face.BorderSizePixel = 0
	face.Size = UDim2.new(1, 0, 1, -depth)
	face.ZIndex = 3
	PlasticUi.outline(face, U.OUTLINE)
	local shading = Instance.new("UIGradient")
	shading.Rotation = 90
	shading.Parent = face
	face.Parent = root

	local faceHeight = props.height - depth
	local dots = if props.dots == false
		then nil
		else Halftone.dots(face, { width = props.width, height = faceHeight, cover = props.dotsCover, zIndex = 1 })

	-- the white shine over the top half, over the dots
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = WHITE
	gloss.BorderSizePixel = 0
	gloss.Size = UDim2.fromScale(1, 0.5)
	gloss.ZIndex = 2
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Parent = gloss
	gloss.Parent = face

	local block = {
		root = root,
		side = side,
		face = face,
		gloss = gloss,
		dots = dots,
		depth = depth,
	} :: any

	function block.setPressed(_self: Block, on: boolean)
		face.Position = UDim2.fromOffset(0, if on then math.floor(depth * 0.75) else 0)
	end

	function block.setColor(_self: Block, color: Color3)
		shading.Color = faceShading(color)
		side.BackgroundColor3 = PlasticUi.darker(color, SIDE_DARKEN)
		-- the shine is weaker on darker faces, so dark plates stay deep
		local strength = U.SHINE_DARK + (1 - U.SHINE_DARK) * math.clamp(brightness(color) * 1.6, 0, 1)
		shine.Transparency = NumberSequence.new(1 - (1 - U.SHINE_SEE) * strength, 1)
		if dots then
			Halftone.paint(dots, color)
		end
	end

	block:setColor(props.color)
	root.Parent = props.parent
	return block :: Block
end

---------------------------------------------------------------- moving textures

type Scroller = { gradient: UIGradient, color: Color3, light: Color3, bandsPerSecond: number }
type Shimmer = { gradient: UIGradient, period: number, phase: number }
local scrollers: { Scroller } = {}
local shimmers: { Shimmer } = {}
local rng = Random.new()
local STRIPE_BANDS = 8 -- stripes across a plate (a gradient takes at most 20 colour points, 2 a stripe plus a spare)

-- Hard diagonal bands of `color` and `light`, slid `phase` bands along (0 to 2 is one pair, so it loops seamlessly).
local function stripeSequence(color: Color3, light: Color3, phase: number): ColorSequence
	local points: { ColorSequenceKeypoint } = {}
	local function add(time: number, shade: Color3)
		local last = points[#points]
		if last and time <= last.Time then
			time = last.Time + 1e-4
		end
		if time < 1 then
			table.insert(points, ColorSequenceKeypoint.new(time, shade))
		end
	end
	for k = -2, STRIPE_BANDS do
		local from = (k + phase) / STRIPE_BANDS
		local to = (k + 1 + phase) / STRIPE_BANDS
		if to > 0 and from < 1 then
			local shade = if k % 2 == 0 then color else light
			add(math.max(from, 0), shade)
			add(math.min(to, 1) - 0.002, shade)
		end
	end
	points[1] = ColorSequenceKeypoint.new(0, points[1].Value)
	table.insert(points, ColorSequenceKeypoint.new(1, points[#points].Value))
	return ColorSequence.new(points)
end

-- A plate of `color` with diagonal stripes (Huss Zero's dark settings plate) that keep scrolling (owner 2026-11-09:
-- "and the texture also animated"). `fade` (optional keypoints of see-through, 0 to 1) fades the plate out from its
-- top-left to its bottom-right. One gradient carries both: its colour points are moved along every frame, its fade
-- stays put.
function PlasticUi.stripedPlate(name: string, width: number, height: number, color: Color3, fade: { NumberSequenceKeypoint }?): Frame
	local plate = Instance.new("Frame")
	plate.Name = name
	plate.BackgroundColor3 = WHITE
	plate.BorderSizePixel = 0
	plate.Size = UDim2.fromOffset(width, height)
	local light = color:Lerp(WHITE, U.STRIPE_LIGHT)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 45
	gradient.Color = stripeSequence(color, light, 0)
	if fade then
		gradient.Transparency = NumberSequence.new(fade)
	end
	gradient.Parent = plate
	-- the gradient runs along the plate's diagonal: STRIPE_SPEED pixels a second, in bands a second
	local diagonal = math.sqrt(width * width + height * height)
	table.insert(scrollers, {
		gradient = gradient,
		color = color,
		light = light,
		bandsPerSecond = U.STRIPE_SPEED / (diagonal / STRIPE_BANDS),
	})
	return plate
end

-- A white glint that keeps sweeping across a label's letters (its colour becomes `base`).
function PlasticUi.shimmer(label: TextLabel, base: Color3, period: number?)
	label.TextColor3 = WHITE
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 20
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, base),
		ColorSequenceKeypoint.new(0.4, base),
		ColorSequenceKeypoint.new(0.5, base:Lerp(WHITE, 0.85)),
		ColorSequenceKeypoint.new(0.6, base),
		ColorSequenceKeypoint.new(1, base),
	})
	gradient.Parent = label
	table.insert(shimmers, { gradient = gradient, period = period or 1.8, phase = rng:NextNumber() })
end

-- Is this on screen: its ScreenGui switched on and every frame above it visible?
local function onScreen(gui: GuiObject): boolean
	local node: Instance? = gui
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

local function moveTextures(now: number)
	local kept = 0
	for i = 1, #scrollers do
		local s = scrollers[i]
		if s.gradient.Parent then
			kept += 1
			scrollers[kept] = s
			-- towards the corner the plate fades into (only while it's on screen)
			local plate = s.gradient.Parent
			if plate and plate:IsA("GuiObject") and onScreen(plate) then
				s.gradient.Color = stripeSequence(s.color, s.light, (now * s.bandsPerSecond) % 2)
			end
		end
	end
	for i = #scrollers, kept + 1, -1 do
		scrollers[i] = nil
	end
	kept = 0
	for i = 1, #shimmers do
		local s = shimmers[i]
		if s.gradient.Parent then
			kept += 1
			shimmers[kept] = s
			-- across in the first 60% of each period, then a rest
			local x = ((now / s.period + s.phase) % 1) / 0.6
			s.gradient.Offset = Vector2.new(if x <= 1 then -0.75 + 1.5 * x else 1, 0)
		end
	end
	for i = #shimmers, kept + 1, -1 do
		shimmers[i] = nil
	end
end

---------------------------------------------------------------- bob, tilt and size

local clock = 0
local tilt = 0
local lastYaw: number? = nil
local started = false

local function yawOf(look: Vector3): number
	return math.deg(math.atan2(-look.X, -look.Z))
end

function PlasticUi.start()
	if started then
		return
	end
	started = true
	-- phones and tablets stay sideways: the HUD is laid out for a wide screen and doesn't fit an upright phone (owner
	-- 2026-11-10: "clean up the mobile ui abit"; the place allowed upright too)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	RunService.PreRender:Connect(function(dt: number)
		clock += dt
		moveTextures(clock)
		local camera = Workspace.CurrentCamera
		if not camera or dt <= 0 then
			return
		end
		local look = camera.CFrame.LookVector
		if math.abs(look.Y) > 0.98 then
			lastYaw = nil
			return
		end
		local yaw = yawOf(look)
		local rate = 0
		local previous = lastYaw
		if previous then
			rate = ((yaw - previous + 180) % 360 - 180) / dt
		end
		lastYaw = yaw
		local target = math.clamp(rate * U.TILT_PER_TURN, -U.TILT_MAX, U.TILT_MAX)
		tilt += (target - tilt) * (1 - math.exp(-U.TILT_SPRING * dt))
	end)
end

-- A panel's bob (pixels, + is down) and tilt (degrees) right now. `phase` (0 to 1) keeps panels out of step.
function PlasticUi.motion(phase: number): (number, number)
	local bob = math.sin((clock * U.BOB_HZ + phase) * math.pi * 2) * U.BOB_PIXELS
	return bob, tilt
end

-- A phone: a screen whose short side is under this many pixels.
local PHONE_SHORT_SIDE = 480
-- On a phone the whole HUD is drawn this much smaller again, so it leaves room for the game (owner 2026-11-10: "bro
-- the ui is literslly taking up the whole screen"; Claude's pick).
local PHONE_SIZE = 0.7

local function shortSide(): number
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(800, 420)
	return math.min(size.X, size.Y)
end

-- Is this screen a phone's?
function PlasticUi.isPhone(): boolean
	return shortSide() < PHONE_SHORT_SIDE
end

-- How big the HUD is drawn for this screen: smaller on small screens, a little bigger on big ones, and smaller again on
-- a phone.
function PlasticUi.screenScale(): number
	local short = shortSide()
	local scale = math.clamp(short / U.SCALE_SHORT_SIDE, U.SCALE_MIN, U.SCALE_MAX)
	return if short < PHONE_SHORT_SIDE then scale * PHONE_SIZE else scale
end

-- A ScreenGui for the HUD that stays across respawns.
function PlasticUi.screen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	return gui
end

return PlasticUi
