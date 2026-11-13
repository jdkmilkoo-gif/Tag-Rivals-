--!strict
-- The bounty's call-outs (owner 2026-11-13: "Add a Bounty system"). Each round with enough players one runner is
-- WANTED (the server's Bounty picks; name tags draw the gold plate over their head). This shouts its moments in the
-- round's call-outs:
--   * at GO!: "YOU'RE WANTED!" to the wanted runner, "WANTED: NAME" to everyone else (it's picked in the dark of the
--     fade, so it's said once the screen is back);
--   * each shrink it grows: said to the wanted runner and to the chasers hunting them;
--   * its end: the chaser who tags them takes it, a fall loses it. (Keeping it by surviving shows on your round's
--     payout, PayoutCard.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoveRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MoveRules"))
local PlasticUi = require(script.Parent.PlasticUi)
local RoundHud = require(script.Parent.RoundHud)
local UiKit = require(script.Parent.UiKit)

local BountyHud = {}

local player = Players.LocalPlayer

local function upper(value: any): string
	return string.upper(if type(value) == "string" then value else "?")
end

local function coins(value: any): number
	return if type(value) == "number" then value else 0
end

function BountyHud.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Round") :: RemoteEvent
	local waiting: any = nil -- this round's bounty, until GO!
	remote.OnClientEvent:Connect(function(kind: unknown, info: any)
		if kind == "go" then
			local bounty = waiting
			waiting = nil
			if type(bounty) == "table" then
				-- just after GO! has had its moment
				task.delay(0.9, function()
					if bounty.who == player then
						local sub = `Survive and its {coins(bounty.amount)} coins are yours`
						RoundHud.say("YOU'RE WANTED!", sub, PlasticUi.GOLD, 2.4)
					else
						local sub = `Tag them for {coins(bounty.amount)} coins`
						RoundHud.say(`WANTED: {upper(bounty.name)}`, sub, PlasticUi.GOLD, 2, true)
					end
				end)
			end
			return
		end
		if type(info) ~= "table" then
			return
		end
		if kind == "bounty" then
			waiting = info
		elseif kind == "bountyUp" then
			if info.who == player then
				RoundHud.say(`YOUR BOUNTY: {coins(info.amount)}`, nil, PlasticUi.GOLD, 1.1, true)
			elseif MoveRules.role(player:GetAttribute(MoveRules.ATTR_ROLE)) == "Chaser" then
				RoundHud.say(`{upper(info.name)}'S BOUNTY: {coins(info.amount)}`, nil, PlasticUi.GOLD, 1.1, true)
			end
		elseif kind == "bountyEnd" then
			if info.kind == "tagged" then
				if info.by == player then
					RoundHud.say("BOUNTY CLAIMED!", `+{coins(info.amount)} coins`, PlasticUi.GOLD, 2)
				elseif info.who == player then
					RoundHud.say("BOUNTY LOST", `{tostring(info.byName)} took your {coins(info.amount)} coins`, UiKit.RED, 1.8, true)
				else
					RoundHud.say(`{upper(info.byName)} TOOK THE BOUNTY`, nil, PlasticUi.GOLD, 1.4, true)
				end
			elseif info.kind == "lost" then
				if info.who == player then
					RoundHud.say("BOUNTY LOST", nil, UiKit.RED, 1.6, true)
				else
					RoundHud.say(`{upper(info.name)}'S BOUNTY IS GONE`, nil, PlasticUi.GOLD, 1.4, true)
				end
			end
		end
	end)
end

return BountyHud
