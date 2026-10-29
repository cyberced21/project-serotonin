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

   **Picked 2026-10-29:**
   - *Pieces, a mix:* rubberduck's timber (frames Wooden_01/02/04/09/14/16, planks 21, gate posts
     29, boardwalk 33), lamps on posts (Lamp_01, Lamp_02), chest, boulder, rubble pile, stalactite
     and cluster. loafbrr's rails (straight, curve, junction), carts (tall, low, chassis), stone
     pillars (Post_1/2, half), wood post/beam/brace, rail fence, plank door, the hanging chain,
     tools (pickaxe, shovel, hammer), tub, jar, stone basin, two rocks. Fantasy Props: wall
     lantern, wall torch, pickaxe, crate, barrel, wooden bucket, rope and chain coils.
     Skipped: rubberduck's rails and minecart, the wall lamp; loafbrr's barrier, metal bucket,
     machinery, pipes, valve, post light; the hand cart.
   - *Texture tiles:* **D**, cut from the village kit's own wood, stone and plaster textures.
   - *Tavern:* **the long hall** (one tall timbered storey, windows down the sides, 8 x 14 m).
   - *Forks:* all eleven as proposed (see below).
   - *Sounds:* drips 162116, 177031, 753938; cave air 38963, 476318; stream 414167, 509547;
     cart 465000, 739576; lift 394222; breaking through 381645, 389303; pump 588629, 815126;
     crystal 839945.

   | Building | Slot | Fork A | Fork B |
   |---|---|---|---|
   | Town hall | 1 | Notice board roof: projects cost 10% less | Market flagstones: the trader a day sooner |
   | Prospector | 1 | Ore cart: mine seams regrow 20% faster | Lamp room: a dig face shows what's behind it |
   | Tavern | 1 | Beer garden: evening seats outdoors | Bigger stage: a second musician |
   | Woodcutter | 2 | Timber slide: mine timber 25% cheaper | Bird feeder: feathers twice as often |
   | Fisher | 2 | Eel traps: a fish in the trap each morning | Jetty lantern: calmer fish at night |
   | Smithy | 2 | Ore sorter: extra ore from seams | Tool rack: dig faces break 20% sooner |
   | Bakery | 2 | Pie window: more visits | Pasty basket: first dig face each day twice as fast |
   | Home | 2 | Reading nook: more desk notes | Hearth: a short nap still wakes you well rested |
   | Town hall | 2 | Clock tower: the time on the map | Lamplighter's post: lamps earlier, till dawn |
   | Prospector | 2 | Assay table: geodes and fossils more often | Survey board: unopened cells show their ore |
   | Tavern | 2 | Fireside snug: time passes faster | Guest room: the market twice a week |
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

## As built (2026-10-29, branch `mine`)

All eleven phases, one commit each, bot-tested (`test_quarry`, `test_mine`, `test_forks`,
`test_camps`, plus the old suites), never seen in a game window. Where it differs from the above:

- **Hardness one tier down:** level 1 any pick, level 2 a copper pick, level 3 an iron pick (the
  crystal pick needs crystal, which is only on level 3).
- **Sizes:** 28, 26 and 28 cells (`MineLayout`), 4 m each, a little over the 12-15 planned.
- **The prospector** doesn't walk down the mine (villagers keep to the village's paths): she
  shores the fresh cells overnight and writes about what you find (desk notes).
- **The mine trophy:** a fossil (new, one look, not picked) or a geode, 1 in 10 dig faces.
- **The tavern's top tier** is 8 x 12, not 8 x 14, to stay clear of your home behind it.
- **The clock-tower add-on** is a big clock face over the door (the hall already has its bell
  tower), and **the notice-board one** a lamp post and a bench (the board's already roofed).
- **The second musician** on the bigger stage is Bram.
- **Code:** `Mine`, `MineLevel`, `MineLayout`, `MineSpot`, `MineMouth`, `MineMap`, `MineRide`,
  `QuarryDressing`; `OreWall` gained richness, stone hardness, give-way and seams; the mine is
  its own biome (`Biome.MINE_BELOW`). Pack pieces: `tools/blender/mine_kit.py` -> `models/mine/`.
