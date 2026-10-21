# Tool progression (the shared foundation)

Gathering stops being gated by skill level and is gated by **tools** instead. Levels go fully
soft: they say *how well* you gather, never *whether* you can. What a level-up *gives* is [levels.md](levels.md)
(chosen 2026-10-20 after exploring [levels-milestones.md](levels-milestones.md) and
[levels-talents.md](levels-talents.md)).

Status: **designed** (grilled 2026-10-20, every open question decided; not started). No branch yet.

## Decisions (grilled 2026-10-20)

| # | Topic | Decision |
|---|-------|----------|
| T1 | Gate | Tools are a **hard gate**. Hitting a node above your tool's tier bounces off as under-levelled hits do today (clank, nudge, no damage, no XP), popup "Needs iron pickaxe". |
| T2 | Source | **Greta (the smithy) forges tools** from ingredients you bring. The smithy's tier caps the best tool she can make. Tools are not drops or finds. |
| T3 | Ladder | Each tool is made from what the tool before it could gather, so no tool needs the material it unlocks (see the table). The last tier opens nothing new: it's the power tier. |
| T4 | Levels | **No hard level gates anywhere.** The old `required_level` becomes a *difficulty rating*: below it you still gather, but worse (see "Under-levelled" below). Fishing already works this way (R8 in fishing.md). |

### The ladder

| Smithy tier | Pickaxe (made from) | Opens | Axe (made from) | Opens |
|---|---|---|---|---|
| Fire Pit (start) | Stone pick (given) | copper | Stone axe (given) | logs, birch |
| Stone Forge | Copper pick (copper + logs) | iron, coal | Copper axe (copper + birch) | oak |
| Smithy | Iron pick (iron + coal + oak) | gold, crystal | Iron axe (iron + coal) | pine |
| Crystal Forge | Crystal pick (crystal + gold + pine) | nothing new, the best tool | Crystal axe | nothing new, the best tool |

Quantities to tune. Checked against today's upgrade costs (`data/buildings/*.tres`): Stone Forge
costs logs + copper and the Smithy costs copper + iron + coal, both reachable with the tools of
the tier below. The Crystal Forge costs crystal, which is why the Iron pick opens crystal.
**Nothing in the village costs needs re-costing** for the pickaxe and axe ladders.

### Under-levelled (soft) — decided: a real penalty (T5)

Per level below a node's rating: fewer effective hits (e.g. -6% hit power per level, floor 40%)
and tighter technique windows (the clean-cut aim tolerance, crack-tip tolerance). At or above the
rating: the plain baseline, with level rewards on top. An under-level break gives **+25% XP**
(fishing gives +50% for an under-level catch), so reaching up is rewarded, not just allowed.

## Decided while grilling (formerly open questions)

1. ~~Fishing and farming tools~~: decided (T6, "for now"): **the rod and spear stay untiered**
   (fish gate softly by level, fishing.md R8/R11); **the sickle gets two steps**: stone sickle
   (given) cuts wheat, copper sickle (copper + logs, Stone Forge) cuts barley. Farming's talents
   wait for a farming pass and are built last.
2. ~~Tool durability~~: decided (T7), **no durability**: forged once, kept forever.
3. ~~Better tools on old nodes~~: decided (T8), **+1 hit power per tier above the node's**, plus a
   per-tier feel upgrade (heavier swing sound, its own sparks). Tools own raw power; levels own
   technique windows.
4. ~~Smithy perk overlap~~: decided (T9), **keep the smithy's perks**: the building sharpens
   whatever you carry. Tools give *flat* power, the smithy *chance* (double hits). The Crystal
   Forge's flat `hit_power` +0.5 becomes chance-flavoured instead: every 3rd hit of a streak
   counts double.
5. ~~Save migration~~: decided (T10), **a fresh start**: a save version bump; an older save is
   not loaded but **renamed aside** (e.g. `*.pre-tools.bak`), never deleted, and the game starts
   new. If `menus` (which hasn't migrated real saves yet) lands around the same time, do both in
   one version bump.
6. ~~Crafting UI~~: decided (T11), **a Forge tab in Greta's panel** (`upgrade_panel.gd`), beside
   Upgrade: the next pick, axe and sickle, each with its cost and what it opens; tools above her
   tier greyed out with "needs Smithy", so the whole ladder is visible.

### The forge moment (T12): epic

Forging is rare (about nine forges in a whole game), so each one is an event, a short cutscene
in first person, about 6–8 s. Sounds synthesized like the rest (`tools/synth_*.py`).

1. **The village holds its breath.** The panel closes; ambience and music duck; the light dims
   everywhere except the forge, which flares (embers swirl up, a heat shimmer). The camera eases
   to face the anvil.
2. **Three blows.** Greta lifts the glowing blank and hammers three times, each heavier: hit-stop,
   a shower of sparks, a ring that echoes off the buildings, camera shake growing with each.
   A low drone rises under them.
3. **The quench.** She plunges it into the trough: a huge hiss, a burst of steam that fills the
   view, everything white for a beat.
4. **The reveal.** The steam clears on the finished tool held up in a shaft of light (the
   tier's colour: copper warm, iron cold steel, crystal violet), a choir-like swell, the tool's
   name in big letters ("**Iron Pickaxe**: opens gold and crystal").
5. **Into your hands.** It swings into the viewmodel with a glint and a heavy settle; villagers
   nearby turn and react (a cheer, a line). **The first swing** with it has its own oversized
   impact: a shockwave ring, double sparks, the biggest hit-stop.

It escalates by tier: copper is the plain version; iron adds a thunder roll and a bell from the
town hall; **crystal is the finale**: the sky darkens, a violet beam rises from the forge over
the whole village, every villager gathers, and the bell rings out. A second press of E skips to
the reveal (for testing), but it plays in full by default.

## Phases (draft)

1. **Tool tiers in data** — `tool_tier` on `ResourceNode` (replacing the gate in `can_gather()`),
   the player's owned tool per type in `Inventory` + save, "Needs X" deflect popup.
2. **Soft levels** — under-level penalty curve and XP bonus; remove the level gate.
3. **Greta forges** — the Forge tab, costs, smithy-tier cap, tool hit power per tier (T8), the
   Crystal Forge's streak double hit (T9).
4. **The forge moment** (T12) — the cutscene, its synthesized sounds, per-tier escalation, the
   first-swing impact.
5. **Models, icons, viewmodels** — four picks, four axes, two sickles (Blender), icons, per-tier
   tint, swing sounds and sparks.
6. **Fresh-start save version (T10), README, TODO.**

Then [levels.md](levels.md) on top.

## Status

- **Phase 1 done** (branch `tools`, 2026-10-20): the `Tools` autoload (owned tier per tool type,
  saved under `tools`), `tool_tier` on every node scene, `can_gather()` checks the tool, "Needs
  Iron pick" on a deflect and on the crosshair, tool rows in the debug menu (F1 → Skills).
  The hard level gate is gone; until phase 2 there's no under-level penalty either. Until
  phase 3 the only way to a better tool is the debug menu, so an existing save drops to stone
  tools (phase 6 starts fresh anyway).
- **Phase 2 done** (2026-10-20): `required_level` is now a node's rating. Under it, hit power
  drops 6% per level (floor 40%, reached 10 levels under) and the clean-cut, crack-tip and
  weak-point windows shrink 4% per level (floor 50%); a hit that falls short of a whole cut
  takes nothing (rocks of pieces keep theirs) and pops the rating ("Mining 15") in amber, which
  the crosshair also shows. Breaking an under-levelled node gives +25% XP (`Skills.UNDER_*`).
  Headless: barley 4 → 10 swings, iron 9 → 22, oak 7 → 18 at the floor. The spear's hard gate
  went soft too: an under-levelled fish is taken with 10% less chance per level (floor 10%) and
  gives +50% XP, like the rod.
