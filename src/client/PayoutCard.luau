--!strict
-- Your round's payout and record (design notes: Coins and economy, "Post-match record board"). With the victory
-- screen, a card slides in from the left with what the round paid you, line by line ("SURVIVED +30", "2 TAGS +10",
-- "BOUNTY +35", "COINS PICKED UP +6"), the total counting up, the XP, and your record: how long you lasted, your tags
-- and your first tag's time. It leaves with the victory screen. The server (Rewards) works all of it out; this only
-- draws it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ProgressRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressRules"))
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)
local Sounds = require(script.Parent.Sounds)

local PayoutCard = {}

local player = Players.LocalPlayer

-- Sizes at full scale (pixels; Claude's picks)
local WIDTH = 276
local HEAD_TALL = 40
local LINE_TALL = 23
local TOTAL_TALL = 34
local NOTE_TALL = 19
local PAD = 12
local LINES = 6
local NOTES = 3
local START = 0.5 -- s after it's sent before it slides in (the victory banner lands first)
local SLIDE = 0.35
local LINE_EVERY = 0.13 -- s between two lines popping in
local COUNT_TIME = 0.6 -- s the total counts up for
local PALE = Color3.fromHex("C8D4FF")
local CYAN = Color3.fromHex("2EE6FF")

type Line = { label: PlasticUi.Text, coins: PlasticUi.Text, holder: Frame, scale: UIScale, shown: boolean }

local function number(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

function PayoutCard.start()
	local gui = PlasticUi.screen("TagRivalsPayout", 11)
	gui.Enabled = false

	local card = PlasticUi.block({
		name = "Payout",
		width = WIDTH,
		height = 200,
		color = PlasticUi.PLATE,
		parent = gui,
		dots = false,
	})
	card.root.AnchorPoint = Vector2.new(0, 0.5)
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card.root

	local head = PlasticUi.text({ name = "Head", size = 24, parent = card.face, zIndex = 4 })
	head.root.Position = UDim2.fromOffset(0, 6)
	head.root.Size = UDim2.new(1, 0, 0, HEAD_TALL - 8)
	head:set("YOUR ROUND")
	PlasticUi.shimmer(head.label, PlasticUi.GOLD, 1.8)

	local lines: { Line } = {}
	for i = 1, LINES do
		local holder = Instance.new("Frame")
		holder.Name = "Line" .. i
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Size = UDim2.fromOffset(WIDTH - PAD * 2, LINE_TALL)
		holder.ZIndex = 4
		holder.Visible = false
		holder.Parent = card.face
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		local label = PlasticUi.text({
			name = "Label",
			size = 15,
			parent = holder,
			zIndex = 4,
			align = Enum.TextXAlignment.Left,
		})
		label.root.Size = UDim2.fromScale(1, 1)
		local coins = PlasticUi.text({
			name = "Coins",
			size = 17,
			parent = holder,
			zIndex = 4,
			color = PlasticUi.GOLD,
			align = Enum.TextXAlignment.Right,
		})
		coins.root.Size = UDim2.fromScale(1, 1)
		lines[i] = { label = label, coins = coins, holder = holder, scale = scale, shown = false }
	end

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = PlasticUi.GOLD
	rule.BorderSizePixel = 0
	rule.Size = UDim2.fromOffset(WIDTH - PAD * 2, 3)
	rule.ZIndex = 4
	rule.Parent = card.face
	local total = PlasticUi.text({ name = "Total", size = 24, parent = card.face, zIndex = 4, color = PlasticUi.GOLD })
	total.root.Size = UDim2.fromOffset(WIDTH, TOTAL_TALL)
	local totalScale = Instance.new("UIScale")
	totalScale.Parent = total.root
	local notes: { PlasticUi.Text } = {}
	for i = 1, NOTES do
		local note = PlasticUi.text({ name = "Note" .. i, size = 13, parent = card.face, zIndex = 4, color = PALE })
		note.root.Size = UDim2.fromOffset(WIDTH, NOTE_TALL)
		notes[i] = note
	end

	gui.Parent = player:WaitForChild("PlayerGui")

	local shownAt = -math.huge
	local leaving = false
	local leaveAt = -math.huge
	local lineCount = 0
	local noteCount = 0
	local totalCoins = 0
	local tall = 200
	local lastCount = -1
	local chimed = false

	local function show(payout: any)
		local list = if type(payout.lines) == "table" then payout.lines else {}
		lineCount = 0
		for i, line in lines do
			local entry = list[i]
			line.shown = false
			line.holder.Visible = false
			if type(entry) == "table" then
				lineCount = i
				line.label:set(tostring(entry.label))
				line.coins:set(`+{ProgressRules.commas(number(entry.coins))}`)
			end
		end
		totalCoins = number(payout.total)
		lastCount = -1
		chimed = false

		-- the record: a runner's time, a chaser's tags
		local record = if type(payout.record) == "table" then payout.record else {}
		local words: { string } = {}
		table.insert(words, `+{number(payout.xp)} XP`)
		if record.survived == true then
			table.insert(words, if record.clutch == true then "LAST ONE STANDING!" else "SURVIVED THE WHOLE MATCH")
		elseif number(record.time) > 0 then
			table.insert(words, `LASTED {RoundRules.clock(number(record.time))} AS A RUNNER`)
		end
		if number(record.tags) > 0 then
			local first = if type(record.firstTag) == "number" then `, FIRST AT {RoundRules.clock(record.firstTag)}` else ""
			table.insert(words, `{number(record.tags)} TAG{if number(record.tags) == 1 then "" else "S"}{first}`)
		elseif record.alpha == true then
			table.insert(words, "YOU WERE THE FIRST CHASER")
		end
		noteCount = math.min(#words, NOTES)
		for i, note in notes do
			note:set(words[i] or "")
			note:setColor(if i == 1 then CYAN else PALE)
			note.root.Visible = i <= noteCount
		end

		-- laid out for as many lines as there are
		local y = HEAD_TALL
		for i = 1, lineCount do
			lines[i].holder.Position = UDim2.fromOffset(WIDTH / 2, y + LINE_TALL / 2)
			y += LINE_TALL
		end
		rule.Position = UDim2.fromOffset(PAD, y + 3)
		y += 8
		total.root.Position = UDim2.fromOffset(0, y)
		y += TOTAL_TALL
		for i = 1, noteCount do
			notes[i].root.Position = UDim2.fromOffset(0, y)
			y += NOTE_TALL
		end
		tall = y + PAD + card.depth
		card.root.Size = UDim2.fromOffset(WIDTH, tall)

		shownAt = os.clock() + START
		leaving = false
		gui.Enabled = true
		card.root.Visible = false
	end

	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: unknown, payout: any)
		if kind == "payout" and type(payout) == "table" then
			show(payout)
		end
	end)

	RunService.PreRender:Connect(function()
		if not gui.Enabled then
			return
		end
		local now = os.clock()
		local age = now - shownAt
		if age < 0 then
			return
		end
		card.root.Visible = true
		if not leaving and Workspace:GetAttribute(RoundRules.ATTR_STATE) ~= "Cleanup" then
			leaving = true
			leaveAt = now
		end
		local out = if leaving then math.clamp((now - leaveAt) / 0.3, 0, 1) else 0
		if out >= 1 then
			gui.Enabled = false
			return
		end
		-- it fits between the timer and the dash bars, smaller if it must
		local screen = HudLayout.screen()
		local size = PlasticUi.screenScale()
		local top = HudLayout.underTimer()
		local bars = HudLayout.get("DashBars")
		local bottom = (if bars then bars.top else screen.Y) - HudLayout.GAP
		size = math.min(size, (bottom - top) / tall)
		local middle = math.clamp(screen.Y * 0.56, top + tall * size / 2, math.max(bottom - tall * size / 2, top + tall * size / 2))
		local enter = 1 - (1 - math.clamp(age / SLIDE, 0, 1)) ^ 3
		local bob, tilt = PlasticUi.motion(0.55)
		local x = HudLayout.EDGE - (1 - enter + out * out) * (WIDTH * size + HudLayout.EDGE + 20)
		card.root.Position = UDim2.fromOffset(x, middle + bob)
		card.root.Rotation = tilt * 0.3
		cardScale.Scale = size

		-- the lines pop in one after the other, each with a tick; then the total counts up
		for i = 1, lineCount do
			local line = lines[i]
			local lineAge = age - SLIDE - (i - 1) * LINE_EVERY
			if lineAge >= 0 then
				if not line.shown then
					line.shown = true
					line.holder.Visible = true
					Sounds.play("count", { pitch = 1 + 0.06 * i })
				end
				line.scale.Scale = 1 + 0.3 * math.max(1 - lineAge / 0.15, 0)
			end
		end
		local countAge = age - SLIDE - lineCount * LINE_EVERY
		local share = math.clamp(countAge / COUNT_TIME, 0, 1)
		local counted = math.floor(totalCoins * (1 - (1 - share) ^ 2) + 0.5)
		if counted ~= lastCount then
			lastCount = counted
			total:set(`TOTAL  +{ProgressRules.commas(counted)}`)
			if share > 0 and share < 1 then
				Sounds.play("count", { pitch = 1.2 + 0.6 * share, volume = 0.8 })
			end
		end
		if share >= 1 and not chimed then
			chimed = true
			if totalCoins > 0 then
				Sounds.chime(3, 4)
			end
		end
		totalScale.Scale = if share >= 1 then 1 + 0.12 * math.max(1 - (countAge - COUNT_TIME) / 0.25, 0) else 1
	end)
end

return PayoutCard
