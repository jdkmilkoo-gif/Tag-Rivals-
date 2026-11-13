--!strict
-- Buttons and pop-up panels in the game's style (PlasticUi), shared by the menu screens (Wallet, QuestPanel,
-- CodesPanel):
--   * UiKit.button: a chunky plastic button with words on it. It grows a touch under the pointer, sinks and shrinks
--     when pressed, springs back, and clicks (Sounds);
--   * UiKit.panel: a big striped card in the middle of the screen over a dimmed game. It pops in and out, bobs like
--     every panel, fits any screen (a phone's too), and closes on its X or a tap outside it. Only one is open at a
--     time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlasticUi = require(script.Parent.PlasticUi)
local Sounds = require(script.Parent.Sounds)

local U = Config.Ui

local UiKit = {}

export type Button = {
	block: PlasticUi.Block,
	text: PlasticUi.Text,
	hit: TextButton,
	setEnabled: (self: Button, on: boolean) -> (),
	setText: (self: Button, text: string) -> (),
	setColor: (self: Button, color: Color3) -> (),
}

export type ButtonProps = {
	name: string,
	width: number,
	height: number,
	color: Color3,
	text: string,
	textSize: number,
	parent: Instance?,
	onClick: () -> (),
}

export type Panel = {
	gui: ScreenGui,
	content: Frame, -- the room under the title: the caller fills it
	width: number, -- the room's size, pixels at full size
	height: number,
	open: (self: Panel) -> (),
	close: (self: Panel) -> (),
	isOpen: (self: Panel) -> boolean,
}

export type PanelProps = {
	name: string,
	title: string,
	width: number, -- the whole card, pixels at full size
	height: number,
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

UiKit.RED = Color3.fromHex("FF3B4A")
UiKit.GREY = Color3.fromHex("6B7088")

local PRESS = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPRING = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- A plastic button, placed by its middle (its root's AnchorPoint is its middle, so it grows and shrinks in place).
function UiKit.button(props: ButtonProps): Button
	local block = PlasticUi.block({
		name = props.name,
		width = props.width,
		height = props.height,
		color = props.color,
		parent = props.parent,
	})
	block.root.AnchorPoint = Vector2.new(0.5, 0.5)
	local scale = Instance.new("UIScale")
	scale.Parent = block.root
	local text = PlasticUi.text({ name = "Words", size = props.textSize, parent = block.face, zIndex = 4 })
	text.root.Size = UDim2.fromScale(1, 1)
	text:set(props.text)

	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 20
	hit.Parent = block.root

	local enabled = true
	local over, down = false, false
	local function look()
		block:setPressed(down)
		local size = if down then U.PRESS_SCALE elseif over then 1.05 else 1
		TweenService:Create(scale, if down then PRESS else SPRING, { Scale = size }):Play()
	end
	hit.MouseEnter:Connect(function()
		if enabled and not over then
			over = true
			Sounds.hover()
			look()
		end
	end)
	hit.MouseLeave:Connect(function()
		over, down = false, false
		look()
	end)
	hit.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if enabled and (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) then
			down = true
			look()
		end
	end)
	hit.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			down = false
			look()
		end
	end)
	hit.Activated:Connect(function()
		if enabled then
			Sounds.click()
			props.onClick()
		else
			Sounds.error()
		end
	end)

	local button = { block = block, text = text, hit = hit } :: any
	function button.setEnabled(_self: Button, on: boolean)
		enabled = on
		if not on then
			over, down = false, false
			look()
		end
	end
	function button.setText(_self: Button, value: string)
		text:set(value)
	end
	function button.setColor(_self: Button, color: Color3)
		block:setColor(color)
	end
	return button :: Button
end

---------------------------------------------------------------- panels

local TITLE_TALL = 58
local PAD = 16
local DIM = 0.45 -- how see-through the black over the game is

local current: Panel? = nil

local function screenSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(800, 420)
end

function UiKit.panel(props: PanelProps): Panel
	local gui = PlasticUi.screen("TagRivals" .. props.name, 30)
	gui.Enabled = false

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = gui

	local holder = Instance.new("Frame")
	holder.Name = "Card"
	holder.Active = true -- a tap on the card isn't a tap outside it
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(props.width, props.height)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local card = PlasticUi.block({
		name = "Plastic",
		width = props.width,
		height = props.height,
		color = PlasticUi.PLATE,
		parent = holder,
		dotsCover = 0.35,
	})
	local title = PlasticUi.text({ name = "Title", size = 38, parent = card.face, zIndex = 4 })
	title.root.Position = UDim2.fromOffset(0, 8)
	title.root.Size = UDim2.new(1, 0, 0, TITLE_TALL - 10)
	title:set(props.title)
	PlasticUi.shimmer(title.label, PlasticUi.GOLD, 2)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(PAD, TITLE_TALL)
	content.Size = UDim2.fromOffset(props.width - PAD * 2, props.height - card.depth - TITLE_TALL - PAD)
	content.ZIndex = 4
	content.Parent = card.face

	local panel = {
		gui = gui,
		content = content,
		width = props.width - PAD * 2,
		height = props.height - card.depth - TITLE_TALL - PAD,
	} :: any

	local open = false
	local openedAt = -math.huge
	local closedAt = -math.huge

	function panel.open(self: Panel)
		if open then
			return
		end
		local other = current
		if other and other ~= self then
			other:close()
		end
		current = self
		open = true
		openedAt = os.clock()
		gui.Enabled = true
		Sounds.open()
		if props.onOpen then
			props.onOpen()
		end
	end
	function panel.close(self: Panel)
		if not open then
			return
		end
		open = false
		closedAt = os.clock()
		if current == self then
			current = nil
		end
		Sounds.close()
		if props.onClose then
			props.onClose()
		end
	end
	function panel.isOpen(_self: Panel): boolean
		return open
	end

	local x = UiKit.button({
		name = "Close",
		width = 46,
		height = 46,
		color = UiKit.RED,
		text = "X",
		textSize = 26,
		parent = card.face,
		onClick = function()
			panel:close()
		end,
	})
	x.block.root.Position = UDim2.new(1, -34, 0, 32)
	x.block.root.ZIndex = 6
	dim.Activated:Connect(function()
		panel:close()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	RunService.PreRender:Connect(function()
		if not gui.Enabled then
			return
		end
		local now = os.clock()
		local screen = screenSize()
		local fit = math.min(screen.X * 0.94 / props.width, screen.Y * 0.9 / props.height, 1.25)
		local bob, tilt = PlasticUi.motion(0.2)
		holder.Position = UDim2.new(0.5, 0, 0.5, bob)
		holder.Rotation = tilt * 0.25
		if open then
			-- pops in from 70% with a little overshoot
			local t = math.clamp((now - openedAt) / 0.28, 0, 1) - 1
			local back = 1 + 2.70158 * t * t * t + 1.70158 * t * t
			scale.Scale = fit * (0.7 + 0.3 * back)
			dim.BackgroundTransparency = 1 - (1 - DIM) * math.clamp((now - openedAt) / 0.2, 0, 1)
		else
			local t = math.clamp((now - closedAt) / 0.14, 0, 1)
			scale.Scale = fit * (1 - 0.25 * t * t)
			dim.BackgroundTransparency = DIM + (1 - DIM) * t
			if t >= 1 then
				gui.Enabled = false
			end
		end
	end)

	return panel :: Panel
end

-- Is one of the panels open (the menu's buttons don't open a second one over it)?
function UiKit.anyOpen(): boolean
	return current ~= nil
end

return UiKit
