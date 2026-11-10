--!strict
-- The coins' rules (design notes, Coins and economy), kept free of anything that needs a running game so they are easy
-- to check. The server's Coins puts coins down and hands them out with them; every screen's CoinFx draws them.
--
-- How a coin gets to every screen: the server keeps one attribute per coin on the ReplicatedStorage folder FOLDER, named
-- "c<id>", holding the coin's spot on the floor (Vector3). A screen that joins mid-round reads them all; a new one is a
-- new coin (it pops in), a removed one is gone. The REMOTE says who took a coin ("take"), which coins fell with a cut
-- strip ("drop") and that the match's coins went ("clear"); your own screen tells the server when you touch one
-- ("take"), so it feels instant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local C = Config.Coins
local S = Config.Shrink

local CoinRules = {}

CoinRules.FOLDER = "ArenaCoins" -- ReplicatedStorage
CoinRules.REMOTE = "Coins" -- ReplicatedStorage.Remotes
CoinRules.MODEL = "CoinModel" -- ReplicatedStorage: the coin's 3D model, shared by the server at start
CoinRules.ATTR_ROUND_COINS = "RoundCoins" -- Player or bot: coins picked up this round (VALUE each)
-- (the coins' speed stack is MoveRules.ATTR_STARS: one for each coin picked up since the round started or you were
-- tagged)

-- A coin's attribute name, and back.
function CoinRules.key(id: number): string
	return "c" .. tostring(id)
end

function CoinRules.idOf(key: string): number?
	if string.sub(key, 1, 1) ~= "c" then
		return nil
	end
	return tonumber(string.sub(key, 2))
end

-- How many coins may be on the map at once with `players` in the round.
function CoinRules.maxAlive(players: number): number
	return math.clamp(math.floor(C.ALIVE_BASE + math.max(players, 0) * C.ALIVE_PER_PLAYER + 1e-6), 1, C.ALIVE_MAX)
end

-- The half-side a new coin has to stay inside: the edge the next cut leaves (the one being warned about now, or the
-- one the next shrink will make), less EDGE_GAP. So a coin never lands on a strip that's about to be cut off.
-- `half` is the square's half-side now, `cutHalf` the warned cut's half-side (0 or nil when none is coming).
function CoinRules.safeHalf(half: number, cutHalf: number?): number
	local nextHalf = half * (1 - S.SHARE)
	if cutHalf and cutHalf > 0 then
		nextHalf = math.min(nextHalf, cutHalf)
	end
	nextHalf = math.max(nextHalf, S.MIN_DIAMETER / 2)
	return math.max(math.min(nextHalf, half) - C.EDGE_GAP, 2)
end

-- Distance across the floor (heights ignored).
function CoinRules.flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Is `spot` outside the square of half-side `half` round `center` (on a strip that's been cut off)?
function CoinRules.outside(spot: Vector3, center: Vector3, half: number): boolean
	return math.abs(spot.X - center.X) > half or math.abs(spot.Z - center.Z) > half
end

-- A spot for a new coin on the floor (its Y is the floor's top): inside `safe` (a half-side round `center`), most of
-- them near the middle, away from the other coins (`taken`) and from bodies (`bodies`). `random` gives 0 to 1.
-- Gives nil when no spot fits after a few tries (the next tick tries again).
function CoinRules.pickSpot(
	center: Vector3,
	safe: number,
	taken: { Vector3 },
	bodies: { Vector3 },
	random: () -> number
): Vector3?
	for _ = 1, 10 do
		local reach = if random() < C.CENTER_SHARE then safe * C.CENTER_ZONE else safe
		local spot = center + Vector3.new((random() * 2 - 1) * reach, 0, (random() * 2 - 1) * reach)
		local clear = true
		for _, other in taken do
			if CoinRules.flatDistance(spot, other) < C.SPACING then
				clear = false
				break
			end
		end
		if clear then
			for _, body in bodies do
				if CoinRules.flatDistance(spot, body) < C.BODY_GAP then
					clear = false
					break
				end
			end
		end
		if clear then
			return spot
		end
	end
	return nil
end

-- "+4.6 SPEED" for a speed bonus.
function CoinRules.speedText(bonus: number): string
	return string.format("+%.1f SPEED", math.max(bonus, 0))
end

return CoinRules
