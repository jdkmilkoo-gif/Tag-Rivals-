# Tag Rivals: what's built (build notes)

Everything built so far, in plain words, with where it lives. The owner's design notes (project file
`tag-rivals/design-notes.md`) are the source of truth for what the game should be; this file says what the code does
today. Every number is in `src/shared/Config.luau`. Numbers marked "Claude's pick" are starting points to tune in
playtests.

Last updated: 2026-11-13.

## Setup

- Rojo serves this folder on port **34873** (Huss Zero uses 34872, so both can run at once). In Studio: Plugins > Rojo,
  port 34873, Connect. Only the Tag Rivals place (id 103953226550190) can connect.
- The game belongs to the group ROBLOXIAN CHAMPIONS UNITED (group id 6886290).

## Map and background

- **The square:** the floor looks like Roblox's baseplate (same grey, same grid), a **permanent 250 x 250 studs**
  square with a glowing cyan rim round its edges (owner 2026-11-09: "lets keep the map at a permanent 250 x 250 square
  with shrinks"). Every round starts at the full 250 whatever the player count, and the shrinks make it smaller (it
  used to be a circle sized by players: 100 + 15 each, then 120 + 18). (`src/server/Arena.luau`)
- **The lobby:** a big glass disc (96 studs across) floating 70 studs above the square, with a glowing cyan rim and an
  invisible wall round its edge. Its floor is see-through, so everyone waiting watches the round below. On it: six
  leaderboards, three pedestals and a practice dummy (see The lobby's show pieces). Shop booths come with the shop.
  (`src/server/Lobby.luau`, Claude's picks for size and height)
- When the game runs, the place's square baseplate and spawn pad are removed; they stay in the place for building.
- The grey floor you see doesn't collide; you stand on an invisible copy under it. Both are resized at the round's
  start and at each shrink's cut, so whoever is still on the cut strip has nothing under them and falls (see The round).
- **Invisible wall:** you can't leave the square; your own game stops your body 1.5 studs inside each edge, and the
  server puts back anyone more than 12 studs past that (it sees bodies a moment late and a shrink moves the edge fast,
  so a smaller grace yanked players near the edge; it used to have none). Falling far below the floor gives you a fresh body.
- **Background** (owner 2026-11-10: "like the back ground too", from the owner's neon sky-city pictures):
  - **The sky:** our own purple sunset over a sea of clouds: deep indigo at the top with stars, violet and magenta
    lower down, a hot pink horizon with thin pink cloud streaks, warm peach where the sun has set (towards the big
    city), and below the map a thick sea of clouds lit pink and lavender. Made by `uploads/sky/make_sky.py`, uploaded
    to the group (ids in `Config.Neon.SKY`, also set in `default.project.json` Lighting > Sky; every screen sets it
    too, so it shows whatever the place file has). It replaced the "Above Clouds Skybox" (3176887455). The haze
    (Lighting.Atmosphere) stays at 0.
  - **The scenery** (`src/client/Backdrop.luau`, drawn on each screen, about 740 plain parts that nothing can touch,
    built a few a frame when you join; Claude's layout):
    - three glowing highways round the map on tall pillars that fade into the clouds: dark decks, cyan lights along
      the rails, pink light under the edges, signs of amber chevrons that march along their sides (our own picture,
      on a surface that ignores the light so it glows), and streaks of light racing along both ways;
    - four floating cities on rock islands with pink neon rims: dark towers with cyan, blue, pink and violet window
      strips, glowing caps and bands, some with antennas and blinking lights;
    - over the biggest city (straight out past the far highway): a huge lavender halo ring with a violet haze and
      four bright lights running round it, and a breathing cyan beam of light up into the sky;
    - six small floating platforms with cyan rims and lamps, bobbing, round the map;
    - a pink shooting star across the sky every 5 to 10 s.
  - Only the light streaks, the ring's lights, the platforms, the shooting star, the blinking lights and the signs'
    arrows move each frame. A 14-bot Studio test held 60 FPS.

## Bodies

- Everyone spawns as an R6 version of their own avatar, on the lobby or in the round (the round decides where), and
  respawns 2 s after dying. (`src/server/Spawner.luau`)
- Streaming is off (`Workspace.StreamingEnabled`), so every screen always has the whole small map.
- No jumping, ever.
- **Name tags** (`src/client/NameTags.luau`; design notes: "Each player's name, level and title visible"): Roblox's own
  names over heads are off; every screen draws its own in the game's font. The name is white, or red for a chaser in
  the round. Under it, small and gold, "LV 12  HUNTER" (whoever tops a leaderboard wears "#1 TAGGER" instead). A bot's
  line starts with a small blue BOT. The wanted runner has a gold pulsing WANTED plate with their bounty, seen through
  everything from any distance. You don't see your own name, only your own WANTED plate. Tags further than 120 studs
  aren't drawn; what a tag says is checked 5 times a second and only changed when it's different.

## Movement (`src/client/MoveController.luau`, `src/server/MoveServer.luau`, `src/shared/MoveRules.luau`)

| | Walk | Sprint |
| --- | --- | --- |
| Runner | 20.5 | 25 |
| Chaser | 23 | 28.5 |
| Last runner | 27.3 | 34.1 |

Raised overall on 2026-11-09 (owner: "increase the overall speed from 22 to 25"): every speed times 25/22, so the
roles keep their gaps. They were 18/22, 20/25 and 24/30. Chasers were then slowed a little (owner 2026-11-09:
"slightly decrease the speed increase for chasers"): 22.7/28.4 became 22/27.5, so becoming a chaser adds 2.5 to your
sprint instead of 3.4. Then buffed a little (owner 2026-11-09 16:31: "buff the overall speed of the taggers a little
bit"): 22/27.5 became 23/28.5 (Claude's pick of "a little"), so a new chaser now sprints 3.5 faster than a runner.
Chaser bots run at their share of it, so they got faster too.

- **Sprint:** hold Shift (L2 held or L3 clicked on a controller). Always on with touch. No dead-stop.
- **Speeding up:** you start at 60% of your walk speed and speed up to your top speed instead of snapping (Claude's
  pick: 32 studs/s every second, slowing down at 48).
- **Speed-ups:** every tag adds 0.5 studs/s to everyone's walk and sprint (Claude's pick; owner: "a little"), and
  acceleration rises with it. Each star adds 0.2 (at most +10). Every rise shows **SPEED UP!** with the old and new
  sprint speed.
- **Dash:** Space (A or R1 on a controller, the Dash button on touch) dashes the way you're holding, or forward. 2
  charges, each refilling in **1.5 s**, one after the other; with none left Space does nothing. A dash covers **8 studs**
  in 0.15 s (owner 2026-11-09: "reduce the dash to 8 studs"; was 13, 12.5, then 10). You can't dash while stunned. and you come out of it a little faster than you run. The server checks every dash against
  the charges.
- **Afterimages:** 5 neon copies of your body along each dash, fading over 0.4 s. Cyan for runners, red for chasers;
  an equipped trail's colour later (the `DashColor` attribute). Everyone sees everyone's.

## Animations (`src/client/CharacterAnim.luau`)

- Idle, walk and sprint all play at once and blend by your speed, so nothing snaps. While walk and sprint blend, the
  feet are kept in step. Walk and sprint speed up with you (owner: "play the sprinting animation faster"): the sprint
  plays about 1.7x at a runner's sprint, at most 2.5x.
- Every dash plays a dash animation over the running, squeezed into 0.42 s. Dashing roughly the way you face plays one of
  the three forward dashes, a different one from the last (owner: "use all of them"). Dashing off to one side (50 to 130
  degrees from your facing) is a sidestep: the left or right dash plays and your body keeps facing the same way for
  0.3 s.

### In use: `ServerStorage > Animations` (owner 2026-11-09: "keep the current walk and run. but name them")

| Name | What it's for | Where it came from |
| --- | --- | --- |
| `TagRivals_Run` | Sprinting | wifonn3, "[🏃] Best Run Animations R6" (the pack's first run) |
| `TagRivals_Walk` | Walking | roblox_boi8913's walk, in wifonn3's "[🚶] Best Walk Animation R6" (127964771902906) |
| `TagRivals_Idle` | Standing still | TheNuggettier, "Dash + idle animation R6" (18979845290) |
| `TagRivals_Dash1`, `TagRivals_Dash2`, `TagRivals_Dash3` | Forward dashes, taking turns | TheNuggettier, "Dash + idle animation R6" |
| `TagRivals_DashLeft` | Sidestep to the left | TheNuggettier, "Dash + idle animation R6" |
| `TagRivals_DashRight` | Sidestep to the right | TheNuggettier, "Dash + idle animation R6" |
| `TagRivals_KnifeEquip`, `TagRivals_KnifeHold` | Drawing the knife, holding it | TheNuggettier, "BEST R6 animations (dash animations)" |
| `TagRivals_KnifeSlash1`, `TagRivals_KnifeSlash2` | The automatic slash, taking turns | TheNuggettier, "BEST R6 animations (dash animations)" |
| `TagRivals_KnifeStab` | The click-stab (PC) | Made for Tag Rivals by Claude from the knife hold |

Each one carries a `Credit` attribute naming its maker.

### Saved for next time: `ServerStorage > Animations_SavedForLater` (owner: "save the other cycles for next time")

| Folder | Name | What it could be for | Where it came from |
| --- | --- | --- | --- |
| Runs | `Run_wifonn3_B`, `Run_wifonn3_C` | Other sprints | wifonn3, "[🏃] Best Run Animations R6" |
| Runs | `Run_TheNuggettier` | Another sprint | TheNuggettier, "BEST R6 animations (dash animations)" (91857791404560) |
| Walks | `Walk_Gusthavuo777`, `Walk_emm1gar`, `Walk_haynob` | Other walks | wifonn3, "[🚶] Best Walk Animation R6" |
| Walks | `Walk_TheNuggettier` | Another walk | TheNuggettier, "BEST R6 animations (dash animations)" |
| Emotes | `Caramell`, `BirdBrain` | The emote menu | TheNuggettier, "BEST R6 animations (dash animations)" |

The second TheNuggettier pack's dashes and idle were the same as the first pack's, and its jump, fall and block weren't
kept (Tag Rivals has no jumping or blocking).

### Uploaded (2026-11-09, to ROBLOXIAN CHAMPIONS UNITED)

| Name | Animation id |
| --- | --- |
| `TagRivals_Run` | 92963569528431 |
| `TagRivals_Walk` | 132648325469907 |
| `TagRivals_Idle` | 111046364098979 |
| `TagRivals_Dash1` | 98007570829570 |
| `TagRivals_Dash2` | 81415439771249 |
| `TagRivals_Dash3` | 96266380699988 |
| `TagRivals_DashLeft` | 109464562762874 |
| `TagRivals_DashRight` | 85394736428002 |
| `TagRivals_KnifeEquip` | 102539697774925 |
| `TagRivals_KnifeHold` | 121243226049767 |
| `TagRivals_KnifeSlash1` | 85882993171030 |
| `TagRivals_KnifeSlash2` | 100170975457482 |
| `TagRivals_KnifeStab` | 88520140084598 |

The ids are in `Config.Anim`, so they play in the live game once the place is published (File > Publish to Roblox).
To change an animation: edit the KeyframeSequence in `ServerStorage > Animations`, upload it again and swap its id.

## The round (`src/server/Round.luau`, `src/shared/RoundRules.luau`)

Built 2026-11-09 (step 1 of the plan). Over and over:

| Step | Time | What happens |
| --- | --- | --- |
| Waiting | until 2 players | Everyone waits on the lobby. The timer says WAITING FOR PLAYERS. In a live game bots join a lone player within a few seconds (see Bots), so this is short. |
| Intermission | 30 s | On the lobby, watching the circle below. (Owner 2026-11-13: "make the intermission after a round 30s"; was 8 s, and 15 before that.) |
| Teleport | 2 s | Every screen fades to black. In the dark the chaser is picked (never the same one twice in a row when there's a choice), the circle is sized, the starting speed set, and everyone gets a fresh body: runners spread evenly round the circle (78% of the way out, a little random), the chaser in the middle with the knife in hand. Your screen says YOU ARE THE CHASER! or RUN! and the chaser's name. Everyone is frozen until GO!. |
| Match | 2 min | Tagged runners become chasers. Ends early when no runner is left. (Owner 2026-11-09: "change the game form 90 seconds to 2 minutes"; was 90 s.) |
| Cleanup | 5 s | Everyone frozen, no more tagging, the victory screen. Then everyone goes back up to the lobby. |

- Players who join mid-round wait on the lobby (owner 2026-11-11 kept this, with a shorter break and the YOU'RE IN
  NEXT ROUND! countdown, see Screens). If every chaser leaves, a runner is made the chaser; if fewer than 2
  are left, the round ends ("ROUND OVER").
- **Phases** go by runners left (owner): phase 2 once a third of the starting runners are tagged, phase 3 at two
  thirds, Last Man Standing with 1 left. The timer's bar is slate grey, amber, orange (Claude's pick), then crimson.
- **Last-runner speeds:** the runners get the last-runner speeds once a third of the starting runners (rounded down,
  at most 3) are all that's left: with 3 to 5 runners at the start only the last one, with 9 or more the last 3
  (Claude's reading of "when 2-3 runners remain").
- **Starting speed** by players in the round (owner: depends on the player count; formula is Claude's pick): +0.15
  studs/s to everyone's walk and sprint for each player over 4, at most +3. With 4 players nothing extra, with 20
  players +2.4. It doesn't show a SPEED UP!.
- **Speed per tag:** every tag adds 0.5 studs/s to runners and shows SPEED UP!. Chasers get less from each tag than
  the last (owner 2026-11-09: "Decrease the rate of speed increase as the more players get tagged for chasers"): 0.5,
  then 0.4, 0.32, 0.26... (each 80% of the one before), never more than +2.5 in all.
- **Shrinking:** the square shrinks **10% every 30 s** (at 30 s, 60 s and 90 s of the 2-minute match; owner 2026-11-09:
  "Decrease the strength of the shrinks. The map should shrink every 30 seconds. like 10%"). Tags no longer shrink it
  (they took 6% each), and the 20% shrink 25 s in is gone (owner: "get rid of the 25% shrink"). Never under 50 studs a
  side. A shrink shakes the camera: a sharp snap, then a rumble that fades over 0.8 s, stronger every shrink (0.25 at
  the first, +0.08 each, at most 1.2). Each shrink has its sound (see Sounds).
- **The warning and the cut** (`src/client/ShrinkFx.luau`; owner 2026-11-09: "make the game warn 3 seconds before the
  map shrinks. and whatever part of the map that shrinks that area should be red. and change the shrinking function as
  just like cutting off a that part of the map"). Numbers in `Config.Shrink`:
  - **3 s before each shrink** the strip round the edge that's about to go (12.5 studs off each side at the first,
    11.25 at the second, about 10 at the third) glows red on every screen, pulsing faster as the cut gets near, with a
    bright red line where the cut will fall and big white arrows on it marching inward, faster as the cut nears.
    Standing on the red flashes your screen's edges red.
  - **The banner** (owner 2026-11-10: "Add these", from the owner's picture): players in the round see a neon banner
    under the timer: a dark red glass plate with a glowing red double edge and slanted ends, **MAP SHRINKING IN 3, 2,
    1** in white-pink letters with a hot red edge and a glint running across them, and three red chevrons either side
    pointing in at the words that light up one after another, marching inward (faster as the cut nears). The plate
    and its glow breathe with the red's pulse, a light sweeps across the glass, the banner pops on each new number,
    shakes in its last second and bobs with the timer. **YOU'RE ON THE RED! MOVE IN!** shows under it only while
    you're standing on the red, with RED blinking red and white. On a phone it's drawn smaller, and never wider than
    the room between the tag feed and the coin counter. The plate, chevrons, arrows and the light are our own
    pictures (`uploads/ui/make_neon_ui.py`, uploaded to the group; ids in `Config.Neon`).
  - **Then it's cut off:** the floor and rim lose the strip at once (no more smooth shrinking), and on every screen the
    red strip breaks into pieces about 25 studs long that tip over the edge and fall into the clouds (1.6 s) while the
    cut line flashes white.
  - **Anyone still on the red falls with it** (owner 2026-11-10: "make the red let players fall and become tagger";
    it used to sweep them onto what's left). Your own game lets go of your body (no wall, no walking, no dashing),
    nudges it clear of the edge and pushes it outward (9 studs/s), and you drop into the clouds; the server sees you
    under the floor and you get **YOU FELL!** on your screen and "Name [bolt] FELL OFF!" in the tag feed. **A runner who
    falls becomes a chaser** (knife in hand, loses their coins' speed, like a tag, but nobody gets the tag and nobody
    speeds up). After 1.7 s you're back on the square somewhere near the middle (within 30% of the half-side); a new
    chaser stands still there for 2 s like a tagged runner. A chaser who falls just comes back. If the last runner
    falls, the chasers win. Bots on the red at the cut are dropped by the server the same way. Numbers in
    `Config.Shrink` (FALL_*; Claude's picks). For a second after a cut the server doesn't pull anyone back onto the
    square (they're on their way down).
  - Runner bots treat the red as off the map, so they get off it.
  - How it works: for the warning the server sets `CutRadius` (the half-side after the cut) and `CutAt` (when) on
    Workspace; the cut is `Arena.cutTo` (`LastCutAt` on Workspace says when), and the Round remote's `shrink` carries
    the half-sides before and after. Your game checks whether you're past the new edge when that message arrives
    (`MoveRules.pastEdge`). Someone falling has `FallingAt` set by the round until they're back; the Round remote's
    `fell` tells every screen.
  - Every screen builds the red strip, its lines, the cut line's flash and 44 pieces once when the game starts
    (Workspace > ShrinkFx, hidden out of sight), then only moves, shows and hides them, so nothing is made mid-round.

## Tagging (`src/client/TagController.luau`, `src/server/Tagging.luau`, `src/server/History.luau`)

- **No button** (owner): a chaser whose body comes within **5.2 studs** of a runner's (middle to middle), or **7.5**
  during their dash's 0.15 s burst, slashes automatically and the runner is tagged.
- The chaser's own screen decides it's close (so it feels instant), plays the slash and its effects at once, and tells
  the server what it saw: where it drew the runner, where its own body was, the moment of the runner's own clock it
  drew them at, and whether it was dashing.
- **Chrono** (the same library as Huss Zero, v2.2.3, MIT, in `src/shared/Chrono`; set up in
  `src/shared/ChronoSetup.luau`): every player's game sends its body's spot 30 times a second and every other screen
  plays it back smoothly a moment behind. The server keeps 2 s of everyone's spots (`History`), by each runner's own
  clock, so it checks the tag against exactly where the runner was on the chaser's screen. It also checks against the
  server's own copy of the bodies over the last moments (the chaser's ping plus 0.35 s, at most 1 s).
- **The server's checks** (Claude's picks, as Huss Zero's hits): the round is on; the claimer is a chaser and the
  target a runner, both in it; the gap is within reach (+1 stud of slack; the dash reach only if the server saw the
  dash just before); the runner really was within 4 studs of where the chaser drew them; the chaser really was within 7
  studs of where it says. A claim the server's history hasn't caught up with waits up to 0.4 s.
- **On a tag:** the runner becomes a chaser (the knife moves to their hand), everyone speeds up, and every screen draws
  it: the runner glows white and red for 1.2 s, fading into the red tagger outline, and the hit burst.
- **Every tagger has a red outline** (`src/client/ChaserOutline.luau`; owner 2026-11-09: "for every tagger add a red
  outline"), players and bots, yours included, on every screen. The chaser's screen edges flash
  crimson, the view pops out 6 degrees and the screen shakes (a snap and a short rumble; owner 2026-11-09: "a screen
  shake for every tag from the player"); the runner's screen too, with TAGGED! You're a chaser now. The chaser sees
  +1 TAG.
- A slash every 0.4 s at most; the same runner isn't claimed twice within 0.6 s.
- **The new chaser's stun** (owner 2026-11-09: "do the stun before tagging"): a runner who's just been tagged stands
  still for **2 s** (they can't move, dash or tag) before they can chase, which slows the swarm's snowball. Their
  screen says "TAGGED! You're a chaser now. Get ready...".
- **The perfect dodge** (`src/client/PerfectDodge.luau`, `Tagging.perfectDodge`; owner 2026-11-09: "Introduce a
  prefect dodge, with like a small gold animated star above when its a current window for a perfect dodge and the
  window should be pretty small..., then slows the tagger and make his screen monochrome for a little bit while hes
  stunned"). Numbers in `Config.Dodge` (Claude's picks):
  - **The window** is open while a chaser is just outside its reach of you (5.2 studs, or 7.5 while it's dashing) by no
    more than **6.7 studs**, and closing in at 3 studs/s or more (or dashing at you). At a sprinting chaser's speed
    that's about a quarter of a second (owner: "the window a little small", then "increase the window again, cuz like,
    i cant get it done bro", then "make the perfect dodge 6.7 studs"; it was 2.5 studs, then 4, then 6.5). A stunned chaser opens no window.
  - **While it's open, a small gold star** spins and pulses over your head (only you see it).
  - **Dash in it** (or up to 0.15 s after) and your game tells the server; it checks you really just dashed and the
    two of you were close, then the chaser is **stunned for 1.2 s**: 45% speed, no dashing, no tagging, and **their
    screen goes grey** (fading back to colour over 0.35 s). They get "DODGED! Stunned for a moment".
  - **A perfect dodge's dash goes 9.5 studs** instead of 8 (owner 2026-11-09: "9.5 studs dodge distance if it is a
    perfect dodge"); runner bots' perfect dodges too.
  - **The runner can't be tagged for 1.3 s** (owner: "slightly increae the invincilibity duration"; was 1) after a
    perfect dodge, and **everyone sees "PERFECT DODGE!"** pop, rise and
    fade over their head (owner 2026-11-09: "when perfect dodging the player is invincible, and everyone can see on the
    runners head 'perfect Dodge!'").
  - **A burst of speed:** the runner runs 30% faster for 1.5 s after it (owner 2026-11-09: "speed boost after perfect
    doging"). Their camera snaps and rumbles hard, the view kicks out 14 degrees and the screen edges flash gold (owner:
    "give me better camera shake when perfect dodge"). The big "PERFECT DODGE!" on the runner's own screen is gone;
    only the one over their head stays (owner).
  - Once every 3 s per runner; a chaser can't be dodged again until 1.5 s after its stun ends.
  - Bots: a runner bot whose juke lands in the window perfect-dodges its chaser (you included).
- **Click to stab (PC only)** (owner, 2026-11-09: "you can click to stab too btw, but only pc"): a chaser playing with
  a mouse and keyboard can also left-click to stab. The stab reaches a little further than the automatic slash, **6.5
  studs**, but only straight ahead (60 degrees either side of where you face), once every 0.6 s (Claude's picks). A
  dash still gives 7.5. Clicks on buttons don't stab. A stab that reaches nobody still shows its trail on every screen.
  Phones and controllers keep the automatic slash only.

## The knife (`src/server/Knives.luau`)

- **Everyone wears a knife diagonally across their back** (owner, 2026-11-09), from the right shoulder (handle) down to
  the left hip (tip). Becoming a chaser (picked in the fade or tagged) moves it into the right hand: the draw
  animation plays, then the hold (right arm only, so the run keeps going). It's held forward out of the fist, tipped up
  30 degrees so you can see it over your shoulder (Claude's pick).
- **Bloomblade** is the test knife (owner: it stays an Epic; at launch chasers get a Common knife). It's behind the
  dev-only switch `Config.Knife.USE_TEST_KNIFE` (on now). Off, everyone gets the default knife; until the shop's
  Common knives exist that's a plain placeholder built in code, in Bloomblade's colours.
- **Bloomblade in Studio:** `ServerStorage > Knives > Bloomblade`, made from the cosmetics thread's export (uploaded to
  the group as Model 131269864457939, 14 parts, 3.52 studs long). Its flat parts were given their colours and
  materials from the export notes; its crystal blade and sakura emblem looked washed out in Studio, so their
  textures are tinted violet and pink. Every knife model has a `KnifeRoot` at its own origin (blade along +X).
- **The knife's effects** (`src/client/KnifeFx.luau`; owner 2026-11-10: the knife showed no effects, "Epic VFX big and
  clearly visible"). Until then a held knife only had a faint light (invisible in daylight), the trail was see-through
  and washed out to white, and the hit burst was small; the idle effects had never been made.
  - Every knife model carries its own effects on an invisible `FX_Blade` part over its blade: particle emitters marked
    with the attribute `KnifeFx = "Idle"` or `"Swing"`, all off in the model. Every screen turns them on and off.
    Bloomblade's are made by `uploads/knives/make_bloomblade_fx.luau` (run it in Studio's command bar in Edit mode,
    then save the place).
  - **Held** (a chaser, not swinging): a violet aura, pink-violet energy flames rising off the blade, pink petals
    drifting down, blossoms of light, violet wisps and white-pink twinkles, and the blade's light (#C86AFF, 9 studs)
    pulsing on a 2.6 s beat. Off on a runner's back. Knives more than **120 studs** from your camera keep them off, so
    a swarm of chasers doesn't slow phones (Claude's pick, `Config.Knife.IDLE_RANGE`).
  - **The slash:** one of two slash animations, taking turns, played 1.35x fast for 0.55 s, over the hold. While the
    blade's trail is on (0.02 s to 0.35 s; the stab 0.1 to 0.3 s) the swing effects run too: petals shed off the
    blade, sparks and a glowing smear; the idle effects pause till the trail's off. A knife more than 120 studs away
    swings with its trail only. The trail is now solid pink to violet (Brightness 1.5, light emission 0.3, lifetime
    0.3 s); brighter than that burns it out to white against the sky.
  - **The hit burst** at the tagged runner: a pink flash, a white-pink star flare, two rings (up to 11 studs), a
    violet bloom, 60 petals, 40 sparks and a pink light (14 studs).
  - The pictures are the coin's white ones (glow, dot squashed into a petal, sparkle, flare, rings; already uploaded
    to the group), tinted, plus Roblox's own fire, until the knife's own effect textures are uploaded. The colours
    are kept low on light emission so the stacked glows stay violet and pink instead of washing out to white.
- The charm swing comes later.
- Animations: `ServerStorage > Animations > TagRivals_KnifeEquip`, `TagRivals_KnifeHold`, `TagRivals_KnifeSlash1`,
  `TagRivals_KnifeSlash2` (TheNuggettier's "BEST R6 animations (dash animations)"), uploaded (ids below).
- **The stab** (`TagRivals_KnifeStab`, made for Tag Rivals from the knife hold): the arm pulls back a little, thrusts
  forward with the right shoulder twisting in (0.19 s, when Bloomblade's stab hits), holds, and eases back by 0.55 s.
  Only the torso and right arm move. Its trail is on from 0.1 s to 0.3 s. The script that builds it is
  `uploads/animations/make_knife_stab.luau`.

## Coins on the arena (`src/server/Coins.luau`, `src/client/CoinFx.luau`, `src/shared/CoinRules.luau`)

The arena pickups the design notes call **Stars** (owner 2026-11-09: "now implement coins as a pickup in the rounds",
with the coin from the 'Tag Rivals Coin' preview). Numbers in `Config.Coins`.

- **The coin:** the preview's gold coin with a 4-point star on both faces, 2 studs across. It floats at chest height,
  bobs, turns once every 4 s and rocks a little, with a soft glow, gold dust rising, twinkles on the rim, a light pool
  and a turning dashed ring on the floor. Model: `ServerStorage > Pickups > Coin` (uploaded to the group as Model
  80640452303536; if the place copy is missing, the server loads the uploaded one). Its pictures are uploaded too (ids
  in `Config.Coins.IMAGES`; sources in the project files under `tag-rivals/coin/`).
- **They come in over time** (owner: "should spawn over time"), and about twice as often as at first (owner
  2026-11-13: "make coins appear more often"): the first 1 s after GO!, then one every 0.75 s while fewer than 10 +
  0.8 a player are on the map (at most 30; 13 with 4 players, 22 with 15). It was the first after 2 s, one every
  1.5 s, 6 + half a coin a player up to 18. New ones pop in with a spin, a light beam and a floor ring. Claude's
  picks.
- **Where:** 65% land near the middle (owner: "most of them spawn near the dangerous centre so runners can't just loop
  the edge"), the rest anywhere, always 6 studs inside the edge the **next** cut will leave (so never on a strip
  that's about to go), 10 studs from other coins and 6 from anyone's body. A cut drops the coins on the strip that
  went; the match's end clears the rest. A new coin keeps 8 studs from the others (was 10).
- **Picking one up:** touch it (within 3.2 studs across the floor) to get **+2 coins and +0.2 top speed** (the speed
  stack, `Stars`: at most +10, SPEED UP! shows each rise). Runners and chasers both can. Your own screen says when you
  touch one, so it's instant; the server checks you really were near it (where it saw you in the last 0.6 s, 6 studs of
  slack). The server also checks every body itself, so bots pick coins up too, and they get faster with them.
- **A tagged runner loses their whole speed stack** (owner) and starts again at zero as a chaser; the coins they picked
  up stay theirs. Leaving the round clears the stack; a new round starts everyone at 0 coins and 0 stack.
- **Collecting:** the coin squashes and snaps to nothing, a white-gold flash, gold sparkles, streaks, glitter and an air
  ring, two floor rings, a short light. A "+2" pops up, a coin flies from it to the counter with a trail of sparks, the
  counter punches and the speed tag glows.
- **No lag** (owner: "make sure it doesnt lag the game at all"): the server keeps only a short list of spots (one
  attribute per coin) and sends one small message per pick-up. Every screen draws the coins itself: the pieces are
  built once and reused, moved all at once each frame, the particles are a few shared emitters, and coins more than
  150 studs from your camera drop their dust and twinkles; their glow, floor light and ring change 20 times a second.
  Turning the coins' pictures off in a Studio test with 29 bots made no difference to the frame rate.
- **Saved at once:** each coin picked up goes straight into your saved coins (see Saving), with 1 XP, and counts
  for the coin quests and the TOTAL COINS EARNED board. The round's own counter still starts at 0 each round.

## Saving (`src/server/PlayerData.luau`)

Built 2026-11-13 (step 2 of the plan). What every player keeps between visits: coins, XP, the saved stats, quests,
used codes, the daily streak, first-minute hints, bought rerolls. Numbers in `Config.Data`.

- One save a player (DataStore `TagRivalsPlayers_v1`, key `u_<user id>`). It loads when they join, saves every 90 s
  (each player on their own beat, so they never all save together), when they leave, and when the server shuts down.
- **Only one server holds a save at a time.** The save carries which server has it; a player who hops servers faster
  than the old one saves waits a few seconds for it (6 tries). A server that crashed counts as gone after 5 minutes.
  This is what stops coins being copied by quick rejoining.
- Every call is tried again with a growing wait. **A save that can't be loaded is never replaced by an empty one:**
  the player is asked to join again instead.
- Anything missing in an old save (a new field) gets its starting value when it loads.
- **Studio play-tests keep everything in memory only** (`STUDIO_SAVES = false`), so a test never touches real saves or
  the leaderboards. A Studio test always starts you as a new player.
- The rest of the server only reads and changes the copy in memory (`PlayerData.get`).

## Coins, XP, levels and titles (`src/server/Progress.luau`, `src/shared/ProgressRules.luau`)

The one place that changes what a player owns; nothing on a screen can set a number. Numbers in `Config.Rewards`,
`Config.Levels`, `Config.Streak` (XP and level numbers are Claude's picks).

- Each player's coins, level, XP into the level, title and survival streak are on their Player (attributes `Coins`,
  `Level`, `Xp`, `XpNeed`, `Title`, `SurviveStreak`), which is what the wallet, name tags and pedestals read.
- **Levels:** 100 XP from level 1 to 2, then 40 more each level (level 10 to 11 takes 460), up to level 100. Each new
  level pays coins (20 + 5 a level: level 10 pays 70) and shouts LEVEL 10! on your screen.
- **Titles:** ROOKIE (1), RUNNER (5), SPRINTER (10), TRICKSTER (15), HUNTER (20), PHANTOM (30), APEX (40), LEGEND (50),
  MYTHIC (75), RIVAL KING (100). First place on a lobby leaderboard wears "#1 TAGGER" (and the like) instead.
- **The daily bonus** (launch checklist): the first join of each day (UTC) pays 25, 40, 60, 80, 100, 125, then 200
  coins for each day in a row; missing a day starts over. DAILY BONUS! shows a few seconds after you join.
- **The saved stats:** tags, survives, clutches, streak, bestStreak, bestRoundTags, coinsEarned, rounds, dodges,
  stars, bounties.
- **The Progress remote** carries the moments to your screen ("coins", "level", "quests", "questDone", "code",
  "streak") and your requests back ("quests", "claim", "reroll", "code", "hint"). Every request is checked for its
  kind and what it carries, and held to 3 a second of each kind for each player.

## What a round pays (`src/server/Rewards.luau`)

The round tells Rewards each moment and it does the rest. A mistake in there can never stop the round.

| For | Coins | XP |
| --- | --- | --- |
| Each tag (paid at once) | 5 | 12 |
| A runner who lasted past phase 1 before being tagged | 15 | 15 |
| A runner who survives the match | 30 | 40 |
| ...as the last runner standing | +50 | +60 |
| A perfect dodge | | 8 |
| Playing a round to its end | | 10 |
| Each coin picked up on the map | 2 | 1 |
| The bounty | see below | 25 |

- **Tags on bots** pay coins and count for quests, but never for the leaderboards (tags, most tags in a round).
- **The survival streak:** rounds in a row you survived. A tag, a fall, or leaving mid-match as a runner ends it.
- A round that falls apart (everyone left) pays what was already earned and nothing more.
- **Your round's card** (`src/client/PayoutCard.luau`; design notes: "Post-match record board"): with the end screen a
  card slides in from the left: SURVIVED +30, 2 TAGS +10, BOUNTY +35, COINS PICKED UP +6, each line popping in with a
  tick, the total counting up, then your XP and your record (how long you lasted, your tags and when the first came,
  or that you were the first chaser). It leaves with the end screen.
- **For the owner's dashboard:** a brand-new player's first minutes go to Roblox's funnel chart (Creator Dashboard >
  Analytics > Funnels): Joined, First round started, First dash, First round finished, Second round finished. It shows
  where new players drop out. Not sent from Studio.

## The bounty (`src/server/Bounty.luau`; owner 2026-11-13: "Add a Bounty system")

Numbers in `Config.Bounty` (Claude's picks).

- Each round with 4 or more in it, **one runner is WANTED**: the one on the longest survival streak (picked at random
  among the runners when it's a tie or nobody has one). A bot can be wanted.
- **Worth:** 20 coins, +15 for each round of their streak, **+5 at every shrink they're still running at**, at most 150.
- A gold WANTED plate with the amount floats over their head on every screen, seen through everything.
- **The chaser who tags them takes it.** If they **survive the match they keep it themselves.** If they fall off a cut
  strip or leave, nobody gets it.
- Shouted on screen (`src/client/BountyHud.luau`): just after GO!, YOU'RE WANTED! to them and WANTED: NAME to everyone
  else; YOUR BOUNTY: 30 at each shrink (their chasers see it too); BOUNTY CLAIMED! or BOUNTY LOST at its end.

## Quests (`src/server/Quests.luau`, `src/shared/QuestRules.luau`, `src/client/QuestPanel.luau`)

Design notes: 3 random quests in each of Daily, Weekly and Monthly.

- **The quests** are listed in `QuestRules`: 8 daily (100 to 250 coins), 7 weekly (800 to 1,200), 5 monthly (3,500
  to 5,000). The owner's are in (ADRENALINE JUNKIE, PURE FLAWLESS, IRON LUNGS, DANGER DANCER, THE INFECTION, LAST ONE
  STANDING); the rest are Claude's picks in the same spirit (tags, coins picked up, rounds played, perfect dodges,
  lasting past phase 1, dash tags, bounties).
- A set is dealt afresh when its day, week (Monday) or month turns over (UTC), also for someone playing through it.
- A finished quest waits for its **CLAIM** button, then pays its coins and a tenth of that in XP.
- **Reroll** swaps an unfinished quest for another: one free daily reroll a day. The Robux rerolls (owner's prices:
  20, 40, 90) are built but **hidden until their product ids are in `Config.Quests.REROLL_PRODUCTS`**. A bought reroll
  that can't be used at once is kept on the save, and no purchase is ever paid out twice.
- **The QUESTS panel:** three tabs, when the set refreshes, and a row a quest: what to do, a bar that fills, the
  reward, and one button (CLAIM!, REROLL FREE, REROLL x2, REROLL R$20 or CLAIMED). Rows slide in one after another,
  bars fill smoothly, a claimed row punches. A red badge on the QUESTS button counts rewards waiting.
- QUEST DONE: NAME is shouted on your screen the moment one is finished.

## Codes (`src/server/Codes.luau`, `src/client/CodesPanel.luau`; owner 2026-11-13: "add a codes system")

- Type a code into the CODES box, press REDEEM (or Enter), get its coins, **once per player** on any server (used
  codes are on the save).
- **The codes are in `Config.Codes.LIST`**: add a line for a new one, with its coins and an optional last day
  (`expires = "2026-12-31"`). To start with (Claude's picks, change or remove them): **RELEASE** (250 coins) and
  **TAGRIVALS** (100 coins).
- What's typed is tidied to capitals and numbers, so "release" and "Release " work. One try every 1.5 s.
- The answer pops under the box: green "+250 COINS!", or red for a code that doesn't exist, has run out or was used.

## Bots (`src/server/DevBots.luau`, `src/server/BotAnim.luau`)

**In a live game** (launch checklist: never leave a player alone; numbers in `Config.LiveBots`): bots top a quiet
server up to **15 players and bots together** (owner 2026-11-13: "bots should stop filling up server at like 15
players"). One player gets 14 bots, 10 players get 5, 15 or more get none. They come and go between rounds only, never
in the middle of one. `ENABLED = false` turns them off.

**They look like players** (owner 2026-11-13: "give bots actual clothes nd avatars"): each wears one of 12 shirts, 8
pants and 18 hair styles, 3 in 10 a cap as well, on one of 7 skin tones, all free items made by Roblox. If Roblox
can't load a look, the bot gets the clothes without the hair, then a plain body. Names come from a list of 30
(Blossom, Comet, Pixel...), a different pick each server. Each has a level from 1 to 14 and its title, and a small
blue **BOT** over its name (`SHOW_TAG`; turning it off makes them pass for players, which players dislike when they
find out).

**In a Studio play-test** they're the tester's: a test adds 3 test bots, so one person can play a whole round. The **TEST BOTS panel** at the top left of
the screen, under Roblox's own buttons (under the tag feed when that's on the left, on a phone; clear of the phone
thumbstick) (Studio only, `src/client/DevBotsPanel.luau`; owner 2026-11-09: "make a setting so that i choose how many bots
i want") has - and + buttons for 0 to 29 bots (a full 30-player server; owner: "max players is 30, so let me add 29
bots"). New bots wait on the lobby for the next round; removed ones leave at once (those not playing first). The choice
lasts for that test; the starting number is `Config.Dev.STUDIO_BOTS`. Under the panel, the test's frames per second
and its slowest frame each second (red under 45 FPS). Never in a live game.

The bots play like players (owner 2026-11-09: "can u make the bots smarter, they can use dashes"; numbers in
`Config.Bots`, Claude's picks), a little slower so a person can still win:
- **Dashes:** the players' dash, 2 charges each refilling in 1.5 s, 8 studs in 0.15 s, with afterimages on every
  screen.
- **Runner bots** (90% of a runner's sprint) watch every chaser within 45 studs, the closest counting most, and run
  away from them while keeping off the edges and out of the corners (near an edge they slide along it). When a chaser
  closes in within 9 studs, or dashes at them, they juke: a sidestep dash across its line, away from the nearest edge,
  after a 0.12-0.3 s reaction.
- Stuns hold bots like players (a new chaser stands still for 2 s; a dodged one is slowed).
- **Chaser bots** (84% of a chaser's sprint) pick the nearest runner no other chaser bot is after (they spread out),
  run to cut it off (where it'll be, not where it is), dash in once the dash and its 7.5 reach cover the gap, and slash
  and tag whoever they reach.
- **Animations** (`BotAnim`): the same idle, walk and sprint as players, blended by speed and sped up with it; a dash
  animation on every dash; the knife hold while chasing and a slash on every tag; a cheer, a dance or a slump at the
  end of a match.
- Bots pick coins up, can be wanted, and keep a survival streak like players, but earn and save nothing.
- In a Studio test with 12 bots, a round went from 12 runners to 2 in about 17 s, with the bots dashing about once a
  second between them.

## Camera (`src/client/CameraFeel.luau`)

- The view widens with speed: 70 standing, 77 walking, 85 sprinting, up to 90 with speed bonuses.
- A dash punches it out to about 103 and eases back over 0.4 s; a sideways dash tilts the view 2.5 degrees the other
  way.
- **Step shake:** on every footstep the view dips a little and rolls slightly toward the foot that landed; lighter
  walking, stronger sprinting. Dialled down to under half its first strength (owner: "dial down the camera shake").
- **Steering with the camera, Huss Valley style** (`src/client/CameraSteer.luau`, `src/client/HeadLook.luau`; owner
  2026-11-09: "think of your camera like a flashlight attached to your chest"). On every device, while you're playing
  a round:
  - **Only you turn the camera** (mouse, right stick, dragging on a phone); moving never turns it. It sits **1.75 studs
    over your right shoulder** (owner: "give it an offset like the over the shoulder"), sliding over as the round
    starts and back as it ends.
  - **The keys move you relative to the camera:** W into the screen, S back, A and D sideways. Your running direction
    follows the camera with a small elastic lag (~0.1 s, `STEER_FOLLOW`), so holding W and panning runs you round a
    smooth arc, and a fast flick drifts a little.
  - **Your body turns after the camera** with the same kind of lag (`BODY_FOLLOW`): standing still it spins on the
    spot to face the new way; running forward it faces where you run; sideways it turns only 45 degrees toward where
    you run (owner: a full turn "would look unnatural"); straight back it keeps facing forward, and the back diagonals
    twist 20 degrees.
  - **Your head turns at once** to where the camera looks (up to 70 degrees either side of the body, 35 up and down),
    and everyone sees it: your game sends the turn 10 times a second, the server puts it on your body
    (`LookYaw`/`LookPitch`, `src/server/LookServer.luau`) and every screen eases the other heads to it.
  - **No sprinting backwards** (S, S+A, S+D; `MoveController`); sideways sprinting is fine. Heads still follow the
    camera on the lobby.
  - **PC:** the mouse is held in the middle of the screen and hidden.
  - **On the lobby it's Roblox's ordinary free camera** (owner: "in the lobby just keep it free camera"): the mouse is
    free, right-drag turns the camera, your body turns the way you walk, and you can sprint any way. (The Alt hint is
    gone with it.)
  - Gone after the owner's "undo all that": the right-click look-around, the instant body snap, and the shift lock.
    Roblox's own turning (AutoRotate) is off while this steers, and Roblox's shift lock isn't used.
- **Looking ahead** (`src/client/CameraLead.luau`): built (the view slid up to 3.5 studs the way you run), now **off**
  (`Config.Camera.LEAD = 0`) because the owner wants "only the player turning the camera can affect the camera".
- **Dash lag** (design notes: "lags a few studs during a dash, then springs back"): in a dash the view falls 2.2 studs
  behind you along the dash in 0.06 s and springs back over 0.35 s (`Config.DashLag`, Claude's picks).

## Screens (UI)

Panels that are hidden (a switched-off screen, a hidden call-out) don't move their dots or stripes, to save work. The dots are drawn from one
picture (see Frame rate).

**Style** (owner: "copy dis Ui Style from Huss Zero"; `src/client/PlasticUi.luau`, `src/client/Halftone.luau`):
Montserrat Bold Italic words with a thick black outline and a black drop under them; chunky square plastic (lit face,
white shine on top, darker side, black outline, soft shadow); moving halftone dots on the faces; bright blue (2B6BFF)
and gold (FFD23A) plastic; dark indigo plates (241B55) with scrolling diagonal stripes. **No SPEED box** (owner: "dont
take the Speed box"). **Everything moves** (owner: "make the Uis All animated", "and the texture also animated").

- **The timer** (`RoundHud.luau`): top middle. A status line (INTERMISSION, THE SWARM IS LOOSE!, LAST MAN STANDING,
  ROUND OVER) with a glint, the big countdown on a striped indigo plate, and a thin bar under it that fills as time
  runs in the phase's colour. It bobs and leans, a new phase pops it, the last 10 s pulse red.
- **YOU'RE IN NEXT ROUND!** (`NextRound.luau`; owner 2026-11-11, from the launch checklist: "Keep waiting, shorter
  break"): first under the timer, on the lobby only. Gold words with a glint over a blue plastic tag, "STARTS IN
  1:12". It shows during the break, and while a round is on that you're not in (you joined late); it hides during
  the end screen (it would sit on it) and while the game waits for players. The time counts to the next fade to
  black: during the break it's the timer's own clock; during a match it counts as if the match runs its full 2
  minutes, so it drops when a match ends early. It pops in, bobs, the words rock, the tag ticks every second and the
  last 5 s pulse gold. Layout and look are Claude's picks. Not tried in Studio yet (no place was open on 2026-11-11).
- **The wallet** (`Wallet.luau`): on the lobby, top left under Roblox's buttons. A card with your level on a gold
  tile, your title, the XP bar and your coins (they count up when you earn some and the card punches), and under it
  the **QUESTS** and **CODES** buttons. Coins you're paid pop up as gold words beside it ("+5 TAG"; beside the coin
  counter in a round). It slides away to the left when your round starts. LEVEL 10!, DAILY BONUS! and QUEST DONE use
  the round's call-outs (`RoundHud.say`), small ones mid-chase so they never hide the game.
- **Buttons and panels** (`UiKit.luau`): the plastic button grows under the pointer, sinks when pressed and springs
  back; a panel is a big striped card over a dimmed game that pops in, fits any screen, and closes on its X or a tap
  outside. One panel at a time.
- **First-minute hints** (`Hints.luau`; launch checklist): shown once ever to each player (remembered on the save).
  SPACE = DASH (DASH BUTTON = DASH on a phone) as your first match starts, RED = CHASERS. RUN! right after if you're a
  runner, and DASH NOW! under the gold star the first 3 times a perfect dodge's window opens.
- **The speed effect** (`SpeedFx.luau`; design notes, Speed screen effect): the screen's left edge glows red and its
  right edge cyan as you go faster than a runner's sprint (from 26.5 studs/s, full at 35), with a burst on every dash
  that eases back in 0.3 s. Never stronger than 65%. Two plain frames, switched off when there's nothing to see.
- **The runner counter** (`RunnerCounter.luau`; owner 2026-11-10: "add a RUnner counter"): just right of the timer, for
  everyone while a round is on (it slides down at the teleport and back up after the end screen). A cyan RUNNERS line
  level with the timer's status line, a striped indigo plate like the timer's with a little cyan runner whose arms and
  legs swing, the runners still running in big numbers and how many started after them ("5/29"), and a thin bar under
  it like the timer's: cyan for the runners left, dark red for the ones tagged. A tag punches the number and flashes it
  red, shakes the plate, flashes the little runner red, drops a red "-1" off it and shrinks the bar. Once the runners get
  the last-runner speeds the number and bar turn gold and the little runner runs faster; with one left the line says
  LAST ONE! and the plate pulses; with none left it says ALL TAGGED in red and the little runner stands still. The
  numbers are the server's own (`RunnersLeft` and `RunnersAtStart` on Workspace). Layout, colours and effects are
  Claude's picks.
  - On a phone the coin counter sits just above the Dash button and keeps clear of this one (see Phone layout); if the
    two ever met, the bar would step aside.
  - Studio test with 29 bots: it counted 29 down to 0 live, and the game held 60 frames a second the whole match.
- **The fade** (`RoundHud.luau`): black for the teleport, with YOU ARE THE CHASER! or RUN! and the chaser's name; GO! as
  the match starts. The call-outs (TAGGED!, +1 TAG, DODGED!, GO!) stack under the timer, under the shrink countdown and
  SPEED UP! when those show (see Phone layout).
- **The tag feed** (`TagFeed.luau`): top right, below the timer's level, as many rows as fit above the coin counter;
  on a phone, top left (see Phone layout). Restyled 2026-11-10 from the owner's kill-feed picture ("Add these"): each
  tag slides in as a row of dark glass with rounded corners and a neon pink edge with a glow, as wide as its words:
  the chaser's name in white, a little lightning bolt, **TAGGED** in gold going orange (**DASH TAG** for a dash tag),
  the runner's name in cyan. Someone falling off the red gets "Name [bolt] **FELL OFF!**" (orange to red). Rows
  involving you have a gold edge. A light runs along each edge and the bolts flicker. Up to 5, each for 6 s. (The
  picture said ELIMINATED; this game's word is TAGGED.)
- **The victory screen** (`VictoryScreen.luau`): runners win, a gold banner RUNNERS WIN! slides in with the
  survivors' names and gold coins raining down; chasers win, a dark overlay with scanlines and the glitching words THE
  SWARM HAS OVERTAKEN THE ARENA, and the top chasers by tags (the first chaser marked ALPHA). The coins themselves
  (+30 to survivors) come with the saving step. It fits between the timer and the dash bars (see Phone layout).
- **Dash bars** (`DashHud.luau`): bottom middle. A small DASH word, one thin square bar per charge, and the seconds until
  the next charge. Full bars glint; refilling bars pulse; a refill pops and flashes; pressing with no charge flashes the
  outlines red and shakes the bars.
- **SPEED UP!** (`SpeedCallout.luau`): gold letters with a sweeping shine, rocking, over a blue plastic tag with the old
  and new speed (e.g. "22 → 25"). Small and low, just above the dash bars (owner 2026-11-10: "can u put the increase
  speed, notif smaller and low"; drawn at 70% of the other pop-ups, was about a third of the way down).
- **Phone Dash button** (`DashButton.luau`): where the Jump button was. A gold plastic button with a big animated arrow
  pointing left and the word DASH, with nothing behind it (owner 2026-11-10: "can u getv rid of that grey background
  panels"; it used to sit on a striped indigo plate). It breathes while a dash is ready, goes grey with a countdown
  when empty, and two pips show the charges.
- **The coin counter** (`CoinHud.luau`): on the right, just below the middle (owner: "put the coin ui below the middle
  of the right side"). A gold plastic block with the coin and this round's coins, a shine sweeping across, and a blue
  tag under it with the coins' speed bonus ("+0.4 SPEED"). It slides in for the round and out after it. On phones it
  sits just above the Dash button.
- The panels bob gently and lean as the camera turns.

### Phone layout (`src/client/HudLayout.luau`; owner 2026-11-10: "bro i think you shiuld clean up the mobile ui abit")

Checked in Studio's device simulator (iPhone 7, Galaxy A06, iPad) and on PC, with 12 bots, the busiest moments
(shrink countdown, SPEED UP! and TAGGED! at once) and both end screens. Layout and numbers are Claude's picks.
- **Smaller on a phone** (owner 2026-11-10: "bro the ui is literslly taking up the whole screen"): the whole HUD is
  drawn at 70% of its usual phone size (`PHONE_SIZE` in PlasticUi; on an iPhone 7 the timer is now about a quarter of
  the screen across, 162 pixels, was 231). The Dash button is about the size of Roblox's own Jump button (72 to 96
  pixels, was 101 on an iPhone 7). PC and tablets are unchanged. Checked on iPhone 7 and Galaxy A06 sizes at the busiest
  moment and the end screen: nothing overlaps and no errors.
- **One plan:** each fixed piece (timer, runner counter, coin counter, Dash button, dash bars, tag feed) says where it
  sits every frame, and the others keep clear of it: 8 pixels between pieces, 12 from the screen's sides. A phone is a
  screen whose short side is under 480 pixels. Roblox's safe area (notches) was already kept clear.
- **Pop-ups stack:** YOU'RE IN NEXT ROUND! (lobby only), the shrink countdown, the big call-outs (TAGGED!, GO!, DODGED!), the small ones (+1 TAG) and SPEED
  UP! (low, just above the dash bars) go down from under the timer in that order and never cover each other, the timer
  or the dash bars. On a phone they're drawn at 85% of the (already smaller) HUD. A long one (YOU ARE THE CHASER!)
  shrinks to stay clear of the tag feed and the coin counter, and so does one squeezed in under the others; one with no
  room at all waits its turn (up to 2 s). The call-outs' box no longer cuts off YOU ARE THE CHASER!.
- **Tag feed on a phone:** with the smaller HUD it fits on the right again, 3 rows between the runner counter and the
  coin counter, so the left side is clear for the thumbstick. Only if fewer than 3 rows fit there does it move to the
  top left, under Roblox's buttons, sliding in from the left, each row as wide as the room left of the timer (long names
  end in "..."). Rows are drawn full size on a phone (90% elsewhere). The DASH badge is bigger (12, was 10). The rows
  fade away when the end screen comes in.
- **Coin counter on a phone:** just above the Dash button; if that would bring it up against the runner counter,
  it's drawn a little smaller between the two. The coin that flies to it when you pick one up now lands on it (it landed
  58 pixels too high).
- **End screen:** fits between the timer and the dash bars, smaller if it must be. On a phone it lists the top 3
  chasers, and the runners' banner stays clear of the coin counter and the Dash button. The survivors' names get two
  lines, as many as fit, then "+7 MORE" (they used to run off the end of one line).
- **TEST BOTS panel:** top left (see Studio bots), out of the thumbstick's way, with bigger buttons and a padded touch
  area.
- **Bigger small words:** the shrink countdown's second line (22, was 20), the coin speed tag (19, was 17), the DASH
  word over the bars (17, was 16), the frame-rate line (15, was 14).
- **Landscape only:** a phone can't turn the game to portrait.
- Each HUD script costs well under 0.1 ms a frame (Studio's script profiler); every test held 60 FPS.

## The lobby's show pieces

Built 2026-11-13. The server makes the parts and publishes the numbers; every screen draws on them itself and switches
all of it off while you're in a round (you can't read it from down there).

- **Leaderboards** (`src/server/Leaderboards.luau`, `src/client/LobbyBoards.luau`; `Config.Boards`): six glass boards
  in a ring in the lobby's middle, facing out: MOST TAGS, SURVIVOR WINS, LAST MAN CLUTCHES, LONGEST STREAK, MOST TAGS
  IN A ROUND, TOTAL COINS EARNED. Each shows the top 10 of everyone who's ever played; gold, silver and bronze ranks,
  your own row in cyan, rows pop when they change. The players in your server are mixed in with their numbers as they
  are right now, so a tag shows at once. Each board is read from Roblox's storage in turn (one every 25 s), numbers
  are written when they've gone up and when a player leaves, and they only ever go up. A Studio test ranks only the
  players in the test.
- **Pedestals** (`src/server/LobbyExtras.luau`): gold, silver and bronze, with statues of the top 3 players in the
  server (by level, then coins) in their own avatars, their names and levels over them. Checked every 20 s.
- **The practice dummy** (`src/client/PracticeDummy.luau`; launch checklist): a red and grey dummy with a knife, in
  a red ring. Step in and every few seconds it glows red, then lunges at you; the gold star shows exactly as in a
  round, and dashing while it shows gives PERFECT DODGE! (2 DODGES IN A ROW!). Too late is TOO LATE!, too early is
  TOO EARLY!. All of it happens on your own screen only: nothing is won, the server does nothing, and nobody is
  bothered by someone else's dummy. Numbers in `Config.LobbyExtras` (Claude's picks).

## Sounds (`src/client/Sounds.luau`; owner 2026-11-13: "add sounds for everything, and dont make them annyoing")

Every sound plays on your own screen, from `Config.Sound` (free licensed sounds from Roblox's library and sounds
built into Roblox). **Nobody has listened to the mix yet:** tune `Config.Sound.VOLUME` and the ids after a playtest.

- **So nothing grates** (owner: "if its the same souns again, adjuts the pitch or temp"):
  - the same sound never plays the same way twice running: each time its pitch and speed move a step (up to 3 to 10%
    either way, by sound), never the same step as last time;
  - a sound that keeps coming gets quieter each time (down to 45%), and one asked for again within a few hundredths
    of a second is skipped;
  - other players' tags, slashes, dodges and falls are only heard within 90 studs, quieter with distance.
- **The round:** a whoosh at the fade, a low sting if you're the chaser, a rising whoosh at GO!, a thud on a tag (and
  a low whomp when it's you), slashes, your dash (and a soft click with no charge left), the perfect dodge, a fall,
  a soft rise on SPEED UP!, the win and the loss.
- **The shrink:** 3, 2, 1 ticks each a step higher; shrinks 1 to 3 thud lower each time, later ones slam, and the
  strip crumbles away.
- **The clock:** the match's last 10 s tick, rising as it runs out; the break's last 3 s tick.
- **Last man standing:** a bass drop for everyone in the round, then the last runner hears a heartbeat (lub-dub).
- **Coins:** each one you pick up is a note higher while you keep picking them up within 3 s (do re mi...), with a
  soft thud under it. Coins paid to you chime up the scale; a level, a finished quest, the daily bonus, a code and
  your round's card each have their own little run of notes.
- **Buttons:** a soft tick under the pointer, a click when pressed, a pop when a panel opens or closes, a low thud
  for a button that can't be pressed.
- Each sound is fetched when the game starts, so the first tag isn't silent; 3 copies of each can overlap.

## The end of a match (`src/client/Celebrate.luau`, `BotAnim`)

Design notes: "Survivors celebrate, infected collapse or emote". While everyone is held still, the winning side
cheers or dances and the rest sit down (Roblox's own R6 emotes, `Config.Celebrate`). It stops when the round sends
everyone back to the lobby. Bots do the same.

## Frame rate (owner 2026-11-09: "can u adjust the game so its has a consistent 60 fps")

Roblox draws at most 60 frames a second, so the aim is every frame on time. What was changed, from measuring a Studio
test with 29 bots (Roblox's script profiler and frame times):
- **The halftone dots** were the biggest cost: one small round Frame a dot, about 640 on screen (2,100 in all) resized
  15 times a second. They're now drawn from one picture (`Config.Ui.DOT_SHEET`, 32 steps of the wave on an 8x8-dot
  tile; source `uploads/ui/HalftoneSheet.png`), a few tiles a panel, and the wave moves on by picking the next step.
  Same look, about 50 pieces instead of 2,100, and the screen's drawing time fell by about 2.5 ms a frame.
- **The coin counter** read its own position every frame, which made the whole screen lay itself out again; it now
  does that only while a coin flies to it, and does nothing while no effect is playing.
- **Coins on the floor:** their glow, floor light and ring change 20 times a second instead of every frame.
- **Chaser outlines** are set once instead of every frame (only the just-tagged flash changes each frame).
- **Studio bots** think every other frame (a dashing bot every frame), because a Studio test runs the server and every
  bot on the same computer as your screen.
- Screen scripts went from about 150 to about 65 ms of work a second.
- **Measured after** (Studio, 29 bots, a whole round from the teleport to the end screen): 60 FPS nearly every second;
  about 3 frames in 100 took a little longer (20 to 30 ms). A catch of about 0.2 s was seen once as the first shrink
  warning appeared. The shrink's parts are now built when the game starts and reused, and a 29-bot test showed no
  catch at either warning or cut (worst frames 24 to 31 ms).
- **Built 2026-11-13 with the same rules** (not measured in Studio yet): the wallet, panels, payout card, hints and
  speed effect build their pieces once and only move them; a closed panel or a hidden card does nothing each frame;
  the lobby's boards and plates are switched off in a round; name tags only change their words when what they say
  changes; sounds reuse 3 copies each; the practice dummy does nothing when you're in a round or far from it.
- **Testing it:** Studio's own frame rate is lower than a real game's, because the server and the bots run on your
  computer too. A short slow patch now and then in Studio can also be Studio itself (saving, plugins); a published
  game with real players is the fair test.

## Studio test keys (`src/client/DevKeys.luau`, Studio only)

| Key | Does |
| --- | --- |
| 1 / 2 / 3 | Become a Runner / Chaser / Last runner |
| T | Fake a tag (everyone speeds up) |
| Y | +5 stars |
| 0 | Back to the start |
| U | Pretend to be on a phone (sprint always on, Dash button shows) |
| N | Skip ahead in the round: end the intermission now, or end the match now |

## Still needed from the owner

- Publish the place (File > Publish to Roblox) so the live game gets the latest code, animations, the knife and the
  coin. The knife's effects live on the Bloomblade model in ServerStorage, so they're only kept once the place is
  saved or published.
- The live game's server size is 30 players (set 2026-11-09, owner: "max players is 30"; it was 50).
- A playtest with friends: tagging between real players (Chrono's part of the check) can only be tried with 2+
  people. Studio tests used the bots.
- **Everything built 2026-11-13 still needs its first Studio test** (saving, rewards, quests, codes, the bounty, live
  bots, the lobby's show pieces, sounds, the wallet and panels, the payout card, hints, the speed effect). It was
  written and read through twice, but the PC couldn't be reached to run it.
- **Game Settings > Security > "Enable Studio Access to API Services"** only if you want to test saving in Studio
  (and set `Config.Data.STUDIO_SAVES = true` for that test). The live game saves without it.
- **The Robux rerolls:** make three developer products (20, 40 and 90 Robux) on the Creator Dashboard and put their
  ids in `Config.Quests.REROLL_PRODUCTS`. Until then that button stays hidden.
- **Codes:** RELEASE (250) and TAGRIVALS (100) are Claude's picks; change them in `Config.Codes.LIST`.
- **Listen to the sounds** and say which are too loud, too quiet or wrong.

## Notes for later

- **The knife's own effects:** the export's effect textures (`vfx_textures/`: petals, blossoms, flares, crescents,
  rays) weren't in the project files, so the coin's white pictures and Roblox's fire stand in. Once they're uploaded,
  swap the texture ids at the top of `uploads/knives/make_bloomblade_fx.luau` (run it again) and `src/client/TagFx.luau`.
  Not built yet: the slash arcs and light rays (Beams), the charm swinging, the finisher.
- **Music:** there's none yet (lobby, match, last man). Sounds are in; see Sounds.
- **More maps** (owner asked 2026-11-13): Claude advised one map at launch. Variants of the square (a round modifier
  such as Tiny Arena or Ice Floor, or a different floor and sky) are cheap to add after launch as weekly updates.

## Not built yet

The shop and everything it sells (cosmetics: knife skins, trails, afterimage colours, tag effects, emotes, crates,
lucky deals; left out on purpose, owner 2026-11-13), the lobby's shop booths, music, the Robux rerolls' products,
golden star drops and round modifiers (ideas in the design notes).
