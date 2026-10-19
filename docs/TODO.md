# TODO — parked for later

Everything we decided to come back to, in one place. Tick items off (`- [x]`) as they're done.
Design background for most of these is in [3d-research-notes.md](3d-research-notes.md).

## Fishing

- [x] **Pike as a predator:** every 25–45 s it stalks the nearest perch, lunges (ripple, the school scatters) and catches one half the time, then glides back to cover. Spooking it calls the hunt off (`FishSpecies` *Hunting* group).
- [ ] **Swimming** — surface swimming in deep water (float, paddle, can't strike well while swimming); maybe diving with a breath meter after that (F2).
- [ ] **Faster regrouping** — scattered schools drift back together slowly (~1 m spread after 8 s); tune cohesion in `scripts/fish_school.gd`.
- [ ] **Skittishness tuning** — play-test `scare_radius`, `nerve`, `calm_down` per species in `data/fish/*.tres`.
- [ ] **Save fish?** — ponds currently start full on every load (deliberate); revisit if it feels exploitable.
- [x] **A lake:** south of the clearing, up a second path. It's 1.35 m deep in the middle, with trout, perch and Arctic char (Fishing 30, keeps to deep water via `FishSpecies.min_depth`).
- [ ] **A stream** feeding the pond. Needs flowing water that isn't a flat `WaterBody` surface.

## Gathering

- [x] **Weak points:** a glowing diamond on one chunk. A swing aimed at it counts an extra hit, gives double XP and a "Weak spot!" burst, then the spot moves (`ResourceNode` *Weak point* group).
- [x] **True tool sinking:** during the bite, a world copy of the tool sticks with its edge buried in the node. The held fist stays on screen holding the handle (`player.gd` `_stick_in_world`).
- [x] **Clean respawn ghost:** one silhouette outline via the stencil buffer (`ResourceNode.ghost_silhouette`, on by default).
- [x] **Iron and oak:** `iron_rock.tscn` (Mining 15) and `oak_tree.tscn` (Woodcutting 15), used in the village's tier-3 costs.
- [x] **More node types:** birch (Woodcutting 8), pine (25), coal (Mining 20) and gold (30), placed around the map.
- [x] **Uses for coal, gold, birch, pine:** they pay for Rosa's and Edda's cottage tiers. The smithy's tier 3 also needs coal, and the town hall's tier 3 needs gold.

### Mining overhaul

- [x] **Feel:** layered impact sounds (`SoundLayers`), chips / dust / sparks per hit (`HitFx`), an impact star, a camera kick and FOV punch (`ShakeCamera.kick`), the tool quivering where it's stuck, pebbles piling up round the rock.
- [x] **Rocks made to break apart:** Voronoi-cut boulders with a `Seam_*` outline per piece and fitted convex collision (`fractured()` in `make_models.py`, `ResourceNode.fit_collision`).
- [x] **Cracks along seams:** every hit on a piece cracks it a step round its outline, tips count double, a full crack splits off exactly that piece; half-cracked pieces keep their progress; no wear-down shedding on seam rocks. Weak points stay on trees only.
- [x] **An ore look each:** copper verdigris, iron basalt columns, coal strata, gold veined geode, crystal snapping off at the base (the other candidates are in `models/designs/`).
- [x] **Overhead pickaxe swing** with a ready stance (`player.gd` `SWINGS`).
- [x] **Real mining sounds** from the GDC 2026 bundle (`tools/cut_sounds.py`, `audio/mining/sfx/`).
- [x] ~~**Iron's crack is faint**~~ superseded: ores no longer crack along seams (see Ore polish).
- [ ] **More ways to mine** (ideas, none picked yet): pry a cracked piece off by pulling the mouse back; keystones (take pieces in the right order or the rest collapses into rubble); ore only from the faces a split exposes; triple points where three seams meet crack all three pieces.
- [x] ~~**Fewer, bigger pieces**~~ superseded by the ore polish.

### Ore polish ([plans/ores.md](../plans/ores.md))

- [x] **Copper breaks where it's struck** (phase 1): 36 pieces drawn as one mesh (`node_rock.gdshader` hides broken ones), 2–3 out per hit, unsupported pieces collapse, shatter at 35% gone; ore spills from vein pieces; exact saves; weathered/fresh baked shading with glinting ore; dirt decal and pebbles; variants rebuilt. Spawns in 5–12 ms (was ~50).
- [x] **Copper playtested**; it felt good. Fixed from it: white blobs by the rocks (`pow(shade, 2.2)` gave NaN pixels the glow smeared out; squared now).
- [x] **The fault:** a hairline crack with trickling grit on every ore rock; hit it and up to six pieces break out (`FAULT_*` in `resource_node.gd`).
- [x] **Every ore breaks its own way** (phases 2–5), its rules in its `.pieces.json` (`support`, `knock`, `shatter_at`, `tough`, `grounded`): iron columns topple (~7 swings), coal plates drop a layer (~7), gold's tough shell hides a gold heart (~9; the quartz-heart candidate is `models/designs/gold_geode_quartz`), crystal shards snap and bring the crystal down (~8). Swings measured hitting one spot; the fault and collapses cut them.
- [x] **Ore pickups and icons** are chunks of their rock's fresh inside (phase 6); **scenery rocks** and **building stone** weathered the same way (phases 7–8).
- [ ] **Playtest the other ores** and tune: swings per ore (`knock`, `shatter_at` in `make_models.py`), how often you find the fault, ore spill rate, glint (`ore_roughness` / `ore_metallic` / `ore_glow`), the dirt patch on quarry sand.
- [ ] **Sounds** for knocking pieces out, collapses and faults still reuse the split and break sounds.
- [ ] **`.pieces.json` in exports:** add `*.json` to the export include filter when an export preset exists.
- [ ] **The seam-crack code** in `resource_node.gd` (and `fractured()`) is now used only by `models/designs/`; drop it if those designs go.
- [ ] **Icons** don't show the baked shade (Workbench renders palette colour only).

### Woodcutting overhaul

Plan and decisions: `plans/woodcutting-overhaul.md`.

- [x] **Felling axe** with a flat side chop of its own in `SWINGS`; the woodcutter villager carries it too.
- [x] **A notch carved into the trunk** (`TrunkCarve`): set by the first hit, deepened toward the swinger, 65% through by the fall, saved with the game. Replaces the weak point on trees.
- [x] **Clean cuts** into the notch's mouth: an extra hit, double XP, a big chip, a snap.
- [x] **Felling from the notch:** the trunk splits there, hangs on the hinge, falls sideways to the swinger toward the clear side, and leaves the cut stump with growth rings.
- [x] **New trees** picked from rendered candidates (`tree_designs`): round starter, airy birch, spreading oak, classic pine; the scenery forest matches.
- [x] **Feel:** wood chips and dust, bark peeling, canopy shake and leaves, sway and creak late in the chop.
- [x] **Wood sounds, synthesized** (`tools/synth_wood_sounds.py`; the GDC bundle's stand-ins sounded wrong): thunk, bite, chips, snap, creak, fibres tearing, crown rushing, landing.
- [ ] **Tune the synthesized wood sounds by ear** in play (each sound is one function in the script; the stacks' levels are in `audio/woodcutting/*.tres`).
- [ ] **The notch on birch** shows less (pale cut wood on white bark); a darker cut colour for it if it reads poorly.
- [ ] **Bucking the fallen trunk into logs** with more swings (left out of this overhaul).

## Village

Design notes are in [village-design.md](village-design.md).

- [x] **Upgrade effects:** tiers give perks (`TierEffect`, summed by `Village.stat`). Smithy: chance of a double hit. Lodge: extra logs. Fisher: calmer fish, then bonus fish. Town hall: an XP bonus.
- [ ] **Villager rig and schedules:** real skeletal animation, a day plan, and wandering the whole valley instead of only 2–3 spots.
- [x] **A growing village:** town hall tier 2 brings Rosa the baker's cottage, tier 3 Edda the prospector's. They build themselves when unlocked (`Building.unlock_hall_tier`).
- [x] **Give the newcomers a job:** both cottages upgrade like the houses. Rosa: Bakery → Bakehouse, walk and sprint 8% / 15% faster (`run_speed`). Edda: Assay Shed → Assay Office, +1 ore per rock, then rocks grow back 30% faster (`extra_ore`, `rock_regrow`).
- [x] **Sitting:** villagers idling on a `Bench` spot sit on the seat (`Villager._animate_sit`).
- [x] **Talk ray occlusion:** a villager behind a pole still counts if their head, chest or hips is in plain sight (`player.gd` `_villager_behind_clutter`).
- [ ] **Interiors:** buildings are solid shells. Could have doors you walk through.

## Biomes

Plan and decisions: [plans/biomes.md](../plans/biomes.md).

- [x] **The Pinewood, Greystone Quarry, Goldmeadow and the ring road**, with their own ground, light, fog, ambience and arrival cards (`WorldMap`, the `Biome` autoload, `data/biomes/`).
- [x] **Crystal and the Crystal Forge:** Mining 40 on the quarry floor; the smithy's fourth tier (`BuildingTier.hall_tier` lets it need only town hall tier 3).
- [x] **Farming lite:** the Farming skill, a sickle, wheat and barley in Goldmeadow.
- [x] **Time trial** round the ring road: gate, eight checkpoints, splits, saved bests, medal banners on the gate.
- [ ] **Mining tunnels** off the quarry's levels. Cut them into any level wall away from the haul road and the mantle stairs (see the generator's `_ramp_t` / `_stair_angles`).
- [ ] **Full farming:** planting and growing, seasons, a farmer villager and building, Rosa baking with wheat, a farming perk, and something to spend wheat and barley on.
- [ ] **Tune the medal times** (170 / 125 / 95 s are first guesses; `TimeTrial` exports in `scenes/biomes/road.tscn`) after some real laps.
- [ ] **Lap ghost:** a see-through figure replaying your best lap.
- [ ] **Trophy / achievement spot** in or near the town hall: medals, discoveries, maxed skills.
- [ ] **A "leaves" footstep set** for the forest floor (it sounds like grass for now).

## Menus and worlds

Plan and decisions: [plans/menus.md](../plans/menus.md).

- [x] **Main menu, worlds, pause, settings, New World:** a menu over a drifting view of the clearing, a folder per world (`user://worlds/`), Esc pauses, four settings tabs, world settings with a live map, small and large worlds, a loading screen.
- [ ] **Playtest the menus by hand:** Continue / Play, the pause menu, Save & Quit and its picture, rename / duplicate / delete, the old saves moving into folders on first start. Checked by `tools/menu_shots.gd` and the tests, not by playing.
- [ ] **Display settings in a window:** borderless, fullscreen and the window sizes weren't tried on screen (the machine was busy).
- [ ] **A large world in a window:** its load time (~20 s headless) and how it looks; the one windowed check came out washed out white (probably snow under Frostpeak's fog where the camera landed, not confirmed).
- [ ] **Key rebinding** in Settings > Controls (left for later in the plan).
- [ ] **A second quarry on large worlds** (the plan's "if it fits"): the quarry is one stamp, one `Biome.quarry_*`, one set of levels today.
- [ ] **Repeated biomes' arrival cards** show the first site's kind (`Biome.kind_names` is per biome, not per site).
- [ ] **Small worlds are 384 m**, not the planned 256 (at 256 the rim would start 44 m from the middle, over the hub).
- [ ] **The debug menu's Graphics tab** now duplicates Settings > Graphics; keep it or drop it.
- [ ] **Sound on the menu:** the backdrop is silent (no ambience or music).

## Generated worlds

Plans and decisions: [plans/procgen.md](../plans/procgen.md), [plans/procgen-variety.md](../plans/procgen-variety.md), [plans/menus.md](../plans/menus.md) (world settings, sizes, loading). Merged into `main` 2026-10-19.

- [x] **A world from a seed:** biome ring, water with fish, a quarry pit, trails, spawners and scenery per biome, four baked variants of every gatherable and big scenery model (`scripts/procgen/`, `scenes/procgen.tscn`).
- [x] **A voice per tree species and per ore** (`tools/synth_wood_sounds.py`, `tools/synth_mining_sounds.py`). This changes the hand-built world's sounds too.
- [ ] **Playtest and listen:** walk a few seeds; listen to every tree species and ore (the voices are measured, not heard yet: no steady pulsing, no beating tones, pitch and ring in the intended order).
- [x] **Load time:** the map generates on a worker thread and the spawning and scenery are spread over frames behind a loading screen; a normal world is ready in ~5 s headless (was ~8), a large one in ~20. Caching built rocks could still cut it.
- [ ] **The quarry ambience hum** (55 + 82.5 Hz) repeats 27.5 times a second: a low growl. Worth a listen given how the breeze turned out.
- [x] **Variety:** a kind per biome, Hearthvale (the village) on every seed, rivers, ruins, camps and rare spots, rich and lean resources, an off-centre start (`plans/procgen-variety.md`).
- [ ] **New screenshots:** `docs/images/procgen.png` predates the village, rivers and landmarks (skipped while a game was using the GPU; take them with the shots script when the machine's free).
- [ ] **Walk the new pieces:** climb both ruins to their reward, wade a river and its fords, check the Lakeside Village's fisher meets the pond, see each kind's ground in person.
- [ ] **The ring road / time trial in generated worlds:** still left out (hand-placed with baked heights).
- [ ] **Hand-sculpting a seed:** a seed you like could be baked to `terrain_data`-style files and edited.
- [x] **Merge or drop:** merged into `main` (2026-10-19, with the ores work).

## Movement

- [ ] **Grapple / rope** — for chasms and cliff-face nodes.
- [ ] **Agility skill or craftable grapple** — optional movement gating for rare nodes.
- [ ] **Movement tuning:** play-test the momentum numbers (Player inspector: *Momentum*, *Air dash*, *Wall run*, *Speed feel*): bhop gain, the hop window, air control, wall-run length.
- [ ] **Slide / mantle tuning** — play-test speeds and heights (Player inspector: *Crouch / slide*, *Mantle*).

## Art & models

- [x] **Real-model pickups:** drops show the item's model (`Items.model`), tumbling on a fitted box, spinning in as they're collected.
- [x] **Block hands:** a blocky fist and sleeve cuff are part of each tool model (`block_hand()` in `make_models.py`).
- [x] **Replace greybox leftovers:** the parkour blocks are low-poly ruins (`ruins()` in `make_models.py`) with exactly the old collision boxes. Chips are wedge shards and bursts are spinning diamond flecks.
- [x] **Scenery:** grass, flowers, bushes and boulders are scattered by `SceneryScatter` (layers in `main.tscn`, models in `make_models.py` `scenery()`).
- [x] **Blender guide:** [blender-guide.md](blender-guide.md), remodelling the rock by hand.
- [ ] **Sculpt / paint the terrain** in the Terrain3D editor (note: re-running `tools/generate_test_terrain.gd` overwrites it).

### Graphics overhaul (Valheim-style, [plans/graphics.md](../plans/graphics.md))

- [x] Phases 0–9: detail textures, smooth textured terrain, smooth shading, leaf-card trees, dense grass, mist / grading / darker nights / firelight, water and sky, presets.
- [ ] **Playtest the look in motion:** grass parting and swaying, leaf flutter, the shake and fall of a leaf-card tree, felled-tree chips and leaf drops, lamp flicker. Only stills were checked.
- [ ] **Night darkness:** nights are much darker now; tune `DayNightSky`'s night ambient (0.32) and moonlight (0.24) by eye.
- [ ] **README gameplay shots** (mining, woodcutting, spearfishing, pond) still show the old look; retake them.
- [ ] **Ghost outlines on leaf-card trees** (trees above your level) outline whole card quads, not the leaves.
- [ ] **Old grass tufts** (`grass_tuft` ScatterLayer) now sit among the dense grass; keep them as accents or drop them.
- [ ] **Buildings, props and villagers** got the detail overlay only; real per-model textures (re-UV) would be the next step up close.

## Audio

- [ ] **Real recordings** to replace the synthesized placeholders: footsteps (all surfaces + water), slide scrape, mantle, splash, spear hit, and the biome ambience beds (`audio/footsteps/`, `audio/movement/`, `audio/fishing/`, `audio/ambience/` — swap the `.wav`s, the `.tres` randomizers stay).
- [x] **Mining sounds:** cut from the GDC 2026 sampler (`tools/cut_sounds.py`).
- [x] **Even mining levels:** every clip at the same loudness, one source per layer, and the plain hit ducks under a crack tip or a split (`ResourceNode._hit_sounds`). Measured with `tools/measure_mix.py`: a plain hit stays within a 3.4 dB window (was 10.7), a tip hit lands 2 dB above it, a split 3.7 dB.
- [x] **Synthesized mining sounds** (`tools/synth_mining_sounds.py`, 2026-10-17, `procgen` branch) replace the GDC clips below, with a voice per ore. Re-run `tools/measure_mix.py` and rebalance the stack volumes after a listen.
- [x] ~~**Better source material for mining (next):**~~ superseded by the synthesis above. playtested, the sounds are even now but still don't feel right. The sampler has almost no real rock: ice cracks, a metal pipe on concrete, body punches and a broom sweeping crumbs stand in for stone cracking, the pick's bite, the thump and gravel, and the split crunch is a "gore smash". Find a real rock / mining library (stone impacts, pick on rock, rubble, gravel), then point the recipes in `tools/cut_sounds.py` at it: the layer stacks, the loudness matching and the ducking all stay. Re-run `tools/measure_mix.py` and rebalance the layer volumes after.

## World & tech

- [x] **Editor re-save dropped villager lines:** in the editor, non-`@tool` scripts run as placeholders, and a placeholder silently refused the saved `PackedStringArray` when the script's default was a bare `[]` / `[...]` literal. So `BuildingTier.lines` and `BuildingDef.night_lines` loaded empty (or as the default), and the next editor save wrote them out that way. Their defaults are now `PackedStringArray(...)`, and an in-editor re-save keeps all 75 lines. **Rule:** give exported packed arrays a `PackedXArray(...)` default, never a bare array literal. (Fields equal to their script default, like Tier 1's `name = "Lean-to"`, are left out of the file on purpose. That's normal and loses nothing.)
- [ ] **Editor bloats `materials/terrain_assets.tres`:** Terrain3D's editor plugin fills in generated placeholder textures and a default grass mesh and saves them as ~13 MB of image data. The low-poly shader uses none of it. Until there's a fix, discard that change (`git checkout -- materials/terrain_assets.tres`).
- [x] **Day / night:** a 20-minute day (`DayNight` autoload) lit by the `Sky` node. Lamps and windows glow after dark, villagers go home at night, and fish are calmer at dawn and dusk.
- [x] **Stars and moon:** `shaders/sky.gdshader` draws the gradient, a sun disc by day, a moon disc and twinkling stars at night.
- [x] **Terrain collision range:** Terrain3D now builds collision for the whole map up front (`collision_mode` Full/Game, ~0.1 s at 512 m). Revisit if the world gets much bigger.
- [x] **Saved node keys:** every placed node has a `save_id`. Saves keyed by the old scene path carry over automatically.
- [ ] **GPU driver resets:** on 2026-10-16 the game lost its graphics device on Direct3D 12 (GTX 1080 Ti; Windows logged a TDR, `0x141`), and again on 2026-10-19 a moment after a generated world appeared (`nvlddmkm` event 153, `0x887a0005`). Switched to Vulkan (`rendering/rendering_device/driver.windows`) the same day; watch whether it comes back.
