# Levels: small perks every level, talent choices at 10 / 20 / 30 / 40

Builds on [tool-progression.md](tool-progression.md): tools decide *whether* you can gather,
levels decide *how well*. Chosen 2026-10-20 from two explorations
([levels-milestones.md](levels-milestones.md), [levels-talents.md](levels-talents.md)): B's
steady per-level growth, with D's gameplay-changing techniques turned into C-style **choices**.

Status: **designed** (grilled 2026-10-20; not started). No branch yet. Built after
tool-progression.md.

## Decisions (grilled 2026-10-20)

| # | Topic | Decision |
|---|-------|----------|
| L1 | Every level | A **small perk**, named in the level-up popup. Perks improve feel and technique (windows, recovery, reach), not raw output: the village owns the percentages (`TierEffect`). |
| L2 | 10, 20, 30, 40 | A **talent choice**: two gameplay-changing mechanics, pick one. These define how you play. |
| L3 | Styles | Each skill has two styles. At every milestone, one option is from each style. **Mixing is allowed**: you pick per milestone, not per skill. |
| L4 | Balance | Options in a pair are matched by **style, not power**: neither is "more damage". Each pair should come out about even in yield per minute (see "Keeping it balanced"). |
| L5 | Under-levelled | A real penalty, as in tool-progression T5. |
| L7 | When you pick | The two cards appear **once the current action ends** (the tree falls, the fish is landed or lost; never mid-fight), with **"decide later"**: the choice then waits in the skills panel with a badge. |
| L6 | Level 50 | **Mastery**: you also gain the other option of one milestone, your choice. It rewards whatever mix you took rather than pushing one style. |

## Every level: small perks

Each skill has three **minor tracks**, and each level adds one step to the next track in turn,
so every level names something real ("Woodcutting 13: steadier aim"). Levels 15, 25, 35 and 45
also give a **flourish** (cosmetic or sensory). Rough sizes: by level 49, each track is about +30
to 40% better than at level 1.

| Skill | Track 1 | Track 2 | Track 3 |
|---|---|---|---|
| Woodcutting | **Steadier aim**: the clean-cut tolerance into the notch is wider | **Quicker recovery**: less time between swings | **Long reach**: logs fly to you from further away (pickup magnet) |
| Mining | **Keen eye**: more leeway in how close a hit must be to a crack tip to count | **Quicker recovery** | **Long reach** (ore) |
| Fishing | **Quick hands**: the strike, bow and jerk windows are wider | **Strong line**: runs give back a little less distance | **Smooth cast**: a wider sweet spot on the release |
| Farming | **Wide blade**: the sickle sweeps a wider arc | **Quicker recovery** | **Long reach** (grain) |

Fishing's current per-10-level cast range (`range_per_10_levels`) and the level window scaling
(`FishFight.level_scales`) fold into these tracks.

**Flourishes (15 / 25 / 35 / 45)**:
- A tool trail on clean hits.
- An extra sound layer on a clean cut, or a deeper ring on a crack tip.
- An engraving on the held tool.
- A title shown in the skills panel ("Woodsman", "Stonebreaker").

## Talent choices

### Woodcutting: Feller (rhythm and speed) vs Forester (placement and care)

| Lv | Feller | Forester |
|---|---|---|
| 10 | **Chain cut**: back-to-back clean cuts each count +1 extra hit (stacks to +3); a miss resets it. Rewards rhythm. | **Back cut**: after notching, a hit from the *opposite* side counts triple and drops the tree away from you. Rewards positioning. |
| 20 | **Dominoes**: the notch's side steers the fall, and a falling trunk deals heavy damage to choppable trees it lands on. Fell a line of trees in one go. | **Heartwood**: after a few hits, a glowing knot shows somewhere on the trunk. Hit it clean for a big chunk and a **heartwood** log (rare item). |
| 30 | **Power swing**: hold to charge (about 1 s, you can't move fast): one swing counts as three hits, five if it's a clean cut. | **Grove keeper**: trees you fell regrow twice as fast, and the regrown tree is *fine-grained* (your first clean cut on it doubles its drops). Farm your own grove. |
| 40 | **Momentum**: each tree felled within 10 s of the last makes your swings 15% faster (stacks 3×). A flow state: keep moving. | **Old growth**: you can see rare, ancient trees (one per area, a faint shimmer). Each is a long fell with a huge haul and a trophy log. |

### Mining: Breaker (force) vs Prospector (reading rock)

| Lv | Breaker | Prospector |
|---|---|---|
| 10 | **Shatter**: a crack-tip hit runs the crack twice as far, so pieces split off sooner. | **Feel the grain**: after each hit, the nearest crack tip glints for a moment. |
| 20 | **Split shot**: a crack-tip hit can split the rock clean in two; both halves drop their ore at once. | **Fault sight**: faults show faintly before your first hit, and the first hit along a fault is always a crack tip. |
| 30 | **Heavy blow**: hold to charge; a charged hit on a fault breaks off its biggest piece. | **Vein sense**: ore nearby hums, louder the closer you get, and you can see hidden **rich veins** (a node variant only you can see). |
| 40 | **Rockslide**: breaking a rock sends a shockwave that leaves nearby rocks pre-cracked. Clears a quarry face fast. | **Gem eye**: some rocks hide a gem pocket (a glint). Hit it precisely to pop a **gem** (rare item). |

### Fishing: Angler (the rod) vs Spearman (the spear)

| Lv | Angler | Spearman |
|---|---|---|
| 10 | **Feel the take**: a faint rod tremble one beat before the take. | **Quiet wading**: schools don't scatter when you walk in, only when you thrust. |
| 20 | **Second strike**: once per bite, a late strike can be saved with a quick re-strike. | **Follow-through**: after a catch, a second thrust within 0.6 s can take a fish from the scattering school. |
| 30 | **Power cast**: hold the back-cast longer for +50% range, out to water no one else can reach. | **Skewer**: a thrust through a dense school can take two or three fish. |
| 40 | **Play the fish**: a perfect answer to a run turns it back toward you, so a skilled fight ends much sooner. | **Spear throw**: throw the spear up to 8 m at a fish, then pull it back. The spear reaches the rod's water. |

Choosing a style here also chooses a tool, so Fishing's pairs are balanced across *both*
tools: one rod perk and one spear perk at every milestone.

### Farming: Harvester (sweep and tempo) vs Grower (the field)

Farming is thin today (wheat and barley sheaves cut with the sickle), so these are lighter. They
may wait for a farming pass.

| Lv | Harvester | Grower |
|---|---|---|
| 10 | **Wide sweep**: one swing takes neighbouring sheaves too. | **Green thumb**: sheaves near you regrow twice as fast. |
| 20 | **Scything rhythm**: each swing on the beat of the last comes faster (stacks 3×). | **Bumper crop**: now and then a golden sheaf grows, worth triple. |
| 30 | **Reaper's spin**: hold to spin and cut everything around you. | **Ripeness**: ripe sheaves glow, and cutting one ripe doubles its yield. |
| 40 | **Threshing**: grain goes straight to your inventory, with no pickups to collect. | **Sow**: plant a sheaf anywhere you like, using grain as seed. |

## Rare items

Only three talents produce one, all on the reading-the-world side: **heartwood** (Forester 20),
**trophy logs** (Forester 40) and **gems** (Prospector 40).

| # | Decision |
|---|----------|
| R1 | **Never required.** No tool, building tier or forge costs a rare item; otherwise the talent that drops it would be mandatory and the choice fake. They're luxuries and shortcuts. |
| R2 | **XP to a skill of your choice**: any skill, not just the one that produced the item. Never dead at level 50, and it lets one trade help another catch up. |
| R3 | Each item has a main use, plus the others: |

| Item | Main use | Also |
|---|---|---|
| Heartwood | XP to the skill you choose | a gift, a respec fee, a heartwood handle (cosmetic) |
| Trophy log | the trophy wall (lodge), next to your biggest fish | a big XP burst |
| Gem | a gift to a villager for a short boost (e.g. Greta sharpens your pick for 10 min) | a respec fee, a gem set in a tool (cosmetic), XP |

Gift boosts are short and never permanent power.

| R4 | **XP is a share of the chosen skill's current level gap**, the same at any level: heartwood about 25% of a level, a gem about 40%, a trophy log about 75% (to tune against drop rates; a rare find should feel like a jackpot, not a stream). The balance bench counts them as fractions of a level. |
|---|---|
| R5 | **Spent at a villager.** Talk to any villager (E, the upgrade panel) and hand over a rare item: **Gift** (a short boost from that villager) or **Learn** (XP to a skill you choose). Any villager takes any item; their lines react to what you bring. Every find is a reason to walk back into the village. |

### Gift boosts (R6)

About 10 in-game minutes each. Any rare item works: the boost is the villager's, so you choose a
boost by choosing who to visit. Each is the villager's trade flavour, never a talent in disguise.

| Villager | Boost | Effect |
|---|---|---|
| Greta (smithy) | **Honed edge** | Much wider clean-cut and crack-tip windows on every tool |
| Bram (woodcutter) | **Timber call** | Trees fall faster and louder; a landing trunk shakes loose extra logs |
| Edda (prospector) | **Lucky strike** | The next few rocks may hold a rare item: **at most one per boost, under 50% odds**, so it can never pay for itself |
| Ollie (fisher) | **Feeding frenzy** | Fish notice the float from twice as far and nibble less |
| Rosa (baker) | **Hearty loaf** | Faster running and quicker swing recovery |
| Mayor Hartwell | **Town's favour** | +50% XP in every skill; a little better than Learn, but only if you gather the whole time |

## Keeping it balanced

- **Matched by style.** In every pair, one option is *active* (timing, rhythm, force) and the
  other *reads the world* (placement, finding, care). Neither just deals more damage.
- **Measured.** A headless bench (like `tools/test_fishing.gd`) plays each talent with a bot at
  that milestone's level and reports yield per minute. The two options in a pair should land
  within ±15% of each other. Options that rely on rare finds (heartwood, old growth, gems, rich
  veins) count by expected value.
- **Rare items need a use** (see "Rare items"), but are **never required** for progression.
- **Respec (L8).** Greta resets one skill's picks. **The first reset is free** (forgives a
  newcomer's pick at 10). After that: 10 of the skill's base goods per milestone picked (40 logs
  at Woodcutting 40) plus one rare item, **or** double the goods instead of the rare item, so no
  respec ever needs the item-dropping talents (R1).

## Open questions

1. ~~Level 50~~: decided, mastery (L6).
2. ~~When you choose~~: decided (L7).
3. ~~Respec price~~: decided (L8).
4. ~~Rare items~~: decided (R1–R3). XP size (R4) and where (R5) decided. Gift boosts decided (R6).
5. ~~Farming~~: decided, its talents wait for a farming pass and come last (tool-progression T6).

## Phases (draft, after tool-progression)

1. **Minor tracks + level-up moment**: per-skill track values read by the technique windows,
   popups naming the perk, stings, the skills panel.
2. **Talent framework**: `TalentDef` resources (`data/talents/`), picks in `Skills` + save, the
   choice cards, the talents page, respec at Greta.
3. **The balance bench** (headless, yield per minute per talent).
4. **Woodcutting talents** end to end, then played by hand before the rest.
5. **Mining**, then **Fishing**, then **Farming** talents.
6. **Flourishes, rare-item uses, README, TODO.**
