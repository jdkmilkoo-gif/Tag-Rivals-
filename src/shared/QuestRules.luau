--!strict
-- The quests (design notes, Coins and economy: "3 random quests in each of Daily, Weekly and Monthly, each tab showing
-- time left until it refreshes"), kept free of anything that needs a running game so they are easy to check. The
-- server's Quests hands them out and counts them; the quest panel on each screen draws them from the same list.
--
-- Each quest counts one kind of moment (its `event`) up to its `goal`, then pays `reward` coins when you press CLAIM.
-- The moments, said by the server as they happen (Progress.event):
--   tag        you tagged a runner            dashTag   ...with a dash
--   survive    you survived a full match      clutch    ...as the last runner standing
--   phase1     you lasted past phase 1        round     you played a round to its end
--   dash       you dashed (in a match)        closeDash ...with a chaser close (Config.Quests.CLOSE_RANGE)
--   dodge      a perfect dodge                star      you picked a coin up on the map
--   bounty     you collected (or kept) a bounty

local QuestRules = {}

export type SetName = "daily" | "weekly" | "monthly"

export type Quest = {
	id: string,
	title: string,
	text: string, -- what to do; %d is the goal
	event: string,
	goal: number,
	reward: number, -- coins
}

-- A player's quest as saved and as sent to their screen.
export type Entry = { id: string, progress: number, claimed: boolean }

local sets: { SetName } = { "daily", "weekly", "monthly" }
QuestRules.SETS = sets
local setTitles: { [string]: string } = { daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY" }
QuestRules.SET_TITLES = setTitles

local function quest(id: string, title: string, text: string, event: string, goal: number, reward: number): Quest
	return table.freeze({ id = id, title = title, text = text, event = event, goal = goal, reward = reward })
end

-- Rewards (owner): daily 100-250 coins, weekly 800-1,200, monthly 3,500-5,000. The first two dailies and the weekly
-- and monthly ones marked "owner" are the owner's; the rest are Claude's picks in the same spirit.
local pools: { [string]: { Quest } } = {
	daily = table.freeze({
		quest("d_adrenaline", "ADRENALINE JUNKIE", "Dash %d times while a chaser is close", "closeDash", 10, 100), -- owner
		quest("d_flawless", "PURE FLAWLESS", "Survive a full round untagged", "survive", 1, 250), -- owner
		quest("d_tags", "ON THE HUNT", "Tag %d runners", "tag", 5, 150),
		quest("d_stars", "STAR CHASER", "Pick up %d coins in rounds", "star", 30, 120),
		quest("d_rounds", "WARM UP", "Play %d rounds", "round", 3, 100),
		quest("d_dodge", "UNTOUCHABLE", "Land %d perfect dodges", "dodge", 2, 200),
		quest("d_phase", "STILL STANDING", "Last past the first phase %d times", "phase1", 3, 150),
		quest("d_lunge", "LUNGE!", "Tag %d runners with a dash", "dashTag", 2, 180),
	}),
	weekly = table.freeze({
		quest("w_survive", "IRON LUNGS", "Survive %d full rounds", "survive", 25, 1200), -- owner
		quest("w_close", "DANGER DANCER", "Dash %d times inside a chaser's reach", "closeDash", 40, 1000), -- owner
		quest("w_tags", "SWARM LEADER", "Tag %d runners", "tag", 60, 900),
		quest("w_stars", "TREASURE HUNTER", "Pick up %d coins in rounds", "star", 300, 800),
		quest("w_rounds", "REGULAR", "Play %d rounds", "round", 40, 800),
		quest("w_dodge", "MATADOR", "Land %d perfect dodges", "dodge", 15, 1100),
		quest("w_bounty", "BOUNTY HUNTER", "Collect or keep %d bounties", "bounty", 5, 1000),
	}),
	monthly = table.freeze({
		quest("m_tags", "THE INFECTION", "Tag %d runners", "tag", 200, 4000), -- owner
		quest("m_clutch", "LAST ONE STANDING", "Win %d rounds as the last runner", "clutch", 15, 5000), -- owner
		quest("m_rounds", "VETERAN", "Play %d rounds", "round", 150, 3500),
		quest("m_survive", "UNCATCHABLE", "Survive %d full rounds", "survive", 80, 4500),
		quest("m_stars", "GOLD RUSH", "Pick up %d coins in rounds", "star", 1500, 3500),
	}),
}
QuestRules.POOLS = pools

local byId: { [string]: Quest } = {}
for _, pool in pools do
	for _, each in pool do
		byId[each.id] = each
	end
end

function QuestRules.get(id: string): Quest?
	return byId[id]
end

-- A quest's line with its goal filled in: "Tag 5 runners".
function QuestRules.describe(each: Quest): string
	local text = string.gsub(each.text, "%%d", tostring(each.goal))
	return text
end

local DAY = 86400

-- Which day, week or month `unix` (seconds since 1970, UTC) is in, as a number that goes up by one each time the set
-- refreshes. Days turn over at midnight UTC, weeks on Monday, months on the 1st.
function QuestRules.period(set: SetName, unix: number): number
	if set == "daily" then
		return unix // DAY
	elseif set == "weekly" then
		return (unix // DAY + 3) // 7 -- 1 Jan 1970 was a Thursday
	end
	local date = os.date("!*t", unix) :: any
	return date.year * 12 + (date.month - 1)
end

-- Seconds from `unix` until `set` refreshes.
function QuestRules.untilRefresh(set: SetName, unix: number): number
	if set == "daily" then
		return DAY - unix % DAY
	elseif set == "weekly" then
		local intoWeek = (unix + 3 * DAY) % (7 * DAY)
		return 7 * DAY - intoWeek
	end
	local date = os.date("!*t", unix) :: any
	local year, month = date.year, date.month + 1
	if month > 12 then
		year, month = year + 1, 1
	end
	local nextMonth = os.time({ year = year, month = month, day = 1, hour = 0, min = 0, sec = 0 })
	-- os.time reads the table as local time on some machines: count from this month's start instead when it's off
	local thisMonth = os.time({ year = date.year, month = date.month, day = 1, hour = 0, min = 0, sec = 0 })
	local length = nextMonth - thisMonth
	local into = (date.day - 1) * DAY + date.hour * 3600 + date.min * 60 + date.sec
	return math.max(length - into, 0)
end

-- "5h 12m", "3d 4h", "12m 30s" for seconds left.
function QuestRules.timeText(seconds: number): string
	local left = math.max(math.floor(seconds), 0)
	local days = left // DAY
	local hours = left % DAY // 3600
	local minutes = left % 3600 // 60
	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%dm %02ds", minutes, left % 60)
end

-- `count` different quests from `set`'s pool, none of them in `skip`. `random(n)` gives a whole number 1 to n.
function QuestRules.pick(set: SetName, count: number, skip: { [string]: boolean }, random: (n: number) -> number): { Quest }
	local pool: { Quest } = {}
	for _, each in pools[set] do
		if not skip[each.id] then
			table.insert(pool, each)
		end
	end
	local picked: { Quest } = {}
	while #picked < count and #pool > 0 do
		table.insert(picked, table.remove(pool, random(#pool)) :: Quest)
	end
	return picked
end

return QuestRules
