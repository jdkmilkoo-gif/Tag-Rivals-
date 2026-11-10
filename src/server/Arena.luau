--!strict
-- The arena (design notes, Map size): one flat square, a permanent 250 x 250 studs (owner 2026-11-09: "lets keep the
-- map at a permanent 250 x 250 square with shrinks"), with a glowing rim and no walls you can see. Its middle and half
-- its side go on Workspace attributes, and every player's game keeps their own body inside that square (the invisible
-- wall, MoveController) while the server catches anyone who gets out anyway (MoveServer).
-- Every round starts at the full size (Arena.setDiameter); each shrink cuts the strip round the edge off at once
-- (Arena.cutTo; owner 2026-11-09: "change the shrinking function as just like cutting off a that part of the map"), and
-- anyone still standing on it falls with it (owner 2026-11-10: "make the red let players fall and become tagger").
-- ("Diameter" here means the square's side; "radius" half of it, the distance from the middle to an edge.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)

local A = Config.Arena

local Arena = {}

local floor: Part? = nil -- the grey grid you see; it never collides
local ground: Part? = nil -- what you stand on: invisible, resized only at a round's start and at each cut (once, never
-- every frame: resizing a big solid part rebuilds its collision)
local rim: Part? = nil
local diameter = A.SIZE

local RIM_HEIGHT = 0.8
local RIM_BELOW = 0.15 -- studs the rim's top sits under the floor's top

local function slab(name: string, color: string, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Color = Color3.fromHex(color)
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

function Arena.diameter(): number
	return diameter
end

-- Half the square's side: the distance from the middle to an edge.
function Arena.radius(): number
	return diameter / 2
end

function Arena.center(): Vector3
	return A.CENTER
end

-- The floor and rim you see, `side` studs a side.
local function setLook(side: number)
	if floor then
		floor.Size = Vector3.new(side, A.THICKNESS, side)
	end
	if rim then
		rim.Size = Vector3.new(side + A.RIM * 2, RIM_HEIGHT, side + A.RIM * 2)
	end
end

-- The invisible wall (and where spawns go), `side` studs a side.
local function setWall(side: number)
	diameter = side
	Workspace:SetAttribute(MoveRules.ATTR_ARENA_RADIUS, side / 2)
end

local function resize(newDiameter: number)
	local side = math.max(newDiameter, 10)
	setLook(side)
	setWall(side)
	if ground then
		ground.Size = Vector3.new(side, A.THICKNESS, side)
	end
end

-- Resizes the square at once (studs a side). Bodies outside it are pulled in by the invisible wall.
function Arena.setDiameter(newDiameter: number)
	resize(newDiameter)
end

-- The square's side now (kept under this name for the round and the coins).
function Arena.targetDiameter(): number
	return diameter
end

-- Cuts the square down to `newDiameter` a side (every screen drops the cut-off strip into the clouds, ShrinkFx). The
-- floor you see, the ground you stand on and the invisible wall all change at once, so anyone still on the cut strip
-- has nothing under them and falls (their own game lets go of them, MoveController; the round makes a runner a chaser
-- and puts them back, Round).
function Arena.cutTo(newDiameter: number)
	resize(newDiameter)
end

-- Kept for the round system (the square no longer follows the players in the server, so there's nothing to stop).
function Arena.manage() end

-- A random standing spot on the square (away from the edges), facing the middle.
function Arena.randomSpawn(): CFrame
	local half = diameter / 2 * 0.75
	local position = A.CENTER + Vector3.new((math.random() * 2 - 1) * half, 3, (math.random() * 2 - 1) * half)
	local middle = Vector3.new(A.CENTER.X, position.Y, A.CENTER.Z)
	if (middle - position).Magnitude < 0.5 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, middle)
end

function Arena.build()
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	local slabCFrame = CFrame.new(A.CENTER - Vector3.new(0, A.THICKNESS / 2, 0))

	local newFloor = slab("Floor", A.FLOOR_COLOR, A.FLOOR_MATERIAL)
	newFloor.CFrame = slabCFrame
	-- the baseplate's grid on the top face
	local grid = Instance.new("Texture")
	grid.Name = "Grid"
	grid.Texture = A.FLOOR_TEXTURE
	grid.Face = Enum.NormalId.Top
	grid.StudsPerTileU = A.FLOOR_TILE
	grid.StudsPerTileV = A.FLOOR_TILE
	grid.Color3 = Color3.new(0, 0, 0)
	grid.Transparency = A.FLOOR_TEXTURE_TRANSPARENCY
	grid.Parent = newFloor
	newFloor.CanCollide = false
	newFloor.CanQuery = false
	newFloor.CanTouch = false
	newFloor.Parent = folder
	floor = newFloor

	local newGround = slab("Ground", A.FLOOR_COLOR, A.FLOOR_MATERIAL)
	newGround.CFrame = slabCFrame
	newGround.Transparency = 1
	newGround.CastShadow = false
	newGround.Parent = folder
	ground = newGround

	-- the square is the whole map: the template's baseplate and spawn pad go (only while the game runs)
	for _, name in A.REMOVE_AT_START do
		local leftover = Workspace:FindFirstChild(name)
		if leftover and leftover:IsA("BasePart") then
			leftover:Destroy()
		end
	end

	local newRim = slab("Rim", A.RIM_COLOR, Enum.Material.Neon)
	newRim.CanCollide = false
	newRim.CanQuery = false
	newRim.CanTouch = false
	newRim.CastShadow = false
	newRim.CFrame = CFrame.new(A.CENTER - Vector3.new(0, RIM_BELOW + RIM_HEIGHT / 2, 0))
	newRim.Parent = folder
	rim = newRim

	Workspace:SetAttribute(MoveRules.ATTR_ARENA_CENTER, A.CENTER)
	Arena.setDiameter(A.SIZE)
	folder.Parent = Workspace
end

return Arena
