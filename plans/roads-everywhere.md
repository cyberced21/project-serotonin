# Roads everywhere

Branch `claude/roads-everywhere-7f270d` (off local `main` at f8aa4af, road travel). Follows
plans/road-travel.md.

The user: "almost all instances of roads upgradable; the cart not on every road, but the speed
bonus on every road." Settled 2026-11-03:

- **Upgradable:** every road and path the map editor draws (as before), plus four *patches*: the
  village lanes (the walkways and the lanes out to the roads), the market place, the quarry's haul
  road and Goldmeadow's field tracks. One card each ("Pack the village lanes", then "Cobble ..."),
  the lanes all on one card.
- **The cart:** runs on the gravel roads only (layout lines of type `road`: the street and the
  roads out), packed or better. Never on paths, lanes or patches. (Recommended default: the user
  answered with a note instead; a per-road editor flag is the alternative if wanted.)

## How

A patch isn't a line: it's the path-painted cells (`TEX_PATH`, or already packed/cobbled) of the
terrain's control map inside its area (the market: `WorldMap.in_market`; the lanes: round the
green; the haul road: inside the pit; the tracks: round the field), less any within a line road's
reach. `Roads` scans them once from the terrain, before `RoadLook` paints anything, and files each
cell under its patch: `bonus_at` reads the cell under you, `roads()` lists the patches (kind
`patch`, priced by their area), `RoadLook` repaints their cells (no edging: they're open ground)
and leaves a road's edging open where a patch meets it.

## Phases

1. Patches: Roads (scan, bonus, list, cost), RoadLook (paint, gaps), Projects (cards: "Pack" /
   "Cobble", no kerbs promised). test_roads: a card per road and patch, the market packed is
   quicker and painted.
2. The cart on gravel roads only (CartLine, the `carter` project's need). test_cart: a packed path
   gets no stops.

3. Build along: a road laid overnight builds itself along when you come to it.

## Noted for later

- **Build along** (the user, 2026-11-03): the buildings' piece-by-piece build-along is loved; do
  the same for a better road. Built as phase 3.

## As built

2026-11-03, both phases, `python tools/run_tests.py test_roads test_cart` passing. Not yet seen in
a game window.

- **Phase 1:** `Roads.PATCHES` / `patch_cells()` (scanned once per terrain, cells within a drawn
  road's reach left to the road), listed by `Roads.roads()` as kind `patch`; `RoadLook` paints them
  and leaves a road's edging open within 1.2 m of a patch cell; `Projects.BETTER_PATCH` words.
  Sizes in Hearthvale and the packing price: market 640 m² (76 stones), lanes 550 m² (66), haul
  road 820 m² (99), field tracks 7000 m², priced at a fifth the rate (167; cobbles twice that).
- **Phase 2:** `Roads.carts_on(r)` (kind `road`): CartLine's network and the `carter` project's
  need. test_cart: a packed footpath neither wakes the cart shed nor gets stops.
- **Phase 3 (build along):** `Roads.laid(was)` at dawn; RoadLook keeps a laid road's old look till
  you're within `REVEAL` (80 m), then paints its cells outward from the point nearest you (both
  ways along a road, out in rings on a patch) at about 25 m/s (2.5-10 s), its edging springing up
  with a little overshoot as the front passes, the packed / cobble footstep sounds knocking at the
  front, dust following it, and at the end the upgrade cue and "<road>, packed!". Loaded worlds and
  the debug menu's levels are just shown. test_roads: away, the old look; back, part laid, then all.
