--!strict
-- "YOU'RE IN NEXT ROUND!" (owner 2026-11-11, from the launch checklist: "Keep waiting, shorter break"; a new player
-- who joins mid-round still waits on the lobby, but now sees when they play). In Huss Zero's style: gold bold italic
-- words with a glint, over a chunky blue plastic tag with "STARTS IN 1:12" and moving halftone dots.
--   * Shows on the lobby during the break, and while a round is on that you're not in (you joined late). Hidden
--     during the end screen (it sits where the end screen goes) and while the game waits for players.
--   * The time counts to the next round's fade to black: during the break that's the break's own clock; during a
--     match it counts as if the match runs its full time, so it drops when a match ends early.
--   * It pops in, bobs, the words rock and glint, every second the tag ticks, and the last 5 s turn gold and pulse.
--     It's the first of the pop-ups under the timer (HudLayout), drawn a little smaller on a phone and squeezed if it
--     would reach the tag feed or the coin counter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)

local R = Config.Round

local NextRound = {}

local player = Players.LocalPlayer

-- Sizes at full scale (pixels; Claude's picks)
local WIDTH = 380
local TITLE_SIZE = 36
local TITLE_TALL = 44
local TAG_W, TAG_TALL = 250, 50
local TALL = TITLE_TALL + 4 + TAG_TALL
local SIZE = 0.8 -- share of the pop-ups' size (HudLayout.popScale) it's drawn at
local SQUEEZE_MIN = 0.6 -- squeezed beside the tag feed or the coin counter, it keeps this share of its size
local FADE = 0.3 -- s to fade out
local POP_TIME = 0.32 -- s to pop in from half size
local FINAL = 5 -- the last seconds turn gold and pulse

local function number(value: any, default: number): number
	return if type(value) == "number" then value else default
end

-- Seconds until the next round's fade to black, for someone on the lobby (`inRound` false) or in the round; nil when
-- it shouldn't show.
function NextRound.secondsLeft(state: string, left: number, inRound: boolean): number?
	if state == "Intermission" then
		return left
	elseif inRound then
		return nil
	elseif state == "Match" then
		return left + R.CLEANUP + R.INTERMISSION
	elseif state == "Teleport" then
		return left + R.MATCH + R.CLEANUP + R.INTERMISSION
	end
	return nil -- waiting for players, or the end screen
end

function NextRound.start()
	local gui = PlasticUi.screen("TagRivalsNextRound", 5)

	local holder = Instance.new("CanvasGroup") -- fades as one piece
	holder.Name = "NextRound"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(WIDTH, TALL)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local title = PlasticUi.text({ name = "Title", size = TITLE_SIZE, parent = holder, zIndex = 3 })
	title.root.Size = UDim2.fromOffset(WIDTH, TITLE_TALL)
	title:set("YOU'RE IN NEXT ROUND!")
	PlasticUi.shimmer(title.label, PlasticUi.GOLD, 1.6)

	local tag = PlasticUi.block({
		name = "Tag",
		width = TAG_W,
		height = TAG_TALL,
		color = PlasticUi.PANEL,
		parent = holder,
	})
	tag.root.AnchorPoint = Vector2.new(0.5, 0)
	local tagScale = Instance.new("UIScale")
	tagScale.Parent = tag.root
	local clock = PlasticUi.text({ name = "Clock", size = 28, parent = tag.face, zIndex = 4 })
	clock.root.Size = UDim2.fromScale(1, 1)

	gui.Parent = player:WaitForChild("PlayerGui")

	local showing = false
	local shownAt = -math.huge
	local hiddenAt = -math.huge
	local lastWhole = -1
	local tickAt = -math.huge

	-- how big it's drawn and where its top goes this frame: first under the timer, smaller if the tag feed or the
	-- coin counter is beside it
	local function place(): (number, number)
		local size = HudLayout.popScale() * SIZE
		local top = HudLayout.stack("Next", HudLayout.underTimer(), TALL * size)
		local room = HudLayout.halfRoom(top, top + TALL * size)
		local fit = math.min(size, 2 * room / WIDTH)
		if fit < size then
			size = math.max(fit, size * SQUEEZE_MIN)
			top = HudLayout.stack("Next", HudLayout.underTimer(), TALL * size)
		end
		return top, size
	end

	RunService.PreRender:Connect(function()
		local now = os.clock()
		local state = Workspace:GetAttribute(RoundRules.ATTR_STATE)
		local endsAt = number(Workspace:GetAttribute(RoundRules.ATTR_ENDS_AT), 0)
		local left = if endsAt > 0 then math.max(endsAt - Workspace:GetServerTimeNow(), 0) else 0
		local inRound = player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
		local seconds = if type(state) == "string" and endsAt > 0
			then NextRound.secondsLeft(state, left, inRound)
			else nil

		if seconds and not showing then
			showing = true
			shownAt = now
			holder.Visible = true
		elseif not seconds and showing then
			showing = false
			hiddenAt = now
		end
		if not holder.Visible then
			return
		end
		if not showing and now - hiddenAt >= FADE then
			holder.Visible = false
			HudLayout.unstack("Next")
			lastWhole = -1
			return
		end

		if seconds then
			local whole = math.max(math.ceil(seconds - 1e-3), 0)
			if whole ~= lastWhole then
				if lastWhole >= 0 then
					tickAt = now
				end
				lastWhole = whole
				clock:set("STARTS IN  " .. RoundRules.clock(seconds))
			end
			local final = whole <= FINAL
			if final then
				local beat = 0.5 + 0.5 * math.sin(now * math.pi * 4)
				clock:setColor(Color3.new(1, 1, 1):Lerp(PlasticUi.GOLD, 0.5 + 0.5 * beat))
			else
				clock:setColor(Color3.new(1, 1, 1))
			end
		end

		-- fades out once it's no longer needed; pops in from half size with a little overshoot (back ease out)
		holder.GroupTransparency = if showing then 0 else math.clamp((now - hiddenAt) / FADE, 0, 1)
		local top, size = place()
		local bob = PlasticUi.motion(0.3)
		holder.Position = UDim2.new(0.5, 0, 0, top + TALL * size / 2 + bob)
		local t = math.clamp((now - shownAt) / POP_TIME, 0, 1) - 1
		scale.Scale = size * (0.5 + 0.5 * (1 + 2.70158 * t * t * t + 1.70158 * t * t))
		title.root.Rotation = -3 + 2 * math.sin(now * 4)
		tag.root.Position = UDim2.new(0.5, 0, 0, TITLE_TALL + 4 + 2 * math.sin(now * 3.5 + 1.1))
		-- every second the tag ticks: a quick punch bigger and back
		local tickAge = now - tickAt
		tagScale.Scale = if tickAge >= 0 and tickAge < 0.2 then 1 + 0.08 * math.sin(math.pi * tickAge / 0.2) else 1
	end)
end

return NextRound
