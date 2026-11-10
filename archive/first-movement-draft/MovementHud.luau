-- Stamina bar and dash cooldown at the bottom of the screen.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Movement = require(script.Parent.Movement)

local COLORS = {
	Track = Color3.fromRGB(18, 20, 28),
	Stamina = Color3.fromRGB(90, 220, 120),
	StaminaLow = Color3.fromRGB(255, 190, 60),
	Exhausted = Color3.fromRGB(235, 70, 70),
	DashReady = Color3.fromRGB(80, 170, 255),
	DashCooling = Color3.fromRGB(45, 50, 64),
	Text = Color3.fromRGB(240, 242, 248),
	Outline = Color3.fromRGB(0, 0, 0),
}

local MovementHud = {}

local function make(className, properties, children)
	local instance = Instance.new(className)
	for name, value in pairs(properties) do
		instance[name] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

local function corner()
	return make("UICorner", { CornerRadius = UDim.new(1, 0) })
end

local function stroke()
	return make("UIStroke", { Color = COLORS.Outline, Thickness = 2, Transparency = 0.4 })
end

function MovementHud.Start()
	local staminaFill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLORS.Stamina,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, { corner() })

	local staminaBar = make("Frame", {
		Name = "Stamina",
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.Track,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -78, 0, 12),
	}, { corner(), stroke(), staminaFill })

	local dashFill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = COLORS.DashReady,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, { corner() })

	local dashLabel = make("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Size = UDim2.fromScale(1, 1),
		Text = "DASH",
		TextColor3 = COLORS.Text,
		TextSize = 14,
		ZIndex = 2,
	}, { make("UIStroke", { Color = COLORS.Outline, Thickness = 1.5, Transparency = 0.3 }) })

	local dashPill = make("Frame", {
		Name = "Dash",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = COLORS.DashCooling,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(66, 28),
	}, { corner(), stroke(), dashFill, dashLabel })

	local container = make("Frame", {
		Name = "Movement",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(300, 30),
	}, { staminaBar, dashPill })

	make("ScreenGui", {
		Name = "TagRivalsMovementHud",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	}, { container })

	RunService.RenderStepped:Connect(function()
		local state = Movement.GetState()

		local ratio = math.clamp(state.Stamina / state.MaxStamina, 0, 1)
		staminaFill.Size = UDim2.fromScale(ratio, 1)
		staminaFill.Visible = ratio > 0.001
		if state.Exhausted then
			staminaFill.BackgroundColor3 = COLORS.Exhausted
		elseif ratio < 0.3 then
			staminaFill.BackgroundColor3 = COLORS.StaminaLow
		else
			staminaFill.BackgroundColor3 = COLORS.Stamina
		end

		if state.DashCooldownLeft > 0 then
			local progress = 1 - state.DashCooldownLeft / state.DashCooldown
			dashFill.Size = UDim2.fromScale(progress, 1)
			dashFill.BackgroundTransparency = 0.45
			dashLabel.Text = string.format("%.1f", state.DashCooldownLeft)
		else
			dashFill.Size = UDim2.fromScale(1, 1)
			dashFill.BackgroundTransparency = 0
			dashLabel.Text = "DASH"
		end
	end)
end

return MovementHud
