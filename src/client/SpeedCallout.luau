--!strict
-- The speed-up callout (design notes, Movement and UI), in Huss Zero's style (owner 2026-11-09: "copy dis Ui Style
-- from Huss Zero"): every time your top speed goes up, "SPEED UP!" pops on screen in big gold bold italic letters
-- with a black outline and drop, over a chunky blue plastic tag with the old and new sprint speeds, e.g. "22 → 30".
-- It keeps moving while it shows (owner: "make the Uis All animated"): a glint sweeps the gold letters, the title
-- rocks, the tag bobs and its halftone dots roll.
-- Rises that come close together (a run of stars) join into one callout that keeps its first number and updates the
-- second.
-- It sits low, just above the dash bars, and small (owner 2026-11-10: "can u put the increase speed, notif smaller and
-- low"; it was about a third of the way down and bigger), the last in the pop-ups' stack (HudLayout) so it never
-- covers the others.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local HudLayout = require(script.Parent.HudLayout)
local MoveController = require(script.Parent.MoveController)
local PlasticUi = require(script.Parent.PlasticUi)

local U = Config.Ui

local SpeedCallout = {}

local player = Players.LocalPlayer

local FADE = 0.3 -- s the callout takes to fade once its time is up
local WIDTH, TITLE_TALL = 460, 70
local TAG_WIDTH, TAG_TALL = 240, 54
local TALL = TITLE_TALL + TAG_TALL + 10
local SIZE = 0.7 -- share of the pop-ups' size (HudLayout.popScale) it's drawn at

local shownFrom: number? = nil
local hideAt = -math.huge

-- 22 → "22", 22.5 → "22.5"
local function speedText(speed: number): string
	local rounded = math.floor(speed * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return string.format("%d", rounded)
	end
	return string.format("%.1f", rounded)
end

function SpeedCallout.start()
	local gui = PlasticUi.screen("TagRivalsSpeedCallout", 5)

	local holder = Instance.new("CanvasGroup") -- fades as one piece
	holder.Name = "Callout"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.8)
	holder.Size = UDim2.fromOffset(WIDTH, TALL)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local title = PlasticUi.text({ name = "Title", size = 58, parent = holder, zIndex = 3 })
	title.root.Size = UDim2.fromOffset(WIDTH, TITLE_TALL)
	title.root.Rotation = -4
	title:set("SPEED UP!")
	PlasticUi.shimmer(title.label, PlasticUi.GOLD, 0.9) -- a white glint sweeping across the gold letters

	local tag = PlasticUi.block({
		name = "Tag",
		width = TAG_WIDTH,
		height = TAG_TALL,
		color = PlasticUi.PANEL,
		parent = holder,
	})
	tag.root.AnchorPoint = Vector2.new(0.5, 0)
	tag.root.Position = UDim2.new(0.5, 0, 0, TITLE_TALL)
	local numbers = PlasticUi.text({ name = "Numbers", size = 32, parent = tag.face, zIndex = 3 })
	numbers.root.Size = UDim2.fromScale(1, 1)

	gui.Parent = player:WaitForChild("PlayerGui")

	local function size(): number
		return HudLayout.popScale() * SIZE
	end

	-- where its middle goes this frame (screen pixels down): just above the dash bars, at the bottom of the pop-ups' stack
	local function middle(): number
		local high = TALL * size()
		return HudLayout.stack("Speed", HudLayout.floor() - high, high) + high / 2
	end

	local pop = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	MoveController.onSpeedUp(function(from: number, to: number)
		local now = os.clock()
		if not shownFrom or now > hideAt then
			shownFrom = from
		end
		hideAt = now + U.CALLOUT_HOLD
		numbers:set(speedText(shownFrom :: number) .. "  →  " .. speedText(to))
		holder.Visible = true
		holder.GroupTransparency = 0
		holder.Position = UDim2.new(0.5, 0, 0, middle())
		scale.Scale = size() * 0.6
		TweenService:Create(scale, pop, { Scale = size() }):Play()
	end)

	RunService.PreRender:Connect(function()
		if not holder.Visible then
			return
		end
		local past = os.clock() - hideAt
		if past >= FADE then
			holder.Visible = false
			shownFrom = nil
			HudLayout.unstack("Speed")
			return
		end
		holder.GroupTransparency = math.clamp(past / FADE, 0, 1)
		-- it keeps moving while it shows: the whole callout bobs, the title rocks, the tag bobs out of step
		local now = os.clock()
		local bob = PlasticUi.motion(0.6)
		holder.Position = UDim2.new(0.5, 0, 0, middle() + bob)
		title.root.Rotation = -4 + 2.5 * math.sin(now * 5)
		tag.root.Position = UDim2.new(0.5, 0, 0, TITLE_TALL + 3 * math.sin(now * 4 + 1.3))
	end)
end

return SpeedCallout
