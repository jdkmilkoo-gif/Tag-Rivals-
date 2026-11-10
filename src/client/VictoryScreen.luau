--!strict
-- The victory screen (design notes, Victory screen: Huss Zero's UI style and font). At the end of the match everyone
-- is frozen (the server) and the result slides in:
--   * runners win: a bright gold banner, "RUNNERS WIN!", with the surviving runners' names under it and gold coins
--     raining down;
--   * chasers win: a dark glitchy overlay, "THE SWARM HAS OVERTAKEN THE ARENA", listing the top chasers by tags (the
--     first chaser marked ALPHA);
--   * a round that ends without enough players: "ROUND OVER".
-- It slides away when the next intermission starts. Coins themselves (+30 to survivors) come with the saving step;
-- the rain is the look for now.
-- It fits between the timer and the dash bars (HudLayout): about a quarter of the way down on a big screen; on a phone
-- just under the timer, a little smaller, the top 3 chasers only, and the runners' banner clear of the coin counter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)

local VictoryScreen = {}

local player = Players.LocalPlayer
local RoundRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent

local BANNER_WIDE = 500 -- room round RUNNERS WIN! (was 560; narrower fits a phone)
local BANNER_TALL = 104
local GLITCH_WIDE, GLITCH_TALL = 820, 124 -- the chasers' two-line title
local HEADING_TALL = 30 -- the list's heading and each line under it, pixels at full size
local LINE_TALL = 30
local LIST_GAP = 8 -- at least this between the title and the list
local HEIGHT = 0.28 -- where the title's middle wants to be, share of the screen down
local LINES_SMALL = 3 -- top chasers listed on a phone
local LINE_TEXT = 24
local SEPARATOR = "   •   " -- between the survivors' names
local COINS = 46
local GLITCH_RED = Color3.fromHex("FF2B4A")
local GLITCH_CYAN = Color3.fromHex("2EE6FF")

type Coin = { frame: Frame, x: number, speed: number, spin: number, delay: number, sway: number }

local rng = Random.new()

function VictoryScreen.start()
	local gui = PlasticUi.screen("TagRivalsVictory", 10)
	gui.Enabled = false

	-- the chasers' dark overlay, scanlines scrolling over it
	local dark = Instance.new("Frame")
	dark.Name = "Dark"
	dark.BackgroundColor3 = Color3.fromHex("12040A")
	dark.BackgroundTransparency = 1
	dark.BorderSizePixel = 0
	dark.Size = UDim2.fromScale(1, 1)
	dark.Parent = gui
	local scan = Instance.new("Frame")
	scan.Name = "Scanlines"
	scan.BackgroundTransparency = 1
	scan.Size = UDim2.new(1, 0, 1, 40)
	scan.Parent = dark
	for i = 0, 60 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new(0, 0, 0)
		line.BackgroundTransparency = 0.75
		line.Position = UDim2.new(0, 0, i / 60, 0)
		line.Size = UDim2.new(1, 0, 0, 2)
		line.Parent = scan
	end

	-- coin rain
	local rain = Instance.new("Frame")
	rain.Name = "Coins"
	rain.BackgroundTransparency = 1
	rain.Size = UDim2.fromScale(1, 1)
	rain.Parent = gui
	local coins: { Coin } = {}
	for i = 1, COINS do
		local coin = Instance.new("Frame")
		coin.Name = "Coin"
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Size = UDim2.fromOffset(26, 26)
		coin.BackgroundColor3 = PlasticUi.GOLD
		coin.BorderSizePixel = 0
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = coin
		PlasticUi.outline(coin, 2)
		local face = Instance.new("Frame")
		face.AnchorPoint = Vector2.new(0.5, 0.5)
		face.Position = UDim2.fromScale(0.5, 0.5)
		face.Size = UDim2.fromScale(0.55, 0.55)
		face.BackgroundColor3 = Color3.fromHex("FFF1A8")
		face.BorderSizePixel = 0
		local inner = Instance.new("UICorner")
		inner.CornerRadius = UDim.new(0.5, 0)
		inner.Parent = face
		face.Parent = coin
		coin.Visible = false
		coin.Parent = rain
		coins[i] = { frame = coin, x = 0, speed = 0, spin = 0, delay = 0, sway = 0 }
	end

	-- the banner (runners) / the title (chasers)
	local banner = PlasticUi.block({
		name = "Banner",
		width = BANNER_WIDE,
		height = BANNER_TALL,
		color = PlasticUi.GOLD,
		parent = gui,
	})
	banner.root.AnchorPoint = Vector2.new(0.5, 0.5)
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner.root
	local title = PlasticUi.text({ name = "Title", size = 56, parent = banner.face, zIndex = 4 })
	title.root.Size = UDim2.fromScale(1, 1)

	-- the glitch title for the chasers: the white words with a red and a cyan copy jumping about behind them
	local glitch = Instance.new("Frame")
	glitch.Name = "Glitch"
	glitch.AnchorPoint = Vector2.new(0.5, 0.5)
	glitch.BackgroundTransparency = 1
	glitch.Size = UDim2.fromOffset(GLITCH_WIDE, GLITCH_TALL)
	glitch.Parent = gui
	local glitchScale = Instance.new("UIScale")
	glitchScale.Parent = glitch
	local redCopy = PlasticUi.text({ name = "Red", size = 52, parent = glitch, color = GLITCH_RED, zIndex = 1 })
	local cyanCopy = PlasticUi.text({ name = "Cyan", size = 52, parent = glitch, color = GLITCH_CYAN, zIndex = 2 })
	local whiteCopy = PlasticUi.text({ name = "White", size = 52, parent = glitch, zIndex = 3 })
	for _, copy in { redCopy, cyanCopy, whiteCopy } do
		copy.root.Size = UDim2.fromScale(1, 1)
		copy.label.TextWrapped = true
		copy.drop.TextWrapped = true
		copy:set("THE SWARM HAS\nOVERTAKEN THE ARENA")
	end
	-- the coloured copies have no outline or drop, so their colour shows round the white words
	for _, copy in { redCopy, cyanCopy } do
		copy.drop.Visible = false
		local stroke = copy.label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Enabled = false
		end
	end

	-- the list under it: survivors, or the top chasers
	local list = Instance.new("Frame")
	list.Name = "List"
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromOffset(BANNER_WIDE, 200)
	list.Parent = gui
	local listScale = Instance.new("UIScale")
	listScale.Parent = list
	local heading = PlasticUi.text({ name = "Heading", size = 22, parent = list, zIndex = 3 })
	heading.root.Size = UDim2.new(1, 0, 0, 26)
	PlasticUi.shimmer(heading.label, PlasticUi.GOLD, 1.6)
	local lines = {}
	for i = 1, 5 do
		local line = PlasticUi.text({ name = "Line" .. i, size = LINE_TEXT, parent = list, zIndex = 3 })
		line.root.Position = UDim2.fromOffset(0, 30 + (i - 1) * 30)
		line.root.Size = UDim2.new(1, 0, 0, 28)
		line.label.TextWrapped = true
		line.drop.TextWrapped = true
		lines[i] = line
	end

	gui.Parent = player:WaitForChild("PlayerGui")

	local shownAt = -math.huge
	local lineCount = 1 -- lines under the heading
	local mode = "None"
	local leaving = false
	local leaveAt = -math.huge

	-- The survivors' names, as many as fit on two lines (then "+3 MORE"); the bold font measures like the bold italic.
	local function fitNames(names: { any }): string
		local room = (BANNER_WIDE - 20) * 2 * 0.9 -- two lines, less what's lost where a line breaks
		local function wide(text: string): number
			return TextService:GetTextSize(text, LINE_TEXT, Enum.Font.MontserratBold, Vector2.new(100000, 100)).X
		end
		local text = ""
		for i, name in names do
			local more = #names - i
			local longer = if text == "" then tostring(name) else text .. SEPARATOR .. tostring(name)
			if wide(longer .. (if more > 0 then `{SEPARATOR}+{more} MORE` else "")) > room and text ~= "" then
				return `{text}{SEPARATOR}+{more + 1} MORE`
			end
			text = longer
		end
		return text
	end

	local function show(result: any)
		mode = if type(result.winner) == "string" then result.winner else "None"
		shownAt = os.clock()
		leaving = false
		gui.Enabled = true
		for _, line in lines do
			line:set("")
			line.root.Size = UDim2.new(1, 0, 0, 28)
		end
		local runnersWon = mode == "Runners"
		banner.root.Visible = mode ~= "Chasers"
		glitch.Visible = mode == "Chasers"
		dark.BackgroundTransparency = 1
		scan.Visible = mode == "Chasers"
		rain.Visible = runnersWon
		lineCount = 1
		if mode == "Chasers" then
			TweenService:Create(dark, TweenInfo.new(0.4), { BackgroundTransparency = 0.25 }):Play()
			heading:set("TOP CHASERS")
			local most = if HudLayout.small() then LINES_SMALL else #lines
			for i, entry in (if type(result.chasers) == "table" then result.chasers else {}) do
				if lines[i] and i <= most then
					lineCount = i
					local tags = if type(entry.tags) == "number" then entry.tags else 0
					local text = `{i}. {tostring(entry.name)}  —  {tags} tag{if tags == 1 then "" else "s"}`
					if entry.alpha == true then
						text ..= "  (ALPHA)"
					end
					lines[i]:set(text)
					lines[i]:setColor(if i == 1 then PlasticUi.GOLD else Color3.new(1, 1, 1))
				end
			end
		elseif runnersWon then
			banner:setColor(PlasticUi.GOLD)
			title:set("RUNNERS WIN!")
			heading:set("SURVIVORS")
			local names = if type(result.survivors) == "table" then result.survivors else {}
			lines[1]:set(fitNames(names))
			lines[1].root.Size = UDim2.new(1, 0, 0, 58) -- the names wrap onto a second line
			lineCount = 2
			lines[1]:setColor(Color3.new(1, 1, 1))
			for _, coin in coins do
				coin.x = rng:NextNumber()
				coin.speed = rng:NextNumber(0.35, 0.7)
				coin.spin = rng:NextNumber(-360, 360)
				coin.delay = rng:NextNumber(0, 1.6)
				coin.sway = rng:NextNumber(0, math.pi * 2)
			end
		else
			banner:setColor(PlasticUi.PANEL)
			title:set("ROUND OVER")
			heading:set("")
			lines[1]:set("Not enough players to finish the round")
			lines[1]:setColor(Color3.new(1, 1, 1))
		end
	end

	RoundRemote.OnClientEvent:Connect(function(kind: string, a: any)
		if kind == "victory" and type(a) == "table" then
			show(a)
		end
	end)

	RunService.PreRender:Connect(function()
		if not gui.Enabled then
			return
		end
		local now = os.clock()
		local state = Workspace:GetAttribute(RoundRules.ATTR_STATE)
		if not leaving and state ~= "Cleanup" then
			leaving = true
			leaveAt = now
			TweenService:Create(dark, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		end
		local screenScale = PlasticUi.screenScale()
		local age = now - shownAt
		-- slide in from the top; slide out upward when leaving
		local enter = 1 - (1 - math.clamp(age / 0.5, 0, 1)) ^ 3
		local out = if leaving then math.clamp((now - leaveAt) / 0.35, 0, 1) else 0
		if leaving and out >= 1 then
			gui.Enabled = false
			return
		end

		-- where it rests: the title, then the list, between the timer and the dash bars, smaller if it must be
		local screen = HudLayout.screen()
		local titleTall = if mode == "Chasers" then GLITCH_TALL else BANNER_TALL
		local listTall = HEADING_TALL + LINE_TALL * lineCount
		local top = HudLayout.underTimer()
		local bars = HudLayout.get("DashBars")
		local bottom = (if bars then bars.top else screen.Y) - HudLayout.GAP
		local size = math.min(screenScale, (bottom - top) / (titleTall + LIST_GAP + listTall))
		-- the runners' bright banner (no dark overlay) stays clear of the coin counter and the Dash button on the right
		if mode ~= "Chasers" then
			for _, name in { "Coin", "DashButton" } do
				local piece = HudLayout.get(name)
				if piece then
					local room = math.max(2 * (piece.left - HudLayout.GAP - screen.X / 2), 0)
					size = math.min(size, room / BANNER_WIDE)
				end
			end
		end
		-- the list sits where it always did on a big screen (a tenth of the screen and a bit under the title's middle)
		local wantGap = screen.Y * 0.1 + 40 * size - titleTall * size / 2
		local gap = math.max(LIST_GAP * size, math.min(wantGap, bottom - top - (titleTall + listTall) * size))
		local middle = screen.Y * HEIGHT
		middle = math.min(middle, bottom - listTall * size - gap - titleTall * size / 2)
		middle = math.max(middle, top + titleTall * size / 2)
		-- sliding: in from above the screen, out upward
		middle -= (1 - enter) * (middle + titleTall * size) + 0.6 * screen.Y * out * out

		local bob, tilt = PlasticUi.motion(0.1)
		banner.root.Position = UDim2.new(0.5, 0, 0, middle + bob)
		banner.root.Rotation = -2 + math.sin(now * 2.2) * 1.5 + tilt * 0.3
		-- it pops in: back-eased from a fifth of its size
		local x = math.clamp(age / 0.45, 0, 1)
		local back = 1 + 2.70158 * (x - 1) ^ 3 + 1.70158 * (x - 1) ^ 2
		bannerScale.Scale = size * (0.2 + 0.8 * back)
		glitch.Position = UDim2.new(0.5, 0, 0, middle + bob)
		glitchScale.Scale = size
		list.Position = UDim2.new(0.5, 0, 0, middle + titleTall * size / 2 + gap + bob)
		listScale.Scale = size

		if mode == "Chasers" then
			-- the glitch: the coloured copies jump about, now and then the whole title jerks sideways
			local jolt = if math.floor(now * 9) % 7 == 0 then rng:NextNumber(-10, 10) else 0
			redCopy.root.Position = UDim2.fromOffset(rng:NextNumber(-9, -3) + jolt, rng:NextNumber(-3, 3))
			cyanCopy.root.Position = UDim2.fromOffset(rng:NextNumber(3, 9) - jolt, rng:NextNumber(-3, 3))
			whiteCopy.root.Position = UDim2.fromOffset(jolt * 0.4, 0)
			scan.Position = UDim2.fromOffset(0, -((now * 30) % 20))
		end

		if mode == "Runners" then
			for _, coin in coins do
				local t = age - coin.delay
				if t < 0 then
					coin.frame.Visible = false
				else
					local fall = (t * coin.speed) % 1.2 - 0.1
					coin.frame.Visible = true
					coin.frame.Position = UDim2.new(coin.x, math.sin(t * 3 + coin.sway) * 20, fall, 0)
					coin.frame.Rotation = t * coin.spin
					-- a coin turning: squash it across as it spins
					local turn = math.abs(math.cos(t * 6 + coin.sway))
					local size = 26 * screenScale
					coin.frame.Size = UDim2.fromOffset(math.max(size * turn, 3), size)
				end
			end
		end
	end)
end

return VictoryScreen
