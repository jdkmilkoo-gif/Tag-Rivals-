--!strict
-- Every sound in the game (owner 2026-11-13: "add sounds for everything, and dont make them annyoing, if its the same
-- souns again, adjuts the pitch or temp"; design notes: Round flow, Shrink shake and sound, Star pickup feel). All
-- played on your own screen, from Config.Sound.
-- So nothing grates:
--   * the same sound never plays the same way twice running: each time it comes back its pitch and speed move a step
--     (Roblox's PlaybackSpeed changes both together), within a small range set for each sound;
--   * a sound that keeps coming quickly gets quieter each time, and one asked for again within a few hundredths of a
--     second is skipped, so a busy moment never stacks into noise;
--   * other players' tags, slashes and falls are only heard near you, quieter with distance;
--   * coins climb a scale (do re mi...) while you keep picking them up, a countdown's ticks rise as it runs out, and
--     the last man's heartbeat goes lub-dub.
-- Every screen's buttons use Sounds.click, Sounds.hover, Sounds.open, Sounds.close and Sounds.error.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local CoinRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CoinRules"))
local Config = require(ReplicatedStorage.Shared.Config)
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local MoveController = require(script.Parent.MoveController)
local ProgressLink = require(script.Parent.ProgressLink)

local S = Config.Sound

local Sounds = {}

-- A sound and how it's played: its own pitch and loudness, the least time between two of it, and how far its pitch
-- and speed may move when it comes again (0.06: up to 6% either way).
-- `steady`: it's meant to repeat (a countdown, a heartbeat, a chime's notes), so repeats don't get quieter.
type Cue = { id: string, pitch: number, volume: number, gap: number, vary: number, steady: boolean? }
type State = { lastAt: number, lastStep: number, burst: number }
type Options = { pitch: number?, volume: number? }

local CUES: { [string]: Cue } = {
	-- the round
	go = { id = S.GO, pitch = 1, volume = 0.7, gap = 1, vary = 0.04 },
	whoosh = { id = S.DASH, pitch = 0.55, volume = 0.5, gap = 0.5, vary = 0.06 }, -- the fade into a round
	tag = { id = S.TAG, pitch = S.TAG_PITCH, volume = 0.9, gap = 0.08, vary = 0.08 },
	tagged = { id = S.DEFEAT, pitch = 1.2, volume = 0.85, gap = 0.5, vary = 0.04 }, -- you were tagged
	sting = { id = S.TAG, pitch = 0.6, volume = 0.8, gap = 0.5, vary = 0.04 }, -- you're the chaser; you're wanted
	slash = { id = S.SLASH, pitch = 1, volume = 0.45, gap = 0.06, vary = 0.1 },
	dash = { id = S.DASH, pitch = 1.08, volume = 0.5, gap = 0.05, vary = 0.08 },
	empty = { id = S.CLICK, pitch = 0.7, volume = 0.3, gap = 0.35, vary = 0.06 }, -- a dash with no charge left
	dodge = { id = S.DODGE, pitch = 1, volume = 0.7, gap = 0.2, vary = 0.06 },
	stunned = { id = S.DEFEAT, pitch = 1.5, volume = 0.6, gap = 0.5, vary = 0.05 }, -- a runner dodged you
	fall = { id = S.FALL, pitch = 1, volume = 0.7, gap = 0.3, vary = 0.08 },
	speedUp = { id = S.GO, pitch = 1.5, volume = 0.22, gap = 1.5, vary = 0.08 },
	shrinkThud = { id = S.SHRINK_THUD, pitch = 0.8, volume = 0.9, gap = 0.5, vary = 0.05 },
	shrinkSlam = { id = S.SHRINK_SLAM, pitch = 1, volume = 0.9, gap = 0.5, vary = 0.05 },
	crumble = { id = S.SHRINK_CRUMBLE, pitch = 1, volume = 0.5, gap = 0.5, vary = 0.1 },
	lastMan = { id = S.LAST_MAN, pitch = 1, volume = 0.9, gap = 5, vary = 0 },
	heartbeat = { id = S.HEARTBEAT, pitch = 0.9, volume = 0.5, gap = 0.1, vary = 0, steady = true },
	-- countdowns set its pitch themselves
	tick = { id = S.TICK, pitch = 1, volume = 0.45, gap = 0.08, vary = 0, steady = true },
	victory = { id = S.VICTORY, pitch = 1, volume = 0.6, gap = 3, vary = 0.03 },
	defeat = { id = S.DEFEAT, pitch = 0.8, volume = 0.8, gap = 3, vary = 0.03 },
	-- coins and rewards
	coin = { id = S.COIN, pitch = 1, volume = 0.5, gap = 0.03, vary = 0 }, -- climbs the scale itself
	coinThud = { id = S.COIN_THUD, pitch = 1.1, volume = 0.22, gap = 0.03, vary = 0.08 },
	ping = { id = S.REWARD, pitch = 1, volume = 0.4, gap = 0.03, vary = 0, steady = true }, -- rewards chime up the scale
	count = { id = S.TICK, pitch = 1.3, volume = 0.3, gap = 0.04, vary = 0.1 }, -- a number counting up
	levelUp = { id = S.LEVEL_UP, pitch = 1.18, volume = 0.6, gap = 2, vary = 0.03 },
	-- buttons and panels
	click = { id = S.CLICK, pitch = 1, volume = 0.5, gap = 0.04, vary = 0.07 },
	hover = { id = S.TICK, pitch = 1.7, volume = 0.16, gap = 0.06, vary = 0.1 },
	open = { id = S.OPEN, pitch = 1, volume = 0.5, gap = 0.1, vary = 0.06 },
	close = { id = S.OPEN, pitch = 0.78, volume = 0.4, gap = 0.1, vary = 0.06 },
	error = { id = S.COIN_THUD, pitch = 0.7, volume = 0.5, gap = 0.2, vary = 0.06 },
}

local POOL = 3 -- copies of one sound that can play over each other
local STEPS = 3 -- pitch steps either side of a sound's own pitch
local BURST_WINDOW = 1.5 -- s: the same sound again inside this counts as "keeps coming"
local BURST_QUIETER = 0.88 -- each one in a burst is this much quieter,
local BURST_FLOOR = 0.45 -- down to this share of its loudness

local player = Players.LocalPlayer
local rng = Random.new()
local group: SoundGroup? = nil
local pools: { [string]: { Sound } } = {}
local states: { [string]: State } = {}

local function soundFor(id: string): Sound
	local pool = pools[id]
	if not pool then
		pool = {}
		pools[id] = pool
	end
	for _, sound in pool do
		if not sound.IsPlaying then
			return sound
		end
	end
	if #pool < POOL then
		local sound = Instance.new("Sound")
		sound.Name = "TagRivalsSound"
		sound.SoundId = id
		sound.SoundGroup = group
		sound.Parent = SoundService
		table.insert(pool, sound)
		return sound
	end
	-- all busy: the one that started first goes again
	local oldest = table.remove(pool, 1) :: Sound
	table.insert(pool, oldest)
	return oldest
end

-- Plays a sound by its name in CUES. `options.pitch` and `options.volume` multiply the sound's own.
function Sounds.play(name: string, options: Options?)
	local cue = CUES[name]
	if not cue or cue.id == "" then
		return
	end
	local now = os.clock()
	local state = states[name]
	if not state then
		state = { lastAt = -math.huge, lastStep = 0, burst = 0 }
		states[name] = state
	end
	local since = now - state.lastAt
	if since < cue.gap then
		return
	end
	state.burst = if since < BURST_WINDOW then state.burst + 1 else 0
	state.lastAt = now
	local pitch = cue.pitch * (if options and options.pitch then options.pitch else 1)
	if cue.vary > 0 then
		-- a step up or down from its own pitch, never the same step as last time
		local step = state.lastStep
		while step == state.lastStep do
			step = rng:NextInteger(-STEPS, STEPS)
		end
		state.lastStep = step
		pitch *= 1 + step / STEPS * cue.vary
	end
	local volume = cue.volume * (if options and options.volume then options.volume else 1)
	if not cue.steady then
		volume *= math.max(BURST_QUIETER ^ state.burst, BURST_FLOOR)
	end
	if volume <= 0.01 then
		return
	end
	local sound = soundFor(cue.id)
	sound.PlaybackSpeed = math.clamp(pitch, 0.3, 3)
	sound.Volume = math.clamp(volume * S.VOLUME, 0, 2)
	sound.TimePosition = 0
	sound:Play()
end

-- A little run of pings up the scale: `count` notes starting `from` notes up (rewards, a quest done, a level).
function Sounds.chime(count: number, from: number?)
	local notes = S.COIN_NOTES
	for i = 1, count do
		local note = notes[math.clamp((from or 0) + i, 1, #notes)]
		task.delay((i - 1) * 0.085, function()
			Sounds.play("ping", { pitch = note, volume = 0.75 + 0.25 * i / count })
		end)
	end
end

function Sounds.click()
	Sounds.play("click")
end

function Sounds.hover()
	Sounds.play("hover")
end

function Sounds.open()
	Sounds.play("open")
end

function Sounds.close()
	Sounds.play("close")
end

function Sounds.error()
	Sounds.play("error")
end

---------------------------------------------------------------- what's heard, and how loud

local function rootOf(who: any): BasePart?
	if typeof(who) ~= "Instance" then
		return nil
	end
	local body = if who:IsA("Player") then who.Character else who
	local root = if body then body:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- How loud something at `position` is to you: 1 right by you, 0 from HEAR_RANGE studs off.
local function near(position: Vector3?): number
	if not position then
		return 0
	end
	local mine = rootOf(player)
	local camera = Workspace.CurrentCamera
	local ears = if mine then mine.Position elseif camera then camera.CFrame.Position else nil
	if not ears then
		return 0
	end
	return math.clamp(1 - (ears - position).Magnitude / S.HEAR_RANGE, 0, 1)
end

local function nearWho(who: any): number
	local root = rootOf(who)
	return near(if root then root.Position else nil)
end

local function isChaser(): boolean
	return MoveRules.role(player:GetAttribute(MoveRules.ATTR_ROLE)) == "Chaser"
end

local function inRound(): boolean
	return player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
end

local function onRound(kind: unknown, a: any, b: any)
	if kind == "fade" then
		Sounds.play("whoosh")
	elseif kind == "chaser" then
		if a == player then
			Sounds.play("sting")
		end
	elseif kind == "go" then
		Sounds.play("go")
	elseif kind == "tag" and type(a) == "table" then
		if a.runner == player then
			Sounds.play("tagged")
			Sounds.play("tag")
		elseif a.chaser == player then
			Sounds.play("tag")
		else
			local loud = near(if typeof(a.at) == "Vector3" then a.at else nil)
			if loud > 0.05 then
				Sounds.play("tag", { volume = loud * 0.8 })
			end
		end
	elseif kind == "slash" then
		local loud = if a == player then 1 else nearWho(a) * 0.7
		if loud > 0.05 then
			Sounds.play("slash", { volume = loud, pitch = if b == "stab" then 1.25 else 1 })
		end
	elseif kind == "dodge" and type(a) == "table" then
		if a.runner == player then
			Sounds.play("dodge")
		elseif a.chaser == player then
			Sounds.play("stunned")
		else
			local loud = nearWho(a.runner)
			if loud > 0.2 then
				Sounds.play("dodge", { volume = loud * 0.5 })
			end
		end
	elseif kind == "fell" and type(a) == "table" then
		local loud = if a.who == player then 1 else nearWho(a.who) * 0.6
		if loud > 0.05 then
			Sounds.play("fall", { volume = loud })
		end
	elseif kind == "shrink" then
		-- the first shrinks thud, lower each time; the later ones slam; and the strip crumbles away
		local count = if type(a) == "number" then a else 1
		if count <= 3 then
			Sounds.play("shrinkThud", { pitch = 1.1 - 0.08 * count })
		else
			Sounds.play("shrinkSlam", { pitch = 1.06 - 0.02 * math.min(count, 8) })
		end
		Sounds.play("crumble", { pitch = 1.1 - 0.03 * math.min(count, 8) })
	elseif kind == "victory" and type(a) == "table" then
		if a.winner == "None" or not inRound() then
			Sounds.play("ping", { pitch = 0.8 })
		elseif (a.winner == "Chasers") == isChaser() then
			Sounds.play("victory")
		else
			Sounds.play("defeat")
		end
	elseif kind == "bounty" and type(a) == "table" then
		if a.who == player then
			Sounds.play("sting", { pitch = 1.3 })
		end
		Sounds.chime(2, 4)
	elseif kind == "bountyUp" and type(a) == "table" then
		Sounds.play("ping", { pitch = 1.5, volume = if a.who == player then 1 else 0.5 })
	elseif kind == "bountyEnd" and type(a) == "table" then
		if (a.kind == "tagged" and a.by == player) or (a.kind == "kept" and a.who == player) then
			Sounds.chime(4, 2)
		elseif a.kind == "lost" or a.who == player then
			Sounds.play("error", { volume = 0.6 })
		end
	end
end

-- Your own coin pick-ups climb the scale while you keep picking them up.
local coinNote = 0
local coinAt = -math.huge

local function onCoin(action: unknown, _id: any, who: any)
	if action ~= "take" or who ~= player then
		return
	end
	local now = os.clock()
	coinNote = if now - coinAt <= S.COIN_CHAIN then math.min(coinNote + 1, #S.COIN_NOTES) else 1
	coinAt = now
	Sounds.play("coin", { pitch = S.COIN_NOTES[coinNote] })
	Sounds.play("coinThud")
end

---------------------------------------------------------------- countdowns and the heartbeat

local lastCut = -1
local lastMatch = -1
local lastBreak = -1
local lastPhase = 1
local beatAt = 0
local beatSecond = false

local function attribute(name: string): number
	local value = Workspace:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function watch()
	local now = Workspace:GetServerTimeNow()
	local state = Workspace:GetAttribute(RoundRules.ATTR_STATE)
	local endsAt = attribute(RoundRules.ATTR_ENDS_AT)
	local left = if endsAt > 0 then math.ceil(endsAt - now) else -1

	-- the shrink's 3, 2, 1: each tick a step higher
	local cutAt = attribute(RoundRules.ATTR_CUT_AT)
	local cutLeft = if cutAt > 0 and state == "Match" then math.ceil(cutAt - now) else -1
	if cutLeft ~= lastCut then
		lastCut = cutLeft
		if cutLeft >= 1 and cutLeft <= 3 and inRound() then
			Sounds.play("tick", { pitch = 1.36 - 0.12 * cutLeft, volume = 1.2 })
		end
	end

	-- the match's last 10 s, rising as it runs out
	local matchLeft = if state == "Match" then left else -1
	if matchLeft ~= lastMatch then
		lastMatch = matchLeft
		if matchLeft >= 1 and matchLeft <= 10 then
			Sounds.play("tick", { pitch = 1.5 - 0.05 * matchLeft, volume = if matchLeft <= 3 then 1.1 else 0.7 })
		end
	end

	-- the break's last 3 s: the round is about to start
	local breakLeft = if state == "Intermission" then left else -1
	if breakLeft ~= lastBreak then
		lastBreak = breakLeft
		if breakLeft >= 1 and breakLeft <= 3 then
			Sounds.play("tick", { pitch = 1.2 - 0.1 * breakLeft, volume = 0.8 })
		end
	end

	-- last man standing: a bass drop for everyone in the round, then the last runner hears their own heart
	local phase = if state == "Match" then attribute(RoundRules.ATTR_PHASE) else 1
	if phase ~= lastPhase then
		if phase >= 4 and lastPhase < 4 and inRound() then
			Sounds.play("lastMan")
		end
		lastPhase = phase
	end
	if phase >= 4 and inRound() and not isChaser() then
		local clock = os.clock()
		if clock >= beatAt then
			-- lub-dub: the second thump comes quickly, lower and softer
			beatSecond = not beatSecond
			beatAt = clock + (if beatSecond then S.HEARTBEAT_EVERY * 0.32 else S.HEARTBEAT_EVERY * 0.68)
			Sounds.play("heartbeat", { pitch = if beatSecond then 1 else 0.86, volume = if beatSecond then 1 else 0.7 })
		end
	end
end

function Sounds.start()
	local made = Instance.new("SoundGroup")
	made.Name = "TagRivalsSounds"
	made.Volume = 1
	made.Parent = SoundService
	group = made

	-- fetched before they're needed, so the first tag isn't silent
	task.spawn(function()
		local seen: { [string]: boolean } = {}
		local list: { Instance } = {}
		for _, cue in CUES do
			if cue.id ~= "" and not seen[cue.id] then
				seen[cue.id] = true
				table.insert(list, soundFor(cue.id))
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local round = remotes:WaitForChild("Round") :: RemoteEvent
	round.OnClientEvent:Connect(onRound)
	task.spawn(function()
		local coins = remotes:WaitForChild(CoinRules.REMOTE, 60)
		if coins and coins:IsA("RemoteEvent") then
			coins.OnClientEvent:Connect(onCoin)
		end
	end)

	MoveController.onDash(function()
		Sounds.play("dash")
	end)
	MoveController.onEmpty(function()
		Sounds.play("empty")
	end)
	MoveController.onSpeedUp(function()
		Sounds.play("speedUp")
	end)

	-- coins paid to you, levels, quests and the daily bonus
	ProgressLink.on("coins", function(amount: any, source: any)
		if source == "TAG" then
			Sounds.play("ping", { pitch = 1.26, volume = 0.8 }) -- the tag has its own sound already
		elseif source ~= "BOUNTY" then -- (a bounty's end chimes by itself)
			Sounds.chime(if type(amount) == "number" and amount >= 50 then 3 else 2, 2)
		end
	end)
	ProgressLink.on("level", function()
		Sounds.play("levelUp")
	end)
	ProgressLink.on("questDone", function()
		Sounds.chime(3, 3)
	end)
	ProgressLink.on("streak", function()
		Sounds.chime(4, 1)
	end)
	ProgressLink.on("code", function(ok: any)
		if ok == true then
			Sounds.chime(4, 2)
		else
			Sounds.error()
		end
	end)

	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= 0.05 then
			since = 0
			watch()
		end
	end)
end

return Sounds
