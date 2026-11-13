--!strict
-- The speed effect (design notes, VFX: red and cyan at the screen's edges as you get fast, like a lens pulling
-- apart). The left edge glows red and the right edge cyan, stronger the faster you run (from Config.SpeedFx.START to
-- PEAK studs/s), with a burst on every dash that eases back. Never stronger than MAX, so it can't blind (owner).
-- Two plain frames with a fade each: nothing is made or thrown away while it runs, and they're switched off when
-- there's nothing to see.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveController = require(script.Parent.MoveController)
local PlasticUi = require(script.Parent.PlasticUi)

local F = Config.SpeedFx

local SpeedFx = {}

local function edge(name: string, parent: Instance, color: Color3, right: boolean): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(if right then 1 else 0, 0)
	frame.Position = UDim2.fromScale(if right then 1 else 0, 0)
	frame.Size = UDim2.fromScale(F.EDGE, 1)
	frame.Visible = false
	local fade = Instance.new("UIGradient")
	-- solid at the screen's edge, gone toward its middle
	fade.Transparency = if right
		then NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.6, 0.75),
			NumberSequenceKeypoint.new(1, 0),
		})
		else NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.4, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		})
	fade.Parent = frame
	frame.Parent = parent
	return frame
end

function SpeedFx.start()
	local gui = PlasticUi.screen("TagRivalsSpeedFx", 1)
	local red = edge("Red", gui, Color3.fromHex(F.RED), false)
	local cyan = edge("Cyan", gui, Color3.fromHex(F.CYAN), true)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local strength = 0
	local shown = -1
	RunService.PreRender:Connect(function(dt: number)
		local state = MoveController.state
		local want = math.clamp((state.speed - F.START) / math.max(F.PEAK - F.START, 1), 0, 1) * F.MAX
		-- a dash's burst, easing back
		local age = os.clock() - state.dashAt
		if age >= 0 and age < F.DASH_BACK then
			want = math.max(want, F.DASH * (1 - age / F.DASH_BACK))
		end
		want = math.min(want, F.MAX)
		strength += (want - strength) * (1 - math.exp(-12 * dt))
		local level = math.floor(strength * 100 + 0.5) / 100
		if level == shown then
			return
		end
		shown = level
		local on = level > 0.01
		red.Visible = on
		cyan.Visible = on
		if on then
			red.BackgroundTransparency = 1 - level * 0.6
			cyan.BackgroundTransparency = 1 - level * 0.6
		end
	end)
end

return SpeedFx
