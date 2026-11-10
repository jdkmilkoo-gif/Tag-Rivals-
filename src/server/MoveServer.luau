--!strict
-- The server side of movement (design notes, Movement):
--   * every new body is set up for Tag Rivals before anyone sees it: no jumping, and Roblox's own Animate script goes
--     (CharacterAnim plays ours);
--   * every player has a role (Runner to start), and the tag speed-up lives on Workspace (MoveServer.addTag);
--   * a dash a player's game reports is checked against their 2 charges, then put on their Player so every screen
--     draws its afterimages (and the tag check can see the dash's bigger reach later);
--   * anyone who gets out of the circle anyway is put back, and anyone who falls gets a fresh body;
--   * in Studio, the test keys (DevKeys) can change your role, fake tags and add stars.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)

local A = Config.Arena

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DashRemote = Remotes:WaitForChild("Dash") :: RemoteEvent
local DevRemote = Remotes:WaitForChild("Dev") :: RemoteEvent

local MoveServer = {}

local charges: { [Player]: number } = {}
local lastDash: { [Player]: number } = {}
local respawn: (player: Player) -> () = function() end

-- Sets a new body up before it goes into the world (Spawner calls this).
function MoveServer.prepareCharacter(player: Player, character: Model)
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		-- Made here on the server, so animations played on the player's own screen show for everyone.
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end
	-- A new body starts with full dash charges, the same as on the player's screen.
	charges[player] = nil
	lastDash[player] = nil
end

-- The round's starting speed (owner: it depends on how many players are in the round), under the tag speed-ups.
local startBonus = 0

-- One more tag this round: everyone gets a little faster (owner). The round system calls this.
function MoveServer.addTag()
	local tags = Workspace:GetAttribute(MoveRules.ATTR_TAGS)
	local count = (if type(tags) == "number" then tags else 0) + 1
	Workspace:SetAttribute(MoveRules.ATTR_TAGS, count)
	local M = Config.Move
	Workspace:SetAttribute(MoveRules.ATTR_TAG_BONUS, startBonus + count * M.TAG_SPEED_BONUS)
	-- chasers: each tag gives less than the last (a geometric series)
	local chaser = M.TAG_SPEED_BONUS * (1 - M.CHASER_TAG_DECAY ^ count) / (1 - M.CHASER_TAG_DECAY)
	Workspace:SetAttribute(MoveRules.ATTR_CHASER_TAG_BONUS, startBonus + chaser)
end

-- Back to the start of a round: no tag speed-ups, and everyone's speed starts `start` studs/s up (default 0).
function MoveServer.resetTags(start: number?)
	startBonus = math.max(start or 0, 0)
	Workspace:SetAttribute(MoveRules.ATTR_TAGS, 0)
	Workspace:SetAttribute(MoveRules.ATTR_TAG_BONUS, startBonus)
	Workspace:SetAttribute(MoveRules.ATTR_CHASER_TAG_BONUS, startBonus)
end

function MoveServer.setRole(player: Player, role: string)
	player:SetAttribute(MoveRules.ATTR_ROLE, MoveRules.role(role))
end

local function finiteVector(value: Vector3): boolean
	return value.X == value.X and value.Z == value.Z and math.abs(value.X) < 1e6 and math.abs(value.Z) < 1e6
end

local function onDash(player: Player, direction: unknown)
	if typeof(direction) ~= "Vector3" or not finiteVector(direction) then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.5 or flat.Magnitude > 1.5 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local ok, after = MoveRules.serverSpend(charges[player], lastDash[player], now)
	if not ok then
		return
	end
	charges[player] = after
	lastDash[player] = now
	local count = player:GetAttribute(MoveRules.ATTR_DASH_COUNT)
	player:SetAttribute(MoveRules.ATTR_DASH_DIR, flat.Unit)
	player:SetAttribute(MoveRules.ATTR_DASH_AT, now)
	player:SetAttribute(MoveRules.ATTR_DASH_COUNT, (if type(count) == "number" then count else 0) + 1)
end

-- Studio-only test keys (DevKeys on the player's screen). Ignored in a live game.
local function onDev(player: Player, action: unknown, value: unknown)
	if not RunService:IsStudio() then
		return
	end
	if action == "role" and type(value) == "string" then
		MoveServer.setRole(player, value)
	elseif action == "tag" then
		MoveServer.addTag()
	elseif action == "stars" then
		local stars = player:GetAttribute(MoveRules.ATTR_STARS)
		player:SetAttribute(MoveRules.ATTR_STARS, (if type(stars) == "number" then stars else 0) + 5)
	elseif action == "reset" then
		MoveServer.setRole(player, "Runner")
		player:SetAttribute(MoveRules.ATTR_STARS, 0)
		MoveServer.resetTags()
	end
end

-- Anyone outside the square (a lag spike, a cheat) is put back on the edge; anyone below the floor gets a fresh body.
-- Not someone who fell off a cut strip (the round puts them back), and nobody just after a cut (whoever was on the
-- strip is on their way down, and the server sees them a moment late).
local function watchBodies()
	local radius = Workspace:GetAttribute(MoveRules.ATTR_ARENA_RADIUS)
	if type(radius) ~= "number" then
		return
	end
	local lastCut = Workspace:GetAttribute(MoveRules.ATTR_LAST_CUT_AT)
	local justCut = type(lastCut) == "number"
		and Workspace:GetServerTimeNow() - lastCut < Config.Shrink.AFTER_CUT_GRACE
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and rootPart and player:GetAttribute(MoveRules.ATTR_FALLING) == nil then
			local position = rootPart.Position
			if position.Y < A.CENTER.Y - A.FALL_LIMIT then
				respawn(player)
			elseif not justCut and position.Y > A.CENTER.Y - 2 and position.Y < A.CENTER.Y + A.WALL_HEIGHT then
				-- SERVER_GRACE studs past the client's own wall, so normal movement never gets yanked: the server sees
				-- bodies a moment late, and in a shrink the circle has already moved on (this used to add 6 to both the
				-- radius and the margin, which left no grace at all)
				local fixed, outward = MoveRules.clampToArena(position, A.CENTER, radius + A.SERVER_GRACE, A.EDGE_MARGIN)
				if outward then
					character:PivotTo(character:GetPivot() + (fixed - position))
				end
			end
		end
	end
end

-- Studio only: copies of the animations in use (the KeyframeSequences in ServerStorage.Animations) go where players'
-- games can see them, so a play-test can run them before they're uploaded (CharacterAnim registers them; a live game
-- needs the uploaded ids).
local function shareStudioAnimations()
	if not RunService:IsStudio() then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "StudioAnimations"
	local A = Config.Anim
	local source = game:GetService("ServerStorage"):FindFirstChild(A.STUDIO_FOLDER)
	local names = {
		A.STUDIO_RUN,
		A.STUDIO_WALK,
		A.STUDIO_IDLE,
		A.STUDIO_DASH_LEFT,
		A.STUDIO_DASH_RIGHT,
		A.STUDIO_KNIFE_EQUIP,
		A.STUDIO_KNIFE_HOLD,
		A.STUDIO_KNIFE_STAB,
	}
	for _, list in { A.STUDIO_DASHES, A.STUDIO_KNIFE_SLASHES } do
		for _, name in list do
			table.insert(names, name)
		end
	end
	for _, name in names do
		local sequence = source and source:FindFirstChild(name)
		if sequence and sequence:IsA("KeyframeSequence") then
			sequence:Clone().Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

function MoveServer.start(respawnPlayer: (player: Player) -> ())
	respawn = respawnPlayer
	MoveServer.resetTags()
	shareStudioAnimations()

	local function onPlayer(player: Player)
		MoveServer.setRole(player, "Runner")
		player:SetAttribute(MoveRules.ATTR_STARS, 0)
		player:SetAttribute(MoveRules.ATTR_DASH_COUNT, 0)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		charges[player] = nil
		lastDash[player] = nil
	end)

	DashRemote.OnServerEvent:Connect(onDash)
	DevRemote.OnServerEvent:Connect(onDev)

	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= 0.25 then
			since = 0
			watchBodies()
		end
	end)
end

return MoveServer
