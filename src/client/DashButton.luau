--!strict
-- The phone and tablet Dash button (design notes, Movement, owner 2026-11-09), in Huss Zero's style (owner 2026-11-09:
-- "copy dis Ui Style from Huss Zero"): where Roblox's Jump button was (that one hides itself because jumping is off), a
-- chunky square gold plastic button like Huss Zero's JUMP, with moving halftone dots, a big animated arrow pointing
-- left and the word DASH, with nothing behind it (owner 2026-11-10: "can u getv rid of that grey background panels"; it
-- used to sit on a striped plate). Everything moves (owner 2026-11-09: "make the Uis All animated", "and the texture
-- also animated"): the arrow keeps sliding left with an echo streaking off it, the dots roll, and the button bobs,
-- tilts with the camera and breathes while a dash is ready. With no charge left the button goes grey, the arrow dims
-- and the seconds until the next charge show; the two pips under it are the charges. A press sinks the button onto its
-- side. Shows while touch is the way you play (InputMode); the Studio test key U shows it on a PC.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local HudLayout = require(script.Parent.HudLayout)
local InputMode = require(script.Parent.InputMode)
local MoveController = require(script.Parent.MoveController)
local PlasticUi = require(script.Parent.PlasticUi)

local D = Config.Dash
local U = Config.Ui

local DashButton = {}

local player = Players.LocalPlayer

local BASE = 120 -- the button's size in pixels before scaling (everything below is laid out at this size)
local AREA = BASE * 1.6 -- the see-through touch area round it, reaching into the screen's corner
local CENTER = 0.42 -- where the button's middle sits in the touch area (share from its top-left), clear of the corner
local ARROW = BASE * 0.6 -- the arrow's box on the button's face
local WORD_TEXT = 20
local PERIOD = 0.9 -- s per slide of the arrow
local GREY = Color3.fromHex("8A8FA3")

-- How big the button is on this screen: big enough for a thumb, never huge. On a phone about the size of Roblox's own
-- Jump button (owner 2026-11-10: "the ui is literslly taking up the whole screen").
local function buttonSize(): number
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(800, 400)
	local short = math.min(size.X, size.Y)
	return if PlasticUi.isPhone() then math.clamp(short * 0.21, 72, 96) else math.clamp(short * 0.27, 96, 150)
end

local function bar(parent: Instance, x: number, y: number, length: number, thick: number, rotation: number, z: number)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(length, thick)
	frame.Rotation = rotation
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

-- A left-pointing arrow (a shaft and two arms, square ends like Huss Zero's square plastic) in a box `size` pixels
-- square; `grow` pixels fatter all round (the black outline is the same arrow, fatter, drawn under the white one, so
-- the joins show no seams).
local function arrowShape(parent: Instance, size: number, grow: number, z: number): { Frame }
	local thick = size * 0.2 + grow * 2
	local tipX, midY = size * 0.12, size * 0.5
	local arm = size * 0.5
	local angle = math.rad(42)
	local parts = {}
	local shaftLeft, shaftRight = tipX + size * 0.06, size * 0.94
	table.insert(parts, bar(parent, (shaftLeft + shaftRight) / 2, midY, shaftRight - shaftLeft + grow * 2, thick, 0, z))
	local dx, dy = math.cos(angle) * arm / 2, math.sin(angle) * arm / 2
	table.insert(parts, bar(parent, tipX + dx, midY - dy, arm + grow * 2, thick, -42, z))
	table.insert(parts, bar(parent, tipX + dx, midY + dy, arm + grow * 2, thick, 42, z))
	return parts
end

local function arrowBox(name: string, parent: Instance, z: number): Frame
	local box = Instance.new("Frame")
	box.Name = name
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(ARROW, ARROW)
	box.ZIndex = z
	box.Parent = parent
	return box
end

local function paint(parts: { Frame }, color: Color3, transparency: number)
	for _, part in parts do
		part.BackgroundColor3 = color
		part.BackgroundTransparency = transparency
	end
end

function DashButton.start()
	local gui = PlasticUi.screen("TagRivalsDashButton", 3)
	gui.Enabled = InputMode.isTouch()

	-- the touch area round the button, reaching into the corner (see-through, so a thumb near the button still dashes)
	local area = Instance.new("TextButton")
	area.Name = "Dash"
	area.Text = ""
	area.AutoButtonColor = false
	area.BackgroundTransparency = 1
	area.AnchorPoint = Vector2.new(1, 1)
	area.Position = UDim2.fromScale(1, 1)
	area.Size = UDim2.fromOffset(AREA, AREA)
	area.BorderSizePixel = 0
	area.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = area

	-- the gold plastic button
	local button = PlasticUi.block({
		name = "Button",
		width = BASE,
		height = BASE,
		color = PlasticUi.GOLD,
		parent = area,
		depth = 8, -- Huss Zero's phone buttons
		dotsCover = 0.6,
	})
	button.root.AnchorPoint = Vector2.new(0.5, 0.5)
	button.root.Position = UDim2.fromScale(CENTER, CENTER)
	button.root.ZIndex = 2
	local breathe = Instance.new("UIScale")
	breathe.Parent = button.root

	-- the arrow, its black outline and its echo, in the face's upper part
	local holder = Instance.new("Frame")
	holder.Name = "ArrowHolder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.4, 0)
	holder.Size = UDim2.fromOffset(ARROW, ARROW)
	holder.ZIndex = 3
	holder.Parent = button.face
	local echoBox = arrowBox("Echo", holder, 3)
	local echo = arrowShape(echoBox, ARROW, 0, 3)
	local mainBox = arrowBox("Arrow", holder, 4)
	local outline = arrowShape(mainBox, ARROW, 3, 4)
	local fill = arrowShape(mainBox, ARROW, 0, 5)
	paint(outline, PlasticUi.OUTLINE_COLOR, 0)
	paint(fill, Color3.new(1, 1, 1), 0)

	local word = PlasticUi.text({ name = "Word", size = WORD_TEXT, parent = button.face, zIndex = 6 })
	word.root.AnchorPoint = Vector2.new(0.5, 1)
	word.root.Position = UDim2.new(0.5, 0, 1, -8)
	word.root.Size = UDim2.fromOffset(BASE, WORD_TEXT)
	word:set("DASH")

	-- the seconds until the next charge, over the dimmed arrow
	local countdown = PlasticUi.text({ name = "Countdown", size = 34, parent = holder, zIndex = 7 })
	countdown.root.Size = UDim2.fromScale(1, 1)
	countdown.root.Visible = false

	-- one pip per charge under the button
	local pips: { Frame } = {}
	local pipWidth, pipHeight, pipGap = BASE * 0.26, 9, 6
	for i = 1, D.MAX_CHARGES do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.AnchorPoint = Vector2.new(0.5, 0)
		local offset = (i - (D.MAX_CHARGES + 1) / 2) * (pipWidth + pipGap)
		pip.Position = UDim2.new(CENTER, offset, CENTER, BASE / 2 + 10)
		pip.Size = UDim2.fromOffset(pipWidth, pipHeight)
		pip.BorderSizePixel = 0
		pip.ZIndex = 4
		PlasticUi.outline(pip, 2)
		pip.Parent = area
		table.insert(pips, pip)
	end

	gui.Parent = player:WaitForChild("PlayerGui")

	-- a press dashes at once; the button stays sunk while any finger holds it
	local holding: { [InputObject]: boolean } = {}
	area.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			holding[input] = true
			MoveController.dash()
		end
	end)
	area.InputEnded:Connect(function(input)
		holding[input] = nil
	end)
	InputMode.onChanged(function()
		gui.Enabled = InputMode.isTouch()
		table.clear(holding)
	end)

	local wasReady: boolean? = nil
	RunService.PreRender:Connect(function()
		if not gui.Enabled then
			HudLayout.report("DashButton", nil)
			return
		end
		-- where the button rests in the corner (its bob and tilt counted in), for the pieces that keep clear of it (the
		-- coin counter above it)
		local k = buttonSize() / BASE
		local edge = (CENTER * AREA - BASE / 2 - 6) * k
		local screen = HudLayout.screen()
		HudLayout.report(
			"DashButton",
			HudLayout.rect(screen.X - AREA * k + edge, screen.Y - AREA * k + edge, screen.X, screen.Y)
		)
		local state = MoveController.state
		local color = MoveRules.dashColor(state.role, player:GetAttribute(MoveRules.ATTR_DASH_COLOR))
		local ready = MoveRules.canSpend(state.charge)
		if ready ~= wasReady then
			wasReady = ready
			button:setColor(if ready then PlasticUi.GOLD else GREY)
			word:setFade(if ready then 0 else 0.4)
		end

		local t = os.clock()
		local slide = 0.5 - 0.5 * math.cos(t / PERIOD * math.pi * 2)
		mainBox.Position = UDim2.fromOffset(-ARROW * 0.07 * (if ready then slide else 0), 0)
		local streak = (t / PERIOD) % 1
		echoBox.Position = UDim2.fromOffset(-ARROW * 0.42 * streak, 0)
		echoBox.Visible = ready
		paint(echo, Color3.new(1, 1, 1), 0.45 + 0.55 * streak)
		paint(fill, Color3.new(1, 1, 1), if ready then 0 else 0.6)
		paint(outline, PlasticUi.OUTLINE_COLOR, if ready then 0 else 0.5)

		local left = MoveRules.nextChargeIn(state.charge)
		countdown.root.Visible = not ready and left ~= nil
		if left then
			countdown:set(string.format("%.1f", left))
		end
		for i, pip in pips do
			local share = MoveRules.cellFill(state.charge, i)
			pip.BackgroundColor3 = if share >= 1 then color else PlasticUi.PLATE
			pip.BackgroundTransparency = if share >= 1 then 0 else 0.5 - 0.3 * share
		end

		local pressed = next(holding) ~= nil
		button:setPressed(pressed)
		scale.Scale = buttonSize() / BASE * (if pressed then U.PRESS_SCALE else 1)
		-- the button bobs and tilts like the other panels, and breathes while a dash is ready
		local bob, tilt = PlasticUi.motion(0.45)
		button.root.Position = UDim2.new(CENTER, 0, CENTER, bob)
		button.root.Rotation = tilt
		breathe.Scale = if ready and not pressed then 1 + 0.03 * (0.5 + 0.5 * math.sin(t * 4)) else 1
	end)
end

return DashButton
