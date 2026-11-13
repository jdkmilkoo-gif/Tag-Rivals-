--!strict
-- Spawns every player as an R6 version of their own avatar (the run animations are R6), on a random spot on the
-- circle, and gives a fresh body after a death or a fall. Players.CharacterAutoLoads is off (default.project.json), so
-- this is the only thing that makes bodies. Adapted from Huss Zero's R6Spawner.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Spawner = {}

-- Where a new body stands, and what to do to it before anyone sees it (both set by init).
local spotFor: (player: Player) -> CFrame = function()
	return CFrame.new(0, 5, 0)
end
local prepare: (player: Player, character: Model) -> () = function() end

local generations: { [Player]: number } = {}
local descriptions: { [Player]: HumanoidDescription } = {}

local function inGame(player: Player): boolean
	return player.Parent == Players
end

local function getDescription(userId: number): HumanoidDescription
	if userId > 0 then
		local ok, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if ok and description then
			return description
		end
	end
	-- Studio test players have negative ids, and the web call can fail: a plain blocky avatar.
	return Instance.new("HumanoidDescription")
end

-- Building loads assets from the web and can throw (an outage, a moderated item): fall back to a plain body.
local function build(description: HumanoidDescription): Model?
	for _, attempt in { description, Instance.new("HumanoidDescription") } do
		local ok, character = pcall(function()
			return Players:CreateHumanoidModelFromDescription(attempt, Enum.HumanoidRigType.R6)
		end)
		if ok and character then
			return character
		end
		warn("Could not build an R6 avatar: " .. tostring(character))
	end
	return nil
end

local spawnPlayer: (player: Player) -> ()

local function respawnLater(player: Player, generation: number, delay: number)
	task.delay(delay, function()
		-- Only the newest body may ask for a new one, and only once.
		if inGame(player) and generations[player] == generation then
			spawnPlayer(player)
		end
	end)
end

spawnPlayer = function(player: Player)
	local generation = (generations[player] or 0) + 1
	generations[player] = generation

	local description = descriptions[player]
	if not description then
		description = getDescription(player.UserId)
		descriptions[player] = description
	end
	local character = build(description)

	-- Building waits on the web; the player may have left or respawned meanwhile.
	if not inGame(player) or generations[player] ~= generation then
		if character then
			character:Destroy()
		end
		return
	end
	if not character then
		respawnLater(player, generation, Config.Respawn.TIME)
		return
	end

	character.Name = player.Name
	-- every screen draws the name tags itself (NameTags): name, level and title, in the game's own style
	local shown = character:FindFirstChildOfClass("Humanoid")
	if shown then
		shown.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		shown.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	for _, child in StarterPlayer.StarterCharacterScripts:GetChildren() do
		child:Clone().Parent = character
	end
	character:PivotTo(spotFor(player))
	prepare(player, character)

	local oldCharacter = player.Character
	-- Character first, then parent: the order Roblox's own spawning uses.
	player.Character = character
	character.Parent = Workspace
	if oldCharacter and oldCharacter ~= character then
		oldCharacter:Destroy()
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		rootPart:SetNetworkOwner(player)
	end

	local gone = false
	local function onGone()
		if not gone then
			gone = true
			respawnLater(player, generation, Config.Respawn.TIME)
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(onGone)
	end
	-- Falling below FallenPartsDestroyHeight can delete the whole body without a death.
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(Workspace) then
			onGone()
		end
	end)
end

-- A player's avatar, once it's been fetched (the lobby's pedestals make statues from it).
function Spawner.descriptionOf(player: Player): HumanoidDescription?
	return descriptions[player]
end

-- A fresh body for one player now (a fall, a new round).
function Spawner.respawn(player: Player)
	if inGame(player) then
		task.spawn(spawnPlayer, player)
	end
end

function Spawner.start(where: (player: Player) -> CFrame, prepareCharacter: (player: Player, character: Model) -> ())
	spotFor = where
	prepare = prepareCharacter
	-- Also set in default.project.json; set here too in case the place still has Roblox's own spawning on.
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(spawnPlayer)
	Players.PlayerRemoving:Connect(function(player)
		generations[player] = nil
		descriptions[player] = nil
		local character = player.Character
		if character then
			character:Destroy()
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(spawnPlayer, player)
	end
end

return Spawner
