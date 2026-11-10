--!strict
-- One plan for where the HUD's pieces sit, so nothing covers anything else, phones included (owner 2026-11-10: "bro i
-- think you shiuld clean up the mobile ui abit"). Every HUD screen (PlasticUi.screen) shares one space: the screen
-- inside the phone's safe area, in pixels from its top-left (the same size as the camera's view).
--   * Each fixed piece says where it rests, every frame it shows (HudLayout.report): the timer, the runner counter, the
--     coin counter, the phone Dash button's plate, the dash bars and the tag feed. The others read that
--     (HudLayout.get) and keep clear of it. Resting means without the bob, the slide in and out or a punch.
--   * The pop-ups (the shrink countdown, SPEED UP!, TAGGED! and the others) stack down from under the timer
--     (HudLayout.stack): each goes where it wants to, or just under the pop-ups above it that are showing, so two
--     never cover each other, the timer or the dash bars. On a phone they're drawn a little smaller
--     (HudLayout.popScale), and a call-out is squeezed a bit more where it would reach the tag feed or the coin
--     counter (HudLayout.halfRoom) or when there's no room left under the others (HudLayout.freeTop).
-- Its numbers are here, not in Config, so the layout is all in one place (Claude's picks).

local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local PlasticUi = require(script.Parent.PlasticUi)

local SMALL_POP_SCALE = 0.85 -- on a phone the pop-ups (SPEED UP!, TAGGED!, the shrink countdown) are this much smaller
local TOPBAR_FALLBACK = 58 -- how far down Roblox's own top-left buttons reach, until Roblox says

export type Rect = { left: number, top: number, right: number, bottom: number }

local HudLayout = {}

HudLayout.GAP = 8 -- screen pixels kept between two pieces
HudLayout.EDGE = 12 -- screen pixels from the screen's sides

-- The pop-ups, top to bottom: the shrink countdown right under the timer, then the round's big call-outs (TAGGED!, GO!,
-- DODGED!), then its small ones (+1 TAG), then SPEED UP! low down just above the dash bars (owner 2026-11-10).
local POP_ORDER = { "Shrink", "Middle", "Small", "Speed" }

local rests: { [string]: Rect } = {}
local pops: { [string]: Rect } = {}

-- The HUD's space on this screen, in pixels.
function HudLayout.screen(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(800, 420)
end

-- How big the HUD is drawn (PlasticUi.screenScale).
function HudLayout.scale(): number
	return PlasticUi.screenScale()
end

-- A phone-sized screen (PlasticUi.isPhone; there the whole HUD is drawn smaller too).
function HudLayout.small(): boolean
	return PlasticUi.isPhone()
end

-- How big the pop-ups are drawn: a little smaller on a phone.
function HudLayout.popScale(): number
	return HudLayout.scale() * (if HudLayout.small() then SMALL_POP_SCALE else 1)
end

function HudLayout.rect(left: number, top: number, right: number, bottom: number): Rect
	return { left = left, top = top, right = right, bottom = bottom }
end

-- A fixed piece says where it rests (nil while it's away).
function HudLayout.report(name: string, rect: Rect?)
	rests[name] = rect
end

-- Where a fixed piece rests, if it's showing.
function HudLayout.get(name: string): Rect?
	return rests[name]
end

-- Do two pieces overlap, or come closer than `gap` pixels?
function HudLayout.touches(a: Rect, b: Rect, gap: number?): boolean
	local g = gap or 0
	return a.left < b.right + g and b.left < a.right + g and a.top < b.bottom + g and b.top < a.bottom + g
end

-- How far down Roblox's own buttons in the top-left corner reach.
function HudLayout.robloxButtonsBottom(): number
	local bottom = GuiService.TopbarInset.Max.Y
	return if bottom > 0 then bottom else TOPBAR_FALLBACK
end

-- Just under the timer, where the pop-ups start.
function HudLayout.underTimer(): number
	local timer = rests.Timer
	local bottom = if timer then timer.bottom else 10 + 102 * HudLayout.scale()
	return bottom + HudLayout.GAP
end

-- The lowest a pop-up reaches: just above the dash bars (or the bottom of the screen).
function HudLayout.floor(): number
	local bars = rests.DashBars
	return (if bars then bars.top else HudLayout.screen().Y) - HudLayout.GAP
end

-- Where a pop-up `tall` pixels high would start: its own top `want`, but never over the timer, and pushed down under
-- any pop-up above it in the stack that's showing. If that leaves less than `tall` above HudLayout.floor, the pop-up
-- can be drawn smaller to fit (RoundHud's call-outs are).
function HudLayout.freeTop(name: string, want: number, tall: number): number
	local top = math.max(want, HudLayout.underTimer())
	for _, other in POP_ORDER do
		if other == name then
			break
		end
		local above = pops[other]
		if above and above.bottom + HudLayout.GAP > top and above.top < top + tall then
			top = above.bottom + HudLayout.GAP
		end
	end
	return top
end

-- Where a pop-up `tall` pixels high goes this frame (HudLayout.freeTop, and never below HudLayout.floor). Call it
-- every frame the pop-up shows, and HudLayout.unstack once it's gone.
function HudLayout.stack(name: string, want: number, tall: number): number
	local top = math.min(HudLayout.freeTop(name, want, tall), HudLayout.floor() - tall)
	pops[name] = HudLayout.rect(0, top, 0, top + tall)
	return top
end

function HudLayout.unstack(name: string)
	pops[name] = nil
end

-- The fixed pieces at the screen's sides that a pop-up in the middle can reach on a phone.
local SIDE_PIECES = { "Feed", "Coin", "DashButton" }

-- How far either side of the screen's middle a pop-up can reach between `top` and `bottom` (pixels down) without
-- covering the tag feed, the coin counter or the Dash button beside it.
function HudLayout.halfRoom(top: number, bottom: number): number
	local middle = HudLayout.screen().X / 2
	local room = middle - HudLayout.EDGE
	for _, name in SIDE_PIECES do
		local piece = rests[name]
		if piece and piece.top < bottom and top < piece.bottom then
			if piece.left >= middle then
				room = math.min(room, piece.left - HudLayout.GAP - middle)
			elseif piece.right <= middle then
				room = math.min(room, middle - HudLayout.GAP - piece.right)
			end
		end
	end
	return room
end

return HudLayout
