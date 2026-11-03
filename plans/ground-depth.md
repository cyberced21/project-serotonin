# Ground depth: vibrant, layered terrain surfaces

The user: "The grass, the dirt, the snow, they all look fairly flat. I want them to be a lot more
vibrant, and have a lot more depth."

## Decisions (grilled 2026-11-03)

| Question | Answer |
|---|---|
| Style | Keep the chunky, nearest-filtered texels (Valheim). Depth comes from light and colour layered on top. |
| Vibrance | Richer but natural: deeper greens, warm sunlit tips, cool blue-green shade, richer browns. Not neon. |
| Depth | Per-texel normal map (the sun lights pebble tops, shades their sides) plus crevice shade (ambient occlusion). No parallax. |
| Slopes and peaks | Layered breakup: grass thins into dirt through ragged patches, rock pokes through steeper ground with strata, snow lies in drifts on ledges with rock on steep faces, blue in shade. |
| Frame cost | Detail fades with distance; aim for under ~0.5 ms extra. |
| Look | Picked from in-game candidates on an artifact page. |

Packed earth stays clearly paler than dirt paths (the roads-everywhere branch sets
`packed_color` to (0.76, 0.65, 0.47); this branch uses the same value). Every control-map id stays
recognisable.

## How

`tools/make_textures.py` makes the ground slices richer:
- `ground.png` becomes RGBA: R tone (as before), G height (what pokes up: pebbles, clods, tufts,
  setts), B crevice shade (dark in the gaps between them), A a second-material mask (pebbles in
  dirt, clover/tips in grass, moss in rock, mud in cobble joints).
- `ground_normal.png`: a per-texel normal map from the height, one flat facet per texel so it stays
  chunky (global `ground_normal`).

`shaders/terrain.gdshader`:
- Height blending uses the real height channel, so pebbles and tufts win at borders.
- Each surface gets two colours (base and second material by the mask) and a stronger warm/cool
  shift between lit and shaded texels.
- Normal detail and crevice shade, faded out with distance.
- A coarser second sample of the main surface's slice (several scales of detail), and big hue (not
  just brightness) patches: lush and dry grass, dark and pale dirt.
- Terrain-scale crevices: hollows in the heightmap shade darker, ridges lighter.
- Slopes: noise-driven breakup thresholds; rock strata bands; snow drifts on flatter ground, rock
  on steep faces, snow bluer in crevices.
- `scripts/grass_field.gd`'s default colours follow the new palette.

## Phases

1. Textures: RGBA ground + normal slices. Shader reads them (height blend, normals, crevices) with
   the old palette. Global uniform registered.
2. Candidate looks as uniform sets; in-game screenshots (tools/ground_shots.gd) on an artifact page;
   the user picks.
3. The picked look as the defaults: palette, slope/snow breakup, grass blade colours.
4. Frame cost check (near/far fade tuned), tests, screenshots of the result.
