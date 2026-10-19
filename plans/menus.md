# Main menu, worlds and world settings

Agreed on 2026-10-19 (a grilling session). On the `menus` branch, one commit per phase. The game
gets a front door: a main menu, a list of worlds with their own saves, a pause menu, a settings
screen, and a New World screen that configures the generator.

## Decisions

| Question | Answer |
|---|---|
| What a save is | **A list of worlds** (Minecraft-style). Each world has its own character, as today |
| The hand-built world | **A permanent entry**, "Hearthvale (classic)": can't be deleted, only reset. The old `user://save.json` becomes its save |
| World settings | **Seed and name, a kind per biome (or Random), resources lean / normal / rich, water dry / normal / wet, terrain gentle / normal / rugged, and world size** |
| World size | **Small 256 m, Normal 512 m, Large 1024 m.** Bigger means **more biomes**, same biome size. Normal stays exactly today's generator |
| Large worlds | A third ring of sites repeating biomes (preferring an unused kind), one Hearthvale only, a second quarry if it fits |
| Small worlds | Clearing, Hearthvale and the inner ring only |
| Main menu | A **live 3D backdrop** (a small dedicated scene, a slow camera over the clearing), title and buttons on the left; **Continue is the big default** |
| First launch | No worlds yet: Continue becomes **Play** and goes into the classic world |
| Esc in game | A **pause menu** that pauses the tree: Resume, Settings, Controls, Save & Quit to Menu (a "Saved" toast), Quit to Desktop |
| Settings | **Graphics, Display, Audio, Controls** tabs, stored in `user://settings.cfg`, live; key rebinding later |
| Storage | **A folder per world**: `user://worlds/<id>/world.json` (meta), `save.json`, `thumb.png` (taken on Save & Quit). Old `procgen_<seed>.json` saves are imported as worlds |
| Generator changes | Worlds rebuild from seed and settings; `world.json` stamps the **generator version**. An outdated world shows a warning on its card, keeps progress, and spawns at the world's start |
| Loading | Generation on a **worker thread**, spawning spread over frames, a loading screen with stages and a progress bar |
| New World preview | A **live map at reduced resolution**, redrawn after a short pause when a setting changes |
| Dev shortcuts | `-- --classic`, `-- --world=<id>`, `-- --procgen [--seed=N]` (a scratch world, `user://worlds/_scratch/`) skip the menu; `--save-root=<dir>` points all saves elsewhere (tests) |

## Terms

- **World**: one entry on the Worlds screen: a folder with its meta, save and thumbnail.
- **Classic**: the hand-built world (`scenes/main.tscn`).
- **Generated world**: a world built by `ProcgenMap` from its seed and settings.
- **World settings**: the seed, size and knobs a generated world was made with (`WorldSettings`).
- **Scratch world**: the throwaway generated world the debug menu and `--procgen` use; never listed.
- **Generator version**: a number bumped whenever the same settings would build different land.

## Phases

1. **Worlds on disk**: a `Worlds` autoload (folders, meta, migration of `save.json` and
   `procgen_*.json`, the scratch world, `--save-root`, `--classic`, `--world`), the generator version
   stamp, `ProcgenWorld` entering by world instead of by seed.
2. **Main menu**: `scenes/menu/main_menu.tscn` as the main scene with its backdrop; Continue / Play,
   Worlds, Settings (stub), Quit; the Worlds screen (Play, Rename, Delete, Duplicate, Reset classic).
3. **Pause menu**: Esc pauses; Resume, Settings, Controls, Save & Quit to Menu (toast, thumbnail),
   Quit to Desktop; a Controls screen listing the bindings.
4. **Settings**: the four tabs; new Ambience and Movement buses with the players routed onto them;
   mouse sensitivity, invert Y, FOV and camera-kick comfort read by the player.
5. **Generator settings**: `WorldSettings`; the map's constants that the knobs touch become
   parameters; normal settings build exactly today's heightmap (checked against hashes).
6. **Background loading**: `ProcgenMap.generate()` on a worker thread, population spread over
   frames under a time budget, the loading screen.
7. **New World screen**: name, seed (reroll), size, knobs, the live preview.
8. **Small and large worlds**: map size as a parameter, site rings per size, Terrain3D regions.
9. **Wrap-up**: docs, README, TODO.md, screenshots.
