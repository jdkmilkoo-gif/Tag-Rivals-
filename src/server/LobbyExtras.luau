--!strict
-- The lobby's extras (design notes, Lobby; Config.LobbyExtras), the server's side:
--   * the flex pedestals: gold, silver and bronze, with statues of the top 3 players in this server (by level, then
--     coins) standing on them. Checked every PEDESTAL_REFRESH s; a statue is only built again when its player changes.
--   * the practice dummy: just its body, standing at its post with a ring on the glass round it. Each player's own
--     game makes it lunge at them (PracticeDummy), so practising costs the server nothing, nothing can be won by it,
--     and nobody is bothered by someone else's dummy.
-- Every screen draws the name tags and the plates on these itself (NameTags, LobbyBoards).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local Knives = require(script.Parent.Knives)
local PlayerData = require(script.Parent.PlayerData)

local X = Config.LobbyExtras
local L = Config.Lobby
local A = Config.Arena

local LobbyExtras = {}

type Statue = { userId: number, model: Model }

local ROOT_HEIGHT = 3 -- studs from an R6 body's feet to its middle
local PEDESTAL_WIDTH = 6

local folder: Folder = nil :: any
local tops: { Vector3 } = {} -- the top of each pedestal, by place
local statues: { [number]: Statue } = {} -- by place
local describe: (player: Player) -> HumanoidDescription? = function()
	return nil
end
local building = false

local function middle(): Vector3
	return A.CENTER + Vector3.new(0, L.HEIGHT, 0)
end

-- A spot on the glass `ring` studs from the middle, `degrees` round it; and the way out from the middle there.
local function ringSpot(ring: number, degrees: number): (Vector3, Vector3)
	local angle = math.rad(degrees)
	local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
	return middle() + out * ring, out
end

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	return part
end

-- A body that only stands there: nothing can push it, touch it or be blocked by it, and Roblox draws no name on it.
-- Only its middle is pinned in place (the rest hangs off it by its joints), so its animations still show.
local function still(model: Model)
	for _, each in model:GetDescendants() do
		if each:IsA("BasePart") then
			each.Anchored = each.Name == "HumanoidRootPart"
			each.CanCollide = false
			each.CanQuery = false
			each.CanTouch = false
			each.Massless = true
		elseif each:IsA("Script") or each:IsA("LocalScript") then
			each:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		-- it never walks, falls or dies: Roblox needn't work any of that out for it
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end
end

local function idle(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = if humanoid then humanoid:FindFirstChildOfClass("Animator") else nil
	local id = Config.Anim.IdleAnimationId
	if not animator or type(id) ~= "number" or id <= 0 then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(id)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track:Play(0)
	end
end

---------------------------------------------------------------- the pedestals

local function buildPedestals()
	local spot, out = ringSpot(X.PEDESTAL_RING, X.PEDESTAL_ANGLE)
	local along = Vector3.new(-out.Z, 0, out.X)
	-- first in the middle, second on its left, third on its right (as on a podium)
	local offsets = { 0, -X.PEDESTAL_GAP, X.PEDESTAL_GAP }
	for place = 1, 3 do
		local height = X.PEDESTAL_HEIGHTS[place]
		local color = Color3.fromHex(X.PEDESTAL_COLORS[place])
		local foot = spot + along * offsets[place]
		local facing = CFrame.lookAt(foot + Vector3.new(0, height / 2, 0), middle() + Vector3.new(0, height / 2, 0))
		local base =
			block("Pedestal", Vector3.new(PEDESTAL_WIDTH, height, PEDESTAL_WIDTH), facing, color, Enum.Material.Metal)
		base:SetAttribute(ProgressRules.ATTR_PLACE, place)
		base.Parent = folder
		local trim = block(
			"Trim",
			Vector3.new(PEDESTAL_WIDTH + 0.5, 0.3, PEDESTAL_WIDTH + 0.5),
			facing * CFrame.new(0, height / 2 - 0.15, 0),
			color,
			Enum.Material.Neon
		)
		trim.CanCollide = false
		trim.CanQuery = false
		trim.CanTouch = false
		trim.Parent = folder
		tops[place] = foot + Vector3.new(0, height, 0)
	end
end

local function clearStatue(place: number)
	local statue = statues[place]
	if statue then
		statues[place] = nil
		statue.model:Destroy()
	end
end

local function buildStatue(place: number, player: Player)
	local description = describe(player)
	if not description then
		return -- their avatar isn't known yet: next time
	end
	local ok, body = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if not ok or not body then
		return
	end
	local model = body :: Model
	if player.Parent ~= Players then
		model:Destroy()
		return
	end
	clearStatue(place)
	model.Name = "Statue" .. place
	still(model)
	local top = tops[place]
	model:PivotTo(CFrame.lookAt(top + Vector3.new(0, ROOT_HEIGHT, 0), middle() + Vector3.new(0, top.Y - middle().Y + ROOT_HEIGHT, 0)))
	model:SetAttribute(ProgressRules.ATTR_PLACE, place)
	model:SetAttribute(RoundRules.ATTR_NAME, player.DisplayName)
	model.Parent = folder
	idle(model)
	statues[place] = { userId = player.UserId, model = model }
end

-- Who's on the pedestals: the three highest levels here (more coins wins a tie). Statues that are still right stay.
local function refreshPedestals()
	if building then
		return
	end
	building = true
	local ranked: { { player: Player, level: number, coins: number } } = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if profile then
			table.insert(ranked, { player = player, level = (ProgressRules.level(profile.xp)), coins = profile.coins })
		end
	end
	table.sort(ranked, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		if a.coins ~= b.coins then
			return a.coins > b.coins
		end
		return a.player.UserId < b.player.UserId
	end)
	for place = 1, 3 do
		local entry = ranked[place]
		local statue = statues[place]
		if not entry then
			clearStatue(place)
		else
			if not statue or statue.userId ~= entry.player.UserId then
				buildStatue(place, entry.player)
				statue = statues[place]
			end
			if statue and statue.userId == entry.player.UserId then
				-- what their name tag reads
				statue.model:SetAttribute(ProgressRules.ATTR_LEVEL, entry.level)
				statue.model:SetAttribute(ProgressRules.ATTR_TITLE, entry.player:GetAttribute(ProgressRules.ATTR_TITLE))
			end
		end
	end
	building = false
end

---------------------------------------------------------------- the practice dummy

local function buildDummy()
	local spot, _ = ringSpot(X.DUMMY_RING, X.DUMMY_ANGLE)
	local ring = block(
		ProgressRules.DUMMY_RING,
		Vector3.new(0.1, X.DUMMY_ZONE * 2, X.DUMMY_ZONE * 2),
		CFrame.new(spot + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromHex("FF2B4A"),
		Enum.Material.Neon
	)
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.88
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = folder

	local description = Instance.new("HumanoidDescription")
	local grey = Color3.fromHex("C9CED9")
	local red = Color3.fromHex("FF2B4A")
	description.HeadColor = grey
	description.LeftArmColor = grey
	description.RightArmColor = grey
	description.TorsoColor = red
	description.LeftLegColor = red:Lerp(Color3.new(0, 0, 0), 0.5)
	description.RightLegColor = red:Lerp(Color3.new(0, 0, 0), 0.5)
	local ok, body = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if not ok or not body then
		warn(`[{Config.GameName}] the practice dummy couldn't be made: {body}`)
		return
	end
	local model = body :: Model
	model.Name = ProgressRules.DUMMY
	Knives.wear(model, true)
	still(model)
	model:PivotTo(CFrame.lookAt(spot + Vector3.new(0, ROOT_HEIGHT, 0), middle() + Vector3.new(0, ROOT_HEIGHT, 0)))
	model.Parent = folder
end

-- `descriptionOf` gives a player's avatar once it's known (Spawner keeps it).
function LobbyExtras.start(descriptionOf: (player: Player) -> HumanoidDescription?)
	describe = descriptionOf
	local made = Instance.new("Folder")
	made.Name = ProgressRules.EXTRAS
	folder = made
	buildPedestals()
	made.Parent = Workspace
	task.spawn(buildDummy)

	Players.PlayerRemoving:Connect(function(player)
		for place, statue in statues do
			if statue.userId == player.UserId then
				clearStatue(place)
			end
		end
	end)
	task.spawn(function()
		task.wait(4)
		while true do
			local ok, problem = pcall(refreshPedestals)
			if not ok then
				building = false
				warn(`[{Config.GameName}] the pedestals couldn't be refreshed: {problem}`)
			end
			task.wait(X.PEDESTAL_REFRESH)
		end
	end)
end

return LobbyExtras
