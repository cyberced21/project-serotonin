# The mine (cozy chunk 10) and the chunk 9 leftovers

Grilled 2026-10-29. Umbrella: [cozy.md](cozy.md) section 6. Branch `mine` off `main`.

## The quarry: decorated, rocks only

- Greystone's five-level pit stays, but **loses its ore walls**. It becomes the open-air, everyday
  source: **ore rocks over all five levels** (copper, coal, iron), growing back as now.
- Dressed as a working quarry: cranes, carts, crates, sorting tables, a tool shed, lanterns on the
  ledges; moss, ferns and wildflowers in the cracks, a little pool on the floor.
- **The mine mouth**: a timbered entrance on the pit floor, boarded up until the first upgrade.
- Old saves drop their quarry ore-wall state.

## The mine

- **Below the quarry, in the same world** (no loading screen): built far under the pit, entered
  through the mouth with a short fade; later by the lift and the minecart.
- **A hand-laid grid.** Each level is designed by hand on a grid of cells (a cell = one tunnel
  segment or a chamber). Unopened cells are solid rock. Same map every game; surprises placed on
  purpose.
- **Two kinds of wall** (both ore walls, `plans/ore-walls.md`):
  - **Dig faces**: the rock at a dead end. About 30-60 s of swinging breaks through, giving ore as
    you go, then a small reveal: dust settles, and the new cell's lanterns flicker on if it's shored.
    Opening is permanent.
  - **Ore seams** along the sides of opened tunnels: they grow back like quarry rocks, so the mine
    stays worth visiting once it's all open.
- **Three levels, ~12-15 cells each** (~40 in all):
  1. Earthy tunnels: copper, coal, a little iron.
  2. Rusty rock, an underground stream: iron, gold.
  3. Glowing crystal caverns (cozy, not spooky): gold, crystal.
- **Ores**: the mine's walls give more per swing than quarry rocks and are the **only source of gold
  and crystal**.
- **Gating**: rock hardness by pick tier (earth: any pick; rusty rock: iron; deep rock: the best),
  depth by mine upgrades.
- **Light**: dim and warm. Lanterns hang wherever a tunnel is shored; your lantern and the dog light
  freshly dug cells. Never pitch black.

### Mine upgrades (noticeboard projects)

- **Timber shoring + lanterns**: shore the entrance (opens level 1), then each level's tunnels.
- **Shaft and lift**: from the pit floor down to each level; opens levels 2 and 3.
- **Rails and minecart**: a calm ~20 s rattling ride from the entrance to the deepest level you've
  opened, lanterns going past; skippable. Fast travel.
- **Obstacles, cleared like the landslide**: a flooded tunnel on level 2 needs a pump; a collapse
  needs timber supports.

### Around it

- **The prospector** runs the mine: works down there by day, remarks on new chambers.
- **Mine map**: M underground shows the level's grid, opened cells drawn, unopened ones blank.
- **A mine trophy**: a rare geode or fossil while digging, for the trophy wall.
- **Sound**: drips, cave air, the cart's rattle, the lift; CC0 recordings picked by ear.

### Art

Tunnel rock and walls in our organic rock style; timber frames, lanterns, rails, carts and crates
from CC0 packs (Quaternius / KayKit). Candidates on a page; the user picks first.

## Painted texture tiles

Grain and wear tiles for our own models so they sit closer to the packs' look; starting with the
mine rock, then the rest of our models. Candidates on a page.

## Chunk 9 leftovers

- **Second add-on slots**: open at each building's top tier; same rules as slot 1 (a fork of two,
  build one, swappable). New forks for every building, plus slot-1 forks for the town hall, the
  prospector (mine-flavoured, e.g. ore cart: seams regrow faster / lamp room: a dig face hints at
  what's behind it) and the tavern. All proposed on a page; the user picks or edits.
- **Tavern restyle**: the Sleepy Hound rebuilt from the Quaternius kit, keeping its room, seats,
  dice and fiddle.
- **Walk-in camps**: the lean-to, fire pit, fisher's tent and meeting hut get a place villagers
  sleep in; nobody vanishes at the door.
- **Trophy hints**: a soft tell that a rare feather or shell is near: a sparkle sound, the dog perks
  up and looks that way.
- **Drop the old `.glb` houses** and their `make_village.py` code.

## Phases

Each phase is a commit on `mine`. Stop after phase 1 for the user's picks; then run through.

1. **Pick pages.** Mine art (tunnel rock, timber, lanterns, rails, cart, lift), painted texture
   tiles, the tavern's kit look, the add-on forks (text), mine sounds. Stop for picks.
   *Up 2026-10-29 on one page: https://claude.ai/artifact/XZMpnyVD8s7zMfH45Ajfg8. Packs:
   loafbrr_1's Mine Object collection and rubberduck's free mine assets (both CC0, OpenGameArt,
   in E:\Godot\downloads\mine-packs); 37 Freesound CC0 clips in E:\Godot\downloads\mine-sounds.*
2. **The quarry.** Ore walls out, rocks over every level, props, greenery, the boarded mouth, save
   migration. Done: screenshots of every level; a bot mines a rock on the floor.
3. **The mine framework + level 1.** Cells, dig faces, seams, the space under the pit, the entrance
   fade, saves, pick-tier hardness. Done: a bot digs through a face and a new cell opens and saves.
4. **Upgrades.** Shoring + lanterns, the shaft and lift, the pump and the collapse. Done: a bot
   builds the lift and rides to level 2.
5. **Levels 2 and 3.** The stream, the crystal caverns, gold and crystal. Done: screenshots.
6. **Rails and the minecart.** Done: a bot rides to the deepest open level.
7. **The prospector, the mine map, the geode/fossil trophy.** Done: a bot sees the map fill in.
8. **Painted texture tiles.** Done: before/after screenshots.
9. **Add-on slots 2 + the new forks.** Done: a slot-2 fork built and read by `Village.stat()`.
10. **Tavern restyle, walk-in camps, trophy hints, old `.glb`s gone.** Done: screenshots; a bot
    follows a camp villager to bed.
11. **Sounds, screenshots, README, TODO, the plan as built.**
