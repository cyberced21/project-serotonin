# Biomes: plan

Agreed in a design interview on 2026-10-14. Everything is on the `biomes` branch, one commit per phase.
`terrain_data/` has never been hand-sculpted, so it can be regenerated freely.

## The map

The heightmap is 512 × 512 m (±256). Today's content sits roughly in x −110…170, z −80…120.
The clearing (0, −4), the village (100, 40), the lake (−16, 74) and the peak (−92, −92) **stay where
they are**, and so does every hand-placed node and its `save_id`.

| Biome | Name | Where |
|---|---|---|
| Clearing | The Clearing | as today |
| Village valley | Hearthvale | as today |
| Lake basin | Stillwater | as today |
| Snowy peak | Frostpeak | as today, NW corner |
| Forest | The Pinewood | north band, z −50 → −180, over the existing pines |
| Quarry | Greystone Quarry | NW, cut into the peak's east flank around (−130, −40) |
| Field | Goldmeadow | SE plain, around x 100…220, z 90…220 |
| Ring road | none (it takes the biome it passes through) | loop at r ≈ 170–200 m, with spurs to every area |

**Hard constraint:** the generator must not move the ground under the clearing, village, lake or any
hand-placed node (their Y values are baked into `main.tscn`). New features only blend in outside a
safe radius. The generator prints every baked node whose ground moved by more than 5 cm.

## Terrain surfaces (control-map texture ids)

| ID | Surface | Colour | Footsteps |
|---|---|---|---|
| 0 | default | grass / dirt / rock / sand / snow bands, as today | as today |
| 1 | dirt path | as today | dirt |
| 2 | gravel road | light warm grey | rock |
| 3 | forest floor | dark moss green with needle-brown patches | grass |
| 4 | field | yellow-green, with wheat-gold crop squares | grass (dirt on the tracks) |
| 5 | quarry | pale dusty stone on flats, banded rock on the walls | rock |
| 6 | crop square | wheat-gold (the field's tracks are id 1) | grass |

- Biome borders are distance to the biome plus noise: ragged, not circles. Slope still wins, so cliffs are always rock.
- `ScatterLayer` gains an `allowed_ids` filter: ferns and mushrooms in the forest, wheat in the field, loose stones in the quarry.

## Greystone Quarry

- A stepped pit carved into the heightmap: **5 levels, about 5 m each, about 25 m deep.** Each level is a terrace ring 8–12 m wide around a floor about 25 m across.
- A spiral haul road down at a walkable grade, painted as path.
- Shortcuts for movement:
  - 2 m mantle ledges cut into some walls, so you can mantle twice in a row (a mantle reaches 2.2 m at most)
  - sheer faces to wall-run on
  - dropping off the edge (no fall damage)
- Leave a flat wall on one or two levels for a future tunnel mouth.
- Props: scaffold planks, a ladder look-alike, a crane frame (`make_models.py`).
- Ore by level (placed by `NodeSpawner`, on the outer half of each terrace):

| Level | Depth | Nodes |
|---|---|---|
| 1 | −5 m | plain rock ×5–6, quick respawn |
| 2 | −10 m | iron ×4 + a few rock |
| 3 | −15 m | coal ×4 + iron ×1–2 |
| 4 | −20 m | gold ×3 |
| 5 | −25 m | **crystal ×2** (new, Mining 40) |

- **Crystal:** faceted violet shards out of a dark rock base, with a soft night glow (`night_glow`). Needs a new palette colour, a model, an icon, an `Items` entry and a pickup model.
- **Smithy tier 4, "Crystal-edged tools":**
  - Costs crystal + gold + coal.
  - Perk: every hit counts for more, so all nodes break faster (a new `TierEffect`).
  - Exception to the hall cap: it needs **hall tier 3**.
  - Needs a tier-4 smithy look (crystal accents on the forge).
- The existing iron, coal and gold nodes stay where they are.

## The Pinewood

- **Canopy:** about 400–600 decorative pine and birch look-alikes, as `ScatterLayer`s.
  - Slightly taller and darker than the gatherable ones.
  - Each trunk gets a slim collision box, so you can wall-run off trunks.
  - Dense at the core, thinner at the edges.
- **About 100 gatherable trees** (about 60 pine, 40 birch, more pine deeper in), from `NodeSpawner`. Clustered around 3–4 glades (15–20 m, with stumps and logs) and along the trail edge, plus some scattered through the canopy.
- A winding 3 m dirt trail from the ring road, past every glade and out the other side, kept clear of trees.
- Ferns and mushrooms as new scatter layers.
- No new tree types.

## Goldmeadow and Farming lite

- Terrain: flat, with gentle 2–4 m swells to slide down. Crop squares with dirt tracks between them.
- Tall swaying wheat scatter (no collision).
- Props:
  - round and stacked hay bales
  - low fences
  - carts
  - a **windmill** landmark with turning sails, tall enough to wall-run
- A few lone oaks.
- **Farming skill:**
  - `&"farming"` as a 4th row in `Skills.SKILLS`, coloured wheat-gold.
  - **Sickle** tool viewmodel with the block fist, and a quick sideways swing (reuses the axe's impact-frame timing).
  - **Wheat** (Farming 1) and **barley** (Farming 15, in the far crop squares) as `ResourceNode`s from `NodeSpawner` (~40). Each takes 2–3 hits, sheds straw flecks, and falls flat when it breaks. Short regrow.
  - Wheat and barley items with icons. **No sink yet.**

## The ring road and time trial

- **The road:**
  - About 1.1 km, 6 m wide gravel (id 2).
  - Long straights and wide bends (radius ≥ 40 m), with banked turns (~1 m) on the tightest ones.
  - Height smoothed along its line, max grade about 8%: one long downhill (forest → field) and a climb back.
  - Rock-wall cuttings through the hills (for wall-runs), and a gully with a short wooden bridge plus an unbridged 5–7 m gap.
  - Spurs to the clearing, village, lake path, quarry rim, forest trail and field tracks, with signposts at each junction.
- **Obstacles** every ~30–50 m, grouped into set-piece sections. Each section has a slower way round, so a botched move costs time but never stops you.

| Prop | Size | For |
|---|---|---|
| Log pile / fallen trunk | 0.8 m | bhop over |
| Low stone wall | 1.1 m | jump or slide-cancel |
| Crate or hay stack | 1.8–2.2 m | mantle |
| Wall-run panel | 3 m × 11 m | one full wall run (1.2 s × 8 m/s ≈ 9.6 m) |
| Wall-run alley | panels alternating left and right, 6 m apart | chained wall jumps |
| Ramp / kicker | 0.8 m rise | launch into a dash or a long jump |
| Low beam / fallen-tree arch | 1.1 m clearance | slide under |
| Gap | 5–7 m, optional bridge | dash across |

- **Time trial:**
  - A start/finish gate near the clearing spur. Running through it starts the timer.
  - About 8 checkpoint arches (`Area3D`) that must be passed in order. The next one glows. Each gives a chime and a split on the HUD (green or red against your best).
  - The run cancels if you go more than 40 m off the road or 20 s pass without a checkpoint.
  - HUD: timer, split delta, checkpoint count.
  - Best lap and best splits are saved.
  - **Medals:** bronze, silver and gold times (tuned after play-testing). Each medal hangs its **banner on the gate**. Purely cosmetic.

## Biome feel

- **`Biome` autoload:**
  - Samples the control-map id under the player about 5 times a second, with 1.5 s of hysteresis.
  - Areas without their own id (clearing, village, lake, peak) are recognised by distance and height.
- **`BiomeMood` resource:** fog density multiplier, fog tint, ambient tint, sun tint and saturation. `DayNightSky` **multiplies** its own per-frame values by the mood (it never overwrites them), blended over about 3 s.

| Biome | Mood |
|---|---|
| The Clearing | neutral |
| Hearthvale | slightly warm |
| Stillwater | cool, light low mist |
| The Pinewood | darker ambient, green-tinted denser fog |
| Greystone Quarry | dusty warm haze, desaturated, thicker the deeper you go |
| Goldmeadow | bright, warm, saturated, thinnest fog |
| Frostpeak | cold blue-white, crisp |

- **Announcements:**
  - A title card at upper centre (name plus subtitle) that fades in, holds 2.5 s and fades out, with a soft sting.
  - The first visit shows the full card plus "Discovered" and a chime.
  - Repeat visits get a smaller card, with a 60 s cooldown per biome.
  - Discovered biomes are saved.
- **Ambience loops**, crossfaded by biome and synthesized as placeholders (`tools/synth_movement_sounds.py` style):
  - forest: birds and creaks
  - field: crickets and wind
  - quarry: echoey hum and drips

## Performance

Idle `ResourceNode`s don't process each frame, so the cost is draw calls (each node is several meshes plus shadows).
- `visibility_range_end` of about 80 m (with a fade) on node meshes.
- No shadows from chunk and rubble pieces (or none beyond about 30 m).
- After phase 2, report the draw calls and frame time from the forest's densest spot.

## Phases (one commit each)

1. **Ground.** ✅ Shapes live in `scripts/world_map.gd`; `generate_test_terrain.gd -- --preview=map.png` writes a top-down check. Generator rework (ids 2–5, ring road, quarry pit, forest glades and trail, field swells and crop squares), shader colours, footsteps for the new ids, the baked-node height check, and debug-menu teleports to each biome.
2. **Spawner and the Pinewood.** ✅ `scenes/biomes/pinewood.tscn`. Densest view measured at ~710 draw calls, 1.2–3.2 ms GPU between runs (1280×720). `NodeSpawner` (seeded, stable `save_id`s like `forest_pine_###`), canopy layers with trunk collision, ~100 trees, ferns and mushrooms, `allowed_ids`, and the performance pass with measurements.
3. **Greystone Quarry and crystal.** ✅ `scenes/biomes/quarry.tscn` (one NodeSpawner ring per level). Tier perk is `hit_power` 0.5; `BuildingTier.hall_tier` lets a tier set its own town-hall requirement. Ore bands, the crystal node, model, icon and item, quarry props, smithy tier 4 and its perk, the hall-cap exception.
4. **Goldmeadow and Farming lite.** ✅ `scenes/biomes/goldmeadow.tscn`. In the wheat: ~140 draw calls, 1.5 ms GPU. Watch out: every mesh on the palette material uses per-instance shader values, and Godot's default buffer for them overflowed when the sheaves were ~34 meshes each; keep node models to a handful of meshes. Skill, sickle, wheat and barley nodes and items, wheat scatter, hay, fences, carts, windmill.
5. **The road.** ✅ `scenes/biomes/road.tscn`: `RoadCourse` (set pieces by metres from the gate) and `TimeTrial`. Checkpoint timeout is 40 s, not 20 (a sprinting lap is ~150 s, ~17 s between arches). Medal times 170 / 125 / 95 s are first guesses: tune them after real laps (TimeTrial exports). The global shader-variable buffer is raised to 262144 (project.godot): the default only fits ~4,000 meshes on the palette material. Obstacle kit, set pieces, gate, checkpoints, HUD, saved bests, medals and banners.
6. **Biome feel.** ✅ `Biome` autoload + `data/biomes/*.tres` (BiomeMood); ambience from `tools/synth_ambience.py`. The quarry's fog thickens to 2× toward the floor. `Biome` autoload, `BiomeMood` layered onto DayNightSky, announcements, ambience.
7. **Docs.** README (features, controls, the sickle) and the TODO additions below.

## TODO additions (phase 7)

- **Mining tunnels** off the quarry levels (a flat wall is reserved for the mouth).
- **Full farming:** planting and growing, seasons, a farmer villager and building, Rosa bakes with wheat, a farming perk, and a sink for wheat and barley.
- **Lap ghost** for the time trial.
- **Trophy / achievement spot** in or near the town hall.
- A **"leaves" footstep set** for the forest floor.
- **Real ambience recordings** (join the existing audio TODO).
