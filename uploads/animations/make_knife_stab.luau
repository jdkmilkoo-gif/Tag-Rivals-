-- Builds TagRivals_KnifeStab, the chaser's click-stab (owner 2026-11-09: "you can click to stab too btw, but only
-- pc"), made by Claude from the knife hold's pose: the arm pulls back a little (0.1 s), thrusts forward with the right
-- shoulder twisting in (0.19 s, when Bloomblade's stab hits), holds, and eases back to the hold (0.55 s). Only the
-- torso and the right arm move. Run in Studio (command bar) to put it in ServerStorage.Animations.

local function rad(x)
	return math.rad(x)
end

local function arm(px, py, pz, rx, ry, rz)
	return CFrame.new(px, py, pz) * CFrame.fromEulerAnglesXYZ(rad(rx), rad(ry), rad(rz))
end

local function torso(forward, twist)
	-- R6 root joint: its Y points backward, its Z up
	return CFrame.new(0, -forward, 0) * CFrame.Angles(0, 0, rad(twist))
end

local keys = {
	{ t = 0.00, arm = arm(0.42, -0.42, -0.26, -8.7, 4.1, 90.7), torso = torso(0, 0), style = Enum.PoseEasingStyle.Cubic },
	{ t = 0.10, arm = arm(-0.05, -0.36, -0.15, -8, 12, 72), torso = torso(-0.05, -10), style = Enum.PoseEasingStyle.Cubic },
	{ t = 0.19, arm = arm(1.1, -0.46, -0.5, -8, -8, 93), torso = torso(0.25, 20), style = Enum.PoseEasingStyle.Linear },
	{ t = 0.30, arm = arm(0.98, -0.45, -0.46, -8, -6, 92), torso = torso(0.2, 16), style = Enum.PoseEasingStyle.Cubic },
	{ t = 0.55, arm = arm(0.42, -0.42, -0.26, -8.7, 4.1, 90.7), torso = torso(0, 0), style = Enum.PoseEasingStyle.Linear },
}

local sequence = Instance.new("KeyframeSequence")
sequence.Name = "TagRivals_KnifeStab"
sequence.Loop = false
sequence.Priority = Enum.AnimationPriority.Action2
sequence:SetAttribute("Credit", "Made for Tag Rivals by Claude (2026-11-09) from TheNuggettier's knife hold")
for _, key in keys do
	local frame = Instance.new("Keyframe")
	frame.Time = key.t
	local root = Instance.new("Pose")
	root.Name = "HumanoidRootPart"
	root.Weight = 0
	root.Parent = frame
	local t = Instance.new("Pose")
	t.Name = "Torso"
	t.CFrame = key.torso
	t.EasingStyle = key.style
	t.EasingDirection = Enum.PoseEasingDirection.Out
	t.Parent = root
	local a = Instance.new("Pose")
	a.Name = "Right Arm"
	a.CFrame = key.arm
	a.EasingStyle = key.style
	a.EasingDirection = Enum.PoseEasingDirection.Out
	a.Parent = t
	frame.Parent = sequence
end
return sequence
