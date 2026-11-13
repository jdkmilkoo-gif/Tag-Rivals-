--!strict
-- Every number for Tag Rivals in one place. Speeds are studs per second, times are seconds.
-- Numbers come from the owner's design notes (2026-11-09) unless marked "Claude's pick": those are starting points to
-- tune in playtests.

local Config = {}

Config.GameName = "Tag Rivals"

-- Walking, sprinting and the speed-ups (design notes, Movement).
Config.Move = table.freeze({
	-- Top speeds by role: walk / sprint (owner). Chasers are faster early; the last 2-3 runners beat them.
	-- Raised overall (owner 2026-11-09: "increase the overall speed from 22 to 25"): every speed times 25/22, so a
	-- runner sprints at 25 and the roles keep their gaps (were 18/22, 20/25, 24/30).
	SPEEDS = table.freeze({
		Runner = table.freeze({ walk = 20.5, sprint = 25 }),
		-- owner 2026-11-09: "slightly decrease the speed increase for chasers" (22.7 / 28.4 became 22 / 27.5), then
		-- "buff the overall speed of the taggers a little bit" (+1 each, Claude's pick): a new chaser sprints 3.5 faster
		-- than a runner
		Chaser = table.freeze({ walk = 23, sprint = 28.5 }),
		LastRunner = table.freeze({ walk = 27.3, sprint = 34.1 }),
	}),
	START_SHARE = 0.6, -- you start moving at this share of your walk speed, then speed up (Claude's pick)
	ACCEL = 32, -- studs/s gained every second while speeding up, at a role's base speeds (Claude's pick)
	DECEL = 48, -- studs/s lost every second slowing to a lower top speed: letting go of sprint, after a dash (Claude's pick)
	-- Every tag raises everyone's walk and sprint by this, and acceleration rises with it (owner: "a little", tune in
	-- playtests).
	TAG_SPEED_BONUS = 0.5,
	-- Chasers get less from each tag than the last (owner 2026-11-09: "Decrease the rate of speed increase as the more
	-- players get tagged for chasers"): the nth tag gives chasers TAG_SPEED_BONUS x CHASER_TAG_DECAY^(n-1), so their
	-- speed-ups shrink (0.5, 0.4, 0.32, ...) and never add up to more than 2.5. Runners keep the full 0.5 a tag.
	CHASER_TAG_DECAY = 0.8,
	STAR_SPEED = 0.2, -- top speed each star picked up this round adds (owner)
	STAR_SPEED_MAX = 10, -- the most stars can add: 50 stars (owner)
})

-- Space to dash (design notes, Movement). Never a jump.
Config.Dash = table.freeze({
	MAX_CHARGES = 2, -- owner
	RECHARGE = 1.5, -- s for one charge to refill, one after another (owner 2026-11-09: "make each charge 1.5 seconds")
	MIN_GAP = 0.2, -- s between two dashes at the least, so one double tap doesn't spend both (Claude's pick, as Huss Zero)
	DISTANCE = 8, -- studs a dash covers (owner 2026-11-09: "reduce the dash to 8 studs"; was 13, 12.5, then 10)
	TIME = 0.15, -- s the burst lasts (owner: the chaser's tag reach grows for this 0.15 s burst)
	EXIT_EXTRA = 6, -- studs/s over your running speed you come out of a dash with, easing back down (Claude's pick)
	SEND_SLACK = 0.25, -- s of extra refill the server allows a dash (messages bunch on the network), as Huss Zero
	EMPTY_FLASH = 0.35, -- s the meter flashes red and shakes when you press with no charge left, as Huss Zero
	-- Neon afterimages (owner): copies of your body dropped along the dash, fading out.
	GHOSTS = 5, -- copies along one dash (Claude's pick)
	GHOST_FADE = 0.4, -- s each copy takes to fade away (Claude's pick)
	GHOST_START = 0.3, -- how see-through a copy starts (0 solid, 1 invisible) (Claude's pick)
	RUNNER_COLOR = "2EE6FF", -- runners' dash colour until a trail is equipped: neon cyan (Claude's pick)
	CHASER_COLOR = "FF2B4A", -- chasers' dash: red neon (owner)
})

-- The arena: one flat square, no walls you can see, an invisible wall at its edges (design notes, Map size).
Config.Arena = table.freeze({
	-- studs a side, every round, whatever the player count (owner 2026-11-09: "lets keep the map at a permanent 250 x
	-- 250 square with shrinks"; it was a circle of 100 + 15 per player, then 120 + 18)
	SIZE = 250,
	CENTER = Vector3.new(0, 1, 0), -- the middle of the floor's top (1 stud above the template baseplate)
	THICKNESS = 1.2, -- studs
	EDGE_MARGIN = 1.5, -- studs inside the edge where the invisible wall stops your body
	SERVER_GRACE = 12, -- studs past that the server lets a body be before it puts it back (it sees bodies a moment
	-- late)
	WALL_HEIGHT = 12, -- the invisible wall only holds bodies within this many studs of the floor (the lobby is above)
	RIM = 2.5, -- studs the glowing rim sticks out past the floor
	-- The floor looks like Roblox's baseplate, cut into a circle (owner, 2026-11-09): its grey, its plastic and its grid.
	FLOOR_COLOR = "5B5B5B",
	FLOOR_MATERIAL = Enum.Material.Plastic,
	FLOOR_TEXTURE = "rbxassetid://6372755229", -- the baseplate's grid
	FLOOR_TILE = 8, -- studs per grid tile, as the baseplate
	FLOOR_TEXTURE_TRANSPARENCY = 0.8, -- as the baseplate
	-- The place's square baseplate and spawn pad are taken away when the game runs (the circle is the whole map); they
	-- stay in the place for building in Studio.
	REMOVE_AT_START = table.freeze({ "Baseplate", "SpawnLocation" }),
	RIM_COLOR = "2EE6FF",
	FALL_LIMIT = 40, -- studs below the floor a body counts as fallen and gets a fresh one
})

Config.Respawn = table.freeze({
	TIME = 2, -- s after a body dies until the next one
})

-- Your body's animations: idle, walk and sprint blend smoothly into each other (owner).
Config.Anim = table.freeze({
	IDLE = "rbxassetid://180435571", -- Roblox's own R6 idle
	ROBLOX_WALK = "rbxassetid://180426354", -- Roblox's own R6 walk: the stand-in when nothing else is there
	-- The animations in use (owner 2026-11-09: "keep the current walk and run. but name them ... and save the other
	-- cycles for next time"). They live as KeyframeSequences in ServerStorage.Animations (STUDIO_FOLDER):
	--   TagRivals_Run    the sprint: wifonn3's "[🏃] Best Run Animations R6" (the pack's first run)
	--   TagRivals_Walk   the walk: by roblox_boi8913, from wifonn3's "[🚶] Best Walk Animation R6"
	--   TagRivals_Idle   standing still: from TheNuggettier's "Dash + idle animation R6"
	--   TagRivals_Dash1, TagRivals_Dash2, TagRivals_Dash3   the forward dashes, all used (owner: "use all of them"),
	--                    each dash a different one from the last; TheNuggettier's pack
	--   TagRivals_DashLeft, TagRivals_DashRight   the sidesteps; TheNuggettier's pack
	-- The spares (other runs and walks, knife slashes, dances) wait in ServerStorage.Animations_SavedForLater.
	-- Put the uploaded ids below (numbers only work too, e.g. 123456789). Until then Studio play-tests play the
	-- KeyframeSequences straight from ServerStorage; a live game needs the uploaded ids.
	-- Uploaded to ROBLOXIAN CHAMPIONS UNITED on 2026-11-09 (owner: "so can u publish them all?").
	SprintAnimationId = 92963569528431, -- TagRivals_Run
	WalkAnimationId = 132648325469907, -- TagRivals_Walk
	IdleAnimationId = 111046364098979, -- TagRivals_Idle
	DashAnimationIds = table.freeze({ 98007570829570, 81415439771249, 96266380699988 }), -- TagRivals_Dash1, 2, 3
	DashLeftAnimationId = 109464562762874, -- TagRivals_DashLeft
	DashRightAnimationId = 85394736428002, -- TagRivals_DashRight
	STUDIO_FOLDER = "Animations",
	STUDIO_RUN = "TagRivals_Run",
	STUDIO_WALK = "TagRivals_Walk",
	STUDIO_IDLE = "TagRivals_Idle",
	STUDIO_DASHES = table.freeze({ "TagRivals_Dash1", "TagRivals_Dash2", "TagRivals_Dash3" }),
	STUDIO_DASH_LEFT = "TagRivals_DashLeft",
	STUDIO_DASH_RIGHT = "TagRivals_DashRight",
	-- The chaser's knife (TheNuggettier's "BEST R6 animations (dash animations)"): drawing it, holding it (the right arm
	-- only) and two slashes taking turns. Uploaded to ROBLOXIAN CHAMPIONS UNITED on 2026-11-09.
	KnifeEquipAnimationId = 102539697774925, -- TagRivals_KnifeEquip
	KnifeHoldAnimationId = 121243226049767, -- TagRivals_KnifeHold
	KnifeSlashAnimationIds = table.freeze({ 85882993171030, 100170975457482 }), -- TagRivals_KnifeSlash1, 2
	KnifeStabAnimationId = 88520140084598, -- TagRivals_KnifeStab: made for Tag Rivals from the knife hold (2026-11-09)
	STUDIO_KNIFE_EQUIP = "TagRivals_KnifeEquip",
	STUDIO_KNIFE_HOLD = "TagRivals_KnifeHold",
	STUDIO_KNIFE_SLASHES = table.freeze({ "TagRivals_KnifeSlash1", "TagRivals_KnifeSlash2" }),
	STUDIO_KNIFE_STAB = "TagRivals_KnifeStab",
	-- A dash animation is squeezed into this many seconds (the dash itself is 0.15 s; the rest is coming out of it),
	-- fading in and out over these (Claude's picks).
	DASH_ANIM_TIME = 0.42,
	DASH_FADE_IN = 0.04,
	DASH_FADE_OUT = 0.15,
	-- A dash more than this many degrees off the way your body faces is a sidestep: the left or right dash plays and
	-- your body keeps facing the same way until it ends. Further round than SIDE_MAX it's a turn: the forward dash
	-- plays and your body turns into it (Claude's picks).
	SIDE_MIN = 50,
	SIDE_MAX = 130,
	SIDESTEP_HOLD = 0.3, -- s your body keeps its facing after a sidestep starts
	-- studs/s each cycle's feet match at normal speed; above it the cycle plays faster (Claude's picks, measured
	-- against Roblox's own walk: 14.5). The sprint was made to play faster (owner 2026-11-09: "play the sprinting
	-- animation faster"): 1.5 times at a runner's sprint, 2 times at a last runner's.
	WALK_REF = 12.8,
	RUN_REF = 15,
	ROBLOX_WALK_REF = 14.5,
	-- Where in each cycle (share of it) a foot lands, for the uploaded walk and sprint (Studio works these out from
	-- the KeyframeSequences): a right-leg swing's two ends.
	WALK_STEPS = table.freeze({ 0.25, 0.75 }),
	RUN_STEPS = table.freeze({ 0.231, 0.795 }),
	MOVING = 0.6, -- studs/s below which you count as standing
	BLEND = 10, -- how quickly one animation blends into the next (per s; bigger is quicker)
	MAX_RATE = 2.5, -- the fastest a cycle plays (times normal), so a dash doesn't spin the legs
})

-- The camera (design notes, Camera).
Config.Camera = table.freeze({
	FOV_STAND = 70, -- owner
	FOV_WALK = 77, -- Claude's pick
	FOV_SPRINT = 85, -- owner: about 84-86
	FOV_FAST_MAX = 90, -- the widest speed bonuses can take it (Claude's pick)
	FOV_SPRING = 6, -- how quickly the view follows your speed (per s)
	DASH_FOV = 18, -- degrees a dash adds at its peak, about 103 from a sprint (owner: 102-105)
	DASH_FOV_RISE = 0.04, -- s to the peak
	DASH_FOV_BACK = 0.4, -- s it eases back (Claude's pick)
	DASH_ROLL = 2.5, -- degrees the view tilts opposite a sideways dash (owner: 2-3)
	DASH_ROLL_BACK = 0.35, -- s the tilt takes to settle (Claude's pick)
	-- On every step the camera shakes a little (owner 2026-11-09: "on every step the camers sublty shakes"): a quick
	-- dip and a tiny roll toward the foot that landed, stronger the faster you go (Claude's picks).
	-- dialled down (owner 2026-11-09: "dial down the ccamera shake from the steps"; was 0.12 and 0.35)
	STEP_DIP = 0.05, -- studs the view dips at a sprint
	STEP_ROLL = 0.15, -- degrees it rolls at a sprint
	STEP_TIME = 0.16, -- s one step's shake lasts
	STEP_WALK_SHARE = 0.45, -- how strong a walking step is next to a sprinting one
	-- Steering with the camera in a round, Huss Valley style (CameraSteer; owner 2026-11-09: "the camera like a
	-- flashlight attached to your chest"); a free camera on the lobby. Claude's picks for the feel:
	SHOULDER_OFFSET = 1.75, -- studs right of your body the camera sits in a round (owner: "like the over the shoulder")
	SHOULDER_EASE = 8, -- how quickly it slides over as a round starts and back as it ends (per s)
	STEER_FOLLOW = 9, -- how quickly your running direction follows the camera (per s; ~0.1 s; owner: "some small elastic lag")
	BODY_FOLLOW = 10, -- how quickly your body turns after the camera (per s; ~0.1 s)
	SIDE_TWIST = 45, -- degrees your body turns toward where you run when running sideways (owner: not completely)
	BACK_TWIST = 20, -- degrees it twists on the back diagonals (S+A, S+D); straight back it faces forward
	-- Heads turn to where the camera looks (HeadLook; owner: "the players head to turn wehre ever the camera is facing")
	HEAD_YAW_MAX = 70, -- degrees either side of the body
	HEAD_PITCH_MAX = 35, -- degrees up and down
	HEAD_SEND_RATE = 10, -- times a second your head's turn is sent to everyone
	HEAD_EASE = 12, -- how quickly other heads ease to the newest turn (per s)
	-- The camera looks a little ahead of where you're running (design notes: about 3.5 studs; owner 2026-11-09, Huss
	-- Valley's "predictive directional lead offset"): full lead at your sprint speed, less when slower.
	-- Off since the owner's 2026-11-09 steering notes: "only the player turning the camera can affect the camera".
	LEAD = 0, -- studs (was 3.5)
	LEAD_SPRING = 3, -- how quickly the lead follows a change of direction (per s; smaller is smoother)
})

-- Huss Zero's UI style, copied (owner, 2026-11-09: "copy dis Ui Style from Huss Zero", with screenshots; this replaces
-- the round corners and Fredoka One of the first design notes): Montserrat Bold Italic words with a thick black outline
-- and a black drop under them, chunky square plastic (a lit face, a white shine over its top, a darker side under it, a
-- black outline and a soft shadow), moving halftone dots on the faces, bright blue and gold plastic, dark indigo plates
-- with diagonal stripes, all of it moving (owner: "make the Uis All animated", "and the texture also animated"). No
-- SPEED badge (owner: "dont take the Speed box"). Numbers from Huss Zero's Config.
Config.Ui = table.freeze({
	FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json",
	FONT_WEIGHT = "Bold", -- an Enum.FontWeight name
	FONT_STYLE = "Italic", -- an Enum.FontStyle name
	TEXT_OUTLINE = 0.08, -- the words' black outline, this share of their size thick
	TEXT_DROP = 0.1, -- the black drop under the words, this share of their size lower
	OUTLINE_COLOR = "000000",
	OUTLINE = 3, -- pixels of black outline round every panel (square corners, as Huss Zero)
	DEPTH = 6, -- pixels of darker side layer under a panel's face
	SHADOW_DROP = 4, -- pixels a panel's soft shadow sits under it
	SHADOW_SEE = 0.55, -- how see-through that shadow is
	FACE_LIGHT = 0.15, -- a face's top is its colour this much whiter (times its brightness)
	FACE_MID = 0.9, -- its middle that times this
	FACE_BOTTOM = 0.76, -- its foot that times this, so it reads round, like plastic
	SHINE_SEE = 0.7, -- how see-through the shine over a bright face's top is
	SHINE_DARK = 0.25, -- on the darkest face the shine is this share as strong
	-- Huss Zero's colours (its Config.Hud)
	PANEL_COLOR = "2B6BFF", -- bright blue plastic
	GOLD_COLOR = "FFD23A", -- sunny gold (Huss Zero's JUMP button and picked options)
	PLATE_COLOR = "241B55", -- the big menus' dark indigo plate
	DONE_COLOR = "4BE36A", -- the green DONE button
	STRIPE_LIGHT = 0.1, -- how much lighter the light stripes are
	STRIPE_SPEED = 18, -- pixels a second the stripes scroll (owner: "the texture also animated")
	-- Moving halftone dots (Huss Zero's Halftone): dots that swell and shrink in a wave rolling down and to the right,
	-- strongest at a face's foot and fading toward its top; black on bright faces, white on dark plates.
	DOT_SPACING = 7, -- pixels between dots at full size
	DOT_CELLS = 8, -- the wave repeats every this many dots
	DOT_MIN = 0.08, -- a dot's radius at the wave's low, share of the spacing
	DOT_MAX = 0.5, -- and at its high (neighbours touch)
	DOT_WAVE_TIME = 2.4, -- s for the wave to roll one repeat along, on average (each face its own uneven pace)
	DOT_FPS = 15, -- how often a second the dots move on
	DOT_DARK_FACE = 0.4, -- a face darker than this gets white dots
	DOT_BLACK_SEE = 0.8, -- black dots at their strongest
	DOT_WHITE_SEE = 0.86, -- white dots at their strongest
	DOT_FADE_TOP = 0.9, -- extra see-through at a face's top, fading to none at its foot
	DOT_MIN_PX = 12, -- faces smaller than this get no dots
	DOT_SHEET = "rbxassetid://132659549686960", -- the dot wave drawn as one picture (32 steps of an 8x8-dot tile; the
	-- Halftone draws faces from it, owner 2026-11-09: "a consistent 60 fps")
	BOB_PIXELS = 3, -- how far panels bob up and down
	BOB_HZ = 0.5, -- bobs per second
	TILT_MAX = 4, -- degrees panels tilt as the camera turns
	TILT_PER_TURN = 0.025, -- degrees of tilt per degree/s of camera turning
	TILT_SPRING = 6, -- how quickly the tilt follows the camera
	SCALE_SHORT_SIDE = 420, -- a screen whose short side is this many pixels draws the HUD at full size
	SCALE_MIN = 0.7,
	SCALE_MAX = 1.1,
	PRESS_SCALE = 0.94, -- a pressed button shrinks to this (Huss Zero)
	EMPTY_COLOR = "FF3B4A", -- the dash bars' outlines flash this when you press with no charge (Huss Zero)
	CALLOUT_HOLD = 1.3, -- s the SPEED UP! callout stays before fading
})

-- The round (design notes, Round flow): intermission on the glass lobby, a fade to black where the chaser is picked,
-- the match, then cleanup and the victory screen.
Config.Round = table.freeze({
	MIN_PLAYERS = 2, -- a round needs a chaser and a runner (Claude's pick)
	INTERMISSION = 30, -- s (owner 2026-11-13: "make the intermission after a round 30s"; was 8, and 15 before that)
	TELEPORT = 2, -- owner: the fade to black, the chaser picked in it, everyone spawned, frozen briefly
	FADE_IN = 0.35, -- s to go black (Claude's pick)
	FADE_OUT = 0.5, -- s to come back from black, ending as the match starts (Claude's pick)
	MATCH = 120, -- s (owner 2026-11-09: "change the game form 90 seconds to 2 minutes"; was 90)
	CLEANUP = 5, -- owner: no more tagging, the victory screen
	-- Phases go by players left (owner): phase 2 once a third of the starting runners are tagged, phase 3 at two
	-- thirds, Last Man Standing with 1 runner left. Bar colours (owner): slate grey early, amber with more infected,
	-- deep crimson for the last man (phase 3's orange is Claude's pick).
	PHASE_COLORS = table.freeze({ "7D8BA1", "FFB020", "FF6A2B", "C4122F" }),
	-- Runners get the last-runner speeds once this share of the starting runners (rounded down) are all that's left,
	-- never more than FAST_RUNNERS_MAX (owner: "when 2-3 runners remain they become faster than chasers"; how it
	-- scales for small rounds is Claude's pick: 3 to 5 runners at the start, only the last one; 9 or more, the last 3).
	FAST_RUNNERS_SHARE = 1 / 3,
	FAST_RUNNERS_MAX = 3,
	-- Starting speed by players in the round (owner: depends on the player count; formula is Claude's pick, tune in
	-- playtests): everyone's walk and sprint start this much higher for each player over START_SPEED_FROM.
	START_SPEED_PER_PLAYER = 0.15,
	START_SPEED_FROM = 4,
	START_SPEED_MAX = 3,
	-- Where runners spawn: spread around the circle at this share of its radius, a little jitter (Claude's pick).
	RUNNER_RING = 0.78,
	RUNNER_JITTER = 0.06,
})

-- The lobby (design notes, Lobby): a big glass ring floating right above the arena, with a see-through floor so
-- everyone waiting watches the round below. The leaderboards, flex pedestals and practice dummy on it are in
-- Config.Boards and Config.LobbyExtras; shop booths come with the shop.
Config.Lobby = table.freeze({
	HEIGHT = 70, -- studs above the circle's floor (Claude's pick)
	RADIUS = 48, -- studs (Claude's pick)
	THICKNESS = 0.6,
	GLASS_COLOR = "CDEFFF",
	GLASS_SEE = 0.55, -- how see-through the floor is
	RIM_COLOR = "2EE6FF",
	RIM = 1.5, -- studs the glowing rim sticks out past the glass
	WALL_HEIGHT = 10, -- the invisible wall round its edge
	WALL_SEGMENTS = 40,
	SPAWN_SHARE = 0.75, -- people appear within this share of its radius
})

-- The neon look from the owner's pictures (2026-11-10: "Add these" with three pictures, then "like the back ground
-- too"): the red "MAP SHRINKING IN" banner, the kill-feed rows, the chevron arrows and the purple sunset sky. Our own
-- pictures, made by uploads/ui/make_neon_ui.py and uploads/sky/make_sky.py and uploaded to the group.
Config.Neon = table.freeze({
	BANNER = "rbxassetid://112380824151645", -- the shrink warning's plate (9-slice, 1024 x 200)
	BANNER_SLICE = Rect.new(90, 50, 934, 150), -- its middle, which stretches
	CHEVRON_RED = "rbxassetid://119748941252235",
	CHEVRON_AMBER = "rbxassetid://95658832329521",
	CHEVRON_WHITE = "rbxassetid://79116454001833", -- for tinting
	ROW = "rbxassetid://98803709606243", -- a feed row's neon edge (9-slice, 256 x 96, white for tinting)
	ROW_SLICE = Rect.new(40, 40, 216, 56),
	BOLT = "rbxassetid://140431219613661",
	SHEEN = "rbxassetid://106782708218151", -- a soft white band that sweeps across the banner
	-- the sky (also set in default.project.json, Lighting > Sky)
	SKY = table.freeze({
		Bk = "rbxassetid://119357248920976",
		Dn = "rbxassetid://134976793660406",
		Ft = "rbxassetid://110125101021218",
		Lf = "rbxassetid://114557315319042",
		Rt = "rbxassetid://129545489916926",
		Up = "rbxassetid://88903185093172",
	}),
})

-- The square shrinking (design notes, Map size).
Config.Shrink = table.freeze({
	-- Owner 2026-11-09: "Decrease the strength of the shrinks. The map should shrink every 30 seconds. like 10%", and
	-- "get rid of the 25% shrink". So the square shrinks on a timer only (at 30 s and 60 s of a 90 s match); tags no
	-- longer shrink it (they took 6% each), and the 20% shrink 25 s in is gone.
	EVERY = 30, -- s between shrinks
	SHARE = 0.1, -- each one takes this share off the square's side (half of it off each edge)
	PER_TAG = 0, -- share each tag takes off (off)
	MIN_DIAMETER = 50, -- studs: never smaller (Claude's pick)
	-- Each shrink cuts the strip round the edge off (owner 2026-11-09: "make the game warn 3 seconds before the map
	-- shrinks. and whatever part of the map that shrinks that area should be red. and change the shrinking function as
	-- just like cutting off a that part of the map"). Drawn by ShrinkFx.
	WARN = 3, -- s the strip that's going glows red, with a countdown, before it's cut (owner)
	CUT_COLOR = "FF2B3A", -- the warning red (Claude's pick)
	-- Anyone still on the red when it's cut falls with it (owner 2026-11-10: "make the red let players fall and become
	-- tagger"; it used to sweep them onto what's left). A runner who falls becomes a chaser; a chaser who falls just
	-- comes back. Claude's picks:
	FALL_PUSH = 9, -- studs/s outward your body gets as the floor goes from under it
	FALL_CLEAR = 1.6, -- studs past the cut line your body is moved so it doesn't catch the edge
	FALL_DETECT = 4, -- studs under the floor's top a body counts as fallen
	FALL_BACK = 1.7, -- s after falling until you're back on the square (you watch yourself drop into the clouds)
	FALL_SPAWN_SHARE = 0.3, -- you come back somewhere within this share of the half-side round the middle
	AFTER_CUT_GRACE = 1, -- s after a cut the server doesn't pull anyone back onto the square (they're falling)
	PIECE = 25, -- studs: the cut strip breaks into pieces about this long (Claude's pick)
	FALL_TIME = 1.6, -- s the pieces take to tip over the edge, fall into the clouds and fade (Claude's pick)
	-- Camera shake (owner: a sharp snap, then a 0.8 s rumble that fades, stronger each shrink; start lighter than 0.35
	-- and work up to 1.2+ in playtests).
	SHAKE_FIRST = 0.25,
	SHAKE_STEP = 0.08,
	SHAKE_MAX = 1.2,
	RUMBLE_TIME = 0.8,
})

-- Tagging (design notes, Round flow): no button. A chaser who gets close enough slashes their knife automatically and
-- the runner is tagged. The chaser's screen claims the tag; the server checks it against where the runner was on the
-- chaser's screen (Chrono's history), then it counts.
Config.Tag = table.freeze({
	REACH = 5.2, -- studs between the two bodies' middles (owner)
	DASH_REACH = 7.5, -- during the chaser's 0.15 s dash burst (owner)
	DASH_GRACE = 0.08, -- s after the burst the dash reach still counts, for the network (Claude's pick)
	SLASH_GAP = 0.4, -- s between two automatic slashes (Claude's pick)
	-- A runner who's just been tagged stands still, and can't tag, for this long before chasing (owner 2026-11-09: "do
	-- the stun before tagging"), which slows the swarm's snowball.
	NEW_CHASER_STUN = 2,
	-- Click to stab (owner 2026-11-09: "you can click to stab too btw, but only pc"): a chaser on a computer can also
	-- left-click to stab straight ahead, reaching a little past the automatic slash (Claude's picks).
	STAB_REACH = 6.5, -- studs between the two bodies' middles
	STAB_CONE = 60, -- degrees either side of the way you face
	STAB_GAP = 0.6, -- s between two stabs
	TARGET_GAP = 0.6, -- s before the same runner is claimed again after a claim the server hasn't answered
	-- The server's checks (Claude's picks, as Huss Zero's hits): how far a claim may be off.
	REACH_SLACK = 1, -- studs over the reach the claimed gap may be
	SEEN_SLACK = 4, -- studs the runner may be from where the server's history says they were
	OWN_SLACK = 7, -- studs the chaser may be from where the server's history says they were
	SEEN_WINDOW = 0.15, -- s either side of the chaser's view moment the runner's history is searched
	REWIND_BASE = 0.35, -- s of history searched, plus the chaser's ping
	REWIND_MAX = 1, -- s, never more
	HIT_WAIT = 0.4, -- s a claim waits for the server's history to catch up before it's a miss
	-- Tag effects (owner: the runner glows white and red, the chaser's screen edges flash crimson)
	OUTLINE_TIME = 1.2, -- s the tagged runner's white-and-red glow takes to settle into the red chaser outline
	OUTLINE_COLOR = "FF1F3D", -- every tagger's outline (owner 2026-11-09: "for every tagger add a red outline")
	FLASH_TIME = 0.45, -- s the crimson edge flash takes to fade
	FOV_POP = 6, -- degrees the view pops out on a tag (owner: "quick FOV pop")
	TAG_SHAKE = 0.45, -- the shake on your screen for every tag you make (owner 2026-11-09: "a screen shake for every tag
	-- from the player"; same snap-then-rumble as a shrink's)
	FEED_SHOW = 6, -- s a tag stays in the tag feed
	FEED_MAX = 5, -- tags shown at once
})

-- The perfect dodge (owner 2026-11-09: "Introduce a prefect dodge, with like a small gold animated star above when its
-- a current window for a perfect dodge and the window should be pretty small for a perfect dodge, then slows the tagger
-- and make his screen monochrome for a little bit while hes stunned"). The window is open while a chaser is just
-- outside reach of you and closing in (or dashing at you): dash in it and the chaser is stunned. Claude's picks:
Config.Dodge = table.freeze({
	WINDOW = 6.7, -- studs beyond the chaser's reach (5.2, or 7.5 in their dash) the window covers: at a sprinting
	-- chaser's closing speed that's about a quarter of a second (owner 2026-11-09: "the window a little small", then
	-- "increase the window again, cuz like, i cant get it done bro", then "make the perfect dodge 6.7 studs"; was 2.5,
	-- 4, then 6.5)
	DASH_DISTANCE = 9.5, -- studs a dash covers when it's a perfect dodge (a normal dash is 8; owner: "9.5 studs dodge
	-- distance if it is a perfect dodge")
	MIN_CLOSING = 3, -- studs/s the chaser must be closing in at (a chaser just standing near you doesn't count; was 6)
	GRACE = 0.15, -- s after the window shuts a dash still counts (a press a little late; was 0.06, then 0.1)
	SLACK = 4, -- studs the server allows on top (it sees bodies a moment late)
	STUN = 1.2, -- s the dodged chaser is stunned: slowed, can't dash, can't tag, and their screen goes grey
	SLOW = 0.45, -- share of their speed they keep while stunned
	COOLDOWN = 3, -- s before the same runner can perfect-dodge again
	IMMUNE = 1.5, -- s after a stun ends before that chaser can be perfect-dodged again
	GREY_FADE = 0.35, -- s the grey takes to fade back to colour at the end
	-- The runner who perfect-dodges can't be tagged for this long, and everyone sees "PERFECT DODGE!" over their head
	-- (owner 2026-11-09: "when perfect dodging the player is invincible, and everyone can see on the runners head
	-- 'perfect Dodge!'")
	INVINCIBLE = 1.3, -- s (owner: "slightly increae the invincilibity duration"; was 1)
	LABEL_TIME = 1.3, -- s the words float over the head
	-- After a perfect dodge the runner gets a burst of speed (owner 2026-11-09: "speed boost after perfect doging")
	BOOST = 1.3, -- times their speed
	BOOST_TIME = 1.5, -- s
	-- The runner's camera on a perfect dodge (owner: "give me better camera shake when perfect dodge"): a hard snap and
	-- rumble, a wide FOV kick and gold screen edges
	SHAKE = 0.9,
	FOV_KICK = 14,
})

-- The knife (owner 2026-11-09): every player wears their knife diagonally across their back; a chaser holds it in
-- their hand from the moment they become one, and slashes it automatically.
Config.Knife = table.freeze({
	-- Dev-only switch (owner: Bloomblade is the test knife; it stays an Epic, and at launch chasers get a Common knife):
	-- on, everyone wears Bloomblade; off, the default knife (a plain placeholder until the shop's Common knives exist).
	USE_TEST_KNIFE = true,
	TEST_KNIFE = "Bloomblade", -- a Model in ServerStorage.Knives (the cosmetics thread's export)
	DEFAULT_KNIFE = "Common", -- not made yet: the plain placeholder knife stands in
	-- The knife's own frame: the blade along +X, the spine up (+Y), as the export. Its hand grip and its length:
	GRIP = Vector3.new(-0.88, 0, 0),
	MIDDLE = Vector3.new(0.41, 0, 0),
	TRAIL_START = Vector3.new(0.2, -0.12, 0),
	TRAIL_END = Vector3.new(2.6, -0.12, 0),
	-- On the back: across it from the right shoulder (handle) down to the left hip (tip), flat on it (Claude's pick).
	BACK_OFFSET = 0.68, -- studs behind the torso's middle
	BACK_ANGLE = -125, -- degrees round the torso's forward axis
	-- In the hand, held forward out of the fist (the hold animation raises the arm).
	HAND_DROP = 1, -- studs below the arm's middle (the fist)
	HAND_TILT = 30, -- degrees the blade tips up from straight ahead, so it shows over your shoulder (Claude's pick)
	-- Animations (in ServerStorage.Animations; TheNuggettier's "BEST R6 animations (dash animations)")
	SLASH_SPEED = 1.35, -- the slash plays this much faster than made (its swing lands about 0.1 s in)
	SLASH_TIME = 0.55, -- s the slash plays before fading back to the hold
	TRAIL_ON = 0.02, -- s into the slash the blade's trail turns on
	TRAIL_OFF = 0.35, -- and off
	STAB_SPEED = 1, -- the stab plays at this speed (it thrusts 0.19 s in, as Bloomblade's stab)
	STAB_TRAIL_ON = 0.1, -- s into the stab the trail turns on (the thrust)
	STAB_TRAIL_OFF = 0.3,
	SLASH_COLOR_A = "FF8AE6", -- the trail and hit burst (Bloomblade's "Sakura Bloom" colours)
	SLASH_COLOR_B = "C45CFF",
	SLASH_COLOR_C = "7A2AFF",
	-- The knife's own effects (KnifeFx; each knife model carries them on its FX_Blade part)
	IDLE_RANGE = 120, -- studs from the camera within which knives run their particles (Claude's pick; beyond: trail only)
	LIGHT_COLOR = "C86AFF", -- the held blade's light (Bloomblade's idle)
	LIGHT_RANGE = 9,
	LIGHT_BRIGHTNESS = 2, -- it pulses round this...
	LIGHT_PULSE = 0.8, -- ...by this much either way...
	LIGHT_BEAT = 2.6, -- ...on this beat (s)
})

-- Coins on the arena (design notes, Coins and economy: the "Stars"; owner 2026-11-09: "now implement coins as a pickup
-- in the rounds" with the coin from the 'Tag Rivals Coin' preview). A gold coin with a 4-point star floats and turns;
-- touching it gives +2 coins and +0.2 top speed (Config.Move.STAR_SPEED, at most +10). They come in over the match
-- (owner: "should spawn over time"), mostly near the dangerous middle, never on a strip that's about to be cut off.
-- The coins and every effect are drawn on each screen only (CoinFx), so the server only keeps a list of spots (owner:
-- "make sure it doesnt lag the game at all").
Config.Coins = table.freeze({
	VALUE = 2, -- coins each (owner)
	MODEL_ID = 80640452303536, -- the coin's 3D model (made from the preview, uploaded to the group; a copy sits in
	-- ServerStorage.Pickups.Coin)
	-- When they come (Claude's picks): the first one this long after GO!, then one more every EVERY s while there's room.
	-- Made to come about twice as often, with more on the map at once (owner 2026-11-13: "make coins appear more
	-- often"; was FIRST 2, EVERY 1.5, ALIVE 6 + 0.5 a player up to 18, SPACING 10).
	FIRST = 1,
	EVERY = 0.75,
	ALIVE_BASE = 10, -- coins on the map at once: this many,
	ALIVE_PER_PLAYER = 0.8, -- plus this many for each player in the round,
	ALIVE_MAX = 30, -- never more than this
	-- Where (owner: "most of them spawn near the dangerous centre so runners can't just loop the edge"; Claude's picks)
	CENTER_SHARE = 0.65, -- this share land near the middle,
	CENTER_ZONE = 0.4, -- within this share of the way out to the edge
	EDGE_GAP = 6, -- studs a new coin stays inside the edge the NEXT cut will leave (so never on a strip about to go)
	SPACING = 8, -- studs a new coin keeps from the other coins
	BODY_GAP = 6, -- and from everyone's body
	-- Picking one up (Claude's picks)
	RADIUS = 3.2, -- studs across the floor from your body's middle to the coin
	CLAIM_SLACK = 6, -- studs on top the server allows your own screen's pick-up (it sees bodies a moment late)
	CLAIM_REWIND = 0.6, -- s of your past spots the server checks it against
	-- The look (the preview's numbers)
	HOVER = 2.6, -- studs over the floor (chest height)
	BOB = 0.18, -- studs up and down
	BOB_SPEED = 2.05, -- radians a second
	TURN_TIME = 4, -- s for one turn
	TILT = 7, -- degrees it rocks side to side
	SPAWN_TIME = 0.5, -- s it pops in (elastic, with a fast spin), with a light beam and a floor ring
	SNAP_TIME = 0.14, -- s it squashes and snaps to nothing when picked up
	FAR = 150, -- studs from your camera past which a coin drops its dust and twinkles (nobody sees them that far)
	RIM_COLOR = "FFD45E", -- polished gold
	FIELD_COLOR = "F4B536", -- the faces, a deeper gold so the star stands out
	STAR_COLOR = "FFD86A", -- the star (neon, so it reads from far away)
	GLOW_COLOR = "FFC63A",
	RING_COLOR = "FFD257", -- the turning dashed ring on the floor
	POOL_COLOR = "FFAE2A", -- the light on the floor under it
	-- Its pictures (drawn from the preview, uploaded to the group)
	IMAGES = table.freeze({
		ICON = "rbxassetid://82393733432281", -- the counter's coin
		GLOW = "rbxassetid://82782979316979",
		DOT = "rbxassetid://108069752069280",
		SPARKLE = "rbxassetid://113364152964594",
		RING_SOFT = "rbxassetid://134705563098159",
		RING = "rbxassetid://131942533254044",
		FLARE = "rbxassetid://87826708506803",
		DASH_RING = "rbxassetid://117517763493377",
		BEAM = "rbxassetid://99863935877161", -- the spawn's light beam (sideways: a Beam lays it along its length)
	}),
	-- The counter (owner 2026-11-09: "put the coin ui below the middle of the right side")
	HUD_MIDDLE_GAP = 12, -- pixels its top sits under the screen's middle
	HUD_EDGE = 14, -- pixels from the right edge
})

-- Chrono, the position library (as Huss Zero; owner: hitboxes use Chrono). Every player's game sends its body's spot
-- 30 times a second; every other screen plays it back smoothly a moment behind, and the server keeps the history it
-- checks tags against.
Config.Net = table.freeze({
	CHRONO = true,
	SEND_RATE = 30, -- spots a second (Huss Zero's)
	HISTORY_TIME = 2, -- s of every body's past the server keeps
})

-- How the Studio test bots play (DevBots; owner 2026-11-09: "can u make the bots smarter, they can use dashes").
-- Claude's picks; a little slower than a player so a person can still win.
Config.Bots = table.freeze({
	RUNNER_PACE = 0.9, -- a runner bot's top speed, share of a runner's sprint
	CHASER_PACE = 0.84, -- a chaser bot's, share of a chaser's sprint (just under a runner's sprint)
	THREAT_RANGE = 45, -- studs: chasers nearer than this make a runner bot run
	EDGE_COMFORT = 25, -- studs from an edge a runner bot starts steering off it
	JUKE_RANGE = 9, -- studs: a chaser closing in nearer than this makes a runner bot juke
	JUKE_CHANCE = 0.15, -- each frame in danger, the chance it decides to juke (so it's quick but not perfect)
	REACTION_MIN = 0.12, -- s from deciding to juke to the dash
	REACTION_MAX = 0.3,
	DASH_CHANCE = 0.08, -- each frame in dash range, the chance a chaser bot dashes in
	SHARE_PENALTY = 25, -- studs a runner another chaser bot is after counts as further away (they spread out)
	TARGET_HOLD = 1.2, -- s a chaser bot sticks with its runner unless another is much nearer
	LEAD_MAX = 1, -- s ahead a chaser bot aims at the most
	LEAD_SHARE = 0.7, -- share of that it aims (so it doesn't overshoot a turn)
	SLASH_GAP = 0.6, -- s between a chaser bot's slashes
})

-- Studio-only helpers.
Config.Dev = table.freeze({
	-- Studio play-tests add this many bots (R6 dummies that wander, flee and chase), so one person can test a whole
	-- round. The BOTS panel on screen changes it during a test (owner 2026-11-09: "make a setting so that i choose how
	-- many bots i want"). Never in a live game.
	STUDIO_BOTS = 3,
	BOTS_MAX = 29, -- a full server is 30 players (owner 2026-11-09: "max players is 30, so let me add 29 bots")
	BOT_NAMES = table.freeze({
		"Bot Blossom",
		"Bot Comet",
		"Bot Pixel",
		"Bot Nova",
		"Bot Turbo",
		"Bot Echo",
		"Bot Sprout",
		"Bot Zap",
		"Bot Mochi",
		"Bot Rocket",
		"Bot Pebble",
		"Bot Flash",
	}),
})

-- Saving (PlayerData): every player's coins, level, stats, quests, codes and hints, kept between visits.
Config.Data = table.freeze({
	STORE = "TagRivalsPlayers_v1", -- the DataStore's name (a new name starts everyone afresh: never change it lightly)
	AUTOSAVE = 90, -- s between saves of each player while they play (and always when they leave)
	LOCK_STALE = 300, -- s after which another server's hold on a save counts as dead (that server crashed)
	LOAD_TRIES = 6, -- tries (a few seconds apart) to get a save another server is still holding
	-- Studio play-tests keep everything in memory only, so a test never touches real saves or leaderboards. Turn on
	-- to test saving itself (needs Game Settings > Security > "Enable Studio Access to API Services").
	STUDIO_SAVES = false,
})

-- Coins and XP from playing (design notes, Coins and economy; XP numbers are Claude's picks).
Config.Rewards = table.freeze({
	TAG = 5, -- coins for each tag, paid at once (owner)
	PHASE1 = 15, -- coins for a runner who lasted past phase 1 before being tagged (owner)
	SURVIVE = 30, -- coins for a runner who survives to the end (owner)
	CLUTCH = 50, -- more coins for the last runner standing who survives (owner)
	XP_ROUND = 10, -- XP for playing a round to its end
	XP_TAG = 12,
	XP_PHASE1 = 15,
	XP_SURVIVE = 40,
	XP_CLUTCH = 60,
	XP_DODGE = 8, -- a perfect dodge
	XP_STAR = 1, -- each coin picked up on the map
})

-- Levels and titles (design notes, Levels and titles). Claude's picks.
Config.Levels = table.freeze({
	MAX = 100,
	XP_BASE = 100, -- XP from level 1 to 2,
	XP_STEP = 40, -- and this much more for each level after (level 10 to 11 needs 460)
	LEVEL_COINS = 20, -- coins for each new level,
	LEVEL_COINS_STEP = 5, -- plus this for each level you already have (level 10 pays 70)
	-- the title you wear from each level on (first place on a lobby leaderboard gives its own title instead)
	TITLES = table.freeze({
		table.freeze({ level = 1, title = "ROOKIE" }),
		table.freeze({ level = 5, title = "RUNNER" }),
		table.freeze({ level = 10, title = "SPRINTER" }),
		table.freeze({ level = 15, title = "TRICKSTER" }),
		table.freeze({ level = 20, title = "HUNTER" }),
		table.freeze({ level = 30, title = "PHANTOM" }),
		table.freeze({ level = 40, title = "APEX" }),
		table.freeze({ level = 50, title = "LEGEND" }),
		table.freeze({ level = 75, title = "MYTHIC" }),
		table.freeze({ level = 100, title = "RIVAL KING" }),
	}),
})

-- Quests (design notes, Coins and economy): 3 random ones in each of Daily, Weekly and Monthly. The quests themselves
-- are listed in QuestRules.
Config.Quests = table.freeze({
	PER_SET = 3,
	CLOSE_RANGE = 14, -- studs: a dash with a chaser this near counts as "while a chaser is close" (Claude's pick)
	FREE_REROLLS = 1, -- free rerolls of a daily quest each day (Claude kept one, design notes)
	REROLL_ROBUX = table.freeze({ daily = 20, weekly = 40, monthly = 90 }), -- owner's prices, shown on the button
	-- The Robux rerolls' developer product ids. 0: not made yet, and the paid reroll button stays hidden. Make the three
	-- products on the Creator Dashboard (Monetization > Developer Products) at the prices above and put their ids here.
	REROLL_PRODUCTS = table.freeze({ daily = 0, weekly = 0, monthly = 0 }),
})

-- Codes (owner 2026-11-13: "add a codes system"): type one in the CODES box for a reward, once per player. Add a line
-- to LIST for a new code (capital letters and numbers, no spaces). `expires` (optional) is a date as "2026-12-31":
-- the code stops working after that day (UTC).
Config.Codes = table.freeze({
	MAX_LENGTH = 24,
	COOLDOWN = 1.5, -- s between two tries
	LIST = table.freeze({
		RELEASE = table.freeze({ coins = 250 }),
		TAGRIVALS = table.freeze({ coins = 100 }),
	}),
})

-- The bounty (owner 2026-11-13: "Add a Bounty system"). Each round one runner is WANTED: the one on the longest run of
-- survived rounds (anyone, when nobody has one). Their bounty shows over their head. The chaser who tags them takes
-- it; if they survive the match they keep it themselves. It grows with every shrink they outlast. Claude's picks.
Config.Bounty = table.freeze({
	MIN_PLAYERS = 4, -- players in the round before there's a bounty (with fewer, everyone knows who's being chased)
	BASE = 20, -- coins on a wanted runner with no streak
	PER_STREAK = 15, -- more for each round in a row they've survived
	PER_SHRINK = 5, -- and it grows this much at every shrink they're still running at
	MAX = 150,
	XP = 25, -- XP for collecting it (or keeping it)
	COLOR = "FFD23A",
})

-- Coming back every day (launch checklist): a few coins the first time you join each day, more each day in a row
-- (day 7's keeps repeating; missing a day starts over). Claude's picks.
Config.Streak = table.freeze({
	REWARDS = table.freeze({ 25, 40, 60, 80, 100, 125, 200 }),
})

-- The lobby's leaderboards (design notes, Lobby): six all-time boards on a ring of holograms in the middle of the
-- lobby, the top SHOW of everyone who's ever played. `stat` is the saved number each one ranks by. Whoever is first
-- on a board wears the title "#1 <short>" over their head instead of their level's.
Config.Boards = table.freeze({
	STORE_PREFIX = "TagRivalsBoard_v1_",
	REFRESH = 150, -- s between reads of the boards (one board every REFRESH / 6 s, so the reads are spread out)
	SHOW = 10,
	RING = 13, -- studs from the lobby's middle to each hologram
	WIDTH = 12, -- studs
	HEIGHT = 15,
	LIFT = 2.5, -- studs its foot floats over the glass
	LIST = table.freeze({
		table.freeze({ stat = "tags", name = "MOST TAGS", short = "TAGGER", color = "FF2B4A" }),
		table.freeze({ stat = "survives", name = "SURVIVOR WINS", short = "SURVIVOR", color = "2EE6FF" }),
		table.freeze({ stat = "clutches", name = "LAST MAN CLUTCHES", short = "CLUTCH", color = "FFD23A" }),
		table.freeze({ stat = "bestStreak", name = "LONGEST STREAK", short = "STREAK", color = "7CFF6B" }),
		table.freeze({ stat = "bestRoundTags", name = "MOST TAGS IN A ROUND", short = "RAMPAGE", color = "FF9F43" }),
		table.freeze({ stat = "coinsEarned", name = "TOTAL COINS EARNED", short = "TYCOON", color = "B98CFF" }),
	}),
})

-- The lobby's extras (design notes, Lobby; launch checklist item 4). Claude's picks for where things stand.
Config.LobbyExtras = table.freeze({
	-- Flex pedestals: statues of the top 3 players in this server (by level, then coins), gold, silver and bronze.
	PEDESTAL_RING = 38, -- studs from the middle
	PEDESTAL_ANGLE = 90, -- degrees round the lobby where the middle pedestal stands
	PEDESTAL_GAP = 9, -- studs between pedestals
	PEDESTAL_HEIGHTS = table.freeze({ 4, 3, 2 }), -- studs: first, second, third
	PEDESTAL_COLORS = table.freeze({ "FFD23A", "C8CCD8", "D98A4E" }),
	PEDESTAL_REFRESH = 20, -- s between checks of who's in the top 3
	-- The practice dummy: it winds up and lunges at whoever is nearest inside its ring every few seconds, so new players
	-- can learn the perfect dodge without being in a round. Nothing is won or lost.
	DUMMY_RING = 30, -- studs from the middle
	DUMMY_ANGLE = 270, -- degrees round the lobby (opposite the pedestals)
	DUMMY_ZONE = 16, -- studs: its practice ring's radius; it only goes for players inside it
	DUMMY_EVERY = 3.2, -- s between lunges
	DUMMY_WINDUP = 0.9, -- s it glows red before it goes
	DUMMY_SPEED = 22, -- studs/s of its lunge: slower than a real chaser, so the star shows for about a third of a second
	DUMMY_MIN_GAP = 14, -- studs: it only lunges from at least this far (so the star has time to show)
	DUMMY_LUNGE_TIME = 1.6, -- s a lunge lasts at the most
	DUMMY_REACH = 5.2, -- studs: it "tags" you this close (as a chaser's reach)
})

-- Bots in live servers (launch checklist item 2: never leave a player alone; owner 2026-11-13: "give bots actual
-- clothes nd avatars"). When a server has fewer than FILL_TO players, bots join so rounds can start; each real player
-- who joins takes a bot's place. They wear real Roblox clothes, hair and hats (all free items made by Roblox, checked
-- 2026-11-13), play like the Studio test bots, and wear a small BOT tag over their name. Tags on bots pay coins and
-- count for quests, but never for the leaderboards. Studio play-tests still use the TEST BOTS panel's count.
Config.LiveBots = table.freeze({
	ENABLED = true,
	-- players and bots together a server is topped up to: with this many real players there are no bots (owner
	-- 2026-11-13: "bots should stop filling up server at like 15 players")
	FILL_TO = 15,
	SHOW_TAG = true, -- the small BOT tag over their heads (off: they look like players; be careful, players dislike it)
	NAMES = table.freeze({
		"Blossom", "Comet", "Pixel", "Nova", "Turbo", "Echo", "Sprout", "Zap", "Mochi", "Rocket", "Pebble", "Flash",
		"Jinx", "Bolt", "Waffle", "Lumi", "Dash", "Kiwi", "Rumble", "Sky", "Noodle", "Blitz", "Maple", "Onyx",
		"Pogo", "Ziggy", "Clover", "Fizz", "Ace", "Biscuit",
	}),
	SKIN = table.freeze({ "F2D2B6", "E0AC69", "C68642", "8D5524", "FFDBAC", "A9714B", "5C3A21" }),
	SHIRTS = table.freeze({
		607785314, -- ROBLOX Jacket
		398633584, -- Denim Jacket with White Hoodie
		144076358, -- Blue and Black Motorcycle Shirt
		398634295, -- Pastel Starburst Top with Gray Jacket
		382538059, -- Green Jersey
		398635081, -- Blue Plaid Shirt
		4047886060, -- Purple and Teal Top
		4047884939, -- My Favorite Pizza Shirt
		4047884046, -- Guitar Tee with Black Jacket
		382537702, -- Teal Shirt
		144076436, -- Grey Striped Shirt with Denim Jacket
		382537085, -- I <3 Pizza Shirt
	}),
	PANTS = table.freeze({
		398633812, -- Black Jeans with White Shoes
		398635338, -- Ripped Skater Pants
		398634487, -- Beautiful You Jeans
		144076760, -- Dark Green Jeans
		382538503, -- Black Jeans with Sneakers
		382537569, -- Black Jeans
		382537950, -- Jean Shorts with White Shoes
		382537806, -- Jean Shorts
	}),
	HAIR = table.freeze({
		63690008, -- Pal Hair
		451221329, -- True Blue Hair
		451220849, -- Lavender Updo
		376524487, -- Blonde Spiked Hair
		376526888, -- Straight Blonde Hair
		1103003368, -- Orange Beanie with Black Hair
		2956239660, -- Belle Of Belfast Long Red Hair
		3814474927, -- Cool Side Shave
		3814476174, -- Colorful Braids
		9243992729, -- Short and Sleek - Black
		9244021842, -- Side Part - Black
		7193448258, -- Wavy Middle Part - Brown
		7193442167, -- Pony Tail - Black
		9174355709, -- Sideswept Dreads - Black
		9244095135, -- Pony Tail - Blonde
		7193450455, -- Curly Afro - Black
		9244038785, -- Surfer - Red
		7193419595, -- Side Part - Brown
	}),
	HATS = table.freeze({
		607702162, -- Roblox Baseball Cap
		417457461, -- ROBLOX 'R' Baseball Cap
		2646473721, -- Roblox Visor
		607700713, -- Roblox Logo Visor
		48474313, -- Red Roblox Cap
	}),
	HAT_CHANCE = 0.3, -- share of bots that wear a hat as well as hair
})

-- Sounds (design notes: Round flow, Shrink shake and sound, Star pickup feel). Licensed sound effects from Roblox's
-- own library (Pro Sound Effects and APM, free in any game) and sounds built into Roblox; all checked to load
-- 2026-11-13. Nobody has listened to the mix yet: tune VOLUME and swap ids here after a playtest.
Config.Sound = table.freeze({
	VOLUME = 0.8, -- everything, times this
	TAG = "rbxassetid://9119872797", -- a tag near you: a deep synth thud ("Synth Whomps 8"), no screech
	TAG_PITCH = 0.85,
	SHRINK_THUD = "rbxassetid://9119874551", -- shrinks 1-3: a sub-bass thud ("Synth Whomps 33"), pitched down
	SHRINK_SLAM = "rbxassetid://9125484367", -- shrinks 4-8: a big reverberant boom ("Deep Hits Big Reverberant Booms")
	SHRINK_CRUMBLE = "rbxassetid://9125879362", -- the strip breaking away ("Rock Scrape Deep Clunky Slides")
	LAST_MAN = "rbxassetid://9043340902", -- last man standing: a bass drop ("AMBIENT BOOM 04")
	HEARTBEAT = "rbxassetid://9119872772", -- the last man's heartbeat: two soft low thumps a beat ("Synth Whomps 9")
	HEARTBEAT_EVERY = 0.62, -- s between beats (fast and heavy)
	TICK = "rbxasset://sounds/clickfast.wav", -- the shrink countdown and the last 10 s
	DASH = "rbxassetid://9120972321", -- your dash ("Wood Whoosh Slicing Air Quick Swings 4")
	SLASH = "rbxassetid://9120972444", -- a knife slash near you ("Wood Whoosh Slicing Air Quick Swings 1")
	DODGE = "rbxassetid://9125648149", -- a perfect dodge ("Magic Zoom Up Sharp Tubular Whoosh Fast Hiss")
	FALL = "rbxassetid://9126229255", -- falling off a cut strip ("Whoosh By Fast Airy Swooshing Whipping Thuds")
	COIN = "rbxasset://sounds/electronicpingshort.wav", -- a coin: a bright ping, a note higher for each within COIN_CHAIN s
	COIN_THUD = "rbxasset://sounds/bass.wav", -- with a soft bass thud under it
	COIN_CHAIN = 3, -- s (design notes)
	COIN_NOTES = table.freeze({ 1, 1.122, 1.26, 1.335, 1.498, 1.682, 1.888, 2 }), -- do re mi fa sol la ti do
	CLICK = "rbxasset://sounds/switch.wav", -- pressing a button
	OPEN = "rbxasset://sounds/button.wav", -- a panel opening
	REWARD = "rbxasset://sounds/electronicpingshort.wav", -- coins paid to you: two quick rising pings
	VICTORY = "rbxasset://sounds/victory.wav", -- your side won
	DEFEAT = "rbxassetid://9119872977", -- your side lost: a low whomp ("Synth Whomps 10")
	GO = "rbxassetid://9125805579", -- the match starts ("Rising Whoosh Hissing Build Up")
	LEVEL_UP = "rbxasset://sounds/victory.wav",
	HEAR_RANGE = 90, -- studs from your camera within which other players' tags and slashes are heard
})

-- The speed screen effect (design notes, Speed screen effect): red and cyan colour split and soft dark edges at the
-- screen's border, on your screen only. The design's "above about 18, peaks around 26" was written when a sprint was
-- 22; every speed went up since (a runner sprints at 25 now), so it starts just above a runner's sprint and peaks at
-- a last runner's (Claude's picks), and a dash still gives a short strong burst.
Config.SpeedFx = table.freeze({
	START = 26.5, -- studs/s it fades in above
	PEAK = 35, -- and is strongest at
	MAX = 0.65, -- never stronger than this (owner: capped at 65% so it never blinds)
	DASH = 0.6, -- a dash's burst,
	DASH_BACK = 0.3, -- easing back in this many s (owner)
	EDGE = 0.16, -- share of the screen's width each coloured edge covers at full strength
	RED = "FF2B4A",
	CYAN = "2EE6FF",
})

-- The first minute (launch checklist items 4 and 5): what a new player is shown, once.
Config.Hints = table.freeze({
	DODGE_TIMES = 3, -- "DASH NOW!" shows beside the gold star the first this many times its window opens
	SHOW = 4, -- s each of the three hints stays (SPACE = DASH, RED = CHASERS, the star = DASH NOW)
})

-- Cleanup (design notes, Round flow: "Survivors celebrate, infected collapse or emote"): Roblox's own R6 emotes.
Config.Celebrate = table.freeze({
	CHEER = "rbxassetid://129423030", -- the winners
	DANCE = table.freeze({ "rbxassetid://182435998", "rbxassetid://182436842", "rbxassetid://182436935" }),
	SLUMP = "rbxassetid://178130996", -- the losers sit down
})

-- The camera's follow lag in a dash (design notes, Camera: "lags a few studs during a dash, then springs back").
Config.DashLag = table.freeze({
	STUDS = 2.2, -- how far behind the view falls at the dash's peak (Claude's pick)
	RISE = 0.06, -- s to fall behind
	BACK = 0.35, -- s to spring back
})

return Config
