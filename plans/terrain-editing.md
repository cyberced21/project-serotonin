# Terrain editing in the map editor

Branch `terrain-edit` (off `main`), one commit per phase.

**Goal.** The map editor (`tools/map_editor/`) shapes the land itself: draw a river (a line with a
width and a depth: a channel is carved and water put in it), deepen or reshape the lake and the
ponds, and raise, lower, flatten and smooth ground. Save & bake regenerates the land
(`tools/generate_test_terrain.gd`), redraws the map and bakes the layout, and it's there in game.

## How it works today

- The layout's `terrain` list (`data/layout/hearthvale.json`) is read by the **terrain generator**,
  not the layout bake. It builds the 768 x 768 heightmap (1 m a cell) in this order: base hills and
  the built-in ponds (`PONDS`: clearing pond, village pond, lake) → biomes, Frostpeak, rim →
  glades → **the layout's shapes** (`_layout_shapes`: `flat`, `raise`, `pond`) → pads under anchored
  buildings → relax pass (eases anything steeper than ~24°) → the creek's channel (`_carve_creek`,
  masked so the relax pass and roads leave it alone) → roads and paths (`road`/`path` shapes too)
  → relax again. It records what it applied in `terrain_applied.json`, so the editor knows the
  land is stale and re-runs it on the next bake (~1 min).
- **Water** is one level everywhere: `WATER_LEVEL` = -0.15 m. A pond is a bowl dug below it
  (`_pond`: circle + shore noise). The water itself is a `WaterBody` (an Area3D with a box volume,
  a surface plane, PondDressing, FishPond). The clearing pond and the lake are hand-made nodes in
  `main.tscn`; the village pond sits on the green (it moves with its anchor); a layout `pond` gets
  its water from the layout bake (`tools/bake_layout.gd` `_pond` → `Layout/Water`).
- The **creek** (`WorldMap.CREEK`, `scripts/creek.gd`) is the model for a river: a spline, a vale
  eased down to the water through the hills, a rounded channel under the water, soft banks; in
  game a strip surface along it and a WaterBody every 10 m (with flow, fish), and a bridge where a
  road crosses.

## Decisions

- **Rivers sit at the water line** (-0.15 m) like the creek and ponds, so they meet the lake and
  ponds without a step. Across higher ground the river cuts itself a vale (the land eased down to
  the banks over `vale` m each side, default 30), as the creek does through the bowl's rim. No
  sloped rivers or waterfalls in this pass.
- A river is `{"type": "river", "points": [...], "width": 4, "depth": 0.8}` (+ optional `vale`,
  `fish`). The line is smoothed with `WorldMap.spline`, the same in the generator and in game.
- **The clearing pond and the lake move into the layout** as `pond` shapes (ids `pond`, `lake`), so
  the editor can deepen, move, resize and reshape them; their hand-made nodes leave `main.tscn`
  and the bake builds them (same names, `Pond` and `Lake`, same fish). The village pond stays
  with the green.
- **Ponds can be outlines** (a polygon) as well as circles: the bowl follows the outline (with the
  same shore noise), deepest a `shelf` m in from the shore.
- **Smooth** is a new shape (polygon or circle): the land inside is blurred over `strength` m,
  easing out over its soft edge. Raise / lower / flatten are the existing `raise` and `flat`.
- `scripts/layout_water.gd` (`LayoutWater`) reads the layout's ponds and rivers for everyone:
  the generator, the bake, the creek (which leaves its surface out where it runs into a pond).

## Phases

1. **Rivers carve the land.** `LayoutWater`; `river` shapes in the generator: vale eased in with
   the other shapes (before the relax pass), channel carved with the creek (masked: the relax
   pass and roads leave it; roads cross it like the creek, by a ford or bridge; the road router
   treats it like the creek). The generator's `--report` lists each river's bed depth and each
   pond's deepest point. Editor: a River brush (a line; width and depth), drawn at its width.
   Test `tools/test_terrain_shapes.gd`: a dry run of the generator on a test layout with a river
   and a pond, checking the bed and the depth from its report.
2. **Rivers get their water.** `scripts/river.gd` (`River`, the creek's surface/stretches/bridges
   made general: `Creek` takes its line, half-width and level from overridable functions); the
   bake puts one under `Layout/Water` per river. `test_layout` checks every river has its water.
3. **Ponds as outlines; the lake and clearing pond into the layout.** Polygon ponds (generator
   and bake: the water's box covers the outline); `shelf`, `fish`, dressing counts; the editor's
   Pond brush draws circles or outlines and shows the depth. The clearing pond and lake become
   layout shapes, their nodes come out of `main.tscn`, the generator's `PONDS` keeps only the
   village pond, `Creek.in_other_water` asks `LayoutWater`. Regenerate the land, redraw the map,
   rebake; tests pass.
4. **Smooth, and the editor's land tools together.** `smooth` in the generator and the editor;
   one Terrain bar: Flat, Hill / hollow, Smooth, Pond, River, Road, Path, with tooltips that
   say what each does; the slope hint for raise works for smooth too.
5. **End to end.** On a throwaway copy of the layout: draw a river into the lake and deepen the
   lake, run the editor's terrain pipeline (generate, map, bake) into a scratch layout, check in a
   headless run that the river's WaterBodies are there, the bed is under the water and the lake's
   deepest point moved down. Tests: `python tools/run_tests.py layout terrain_shapes creek dog
   terrain_follows` (and whatever else the phases touched).

## As built

- Phases 1-4 as planned. Extra: layout ponds are dug again after the relax pass (it filled a
  bowl dug into a hillside) and kept from the second one; `scripts/map/map_data.gd` skips water a
  rebake freed (the bake frees the old Layout, which now has water in it: it crashed).
- Phase 5: `tools/test_water.gd` checks the layout's water in game, whatever the layout has (each
  pond as deep as asked with its fish; each river wet, wadeable and flowing all the way). End to
  end, in the editor: a 5 m river drawn from the western hills into the lake and the lake set to
  1.6 m, Save & bake (it asked to regenerate the land: 113 s for land, map and bake), then
  `test_water`: the river wet all 62 sampled points with its current, the lake 1.60 m at its
  deepest. That river was thrown away after (the layout stays as committed).
- How to use it: Terrain tool → River: click along it from its source down (start it up a hill,
  end it in a pond, the lake or the creek), Enter; width/depth/vale in the panel. Pond: Circle or
  Outline. Click the lake (or the clearing's pond) to change its depth or drag its middle and edge;
  "Make it an outline" turns it into a 12-cornered outline (same id, fish and water) whose corners
  drag and add like a patch's. Save & bake regenerates the land when terrain changed.
- Known: a river's water is level, so up in the hills its vale cuts a groove down to the water
  (the steeper the hill, the deeper the groove at its source). Start rivers low, or in a hollow.

## Not in this pass

- Sloped rivers (water that falls with the land), waterfalls.
- Painting textures by hand; finer sculpting (plans/terrain-detail.md).
- Moving the creek itself into the layout (it's tied to the mill, its pools and the bridges).
