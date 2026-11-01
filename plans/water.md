# Water: waves, depth, swimming

Branch `water` (off `main`), worktree `../project-serotonin-water`, one commit per phase.

**Goal.** Water that looks like water: gentle rolling waves, a bed that fades from clear to deep
blue-green, light dancing on the shallows, the view bending through the surface, foam that laps
and wakes behind you. And water deep enough to matter: Stillwater (the lake) becomes a real lake
you swim across and dive into, where you can spear fish on the bed.

## How it works today

- One water level everywhere: -0.15 m (`LayoutWater.LEVEL`, `Creek.WATER_LEVEL`, the generator's
  `WATER_LEVEL`). A pond is a bowl dug under it (`_pond` in `tools/generate_test_terrain.gd`).
- The lake is a layout `pond` (`data/layout/hearthvale.json`, id `lake`): circle at (38, 340),
  radius 14, depth 1.35 — wadeable everywhere. Its basin (`LAKE_BASIN`) is a 26 m flat. The clearing
  pond is 0.95 m, the creek 0.55 m (1.2 m in the salmon pools).
- `WaterBody` (Area3D + box): `depth_here` / `depth_at` / `surface_at`, mist, lapping sound.
  The player only slows with depth (`wade_slow`, `wade_full_depth`); deep water would just be
  walked along the bottom.
- `shaders/water.gdshader`: a tiny sine swell (2.5 cm) on the vertices, six sine ripples bending the
  normal, depth-buffer thickness → shallow/deep colour and alpha, a noisy foam band at the shore,
  Fresnel sky. No refraction (on purpose, so fish are where they look for the spear), `cull_back`
  (invisible from below).
- Shared wind already exists as global shader uniforms (`wind_direction`, `wind_strength`, grass).

## Decisions

- **The lake**: radius ~22 m (basin widened to match), about **5 m deep** in the middle, with a
  wadeable **shelf** (≤ 1 m) a few metres wide round the shore, then a slope down. The clearing
  pond's middle goes to **~2.5 m** (a swimmable spot), the creek's salmon pools to **~2 m** (a dip).
  Reeds, lilies, stones and fish follow the new shapes; deep fish (char) live low in the lake.
- **Swimming: surface + diving.** In water deeper than chest height you float, eyes just above the
  waves, and paddle along your look direction. **Ctrl / C dives**, **Space rises**; underwater you
  swim where you look. A gentle **breath meter** (~25 s, a small bubble ring by the crosshair, only
  while under): when it runs out you just float back up and can't dive again until it refills. No
  drowning — it's cozy. Ground under your feet (the shelf, the shore) = walking again; the existing
  mantle gets you out over a bank.
- **Tools while swimming**: put away at the surface. **Underwater, the spear comes out**: thrust at
  fish you swim up to. Fish notice a swimmer (they drift off if you rush them), so it's a slow,
  quiet hunt — a new way to fish the deep lake the spear can't reach from the shore. Same catches
  and XP as spearfishing, tuned so it doesn't beat the rod (checked with `tools/fishing_bench.gd`).
- **Waves: gentle lake chop.** A few **Gerstner waves** (rolling waves with sharper crests) of
  ~10–15 cm on the lake, following the shared wind; calmer on ponds; streaks running with the
  current on the creek. The same wave sum is written once in GDScript (`WaterWaves`) and in the
  shader, on a shared clock (global shader uniform `water_time`), so the swimmer and a float bob
  exactly with the surface you see. Surfaces get subdivided enough to show them (~0.5–1 m quads).
- **Depth & detail** (all four):
  - **Depth colour**: light absorbed per colour by depth (red first, then green: the bed goes
    clear → green-teal → deep blue), plus a little murk scattering.
  - **Caustics**: dancing light on beds under shallow water (terrain shader, and the rock/stone
    shaders), only where the sun reaches, fading with depth.
  - **Refraction**: the view through the surface bends with the waves, kept **subtle** (a few cm
    offset, not over foreground objects), so a fish within spear reach is still about where it
    looks; the spear's hit gets a small tolerance if needed.
  - **Foam + wakes**: shore foam that laps in and out with the waves; ripples and a V wake behind
    you wading or swimming; a splash ring when you dive in or climb out.
- **Underwater**: the camera under the surface sees a tinted, distance-faded world (the same
  absorption colours), the surface from below (bright sky window overhead, mirror-teal at an angle),
  sun shafts (a volumetric FogVolume per deep water, only while you're under), and everything
  sounds muffled (a low-pass on the world's sound buses).
- **Sounds**: CC0 packs, candidates on a page, you pick by ear before they're wired (strokes,
  dive in, underwater loop, surfacing breath, climbing out).
- **The dog** waits at the water's edge while you swim (sits, watches you), and runs to meet you
  when you come out.

## Phases

1. **Deep lake + floating.** ✅ Lake radius 22 / depth 5 with a shelf (generator `_bed`: water
   deeper than 0.9 m keeps a 0.9 m shelf up to 5 m wide, then drops; basin 34 m); clearing pond
   2.5 m; salmon pools 2 m as soft-rimmed round bowls (deepening the narrow channel left ledges).
   Player: `swimming` once your feet are 1.35 m under (by the surface, not the bed's height, which
   is coarse on the drop) — floats eye 0.14 m up, paddles 2.2 / 3.2 m/s, tools put away, walks out
   up the shelf, jump at a bank to mantle. Dog: goes round deep water to you on the far side;
   strays nap on dry bank. New `test_swim`; all 40 tests pass. Stills not taken (needs a window).
2. **Diving + underwater.** ✅ Hold crouch to dive; under (eye 0.35 m down) you swim where you
   look, Space rises, left alone you drift up (0.8 m/s); the water brakes a jump in (12 m/s²).
   Breath 25 s under, back in 4 s; out of it you float up and can't dive till it's full
   (`BreathRing` round the crosshair). `UnderwaterView` (camera child): two full-screen passes,
   multiply by per-colour absorption then add murk, by the water between the eye and the pixel
   (the depth buffer, or the surface plane for rays going up); `under_light` global dims it at
   night. The water shader's back face: Snell's window onto the sky, dark mirror outside it. A
   low-pass on Effects / Ambience / Movement / Music (half). `test_swim` covers it all headless;
   the shaders are not yet seen rendered.
   Sound candidates (34 CC0 Freesound takes, 5 slots: strokes, diving in, under the water, coming
   up for air, climbing out) on https://claude.ai/artifact/7BV7SbNtD5tVcoeuzE6bKL; previews kept in
   E:/Godot/downloads/water-sounds. **Picked** (wire in phase 7): strokes 372518 "lake swimming"
   (dawidwmika); diving in 529793 "dive.wav" (bruno.auzet); under the water 482167 "Underwater
   Ambience" (Tim_Verberne); coming up for air 169931 "Gasp Inhale" (u3190); climbing out 637948
   "water movement body step out of pool splash drips" (kyles).
   Stills (`tools/water_shots.gd`, docs/images/water/): first take far too dark and the mirror
   let the hills show through; murk brightened, absorption eased, mirror opaque, night floor 0.16.
   Phase 4 todo seen there: the lake bed is grass/sand blotches (wants a silt/sand bed).
3. **Waves.** ✅ `Waves` autoload (scripts/autoload/waves.gd): four Gerstner waves off the shared
   wind (7 / 4.3 / 2.9 / 1.9 m, 5 cm down to 1 cm, steepness 0.5, 0.7× deep-water pace), and the
   `water_time` global it sets; the shader's `gerstner()` is the same sum (displaces the vertices,
   per-pixel normal). Per body `WaterBody.wave_scale` (auto: 1 for water ≥ 36 m wide, else 0.3;
   creek 0.06, quarry puddles 0) sent as the instance uniform `waves`; `WaterBody.surface_y(pos)`.
   The swimmer floats on surface_y (the spring also matches the wave's rise and fall, so you ride
   it, not trail it), the float and the line ride it, the lily pads ride it, the underwater view
   switches by it. The creek's strip carries its downstream direction in the vertex colour:
   ripples drift with the current (`flow_speed`), faint slick streaks run along it. `test_swim`
   checks the lake's waves (~0.13 m) and that your eye stays within 5 cm of its float height.
   Stills: lake_waves, creek (docs/images/water/); the riding lily pads not yet seen rendered.
4. **Depth look.** Per-colour absorption, subtle depth-safe refraction, caustics on beds and rocks,
   underwater sun shafts. Before/after stills (lake from the shore, the shelf, the clearing pond,
   underwater).
5. **Foam + wakes.** Lapping shore foam; wakes, rings and splashes for wading, swimming, diving
   (building on `water_ripple`).
6. **Spear while diving.** Underwater thrust, fish spooking from a swimmer, species and depths,
   XP; bench it against the rod and tune.
7. **Sounds + dog.** Wire your picked sounds; the dog waits at the edge and greets you.
8. **Polish + checks.** Save/load mid-swim, the map editor's lake depth/shelf, `tools/audit_world.gd`,
   all tests (`python tools/run_tests.py`), a stills page, TODO.md updated.

## Open (decide in play)

- Wave height, swim speed, breath length, refraction strength: by eye once you've swum it.
- Whether the creek's stretches deserve their own swim spots later (pools stay a dip for now).
