# Levels: talent choices (C)

Builds on [tool-progression.md](tool-progression.md): tools decide *whether* you can gather,
levels decide *how well*. The alternative design is [levels-milestones.md](levels-milestones.md).

Status: **superseded** by [levels.md](levels.md) (2026-10-20); kept for the reasoning.

## The idea

Same per-level **proficiency** bump and level-up moment as the milestones plan (those don't depend
on the choice and would be built the same way). The difference is the milestones: at 10, 20, 30
and 40 you **pick one of two talents**; 50 is a capstone for the side you leaned into.

The choice is satisfying because it says *what kind of* woodcutter you are. To keep it a real
choice and not a trap, each skill has **two styles**, and every pair is one talent from each:

| Skill | Style A | Style B |
|---|---|---|
| Woodcutting | **Feller** — speed and big moments (chain felling, power swings) | **Forester** — care and rewards (heartwood, rare logs, clean-cut streaks) |
| Mining | **Breaker** — force (split shots, shattering) | **Prospector** — reading rock (fault sight, vein sense) |
| Fishing | **Angler** — the rod (feel the take, power cast, second strike) | **Spearman** — the spear (wider thrust, multi-catch, wading quietly) |
| Farming | **Harvester** — sweep and speed | **Grower** — gleaning and yield |

Fishing maps neatly onto its two tools. Example woodcutting tree:

| Level | Feller | Forester |
|---|---|---|
| 10 | Chain cut | Steady hand (clean-cut window much wider) |
| 20 | Steer the fall + chain felling | Heartwood |
| 30 | Power swing | Seasoned logs (a clean-cut streak drops a rare log) |
| 40 | Timber! (a felled tree's landing shakes loose a bonus) | Reading the grain (see the best notch height) |
| 50 capstone | depends on which side has 3+ picks | |

Mixing sides is allowed (pick per milestone, not per skill); the capstone rewards leaning.

## What it costs over B + D

- **Twice the talents**: 32 at 10–40 across four skills (vs 16), plus capstones.
- **Balance**: each pair has to be roughly equal, or the choice is fake. Paired by *style*, not
  power, it's easier: neither is "more damage".
- **UI**: a choice screen at the milestone (pause, two cards, pick) and a talents page.
- **Save**: picks per skill (small: 4 bits per skill), plus migration (existing high-level saves
  pick on load).
- **Respec** (undoing picks), needed so a pick isn't a forever mistake. Recommendation: Greta (or
  the town hall) resets a skill's picks for a fee in that trade's goods (logs for woodcutting,
  ore for mining), so a respec is a small task, not a menu click.

## Exploration: blending with B + D

The two aren't exclusive. A cheaper blend: **fixed techniques at 10 and 30** (everyone gets the
core verbs), **choices at 20 and 40** (where you specialise). That's 8 fixed + 16 choice talents,
with half the balance risk. Worth weighing once the woodcutting tree is designed and played.

## Open questions

1. Pick per milestone (mixing allowed) or commit to a style per skill? Recommendation: per milestone.
2. Respec cost and where: Greta / town hall, paid in goods?
3. Choose on the spot (pause at level-up) or later at a villager? Recommendation: on the spot,
   with "decide later" allowed (the milestone waits in the skills panel).
4. Full C, or the blend?

## Phases (draft, after tool-progression)

1. **Proficiency + level-up moment** (shared with levels-milestones.md).
2. **Talent framework** — `TalentDef` resources (`data/talents/`), picks in `Skills` + save, the
   choice card, the talents page, respec.
3. **One skill's tree end to end** (woodcutting) and play it by hand before the rest.
4. **Mining, fishing, farming trees.**
5. **Capstones, README, TODO.**
