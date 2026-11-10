--!strict
-- The BOTS panel (Studio play-tests only; owner 2026-11-09: "make a setting so that i choose how many bots i want"):
-- a small striped plate at the top left of the screen (under Roblox's buttons, or under the tag feed when that's on
-- the left; clear of a phone's thumbstick) with the number of test bots and two gold buttons, - and +. A
-- press changes the number at once (0 to Config.Dev.BOTS_MAX): new bots wait on the lobby and join the next round;
-- removed ones leave straight away. It lasts for that test; a new test starts with Config.Dev.STUDIO_BOTS.
-- In Huss Zero's style, moving like every other panel: it bobs and leans, its stripes scroll, the number pops when it
-- changes, the buttons sink when pressed. Under it, the frames per second this test is running at (red under 45), to
-- tell real slowness from a feel problem (owner 2026-11-09: "it still feel laggy when i play").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)

local DevBotsPanel = {}

local player = Players.LocalPlayer
local DevRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Dev") :: RemoteEvent

local WIDE = 186
local TALL = 80
local BUTTON = 46 -- with HIT_PAD round it, a thumb-sized target on a phone
local HIT_PAD = 6
local SIZE = 0.85 -- share of the rest of the HUD's size
local POP_TIME = 0.25

local function wanted(): number
	local value = Workspace:GetAttribute(RoundRules.ATTR_STUDIO_BOTS)
	return if type(value) == "number" then value else Config.Dev.STUDIO_BOTS
end

function DevBotsPanel.start()
	if not RunService:IsStudio() then
		return
	end
	local gui = PlasticUi.screen("TagRivalsDevBots", 6)

	local holder = Instance.new("Frame")
	holder.Name = "BotsPanel"
	holder.AnchorPoint = Vector2.new(0, 0)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(WIDE, TALL)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local plate = PlasticUi.block({ name = "Plate", width = WIDE, height = TALL, color = PlasticUi.PLATE, parent = holder })
	local stripes = PlasticUi.stripedPlate("Stripes", WIDE, TALL - plate.depth, PlasticUi.PLATE)
	stripes.ZIndex = 0
	stripes.Size = UDim2.fromScale(1, 1)
	stripes.Parent = plate.face

	local title = PlasticUi.text({ name = "Title", size = 15, parent = plate.face, zIndex = 4 })
	title.root.Position = UDim2.fromOffset(0, 4)
	title.root.Size = UDim2.new(1, 0, 0, 18)
	title:set("TEST BOTS")
	PlasticUi.shimmer(title.label, PlasticUi.GOLD, 2)

	local number = PlasticUi.text({ name = "Number", size = 34, parent = plate.face, zIndex = 4 })
	number.root.AnchorPoint = Vector2.new(0.5, 0)
	number.root.Position = UDim2.new(0.5, 0, 0, 22)
	number.root.Size = UDim2.fromOffset(60, 38)
	local numberScale = Instance.new("UIScale")
	numberScale.Parent = number.root

	-- a gold plastic button with a word on it; `onPress` runs when it's clicked
	local function button(name: string, label: string, x: number, onPress: () -> ())
		local block = PlasticUi.block({
			name = name,
			width = BUTTON,
			height = BUTTON,
			color = PlasticUi.GOLD,
			parent = holder,
			dots = false,
		})
		block.root.ZIndex = 2
		block.root.Position = UDim2.fromOffset(x, TALL - plate.depth - BUTTON + 2)
		local word = PlasticUi.text({ name = "Word", size = 28, parent = block.face, zIndex = 4 })
		word.root.Size = UDim2.fromScale(1, 1)
		word:set(label)
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.Position = UDim2.fromOffset(-HIT_PAD, -HIT_PAD)
		hit.Size = UDim2.new(1, HIT_PAD * 2, 1, HIT_PAD * 2)
		hit.ZIndex = 10
		hit.Parent = block.root
		hit.MouseButton1Down:Connect(function()
			block:setPressed(true)
		end)
		hit.MouseButton1Up:Connect(function()
			block:setPressed(false)
		end)
		hit.MouseLeave:Connect(function()
			block:setPressed(false)
		end)
		hit.Activated:Connect(onPress)
	end
	button("Minus", "-", 8, function()
		DevRemote:FireServer("bots", wanted() - 1)
	end)
	button("Plus", "+", WIDE - BUTTON - 8, function()
		DevRemote:FireServer("bots", wanted() + 1)
	end)

	local fps = PlasticUi.text({ name = "Fps", size = 15, parent = holder, zIndex = 4 })
	fps.root.Position = UDim2.fromOffset(0, TALL + 6)
	fps.root.Size = UDim2.fromOffset(WIDE, 17)

	gui.Parent = player:WaitForChild("PlayerGui")

	local frames, since, worst = 0, 0, 0
	local shownTop: number? = nil -- glides when the tag feed moves left for a round
	local shown: number? = nil
	local popAt = -math.huge
	RunService.PreRender:Connect(function(dt: number)
		local now = os.clock()
		frames += 1
		since += dt
		worst = math.max(worst, dt)
		if since >= 1 then
			local rate = frames / since
			fps:set(string.format("%d FPS  (slowest frame %d ms)", math.floor(rate + 0.5), math.floor(worst * 1000 + 0.5)))
			fps:setColor(if rate < 45 then Color3.fromHex("FF5A6E") else Color3.new(1, 1, 1))
			frames, since, worst = 0, 0, 0
		end
		local count = wanted()
		if count ~= shown then
			if shown ~= nil then
				popAt = now
			end
			shown = count
			number:set(tostring(count))
		end
		local age = now - popAt
		numberScale.Scale = if age >= 0 and age < POP_TIME then 1 + 0.35 * math.sin(math.pi * age / POP_TIME) else 1
		-- top left: under the tag feed when that's on the left (a phone), else under Roblox's buttons
		local feed = HudLayout.get("Feed")
		local top = if feed and feed.left < HudLayout.screen().X / 2
			then feed.bottom + HudLayout.GAP * 2
			else HudLayout.robloxButtonsBottom() + HudLayout.GAP
		local from = shownTop or top
		shownTop = from + (top - from) * (1 - math.exp(-8 * dt))
		local bob, tilt = PlasticUi.motion(0.35)
		holder.Position = UDim2.new(0, HudLayout.EDGE + tilt, 0, (shownTop :: number) + bob)
		scale.Scale = PlasticUi.screenScale() * SIZE
	end)
end

return DevBotsPanel
