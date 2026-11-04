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
- per-texel normals from the height, one flat facet per texel so it stays
  chunky (as built: packed into ground.png, see below).

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

## As built (2026-11-03)

- Look **A (richer, natural)** picked from in-game candidates (page:
  https://claude.ai/artifact/LEciGrTPCqNmGUfLkqt1p2). Before/after shots in docs/images/ground/
  (`before_*` / `game_*`), from `tools/ground_shots.gd`.
- In the end there is **one** texture, not two: `ground.png` RGBA = tone, height, normal X,
  normal Z. A separate normal texture (and per-corner crevice/mask channels) cost about 1 ms of GPU
  time, so the second-material mask now rides on the height (the top of its 8 levels; for cobbles
  the bottom, the joints) and the crevice shade is worked out from the height in the shader.
- Frame cost: measured against the old shader at five spots (1920×1080, GPU time), the new
  ground costs **-0.02 to +0.07 ms**. The extra work is paid for by sharing the 12 heightmap
  vertices round each pixel between the smooth normal and the surface blend (it used to fetch 20,
  each with its own region lookup) and looking the region up once per pixel.
- The hue patches and saturation skip snow, sand, rock and cobbles (snow went beige otherwise).
- Not done: snow bluer in shade beyond the general cool crevice tint; footsteps still use the plain
  `snow_height`, so near the wandering snow line the sound and the look can disagree by a few
  metres.

## Phases

1. Textures: RGBA ground + normal slices. Shader reads them (height blend, normals, crevices) with
   the old palette. Global uniform registered.
2. Candidate looks as uniform sets; in-game screenshots (tools/ground_shots.gd) on an artifact page;
   the user picks.
3. The picked look as the defaults: palette, slope/snow breakup, grass blade colours.
4. Frame cost check (near/far fade tuned), tests, screenshots of the result.
