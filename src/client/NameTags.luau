--!strict
-- Name tags (design notes, Levels and titles), drawn by each screen itself in the game's style instead of Roblox's:
--   * the name in bold italic with a black outline: white, or red for a chaser in the round;
--   * under it, small and gold, the level and title ("LV 12  HUNTER"; whoever tops a leaderboard wears "#1 TAGGER");
--   * a bot's line starts with a small blue BOT (Config.LiveBots.SHOW_TAG);
--   * the bounty (owner 2026-11-13: "Add a Bounty system"): a gold WANTED plate with the coins on their head over the
--     wanted runner, pulsing, drawn over everything and from any distance so the whole round can hunt them;
--   * the statues on the lobby's pedestals wear their player's name and level.
-- Your own name isn't drawn (only your own WANTED plate). One tag is built per body; its words only change when what
-- they say changes, checked a few times a second; far tags aren't drawn at all.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local PlasticUi = require(script.Parent.PlasticUi)

local NameTags = {}

type Tag = {
	who: Instance, -- the Player, the bot or the statue: whose attributes it shows
	gui: BillboardGui,
	name: TextLabel,
	sub: TextLabel,
	wanted: Frame,
	wantedText: TextLabel,
	wantedScale: UIScale,
	mine: boolean,
	statue: boolean,
	shownName: string,
	shownSub: string,
	shownRed: boolean,
	shownBounty: number,
}

local SEEN_FROM = 120 -- studs: further tags aren't drawn
local WIDE, TALL = 9, 3.2 -- studs
local LIFT = 2.6 -- studs from the head's middle to the tag's
local EVERY = 0.2 -- s between checks of what the tags say
local RED = Color3.fromHex("FF2B4A")
local WHITE = Color3.new(1, 1, 1)
local BOT_BLUE = "#2EE6FF"

local player = Players.LocalPlayer
local tags: { [Model]: Tag } = {}
local holder: Folder = nil :: any

local function words(name: string, parent: Instance, top: number, tall: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, top)
	label.Size = UDim2.fromScale(1, tall)
	label.FontFace = PlasticUi.FONT
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = ""
	local stroke = PlasticUi.outline(label, 1.5, Enum.ApplyStrokeMode.Contextual)
	stroke.Name = "Outline"
	label.Parent = parent
	return label
end

local function build(who: Instance, body: Model, adornee: BasePart): Tag
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(WIDE, TALL)
	gui.StudsOffsetWorldSpace = Vector3.new(0, LIFT, 0)
	gui.MaxDistance = SEEN_FROM
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false

	-- the WANTED plate: gold, a black outline, dark words
	local wanted = Instance.new("Frame")
	wanted.Name = "Wanted"
	wanted.AnchorPoint = Vector2.new(0.5, 0.5)
	wanted.Position = UDim2.fromScale(0.5, 0.2)
	wanted.Size = UDim2.fromScale(0.62, 0.34)
	wanted.BackgroundColor3 = Color3.fromHex(Config.Bounty.COLOR)
	wanted.BorderSizePixel = 0
	wanted.Visible = false
	PlasticUi.outline(wanted, 2)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHex("D9A21C"))
	shade.Parent = wanted
	local wantedScale = Instance.new("UIScale")
	wantedScale.Parent = wanted
	local wantedText = Instance.new("TextLabel")
	wantedText.Name = "Words"
	wantedText.BackgroundTransparency = 1
	wantedText.AnchorPoint = Vector2.new(0.5, 0.5)
	wantedText.Position = UDim2.fromScale(0.5, 0.5)
	wantedText.Size = UDim2.fromScale(0.92, 0.8)
	wantedText.FontFace = PlasticUi.FONT
	wantedText.TextScaled = true
	wantedText.TextColor3 = Color3.fromHex("2A1B00")
	wantedText.Text = ""
	wantedText.Parent = wanted
	wanted.Parent = gui

	local name = words("Name", gui, 0.4, 0.34, WHITE)
	local sub = words("Sub", gui, 0.74, 0.24, PlasticUi.GOLD)
	sub.RichText = true

	gui.Parent = holder
	return {
		who = who,
		gui = gui,
		name = name,
		sub = sub,
		wanted = wanted,
		wantedText = wantedText,
		wantedScale = wantedScale,
		mine = who == player,
		statue = who:GetAttribute(ProgressRules.ATTR_PLACE) ~= nil,
		shownName = "",
		shownSub = "",
		shownRed = false,
		shownBounty = -1,
	}
end

local function number(value: unknown): number
	return if type(value) == "number" then value else 0
end

-- Puts what the tag should say on it, where that's changed.
local function refresh(tag: Tag)
	local who = tag.who
	local shown = who:GetAttribute(RoundRules.ATTR_NAME)
	local name = if who:IsA("Player") then who.DisplayName elseif type(shown) == "string" then shown else who.Name
	if name ~= tag.shownName then
		tag.shownName = name
		tag.name.Text = name
	end

	local level = number(who:GetAttribute(ProgressRules.ATTR_LEVEL))
	local title = who:GetAttribute(ProgressRules.ATTR_TITLE)
	local sub = ""
	if level > 0 then
		sub = `LV {level}`
		if type(title) == "string" and title ~= "" then
			sub ..= `  {title}`
		end
	end
	if who:GetAttribute(RoundRules.ATTR_BOT) == true and Config.LiveBots.SHOW_TAG then
		sub = `<font color="{BOT_BLUE}">BOT</font>  {sub}`
	end
	if sub ~= tag.shownSub then
		tag.shownSub = sub
		tag.sub.Text = sub
	end

	local red = not tag.statue
		and who:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
		and MoveRules.role(who:GetAttribute(MoveRules.ATTR_ROLE)) == "Chaser"
	if red ~= tag.shownRed then
		tag.shownRed = red
		tag.name.TextColor3 = if red then RED else WHITE
	end

	local bounty = if tag.statue then 0 else number(who:GetAttribute(ProgressRules.ATTR_BOUNTY))
	if bounty ~= tag.shownBounty then
		tag.shownBounty = bounty
		local on = bounty > 0
		tag.wanted.Visible = on
		tag.wantedText.Text = `WANTED  {bounty}`
		-- the wanted runner is seen through everything and from anywhere
		tag.gui.AlwaysOnTop = on
		tag.gui.MaxDistance = if on then 100000 else SEEN_FROM
	end
	-- your own tag is only ever your WANTED plate
	if tag.mine then
		tag.name.Visible = false
		tag.sub.Visible = false
		tag.gui.Enabled = bounty > 0
	end
end

local function drop(body: Model)
	local tag = tags[body]
	if tag then
		tags[body] = nil
		tag.gui:Destroy()
	end
end

-- Gives `body` its tag (`who`: the Player, or the bot or statue itself).
local function attach(who: Instance, body: Model)
	task.spawn(function()
		local head = body:WaitForChild("Head", 10)
		if not head or not head:IsA("BasePart") or not body:IsDescendantOf(Workspace) or tags[body] then
			return
		end
		local tag = build(who, body, head)
		tags[body] = tag
		refresh(tag)
		body.AncestryChanged:Connect(function()
			if not body:IsDescendantOf(Workspace) then
				drop(body)
			end
		end)
	end)
end

-- Every body in a folder gets a tag as it comes (the bots; the pedestals' statues).
local function watchFolder(name: string, wants: (child: Instance) -> boolean)
	task.spawn(function()
		local folder = Workspace:WaitForChild(name, 60)
		if not folder then
			return
		end
		local function consider(child: Instance)
			if child:IsA("Model") and wants(child) then
				attach(child, child)
			end
		end
		folder.ChildAdded:Connect(function(child)
			task.defer(consider, child) -- its attributes are set by now
		end)
		for _, child in folder:GetChildren() do
			consider(child)
		end
	end)
end

function NameTags.start()
	local made = Instance.new("Folder")
	made.Name = "TagRivalsNameTags"
	made.Parent = player:WaitForChild("PlayerGui")
	holder = made

	local function onPlayer(other: Player)
		other.CharacterAdded:Connect(function(character)
			attach(other, character)
		end)
		if other.Character then
			attach(other, other.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, other in Players:GetPlayers() do
		onPlayer(other)
	end
	watchFolder("TagBots", function()
		return true
	end)
	watchFolder(ProgressRules.EXTRAS, function(child)
		return child:GetAttribute(ProgressRules.ATTR_PLACE) ~= nil and child:FindFirstChildOfClass("Humanoid") ~= nil
	end)

	local since = 0
	RunService.PreRender:Connect(function(dt: number)
		since += dt
		local check = since >= EVERY
		if check then
			since = 0
		end
		local beat = 1 + 0.07 * math.sin(os.clock() * math.pi * 3)
		for _, tag in tags do
			if check then
				refresh(tag)
			end
			if tag.shownBounty > 0 then
				tag.wantedScale.Scale = beat
			end
		end
	end)
end

return NameTags
