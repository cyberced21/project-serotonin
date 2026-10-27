# Levels: small perks every level, talent choices at 10 / 20 / 30 / 40

Builds on [tool-progression.md](tool-progression.md): tools decide *whether* you can gather,
levels decide *how well*. Chosen 2026-10-20 from two explorations
([levels-milestones.md](levels-milestones.md), [levels-talents.md](levels-talents.md)): B's
steady per-level growth, with D's gameplay-changing techniques turned into C-style **choices**.

Status: **phases 1 to 3 built** (3: the bench) 2026-10-27 on branch `levels` (off `fishing-yank`): the minor
tracks (`scripts/perks.gd`), the perk line under the level-up banner, a Skills page in the pause
menu; the talent framework (choice cards, picks saved, mastery, respec at Greta). Unplayed by
hand. **The talents don't do anything yet**: their effects are phases 4 and 5.

## Decisions (grilled 2026-10-20)

| # | Topic | Decision |
|---|-------|----------|
| L1 | Every level | A **small perk**, named in the level-up popup. Perks improve feel and technique (windows, recovery, reach), not raw output: the village owns the percentages (`TierEffect`). |
| L2 | 10, 20, 30, 40 | A **talent choice**: two gameplay-changing mechanics, pick one. These define how you play. |
| L3 | Styles | Each skill has two styles. At every milestone, one option is from each style. **Mixing is allowed**: you pick per milestone, not per skill. |
| L4 | Balance | Options in a pair are matched by **style, not power**: neither is "more damage". Each pair should come out about even in yield per minute (see "Keeping it balanced"). |
| L5 | Under-levelled | A real penalty, as in tool-progression T5. |
| L7 | When you pick | The two cards appear **once the current action ends** (the tree falls, the fish is landed or lost; never mid-fight), with **"decide later"**: the choice then waits in the skills panel with a badge. |
| L9 | Fishing track 2 (2026-10-27) | **Patience** replaces *Strong line*, which did almost what the Second strike talent does: rod bites come sooner, and a school you scattered settles sooner. Fishing's version of "quicker recovery", for both tools. |
| L10 | Angler 40 (2026-10-27) | **Trophy hunter** replaces *Play the fish* (the fight it turned is gone): the rod's way to target size, as the spear already can by eye. |
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
| Fishing | **Quick hands**: the strike window (rod) is wider and the thrust (spear) a little thicker | **Patience**: bites come sooner (rod), a scattered school settles sooner (spear) | **Smooth cast**: a wider sweet spot on the release |
| Farming | **Wide blade**: the sickle catches a sheaf a little off the crosshair | **Quicker recovery** | **Long reach** (grain) |

As built: each level from 2 adds one step (2.2%) to tracks 1, 2, 3 in turn, so +35 to 37% at 50.
Quick hands took over the old level scaling of the strike window (`FishBite.window_scale`, now
gone) and Smooth cast that of the cast's sweet spot. The rod's cast range
(`range_per_10_levels`) and the spear's skewer length (`reach_bonus_per_10_levels`) stay as they
are: the fishing bench balanced the two tools with them. Wide blade isn't Harvester's *Wide
sweep* (one swing, several sheaves): it only forgives aim. (The rod's fight is gone since
2026-10-27: plans/fishing-parity.md.)

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
| 40 | **Trophy hunter**: the biggest fish nearby notice your float first, so far more of your catches are Big or Huge. | **Spear throw**: throw the spear up to 8 m at a fish, then pull it back. The spear reaches the rod's water. |

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

1. ~~**Minor tracks + level-up moment**~~: done 2026-10-27. `Perks` (track values) read by the
   technique windows, swing recovery, pickup magnet, sickle aim and fishing; the perk named
   under the level-up banner; a Skills page in the pause menu; `tools/test_perks.gd`.
2. ~~**Talent framework**~~: done 2026-10-27. `TalentDef` (all 32 in `data/talents/`, texts from
   the tables above); `Talents` (owned by `Skills` as `Skills.talents`, saved under its own key
   `talents`, so old saves load with no picks); gameplay asks `Skills.talents.has(&"chain_cut")`.
   `TalentCards` (on the HUD) waits until you're idle 2.2 s after a milestone, pauses, and shows
   the pair; "Decide later" / Esc leaves it waiting (a badge on the pause menu's Skills button,
   a Choose button on the Skills page). Mastery offers the four options not taken. Greta's panel
   has a third tab, Talents: reset one skill, free the first time, then 20 of its base goods per
   pick (the rare-item option, 10 per pick plus one item, comes with rare items in phase 6).
   `tools/test_talents.gd` (rules) and `tools/talent_playtest.gd` (the flow in a real world).
3. ~~**The balance bench**~~: built 2026-10-27, `tools/talent_bench.gd` on a shared bot
   (`tools/bench_bot.gd`, also behind `tools/fishing_bench.gd` now). Per milestone: a no-talent
   baseline, then each option alone, at that level with the best tools, each `--repeats` times in
   a fresh copy of one world (fishing: the pond in main.tscn, rod and spear each against their
   own baseline). Judged on items/min (fishing: XP/min). Windowed and muted. It reports its own
   noise and won't judge a pair when runs of one option disagree by more than ±15%.
   **Finding**: the bot isn't frame-exact, so runs scatter: mining ±14% at 2 game minutes, the
   rod ±12% at 3. Use 5+ minutes and 3 repeats for verdicts (long: ~20 min per milestone). The
   spear at level 10 on the pond barely caught anything (0.3 fish/min): most fish were below
   its length. The bot now only goes for fish it can reach. The fishing tools were balanced at
   30 (plans/fishing-parity.md); level 10 needs a look.
   Also fixed: walks the bot skips by teleporting are now really charged to the clock (the
   fishing bench's next steps used to swallow them, so the rod's walks were free).
4. **Woodcutting talents** end to end, then played by hand before the rest. **Built, not
   balanced** (2026-10-27): all eight in `ResourceNode` ("woodcutting talents" section) and
   `player.gd` (Power swing's charge, Momentum); heartwood and trophy logs are items (icons are
   tinted log icons for now). `tools/woodcutting_talents_playtest.gd` checks each one headless.
   **The talent model** (`tools/talent_model.gd`): woodcutting worked out in code on a measured
   world's trees (`tools/model_data/`), every number read from the game; all milestones in a
   few seconds, no noise. It plays the best trees for the level with the axe that just opens
   them (the bench used the best axe, which fells everything in 1-2 swings and flattens every
   talent). First findings (60 game min, a bot that never misses):
   | Lv | Pair | Result |
   |---|---|---|
   | 10 | Chain cut / Back cut | +0% / -10%: 5-hit trees fall before a chain starts; walking round costs more than the triple gives |
   | 20 | Dominoes / Heartwood | +0% / +282%: oaks stand 12-16 m apart (nothing to fall on); a knot on every tree is a stream of heartwood, not a jackpot |
   | 30 | Power swing / Grove keeper | -9% / +120%: a 1 s charge for 3 hits loses to 6 quick swings; double-speed regrowth plus double logs on every regrown tree |
   | 40 | Momentum / Old growth | -4% / +0%: chopping isn't the limit (walking and regrowth are); no ancient pine near the start |
   Woodcutting is **limited by walking and regrowth**, not swing speed: trees take 3-6 s to fell
   and regrow in 15-40 s. Speed talents have little to win; yield talents dominate. Needs
   design decisions before tuning (see the session of 2026-10-27).
5. **Mining**, then **Fishing**, then **Farming** talents.
6. **Flourishes, rare-item uses, README, TODO.**
