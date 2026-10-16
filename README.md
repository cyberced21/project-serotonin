# Project Serotonin

A first-person, low-poly gathering game made in **Godot 4.7**. Chop trees, mine rocks, cut
grain and spearfish in shallow ponds, across a forest, a quarry, farmland and a village, joined
by a ring road built for fast movement. The game is about how gathering *feels*: impact-frame hits,
hit-stop, screen shake, positional audio, chunks flying off nodes, and a tool that bites into
whatever you hit.

![The clearing](docs/images/clearing.png)

| Mining | Spearfishing | The pond |
|---|---|---|
| ![Mining](docs/images/mining.png) | ![Spearfishing](docs/images/spearfishing.png) | ![Pond](docs/images/pond.png) |

## Features

- **Gathering with weight.**
  - The hit lands on the swing's impact frame, not when you press the button.
  - The tool sinks into the node, holds through the hit-stop, then yanks out and tears a chunk loose.
  - During the bite, the tool really sticks in the node until you yank it out, quivering.
  - Every hit leaves a notch. Trees have a glowing weak spot (an extra hit and double XP, then it moves), and they topple, crash down and spill logs.
  - Each hit is felt: a layered sound (crack, tink, thump, a gravel trickle a beat later), chips that bounce on the ground, a dust puff, sparks, an impact star, a camera kick with a quick narrowing of the view, and pebbles piling up round the rock. Pitch rises as a node weakens.
- **Mining: rocks made to break apart.**
  - Rocks are hefty boulders (about 2.4 m) cut into pieces that fit together exactly. Their collision follows the real shape, refitted as pieces come off.
  - Hit a piece and a crack runs along its seam, both ways from where you struck. Every hit takes it further, and hitting one of its two glowing tips counts double (an extra hit and double XP). When the crack has gone all the way round, exactly that piece splits off and tips away, showing the fresh stone and ore inside.
  - Leave a piece half-cracked and its crack waits for you. Pieces only ever come off along a crack.
  - The pickaxe squares up when you look at a rock, then swings overhead and comes down pick-first on the crosshair.
- **Skills:** Woodcutting, Mining, Fishing and Farming, each with XP and levels. Nodes and fish above your level bounce off or dodge.
  - Every ore has its own look, built for cracking: **copper** is a weathered boulder with a green cap whose seams follow its copper veins, **iron** a cluster of basalt columns bleeding rust, **coal** layered seams of coal and shale that split into slabs, **gold** a dull brown geode, thinly veined, with a quartz rim and a gold core inside, and **crystal** violet crystals that crack round their base and snap off.
  - Higher-level nodes:
    - Birch (Woodcutting 8) grows west of the clearing.
    - Oak (15) grows around the village, and iron rocks (Mining 15) sit east of the smithy. The village's top tiers ask for them.
    - Pine (25) is on the northern hills, coal (Mining 20) by the pass, and gold (30) in the foothills of the peak. The newcomers' cottages are built from them, and the smithy and town hall want coal and gold for their top tiers.
    - Crystal (Mining 40) grows only on the floor of Greystone Quarry. The smithy's fourth tier is forged with it.
    - Wheat (Farming 1) and barley (Farming 15) stand in Goldmeadow's crop squares. You cut them with a sickle, which comes out when you aim at grain. There's nothing to spend them on yet.
- **Spearfishing.**
  - Ponds in the clearing and the village, and a deeper lake to the south where Arctic char (Fishing 30) keep to the middle.
  - Wade into the pond and stalk wary schools of perch, trout and pike. The pike hunts too: watch it stalk the perch and lunge. Crouch to stay quiet: splashing and misses scatter them.
  - Every fish along the thrust gets skewered, and multi-catches escalate the feedback and XP ("Double!", "Triple!").
- **Biomes.** Each has its own ground colour, light, fog and ambience, and a title card when you arrive (the first visit says *Discovered*, and it's saved). Night still falls in all of them.
  - **The Pinewood** (north): a dense forest of about 100 pines and birches you can chop, among several hundred scenery trees you can bump into and wall-run off. A dirt trail runs from the clearing past three open glades to the ring road. Ferns, mushrooms, birdsong.
  - **Greystone Quarry** (west, past the peak): a five-level pit about 25 m deep.
    - A haul road spirals to the floor. Each wall has two three-step mantle stairs and sheer faces to wall-run.
    - Copper, iron, coal and gold on the levels, crystal on the floor glowing violet after dark.
    - A crane on the rim, scaffold steps, ladders, and haze that thickens as you go down.
  - **Goldmeadow** (south-east): rolling farmland. Crop squares of wheat and barley between dirt tracks, a windmill with turning sails (wall-run it), a fenced pasture with hay bales, a hay cart, lone oaks, and crickets.
  - **Hearthvale** (the village), **Stillwater** (the lake), **The Clearing** and **Frostpeak** have moods of their own too.
- **The ring road and its time trial.** A 1 km gravel loop, graded smooth, with banked bends, rock cuttings to wall-run along, spurs into every area, and a gully you can bridge or leap.
  - An obstacle course runs all the way round: log piles to hop, low walls, crate steps to mantle, wall-run panels and side-to-side alleys, ramps, low beams to slide under. Every piece leaves part of the road clear.
  - Run through the start gate (where the forest trail meets the road) and the clock starts. Pass eight checkpoint arches in order: the next one's pennants light up, and each shows your split against your best.
  - Best lap and splits are saved. Bronze, silver and gold times each hang a banner on the gate.
- **A village to build up.** Over the hills, a dirt path leads to a valley with four villagers: a woodcutter, a smith, a fisher and the mayor.
  - Talk to a villager (E) to see what their building's next tier costs, then pay with the logs, ore and fish you've gathered.
  - Every building has three tiers (the smithy has a fourth, the Crystal Forge, which needs town hall tier 3). The town hall's tier caps the houses, so raising it opens the next round.
  - The village grows: raising the town hall brings new neighbours, whose cottages build themselves (Rosa the baker at tier 2, Edda the prospector at tier 3). Their cottages upgrade too: Rosa's into a bakery and bakehouse, Edda's into an assay shed and office.
  - Every tier above the first gives a perk, shown in the panel:
    - Smithy: sharper tools, so a hit can count twice. At the Crystal Forge, every other hit also cuts twice as deep.
    - Woodcutter: extra logs from every tree.
    - Fisher: calmer fish, then a chance of a bonus fish.
    - Town hall: bonus XP in every skill.
    - Rosa: fresh bread, so you walk and sprint faster.
    - Edda: extra ore from every rock, then rocks grow back faster.
  - Upgrades are staged: the old building collapses into dust, then the new one pops up piece by piece. The villager steps back to watch, then cheers.
  - Villagers are toy figures animated in code. They work (chopping, hammering, fishing, holding forth), wander between their spots, and turn to look at you.
- **Fast, expressive movement (Ghostrunner-ish).** Sprint, jump (with coyote time and jump buffering), crouch, slide down slopes, and mantle up ledges.
  - **Momentum:** speed above running pace bleeds off slowly instead of stopping dead.
  - **Bunny hop:** jump right as you land to keep your speed and add a little, up to 16 m/s.
  - **Slide cancel:** jump out of a slide to keep its speed. Land with crouch held and you drop straight back into a slide.
  - **Air control:** steering in the air turns you without slowing you down.
  - **Air dash:** Shift in the air, once per jump.
  - **Wall run:** jump alongside a wall at speed and run along it, then jump to kick off.
  - **Speed effects:** field of view widens, wind rises and speed lines appear as you go faster.
  - Smooth at any frame rate: physics interpolation, with the eye placed every frame.
  - Subtle feel on top: head bob, a dip when you land, a lean into strafes, and a held tool that sways with the mouse, bobs with your steps and drops out of view when you switch tools.
- **Low-poly world.**
  - Terrain3D terrain with a faceted shader that colours each face by slope and height: grass, dirt, rock, sand, snow, and a muddy bed under water. Painted surfaces add the paths, the gravel road, forest floor, meadow, crops and banded quarry stone.
  - Low-poly water, swaying reeds and lily pads.
  - Grass clumps, flower patches, bushes and boulders scattered over the land. They stay off paths and water and away from buildings, and the plants sway in the wind.
  - Every model shares one palette texture.
- **Day and night.** A day lasts 20 minutes: 14 of daylight, 6 of night.
  - The sun swings across the sky, and the light warms at dawn and dusk.
  - Nights are moonlit blue, with lamps, lanterns and windows glowing.
  - Villagers go home after dark, but step out if you come to their door.
  - Fish are dozy around dawn and dusk.
- **Positional audio:** footsteps change with the surface (grass, dirt, stone, sand, snow, water; the road and quarry crunch), and the slide scrape, splashes and spear hits are placed in 3D. Mining sounds are real recordings, built up in layers, each with several variations.
- **Saving:** skills, inventory, player position, the village's tiers, the time of day, which nodes are depleted (with their respawn timers), the biomes you've discovered, and your best lap and medals.

## Controls

| Action | Keys |
|---|---|
| Move / look | WASD / mouse |
| Sprint / air dash (in the air) | Shift |
| Jump / mantle (jump at a ledge while moving forward) / wall run (jump alongside a wall at speed) | Space |
| Crouch / slide (crouch while running fast, or land holding it) | Ctrl or C |
| Gather (axe, pickaxe or sickle: whichever fits what you aim at) / spear (hold) | Left mouse or E |
| Talk to a villager | E |
| Free the mouse | Esc (click to recapture) |
| Debug menu: items, skill levels, building tiers, time of day and speed, pause, teleports (buildings, biomes, ponds, nodes), fly mode, a live readout (with the biome), save wipe | F1 (debug builds) |
| Debug: skip ahead 3 hours / give 50 of every item / upgrade every building (wraps back to tier 1) | F6 / F7 / F8 (debug builds) |
| Debug: give XP / reset save | F9 / F10 (debug builds) |

## Getting started

1. Install **Godot 4.7.2** (standard build).
2. Clone the repo and open `project.godot`. The Terrain3D addon is included in `addons/terrain_3d`.
3. Press **Play** (F5). The main scene is `scenes/main.tscn`.

Saves are written to `user://save.json`. Press F10 in a debug build to wipe the save.

## Project layout

```
addons/terrain_3d/   Terrain3D v1.0.2 (MIT) — terrain + editor tools
art/                 palette.png (+ palette.json), icons/ rendered item icons
audio/               sfx; footsteps/, movement/, fishing/, ambience/ are synthesized placeholders;
                     mining/ the layered mining sounds, its sfx/ clips cut from the GDC 2026 bundle
data/biomes/         BiomeMood resources (each biome's light, ambience and card)
data/buildings/      BuildingDef resources (tiers, costs, villager lines)
data/fish/           FishSpecies resources (perch, trout, pike, char)
docs/                design notes, TODO list, README images
materials/           shared node / palette / terrain-asset materials
models/              .glb models generated by the Blender scripts (rocks, trees, tools, fish, scenery, items, village/, quarry/, field/, road/)
scenes/              main.tscn, player.tscn, resource nodes (rocks, trees, crystal, wheat, barley), pickup; village/ holds one scene per building, biomes/ the Pinewood, the quarry, Goldmeadow and the road
scripts/             gameplay code; autoload/ holds the global systems
shaders/             terrain, water, ripples, node surface, fish, sway, ghost outline
terrain_data/        Terrain3D region data
tools/               asset-generation scripts (see below)
```

Key scripts:
- **Player and feel:** `player.gd` (movement, per-tool swings, bite), `viewmodel.gd` (held tool), `shake_camera.gd` (shake, impact kick, FOV)
- **Gathering:** `resource_node.gd` (every tree and rock: hits, cracks along seams, splits, fitted collision), `hit_fx.gd` (chips, dust, sparks, impact star), `pickup.gd`, `items.gd`
- **Layered sound:** `sound_layers.gd` / `sound_layer.gd` (a sound built from timed layers), played through `Sfx`
- **Fishing:** `spear_fishing.gd`, `fish_pond.gd`, `fish_school.gd`, `fish.gd`, `water_body.gd`
- **Village:** `building.gd` (shows a tier, plays the upgrade), `villager.gd`, `upgrade_panel.gd`, `building_def.gd` / `building_tier.gd`, `prop.gd`
- **World:** `world_map.gd` (where the biomes, roads and landmarks are, shared with the terrain generator), `day_night_sky.gd`, `footsteps.gd`, `pond_dressing.gd`, `scenery_scatter.gd` + `scatter_layer.gd`, `node_spawner.gd` + `spawn_entry.gd` (seeded gatherable nodes with stable save ids), `windmill.gd`
- **The road:** `road_course.gd` (set pieces by metres along the road), `time_trial.gd`
- **Autoloads:** `Skills`, `Inventory`, `SaveGame`, `Village` (building tiers, the town-hall cap, perks), `DayNight` (the clock), `Biome` (where you are, the mood, cards and ambience), `Juice` (hit-stop and shake), `Sfx`, `GameInput`

## Asset pipeline

Most content is generated by scripts, so it's easy to tweak and regenerate. Run these from the project folder:

| What | Command |
|---|---|
| Palette atlas (`art/palette.png` + `.json`) | `python tools/make_palette.py` |
| Low-poly models → `models/*.glb` (needs Blender 4.2+) | `blender -b -P tools/blender/make_models.py -- models art/palette.json` (add builder names such as `forest quarry farming road` to rebuild only those) |
| Village buildings, villagers and props → `models/village/` | `blender -b -P tools/blender/make_village.py -- models art/palette.json` (or name builders, e.g. `smithy`) |
| Item icons → `art/icons/*.png` | `blender -b -P tools/blender/render_icons.py -- models art/palette.png art/icons`, then `python tools/outline_icons.py` (name item ids after either to do only those) |
| Ore design candidates → `models/designs/` (not used by the game; two looks per ore) | `blender -b -P tools/blender/make_models.py -- models art/palette.json designs` |
| Mining sound clips → `audio/mining/sfx/` (needs the Sonniss GDC 2026 bundle, which isn't in the repo) | `blender -b -P tools/cut_sounds.py -- <bundle folder> audio/mining/sfx` (Blender's Python, for numpy) |
| Placeholder sounds (footsteps, slide, wind, mantle, splash, spear) | `python tools/synth_movement_sounds.py` (needs numpy) |
| Placeholder biome ambience (forest, field, quarry) | `python tools/synth_ambience.py` (needs numpy) |
| Terrain: the original layout plus the biomes and roads (**overwrites** `terrain_data/`) | `godot --headless --path . -s res://tools/generate_test_terrain.gd` (add `-- --preview=map.png` for a top-down check). It keeps the ground under hand-placed nodes as it was and reports any that moved. |

Models colour their faces by pointing UVs at palette swatches. To hand-edit a model, import the
`.glb` in Blender, edit it, and export it back as `.glb`.

## Extending

- **Placing nodes:** give every placed node its own `save_id` in the inspector. It's the key its depleted state is saved under. For many at once, use a `NodeSpawner` (see `scenes/biomes/`): it places them by seed and numbers their save ids itself.
- **Moving a biome or a road:** edit `scripts/world_map.gd` and regenerate the terrain. The spawners, scatter and road course follow the new shapes.
- **Keep node models to a few meshes.** Every mesh on the palette material uses per-instance shader slots. The global buffer for them is raised in `project.godot`, but a model of dozens of loose parts, times a field of them, still adds up.
- **A new resource node:** in Godot, right-click `scenes/resource_node.tscn` → *New Inherited Scene*. Set the item, skill and sounds, then either add meshes under `Visual/Body`, `Visual/Chunks` and `Rubble`, or set `model` to a `.glb` whose objects are named `Body_*`, `Chunk_*` and `Rubble_*`.
- **A new rock that cracks:** inherit `scenes/rock.tscn` (cracks, fitted collision, the layered sounds and hit effects are already on) and build its model with `fractured()` in `make_models.py`, like the ore rocks. That gives each `Chunk_X` a `Seam_X` line (its outline, which the crack follows) and marks the cut faces in a `cut_mark` vertex colour. Set `chip_color` to the rock's stone (cracks are drawn in it) and `ore_color` to its ore. `seam_crack_on_piece_only` keeps a crack off what surrounds the piece (the crystal rock uses it).
- **A new layered sound:** make a `SoundLayers` `.tres` (see `audio/mining/`) with a `SoundLayer` per layer (stream, delay, volume, pitch, jitter), and play it with `Sfx.play_at()` or `Sfx.play_layers()`.
- **A new item:** add a row to `Items.DEFS` (`scripts/items.gd`) and an entry to `ICONS` in `tools/blender/render_icons.py`.
- **A new fish:** add a model to the Blender script and a `FishSpecies` `.tres` in `data/fish/`, then list it in the pond's `Fish` node (`FishPond.schools`).
- **A new skill:** add a row to `Skills.SKILLS` (`scripts/autoload/skills.gd`).
- **A new village building:**
  1. Add a function to `tools/blender/make_village.py` that builds each tier's pieces with a `Kit("T1", ...)`, `Kit("T2", ...)` and so on.
  2. Add a `BuildingDef` `.tres` in `data/buildings/` with its tiers, costs and lines.
  3. Copy a scene in `scenes/village/`, then move its `Spots` markers (Door, Bench, Work1–3) to fit the new model.
- **Retuning upgrades:** costs and villager lines live in `data/buildings/*.tres`. Each tier also has an empty `effects` list, where upgrade mechanics will plug in.

## Docs

- [docs/TODO.md](docs/TODO.md): everything planned or parked for later.
- [docs/blender-guide.md](docs/blender-guide.md): remodel the rock by hand in Blender (a first modelling project).
- [docs/village-design.md](docs/village-design.md): the village design decisions.
- [docs/3d-research-notes.md](docs/3d-research-notes.md): design decisions and research notes from the 3D conversion and the fishing design.

## Credits

- [Terrain3D](https://github.com/TokisanGames/Terrain3D) by Cory Petkovsek, Roope Palmroos and contributors (MIT). `shaders/terrain_lowpoly.gdshader` builds on its example shader.
- Models made with [Blender](https://www.blender.org/). The game is built with [Godot](https://godotengine.org/).
- Mining sounds cut from the [Sonniss GDC 2026 Game Audio Bundle](https://sonniss.com/gameaudiogdc) (royalty free, no attribution required). Per-clip sources: `audio/mining/sfx/SOURCES.md`.
