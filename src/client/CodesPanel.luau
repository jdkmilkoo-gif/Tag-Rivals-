--!strict
-- The CODES panel (owner 2026-11-13: "add a codes system"): type a code, press REDEEM, get its coins, once. It only
-- sends what was typed; the server (Codes) decides and answers, and the answer pops under the box: green for coins,
-- red for a code that doesn't exist, has run out or was used already.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlasticUi = require(script.Parent.PlasticUi)
local ProgressLink = require(script.Parent.ProgressLink)
local UiKit = require(script.Parent.UiKit)

local CodesPanel = {}

-- Sizes at full scale (pixels; Claude's picks)
local WIDTH, HEIGHT = 470, 292
local BOX_H = 58
local BUTTON_W, BUTTON_H = 200, 60

local panel: UiKit.Panel? = nil

function CodesPanel.toggle()
	local p = panel
	if p then
		if p:isOpen() then
			p:close()
		else
			p:open()
		end
	end
end

function CodesPanel.start()
	local answerAt = -math.huge
	local sentAt = -math.huge
	local box: TextBox

	local made = UiKit.panel({
		name = "Codes",
		title = "CODES",
		width = WIDTH,
		height = HEIGHT,
		onClose = function()
			box:ReleaseFocus()
		end,
	})
	panel = made
	local content = made.content
	local roomW = made.width

	local hint = PlasticUi.text({ name = "Hint", size = 15, parent = content, zIndex = 4, color = Color3.fromHex("C8D4FF") })
	hint.root.Size = UDim2.fromOffset(roomW, 22)
	hint:set("Type a code to get free coins")

	-- the box: a dark plate with a black outline, the typed code in the game's font
	local plate = Instance.new("Frame")
	plate.Name = "Box"
	plate.BackgroundColor3 = Color3.fromHex("120C33")
	plate.BorderSizePixel = 0
	plate.Position = UDim2.fromOffset(0, 30)
	plate.Size = UDim2.fromOffset(roomW, BOX_H)
	plate.ZIndex = 4
	local plateStroke = PlasticUi.outline(plate, 3)
	plate.Parent = content
	box = Instance.new("TextBox")
	box.Name = "Code"
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(12, 0)
	box.Size = UDim2.new(1, -24, 1, 0)
	box.FontFace = PlasticUi.FONT
	box.TextSize = 30
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderText = "TYPE CODE HERE"
	box.PlaceholderColor3 = Color3.fromHex("6C63A8")
	box.Text = ""
	box.ClearTextOnFocus = false
	box.ZIndex = 5
	box.Parent = plate
	-- capitals only, and never longer than a code can be
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local tidy = string.sub(string.upper(box.Text), 1, Config.Codes.MAX_LENGTH)
		if tidy ~= box.Text then
			box.Text = tidy
		end
	end)

	local answer = PlasticUi.text({ name = "Answer", size = 20, parent = content, zIndex = 4 })
	answer.root.AnchorPoint = Vector2.new(0.5, 0.5)
	answer.root.Position = UDim2.fromOffset(roomW / 2, 30 + BOX_H + 22)
	answer.root.Size = UDim2.fromOffset(roomW, 28)
	local answerScale = Instance.new("UIScale")
	answerScale.Parent = answer.root

	local function redeem()
		local code = box.Text
		if code == "" then
			answer:set("Type a code first")
			answer:setColor(UiKit.RED)
			answerAt = os.clock()
			return
		end
		sentAt = os.clock()
		ProgressLink.send("code", code)
	end
	local button = UiKit.button({
		name = "Redeem",
		width = BUTTON_W,
		height = BUTTON_H,
		color = PlasticUi.GOLD,
		text = "REDEEM",
		textSize = 26,
		parent = content,
		onClick = redeem,
	})
	button.block.root.Position = UDim2.fromOffset(roomW / 2, made.height - BUTTON_H / 2 - 2)
	box.FocusLost:Connect(function(enter: boolean)
		if enter then
			redeem()
		end
	end)

	ProgressLink.on("code", function(ok: any, message: any)
		answer:set(if type(message) == "string" then string.upper(message) else "")
		answer:setColor(if ok == true then PlasticUi.DONE else UiKit.RED)
		answerAt = os.clock()
		sentAt = -math.huge
		if ok == true then
			box.Text = ""
		end
	end)

	RunService.PreRender:Connect(function()
		if not made.gui.Enabled then
			return
		end
		local now = os.clock()
		-- the answer pops in; the box's outline glows gold while you type
		local age = now - answerAt
		answerScale.Scale = if age >= 0 and age < 0.3 then 1 + 0.3 * (1 - age / 0.3) else 1
		answer.root.Rotation = if age >= 0 and age < 0.3 then 4 * math.sin(age * 40) * (1 - age / 0.3) else 0
		local typing = box:IsFocused()
		local glow = if typing then 0.5 + 0.5 * math.sin(now * 6) else 0
		plateStroke.Color = PlasticUi.OUTLINE_COLOR:Lerp(PlasticUi.GOLD, glow)
		-- no answer after a couple of seconds: say so rather than leave them guessing
		if sentAt > 0 and now - sentAt > 3 then
			sentAt = -math.huge
			answer:set("NO ANSWER. TRY AGAIN IN A MOMENT")
			answer:setColor(UiKit.RED)
			answerAt = now
		end
	end)
end

return CodesPanel
