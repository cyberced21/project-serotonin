# Lamps: path lamps and the lantern you carry

Chunk 4 of [cozy.md](cozy.md) (its section 3). Grilled 2026-10-28. Branch `lamps` off `main`.

Status: **all 6 phases built** 2026-10-28 on branch `lamps` (headless tests: `tools/test_lamps.gd`,
`test_lantern.gd`, `test_gift.gd`; night shots in `docs/images/graphics/lamps/`, the darker night
approved from them; sounds picked on https://claude.ai/artifact/MY4wztTjzKM4pV9VYznzHH,
`audio/lamps/SOURCES.md`). **Not played, and the sounds' levels not heard in game.**

### Built, and what changed on the way

- Generated worlds have no roads, only trails from the hub, so their trails are the stretches
  (L2's "trails stay dark" holds for Hearthvale's forest trail and field tracks).
- A new world lights the path from the clearing to the village (not only the lanes): otherwise
  a new game had no path lamps at all.
- The wave spreads by straight distance from the village, not along the road: it looks the same.
- The lantern lights itself on the same darkness as the lamps (`DayNight.darkness()`), not at
  full night. The gift starts about a minute before sunset (`Lamps.GIFT_BEFORE_SUNSET`); with
  no player home yet, "your doorstep" is the town hall step.
- Night: moon 0.36 -> 0.26, night ambient 0.45 -> 0.3, night sky 0.6 -> 0.5 (`sky_look.gd`).

## Where we start (2026-10-28)

- Building lamps, lanterns and windows glow after dark: `DayNightSky.make_glow()` tags meshes
  `night_glow` and hangs an `OmniLight3D` (range 9 m, group `night_light`) on lamps. They all fade
  in together on one `smoothstep` of `DayNight` night, then flicker out of step.
- Props named like lamps glow too (`prop.gd`); the village square has 3 `lamp_post` props (procgen
  `VILLAGE_PROPS`, and the hand-built square).
- Roads: Hearthvale's ring road (`WorldMap.ring()`), its 3 `SPURS` (lake, village, field) and
  `RoadCourse.frame_at()` to place things along the ring. Generated worlds lay their own roads and
  trails (`procgen_map.gd`).
- Lamp shadows follow the `light_shadows` graphics setting (on only on High).
- The player is first person: the held tool sits low on the right (`viewmodel.gd`).
- Free keys: L, F. Villagers walk straight lines between their spots and can cheer; no dialogue.

## Decisions

| # | Question | Decision |
|---|----------|----------|
| L1 | How lamps arrive before the projects system | **Stretches.** Roads are cut into named stretches between junctions (village lanes, lake road, mine road...). A saved list says which are lit; a new world starts with the village and its lanes only. Debug toggles light the rest. Chunk 5 lets you pay to light a stretch. |
| L2 | Which paths | **Roads, both worlds**: the ring road, spurs and village lanes in Hearthvale, and the matching roads in generated worlds. Narrow dirt trails stay dark (the lantern's ground). |
| L3 | Spacing | **~20 m**: warm pools with dusk between. |
| L4 | Lighting up | **A wave out from the village**: at dusk lamps catch one after another, spreading outward along each road, each with a small flicker-on. A lamplighter waits for villager routines (chunk 8) and can take over the wave then. |
| L5 | Look | **Two posts**: the square's `lamp_post` on village roads, a rougher wooden post with a hanging lantern on the far roads. |
| L6 | Where the lantern sits | **Belt, raised by a key**: hangs at the left hip (its top and glow show bottom-left), sways with steps; **hold F** to raise it in front of you; swinging a tool lowers it. |
| L7 | Getting it, using it | **A gift at the first dusk.** Lights itself when it's dark; **L** turns it on/off. No fuel. |
| L8 | The gift moment | **The elder walks over**, holds it out, cheers; popup "The elder gave you a lantern. L to light it." If you're far from the village it waits on your doorstep. Existing saves get it at their next dusk. |
| L9 | Shadows | **The lantern always casts soft shadows** (the one moving light); path lamps follow the `light_shadows` setting. |
| L10 | Night darkness | **A touch darker**, tuned in the debug Sky tab so lamp pools and the lantern read as warm islands while open ground still shows by moonlight. Approved by the user from screenshots. |
| L11 | Sounds (CC0, picked by ear) | Lantern handle creak while walking, lantern on/off (flint or shutter), a soft whoomp as a nearby lamp catches, a faint flame crackle right beside a lamp. |

## Phases

One commit each; phases marked **(pick)** stop for your choice.

1. **Lamp stretches.** Road stretches in both worlds (Hearthvale from the ring and spurs, generated
   worlds from their roads), posts every ~20 m on alternate sides, clear of junctions, bridges
   and buildings; the two post models (L5; the far-road post made in Blender); the lit list saved
   in the world save, village lit by default; debug menu toggles per stretch. Unlit stretches
   have no posts at all (they appear when lit, so paying in chunk 5 visibly adds them).
2. **The dusk wave.** Each path lamp gets its light-up time from its distance along the road from
   the village; a short flicker-on, then the usual flicker. Building lamps and windows keep their
   fade.
3. **The lantern.** Model, belt pose in the viewmodel with step sway and a little swing lag, the
   raised pose on F, lowered while swinging; a shadowed warm light; L toggles, auto-on after dusk;
   saved (have it / on or off).
4. **The gift.** The elder's walk over at the first dusk, the cheer, the popup; the doorstep
   fallback; old saves get it at their next dusk.
5. **Night tune (pick).** Night ambient a touch lower, screenshots of the lit village, a lamp-lit
   road, a dark trail by lantern; you approve or adjust.
6. **Sounds (pick).** A listening page of CC0 candidates for L11; download your picks (asked
   first), loudness-match, wire them in (creak paced by steps, whoomp only near you, crackle as a
   quiet emitter on each lit lamp).

## Not in this chunk

Paying to light a stretch (chunk 5), the lamplighter and windows going dark one by one (chunk 8),
the dog carrying the lantern (chunk 6), the lantern in the mine (chunk 10).
