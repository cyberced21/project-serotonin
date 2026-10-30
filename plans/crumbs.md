# Crumbs: mining that digs in

## Why

Rocks and ore walls break into pieces that are too big: a wall piece is ~40 cm, a copper rock's
flakes 20–30 cm with 40–60 cm slabs inside, and when a rock shatters every slab it has left is
flung at once. The pieces are thrown as physics bodies with a box the size of their bounds. A box
born overlapping the terrain (rocks are sunk a few cm) or the wall's other pieces is shoved out
hard or falls through the world.

The goal: every swing digs in and takes out a pickaxe-sized bit of rock, and what comes off
crumbles into dust rather than tumbling through the world.

## Decisions (grilled 2026-10-30)

1. **Crumbs of ~10–15 cm.** Today's pieces stay as **blocks** (so saves and rules carry over).
   Each block is baked into **crumbs**: a skin of ~13 cm crumbs on the block's exposed faces plus
   one **core** crumb for the rest. Rocks: skin on the outside faces. Wall blocks: skin on the
   face side. A block with no outside face (deep in a rock) is a core alone.
2. **A swing = the struck crumb + neighbours.** The crumb nearest the hit, plus 1–3 linked skin
   crumbs (a better pick, or a Sharp! hit, takes more). Neighbours are never cores. Striking a core
   crumbles its block.
3. **Blocks crumble.** Once a block has lost its share of crumbs (`crumble_at`: walls ~⅓, rocks
   more), or its core is struck, what's left of it crumbles to dust. Support, collapse, the fault
   and loose slabs still work on blocks.
4. **No physics debris for rock.** A crumb coming out pops a few cm out of the dent as a small
   lump that falls on a scripted arc and breaks into a dust puff. Nothing is simulated, so nothing
   clips. (Trees keep their physics chips and logs. Ore pickups are unchanged.)
5. **The end of a rock crumbles away.** Swing counts stay as today (copper ~6). On the last swing
   the rest of the rock cracks, slumps and sinks into a dust cloud, leaving its rubble pile. No
   flying slabs.
6. **Big breaks slump to dust.** The fault cluster, undercut collapses and the wall's loose slabs
   keep their triggers. The cluster (its exact crumbs, cut out of the mesh) sags out of place for
   a beat, then collapses into a big dust cloud and gravel, with today's rumble.
7. **Crystal.** Its prisms stay whole and snap off where struck, then break into glittering shards
   that fade. The stone base never breaks, so it gets no crumbs.
8. **Pace.** Rocks: today's swing counts per ore. Walls: a 0.5 m layer takes ~60–80 swings (today
   40–60), about 2 swings a block.
9. **Leftovers.** A dust puff per crumbling bit; a few gravel specks settle at the foot and fade
   after ~20 s. The rock's rubble pile stays as now.
10. **Budget.** Same frame rate. Crumbs are data, not nodes: each rock stays one draw call.
    ≤ ~250 crumbs a rock, ≤ ~800 a wall layer. Load time may grow by about a second (measured).
    Wall panels further than NEAR (14 m) draw today's block mesh. Only near ones draw crumbs.

## Shape of the code

- **Bake (Blender, make_models.py):** after a model's blocks are cut (same seeds, same rng, so the
  blocks don't change), each block is cut again round its crumb seeds by a separate rng. The crumbs
  go to their own glb (`<model>_crumbs.glb`; walls one per layer), read only by code and merged
  into one mesh at load (cached per model, as the wall panels already are), with UV2 = (crumb + 1,
  block + 1). Crumb data goes in the `.pieces.json` (`crumbs`: block, centre, volume, core, links).
- **Shader:** a mask by crumb. Rocks use instance uniforms (`pieces_gone` + two more vec4s, 288
  bits). Wall layers use a small mask texture on the layer's own material. Ore stays per block
  (UV2.y).
- **ResourceNode:** crumbs drawn by the merged mesh; the Chunk_* blocks stay as invisible
  stand-ins for aiming and the hull. Pace from gone volume. Save the gone crumbs (old saves: a gone
  block = all its crumbs gone).
- **Dust:** one helper for a crumb's pop (`Crumble.bit`), a cluster's slump (`Crumble.slump`, its
  crumbs cut out of the merged mesh by id) and fading gravel. It replaces `_throw` for rocks and
  walls.
- **OreWall:** a crumb mesh per (template, layer) for near panels, a mask texture per layer, block
  crumble at ⅓, save per layer {blocks gone, crumbs gone}, old saves loading as blocks.

## Phases (commit each)

1. **Plan + pace bench.** `tools/bench_mining_pace.gd` (headless): strikes each ore rock at random
   visible points until it breaks, and digs a wall layer, and reports the average swings. The
   baseline from main goes in this file.
2. **Dust, not physics.** Crumble helper; rocks and walls stop throwing bodies. Pieces pop and
   crumble, the shatter slumps, the fault, collapses and slabs slump, crystal glitters, gravel
   fades. Works on today's pieces: this alone fixes the clipping.
3. **Rock crumbs baked.** make_models.py crumbs for copper, iron, coal and gold (crystal: blocks
   only). The `.crumbs.res` step, and a check that the blocks didn't change.
4. **Rocks dig in.** Crumb mesh and mask, struck crumb + neighbours, block crumble, support, ore
   spill, save + migration. `shatter_at` and the knock retuned to the baseline swing counts.
5. **Wall crumbs.** Bake the 4 panel templates' crumbs (blocks unchanged). OreWall near/far
   meshes, mask texture, crumble at ⅓, slabs, save + migration. Tuned to ~60–80 swings a layer.
6. **Check + polish.** test_ore_wall, test_quarry, the bench, close-ups (ore_closeup /
   wall_closeup), load time and vertex counts, docs/TODO.md, as-built notes here.
7. **Performance pass** (asked for 2026-10-30, after the crumbs): the world has grown, and frames
   dip where many actors are on screen. Profile the busy spots (village, quarry, mine) headless
   for draw calls, node counts, per-frame scripts and lights; then cut what costs most
   (visibility ranges, merged or instanced meshes, `_process` that can sleep, shadow casters).
   Before/after numbers go here.

## Baseline (main, 2026-10-30, tools/bench_mining_pace.gd, 12 rocks each, 4 wall layers)

| Ore | Swings to break (mean, min–max) |
|---|---|
| copper (rock) | 5.3 (4–7) |
| iron | 10.8 (8–14) |
| coal | 8.6 (6–11) |
| gold | 11.0 (8–15) |
| crystal | 11.3 (10–14) |
| wall layer 1 | 31.0 (25–39) |

The bench's swings land at random, so a wall layer reads lower than the 40–60 the ore-walls plan
guessed. Target after crumbs: rocks within ±1 swing of these, wall layer ~1.5–2× (≈ 50–60).
