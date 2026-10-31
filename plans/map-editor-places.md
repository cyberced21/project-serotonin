# The map editor, part 2: buildings and places

Asked 2026-10-30: the map editor ([map-editor.md](map-editor.md)) places gatherables, hedges,
props and terrain, but the village's buildings and the named places are locked. The goal was to
hand-build Hearthvale: drag the buildings and places where you want them and have the world follow.

## Picked (2026-10-30)

- **Anywhere:** any building or place can go anywhere on the map (the tavern by the lake is fine).
- **Move and rotate:** drag to move, a handle to turn.
- **Walkways drawn in the editor:** the villagers' walking network becomes a line brush; each
  building's door joins the nearest walkway on its own, and the editor warns when one can't.
- **Move what exists:** the 8 buildings and the named places are one of a kind and only move.
  Lamps, signposts, benches, crates, carts and the like become catalog props you can add freely.

## As built

Branch `places` off `main`, one commit a phase.

- **Phase 1 (2026-10-30):** `data/layout/hearthvale.json` has 27 `anchors` (`{id, node, at, yaw}`:
  the 8 buildings, the 15 `Village/Fixtures`, the watermill, orchard, shepherd's hill and haven),
  read by `LayoutAnchors` (Main's first child; `apply()` for tools that instance `main.tscn` without
  a tree, like the terrain generator's scan of hand-placed things). The places are self-contained:
  each has its own origin with its pieces local to it, and their own things moved under them (the
  mill's two sounds; the flock, hill wind and a skylark; the orchard's bees, butterflies, birds and
  blackbird; the haven's pool, deer track, two deer, frog, critters, blackbird and fish jump).
  `WorldMap.site(id)`, `haven_center()`, `haven_pool_center()` replace `MILL_SITE` and the rest
  (`HAVEN_TRACK` was unused: gone). Every node stands where it stood (checked by dumping all 406
  global transforms before and after: no position moved, turns within 0.1°). `tools/test_anchors.gd`.
  `audit_world.gd` skips the flying critters by their `Critters` script now, not by path.
  `tools/import_layout.gd` (run once, long ago) doesn't write anchors: don't re-run it.
- **Phase 2 (2026-10-30):** a `walkway` line kind (catalog `"walk": true`, no model: the bake
  builds nothing). Today's network (32 points, 39 links) imported as 20 walkway lines, the green's
  ring one closed line marked `stroll` (villagers' strolls round the square follow it:
  `VillagePaths.ring()`). `VillagePaths.graph()` builds the network from them: corners within
  0.75 m are one point, a line's end landing on another's leg splits it, and a building's `Door`
  with no point within 4 m gets one on the nearest leg (the last step onto a door stays off the
  network, as before). The imported graph is today's, link for link, but for the noticeboard's
  link now running through the town hall's front (which sat on it). The editor draws walkways
  dotted and gives them a Stroll box instead of gates. `tools/test_walkways.gd`.
- **Phase 3 (2026-10-30):** a `Village/Green` node at the green's middle (128, 128), anchor
  `green`, with the green's own things under it: its two benches, four lamps, the crates by the
  fisher's hut and the village pond (its water and fish; the pond's dug bed is the terrain's, phase
  4). `VillageDecor` takes its middle and turn from that node, so the noticeboard, market stall,
  well, fountain, planters, bunting and the rest turn round the green. The kennel (and its door,
  porch, bowl, blanket) is in your home's frame, Rosa's terrace in her bakery's
  (`VillageDecor.frame_of`). The four spots that reached out to the green (Rosa's and Edda's
  Square, the fisher's and woodcutter's Bench) are markers on the green now
  (`Village/Green/<building id>_<spot>`), which `Building.spot()` falls back to; the town hall's
  Square (12.5 m out, its own front) stays its own. `WorldMap.VILLAGE_CENTER` became
  `village_center()` (the green's anchor), for the biome cards, the dog, the lamps, the trader and
  the terrain generator. `tools/test_green.gd` turns your home, the lodge and the green a quarter
  and moves the bakery 20 m, and checks each spot went with its owner.

## What moves

| Thing | Today | Moves as |
| --- | --- | --- |
| Town hall, woodcutter, smithy, fisher, bakery, prospector, tavern, your home | `main.tscn` `Village/*`, world transforms | one anchor each (x, z, turn) |
| The green (market stall, noticeboard, benches, terrace seats, the well) | `VillageDecor`, offsets from `VILLAGE_CENTER` | one anchor; its pieces stay relative to it |
| Kennel | `VillageDecor`, off the green | follows your home |
| Watermill, orchard, shepherd's hill | `Places/*`, children in world coords | one anchor each, children made local |
| The hidden haven | `Places/Haven` (has a transform) + `HavenPool`, `DeerTrack`, its sounds and deer outside it | one anchor, everything pulled inside |
| Fixtures (barn, granary, chapel, ...) and the yards' props | `Village/Fixtures`, `Village/Yards`, world coords | one anchor each |
| Village lamps and signposts | `Village/Props`, world coords | catalog points (add, move, delete) |
| The mine mouth, the quarry, the clearing | placed from `WorldMap` constants | stay put in this plan (see Later) |

## How it works

- **Anchors in the layout:** `data/layout/hearthvale.json` gets an `anchors` list:
  `{id, x, z, turn}` per building, place and fixture. `scenes/main.tscn` keeps the nodes; a
  `LayoutAnchors` node on `Main` moves each one to its anchor in `_enter_tree`, before anything
  under it is ready, so every script sees the final position. No re-save of `main.tscn` by a tool.
- **Places become self-contained:** each place gets its own transform and local children (the
  mill's wheel, sounds and path end; the haven's pool, deer track, deer and blackbird), so moving
  the anchor moves all of it.
- **`WorldMap` reads positions, not constants:** `MILL_SITE`, `ORCHARD_SITE`, `SHEPHERD_SITE`,
  `HAVEN_*`, `VILLAGE_CENTER` and `LANDMARKS` come from the anchors (the layout file, so the terrain
  generator and the game agree). Biome detection, the trader's park, the dog's checks and the
  minimap labels follow.
- **Terrain follows:** each anchor flattens a pad under its footprint (soft edge, like a flat
  shape), and the haven digs its pool where the pool now is. The door lanes in
  `generate_test_terrain.gd` (`LANES`) are worked out from each building's `Door` marker instead of
  a list of world points. Roads to a place end at its `RoadEnd` marker; saving with an anchor moved
  re-runs the terrain like a terrain shape does (~75 s).
- **Walkways:** a new line kind, `walkway`. `VillagePaths.POINTS` (world coords today) becomes the
  baked walkway lines plus one link from each building's `Door` marker to the nearest walkway. The
  import turns today's network into walkway lines, so nothing changes until you edit it.
- **Spots that reach out:** a building's `Square` and `Bench` markers reach 30-40 m to the green
  or a bench, so they swing wrongly once it's turned or moved. They become named spots on the
  green anchor (or a bench prop), picked by name.
- **Lamps along the roads** already place themselves from the roads at load and keep clear of the
  buildings where they stand (`PathLamps`); the village's own lamps and signposts become points.
- **Animals:** each herd's home is its spawn position today; herds by a place move with it (the
  sheep at the fold, the haven's deer), the rest stay where they are.
- **Saves:** buildings save by id, not position, so a move keeps their tiers and add-ons. A saved
  player position that ends up inside a moved building is stepped out to its door.

## The page

- A **Buildings** layer (not locked any more): each building, place and fixture drawn as its real
  footprint, turned, with its name. Select to move (drag) or turn (a handle, snapping to 15°;
  hold Shift for free). The properties panel shows x, z and turn to type in.
- **Warnings** after a bake, clickable: footprints overlapping, a door with no walkway in reach, a
  place on ground steeper than its pad can level, a road crossing a footprint, an anchor in water.
- `tools/export_map.gd` exports each thing's id, footprint (a box, not a circle) and turn, so the
  page can draw it; it already exports the rest of the map picture.

## Phases

1. **Anchors, no editor change yet.** The `anchors` list, `LayoutAnchors`, places made
   self-contained, `WorldMap` positions read from the layout; the import writes today's positions,
   so the world loads exactly as now. Checks: every node stands where it stood (a test comparing
   transforms), `audit_world.gd`, `test_day`, `test_paths`.
2. **Walkways as lines.** The `walkway` line kind; `VillagePaths` built from the baked lines and
   the door links; today's network imported as lines. `test_paths`, `test_day` unchanged.
3. **The spots and the green.** `Square`/`Bench` spots named on the green; market, noticeboard,
   benches and terrace on the green anchor; the kennel on your home. A test turning every
   building 90° and checking each villager still reaches its spots (`test_day`).
4. **Terrain follows.** Pads under anchors, lanes from `Door` markers, roads ending at `RoadEnd`,
   the haven pool dug where it is. A test moving the mill 60 m and checking its pad is level, its
   road reaches it, and its wheel sits in water when it's on the creek (warns otherwise).
5. **The page.** The Buildings layer, move / turn / type in, the export with footprints and turns,
   the warnings. Save & bake re-runs the terrain when an anchor moved.
6. **More props in the catalog.** Village lamps, signposts, crates, barrels, carts, logs, fences,
   the yards' pieces; the village's lamps and signposts imported as points.
7. **Checks and pictures.** Move a few things for real (the tavern to the lake, the orchard to the
   other side of the green, your home turned), bake, run `audit_world.gd` and the village tests,
   screenshots from `tools/graphics_tour.gd`; then put everything back.

## Things to know

- The mill's wheel wants the creek: the editor lets you put the mill anywhere, but its wheel only
  turns in water (a warning says so).
- Moving a building leaves its old ground as it was until the terrain re-runs (Save & bake does
  that when an anchor moved).
- `tools/village_layout.gd` (stale `CENTER`) and `tools/perf_probe.gd` (hard-coded node paths) get
  updated or dropped in phase 7.
- A gatherable patch avoids buildings only when it's baked: moving a building over a patch needs a
  re-bake (Save & bake does it).

## Later (not in this plan)

- Moving the mine mouth and the quarry (it's cut into the land by the generator and the mine's
  levels hang off it), the clearing, the creek, the lake and the biome borders.
- **Water you draw** (asked 2026-10-30, once this plan is done): investigate drawing rivers and
  streams as a line and lakes and ponds as a shape in the editor, the terrain carving their beds
  and the water, fish and banks following (today the creek is `WorldMap.CREEK`, built by
  `creek.gd`, and the lake is hard-coded).
- New buildings (more houses or barns from a list).
- The hard-coded land (the bowl, the village flat, Frostpeak) as terrain shapes.
