# Cozy: the new direction

Written 2026-10-27 from an idea dump. **Cozy beats everything else.** When a feature has to choose
between calm and punchy, calm wins. This file is the umbrella design: every section below becomes
its own plan (and branch) when we start it, after a grill session on its open questions.

Status: **chunks 1–3 built, merged, released v0.3 and playtested** (2026-10-28):
[mood-pass.md](mood-pass.md), [calm-feel.md](calm-feel.md), [cozy-sound.md](cozy-sound.md).
Chunks 4–7 merged and released: lamps v0.4 ([lamps.md](lamps.md)), projects v0.5
([projects.md](projects.md)), the dog v0.7 ([dog.md](dog.md)), the market v0.8
([market.md](market.md)); mostly unplayed. Chunk 8 (villager days + the tavern) grilled
2026-10-29 → [tavern.md](tavern.md). Open questions at the end of each section.

## The pillars

1. **Calm first.** Soft light, gentle fog, slow movement, warm sounds. Nothing glares, nothing rushes.
2. **The world answers your work.** Resources you spend change the world you see, not just numbers.
   Some spending is purely for ambiance, and that counts as progress too.
3. **Day and night feel different.** Day is busy and bright; night is lantern-lit, crickets, the
   tavern full of villagers.
4. **Company.** Villagers with lives, and a dog that follows you around.
5. **Sound is half the coziness.** Every sound gets reworked for satisfaction and warmth (gated on
   its own grill session, see section 9).

## What this changes in what we have

The gathering work so far leaned toward *juice* (camera kicks, FOV punch, shakes, "Weak spot!"
bursts, time trials). That's the opposite pull. Proposals, to confirm in a grill:

- **Tone the juice down, don't remove it.** Keep the satisfying hit, lose the jolt: smaller camera
  kicks, no FOV punch, softer popups. Probably a "calm" default with the current feel as an option.
- **Under-levelled penalty** (`plans/levels.md` L5, "a real penalty"): soften to "slower" rather
  than "punishing"?
- **Time trials** (`scripts/time_trial.gd`): keep as an opt-in debug/bench thing, out of the game loop.
- **The quarry** becomes a mine (section 6). Ore walls (`plans/ore-walls.md`) fit a mine's walls well.
- **Villagers have no schedule** today (`docs/village-design.md`). They will need one (section 7).

---

## 1. Light and sky: softer, and sunrise ≠ sunset

**Grilled 2026-10-27 → [mood-pass.md](mood-pass.md)** (decisions and phases there; this section is
the original pitch).

Today `day_night_sky.gd` has **one** dusk palette (`DUSK_TOP`, `DUSK_HORIZON`, `DUSK_GRADE`) used for
both ends of the day, plus a morning mist.

- **Two twilight palettes**, picked by whether the sun is rising or setting:
  - **Sunrise:** yellow and orange. Pale gold horizon, peach clouds, a clean cool-blue top; mist in
    the low ground catching the gold.
  - **Sunset:** pinker. Rose and magenta horizon, lilac top, warm pink grade on highlights; clearer
    air than morning.
- **The sun is too blinding:** lower the sun's energy and glow/bloom at midday, cap how bright the
  sun disc gets, and let the colour grade lift shadows a little (soft, not contrasty). Check the
  sun-in-view case specifically (looking toward it shouldn't white out the screen).
- **The fog is too oppressive:** thinner distance fog by day so the valley reads at a glance;
  volumetric mist only in the morning and in low spots, and light shafts kept subtle. The quarry's
  depth fog goes with the quarry. Each biome's `fog_density` / `mist` factors get re-tuned downward.
- Night stays readable: moonlit blue, not black, with warm lamp pools as the contrast.

Open: do we want weather at all (soft rain on roofs is very cozy; storms aren't)? Day length?

## 2. Night ambiance

- **Separate day and night soundscapes**, crossfaded with the time of day (`DayNight.twilight()`):
  - Day: birds, wind in leaves, distant village chatter, a hot-afternoon cicada drone in summer
    fields (cicadas are a daytime insect, so they mark warm afternoons).
  - Dusk: birds settle, first crickets, frogs by ponds.
  - Night: crickets, frogs, an owl, wind; the tavern's murmur and music when you're near it.
  - **A rare wolf howl**: far away, heavy reverb, maybe once every several in-game nights, never
    near the village. Cozy, not scary: the dog's ears could prick up and it answers with a small
    "woof". (Confirm in the sound grill.)
- **Fireflies:** soft blinking points over grass, ponds and the forest edge from dusk to midnight;
  they drift away from you, never swarm.
- Night visuals: stars, moon, windows glowing warm, chimney smoke lit by lamps.

Open: seasons (fireflies and cicadas are summer things)? Or a permanent late summer?

## 3. Lamps, torches and your lantern

**Grilled 2026-10-28 → [lamps.md](lamps.md)** (decisions and phases there; this section is the
original pitch).

- **Lampposts and torches along the paths** (the roads come from `road_course.gd`, so posts can be
  placed along them at a spacing). They light at dusk with a small flicker-on, one after another.
  A nice touch: a **lamplighter** villager walks the path at dusk lighting them.
- More lights are a **village project** (section 5): early on only the village square is lit, the
  path to the clearing gets lamps when you pay for them, then the lake path, then the mine road.
- **A lantern you carry:** an item you hold (or hang on your belt so your hands stay free for
  tools), a warm moving light with gentle sway. Night becomes "walk home by lantern light".
- **The dog can carry it** in its mouth (section 4), freeing your hands entirely.

Open: does the lantern need fuel (oil from somewhere)? Proposal: no, cozy means no chores.
Belt or hand?

## 4. The dog

- A dog who **follows you** at a relaxed distance, sniffs around, sits when you stop, lies down
  when you gather for a while, trots ahead on paths.
- **Carries the lantern** in its mouth at night when you give it to him.
- **Pet him** (E): a little animation, a happy sound. No happiness meter, nothing to maintain.
- **A dog house** built in the village, upgraded like a building (kennel → painted doghouse with
  name sign → doghouse with a bowl, blanket and a little porch). He sleeps there at night if you're
  in the village, or curls up by you otherwise.
- Maybe later: he notices things (barks at a fault in a rock, points at a fish school), small help,
  never required.

**Grilled 2026-10-29 → [dog.md](dog.md)** (a stray met on the first morning, three breeds, you
name him, hints only, the doghouse as three chained projects). Built 2026-10-29 on branch `dog`, sounds picked by ear.

## 5. A world that grows with what you spend

**Grilled 2026-10-28 → [projects.md](projects.md)** (projects and decorations; the landslide, market
and café are chunks 7 and 8).

Today's spending is building tiers (`Village` autoload, `BuildingDef` tiers). This extends it.

- **Two kinds of spending, side by side in the same panel:**
  - **Upgrades**: the existing tiers, they unlock things (better tools, new fish...).
  - **Projects** for ambiance: flower boxes, lampposts along a path, a well, benches, a fountain,
    bunting for a festival, a fixed bridge. They change the look and sound of the world. Some feed
    back into villager life (benches give villagers somewhere to sit at dusk).
- **Decorations you place**: lanterns, benches, planters, fences, a café terrace. Either placed
  freely with a build mode, or on predefined "slots" around the village (simpler, always looks
  good). *Recommendation: slots first.*
- **A café**: a building villagers visit in the morning, the day's counterpart to the tavern.
- **In-world progress checks**: real obstacles in the world you clear with resources:
  - a **landslide** blocking the road out of the valley. Clearing it (stone, logs for a retaining
    wall) lets **traders and visitors** come to town;
  - a broken bridge to the lake, a fallen tree on the forest path, a flooded mine level.
  These replace some numeric gates with something you can see and walk past.
- **A market stall** you build: a resources exchange. Trade what you have plenty of for what you
  need, at rates that are a bit lossy (so gathering stays the main way). Visiting traders (after the
  landslide) bring better rates or rare goods on certain days.

**Chunk 7 grilled 2026-10-29 → [market.md](market.md)**: a road east blocked by a landslide you dig
out and shore up, a barter market stall, a trader cart every second day (dog collars, decorations,
lantern glass). Barter only; the trader passes through. Built 2026-10-29 on branch `market`.

## 6. The mine (instead of the quarry)

The quarry becomes a **cave system that grows with the village**.

- **The mine entrance** sits in the rocky hills. Early on it's one shallow chamber with copper and
  coal by lamplight.
- **Mine upgrades**, built like buildings: shore up the entrance with timber, lay rails, a **minecart**
  that takes you to deeper levels, a lift. Each level has its own look and ore:
  - Level 1: earthy tunnels, copper, coal.
  - Level 2: iron in rusty rock, an underground stream.
  - Level 3: gold, crystal caverns that glow softly (cozy, not spooky).
- The minecart ride itself is a calm moment: a gentle rattling descent, lanterns going past.
- Mine levels are cleared like the landslide: a flooded tunnel needs a pump, a collapse needs
  timber supports.
- Ore walls (`plans/ore-walls.md`) become the natural way to mine in tunnels.

Open: hand-built caves or generated (procgen already makes worlds)? Does the mine replace the
quarry in procgen worlds too? Is the mine dark enough that you need the lantern/dog?

## 7. Villager life

- **Daily routines**: morning at the café, day at their work spots, evening on benches, **night at
  the tavern** drinking and having fun (laughing, clinking mugs, someone playing music, maybe a
  little dance), then home to bed with their windows going dark one by one.
- **The tavern** is a building (and upgradable): more tiers = more music, more people, a fireplace.
  You can go in, sit, listen.
- Visitors and traders (section 5) join the routines.

Open: can you join in (sit down, drink, a little minigame)? Do villagers talk to each other?

**Grilled 2026-10-29 → [tavern.md](tavern.md)**: a shared day with quirks on a waypoint graph,
breakfast on Rosa's bakery terrace, a tavern on the square (a ruin you restore, 3 tiers, a keeper,
the first walk-in interior), murmur and gestures, a musician, and a press-your-luck dice game with
real 3D dice, played for fun.

## 8. Interiors and add-ons

- **Go inside buildings**: the woodcutter's lodge, the smithy, the tavern, your own home. Interiors
  are small, warm, full of detail; the light from windows and fireplaces matters most.
- **Add-ons**: optional pieces bolted onto a building, separate from its tier: a porch, a garden, a
  chimney, a sign, window boxes, an awning. Some are cosmetic projects, some functional (a drying
  rack for the fisher).
- **A player home** to come back to (bed to sleep through the night, a fireplace, a place for the
  dog). Doesn't exist yet.

Open: seamless interiors (walk in, same scene) or a loading fade? *Recommendation: seamless for
small ones, it keeps the calm.* A player home, yes or no?

## 9. Sound and music overhaul (gated: needs a grill session)

The whole soundscape gets redone around **satisfaction and coziness**. We don't design this here:
it gets **a dedicated grill session** before anything is made. Topics to grill:

- **Music:** there's no music at all today. Style (acoustic guitar, piano, music box, lo-fi?),
  when it plays (constant, or in waves with silence between, like many cozy games), day vs night
  themes, tavern music, the mine. Source: synthesized/procedural, or commissioned/licensed tracks?
  (We synthesize sound effects today because the bundle didn't fit; music is a different problem.)
- **Footsteps:** grounded and satisfying: weight, per-surface (grass, dirt, gravel, wood planks,
  stone, the cave), a slight crunch, matching the slower walk.
- **Gathering sounds:** softer transients (the sharp "attack" at the start of a sound), more body
  and warmth, still satisfying. Where the "satisfying click" lives without being harsh.
- **UI sounds:** soft, wooden, paper-like.
- **Ambiance layers:** day/night/dusk sets (section 2), interiors muffling the outside, rain on roofs.
- **Mixing:** overall loudness, how much reverb, the bus layout (the sound pass and menus already
  conflict there, see memory).

## 10. Movement

- **Calm, relaxing movement**: slightly slower default walk, softer acceleration and stopping (no
  snap), a gentle head bob that can be turned off, a relaxed sprint (a jog, not a dash).
- Footsteps synced to the slower gait (section 9).
- Maybe: sit on benches, lean on fences, look at the view.

Open: is sprint still needed? A stamina bar would be anti-cozy; no stamina.

---

## Suggested order

Cheapest and most transformative first, so the game *feels* cozy early, then the big systems.

| # | Chunk | Why here | Size |
|---|-------|----------|------|
| 1 | **Mood pass**: sunrise/sunset palettes, sun glare, fog | Mostly tuning in `day_night_sky.gd` and biomes; changes the feel at once | S |
| 2 | **Calm movement + toned-down juice** | Small code changes, big feel change | S |
| 3 | **Sound & music grill**, then night ambiance, fireflies, footsteps | The grill blocks the sound work; fireflies can go ahead | M |
| 4 | **Path lamps + the carried lantern** | Builds on existing lamplight; makes nights a feature | M |
| 5 | **Projects & decorations** framework (slots, café, benches, lamps as projects) | Extends `Village`/`BuildingDef`; everything after uses it | M |
| 6 | **The dog** (+ dog house as a project) | Needs 4 for the lantern, 5 for the doghouse | M |
| 7 | **Landslide + market stall + traders** | Uses 5; first in-world progress check | M |
| 8 | **Villager routines + the tavern** | Needs schedules, a new building | L |
| 9 | **Interiors + add-ons + player home** | Biggest art cost | L |
| 10 | **The mine** (replaces the quarry, minecart, levels) | Biggest system; reuses ore walls | L |

The rest of the sound overhaul runs alongside from step 3 on, once the grill has set its direction.

## Next step

Grill each chunk before its own plan; the open questions in each section are the starting list.
Next: build chunk 8 from [tavern.md](tavern.md) on branch `tavern`. After it: chunk 9 (interiors,
add-ons, a player home), which reuses the tavern's interior pattern.
