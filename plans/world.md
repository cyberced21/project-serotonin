# World: one curated Hearthvale that feels like one piece

Asked 2026-10-28: procedural worlds go; Hearthvale (the hand-built world, `scenes/main.tscn`) is
the one map. Today its ground is jagged and it reads as pieces stamped onto each other. Grilled
2026-10-28. Branch `world` off `main`.

Status: **all 7 phases built** 2026-10-28 on branch `world` (one commit each). Checked headless
only: slope maps (docs/images/world/), `tools/test_creek.gd` and the other tests (all pass but
`test_lamps`' two timing checks, which failed on `main` too). **Not played; no in-game
screenshots yet.** Open items: docs/TODO.md, "World".

## Where we start (2026-10-28)

The terrain comes from `tools/generate_test_terrain.gd` (shapes in `scripts/world_map.gd`), 512 m
square, 1 m between vertices. A slope map of the saved terrain (green gentle, orange/red steep,
black sheer):

- **Speckle everywhere off the flats**: a high-frequency "bumps" noise (lumps every ~15 m, 1.5 m
  tall) on top of the hills, so ~10% of the ground is steeper than 30° and every hillside is rough.
- **Round craters**: the clearing, the village and the lake basin are perfect circles of flat
  ground with a ring of hills easing up around them, like three dishes set on a table.
- **Movement-era hard edges** (wall-run and dash went with the calm feel; only the mantle is
  left): road cuttings with sheer walls wherever the ring road cuts > 2.5 m into a hill, banked
  bends, a 6 m gully gap across the road, the quarry's five sheer 5 m pit walls, the peak's
  sheer shell.
- **Stamped biomes**: the quarry shoulder, Goldmeadow's disc of swells and its ruler-straight
  crop grid, the Pinewood ellipse: each a shape pasted over the base hills with a hard texture
  border.
- **Pinned islands**: the generator puts the old ground back within 3-10 m of every hand-placed
  node (their Y is baked into main.tscn), leaving bumps and dips where the new land meets them.
- **The ring road** is a perfect loop that ignores the land, joined to each place by straight spurs
  that end in cuttings.

## Decisions (grilled 2026-10-28)

- **Procgen is removed fully**: `scripts/procgen/`, `scenes/procgen.tscn`, the New World screen,
  generated worlds in `Worlds`, the generator tools. Tools and benches that used the scratch world
  (`play_scratch(42)`) use Hearthvale under `--save-root` instead. Old generated world folders on
  disk are left alone and simply not listed.
- **Same places, new ground**: the clearing, village, lake, Pinewood, quarry, Goldmeadow and the
  peak stay roughly where they are (saves, lamps, projects keep meaning the same places); all the
  land is regenerated.
- **Soften everything, add a creek**: no sheer walls anywhere except a few deliberate crags on the
  peak. The gully goes; a creek runs from the Pinewood hills down through the valley into the
  lake, and the footbridge project spans it. The quarry becomes gentle terraces joined by sloped
  ramps.
- **Roads follow the land**: the ring and spurs are replaced by winding roads that go round hills
  and along valleys, joining every place to the village like a countryside.

## Principles

- **One land, then places on it**: a single height function (broad rolling hills, low-frequency,
  domain-warped so nothing is round) that every place *eases into*, never a shape pasted on top.
- **Slopes a person would walk**: off the peak, nothing steeper than ~30°; most ground under 15°.
- **Soft borders**: every biome edge is a wide, noisy blend, in height, texture and scatter.
- **Hand-placed things follow the ground**, not the other way round: a tool re-bakes their Y after
  each regeneration (no more pinned islands); anything with `snap_to_ground` snaps at runtime.
- **Saves survive**: a saved player position that ends up under the ground is lifted onto it.

## Phases (one commit each)

1. **Remove procgen.** Delete the generator, its scene, the New World screen and the generated
   kind in `Worlds`; strip the procgen branches from biome, fireflies, map data, path lamps,
   village decor, footbridge, node spawner, ore wall placer, scatter, loading screen, menu, debug
   menu. Move every tool/bench/test off `play_scratch` onto Hearthvale. Done: the game boots to a
   menu with one world; `test_worlds`, `test_lamps`, `test_projects` pass headless.
2. **The new ground.** Rewrite the base height: warped low-frequency hills, organic flats for the
   clearing, village and lake (warped edges, long gentle rims), no bumps noise, a slope-limiting
   relax pass, the world's edge rising into a ring of higher hills so the valley feels enclosed.
   Replace `_protect` with a re-bake tool that sets each hand-placed node's Y to the new ground.
   Done: slope map has < 2% of cells over 30° and no sheer cell outside the peak; every
   hand-placed node sits on the ground.
3. **The creek.** A spring in the Pinewood hills, a shallow wadeable bed with soft banks winding
   down past the clearing into the lake; a water surface along it (WaterBody), the footbridge
   moved onto it where the road to the lake crosses. Grayling (holding in the current) and
   salmon (deep pools at the bends) move here: they lived only in generated worlds' rivers.
   Done: walk the creek's length without a ledge; the footbridge project builds over it; both
   fish bite.
4. **Roads that follow the land.** Lay the network with a least-cost path over the terrain
   (slope and height change cost, water costs a crossing): the village hub to the clearing, the
   lake, the Pinewood trail, the quarry and Goldmeadow. Roads settle into the ground with gentle
   shoulders (a cutting at most ~1 m, no sheer walls, no banking). `WorldMap`, `RoadCourse`,
   `PathLamps`, the map and the lamps' stretches follow the new lines. Done: every road walkable
   end to end, lamps line them, the map draws them.
5. **Blended biomes.** Wide warped masks for the Pinewood, Goldmeadow and the quarry; texture
   blending across borders (Terrain3D overlay + blend); scatter and spawners thin out gradually.
   Goldmeadow's grid becomes fields that follow its swells. Done: no straight or circular border
   visible from the ground.
6. **The quarry: faces kept, the rest softened** (decided 2026-10-28: its sheer walls are the
   ore walls' faces, so they stay). The mantle stairs go (the haul road already walks you to the
   floor), the mountainside falls away over a longer, wandering slope, the apron's edge frays.
   Done: walk to the bottom without a mantle; the ore walls stand on every ring.
7. **Pictures and checks.** Before/after slope maps and screenshots (`graphics_tour.gd`), the
   minimap/world map, the README and TODO; all headless tests pass.

## Open (decide while building)

- Whether the creek also feeds the village pond.
- The mine (cozy chunk 6) will want an entrance in the rocky hills: leave a spot for it by the
  quarry.
