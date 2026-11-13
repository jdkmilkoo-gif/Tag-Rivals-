--!strict
-- A new player's first-minute hints (launch checklist: teach the game in the first minute; Config.Hints). Each shows
-- once, ever (the server remembers on your save):
--   * "SPACE = DASH" (on a phone: "DASH BUTTON = DASH") as your first match starts;
--   * "RED = CHASERS. RUN!" right after it, if you start as a runner;
--   * "DASH NOW!" under the gold star the first few times a perfect dodge's window opens.
-- The first two are a chunky tag that pops in above the dash bars, bobs, and fades.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local MoveRules = require(ReplicatedStorage.Shared.MoveRules)
local ProgressRules = require(ReplicatedStorage.Shared.ProgressRules)
local RoundRules = require(ReplicatedStorage.Shared.RoundRules)
local HudLayout = require(script.Parent.HudLayout)
local PerfectDodge = require(script.Parent.PerfectDodge)
local PlasticUi = require(script.Parent.PlasticUi)
local ProgressLink = require(script.Parent.ProgressLink)

local H = Config.Hints

local Hints = {}

local player = Players.LocalPlayer

local WIDTH, TALL = 340, 58
local POP_TIME = 0.3
local FADE = 0.3
local DODGE_SHOW = 0.7 -- s "DASH NOW!" stays under the star

type Card = { words: string, color: Color3 }

function Hints.start()
	local gui = PlasticUi.screen("TagRivalsHints", 6)
	local holder = Instance.new("CanvasGroup")
	holder.Name = "Hint"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(WIDTH, TALL + 8)
	holder.Visible = false
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local tag = PlasticUi.block({ name = "Tag", width = WIDTH, height = TALL, color = PlasticUi.PANEL, parent = holder })
	local words = PlasticUi.text({ name = "Words", size = 26, parent = tag.face, zIndex = 4 })
	words.root.Size = UDim2.fromScale(1, 1)
	gui.Parent = player:WaitForChild("PlayerGui")

	local queue: { Card } = {}
	local shownAt = -math.huge
	local showing = false

	local function add(text: string, color: Color3)
		table.insert(queue, { words = text, color = color })
	end

	-- as your first matches start
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: unknown)
		if kind ~= "go" or player:GetAttribute(RoundRules.ATTR_IN_ROUND) ~= true then
			return
		end
		if player:GetAttribute(ProgressRules.ATTR_LOADED) ~= true then
			return
		end
		if player:GetAttribute(ProgressRules.ATTR_HINT_DASH) ~= true then
			local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
			add(if touch then "DASH BUTTON = DASH" else "SPACE = DASH", PlasticUi.PANEL)
			ProgressLink.send("hint", "dash")
		end
		local runner = MoveRules.role(player:GetAttribute(MoveRules.ATTR_ROLE)) ~= "Chaser"
		if runner and player:GetAttribute(ProgressRules.ATTR_HINT_CHASER) ~= true then
			add("RED = CHASERS. RUN!", Color3.fromHex("FF2B4A"))
			ProgressLink.send("hint", "chaser")
		end
	end)

	-- "DASH NOW!" under the gold star, the first few times its window opens
	local dodgeGui = Instance.new("BillboardGui")
	dodgeGui.Name = "TagRivalsDashNow"
	dodgeGui.Size = UDim2.fromOffset(220, 44)
	dodgeGui.StudsOffset = Vector3.new(0, 4.4, 0)
	dodgeGui.AlwaysOnTop = true
	dodgeGui.LightInfluence = 0
	dodgeGui.ResetOnSpawn = false
	dodgeGui.Enabled = false
	local dodgeWords = PlasticUi.text({ name = "Words", size = 26, parent = dodgeGui, zIndex = 2, color = PlasticUi.GOLD })
	dodgeWords.root.Size = UDim2.fromScale(1, 1)
	dodgeWords:set("DASH NOW!")
	local dodgeScale = Instance.new("UIScale")
	dodgeScale.Parent = dodgeWords.root
	dodgeGui.Parent = player:WaitForChild("PlayerGui")
	local dodgeAt = -math.huge
	local dodgeShown = 0 -- times this visit (the save's count comes a moment late)
	PerfectDodge.onWindow(function()
		local had = player:GetAttribute(ProgressRules.ATTR_HINT_DODGE)
		local times = math.max(if type(had) == "number" then had else 0, dodgeShown)
		if times >= H.DODGE_TIMES or player:GetAttribute(ProgressRules.ATTR_LOADED) ~= true then
			return
		end
		dodgeShown = times + 1
		dodgeAt = os.clock()
		ProgressLink.send("hint", "dodge")
	end)

	RunService.PreRender:Connect(function()
		local now = os.clock()
		-- DASH NOW!
		local dodgeAge = now - dodgeAt
		local head = player.Character and player.Character:FindFirstChild("Head")
		if dodgeAge >= 0 and dodgeAge < DODGE_SHOW and head then
			dodgeGui.Adornee = head :: any
			dodgeGui.Enabled = true
			dodgeScale.Scale = 1 + 0.15 * math.sin(now * 28)
			dodgeWords:setFade(math.clamp((dodgeAge - (DODGE_SHOW - 0.2)) / 0.2, 0, 1))
		elseif dodgeGui.Enabled then
			dodgeGui.Enabled = false
		end

		-- the tags, one after the other
		if not showing then
			local nextCard = table.remove(queue, 1)
			if not nextCard then
				return
			end
			showing = true
			shownAt = now
			words:set(nextCard.words)
			tag:setColor(nextCard.color)
			holder.Visible = true
		end
		local age = now - shownAt
		if age >= H.SHOW + FADE then
			showing = false
			holder.Visible = false
			return
		end
		holder.GroupTransparency = math.clamp((age - H.SHOW) / FADE, 0, 1)
		local size = HudLayout.popScale()
		local t = math.clamp(age / POP_TIME, 0, 1) - 1
		scale.Scale = size * (0.5 + 0.5 * (1 + 2.70158 * t * t * t + 1.70158 * t * t))
		local bob = PlasticUi.motion(0.15)
		holder.Position = UDim2.new(0.5, 0, 0, HudLayout.floor() - 6 + bob)
		holder.Rotation = 1.5 * math.sin(now * 3)
	end)
end

return Hints
