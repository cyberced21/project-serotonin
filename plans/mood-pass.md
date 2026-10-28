# Mood pass: softer light, sunrise ≠ sunset

Chunk 1 of [cozy.md](cozy.md). Grilled 2026-10-27. Branch `mood` off `main` when started.

Status: **decided, not built.**

## Where we start (2026-10-27)

- `scripts/day_night_sky.gd` has **one** dusk palette (`DUSK_TOP`, `DUSK_HORIZON`, `DUSK_GRADE`) for
  both ends of the day. `DayNight.TWILIGHT` is 0.05: the colour shows for about a minute of real time
  each way (`DAY_LENGTH` 1200 s; day 06:00–20:00).
- Glare comes from ACES tone mapping at exposure 1.1 (`materials/world_environment.tres`), glow
  (bloom) on anything brighter than 0.9, sun energy 1.0 at noon, and the sky shader's own warm halo
  round the sun (`shaders/sky.gdshader`).
- Fog: distance fog 0.008 (about half gone at 100 m), volumetric mist 0.006, ×3.2 at the morning peak,
  ×1.6 at night; biomes multiply on top (pinewood fog 1.8 / mist 2.2, stillwater 1.6 / 1.8, quarry
  1.3 / 1.6).

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| M1 | Golden hour length | **About 3 minutes each** of real time with colour (roughly triple today). |
| M2 | Where the time comes from | **Mostly from night**. The working day stays about 14 minutes; night gets shorter. |
| M3 | Sunrise | **Golden and fresh**: butter-yellow to orange horizon, clean cool pale-blue top, golden light. |
| M4 | Sunset | **Clearly pink**: rose/coral horizon, lilac-purple top, pink-tinted light and grade on the world. Clouds follow (golden at dawn, pink/magenta at dusk). |
| M5 | Facing the sun | **Soft disc, small halo**: dimmer disc, tighter halo, no bloom flare at noon; the wide warm glow only when it's low. |
| M6 | Noon | **Soft and warm**: a bit dimmer sun, lighter shadows (less contrast), faint warm tint, bloom only on truly bright things (lamps, glints). |
| M7 | View range | **Across the valley**: crisp to ~150–200 m, a soft haze beyond (aerial perspective: far things fade toward the sky colour). |
| M8 | Morning mist | **Low ground only**: thin wisps on ponds and hollows at dawn, burnt off by mid-morning. Air above eye level stays clear; light shafts subtle. |
| M9 | Biomes | **Colour, not thickness**: extra fog/mist capped at about ×1.2; identity from tint (green-gold dappled forest, cool silvery lake air). |
| M10 | Night | **Moonlit and readable**: soft blue moonlight, paths and silhouettes visible without a lantern; lamps are warm pools that pull you in, not a requirement. Night mist no thicker than day. |
| M11 | Tuning | **A Sky tab in the debug menu**: scrub the time of day, tweak palettes, sun and fog live, copy values out. I set first values, you tune by eye. |
| M12 | Checking | **Windowed screenshot runs allowed for this work** (muted, screen 2): dawn / noon / dusk / night in the clearing, forest, lake and village, before and after. |

Applies everywhere the sky does: main world, procgen worlds, the menu backdrop. The quarry's depth
fog stays until the mine replaces it (cozy chunk 10), but goes under the same ×1.2 cap.

## Phases

One commit each.

1. **Sky tab in the debug menu.** Time-of-day scrub (and pause), and live controls for: both twilight
   palettes (top, horizon, grade), sun energy at noon/low, exposure, glow threshold/intensity, sun disc
   and halo size, distance fog, mist, the biome cap. A "copy values" button that prints them as GDScript
   constants. Do this first so every later phase is tuned with it.
2. **Sunrise and sunset split.** Separate `SUNRISE_*` and `SUNSET_*` palettes and grades, chosen by
   which side of noon it is; clouds tinted by them. Longer `TWILIGHT` with sunrise/sunset moved so the
   extra time comes out of night (`DayNight`; check `clock_text()`, `is_night`-style checks, the map
   and anything else timed on SUNRISE/SUNSET).
3. **Sun and noon.** Lower exposure and noon sun energy, raise the glow threshold, lift ambient /
   shadow a little, faint warm noon grade; smaller, dimmer disc and tighter halo in `sky.gdshader`
   (the wide glow scaled by how low the sun is).
4. **Fog.** Thinner distance fog with aerial-perspective haze past ~150 m; morning mist moved to low
   ground (height falloff or `FogVolume`s over ponds and hollows), no extra night mist; biome fog/mist
   capped at ×1.2 and their tints reworked to carry the identity (`data/biomes/*.tres`).
5. **Night.** Moonlight brightness and colour, night ambient, so it reads without a lantern.
6. **Screenshots and a first tuning pass**, then hand over for tuning by eye with the Sky tab.

## Not in this chunk

Weather, seasons, fireflies, night sounds (chunk 3), path lamps and the lantern (chunk 4).
