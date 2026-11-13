--!strict
-- The QUESTS panel (design notes, Coins and economy: 3 random quests each in Daily, Weekly and Monthly). It only draws
-- what the server sends and asks for things; the server (Quests) decides everything.
--   * three tabs, and under them when the set you're looking at is dealt afresh;
--   * a row a quest: what to do, a bar filling as you do it, and the coins it pays;
--   * the row's button: CLAIM (green, pulsing) once it's done; before that REROLL, when a swap is to be had: the free
--     daily one, a reroll you bought earlier, or the Robux one (only once its product ids are in Config.Quests);
--   * rows slide in one after the other when the panel opens or the tab changes, bars fill smoothly, a claimed row
--     punches.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local QuestRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("QuestRules"))
local PlasticUi = require(script.Parent.PlasticUi)
local ProgressLink = require(script.Parent.ProgressLink)
local UiKit = require(script.Parent.UiKit)

local QuestPanel = {}

-- Sizes at full scale (pixels; Claude's picks)
local WIDTH, HEIGHT = 640, 432
local TAB_W, TAB_H = 140, 44
local ROW_H = 92
local ROW_GAP = 6
local ROWS_TOP = 54
local BUTTON_W, BUTTON_H = 164, 56
local BAR_W, BAR_H = 300, 18
local PALE = Color3.fromHex("C8D4FF")
local BLUE_DARK = Color3.fromHex("0F1F5C")

type Row = {
	block: PlasticUi.Block,
	scale: UIScale,
	title: PlasticUi.Text,
	text: PlasticUi.Text,
	fill: Frame,
	count: PlasticUi.Text,
	reward: PlasticUi.Text,
	button: UiKit.Button,
	share: number, -- the bar's fill as drawn
	want: number, -- and where it's going
	mode: string, -- what the button does: "claim", "reroll", or "" (nothing)
	punchAt: number,
}

local panel: UiKit.Panel? = nil

function QuestPanel.toggle()
	local p = panel
	if p then
		if p:isOpen() then
			p:close()
		else
			p:open()
		end
	end
end

function QuestPanel.start()
	local snapshot: any = nil
	local gotAt = 0 -- os.clock() the snapshot came
	local tab: QuestRules.SetName = "daily"
	local shownAt = os.clock() -- when the rows last slid in
	local rows: { Row } = {}

	local made = UiKit.panel({
		name = "Quests",
		title = "QUESTS",
		width = WIDTH,
		height = HEIGHT,
		onOpen = function()
			shownAt = os.clock()
			ProgressLink.send("quests")
		end,
	})
	panel = made
	local content = made.content
	local roomW = made.width

	local redraw: () -> ()

	-- the tabs
	local tabs: { [string]: UiKit.Button } = {}
	for i, set in QuestRules.SETS do
		local button = UiKit.button({
			name = "Tab" .. set,
			width = TAB_W,
			height = TAB_H,
			color = PlasticUi.PANEL,
			text = QuestRules.SET_TITLES[set],
			textSize = 20,
			parent = content,
			onClick = function()
				if tab ~= set then
					tab = set
					shownAt = os.clock()
					redraw()
				end
			end,
		})
		button.block.root.Position = UDim2.fromOffset(TAB_W / 2 + (i - 1) * (TAB_W + 6), TAB_H / 2)
		tabs[set] = button
	end
	local timer = PlasticUi.text({ name = "Timer", size = 15, parent = content, zIndex = 4, color = PALE })
	timer.root.Position = UDim2.fromOffset(3 * (TAB_W + 6), 4)
	timer.root.Size = UDim2.fromOffset(roomW - 3 * (TAB_W + 6), TAB_H - 8)
	timer.label.TextWrapped = true
	timer.drop.TextWrapped = true

	-- the rows
	for i = 1, 3 do
		local block = PlasticUi.block({
			name = "Quest" .. i,
			width = roomW,
			height = ROW_H,
			color = PlasticUi.PANEL,
			parent = content,
			depth = 5,
			dotsCover = 0.5,
		})
		block.root.AnchorPoint = Vector2.new(0.5, 0.5)
		local scale = Instance.new("UIScale")
		scale.Parent = block.root
		local title = PlasticUi.text({
			name = "Title",
			size = 20,
			parent = block.face,
			zIndex = 4,
			align = Enum.TextXAlignment.Left,
		})
		title.root.Position = UDim2.fromOffset(12, 5)
		title.root.Size = UDim2.fromOffset(roomW - BUTTON_W - 36, 24)
		local text = PlasticUi.text({
			name = "Text",
			size = 14,
			parent = block.face,
			zIndex = 4,
			color = PALE,
			align = Enum.TextXAlignment.Left,
		})
		text.root.Position = UDim2.fromOffset(12, 30)
		text.root.Size = UDim2.fromOffset(roomW - BUTTON_W - 36, 18)

		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BackgroundColor3 = BLUE_DARK
		bar.BorderSizePixel = 0
		bar.Position = UDim2.fromOffset(12, 56)
		bar.Size = UDim2.fromOffset(BAR_W, BAR_H)
		bar.ZIndex = 4
		PlasticUi.outline(bar, 2)
		bar.Parent = block.face
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = PlasticUi.GOLD
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = bar
		local count = PlasticUi.text({ name = "Count", size = 12, parent = bar, zIndex = 5 })
		count.root.Size = UDim2.fromScale(1, 1)

		local reward = PlasticUi.text({
			name = "Reward",
			size = 20,
			parent = block.face,
			zIndex = 4,
			color = PlasticUi.GOLD,
			align = Enum.TextXAlignment.Left,
		})
		reward.root.Position = UDim2.fromOffset(12 + BAR_W + 12, 52)
		reward.root.Size = UDim2.fromOffset(110, 26)

		local row: Row
		local button = UiKit.button({
			name = "Button",
			width = BUTTON_W,
			height = BUTTON_H,
			color = PlasticUi.DONE,
			text = "",
			textSize = 20,
			parent = block.face,
			onClick = function()
				if row.mode == "claim" then
					row.punchAt = os.clock()
					ProgressLink.send("claim", tab, i)
				elseif row.mode == "reroll" then
					ProgressLink.send("reroll", tab, i)
				end
			end,
		})
		button.block.root.Position = UDim2.fromOffset(roomW - 12 - BUTTON_W / 2, (ROW_H - 5) / 2)
		button.block.root.ZIndex = 5
		row = {
			block = block,
			scale = scale,
			title = title,
			text = text,
			fill = fill,
			count = count,
			reward = reward,
			button = button,
			share = 0,
			want = 0,
			mode = "",
			punchAt = -math.huge,
		}
		rows[i] = row
	end

	redraw = function()
		for set, button in tabs do
			button:setColor(if set == tab then PlasticUi.GOLD else PlasticUi.PANEL)
		end
		local state = if type(snapshot) == "table" and type(snapshot.sets) == "table" then snapshot.sets[tab] else nil
		local list = if type(state) == "table" and type(state.list) == "table" then state.list else {}
		for i, row in rows do
			local entry = list[i]
			local quest = if type(entry) == "table" and type(entry.id) == "string" then QuestRules.get(entry.id) else nil
			row.block.root.Visible = quest ~= nil
			if quest then
				local progress = if type(entry.progress) == "number" then entry.progress else 0
				local done = progress >= quest.goal
				row.title:set(quest.title)
				row.text:set(QuestRules.describe(quest))
				row.count:set(`{math.min(progress, quest.goal)} / {quest.goal}`)
				row.reward:set(`+{quest.reward} coins`)
				row.want = math.clamp(progress / math.max(quest.goal, 1), 0, 1)
				local button = row.button
				button.block.root.Visible = true
				if entry.claimed == true then
					row.mode = ""
					button:setText("CLAIMED")
					button:setColor(UiKit.GREY)
					button:setEnabled(false)
				elseif done then
					row.mode = "claim"
					button:setText("CLAIM!")
					button:setColor(PlasticUi.DONE)
					button:setEnabled(true)
				else
					-- a swap: the free one, one bought earlier, or the Robux one
					local free = if type(state.free) == "number" then state.free else 0
					local tokens = if type(state.tokens) == "number" then state.tokens else 0
					row.mode = "reroll"
					button:setColor(PlasticUi.PANEL)
					button:setEnabled(true)
					if free > 0 then
						button:setText("REROLL FREE")
					elseif tokens > 0 then
						button:setText(`REROLL x{tokens}`)
					elseif state.paid == true and type(state.price) == "number" then
						button:setText(`REROLL R${state.price}`)
					else
						row.mode = ""
						button.block.root.Visible = false
					end
				end
			end
		end
	end

	ProgressLink.on("quests", function(new: any)
		if type(new) == "table" then
			snapshot = new
			gotAt = os.clock()
			redraw()
		end
	end)
	-- a reroll was bought (or not): the server sends the quests again either way; ask once more in case it's slow
	MarketplaceService.PromptProductPurchaseFinished:Connect(function()
		task.delay(1.5, function()
			ProgressLink.send("quests")
		end)
	end)
	redraw()

	RunService.PreRender:Connect(function(dt: number)
		if not made.gui.Enabled then
			return
		end
		local now = os.clock()
		-- when this set is dealt afresh, by the server's clock
		if type(snapshot) == "table" and type(snapshot.now) == "number" then
			local unix = snapshot.now + (now - gotAt)
			local left = QuestRules.untilRefresh(tab, unix)
			timer:set(`NEW {QuestRules.SET_TITLES[tab]} QUESTS IN {QuestRules.timeText(left)}`)
			if left <= 0.5 and now - gotAt > 2 then
				gotAt = now -- (so it asks once, not every frame)
				ProgressLink.send("quests")
			end
		else
			timer:set("LOADING...")
		end
		for i, row in rows do
			-- rows slide in from the right, one after the other
			local t = math.clamp((now - shownAt - (i - 1) * 0.06) / 0.28, 0, 1)
			local ease = 1 - (1 - t) ^ 3
			local y = ROWS_TOP + (i - 1) * (ROW_H + ROW_GAP) + ROW_H / 2
			row.block.root.Position = UDim2.fromOffset(roomW / 2 + (1 - ease) * 70, y + math.sin(now * 2 + i) * 1.5)
			local punchAge = now - row.punchAt
			local punch = if punchAge >= 0 and punchAge < 0.3 then 1 + 0.06 * math.sin(math.pi * punchAge / 0.3) else 1
			row.scale.Scale = (0.9 + 0.1 * ease) * punch
			row.share += (row.want - row.share) * (1 - math.exp(-9 * dt))
			row.fill.Size = UDim2.fromScale(row.share, 1)
			if row.mode == "claim" then
				local beat = 0.5 + 0.5 * math.sin(now * math.pi * 3 + i)
				row.button.text:setColor(Color3.new(1, 1, 1):Lerp(PlasticUi.GOLD, beat))
			else
				row.button.text:setColor(Color3.new(1, 1, 1))
			end
		end
	end)
end

return QuestPanel
