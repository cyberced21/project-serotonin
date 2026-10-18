# Woodcutting overhaul

Decided 2026-10-16 via /grill-me. Branch `woodcutting-overhaul` off `main`, **after** `mining-overhaul`
is merged into `main` (woodcutting reuses its `SWINGS`, HitFx, ShakeCamera kick, SoundLayers and
`tools/cut_sounds.py`). One commit per phase. Test with the save backed up (headless runs touch
`user://save.json`).

## What we're building

- **Axe swing:** a flat side chop. The axe is pulled back to the right at chest height with the blade
  level, swings right-to-left in a horizontal arc and bites into the trunk side-on at the crosshair.
  It sticks, then yanks out, using the same bite and stick as the pickaxe. It gets its own entry in
  `player.gd` `SWINGS` (ready stance, eased wind-up, kick, quiver).
- **New axe model:** a proper felling axe. It has a longer handle and a wedge head with a bit and a
  poll. The bit sits flat in the cut when it sticks. Villagers on CHOP use it too, with their
  animation unchanged.
- **The notch (live mesh carve):** one notch per tree.
  - The first hit sets its height, clamped to a 0.6–1.4 m band and snapped to a ring row of the trunk.
  - Each hit pushes the trunk's band vertices inward with a V-wedge profile centred on the angle the
    hit came from. Circling the tree widens the notch around the trunk.
  - Depth is stored per angle (around 24 bins). The V opens wider as it deepens.
  - Wood chips fly out of the notch every hit.
- **Felling:** the tree goes at about 65% depth. `max_hits` stays per tree (starter 5, birch 5, oak 7,
  pine 9).
  - When the tree reaches the limit it sways and creaks. The final crack has a short pause before it
    goes.
  - The trunk splits at the notch row. The stump keeps the lower half of the cut, and the trunk falls
    hinged at the notch.
  - It falls **sideways to the player** (left or right, whichever side is clear). It never lands on
    them.
  - Logs pop out on landing, as they do now, then the trunk sinks away. The stump regrows into a full
    tree.
- **Bonus hits:** the weak-point diamond is removed from trees. A hit inside the mouth of the
  existing notch is a **clean cut**: it counts double, gives double XP, throws a big chip and plays a
  sharper sound, like the rocks' crack tips. Hits off the notch count once.
- **Save:** a half-cut tree keeps its notch height, its per-angle depth and its hits left across
  save and reload.
- **Feel:**
  - HitFx tuned for wood: pale chips, bark flakes, a puff of sawdust.
  - Camera kick and tool quiver scaled for the axe.
  - Every hit shakes the canopy and drops a few leaves.
- **Sound:** SoundLayers stacks in `audio/woodcutting/`: thunk, clean-cut crack, creak, fall and
  land, ducked like `ResourceNode._hit_sounds`. These are placeholders cut from the GDC 2026 sampler
  with `tools/cut_sounds.py`, kept easy to repoint at a real wood or foley library later.
  `tools/measure_mix.py` checks the levels.
- **Tree models (render candidates and pick, like the ores):** two candidates per tree (starter,
  birch, oak, pine) plus the axe, in `models/designs/`. Every tree gets:
  - a rounder trunk (10–12 sides) with a root flare and a slight lean or curve
  - a dense ring band at chopping height for the carve
  - pale end grain with growth rings inside the notch and on the stump and log cut faces
  - a few branches into more, smaller canopy clumps
  - bark that flakes off around the notch as it grows (replaces the 4 `Chunk_Bark` slabs)
- **Scenery trees** (`canopy_pine`, `canopy_birch`, `forest`) are restyled to match in the last phase.
  They stay single-mesh and can't be chopped.

## Phases

1. **Axe swing + felling axe.** Add an axe entry to `SWINGS` and a new `axe()` in
   `tools/blender/make_models.py`. The bit should stick flat into the current trees. Swap the
   villagers' axe.
2. **Notch tracer bullet.** Build the starter tree with a 12-sided trunk and a ring band, then add:
   - the runtime carve in `ResourceNode` (ArrayMesh rebuild of the band from per-angle depth)
   - the notch height set by the first hit
   - felling at 65% depth: split at the notch row, stump plus hinged fall sideways to the player
   - removing the weak point from trees

   The other trees keep working as they do now until phase 4.
3. **Clean cuts + save.** Notch-mouth hit detection (double, XP, big chip), notch state in
   `to_dict` / `from_dict`.
4. **Tree designs.** Render two candidates per tree, the user picks, then build all four with end
   grain, branches, canopy clumps and peeling bark. Switch every tree scene to the carve.
5. **Feel.** Wood HitFx, axe kick and quiver, canopy shake and leaves, sway, creak and pause before
   the fall.
6. **Sounds.** Cut the `audio/woodcutting/` layers, wire them up, check them with `measure_mix.py`.
7. **Scenery trees** restyled to match.
8. **Wrap-up:** README, docs/TODO.md (tick "The axe" and "Cracks on trees"), screenshot.

## Out of scope

- Bucking the fallen trunk into logs.
- Carving notches from villagers' swings.
- Better mining sound source material (separate task, see the mining-overhaul notes).
