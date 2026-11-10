--!strict
-- Chrono, the position library (design notes: "Hitboxes use Chrono (same library as Huss Zero: position sync, snapshot
-- interpolation, lag compensation)"). Chrono 2.2.3 by Parihsz (MIT), in ReplicatedStorage.Shared.Chrono, set up the
-- way Huss Zero runs it:
--   * every player's game sends its own body's spot Config.Net.SEND_RATE times a second, stamped with its own clock;
--   * every other screen plays those spots back smoothly, a moment behind (snapshot interpolation);
--   * Roblox's own sending stays on alongside it (Chrono's NATIVE mode), so the server's checks see bodies as before.
-- The tag check uses it from both ends: the chaser's screen says at which moment of the runner's own clock it drew the
-- runner (ChronoSetup.renderTime), and the server's History keeps each body's spots by that same clock
-- (ChronoSetup.latest), so it can look up exactly where the runner was on the chaser's screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local ChronoSetup = {}

-- Chrono's own module once started (a library without our types, so it is held loosely).
local chrono: any = nil

local function entityOf(player: Player): any
	local library = chrono
	if not library then
		return nil
	end
	local ok, entity = pcall(library.Holder.GetEntityFromPlayer, player)
	if ok and entity and not entity.destroyed then
		return entity
	end
	return nil
end

-- Starts Chrono with Tag Rivals' settings (once; nothing while Config.Net.CHRONO is off).
function ChronoSetup.start()
	if chrono or not Config.Net.CHRONO then
		return
	end
	local module = ReplicatedStorage.Shared:FindFirstChild("Chrono")
	if not module or not module:IsA("ModuleScript") then
		warn(`[{Config.GameName}] Chrono is switched on but ReplicatedStorage.Shared.Chrono is missing`)
		return
	end
	local library = (require :: any)(module)
	local settings = library.Config
	settings.SetConfig("CHECK_NEW_VERSION", false) -- no call to GitHub at every server start
	settings.SetConfig("REPLICATE_DEATHS", "NONE") -- nobody dies in Tag Rivals
	settings.SetConfig("WARNING_SEVERITY", "LOW")
	settings.RegisterEntityType("PLAYER", {
		NAME = "PLAYER",
		MODEL_REPLICATION_MODE = "NATIVE",
		BUFFER = 0, -- Chrono picks the smallest safe delay by itself
		TICK_RATE = 1 / Config.Net.SEND_RATE,
		HALF_TICK_DISTANCE = math.huge, -- every body is sent at full rate at every distance (the lobby watches)
		ASSEMBLY_ROOT_PART_CHECK = true,
	})
	library.Start()
	chrono = library
end

function ChronoSetup.running(): boolean
	return chrono ~= nil
end

-- Screens: the moment of `other`'s own clock their body is drawn at on this screen right now (nil: not known).
function ChronoSetup.renderTime(other: Player): number?
	local entity = entityOf(other)
	if not entity or RunService:IsServer() then
		return nil
	end
	local ok, t = pcall(chrono.Entity.GetTargetRenderTime, entity)
	if ok and type(t) == "number" and t > 0 and t == t then
		return t
	end
	return nil
end

-- Server: the newest spot Chrono has from `player`'s current body: the stamp (their own clock) and the root's CFrame.
function ChronoSetup.latest(player: Player): (number?, CFrame?)
	local entity = entityOf(player)
	if not entity or entity.model ~= player.Character then
		return nil, nil
	end
	local stamp = entity.lastClientClock
	local cframe = entity.latestCFrame
	if type(stamp) ~= "number" or typeof(cframe) ~= "CFrame" then
		return nil, nil
	end
	return stamp, cframe
end

-- Your own body just jumped somewhere (a spawn): tells Chrono, so other screens show it straight there.
function ChronoSetup.jumped(root: BasePart)
	local entity = entityOf(Players.LocalPlayer)
	if entity then
		pcall(chrono.Entity.SetCFrame, entity, root.CFrame)
	end
end

return ChronoSetup
