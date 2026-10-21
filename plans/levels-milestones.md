# Levels: fixed milestone techniques (B + D)

Builds on [tool-progression.md](tool-progression.md): tools decide *whether* you can gather,
levels decide *how well*. The alternative design is [levels-talents.md](levels-talents.md).

Status: **superseded** by [levels.md](levels.md) (2026-10-20); kept for the reasoning.

## The problem it solves

Today a level is only a key: `ResourceNode.can_gather()` checks `level >= required_level`, and
nothing else in woodcutting or mining reads the level. Woodcutting 2 → 14 changes nothing. With
the level gate gone (tool-progression T4), a level has to be *worth something* on its own.

The curve is steep (XP for level L = 50 · (L−1)^2.2, max 50), so late levels are rare: each one
has to land as an event.

## The idea

Three layers, each felt on a different timescale:

1. **Every level: proficiency.** A small, *feel* bump, not a percentage of output (the village
   owns percentages: `TierEffect` has double hits, hit power, extra drops, regrow, XP). Each level
   widens the skill's **technique windows** a little and trims swing recovery:
   - Woodcutting: the clean-cut aim tolerance into the notch's mouth (`ResourceNode` clean cut).
   - Mining: how close to a crack tip counts as on it.
   - Fishing: the strike, bow and jerk windows (already level-scaled via `FishFight.level_scales`).
   - Farming: the sickle's sweep width.
   Felt over a session, not per level: "I'm landing more clean cuts than I used to."
2. **Every 10 levels: a technique (D).** A new verb or a new read of the world, fixed per skill.
   This is the big level-up: fanfare, a card naming it, and something you can try right away.
3. **Every 5 between (15, 25, 35, 45): a flourish.** Cosmetic or sensory: a tool trail, an extra
   sound layer on clean hits, a title, a tool engraving. Cheap to make, keeps the gaps short.

### Technique candidates (to grill one by one)

| Level | Woodcutting | Mining | Fishing | Farming |
|---|---|---|---|---|
| 10 | **Chain cut**: back-to-back clean cuts bite deeper each time | **Feel the grain**: crack tips glint for a moment after each hit | **Read the water**: hooked fish's shadow shows earlier and clearer | **Wide sweep**: one swing takes neighbouring sheaves |
| 20 | **Steer the fall**: the notch's side picks the fall direction; a falling trunk damages trees it lands on (chain felling) | **Fault sight**: fault lines show faintly before you hit | **Feel the take**: a faint rod tremble one beat before the take | **Gleaning**: a perfect-timed swing drops seed/extra |
| 30 | **Heartwood**: sometimes a glowing knot appears; hit it for a big chunk and a rare log | **Split shot**: a crack-tip hit can split the rock clean in two | **Second strike**: a slightly late strike can be saved with a quick re-strike | (tbd) |
| 40 | **Power swing**: hold to charge a heavy chop (slow, huge on a clean cut) | **Vein sense**: ore nearby hums when you're close (prospecting) | **Power cast**: hold the back-cast longer for distance | (tbd) |
| 50 | **Master**: max tolerances, master's engraving on every axe, a title | same | same | same |

Rules for a good technique: it changes **what you do or notice**, it's usable in the first minute
after you get it, and it builds on mechanics that already exist (the notch, cracks/faults, the
fight's telegraphs) rather than adding systems.

### The level-up moment

Today: popup text + HUD bar (`hud.gd` `_on_leveled_up`). Proposed:
- Every level: a short sting, the tool glints, a one-line popup ("Woodcutting 13 — cleaner cuts").
- Milestone: hit-stop, a bigger sting, a card "**Chain cut** — back-to-back clean cuts bite deeper",
  and the next clean cut is highlighted so you notice it working.
- The skills panel lists every milestone: earned, and the next one with its level (a goal to aim at).

## Open questions

1. Milestones every 10 + flourishes every 5 (20 techniques, 16 flourishes), or a technique every 5
   (40)? Recommendation: every 10.
2. Farming has only two crops: does it get the full ladder, or two or three techniques?
3. Fishing techniques: spear and rod both, or the rod only? Recommendation: split them (10 and 30
   rod, 20 and 40 spear) so both tools grow.
4. Proficiency sizing: e.g. +1% window per level → +49% at 50. Tune so 1 → 50 is clearly felt.

## Phases (draft, after tool-progression)

1. **Proficiency** — a per-skill `proficiency(level)` the technique windows read; tune.
2. **Level-up moment** — stings, glint, popups, the milestone card, the skills panel list.
3. **Techniques, one skill per phase** — woodcutting, mining, fishing, farming.
4. **Flourishes** — trails, engravings, titles, extra sound layers.
5. **README, TODO, playtest** (by hand: every technique tried right after unlocking).
