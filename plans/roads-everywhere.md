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

## Noted for later

- **Build along** (the user, 2026-11-03): the buildings' piece-by-piece build-along is loved; do
  the same for a better road: in the morning the new surface and edging spread along the road from
  one end instead of appearing at once. Not built yet.

## As built

(after the phases)
