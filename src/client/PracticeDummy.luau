--!strict
-- The lobby's practice dummy (launch checklist: let new players learn the perfect dodge before a round;
-- Config.LobbyExtras). The server only stands its body at its post; everything it does happens on your screen alone:
--   * step into its red ring and every few seconds it glows red, then lunges at you like a chaser;
--   * the gold star shows over your head exactly as in a round (PerfectDodge treats the lunging dummy as a chaser):
--     dash while it shows for "PERFECT DODGE!"; too late and it "tags" you. Nothing is won or lost;
--   * a sign over its head says what it's for and counts your dodges in a row.
-- It runs with the real run animation, goes back to its post after each lunge, and does nothing while you're in a
-- round or far from it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local MoveController = require(script.Parent.MoveController)
local PerfectDodge = require(script.Parent.PerfectDodge)
local PlasticUi = require(script.Parent.PlasticUi)
local RoundHud = require(script.Parent.RoundHud)
local Sounds = require(script.Parent.Sounds)
local UiKit = require(script.Parent.UiKit)

local X = Config.LobbyExtras

local PracticeDummy = {}

local player = Players.LocalPlayer

local AWAKE_RANGE = 70 -- studs: further than this from its post, nothing runs
local BACK_TIME = 0.45 -- s to get back to its post
local STUN_TIME = 0.9 -- s it stands dazed after you dodge it
local RED = Color3.fromHex("FF2B4A")
local GREY = Color3.fromHex("C8CCD8")

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function loadTrack(animator: Animator, id: unknown, looped: boolean): AnimationTrack?
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(id)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = looped
	track.Priority = Enum.AnimationPriority.Movement
	return track
end

local function run(dummy: Model)
	-- its parts can arrive a moment after the body itself
	dummy:WaitForChild("HumanoidRootPart", 20)
	local head = dummy:WaitForChild("Head", 20)
	local humanoid = dummy:WaitForChild("Humanoid", 20)
	local found = if humanoid then humanoid:WaitForChild("Animator", 5) else nil
	local animator = if found and found:IsA("Animator") then found else nil
	local home = dummy:GetPivot()
	local idle = if animator then loadTrack(animator, Config.Anim.IdleAnimationId, true) else nil
	local sprint = if animator then loadTrack(animator, Config.Anim.SprintAnimationId, true) else nil
	if idle then
		idle:Play(0)
	end

	local glow = Instance.new("Highlight")
	glow.Name = "PracticeGlow"
	glow.FillColor = RED
	glow.OutlineColor = RED
	glow.FillTransparency = 1
	glow.OutlineTransparency = 1
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Adornee = dummy
	glow.Parent = dummy

	-- the sign over its head
	local sign = Instance.new("BillboardGui")
	sign.Name = "TagRivalsPracticeSign"
	sign.Size = UDim2.fromOffset(300, 64)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	sign.MaxDistance = AWAKE_RANGE
	sign.LightInfluence = 0
	sign.ResetOnSpawn = false
	sign.Adornee = if head and head:IsA("BasePart") then head else dummy.PrimaryPart
	local top = PlasticUi.text({ name = "Top", size = 24, parent = sign, zIndex = 2 })
	top.root.Size = UDim2.new(1, 0, 0, 30)
	top:set("DODGE PRACTICE")
	PlasticUi.shimmer(top.label, PlasticUi.GOLD, 2)
	local sub = PlasticUi.text({ name = "Sub", size = 16, parent = sign, zIndex = 2 })
	sub.root.Position = UDim2.fromOffset(0, 32)
	sub.root.Size = UDim2.new(1, 0, 0, 22)
	sign.Parent = player:WaitForChild("PlayerGui")
	local shownSub = ""
	local function say(words: string)
		if words ~= shownSub then
			shownSub = words
			sub:set(words)
		end
	end

	local state = "rest"
	local stateAt = os.clock()
	local nextAt = os.clock() + 2
	local streak = 0
	local dodged = false
	local dashedEarly = false
	local reachedAt = math.huge -- when it got within reach of you this lunge
	local backFrom = home
	local running = false

	local function setRunning(on: boolean)
		if on ~= running then
			running = on
			if sprint then
				if on then
					sprint:Play(0.08)
				else
					sprint:Stop(0.15)
				end
			end
		end
	end
	local function go(new: string)
		state = new
		stateAt = os.clock()
	end
	local function goBack()
		PerfectDodge.practice(nil, nil)
		setRunning(false)
		backFrom = dummy:GetPivot()
		nextAt = os.clock() + BACK_TIME + X.DUMMY_EVERY
		go("back")
	end
	-- stands at `position` (its feet height never changes), looking the flat way `look`
	local function stand(position: Vector3, look: Vector3)
		local spot = Vector3.new(position.X, home.Position.Y, position.Z)
		local way = flat(look)
		if way.Magnitude > 1e-3 then
			dummy:PivotTo(CFrame.lookAt(spot, spot + way.Unit))
		else
			dummy:PivotTo(CFrame.new(spot) * dummy:GetPivot().Rotation)
		end
	end

	MoveController.onDash(function()
		if state == "lunge" and not dodged then
			dashedEarly = true -- (a perfect dodge sets `dodged` first, below)
		end
	end)

	RunService.PreRender:Connect(function(dt: number)
		local now = os.clock()
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local mine = if root and root:IsA("BasePart") then root.Position else nil
		local inRound = player:GetAttribute(RoundRules.ATTR_IN_ROUND) == true
		local fromHome = if mine then flat(mine - home.Position).Magnitude else math.huge
		if inRound or not mine or fromHome > AWAKE_RANGE then
			if state ~= "rest" then
				PerfectDodge.practice(nil, nil)
				setRunning(false)
				dummy:PivotTo(home)
				glow.FillTransparency = 1
				glow.OutlineTransparency = 1
				go("rest")
			end
			return
		end
		local here = dummy:GetPivot().Position
		local toMe = flat(mine - here)
		local gap = toMe.Magnitude
		local inRing = fromHome <= X.DUMMY_ZONE

		if state == "rest" then
			glow.FillTransparency = 1
			glow.OutlineTransparency = 1
			if inRing then
				stand(home.Position, toMe)
				if gap < X.DUMMY_MIN_GAP then
					say("STEP BACK A LITTLE")
					nextAt = math.max(nextAt, now + 0.6)
				else
					say(if streak > 0 then `{streak} IN A ROW! AGAIN...` else "DASH WHEN THE GOLD STAR SHOWS")
					if now >= nextAt and not UiKit.anyOpen() then
						Sounds.play("tick", { pitch = 0.8, volume = 1.2 })
						go("windup")
					end
				end
			else
				say("STEP INTO THE RING")
				nextAt = math.max(nextAt, now + 1)
			end
		elseif state == "windup" then
			-- it glows red, faster and faster, then goes
			local share = math.clamp((now - stateAt) / X.DUMMY_WINDUP, 0, 1)
			local beat = 0.5 + 0.5 * math.sin((now - stateAt) * (10 + 20 * share))
			glow.FillTransparency = 1 - 0.55 * share * (0.5 + 0.5 * beat)
			glow.OutlineTransparency = 1 - share
			stand(home.Position, toMe)
			say("HERE IT COMES...")
			if share >= 1 then
				dodged = false
				dashedEarly = false
				reachedAt = math.huge
				PerfectDodge.practice(dummy, function()
					dodged = true
				end)
				Sounds.play("slash", { pitch = 0.8 })
				setRunning(true)
				go("lunge")
			end
		elseif state == "lunge" then
			glow.FillTransparency = 0.45
			glow.OutlineTransparency = 0
			if gap <= X.DUMMY_REACH and reachedAt == math.huge then
				reachedAt = now
			end
			if dodged then
				streak += 1
				PerfectDodge.practice(nil, nil)
				setRunning(false)
				RoundHud.say(if streak > 1 then `{streak} DODGES IN A ROW!` else "THAT'S IT!", nil, PlasticUi.GOLD, 1.2, true)
				go("stunned")
			elseif reachedAt ~= math.huge and now - reachedAt >= Config.Dodge.GRACE then
				-- within reach, and the moment a late press still counts has passed
				streak = 0
				Sounds.play("tag", { volume = 0.7 })
				RoundHud.say("TOO LATE!", "Dash the moment the gold star shows", UiKit.RED, 1.6, true)
				goBack()
			elseif now - stateAt > X.DUMMY_LUNGE_TIME or fromHome > X.DUMMY_ZONE * 2 then
				if dashedEarly then
					streak = 0
					RoundHud.say("TOO EARLY!", "Wait for the gold star, then dash", PlasticUi.GOLD, 1.6, true)
				end
				goBack()
			elseif reachedAt == math.huge and gap > 1e-3 then
				local step = math.min(X.DUMMY_SPEED * dt, math.max(gap - 0.5, 0))
				stand(here + toMe.Unit * step, toMe)
			end
		elseif state == "stunned" then
			-- dazed and grey for a moment, like a dodged chaser
			glow.FillColor = GREY
			glow.OutlineColor = GREY
			glow.FillTransparency = 0.5
			if now - stateAt >= STUN_TIME then
				glow.FillColor = RED
				glow.OutlineColor = RED
				goBack()
			end
		elseif state == "back" then
			glow.FillTransparency = 1
			glow.OutlineTransparency = 1
			local share = math.clamp((now - stateAt) / BACK_TIME, 0, 1)
			local eased = share * share * (3 - 2 * share)
			dummy:PivotTo(backFrom:Lerp(home, eased))
			if share >= 1 then
				go("rest")
			end
		end
	end)
end

function PracticeDummy.start()
	task.spawn(function()
		local folder = Workspace:WaitForChild(ProgressRules.EXTRAS, 120)
		local dummy = if folder then folder:WaitForChild(ProgressRules.DUMMY, 120) else nil
		if dummy and dummy:IsA("Model") then
			local ok, problem = pcall(run, dummy)
			if not ok then
				warn(`[Tag Rivals] the practice dummy didn't start: {problem}`)
			end
		end
	end)
end

return PracticeDummy
