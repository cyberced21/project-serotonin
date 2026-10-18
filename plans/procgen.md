# Procedural generation: plan

Agreed in a design interview on 2026-10-17. An experiment: everything is on the `procgen` branch
(cut from `main` after merging `woodcutting-overhaul`), one commit per phase. The hand-built world
in `main.tscn` stays as it is.

## Decisions

| Question | Answer |
|---|---|
| What's procedural | A new map from a seed, **plus** model and sound variants |
| Asset variants | Baked **offline** into variant pools; the map's seed picks from them, plus per-instance jitter |
| When the map is built | At **runtime**, every time the scene loads, from the seed |
| Biome layout | A flat **spawn hub**, then a ring of domain-warped **Voronoi** cells, one biome each; harder nodes farther out |
| Special features | Water basins with fish on every seed (hub pond, outer ponds, a deep lake with char) and a **simplified 3-ring quarry** stamp |
| Getting around | **A\*** dirt trails from the hub to every biome and lake, smoothed, painted and lightly graded |
| Size | **512 m**, a mountain rim at the edge, a "Generating…" overlay while it builds |
| Model pools | Ores, choppable trees and big scenery (boulders, bushes, canopies), **4 variants each**, in `models/variants/` |
| Sound pools | Synthesized, **voiced per tree species and per ore**; a new `synth_mining_sounds.py` replaces the GDC mining recordings (this changes the main world's sound too) |
| Getting in | A **Procgen** section in the debug menu (enter, seed, new seed, back) and `--procgen --seed=N` |
| Saves | Each seed has its **own fresh character and save**, `user://procgen_<seed>.json`; the main save is never touched |

Not in scope for now: the village and its buildings, the ring road and time trial, hand-sculpting a
generated map.

## Terms

- **Seed**: one number that drives every random choice; the same seed always gives the same world.
- **Heightmap / control map**: images Terrain3D builds the ground from: height per pixel, and surface
  texture id per pixel (`WorldMap.TEX_*`).
- **Voronoi cell**: the area nearer one scattered point than any other; domain warping bends the borders.
- **Stamp**: a designed height shape pressed into the heightmap (a lake bowl, the quarry terraces).
- **Variant pool**: pre-baked alternatives of one asset that the seed picks from.

## Phases

0. **Setup** ✅: merge `woodcutting-overhaul` into local `main`, branch `procgen`, this plan.
1. **Playable skeleton** ✅: `scenes/procgen.tscn` builds a noise heightmap at runtime (flat hub,
   rolling ground, mountain rim), hands it to Terrain3D, and drops the player in the hub. The
   "Generating…" overlay, the debug menu's Procgen section, `--procgen --seed=N`, and a save per seed.
2. **Biomes** ✅: the warped Voronoi ring, a height profile per biome blended over the borders, the
   control map painted per biome, biome moods, title cards and ambience.
3. **Water and the quarry**: basin stamps with `WaterBody` + `FishPond`; the 3-ring quarry stamp with
   a spiral ramp, mantle stairs on two walls and crystal on the floor.
4. **Trails**: A\* on a coarse grid (slope and water cost) from the hub to every biome and lake,
   smoothed, painted as dirt, graded.
5. **Population**: `NodeSpawner` and `SceneryScatter` per biome, node levels rising with distance
   from the hub. The whole game loop works on any seed.
6. **Model variants**: `make_models.py --variants 4` for ores, trees (trunks kept in the range
   `trunk_carve.gd` expects) and big scenery; the spawners pick a variant from the seed.
7. **Wood voicing**: per-species pools in `synth_wood_sounds.py`, wired to each tree type.
8. **Mining synthesis**: `synth_mining_sounds.py`, voiced per ore, replacing the GDC recordings.
9. **Wrap-up**: README, TODO, a screenshot.

## Verifying

Each phase: a throwaway `tools/_shots.gd` run headless with `--procgen --seed=N` for in-game
screenshots, backing up and restoring `user://save.json` around it, plus a top-down preview image
of the seed's height and surfaces.
