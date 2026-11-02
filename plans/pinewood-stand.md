# The whole Pinewood choppable: a stand of trees that wake when you come near

Asked 2026-10-31: could every tree in the Pinewood be choppable? Doing it the plain way (all of
them as ResourceNodes) roughly doubles the world: a choppable tree is ~29 nodes (15 meshes, 3
particle emitters, 2 sound players, a collision shape, a label, a rubble MultiMesh), and the
Pinewood's backdrop is ~970 trees. So instead: every tree is drawn as a cheap MultiMesh copy, and
the few near you are swapped for real choppable trees. Walk away and they go back to copies.

## Where it stands today (counted 2026-10-31, headless)

- **Backdrop (not choppable):** `scenes/biomes/pinewood.tscn`'s `SceneryScatter`, three canopy
  layers: 582 `canopy_pine`, 275 `canopy_pine_young`, 116 `canopy_birch`. One MultiMesh per layer
  per 32 m cell, a box per trunk in one StaticBody for collision. Placement is seeded, and a
  rejected spot doesn't shift the rest (every random number is drawn before the checks).
- **Choppable:** ~225 pines and birches from the map editor's forest patches (`forest`,
  `forest_spot1`-`7` in `data/layout/hearthvale.json`), placed by `NodeSpawner` and saved as
  `node:<save_prefix>_<n>`. The backdrop keeps 2.2 m clear of them.
- **The world:** 36,055 nodes, 16,428 MeshInstance3Ds, 1,364 particle emitters (`perf_census.gd`).

## The catch: the backdrop trees aren't the choppable ones

The canopy models are their own simpler meshes (`make_models.py`, "forest scenery"), drawn 1.45-2.2x
size: the backdrop pines stand 12-18 m, the choppable pine about 10 m. ResourceNodes are never
scaled (the notch, the fall and the physics assume size 1). A swap from one to the other would be
seen. So the stand draws **the choppable trees' own meshes, at size 1**, in all their shape
variants. The forest will look different: shorter, and in the choppable trees' look. Phase 1
shows it in screenshots before anything else is built on it.

## Plan

Branch `stand` off `main`, one commit a phase. (Main's working copy has a rewritten
`docs/TODO.md` and touched `.import` files: leave them out of these commits.)

1. **The stand, drawn, and in the map editor** (asked 2026-10-31: the editor must know about it).
   A stand is a map editor patch: tick **Stand** on a wood patch. The bake picks every tree's
   spot and writes it into `layout.tscn`; the game only draws them. Built 2026-10-31:
   - `ForestStand` (scripts/forest_stand.gd, a SceneryScatter): `place()` (the bake) picks up to
     the patch's count inside its polygon or ring, `spacing` apart (3.5 m, so a felled tree has
     room to fall), clear of what's there, thinning over its last `fringe` metres. The trees are
     baked as lists (`ids`, `spots`, `yaws`, `kinds`, `looks`), so the game places nothing and the
     editor's dots are exact. Each tree's key is `<patch id>_<draw number>`, not its placed count:
     moving something drops only the trees it now covers. Looks are the model or one of its 8
     variants, picked like NodeSpawner's (a shape family per 14 m cluster).
   - Drawn from the trees' own `Body_*` meshes (`copy_mesh`: one mesh per look, a surface per
     material), a MultiMesh per look per 64 m square, plus a box per trunk (the kind's own shape).
   - `tools/bake_layout.gd` `_stand()`: a stand patch's variants found by model name
     (`models/variants/<model>_vN.glb`), every tree in `baked.json` (the editor's dots), and a
     keep-clear marker per trunk for any patch after it.
   - The editor (`patches.js`): a Stand box on wood patches, a Fringe field, "Stand" in the label.
   - The Pinewood's big `forest` patch is a stand: 1000 trees (pine 2.4 : birch 0.6), fringe
     20 m. Its 139 old trees are gone; the 7 spots stay ordinary patches. `pinewood.tscn` lost its
     three canopy layers (ferns, mushrooms, grass stay).
   - Counted headless: 1000 trees, 242 MultiMeshes, 484 surfaces (the old backdrop was ~180
     single-surface MultiMeshes); 1000 trunk boxes. `test_layout` knows stands (and no longer
     trips on the walkway line's missing model).
   Stills taken (`docs/images/graphics/stand_before/`, `stand_after/`); the new look kept
   (2026-11-01).
2. **Wake and sleep.** Built 2026-11-01: `ForestStand._process` / `_check` / `_wake` / `_sleep`,
   trees filed in 16 m squares; a hidden copy is a zero-sized instance and its trunk box is
   switched off. `ResourceNode.is_busy()`: 6 s after a hit or a crush, 12 s after it breaks (the
   fall, logs and sinking play out on the node). A headless MultiMesh doesn't keep instance
   transforms, so the stand keeps its own record of which copies are drawn (`copy_shown`). Every 0.25 s the stand looks at the trees in the cells around the player.
   A tree within `WAKE_RANGE` (14 m) wakes: its copy is hidden (instance transform zeroed) and a
   real `pine_tree.tscn` / `birch_tree.tscn` is placed on the spot with the same yaw, variant and
   theme look, `save_id` = its key. A tree farther than `SLEEP_RANGE` (20 m: the gap stops
   flicker at the edge) goes back to a copy, unless it's busy (falling, shaking, a fresh notch).
   No more than `WAKE_PER_FRAME` (2) are made in a frame, so a jog into the forest doesn't hitch.
   A cap of awake trees (~40) as a safety net.
   Check: a new headless `tools/test_forest_stand.gd` walks the player through the forest and
   checks the copies hidden equal the trees awake, and that nothing is ever both or neither.
3. **Remembering a sleeping tree.** When a tree goes to sleep, its state (`to_dict()`: hits
   left, the notch, the respawn time left) goes to `SaveGame` straight away. That needs a new
   `SaveGame.store(key, dict)`, because a freed node only keeps what was saved last time. The
   stand keeps the felled ones in a small list and counts their regrowth down in game time itself.
   It also hooks into `Home.skip_to_morning`'s fast-forward and the debug menu's "respawn all".
   A felled tree that's asleep is drawn as its stump (the `Rubble_*` mesh) in a second MultiMesh,
   and one half-notched keeps its notch when it wakes. On load, saved `node:stand_*` entries are
   read without making any trees.
   Check: in the test, fell one, walk away, save, reload, walk back (stump, then regrown after
   its time); sleep through the night; half-cut one and come back.
   Built 2026-11-01: `SaveGame.store()` / `saved_data()` / `forget()` and a `saving` signal (the
   stand writes its felled trees' time left just before a save). A tree that slept untouched is
   forgotten, so the save doesn't grow with every tree you walk past. Home's fast-forward and the
   debug menu's regrow-all reach the stand through the `forest_stand` group.
4. **What reaches past the wake range.** A falling trunk wakes every tree it could land on (within
   its height, toward its fall) the moment it starts to tip, so Dominoes and the crush still
   work. The backdrop's trunk boxes become the stand's own, so the old `SceneryScatter` collision
   for trees goes away. Go through what reads the `gatherable` group: the dog's hints, the home,
   `nature_spots`, `path_lamps` and the debug menu. The keep-out lists (lamps, nature spots) take
   the stand's tree spots too, through a `keep_clear`-style group. Ghost outlines for trees above
   your level only show on awake trees, which is fine: you're never close to a sleeping one.
   Check: test_forest_stand fells a tree into a sleeping neighbour; `test_dog`, `test_home`, the
   woodcutting talent bench still pass.
   Built 2026-11-01: with Dominoes, `_break` calls every stand's `wake_along()` before the fall
   (trees within 2 m of a 14 m line wake at once, past the per-frame limit). The trunk boxes were
   already the stand's own (phase 1). Readers: the scenery's keep-out list (ferns, grass) and the
   path lamps' obstacles take the stand's spots; the stand joins `forest_stand` on entering the
   tree, so scenery that scatters first still sees it. The dog's hints (rare looks, faults), the
   debug teleports and `nature_spots` only need awake trees. `talent_model.gd --measure` takes
   the sleeping trees too (1158 trees, was 123). Its level 40 pair is now 16% apart (Old growth
   +36%, Momentum +16%; 11% at `--human=0.7`); left as is: which trees are old growth is seeded,
   and 1 in 40 instead of 30 swung it to 30%. The test checks `wake_along` directly (a real fall's
   direction depends on where you stand), not a whole Dominoes chain.
5. **Measure.** `perf_census.gd` before and after (node, mesh and emitter counts with the whole
   forest choppable). `perf_probe.gd` frame times standing in the forest and jogging through it.
   It runs in a game window, so ask first. Update `docs/TODO.md` and the README's notes.
   Census 2026-11-01 (headless, a fresh Hearthvale, nobody in the forest): 32,313 nodes (was
   36,055), 14,637 MeshInstance3Ds (was 16,428), 947 particle emitters (was 1,364: the 139 old
   forest trees' three each). The whole forest is choppable and the world is smaller than before.
   Awake, a tree is ~29 nodes; at most 40 awake (typically ~20 standing in the forest) adds
   ~600-1,200. The copies have no draw distance and cast shadows, like the old canopy layers.
   `perf_probe.gd` now ends with the stand (`--only=stand`): its middle as played, with every
   tree asleep, with the copies hidden, and a 70 m jog through it. (Two earlier runs with a game
   on the same GPU were unusable.) Frame times 2026-11-01, 1920x1080, nothing else on the GPU:

   | spot | fps | ms | p95 | GPU ms | draws | prims |
   |---|---|---|---|---|---|---|
   | village (reference) | 92.8 | 10.8 | 13.4 | 9.2 | 1825 | 3.95 M |
   | Pinewood trail | 87.0 | 11.5 | 15.8 | 10.6 | 1416 | 6.22 M |
   | stand middle, 13 awake | 108.2 | 9.2 | 12.4 | 7.7 | 1631 | 5.91 M |
   | stand middle, all asleep | 108.4 | 9.2 | 12.4 | 7.9 | 1583 | 5.97 M |
   | stand middle, copies hidden | 138.6 | 7.2 | 9.8 | 5.7 | 894 | 1.32 M |
   | jogging through (6 m/s) | 93.8 | 10.7 | 22.4 | 7.7 | 1138 | 5.61 M |

   The forest costs about what the village does. Awake trees cost nothing measurable over
   copies; the copies themselves are ~2 ms of GPU (4.6 M of the triangles: no draw distance,
   shadows). The jog's p95 of 22 ms is the waking (2 trees a frame); no long hitch. Left as is;
   if needed later: a draw distance or shadow cut-off on the copies, or a lower-poly far look.

## Later (not in this plan)

- **Fold the map editor's forest patches into the stand**: one system for every Pinewood tree,
  the patch's density and pine/birch mix set in the editor. That fixes the TODO's lost
  "core-to-edge slide". Until then, the stand keeps clear of the patches' trees like the backdrop
  does now.
- **Other woods** (the orchard, the lone oaks, the Frostpeak pines) could use the same stand.
- **Taller trees**: if the forest looks too short, a big-pine variant baked to the old backdrop's
  height (a choppable tree of its own, maybe old growth with more logs).

## Open questions

- **The forest's new look** (phase 1): the choppable trees' look at size 1, in place of the tall
  dark backdrop pines. Pick from the stills before going on.
- **Level gate:** pines need Woodcutting 25, so most of the forest stays locked early. Meant, but
  a lot of ghost-outlined trees in one place could feel like a wall.
- **Dense chains:** with trees ~3.5-7 m apart, Dominoes fells more neighbours than in the patches.
  Tune `CRUSH_SHARE` after a playtest.
