# The Hearthvale designer (town mode in the map editor)

A part of the map editor (`tools/map_editor/`) for the village itself: its buildings, plots,
yards, decorations, the street and the market place. Cozy first: it's for making the village feel
lived-in, quickly, without hand-placing every flower.

## Picked (2026-11-06, grilled)

- **Town mode in the same editor**, not a separate page: a "Town" button in the header zooms to the
  village area and swaps in the town tools and a village-only list. Same file, same undo, same
  Save & bake. Works on **any map's village** (wherever its `village` area is), not only Hearthvale.
- **Add buildings from a list.** The models the village already has (empty cottage, barn, cart
  shed, granary, stable, storehouse, woodshed, dovecote, washhouse, ore store, timber yard, ruined
  cottage) as a palette: drop one in, copy it, delete it. The story buildings (smithy, tavern, your
  home...) stay one of a kind: they move and turn, they can't be copied or deleted.
- **An added building is scenery that fits in:** levelled ground under it (a pad), its door joined
  to the walkways, lamps and patches keeping clear of it, on the in-game map. Nobody lives in it.
- **Plots** (a house's back garden): drawn as a shape, owned by a house (it moves and turns with
  it), edged with a hedge, fence or wall with a gate gap on the side facing the house, filled with
  a garden style (vegetables, flowers, orchard, paddock), and kept clear of scattered trees and
  rocks.
- **Decorations:** a palette with pictures (each prop drawn small, from above), click to stamp;
  a scatter brush; a row along a line; front-garden presets (one click dresses a house's front).
- **Work yards** (each worker's stations, today written in code) move into the layout: select a
  building to see its yard, drag and turn its props and stations (where the worker stands), add or
  remove props from the yard kit. They still go where the building goes.
- **The street and the market:** the street line as now; the market lens (the widened part of the
  street, today 52 m long and 14 m either side) sized and moved with handles; everything on it
  (stall, noticeboard, well, fountain, planters, baskets, bunting, cart, benches, the villagers'
  standing spots) draggable.
- **Walkways update themselves, hand edits kept:** every door without a walkway near it gets a lane
  drawn from its step to the nearest walkway, and the street's own walkway follows the street.
  Those are marked `auto` and redrawn whenever a building or the street moves; lanes you draw stay.
- **Done:** every phase works in the browser; a test edit (two cottages, a plot, a yard tweak,
  some decorations) saves and bakes cleanly with the tests and `audit_world.gd` passing; then the
  test edit is undone, so Hearthvale's layout is unchanged unless you change it.

Not doing: mirrored copies (a negative scale breaks the collision shapes Godot builds); copies
get their variety from turning and from their gardens instead. New models: later, through a pick
page.

## Words

- **Anchor:** one entry in the layout's `anchors` list: where a building, fixture or place stands
  (`at`, `yaw`). Today each names a node in `scenes/main.tscn`; an added building names a `type`
  from the catalog instead, and the game makes it.
- **Pad:** the level ground the terrain generator cuts under an anchor (`pad`: its radius, m).
- **Owned:** a point, line or plot with `owner: <anchor id>`. The editor carries it when its owner
  moves or turns; the game just reads where it is.
- **Walkway:** a line villagers walk along (`walkway` lines); `auto` ones are the designer's.

## Data

- `catalog.json` gets `buildings`: `{type: {label, model, pad, box, door, kind}}` (box and door in
  the model's own frame, so the editor can draw one before the map export has measured it), and
  `gardens` (plot fills: `{label, items: {prop: weight}, spacing}`) and `presets` (front gardens:
  `{label, props: [[prop, [x, z], yaw]]}` in the house's frame, +Z its front).
- `anchors`: `{id, type, at, yaw, area: "village"}` for an added building (no `node`). A story
  building's anchor may carry `yard: {props: [[model, [x, z], yaw, solid, y?]], stations:
  [[[x, z], yaw, motion, tier, y?]]}` in its own frame. The green's may carry `market: {length,
  half_width}` and `spots: {name: [x, z, yaw]}` in the green's frame.
- `plots`: `{id, owner?, points (world), edge: hedge|fence|wall|low_wall|none, gate: [edge index,
  width m], fill: none|<garden>, seed}`.
- `points` and `lines` may carry `owner`; walkway lines may carry `auto: true` (and `follows`: the
  road it follows).

## Phases

One commit a phase, on this branch (`claude/town-designer-f0b3b6`).

1. **Town mode.** The Town button (and `?town=1`), zoomed to the village area; the town tools in
   the toolbar; the list shows only the village's things, grouped (buildings, plots, yards,
   decorations, lanes). Off: the editor as it was.
2. **Added buildings.** Catalog `buildings`; `LayoutAnchors.apply` makes a `Fixture` for an anchor
   with a `type` (under `Village/Added`, a `Door` marker at the catalog's door); `Fixture.door_point()`;
   pads, the map export and the walkways' door links pick them up as they do the others. Editor:
   the Building tool (palette, place, turn), copy and delete for added ones only.
   Test: `tools/test_town.gd` (an added cottage stands where its anchor says, has a door, is kept
   out on a map without it).
3. **Owned things and front gardens.** Points, lines and plots with an `owner` move and turn with
   it in the editor; a building's panel gets "Dress the front garden" (the presets) and "Clear its
   garden".
4. **Plots.** The Plot tool (draw a shape by a house: it's owned by the nearest one), its panel
   (edge, gate, fill, reseed); drawn with its edge and gate. `bake_layout.gd`: the edge as a line
   with the gap, the fill scattered inside, a keep-clear so patches stay out. Test in `test_town.gd`.
5. **Decorations.** Prop pictures rendered from above by Blender (`tools/blender/prop_icons.py` ->
   `tools/map_editor/icons/`); the town palette (grouped: garden, lamps and seats, farm, yard,
   market); the Stamp tool (click, R to turn, random turn), the Scatter brush (radius, density, a
   mix), the Row tool (draw a line, a prop every N m, facing along or across).
6. **Work yards in the layout.** `WorkYards` reads the anchor's `yard` (else its own table, so an
   old layout plays the same); Hearthvale's written into the layout as they are today. Editor: a
   selected building shows its yard; drag and turn props and stations; add or remove props from
   the yard kit; a station's motion and tier in the panel. `test_day` unchanged.
7. **The market in the layout.** The green's `market` and `spots`: `WorldMap.market_*`, the
   generator's paving, `VillageDecor` and the green's markers read them (else today's numbers).
   Editor: the lens drawn with handles for its length and width; each spot draggable and turnable.
   `test_green` unchanged.
8. **Lanes that follow.** Auto door lanes for doors with no walkway within reach; the street's
   walkway following the street (`follows`); redrawn when a building, plot or the street changes;
   hand lanes untouched; the door warnings see the auto ones.
9. **Checked.** The test edit made in the browser, saved, baked with the land regenerated; the
   touched tests and `audit_world.gd`; the test edit undone; Hearthvale's layout back as it was.

## As built

(filled in as the phases land)
