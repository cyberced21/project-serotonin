# Project Serotonin

A first-person, low-poly gathering game made in **Godot 4.7**. Chop trees, mine rocks and
spearfish in shallow ponds. The game is about how gathering *feels*: impact-frame hits,
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
  - Every node has a glowing weak spot. Hit it for an extra hit and double XP, and it moves.
  - During the bite, the tool really sticks in the node until you yank it out.
  - Every hit leaves a notch. Rocks shed physics debris, and trees topple, crash down and spill logs.
  - Pitch rises as a node weakens.
- **Skills:** Woodcutting, Mining and Fishing, each with XP and levels. Nodes and fish above your level bounce off or dodge.
  - Higher-level nodes:
    - Birch (Woodcutting 8) grows west of the clearing.
    - Oak (15) grows around the village, and iron rocks (Mining 15) sit east of the smithy. The village's top tiers ask for them.
    - Pine (25) is on the northern hills, coal (Mining 20) by the pass, and gold (30) in the foothills of the peak.
- **Spearfishing.**
  - Wade into the pond and stalk wary schools of perch, trout and pike. The pike hunts too: watch it stalk the perch and lunge. Crouch to stay quiet: splashing and misses scatter them.
  - Every fish along the thrust gets skewered, and multi-catches escalate the feedback and XP ("Double!", "Triple!").
- **A village to build up.** Over the hills, a dirt path leads to a valley with four villagers: a woodcutter, a smith, a fisher and the mayor.
  - Talk to a villager (E) to see what their building's next tier costs, then pay with the logs, ore and fish you've gathered.
  - Every building has three tiers. The town hall's tier caps the houses, so raising it opens the next round.
  - Every tier above the first gives a perk, shown in the panel:
    - Smithy: sharper tools, so a hit can count twice.
    - Woodcutter: extra logs from every tree.
    - Fisher: calmer fish, then a chance of a bonus fish.
    - Town hall: bonus XP in every skill.
  - Upgrades are staged: the old building collapses into dust, then the new one pops up piece by piece. The villager steps back to watch, then cheers.
  - Villagers are toy figures animated in code. They work (chopping, hammering, fishing, holding forth), wander between their spots, and turn to look at you.
- **Expressive movement.** Sprint, jump (with coyote time and jump buffering), crouch, slide down slopes, and mantle up ledges.
- **Low-poly world.**
  - Terrain3D terrain with a faceted shader that colours each face by slope and height: grass, dirt, rock, sand, snow, and a muddy bed under water.
  - Low-poly water, swaying reeds and lily pads.
  - Grass clumps, flower patches, bushes and boulders scattered over the land. They stay off paths and water and away from buildings, and the plants sway in the wind.
  - Every model shares one palette texture.
- **Day and night.** A day lasts 20 minutes: 14 of daylight, 6 of night.
  - The sun swings across the sky, and the light warms at dawn and dusk.
  - Nights are moonlit blue, with lamps, lanterns and windows glowing.
  - Villagers go home after dark, but step out if you come to their door.
  - Fish are dozy around dawn and dusk.
- **Positional audio:** footsteps change with the surface (grass, dirt, stone, sand, snow, water), and the slide scrape, splashes and spear hits are placed in 3D.
- **Saving:** skills, inventory, player position, the village's tiers, the time of day, and which nodes are depleted (with their respawn timers).

## Controls

| Action | Keys |
|---|---|
| Move / look | WASD / mouse |
| Sprint | Shift |
| Jump / mantle (jump at a ledge while moving forward) | Space |
| Crouch / slide (crouch while sprinting) | Ctrl or C |
| Gather / spear (hold) | Left mouse or E |
| Talk to a villager | E |
| Free the mouse | Esc (click to recapture) |
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
audio/               sfx; footsteps/, movement/, fishing/ are synthesized placeholders
data/buildings/      BuildingDef resources (tiers, costs, villager lines)
data/fish/           FishSpecies resources (perch, trout, pike)
docs/                design notes, TODO list, README images
materials/           shared node / palette / terrain-asset materials
models/              .glb models generated by the Blender scripts (rocks, trees, tools, fish, scenery, items, village/)
scenes/              main.tscn, player.tscn, resource nodes (rock, iron_rock, tree, oak_tree), pickup; village/ holds one scene per building
scripts/             gameplay code; autoload/ holds the global systems
shaders/             terrain, water, ripples, node surface, fish, sway, ghost outline
terrain_data/        Terrain3D region data
tools/               asset-generation scripts (see below)
```

Key scripts:
- **Player and feel:** `player.gd` (movement, swing, bite), `viewmodel.gd` (held tool), `shake_camera.gd`
- **Gathering:** `resource_node.gd` (every tree and rock), `pickup.gd`, `items.gd`
- **Fishing:** `spear_fishing.gd`, `fish_pond.gd`, `fish_school.gd`, `fish.gd`, `water_body.gd`
- **Village:** `building.gd` (shows a tier, plays the upgrade), `villager.gd`, `upgrade_panel.gd`, `building_def.gd` / `building_tier.gd`, `prop.gd`
- **World:** `day_night_sky.gd`, `footsteps.gd`, `pond_dressing.gd`, `scenery_scatter.gd` + `scatter_layer.gd`
- **Autoloads:** `Skills`, `Inventory`, `SaveGame`, `Village` (building tiers, the town-hall cap, perks), `DayNight` (the clock), `Juice` (hit-stop and shake), `Sfx`, `GameInput`

## Asset pipeline

Most content is generated by scripts, so it's easy to tweak and regenerate. Run these from the project folder:

| What | Command |
|---|---|
| Palette atlas (`art/palette.png` + `.json`) | `python tools/make_palette.py` |
| Low-poly models → `models/*.glb` (needs Blender 4.2+) | `blender -b -P tools/blender/make_models.py -- models art/palette.json` |
| Village buildings, villagers and props → `models/village/` | `blender -b -P tools/blender/make_village.py -- models art/palette.json` |
| Item icons → `art/icons/*.png` | `blender -b -P tools/blender/render_icons.py -- models art/palette.png art/icons`, then `python tools/outline_icons.py` |
| Placeholder sounds (footsteps, slide, mantle, splash, spear) | `python tools/synth_movement_sounds.py` (needs numpy) |
| Starter terrain (**overwrites** `terrain_data/`) | `godot --headless --path . -s res://tools/generate_test_terrain.gd` |

Models colour their faces by pointing UVs at palette swatches. To hand-edit a model, import the
`.glb` in Blender, edit it, and export it back as `.glb`.

## Extending

- **Placing nodes:** give every placed node its own `save_id` in the inspector. It's the key its depleted state is saved under.
- **A new resource node:** in Godot, right-click `scenes/resource_node.tscn` → *New Inherited Scene*. Set the item, skill and sounds, then either add meshes under `Visual/Body`, `Visual/Chunks` and `Rubble`, or set `model` to a `.glb` whose objects are named `Body_*`, `Chunk_*` and `Rubble_*`.
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
