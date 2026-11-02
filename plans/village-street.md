# The village street

Asked 2026-11-01: the village needs some structure. Today the buildings sit in a loose ring
round the green, each turned its own way, the lanes cross the green like a spiderweb, and none of
the roads reaches the middle. And the villagers roam: each has one work spot by their door, and
half their daytime picks send them to their door or out to the green, so they spend much of the
day walking back and forth.

![The three styles against today](village-styles.png)

## Picked (2026-11-01)

- **A street village**, not a green village or a crossroads. One main street west to east,
  following the quarry road into the east road, about 140 m long with one gentle bend.
- **Tight rows:** buildings 2–5 m apart behind small front gardens, each with a hedged plot about
  18 m deep running back from it.
- **The street widens into the market place** in the middle (about 50 m long, up to 25 m across):
  the pond, the pump, the market stall. The green becomes this paved lens; no separate square.
- **Zoning:** craft at the west end (smithy, woodcutter, timber yard, by the creek and the quarry
  road), civic in the middle (town hall, tavern, baker, chapel on the market place), farm at the
  east end (barn, stable, granary, cart shed and dovecote round a farmyard, turning toward the fields).
- **Your home:** on the street, the last house west of the market, with the biggest plot behind it
  as your garden (the woodshed and the kennel; room for veg beds and trophies later).
- **More empty cottages:** four more copies of the empty cottage, turned and mirrored so they don't
  read as copies, fill the rows; a few gaps stay as gates and alleys to the back plots.
- **Side roads:** the north road and the lake road meet the street at the market's west end; the
  fields road at its east end.
- **Work yards (everyone with a job gets a place to work):**
  - **Open to the street:** the smith's and woodcutter's beside their workshops, the baker's beside
    the bakery on the market place.
  - **Where the job is:** the fisher's at the creek (a jetty and a drying rack); the prospector's
    between her cottage and the ore store, sorting ore.
  - **The mayor** works the market edge in front of the hall (the steps, the noticeboard). **Maud**
    works out front of the tavern (wiping the tables, sweeping the step).
- **Work hours stay in the yard:** a villager moves between their own 3–4 stations, doing a
  different motion at each, with now and then a step to their own door. No trips to the green until
  work ends at dusk; the evenings (benches, strolls, the tavern) stay as they are.

![The street village with its work yards (sketch)](village-street.png)

The sketch is a guide, not the layout. Every spot gets checked again in the editor (the creek,
slopes, roads across pads). Its sizes are real: footprints from `world.json`'s anchors.

## What it touches

- `data/layout/hearthvale.json`: anchors (every building and fixture moves, four new cottages),
  walkways (the old ring and spiderweb go; the street's footways and each door's step join it),
  hedges and fences for the plots, props for the yards and gardens.
- `scenes/main.tscn`: four new `Village/Fixtures/EmptyCottage3..6`, each yard's stations.
- `scripts/world_map.gd` `ROADS`: the main street as a road; the village ends of the quarry, east,
  north, lake and fields roads moved to meet it (`VILLAGE_PATH` and `EAST_ROAD` are fixed control
  points today and don't follow the green).
- The green's contents: `Village/Green` (benches, lamps, crates, the pond, the four spots of
  Rosa's, Edda's, the fisher's and the woodcutter's) and `VillageDecor`'s offsets (noticeboard,
  market stall, well, fountain, planters, baskets, bunting, weathervane, painted cart) are laid out
  for a round green 40 m across. They get new spots inside the lens.
- `scripts/villager.gd` `_pick_spot()` and the work motions; `scripts/building.gd` `work_spot()`.
- The terrain: pads levelled, lanes painted, the village pond dug where the green puts it
  (the editor's Save & bake regenerates it).

## Phases

Branch `street` off `main`, one commit a phase.

1. **Props to pick.** Candidates on a page for each yard's stations: forge, anvil, quench barrel,
   tool rack, chopping block, woodpile, sawhorse, fish-drying rack, jetty, gutting table, bread
   oven, dough table, ore-sorting table, ore heap. CC0 packs first, then what we already have
   (crates, barrels, cart, hay). You pick, then they go in the catalog as props.
2. **The street and the market place.** The main street in `ROADS` and the other roads' village ends
   moved to meet it. The green reshaped into the lens: its benches, lamps, crates, pond and spots,
   and `VillageDecor`'s offsets, re-spotted inside it, with the pump and the market stall on it.
   `test_green.gd` updated for the new spots. Nothing else moves yet.
3. **The buildings on the street.** Every anchor to its place in the rows, facing the street;
   the four new cottages; the farmyard. Walkways redrawn: a footway along each side of the street,
   each door's step, gates into the plots. Terrain regenerated; the editor's warnings and
   `audit_world.gd` clean (nothing overlapping, floating, in the creek or on a slope). Before that,
   check the save: anything stored by position (built decorations, dropped items, the dog's spot)
   that would end up in the wrong place.
4. **Plots and gardens.** Hedges, fences and low walls round each back plot, with gates; your home's
   garden (woodshed, kennel, room to grow); a little clutter in each (barrels, a cart, veg beds,
   washing). The empty cottages get gardens too, so they look lived-in, or nearly.
5. **Work yards.** Each worker's stations as markers in their building's frame (so they move
   with it), each with the motion to do there. `_pick_spot()` by day: their own stations and now
   and then their door, never the green. The fisher's jetty and the prospector's sorting table out
   where they are. The mayor's and Maud's spots. **To settle while building it:** whether a tier adds
   a station (the yard filling out as the building grows, as `Work1..3` move up with the tier today)
   or all the stations are there from the start; default: a tier adds one.
6. **New motions.** Where today's six (chop, hammer, fish, orate, tend, wipe) don't fit: dunking at
   the quench barrel, kneading, carrying, sorting, sweeping. Reuse first, add only what's missing.
7. **Check.** The tests that touch it (`test_green`, `test_walkways`, `test_anchors`, the terrain
   follows test), `audit_world.gd`, the map before and after, headless screenshots down the street
   and of each yard at work, frame times walking the street. Then it's yours to play.

## Not in this plan

- The rest of the map (the road loop, the creek, the empty east, the border): its own grill later.
- What the empty cottages become (new villagers, project unlocks).
