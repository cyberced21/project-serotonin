# Graphics overhaul: Valheim-style

Status: **done** 2026-10-18, all phases committed on branch `graphics` (off `procgen`), unpushed,
not merged. Open items are in docs/TODO.md ("Graphics overhaul"). Before / after:
docs/images/graphics/before_after.jpg (full sets in `before/` and `after/`).

## Target look

Valheim's look: **low-poly shapes with small, pixelated textures, under heavy atmosphere**.
We keep our shapes and palette, add texture detail, and rebuild the lighting, fog, grass,
trees, water and sky around them. All of it must work in procgen worlds too.

## Decisions

| Area | Decision |
|---|---|
| Surfaces | Textured low-poly. Small (64–128 px) tileable textures, nearest-filtered. |
| Mapping | Keep the palette atlas for colour. Shaders multiply in a greyscale **detail texture**, projected triplanar in world space, so no model needs new UVs. Material kind (bark, rock, planks, leaves…) picked per swatch / per material. |
| Texture source | Generated in code: `tools/make_textures.py` (noise-based, deterministic, tileable), like `make_palette.py` and the sound synths. No downloaded packs. |
| Terrain | Smooth normals plus blended pixelated ground textures (grass/dirt/rock/sand/snow by slope and height, paths from the control map). Replaces `terrain_lowpoly.gdshader`'s faceting. **0.5 m vertex spacing and the sculpt workflow stay in `terrain-detail.md`.** |
| Model shading | Smooth organics (trunks, boulders), hard props (rock seams, crystals, planks, buildings): auto-smooth by angle in `tools/blender`. |
| Trees | Leaf-card canopies: clusters of alpha-cutout quads showing a generated leaf texture, with wind sway, on all four kinds plus background trees. Felling, notches, leaf drop unchanged. |
| Grass | New dense grass system: blade clumps in a ~40 m ring round the player on a moving grid, coloured from the ground, shared wind, bends away from the player, fades at the edge. `SceneryScatter` keeps flowers, bushes, boulders. |
| Atmosphere | Full mood: volumetric fog by biome and time of day, god rays, bloom, per-biome colour-grading LUT, darker nights, flickering shadow-casting firelight on lamps. Builds on `Biome` + `DayNightSky`. |
| Water | Smooth surface, scrolling normals, depth tint, shore foam, sky reflection, sun glint; keep ripples. |
| Sky | Painterly drifting clouds, sun halo; keep the day/dusk/night palettes, moon, stars. |
| Performance | High on the user's PC; **Low / Medium / High presets** that turn off volumetrics, SSAO, SSIL, cut grass density and shadow distance. |
| Settings UI | *Graphics* tab in the debug menu, saved to `user://settings.cfg`. |
| Verification | Screenshot harness: ~6 fixed views (clearing, forest, quarry, meadow, lake, village at dusk) saved per phase into `docs/images/graphics/`, plus an FPS readout per preset. Windowed runs use `--screen 1`. |

Gameplay shader features must survive everywhere: hit flash, hover highlight, night glow,
crystal glow tint, ghost outlines, trunk notches, crack lines.

## Phases

0. ✅ **Baseline harness.** Screenshot-tour script (`tools/graphics_tour.gd`), capture the
   *before* set and FPS.
1. ✅ **Renderer and presets.** Environment work-up: glow, SSAO, SSIL, tonemap and exposure, shadow
   cascades and distance, TAA or MSAA choice. `GraphicsSettings` autoload + debug-menu tab +
   settings.cfg. Applies to `main.tscn` and `procgen.tscn`.
2. ✅ **Texture generator + detail overlay.** `tools/make_textures.py` → `art/textures/`
   (grass, dirt, rock, sand, snow, bark, planks, leaves, ore grain). Add the triplanar detail
   overlay to `node_surface.gdshader`, `sway*.gdshader` and the building/prop materials.
3. ✅ **Terrain.** New smooth, textured terrain shader (keep Terrain3D's vertex/geomorph code
   and the colour-tool multiply). Note in `terrain-detail.md` that its steps 1 and 4 are done.
4. ✅ **Model shading.** Auto-smooth in the Blender scripts, regenerate the .glbs, check rock
   pieces still fit and crack seams still read.
5. ✅ **Leaf-card trees.** New canopies for round, birch, oak, pine and background trees,
   leaf texture, wind sway, shadows, and leaf-drop particles that match.
6. ✅ **Dense grass.** Grass ring system, wind uniform shared with the trees, bending round the
   player, density by preset, works on Terrain3D in both worlds.
7. ✅ **Atmosphere.** Volumetric fog per biome and time, god rays, per-biome LUTs (generated),
   darker nights, firelight flicker plus shadows, bloom tuning.
8. ✅ **Water and sky.** Rebuild `water_lowpoly.gdshader` and `sky.gdshader` as above.
9. ✅ **Wrap-up.** *After* screenshots, README images and text, FPS table per preset.

## Risks

- Leaf cards and dense grass use alpha cutout: watch overdraw and shadow cost; presets must
  cut them.
- Smoothing normals on fitted rock pieces may show seams. Keep seams hard.
- Terrain3D's `terrain_assets.tres` bloats on editor re-save: discard it.
- Headless runs touch the real save: back up `user://save.json` around `godot -s` runs.

## Results

Frame rates from `tools/graphics_tour.gd` at 1280×720 on a GTX 1080 Ti, with another game running
on the same GPU (so they're noisy and on the low side):

| View | Before | Low | Medium | High |
|---|---|---|---|---|
| Clearing | 317 | 255 | 224 | 189 |
| Pinewood | 360 | 302 | 230 | 190 |
| Quarry | 410 | 400 | 329 | 295 |
| Goldmeadow | 348 | 343 | 281 | 236 |
| Stillwater | 298 | 310 | 232 | 193 |
| Hearthvale at dusk | 259 | 295 | 227 | 148 |
| Clearing at night | 315 | 141* | 224 | 186 |

\* a one-off dip (the other game); every other Low view is faster than Medium.

What changed from the plan:
- Tonemapping is ACES, not AgX: AgX left the meadows grey.
- The high preset's shadow atlas is 4096, not 8192: 8192 ran out of video memory next to
  another game.
- Leaf cards ride in the same mesh as the canopy core, marked by a second UV layer, so
  ResourceNode, scatter, shaking and felling needed no changes (PaletteMaterial picks the
  foliage material for meshes with UV2).
- The colour grade is a small lookup table rebuilt from two tints (ColorGrade), so biomes and
  the time of day blend smoothly instead of swapping fixed LUT files.

