--!strict
-- The Progress remote from a screen's side (ProgressRules.REMOTE; the server's Progress makes it when it starts). The
-- screens that show coins, levels, quests and codes listen here (ProgressLink.on) and ask through it
-- (ProgressLink.send), so each of them doesn't have to wait for the remote itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressRules"))

local ProgressLink = {}

type Handler = (...any) -> ()

local remote: RemoteEvent? = nil
local handlers: { [string]: { Handler } } = {}
local queued: { { any } } = {} -- asked before the remote was there
local missed: { [string]: { { any } } } = {} -- heard before any screen was listening for that kind
local started = false

local MISSED_MAX = 12 -- of each kind

-- Hears one kind of word from the server ("coins", "level", "quests", "code", "streak", "questDone"). Words that came
-- before the first screen listened for their kind are kept and said a moment later, to every screen listening by then.
function ProgressLink.on(kind: string, handler: Handler)
	local list = handlers[kind]
	if not list then
		list = {}
		handlers[kind] = list
		task.defer(function()
			local early = missed[kind]
			missed[kind] = nil
			if early then
				for _, each in early do
					for _, hears in handlers[kind] do
						task.spawn(hears, table.unpack(each, 1, (each :: any).n))
					end
				end
			end
		end)
	end
	table.insert(list, handler)
end

-- Asks the server for something ("quests", "claim", "reroll", "code", "hint"). The server checks everything.
function ProgressLink.send(kind: string, ...: any)
	local r = remote
	if r then
		r:FireServer(kind, ...)
	elseif #queued < 20 then
		table.insert(queued, table.pack(kind, ...))
	end
end

function ProgressLink.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(ProgressRules.REMOTE, 60)
		if not found or not found:IsA("RemoteEvent") then
			warn("[Tag Rivals] no Progress remote: coins, quests and codes won't show")
			return
		end
		remote = found
		found.OnClientEvent:Connect(function(kind: unknown, ...: any)
			if type(kind) ~= "string" then
				return
			end
			local list = handlers[kind]
			if not list then
				local early = missed[kind]
				if not early then
					early = {}
					missed[kind] = early
				end
				if #early < MISSED_MAX then
					table.insert(early, table.pack(...))
				end
				return
			end
			for _, handler in list do
				task.spawn(handler, ...)
			end
		end)
		for _, each in queued do
			found:FireServer(table.unpack(each, 1, (each :: any).n))
		end
		table.clear(queued)
	end)
end

return ProgressLink
