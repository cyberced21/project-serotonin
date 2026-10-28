# Calm feel: unhurried movement, softer gathering

Chunk 2 of [cozy.md](cozy.md). Grilled 2026-10-27. Branch `calm` off `main` (doesn't need the mood
pass).

Status: **all 7 phases built** 2026-10-27 on branch `calm`; checked headless only (the test suite
passes; a headless walk in the main world measures stroll 3.8 m/s reached in 0.28 s, stopping in
0.22 s; jog 5.5 m/s in 0.42 s, stopping in 0.32 s; a jump is 0.52 s in the air). Merged to main and
released v0.3; **playtested 2026-10-28**, approved.

### Notes from building

- Fishing had its own hit-stops and shakes; folded into phase 4 (light shake on a catch only).
- The ring road's whole obstacle course went with the trial (it was built for wall runs and hops);
  the gully bridge stays. Road models kept in `models/road/` for possible decoration later.
- Without hit-stop stretching it, the tool's stuck moment is now `bite_hold` 0.1 s (was 0.06).
- Removing `Juice.hitstop` also fixes it silently resetting the debug menu's time scale.
- `tools/talent_model.gd` and the bench bots use `walk_speed` for travel time, so their yields per
  minute shift a little with the slower stroll; re-run before tuning talents again.

## Where we start (2026-10-27)

- `scripts/player.gd` is a parkour controller: walk 4.5 / sprint 7 m/s, full speed in about 0.1 s
  (`ground_accel` 45, `ground_friction` 55), bunny-hop speed gain up to 16 m/s, air dash, wall run,
  slide, mantle, a speed FOV widening (`speed_fov_kick` 14°, `slide_fov_kick`) and a wind loop.
- Gathering hits: `Juice.hitstop` (the game freezes for 30–110 ms), `Juice.shake`, `ShakeCamera.kick`
  (the view snaps away from the hit) and an FOV punch, in `resource_node.gd`, `ore_wall.gd`,
  `player.gd`. Settings already has a *Camera motion* slider (`Settings.camera_motion()`).
- Building upgrades (`building.gd`) and the forge cutscene (`forge_cutscene.gd`) shake and freeze.
- A ring-road time trial (`scripts/time_trial.gd`, `scenes/biomes/road.tscn`): gate, arches, medals.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| C1 | Moves | **Calm kit**: walk, jog, jump, mantle, crouch. **Removed**: bunny-hop speed gain, air dash, wall run, slide, the speed FOV widening, the wind loop. Deleted, not hidden (git keeps them). |
| C2 | Speed | **Stroll and jog**: walk about 3.8 m/s, Shift for a relaxed jog about 5.5 m/s. No stamina. |
| C3 | Starting and stopping | **Soft glide**: about 0.3 s to get going, about 0.25 s to settle. Still precise enough to line up a swing. |
| C4 | Hit feel | **A soft thunk**: no hit-stop, no FOV punch; a small camera nudge per hit; a light shake only on the big moments (a tree falling, a rock breaking). Particles, sounds, the tool sticking in all stay. |
| C5 | Popups | **Gentler, same info**: smaller text, soft fade in and out, no bounce or burst. Level-up and biome cards stay but calmer, with softer stings. |
| C6 | Big moments | **Kept, softened**: building upgrades and the forge cutscene keep a gentle shake; no hit-stop freezes anywhere. |
| C7 | Time trial | **Removed**: gate, arches and clock out of the world; the road stays a road. |
| C8 | Under-levelled penalty | **Left for later** (balance, not feel). |

Footstep *sounds* wait for the sound grill (cozy chunk 3); their timing follows the new speeds.

## Phases

One commit each.

1. **The calm kit.** Delete bunny-hop gain, air dash, wall run, slide (crouch stays), speed FOV and
   wind from `player.gd`, and their controls, settings and debug entries (`controls_screen.gd`,
   `settings_screen.gd`, `debug_menu.gd`). Head bob, landing dip and lean stay gentle.
2. **Speeds and glide.** Walk 3.8, jog 5.5, softer acceleration and stopping (ground and air);
   footstep cadence checked against the new gait. Check the bench bots that walk the player
   (`tools/*bench*`, `*playtest*`) still get where they're going.
3. **Soft hits.** No hit-stop in gathering, no FOV punch; per-hit shake to zero, a smaller kick; a
   light shake kept for falls and breaks (`resource_node.gd`, `ore_wall.gd`, `player.gd`, `hud.gd`,
   `landed_fish.gd`).
4. **Big moments.** Building upgrades and the forge cutscene: no hit-stop, gentler shakes.
5. **Gentler popups.** `popup_text.gd`, the level-up banner and perk line, biome cards and stings,
   "Weak spot!" and similar bursts.
6. **No time trial.** Remove `TimeTrial` and its arches/gate from `road.tscn`; `RoadCourse` keeps
   only what other systems use; drop the save key quietly on load.
7. **Checks.** Headless tests and bots pass; a short muted bot walk to confirm movement. Feel is
   judged by playing.
