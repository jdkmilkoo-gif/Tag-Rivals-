--!strict
-- A red outline round every tagger (owner 2026-11-09: "for every tagger add a red outline"), so everyone can see at a
-- glance who's chasing: every chaser in the round, players and Studio bots, yours included. A runner who's just been
-- tagged first glows white and red (TagFx.outline marks the moment; design notes: "the runner gets a white-and-red
-- glowing outline and becomes a chaser"), which fades into the steady red outline.
-- One Highlight a body (Roblox draws at most 31 at once, enough for a full 30-player server).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)

local T = Config.Tag

local ChaserOutline = {}

ChaserOutline.ATTR_FLASH = "TaggedFlashAt" -- on a body, this screen only: os.clock() it was tagged

local RED = Color3.fromHex(T.OUTLINE_COLOR)
local CRIMSON = Color3.fromHex("D3132F")
local WHITE = Color3.new(1, 1, 1)
local NAME = "TagOutline"

local outlines: { [Model]: Highlight } = {}
local steady: { [Highlight]: boolean } = {} -- outlines already set to the plain red one (nothing to change each frame)

-- Everyone who might be outlined: players' bodies (with their Player, which holds the role) and Studio bots.
local function each(callback: (body: Model, owner: Instance) -> ())
	for _, player in Players:GetPlayers() do
		local body = player.Character
		if body then
			callback(body, player)
		end
	end
	local bots = Workspace:FindFirstChild("TagBots")
	if bots then
		for _, bot in bots:GetChildren() do
			if bot:IsA("Model") then
				callback(bot, bot)
			end
		end
	end
end

local function step()
	local now = os.clock()
	local seen: { [Model]: boolean } = {}
	each(function(body: Model, owner: Instance)
		local chasing = owner:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
			and MoveRules.role(owner:GetAttribute(MoveRules.ATTR_ROLE)) == "Chaser"
		local flashAt = body:GetAttribute(ChaserOutline.ATTR_FLASH)
		local flashAge = if type(flashAt) == "number" then now - flashAt else math.huge
		local flashing = flashAge < T.OUTLINE_TIME
		if not chasing and not flashing then
			return
		end
		seen[body] = true
		local outline = outlines[body]
		if not outline or outline.Parent ~= body then
			if outline then
				steady[outline] = nil
			end
			outline = Instance.new("Highlight")
			outline.Name = NAME
			outline.DepthMode = Enum.HighlightDepthMode.Occluded
			outline.Adornee = body
			outline.Parent = body
			outlines[body] = outline
		end
		local o = outline :: Highlight
		if flashing then
			steady[o] = nil
			-- just tagged: a white-and-red glow fading into the steady red outline
			local x = flashAge / T.OUTLINE_TIME
			o.FillColor = CRIMSON
			o.FillTransparency = 0.35 + 0.65 * x
			o.OutlineColor = WHITE:Lerp(RED, x)
			o.OutlineTransparency = if chasing then 0 else x
		elseif not steady[o] then
			-- set once: changing a highlight every frame makes it redraw
			steady[o] = true
			o.FillTransparency = 1
			o.OutlineColor = RED
			o.OutlineTransparency = 0
		end
	end)
	for body, outline in outlines do
		if not seen[body] then
			steady[outline] = nil
			outline:Destroy()
			outlines[body] = nil
		end
	end
end

function ChaserOutline.start()
	RunService.Heartbeat:Connect(step)
end

return ChaserOutline
