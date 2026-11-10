--!strict
-- The lobby (design notes, Lobby): a big glass ring floating right above the arena. Its floor is see-through, so
-- everyone waiting (between rounds, or who joined mid-round) watches the round live below. A glowing rim marks its
-- edge and an invisible wall keeps people on it. Shop booths, flex pedestals and the holographic leaderboards come in
-- later steps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local L = Config.Lobby
local A = Config.Arena

local Lobby = {}

-- Roblox's cylinder part is round across its Y and Z sizes: turned onto its side, the round face points up.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local function floorTop(): Vector3
	return A.CENTER + Vector3.new(0, L.HEIGHT, 0)
end

local function part(name: string, size: Vector3, cframe: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function Lobby.build()
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	local top = floorTop()

	local glass = part(
		"Glass",
		Vector3.new(L.THICKNESS, L.RADIUS * 2, L.RADIUS * 2),
		CFrame.new(top - Vector3.new(0, L.THICKNESS / 2, 0)) * UPRIGHT
	)
	glass.Shape = Enum.PartType.Cylinder
	glass.Material = Enum.Material.Glass
	glass.Color = Color3.fromHex(L.GLASS_COLOR)
	glass.Transparency = L.GLASS_SEE
	glass.CastShadow = false
	glass.Parent = folder

	local rim = part(
		"Rim",
		Vector3.new(0.4, L.RADIUS * 2 + L.RIM * 2, L.RADIUS * 2 + L.RIM * 2),
		CFrame.new(top - Vector3.new(0, L.THICKNESS + 0.2, 0)) * UPRIGHT
	)
	rim.Shape = Enum.PartType.Cylinder
	rim.Material = Enum.Material.Neon
	rim.Color = Color3.fromHex(L.RIM_COLOR)
	rim.CanCollide = false
	rim.CanQuery = false
	rim.CanTouch = false
	rim.CastShadow = false
	rim.Transparency = 0.2
	rim.Parent = folder

	-- the invisible wall: short straight pieces round the edge, overlapping a little so there's no gap
	local count = L.WALL_SEGMENTS
	local width = 2 * L.RADIUS * math.sin(math.pi / count) + 1
	for i = 1, count do
		local angle = (i - 0.5) / count * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = top + out * (L.RADIUS + 0.5) + Vector3.new(0, L.WALL_HEIGHT / 2, 0)
		local wall = part("Wall", Vector3.new(width, L.WALL_HEIGHT, 1), CFrame.lookAt(position, position + out))
		wall.Transparency = 1
		wall.CanQuery = false
		wall.CastShadow = false
		wall.Parent = folder
	end

	folder.Parent = Workspace
end

-- A random standing spot on the glass, facing its middle.
function Lobby.randomSpawn(): CFrame
	local distance = L.RADIUS * L.SPAWN_SHARE * math.sqrt(math.random())
	local angle = math.random() * math.pi * 2
	local position = floorTop() + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)
	local middle = Vector3.new(A.CENTER.X, position.Y, A.CENTER.Z)
	if (middle - position).Magnitude < 0.5 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, middle)
end

-- Is this spot up on the lobby (not down in the arena)?
function Lobby.isUp(position: Vector3): boolean
	return position.Y > A.CENTER.Y + L.HEIGHT * 0.5
end

return Lobby
