# Graphics overhaul: Valheim-style

Status: planned 2026-10-18, not started. Branch `graphics` off `procgen`. One commit per
phase; run the phases straight through and report at the end.

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

0. **Baseline harness.** Screenshot-tour script (debug menu or `-- --shots`), capture the
   *before* set and FPS.
1. **Renderer and presets.** Environment work-up: glow, SSAO, SSIL, tonemap and exposure, shadow
   cascades and distance, TAA or MSAA choice. `GraphicsSettings` autoload + debug-menu tab +
   settings.cfg. Applies to `main.tscn` and `procgen.tscn`.
2. **Texture generator + detail overlay.** `tools/make_textures.py` → `art/textures/`
   (grass, dirt, rock, sand, snow, bark, planks, leaves, ore grain). Add the triplanar detail
   overlay to `node_surface.gdshader`, `sway*.gdshader` and the building/prop materials.
3. **Terrain.** New smooth, textured terrain shader (keep Terrain3D's vertex/geomorph code
   and the colour-tool multiply). Note in `terrain-detail.md` that its steps 1 and 4 are done.
4. **Model shading.** Auto-smooth in the Blender scripts, regenerate the .glbs, check rock
   pieces still fit and crack seams still read.
5. **Leaf-card trees.** New canopies for round, birch, oak, pine and background trees,
   leaf texture, wind sway, shadows, and leaf-drop particles that match.
6. **Dense grass.** Grass ring system, wind uniform shared with the trees, bending round the
   player, density by preset, works on Terrain3D in both worlds.
7. **Atmosphere.** Volumetric fog per biome and time, god rays, per-biome LUTs (generated),
   darker nights, firelight flicker plus shadows, bloom tuning.
8. **Water and sky.** Rebuild `water_lowpoly.gdshader` and `sky.gdshader` as above.
9. **Wrap-up.** *After* screenshots, README images and text, FPS table per preset.

## Risks

- Leaf cards and dense grass use alpha cutout: watch overdraw and shadow cost; presets must
  cut them.
- Smoothing normals on fitted rock pieces may show seams. Keep seams hard.
- Terrain3D's `terrain_assets.tres` bloats on editor re-save: discard it.
- Headless runs touch the real save: back up `user://save.json` around `godot -s` runs.
