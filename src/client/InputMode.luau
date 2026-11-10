--!strict
-- Which way the player is playing right now: "Touch" (phone or tablet), "Gamepad" or "Keyboard" (with a mouse).
-- Follows the last thing they used, so a touchscreen laptop switches as they switch. On touch, sprint is always on and
-- the Dash button shows (design notes, Movement). InputMode.setForced(true) pretends to be on touch (a Studio test key).

local UserInputService = game:GetService("UserInputService")

export type Mode = "Touch" | "Gamepad" | "Keyboard"

local InputMode = {}

local current: Mode = "Keyboard"
local forced = false
local listeners: { (mode: Mode) -> () } = {}

local GAMEPADS = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

local function classify(inputType: Enum.UserInputType): Mode?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif GAMEPADS[inputType] then
		return "Gamepad"
	elseif
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "Keyboard"
	end
	return nil -- mouse movement and the rest don't change the mode
end

local function announce()
	local mode = InputMode.get()
	for _, listener in listeners do
		task.spawn(listener, mode)
	end
end

function InputMode.get(): Mode
	return if forced then "Touch" else current
end

function InputMode.isTouch(): boolean
	return InputMode.get() == "Touch"
end

function InputMode.onChanged(listener: (mode: Mode) -> ())
	table.insert(listeners, listener)
end

function InputMode.setForced(on: boolean)
	if forced ~= on then
		forced = on
		announce()
	end
end

function InputMode.isForced(): boolean
	return forced
end

function InputMode.start()
	current = classify(UserInputService:GetLastInputType())
		or (if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard")
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local mode = classify(inputType)
		if mode and mode ~= current then
			current = mode
			announce()
		end
	end)
end

return InputMode
