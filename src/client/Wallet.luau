--!strict
-- The lobby's corner (design notes: Coins and economy, Levels and titles): your wallet and the menu's buttons, on the
-- left of the screen while you're not in a round.
--   * the wallet card: your level on a gold tile, your title, the XP bar filling toward the next level, and your
--     coins, which count up when you earn some while the card punches;
--   * under it the QUESTS and CODES buttons (a red badge on QUESTS counts the rewards waiting to be claimed);
--   * coins you're paid pop up as gold words ("+5 TAG") beside the wallet, or beside the coin counter in a round;
--   * a new level, the daily bonus and a finished quest are shouted in the round's call-outs (RoundHud.say).
-- It slides away to the left when your round starts and back when you return, keeps clear of Roblox's own buttons and
-- the runner counter, and says where it rests (HudLayout "Wallet").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)
local QuestRules = require(ReplicatedStorage.Shared.QuestRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local CodesPanel = require(script.Parent.CodesPanel)
local HudLayout = require(script.Parent.HudLayout)
local PlasticUi = require(script.Parent.PlasticUi)
local ProgressLink = require(script.Parent.ProgressLink)
local QuestPanel = require(script.Parent.QuestPanel)
local RoundHud = require(script.Parent.RoundHud)
local UiKit = require(script.Parent.UiKit)

local Wallet = {}

local player = Players.LocalPlayer

-- Sizes at full scale (pixels; Claude's picks)
local CARD_W, CARD_H = 236, 100
local BUTTON_W, BUTTON_H = 114, 60
local GAP = 8
local GROUP_H = CARD_H + GAP + BUTTON_H
local TILE_W, TILE_H = 62, 70
local BAR_W, BAR_H = 142, 14
local SLIDE_TIME = 0.35
local PUNCH_TIME = 0.3
local TOASTS = 5
local TOAST_TIME = 1.4
local TOAST_RISE = 46

type Toast = { text: PlasticUi.Text, at: number, live: boolean, slot: number }

local function number(value: unknown): number
	return if type(value) == "number" then value else 0
end

function Wallet.start()
	local gui = PlasticUi.screen("TagRivalsWallet", 4)

	local group = Instance.new("Frame")
	group.Name = "Wallet"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromOffset(CARD_W, GROUP_H)
	group.Parent = gui
	local groupScale = Instance.new("UIScale")
	groupScale.Parent = group

	---------------------------------------------------------------- the card
	local card = PlasticUi.block({ name = "Card", width = CARD_W, height = CARD_H, color = PlasticUi.PANEL, parent = group })
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromOffset(CARD_W / 2, CARD_H / 2)
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card.root

	local tile = PlasticUi.block({
		name = "Level",
		width = TILE_W,
		height = TILE_H,
		color = PlasticUi.GOLD,
		parent = card.face,
		depth = 4,
		dots = false,
	})
	tile.root.Position = UDim2.fromOffset(10, 10)
	tile.root.ZIndex = 4
	local tileWord = PlasticUi.text({ name = "Word", size = 12, parent = tile.face, zIndex = 4 })
	tileWord.root.Position = UDim2.fromOffset(0, 4)
	tileWord.root.Size = UDim2.new(1, 0, 0, 14)
	tileWord:set("LEVEL")
	local tileNumber = PlasticUi.text({ name = "Number", size = 32, parent = tile.face, zIndex = 4 })
	tileNumber.root.Position = UDim2.fromOffset(0, 20)
	tileNumber.root.Size = UDim2.new(1, 0, 0, 40)
	tileNumber:set("1")

	local left = 10 + TILE_W + 10
	local title = PlasticUi.text({
		name = "Title",
		size = 20,
		parent = card.face,
		zIndex = 4,
		align = Enum.TextXAlignment.Left,
	})
	title.root.Position = UDim2.fromOffset(left, 8)
	title.root.Size = UDim2.fromOffset(BAR_W, 24)
	title:set("ROOKIE")

	local bar = Instance.new("Frame")
	bar.Name = "XpBar"
	bar.BackgroundColor3 = Color3.fromHex("0F1F5C")
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(left, 36)
	bar.Size = UDim2.fromOffset(BAR_W, BAR_H)
	bar.ZIndex = 4
	PlasticUi.outline(bar, 2)
	bar.Parent = card.face
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = PlasticUi.GOLD
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	local barText = PlasticUi.text({ name = "Xp", size = 11, parent = bar, zIndex = 5 })
	barText.root.Size = UDim2.fromScale(1, 1)

	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.BackgroundColor3 = PlasticUi.GOLD
	coin.BorderSizePixel = 0
	coin.Position = UDim2.fromOffset(left, 58)
	coin.Size = UDim2.fromOffset(24, 24)
	coin.ZIndex = 4
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = coin
	PlasticUi.outline(coin, 2)
	local coinFace = Instance.new("Frame")
	coinFace.AnchorPoint = Vector2.new(0.5, 0.5)
	coinFace.Position = UDim2.fromScale(0.5, 0.5)
	coinFace.Size = UDim2.fromScale(0.5, 0.5)
	coinFace.BackgroundColor3 = Color3.fromHex("FFF1A8")
	coinFace.BorderSizePixel = 0
	local inner = Instance.new("UICorner")
	inner.CornerRadius = UDim.new(0.5, 0)
	inner.Parent = coinFace
	coinFace.Parent = coin
	coin.Parent = card.face
	local coins = PlasticUi.text({
		name = "Coins",
		size = 24,
		parent = card.face,
		zIndex = 4,
		color = PlasticUi.GOLD,
		align = Enum.TextXAlignment.Left,
	})
	coins.root.Position = UDim2.fromOffset(left + 30, 56)
	coins.root.Size = UDim2.fromOffset(BAR_W - 30, 28)
	coins:set("0")

	---------------------------------------------------------------- the menu's buttons
	local buttonY = CARD_H + GAP + BUTTON_H / 2
	local quests = UiKit.button({
		name = "Quests",
		width = BUTTON_W,
		height = BUTTON_H,
		color = PlasticUi.GOLD,
		text = "QUESTS",
		textSize = 22,
		parent = group,
		onClick = function()
			QuestPanel.toggle()
		end,
	})
	quests.block.root.Position = UDim2.fromOffset(BUTTON_W / 2, buttonY)
	local codes = UiKit.button({
		name = "Codes",
		width = BUTTON_W,
		height = BUTTON_H,
		color = PlasticUi.DONE,
		text = "CODES",
		textSize = 22,
		parent = group,
		onClick = function()
			CodesPanel.toggle()
		end,
	})
	codes.block.root.Position = UDim2.fromOffset(CARD_W - BUTTON_W / 2, buttonY)

	-- the badge: rewards waiting on the QUESTS button
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -6, 0, 6)
	badge.Size = UDim2.fromOffset(26, 26)
	badge.BackgroundColor3 = UiKit.RED
	badge.BorderSizePixel = 0
	badge.ZIndex = 30
	badge.Visible = false
	local badgeRound = Instance.new("UICorner")
	badgeRound.CornerRadius = UDim.new(0.5, 0)
	badgeRound.Parent = badge
	PlasticUi.outline(badge, 2)
	local badgeScale = Instance.new("UIScale")
	badgeScale.Parent = badge
	local badgeText = PlasticUi.text({ name = "Count", size = 16, parent = badge, zIndex = 31 })
	badgeText.root.Size = UDim2.fromScale(1, 1)
	badge.Parent = quests.block.root

	---------------------------------------------------------------- "+5 TAG"
	local toastGui = PlasticUi.screen("TagRivalsCoinToasts", 7)
	local toasts: { Toast } = {}
	for i = 1, TOASTS do
		local text = PlasticUi.text({ name = "Toast" .. i, size = 24, parent = toastGui, color = PlasticUi.GOLD, zIndex = 2 })
		text.root.Size = UDim2.fromOffset(260, 30)
		text.root.Visible = false
		local scale = Instance.new("UIScale")
		scale.Parent = text.root
		toasts[i] = { text = text, at = 0, live = false, slot = 0 }
	end
	local function toast(words: string)
		local pick: Toast? = nil
		local busy = 0
		for _, each in toasts do
			if each.live then
				busy += 1
			elseif not pick then
				pick = each
			end
		end
		local chosen = pick or toasts[1]
		chosen.live = true
		chosen.at = os.clock()
		chosen.slot = busy
		chosen.text:set(words)
		chosen.text.root.Visible = true
	end

	gui.Parent = player:WaitForChild("PlayerGui")
	toastGui.Parent = player:WaitForChild("PlayerGui")

	---------------------------------------------------------------- what the server says
	local claimable = 0
	ProgressLink.on("quests", function(snapshot: any)
		local count = 0
		if type(snapshot) == "table" and type(snapshot.sets) == "table" then
			for _, set in snapshot.sets do
				if type(set) == "table" and type(set.list) == "table" then
					for _, entry in set.list do
						local quest = if type(entry) == "table" and type(entry.id) == "string"
							then QuestRules.get(entry.id)
							else nil
						if quest and entry.claimed ~= true and number(entry.progress) >= quest.goal then
							count += 1
						end
					end
				end
			end
		end
		claimable = count
		badge.Visible = count > 0
		badgeText:set(tostring(count))
	end)
	local punchAt = -math.huge
	ProgressLink.on("coins", function(amount: any, source: any)
		if type(amount) == "number" and amount > 0 then
			toast(`+{ProgressRules.commas(amount)}  {if type(source) == "string" then source else ""}`)
			punchAt = os.clock()
		end
	end)
	ProgressLink.on("level", function(level: any, levelTitle: any, levelCoins: any)
		local inMatch = player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
			and Workspace:GetAttribute(RoundRules.ATTR_STATE) == "Match"
		local sub = `{tostring(levelTitle)}   +{number(levelCoins)} coins`
		-- mid-chase it's the small call-out, so it never hides the game
		RoundHud.say(`LEVEL {number(level)}!`, if inMatch then nil else sub, PlasticUi.GOLD, 2.2, inMatch)
		punchAt = os.clock()
	end)
	ProgressLink.on("streak", function(days: any, bonus: any)
		RoundHud.say("DAILY BONUS!", `Day {number(days)} in a row   +{number(bonus)} coins`, PlasticUi.GOLD, 2.8)
		punchAt = os.clock()
	end)
	ProgressLink.on("questDone", function(questTitle: any)
		RoundHud.say(`QUEST DONE: {string.upper(tostring(questTitle))}`, nil, PlasticUi.DONE, 1.8, true)
	end)

	---------------------------------------------------------------- every frame
	local shownCoins = -1
	local shownLevel = -1
	local shownTitle = ""
	local shownXp = ""
	local fillShare = 0
	local slide = 1 -- 0: in its place, 1: away to the left
	RunService.PreRender:Connect(function(dt: number)
		local now = os.clock()
		local size = PlasticUi.screenScale()
		local loaded = player:GetAttribute(ProgressRules.ATTR_LOADED) == true
		local away = player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true or not loaded
		slide = math.clamp(slide + (if away then dt else -dt) / SLIDE_TIME, 0, 1)

		-- the "+5 TAG" pop-ups: beside the wallet, or beside the coin counter in a round
		local coinRest = HudLayout.get("Coin")
		local walletRest = HudLayout.get("Wallet")
		for _, each in toasts do
			if each.live then
				local age = now - each.at
				if age >= TOAST_TIME then
					each.live = false
					each.text.root.Visible = false
				else
					local root = each.text.root
					local rise = TOAST_RISE * size * (1 - (1 - age / TOAST_TIME) ^ 2) + each.slot * 26 * size
					if coinRest then
						root.AnchorPoint = Vector2.new(1, 1)
						root.Position = UDim2.fromOffset(coinRest.right, coinRest.top - 4 - rise)
						each.text.label.TextXAlignment = Enum.TextXAlignment.Right
						each.text.drop.TextXAlignment = Enum.TextXAlignment.Right
					else
						local x = if walletRest then walletRest.right + 10 else HudLayout.EDGE
						local y = if walletRest then walletRest.top + 60 * size else HudLayout.screen().Y * 0.4
						root.AnchorPoint = Vector2.new(0, 1)
						root.Position = UDim2.fromOffset(x, y - rise)
						each.text.label.TextXAlignment = Enum.TextXAlignment.Left
						each.text.drop.TextXAlignment = Enum.TextXAlignment.Left
					end
					local scale = root:FindFirstChildOfClass("UIScale")
					if scale then
						-- pops in bigger, settles
						scale.Scale = size * (1 + 0.35 * math.max(1 - age / 0.18, 0))
					end
					each.text:setFade(math.clamp((age - (TOAST_TIME - 0.35)) / 0.35, 0, 1))
				end
			end
		end

		if slide >= 1 then
			group.Visible = false
			HudLayout.report("Wallet", nil)
			return
		end
		group.Visible = true

		-- the numbers
		local level = number(player:GetAttribute(ProgressRules.ATTR_LEVEL))
		if level ~= shownLevel then
			shownLevel = level
			tileNumber:set(tostring(math.max(level, 1)))
		end
		local titleNow = player:GetAttribute(ProgressRules.ATTR_TITLE)
		local titleText = if type(titleNow) == "string" then titleNow else ""
		if titleText ~= shownTitle then
			shownTitle = titleText
			title:set(titleText)
		end
		local into = number(player:GetAttribute(ProgressRules.ATTR_XP))
		local need = number(player:GetAttribute(ProgressRules.ATTR_XP_NEED))
		local xpText = if need > 0 then `{into} / {need} XP` else "MAX LEVEL"
		if xpText ~= shownXp then
			shownXp = xpText
			barText:set(xpText)
		end
		local share = if need > 0 then math.clamp(into / need, 0, 1) else 1
		fillShare += (share - fillShare) * (1 - math.exp(-8 * dt))
		fill.Size = UDim2.fromScale(fillShare, 1)
		-- the coins count up to what you have
		local real = number(player:GetAttribute(ProgressRules.ATTR_COINS))
		if shownCoins < 0 or math.abs(real - shownCoins) < 1 then
			if shownCoins ~= real then
				shownCoins = real
				coins:set(ProgressRules.commas(real))
			end
		else
			shownCoins += (real - shownCoins) * (1 - math.exp(-9 * dt))
			coins:set(ProgressRules.commas(math.floor(shownCoins + 0.5)))
		end

		-- where it sits: the left edge, under Roblox's buttons and the runner counter
		local top = HudLayout.robloxButtonsBottom() + HudLayout.GAP
		local runners = HudLayout.get("Runners")
		if runners and runners.left < HudLayout.EDGE + CARD_W * size then
			top = math.max(top, runners.bottom + HudLayout.GAP)
		end
		local bob, tilt = PlasticUi.motion(0.8)
		local eased = slide * slide
		local x = HudLayout.EDGE - eased * (CARD_W * size + HudLayout.EDGE + 10)
		groupScale.Scale = size
		group.Position = UDim2.fromOffset(x + tilt * 1.5, top + bob)
		group.Rotation = tilt * 0.3
		local punchAge = now - punchAt
		cardScale.Scale = if punchAge >= 0 and punchAge < PUNCH_TIME
			then 1 + 0.1 * math.sin(math.pi * punchAge / PUNCH_TIME)
			else 1
		coin.Rotation = 8 * math.sin(now * 2.4)
		if claimable > 0 then
			badgeScale.Scale = 1 + 0.12 * math.sin(now * math.pi * 3)
		end
		HudLayout.report(
			"Wallet",
			if slide <= 0.01
				then HudLayout.rect(
					HudLayout.EDGE,
					top,
					HudLayout.EDGE + CARD_W * size,
					top + (GROUP_H + Config.Ui.DEPTH) * size + Config.Ui.BOB_PIXELS
				)
				else nil
		)
	end)
end

return Wallet
