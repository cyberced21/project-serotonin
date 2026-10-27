# Themed nodes: the art style baked into generation

Agreed on 2026-10-26. Branch `themes`, off `tools` (the `tools` PR, #4, was still open). One
commit per phase. **Status: all 7 phases done 2026-10-26**, unpushed and unplayed (judged from
screenshots in `docs/images/themes/`). Open items are in docs/TODO.md ("Themed nodes").

What changed from the decisions below while building:
- No squash/stretch at load time (non-uniform scale fights the pieces' physics); proportions come
  only from the shape families' recipes in Blender.
- Three instance uniforms, not two: `theme_c` gives the leaves their own colour (autumn, value,
  saturation) and a rare look's shimmer.
- Scenery is dressed with the same instance uniforms, which Godot applies per MultiMesh: each
  32 m cell of a layer wears one look. No `INSTANCE_CUSTOM`.
- Rare looks are Ancient moss, Lightning-scorched, Frost-touched and Gilded (they fit trees and
  rocks alike), rolled by `ProcgenMap` so the preview tool can list them.

## Why

Each rock and tree is now designed by a hand-written Blender builder (`copper_verdigris`,
`iron_columns`, `tree_round`…). Procgen's variety only rebuilds that same builder from four shifted
seeds (`variants()` in `tools/blender/make_models.py`), and a node picks one by its save id. Biome
kinds change how many nodes appear, not how they look, so a copper rock in Frostpeak looks just
like one in the Pinewood. The look should come out of the generation: plenty of variation, but
every rock in a place clearly belonging to the same family and the same place.

## Decisions

| Area | Decision |
|---|---|
| What a theme is | A **recipe of ranges**, not a model: shape (roundness, squat/tall, lumpiness), colour shift, surface dressing (moss, lichen, snow, wet, dust, soot), vein brightness. Generation samples inside the ranges. |
| Two layers | **Identity** is fixed per resource and themes never touch it: copper's green glint and flaky pieces, iron's columns, coal's plates, gold's geode, crystal's shards, each tree's bark and cut wood. **Dressing** comes from where the node grows. A copper rock always reads as copper. |
| Theme axis | **Per biome kind** (Birch Grove ≠ Old Growth). The kind is already rolled per seed, so seeds differ through it. |
| Seed hierarchy | World seed → kind's theme → **cluster** → node. Nodes close together share a cluster seed, so they look like siblings (same base shape family, similar dressing), with small per-node jitter. |
| Where it runs | **Hybrid.** Shape is baked in Blender (the pieces and `pieces.json` come from there, and mining depends on them), with **8 variants** per ore rock and choppable tree instead of 4. Dressing is applied at load time through shader parameters plus a slight squash/stretch. No runtime mesh generation. |
| Shader | Theme parameters packed into two `instance uniform vec4`s in `node_surface.gdshaderinc` (e.g. `theme_a` = moss, snow, wet, dust; `theme_b` = hue shift, value, saturation, vein brightness). Snow sits on upward world-space normals; moss uses the baked crevice shade already in vertex colour; wet darkens and smooths below a height. MultiMesh scenery reads the same values from `INSTANCE_CUSTOM`. |
| Mining and chopping | Unchanged. The piece mask and `trunk_carve.gd` work on whatever mesh they're given; fresh insides and cut wood are identity, so they stay bright and readable. |
| Saving | Nothing new to save: the theme comes from the seed, the site's kind and the save id. |
| Scope | Ore rocks, choppable trees, and the scenery around them (scenery rocks, bushes, background canopies), so a biome hangs together. Building stone keeps its look. |
| Rare themed nodes | One-off looks, 1–3 per seed (e.g. crystal-crusted copper, a lightning-struck oak, an ancient moss-heavy boulder), with a small bonus (extra drop or XP). |
| Load time | Procgen is 4–7 s per seed; theming must add well under a second. Measured in phase 1 and wrap-up. |

## Dressings (first pass, tuned by eye)

| Biome · kinds | Rocks | Trees |
|---|---|---|
| The Clearing · Meadow, Hollow | Baseline: light moss, grass-green lichen | Baseline |
| The Pinewood · Pine Forest | Heavy moss on tops and north faces | Moss climbing the trunk base |
| · Birch Grove | Light, pale lichen, brighter stone | Paler bark, golden-green canopy |
| · Old Growth | Deep moss, ferny crevices, darker | Gnarlier, taller, lichen, darker canopy |
| Goldmeadow · all | Sun-bleached, warm, dry, little moss | Warm canopy, a hint of autumn in Orchard Downs |
| Stillwater · all | Wet dark bottoms, algae line, smoother | Darker damp bark, moss line |
| Greystone Quarry · all | Pale quarry dust, no moss, sharper | Dusty, sparse |
| Frostpeak · all | Snow caps, frost-blue cast, darker stone | Snow on pine crowns, cold canopy |
| Hearthvale · all | Tidy, worn smooth, a little moss | Baseline, well kept |

## Terms

- **Recipe**: the ranges a theme or a shape family samples from.
- **Identity / dressing**: what makes a resource recognisable (fixed) / what the place adds (themed).
- **Cluster**: nodes within a few metres of each other in one spawner; they share a seed.
- **Instance uniform**: a shader value set per object (`set_instance_shader_parameter`), so one
  shared material can look different on every node.

## Phases

1. ✅ **Tracer: copper in two kinds.** A `NodeTheme` resource (`data/themes/`), the seed hierarchy
   with cluster seeds in `NodeSpawner`, the two theme uniforms in the node shader, applied to
   copper only, with Pine Forest and Frostpeak dressings. Load-time measurement. Screenshots of the
   same rock in both kinds (`tools/ore_closeup.gd`) added to docs/images.
2. ✅ **Every rock, every kind.** All five ores and every kind's dressing from the table; Quarry dust
   and Frostpeak snow checked against the quarry levels and foothills.
3. ✅ **Shape recipes.** Ore builders in `make_models.py` take ranges instead of fixed values; 8
   variants each; a cluster picks its variants from a shared shape family (picked by cluster seed,
   not just by save id). `VARIANTS` in `procgen_population.gd` follows.
4. ✅ **Trees.** Tree builders take shape ranges (lean, crown size, gnarl); 8 variants; bark and
   canopy dressing through the foliage and palette paths; snow on Frostpeak pines; the felled log
   keeps its tree's dressing.
5. ✅ **Scenery.** Boulders, bushes and background canopies themed via MultiMesh custom data, so the
   ground round a node matches it.
6. ✅ **Rare themed nodes.** The one-off looks, 1–3 per seed, with their bonus; shown in the debug
   menu's Procgen tab and the preview tool's output.
7. ✅ **Wrap-up.** README, docs/TODO.md, a graphics tour shot per kind, load-time check against
   phase 1's numbers.

## Verifying

`tools/ore_closeup.gd` for single rocks (struck, so the fresh inside is checked against the
dressing), `tools/procgen_preview.gd` across several seeds, and the graphics tour per kind.
Windowed runs on `--screen 1`; `--save-root=user://tmp` on headless runs, and the real save is
backed up around game runs.
