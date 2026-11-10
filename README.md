# Tag Rivals

A fast infection tag game for Roblox: one shrinking circle arena, dashes, and a swarm of chasers.

- Design notes (source of truth): the project file `tag-rivals/design-notes.md`
- What's built so far, in plain words: [docs/BUILD_NOTES.md](docs/BUILD_NOTES.md)

## Run it (owner PC)

1. Open a terminal in this folder and run `rojo serve`. It serves on port **34873** (Huss Zero uses 34872, so both can run at once).
2. In Studio, open the Tag Rivals place, then Plugins > Rojo.
3. Set the port box to `34873` (address stays `localhost`) and click Connect.
4. Press Play. The Output window should show `[Tag Rivals] server scripts loaded` and `[Tag Rivals] client scripts loaded`.

Only the Tag Rivals place (place id 103953226550190) can connect to this server, so Tag Rivals code can't be synced into
another game by mistake. If the game moves to a new place, change `servePlaceIds` in `default.project.json`.

Tools are pinned in `rokit.toml` (Rojo 7.7.1, StyLua 2.0.2, Selene 0.28.0).

## Controls

| | PC | Controller | Phone / tablet |
| --- | --- | --- | --- |
| Move | WASD | Left stick | Thumbstick |
| Sprint (not backwards) | Hold Shift | Hold L2, or click L3 | Always on |
| Dash | Space | A or R1 | Dash button (bottom right) |
| Steer (turn the camera, in a round) | Move the mouse (on the lobby: right-drag, free mouse) | Right stick | Drag the screen |
| Stab (chasers) | Left click | | |

No jumping. 2 dash charges, each refilling in 1.5 s.

Studio-only test keys: `1` Runner, `2` Chaser, `3` Last runner, `T` fake a tag (speed-up), `Y` +5 stars, `0` reset,
`U` pretend to be on a phone, `N` skip ahead in the round. A Studio play-test adds test bots, so one person can play a
whole round; the TEST BOTS panel at the top left of the screen sets how many (0 to 12).

Tagging is automatic: a chaser who gets close enough to a runner slashes their knife and the runner is tagged. On a
computer a chaser can also left-click to stab straight ahead (a little further reach).

All movement numbers are in `src/shared/Config.luau`. The animations in use are KeyframeSequences in
`ServerStorage > Animations` (spares in `Animations_SavedForLater`; full list in docs/BUILD_NOTES.md). Their uploaded
ids go in `Config.Anim`; until then they play in Studio only.

## Layout

| Folder | Goes to |
| --- | --- |
| `src/shared` | ReplicatedStorage.Shared |
| `src/server` | ServerScriptService.Server |
| `src/client` | StarterPlayer.StarterPlayerScripts.Client |

`archive/` holds an earlier movement draft, kept for reference only (not synced into the game).
