--!strict
-- Neon afterimages behind every dash (design notes, Movement): copies of the body dropped along the dash, glowing in
-- the dasher's colour (their equipped trail's colour, or cyan for runners and red for chasers), each fading away.
-- Your own dash draws the moment you press (MoveController.onDash); other players' draw when their DashCount ticks up
-- (the server sets it once it has checked the dash), and so do the Studio test bots' (on their bodies). Drawn on this
-- screen only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local MoveController = require(script.Parent.MoveController)

local D = Config.Dash

local Afterimages = {}

local player = Players.LocalPlayer
local folder: Folder? = nil
local fadeInfo = TweenInfo.new(D.GHOST_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- One glowing copy of `character` where it stands now.
local function dropGhost(character: Model, color: Color3)
	local holder = folder
	if not holder or not character.Parent then
		return
	end
	local ghost = Instance.new("Model")
	ghost.Name = "Afterimage"
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			local copy = Instance.new("Part")
			copy.Name = part.Name
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = false
			copy.Material = Enum.Material.Neon
			copy.Color = color
			copy.Transparency = D.GHOST_START
			copy.Size = part.Size
			copy.CFrame = part.CFrame
			-- R6 heads are blocks with a head-shaped mesh
			local mesh = part:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				local shape = Instance.new("SpecialMesh")
				shape.MeshType = mesh.MeshType
				shape.MeshId = mesh.MeshId
				shape.Scale = mesh.Scale
				shape.Parent = copy
			end
			copy.Parent = ghost
			TweenService:Create(copy, fadeInfo, { Transparency = 1 }):Play()
		end
	end
	ghost.Parent = holder
	task.delay(D.GHOST_FADE + 0.05, function()
		ghost:Destroy()
	end)
end

-- A trail of copies over the dash's burst, starting now. `dasher` is a player, or a bot's body.
local function drawDash(dasher: Instance)
	local character = if dasher:IsA("Player") then dasher.Character elseif dasher:IsA("Model") then dasher else nil
	if not character then
		return
	end
	local color = MoveRules.dashColor(
		dasher:GetAttribute(MoveRules.ATTR_ROLE),
		dasher:GetAttribute(MoveRules.ATTR_DASH_COLOR)
	)
	local count = math.max(D.GHOSTS, 1)
	for i = 0, count - 1 do
		local delay = if count > 1 then D.TIME * i / (count - 1) else 0
		task.delay(delay, dropGhost, character, color)
	end
end

local function watch(other: Instance)
	if other == player then
		return
	end
	other:GetAttributeChangedSignal(MoveRules.ATTR_DASH_COUNT):Connect(function()
		drawDash(other)
	end)
end

function Afterimages.start()
	local holder = Instance.new("Folder")
	holder.Name = "Afterimages"
	holder.Parent = Workspace
	folder = holder

	MoveController.onDash(function()
		drawDash(player)
	end)
	Players.PlayerAdded:Connect(watch)
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	-- the Studio test bots
	task.spawn(function()
		local bots = Workspace:WaitForChild("TagBots", 30)
		if not bots then
			return
		end
		bots.ChildAdded:Connect(watch)
		for _, bot in bots:GetChildren() do
			watch(bot)
		end
	end)
end

return Afterimages
