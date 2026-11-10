--!strict
-- The knife every player carries (owner 2026-11-09): worn diagonally across the back, runners included; a chaser
-- (picked in the fade or tagged) holds it in their hand from then on, and it slashes by itself when they get close
-- enough to a runner (the slash and its effects are drawn on every screen, TagController and TagFx).
-- Which knife: Config.Knife's dev-only switch. On, everyone wears the test knife, Bloomblade (a Model in
-- ServerStorage.Knives, the cosmetics thread's export); off, the default knife. A knife that isn't there yet is stood in
-- for by a plain placeholder built here, in Bloomblade's colours.
-- Every knife model is set up the same way: a PrimaryPart named KnifeRoot at the knife's own origin (blade along +X,
-- spine up), every other part welded to it; TrailStart and TrailEnd attachments and a SlashTrail (off) on KnifeRoot,
-- and a BladeLight. A knife's own effects (emitters marked KnifeFx = "Idle" or "Swing", on its FX_Blade part) come
-- with its model, all off; every screen's KnifeFx turns them on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local K = Config.Knife

local Knives = {}

Knives.MODEL_NAME = "Knife" -- the knife's name inside a body
local WELD_NAME = "KnifeWeld"

local template: Model? = nil

local function part(name: string, size: Vector3, cframe: CFrame, color: string, material: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = Color3.fromHex(color)
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- A plain knife in Bloomblade's colours, until the real one is in ServerStorage.Knives.
local function placeholder(): Model
	local model = Instance.new("Model")
	model.Name = "PlaceholderKnife"
	local glass, neon, smooth, metal =
		Enum.Material.Glass, Enum.Material.Neon, Enum.Material.SmoothPlastic, Enum.Material.Metal
	local handle = part("Handle", Vector3.new(1, 0.24, 0.24), CFrame.new(-0.85, 0, 0), "F4F0FF", smooth)
	handle.Shape = Enum.PartType.Cylinder
	handle.Parent = model
	local pommel = part("Pommel", Vector3.new(0.3, 0.3, 0.3), CFrame.new(-1.38, 0, 0), "E8B84A", metal)
	pommel.Shape = Enum.PartType.Ball
	pommel.Parent = model
	part("Guard", Vector3.new(0.16, 0.66, 0.32), CFrame.new(-0.3, -0.04, 0), "E8B84A", metal).Parent = model
	part("Blade", Vector3.new(1.95, 0.4, 0.07), CFrame.new(0.68, -0.04, 0), "9B4DFF", glass).Parent = model
	part("Edge", Vector3.new(1.95, 0.06, 0.08), CFrame.new(0.68, -0.25, 0), "FFD9F7", neon).Parent = model
	part("Band", Vector3.new(1.6, 0.05, 0.09), CFrame.new(0.6, 0.02, 0), "E45AD6", neon).Parent = model
	-- the point: a wedge whose long side lies against the blade and whose tip is at the edge (cutting side, down)
	local tip = Instance.new("WedgePart")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.07, 0.4, 0.5)
	tip.CFrame = CFrame.fromMatrix(Vector3.new(1.9, -0.04, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
	tip.Color = Color3.fromHex("9B4DFF")
	tip.Material = glass
	tip.Parent = model
	local charm = part("Charm", Vector3.new(0.18, 0.18, 0.18), CFrame.new(-1.45, -0.32, 0), "F6BCEE", smooth)
	charm.Shape = Enum.PartType.Ball
	charm.Parent = model
	return model
end

-- Gets a knife model ready to be worn: a KnifeRoot at its origin, every part welded to it and weightless, and the
-- slash trail.
local function prepared(source: Model): Model
	local model = source:Clone()
	model.Name = Knives.MODEL_NAME
	local root = model:FindFirstChild("KnifeRoot")
	if not root or not root:IsA("BasePart") then
		-- no KnifeRoot: the parts are laid out in the knife's own frame round the world's origin
		local newRoot = Instance.new("Part")
		newRoot.Name = "KnifeRoot"
		newRoot.Size = Vector3.new(0.2, 0.2, 0.2)
		newRoot.Transparency = 1
		newRoot.CFrame = CFrame.identity
		newRoot.Parent = model
		root = newRoot
	end
	local rootPart = root :: BasePart
	for _, each in model:GetDescendants() do
		if each:IsA("BasePart") then
			each.Anchored = false
			each.CanCollide = false
			each.CanTouch = false
			each.CanQuery = false
			each.Massless = true
			each.CastShadow = false
			if each ~= rootPart then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rootPart
				weld.Part1 = each
				weld.Parent = each
			end
		elseif each:IsA("ParticleEmitter") and each:GetAttribute("KnifeFx") ~= nil then
			each.Enabled = false -- off for everyone; each screen turns its own on (KnifeFx)
		end
	end
	model.PrimaryPart = rootPart

	-- the slash trail (Bloomblade's "Sakura Bloom" colours), off until a slash turns it on
	local function attachment(name: string, position: Vector3): Attachment
		local found = rootPart:FindFirstChild(name)
		if found and found:IsA("Attachment") then
			return found
		end
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = position
		a.Parent = rootPart
		return a
	end
	local a0 = attachment("TrailStart", K.TRAIL_START)
	local a1 = attachment("TrailEnd", K.TRAIL_END)
	if not rootPart:FindFirstChild("SlashTrail") then
		local trail = Instance.new("Trail")
		trail.Name = "SlashTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex(K.SLASH_COLOR_A)),
			ColorSequenceKeypoint.new(0.5, Color3.fromHex(K.SLASH_COLOR_B)),
			ColorSequenceKeypoint.new(1, Color3.fromHex(K.SLASH_COLOR_C)),
		})
		-- solid and saturated so it reads against the bright sky (owner 2026-11-10: "big and clearly visible"; it was
		-- see-through and washed out to white). Brighter than this burns it out to white again.
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new(1, 0.5)
		trail.Lifetime = 0.3
		trail.LightEmission = 0.3
		trail.Brightness = 1.5
		trail.FaceCamera = true
		trail.MinLength = 0.05
		trail.Enabled = false
		trail.Parent = rootPart
	end
	-- the blade's glow (pulsed on screens while held, KnifeFx)
	if not model:FindFirstChild("BladeLight", true) then
		local light = Instance.new("PointLight")
		light.Name = "BladeLight"
		light.Color = Color3.fromHex(K.LIGHT_COLOR)
		light.Range = K.LIGHT_RANGE
		light.Brightness = 0
		light.Shadows = false
		light.Parent = attachment("BladeMiddle", Vector3.new(1.12, -0.16, 0))
	end
	return model
end

-- The knife everyone wears now (made once).
local function getTemplate(): Model
	if template then
		return template
	end
	local name = if K.USE_TEST_KNIFE then K.TEST_KNIFE else K.DEFAULT_KNIFE
	local folder = ServerStorage:FindFirstChild("Knives")
	local source = folder and folder:FindFirstChild(name)
	local made = if source and source:IsA("Model") then prepared(source) else prepared(placeholder())
	made:SetAttribute("KnifeName", if source then name else "Placeholder")
	template = made
	return made
end

-- Where the knife's origin sits on the back: across it from the right shoulder (handle) to the left hip (tip).
local function backOffset(): CFrame
	return CFrame.new(0, 0, K.BACK_OFFSET) * CFrame.Angles(0, 0, math.rad(K.BACK_ANGLE)) * CFrame.new(-K.MIDDLE)
end

-- In the right fist: the blade points out of the fist (down the arm), tipped up by HAND_TILT so you can see it over
-- your shoulder, the spine the way the arm's front faces: a raised arm holds it forward and up, edge down.
local function handOffset(): CFrame
	local tilt = math.rad(K.HAND_TILT)
	local blade = Vector3.new(0, -math.cos(tilt), -math.sin(tilt))
	local spine = Vector3.new(0, math.sin(tilt), -math.cos(tilt))
	local turn = CFrame.fromMatrix(Vector3.zero, blade, spine)
	return CFrame.new(0, -K.HAND_DROP, 0) * turn * CFrame.new(-K.GRIP)
end

-- Puts the knife on `character` (making it if it hasn't one): in the hand when `inHand`, else on the back.
function Knives.wear(character: Model, inHand: boolean)
	local holder = character:FindFirstChild(if inHand then "Right Arm" else "Torso")
	if not holder or not holder:IsA("BasePart") then
		return
	end
	local found = character:FindFirstChild(Knives.MODEL_NAME)
	local knife: Model = if found and found:IsA("Model") then found else getTemplate():Clone()
	local root = knife.PrimaryPart
	if not root then
		return
	end
	local weld = root:FindFirstChild(WELD_NAME)
	if not weld or not weld:IsA("Weld") then
		local newWeld = Instance.new("Weld")
		newWeld.Name = WELD_NAME
		newWeld.Parent = root
		weld = newWeld
	end
	local w = weld :: Weld
	w.C0 = if inHand then handOffset() else backOffset()
	w.C1 = CFrame.identity
	w.Part0 = holder
	w.Part1 = root
	if knife.Parent ~= character then
		knife:PivotTo(holder.CFrame * w.C0)
		knife.Parent = character
	end
	character:SetAttribute("KnifeInHand", inHand)
end

return Knives
