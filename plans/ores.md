# Ore polish: rocks that break where they're struck

Status: **done** 2026-10-19, all phases committed on branch `ores` (off `graphics`), unpushed.
Copper was playtested between phases 1 and 2; that playtest added the fault (a sweet spot) and
found the white-blob bug. Open items are in docs/TODO.md ("Ore polish").

## Why

The ore rocks looked rough next to the graphics overhaul, and the seam crack fought the pieces
flaking off: a crack decal was painted on, then a different-looking piece flew away. A first
fix (pieces loosening along their seam, 365f2b9) worked but was dropped for a bigger idea:
break the rock where it's hit.

## Decisions

| Area | Decision |
|---|---|
| Mechanic | Rocks are ~30–50 Voronoi pieces, small near the surface, big inside. Each hit knocks out the struck piece and 1–3 neighbours near the hit. No cracks, no tips. |
| Collapse | A piece with no chain of intact pieces down to the ground falls ("Collapse!", bonus XP, shake). Undercutting is the skill shot that replaces crack tips. |
| Shatter | At ~35% of the pieces gone (tunable per ore) the rest bursts apart. About 6 swings for copper; harder ores take more. |
| Ore payout | Pieces carrying ore faces spill one ore pickup as they come out, up to `drop_count - 1`; the shatter pays the rest (at least 1). Totals unchanged, Edda's +1 included. |
| Break styles | Copper flaky (many small pieces). Iron basalt columns (knock out a base, the column topples). Coal strata (flat plates, undercut drops a layer). Gold geode (tough shell of few pieces, crystal-lined hollow with the gold; two candidates rendered to pick from). Crystal keeps snapping off, each crystal breaking into shards from the hit. |
| Art | **Weathered outside, fresh inside.** Outside: denser rounder shapes, baked per-vertex shading (darker/mossier base, lighter top, worn convex edges, AO in crevices), moss and lichen in the grass greens blended with noise. Inside: bright crisp stone with its own detail slice; ore glints (lower roughness, metallic sheen on copper/gold, faint glow on crystal). |
| Grounding | Dirt and pebble skirt merged into the terrain, rocks sunk a few cm, rubble that stays when mined out. |
| Vertex colour | Rocks start using it: baked shading in RGB, the cut-face mark (`cut_mark`) moves to alpha. |
| Performance | One merged mesh per rock (piece id per vertex, a shader mask hides broken pieces): one draw call however many pieces. Only flying pieces get their own mesh. Watch spawn/load time (procgen is 4–7 s per seed now). |
| Saving | Exactly which pieces are gone, so a half-mined rock reloads with the same hole. |
| Neighbours | `make_models.py` `shattered()` writes `<model>.pieces.json` (piece -> touching pieces); may need an export include filter. |
| Variants | Every ore's procgen variants rebuilt the same way. |
| Scope | Ore rocks, scenery rocks (boulders, shore stones, quarry rubble), ore pickups and icons (pieces of the fresh inside), and building stone (village walls, ruins, quarry stonework in `make_village.py`, keeping their brick shapes). |
| Verification | `tools/ore_closeup.gd` strikes a rock and screenshots every hit (`--ore`, `--angle`, `--distance`, `--label`); graphics tour before/after. Windowed runs on `--screen 1`; the real save is backed up around runs. |

## Phases

One commit per phase. Phases 2 onward run straight through after the copper playtest.

1. ✅ **Copper, the reference rock.** Merged mesh with the piece mask; exact saves; ore spilling
   from vein pieces; weathered/fresh shading with glinting ore (shader + baked vertex colour);
   grounding skirt; rebuilt variants. **Stop for the user's playtest:** tune pieces per hit,
   shatter point, collapse feel, sounds.
2. ✅ **Iron columns.**
3. ✅ **Coal plates.**
4. ✅ **Gold geode** (render two candidates, the user picks).
5. ✅ **Crystal shards.**
6. ✅ **Ore pickups and icons** from each ore's fresh inside.
7. ✅ **Scenery rocks:** boulders, shore stones, quarry rubble.
8. ✅ **Building stone:** village walls, ruins, quarry stonework.
9. ✅ **Wrap-up:** README, docs/TODO.md, graphics tour before/after, load-time check, retire the
   seam-crack code if nothing uses it.
