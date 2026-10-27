# Fishing parity: spear and rod as two styles, neither stronger

Branch `fishing-yank` (it builds on the yank rework), one commit per phase.

The pitch: **how you fish is a style, not a power choice.** The spear is active and bursty (wade
in, read the school, take two or three at once, scatter them on a miss); the rod is patient and
far-reaching (fish from the bank, one at a time, bigger rewards per fish). At the same tier and
level, a skilled player earns about the same XP and fish per hour either way. Both get tiers like
the axe and pickaxe, and the level talents (plans/levels.md, *Angler* vs *Spearman*) are where you
specialize.

## Decisions (2026-10-27)

| # | Topic | Decision |
|---|-------|----------|
| P1 | Choosing | **You pick the tool**: Q swaps spear ↔ rod (Q was the old fight's bow, now free), and the choice is remembered (saved). The spear takes water within its reach, the rod anything from 2 m out to its cast range, so the middle distance works with either. Aiming at water the held tool can't take shows a hint ("Q: rod"). |
| P2 | Every fish both ways | Every species can be caught with either tool somewhere, sometime. **Char** and **salmon** come up out of deep water into the nearest shallows to feed at dawn and dusk (`FishSpecies.dusk_depth`). The rod reaches them any time from the bank; the spear needs the right time and place. No village cost only one tool can pay. |
| P3 | Equal means | **XP per hour and fish per hour** for a skilled player at the same tier and level, per species, within ±15%. Measured by a bot bench (phase 7), tuned by the numbers, not by feel alone. |
| P4 | Identities | Spear: fast, multi-catch on schools, a miss scatters them. Rod: slow, one fish per bite, quiet, bigger payout per fish (Perfect!). Tuned so they even out over an hour (P3). |
| P5 | Size in the water | **Each fish has its size from the moment it spawns**: big ones are visibly bigger in the school (model scale ~0.8x–1.35x), so you can pick your target. The size gives the weight popup ("Trout, 1.4 kg") and +0–50% XP **for both tools**. |
| P6 | Big fish count extra | On pickup, a fish past a size threshold is worth more than one: **Big** (~12%) counts **2**, **Huge** (top ~4%) counts **3**, with a popup. Both tools. |
| P7 | Tiers gate species | **Like the axe and pickaxe**: four spears and four rods, each opening the same fish at the same tier (so neither tool gets a species first). The Fishing level stops gating (soft difficulty only, like mining since tools landed). Each tier also gets a little stronger. |
| P8 | Under-levelled | One rule for both tools: below a species' rating, each tool's success drops by about the same amount for the same gap (spear: dodge chance; rod: window). Bench-checked (P3). |
| P9 | Village perks | Every fisher's hut perk helps both tools. *Bonus fish* (today spear-only) counts for the rod too; *Sharper eyes* (today rod-only) also widens the spear's skewer. |
| P10 | Talents | The levels plan's *Angler* vs *Spearman* track is where you specialize (it stays one rod perk and one spear perk per milestone). Its rod perks that assumed the old fight are rewritten (below). Built later, with the levels work. |

### The ladder (P7)

Each tool is made from what the tier below could gather (as tool-progression.md T3), so no tool
needs the fish it opens. Greta forges both (the Forge tab), capped by the smithy's tier.

| Tier | Spear | Rod | Opens | Made from (both, plus each one's wood) |
|---|---|---|---|---|
| 0 | Sharpened stick (given) | Willow pole (given) | perch | — |
| 1 | Copper spear | Copper-reel rod | trout, grayling | copper + perch (spear: logs; rod: birch) |
| 2 | Iron spear | Iron-reel rod | pike, char | iron + coal + trout (spear: oak; rod: birch) |
| 3 | Crystal spear | Crystal rod | salmon, and the most power | crystal + gold + pike (spear: oak; rod: pine) |

Quantities to tune. To check: the fisher's tier 3 (trout, pike, char) needs iron fishing tools,
so it comes after the smithy's tier 3: confirm that order matches the other buildings.

**Too weak a tool**: the spear glances off with a clank and the fish bolts ("Needs iron spear");
on the rod, such fish notice the float a third as often, and when one does take, the hook tears out on the yank ("Needs Iron-reel rod"), so you learn why.

**Power per tier** (the tools' raw strength; technique stays with levels): spear +reach and
+skewer length; rod +cast range and +strike window. Sized so the two climb together (P3).

## Phases

1. **Choosing the tool** — Q swaps spear ↔ rod (saved), overlapping ranges, the hint, the
   controls bar.
2. **Size in the water** — per-fish size at spawn, model scale, weight, Big ×2 / Huge ×3 on
   pickup and size XP for both tools, popups.
3. **Tool tiers** — spear and rod in `Tools.LADDER` / `RECIPES`, species rated by tier, the
   glance-off and torn-hook feedback, the Forge tab, level gating turned soft.
4. **Models** — four spears and four rods (Blender script), icons, the viewmodel per tier.
5. **Every fish both ways** — char and salmon up in the shallows at dawn and dusk;
   village costs checked.
6. **Power and perks** — per-tier power, the shared under-level rule, the hut's perks for both.
7. **The bench** — a headless bot that fishes each species with each tool and prints XP/hour and
   fish/hour; tune until they're within ±15%.
8. **Docs** — README, TODO, fishing.md, levels.md's rod talents rewritten for the yank.

### levels.md rod talents to rewrite (P10)

The old fight's perks no longer fit: *Quick hands* (strike, bow and jerk windows) becomes the
strike window only; *Strong line* (runs give back less) and *Play the fish* (Lv 40: turn a run)
need replacing, e.g. *Strong line*: a late pull still lands the fish one time in three;
*Play the fish*: a big fish on the rod rolls one size class up.
