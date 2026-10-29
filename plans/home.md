# A home, interiors and add-ons

Chunk 9 of [cozy.md](cozy.md) (its section 8: interiors and add-ons). Grilled 2026-10-29. Branch `home`
off `main`.

Status (2026-10-29): grilled. Phase 1 pick page is up, waiting on picks:
https://claude.ai/artifact/Pkbpyd4N1Uy3LUT9EyLG1R (113 renders; saved to its db, `picks/main`).
Packs and renders are in `E:\Godot\downloads\art-packs` and `art-pick` (C: is low on space).

## Where we start (2026-10-29)

- Seven village buildings (`data/buildings/*.tres`): town hall, woodcutter's lodge, smithy, fisher's
  hut, baker's cottage, prospector's cottage, tavern. Tiers cost items, are capped by the town
  hall's tier (3) unless `BuildingTier.hall_tier` says otherwise, and give perks (`TierEffect`,
  summed by `Village.stat()`).
- Every model is made in code by Blender scripts (`tools/blender/make_village.py` and friends): boxes,
  cylinders and bevels, which is why the houses look rough and geometric. They are also too small.
- The tavern is the only interior: seamless (walk in, no fade), in the "interior" group so
  `Acoustics` gives it a small-room reverb. Seats are markers in the "seat" group with a kind.
- Villagers walk to their door at night and vanish till morning; windows light while they're home.
  Nobody has a bed, and there's no sleeping in the game.
- The game is first person, so there's no camera-through-walls problem indoors.
- The inventory has no capacity, so storage is not a reward.
- There's no player home. The dog has a kennel project by the square.

## Decisions (grilled 2026-10-29)

### The player home

- **A building like the others** (a `BuildingDef` with tiers), four tiers:

  | Tier | Name | What's there | Reward |
  |---|---|---|---|
  | 1 | **Tent** (from the start) | A bedroll, a fur patch for the dog, a small campfire | It's home: a map pin; the dog sleeps here instead of the square |
  | 2 | **Cabin** (wood, birch; town hall 1) | A real bed, a stove, a basket for the dog | **Sleep from dusk** (skip the night) |
  | 3 | **Cottage** (oak, stone; town hall 2) | A hearth, a kitchen corner, **the desk**, **the trophy wall** | **Well rested**; **morning notes and gifts** |
  | 4 | **Homestead** (planks, iron, crystal; town hall 3) | A loft bedroom, a porch | **Head home** from the map at dusk; the home's **add-on slots** |

  Tier 2 sets `hall_tier = 1` (the default rule would need a second hall). Costs are first guesses.
- **Where:** the village's rim, on a gentle rise above the creek, facing west for the sunsets,
  30-45 s walk from the square. Needs ~14×14 m of flat ground for the Homestead and its add-ons
  (may need a little terrain work). **New games start there**; old saves get the tent placed and
  keep their position. Its site is data, not baked in: a world pass after cozy will move the village.
- **Sleeping:**
  - The tent's bedroll: from midnight. The Cabin's bed: from dusk. Never by day ("Not tired yet").
  - A slow fade, the fire crackling, wake at first light (06:00), the view rising from the bed.
  - The world **fast-forwards honestly**: villagers to bed and on to breakfast, nodes regrow on
    their timers, lamps go out, as if the hours passed. No special sleep rules.
  - Autosave on waking.
  - The dog curls up on its fur patch / basket when you go to bed (comes home if it was off), and is
    there wagging when you wake.
- **Well rested** (Cottage): a full night in your own bed gives extra XP until noon.
- **The desk** (Cottage): some mornings there's a note: a villager's thanks for something you built,
  a gentle hint at what the village could do next (a tier, an add-on), or a little gift (a few logs,
  a fish, a pie for the dog). Small, not a currency.
- **Head home** (Homestead): from the world map, at dusk only, go straight home.
- **The trophy wall** (Cottage): built as an empty wall. What goes on it gets its own grill later,
  with the user grilled for ideas.

### Villagers come to you

- **Visits** (from the Cabin): every few in-game days a villager walks up to your home. If you're
  near, they chat; if not, they leave a gift on the doorstep.
- **Porch company** (from the Homestead): some evenings one sits on your porch (or the swing) before
  the tavern; you can sit beside them.
- **They react** the first time they see a new tier, add-on or trophy.
- Built as quirks in the shared day (`VillagerDay`), no new AI.
- They never come inside. The home is yours and the dog's.

### Interiors: every building, rebuilt bigger

- **Every building can be entered**: the seven village buildings and the home, all seamless like
  the tavern. Each shows the villager's trade (Bram's saw horse, Greta's anvil, Rosa's ovens) and
  their life: a bed, a table, a few personal things.
- **The inside grows with the tiers**: tier 1 is one room; the middle tier adds furniture and a work
  corner; the top tier a second room or a loft.
- **Sizes:** about 6×8 m inside at tier 1, 10×12 m plus a loft at the top. Hearthvale gets re-laid
  around the new sizes (positions, paths in `village_paths.gd`, `Spots/`, seats).
- **What there is to do inside:**
  1. **Look-at objects**, 4-6 per interior: E gives a short line in the villager's voice (Bram's
     grandfather's axe, Greta's first broken hammer, Rosa's recipe book). Some change with the tier.
  2. **Sit** on any chair (the seat system).
  3. **Villagers live at home**: on evenings they skip the tavern they're inside (Greta reading by
     the hearth, Rosa kneading tomorrow's dough); at night they're in bed, asleep.
- **Doors** are open while the villager is up. While they sleep the door is shut, and knocking gets
  a line.
- Not doing: hidden collectibles, taking things, new crafting stations.

### Add-ons

- **Slots open with tiers**: one at tier 2, a second at the top tier (the home's at the Homestead).
- **Each slot is a fork**: two add-ons, you build one. Each is a different model in the same spot,
  with a different effect.
- **Swappable**: pay for the other one and the first comes down.
- **Every add-on does something.** Purely cosmetic things stay projects/decorations.
- First forks (effects from `TierEffect` where one exists; to tune):

  | Building | Fork A | Fork B |
  |---|---|---|
  | Woodcutter's lodge | Drying rack: extra logs | Sharpening bench: more double hits |
  | Fisher's hut | Smokehouse: speared fish count twice more | Lookout perch: calmer fish |
  | Smithy | Quench trough: extra ore | Big bellows: faster rock regrowth |
  | Bakery | Bread oven: well rested lasts longer | Terrace awning: more at breakfast |
  | Tavern | Beer garden: outdoor evening seats, music carries | Bigger stage: a second musician |
  | Home | Porch swing: sit and watch, time passes faster | Garden plot: grows something each morning |

  The town hall and prospector's cottage forks are still to be found.

### Art

- **A first:** CC0 model packs (Quaternius, Kenney, KayKit...) for furniture and props, recoloured
  to our palette by a script; the shells (walls, roofs, timber frames) stay generated, but the
  generator is reworked for proportions: thick walls, overhanging roofs, crooked beams, framed
  windows.
- **B as the fallback** if the packs don't look right: everything generated, just better.
- **Picked on a page**, like the sounds: candidates rendered in our palette on an artifact page;
  the user picks, then we build on the picks.

## Phases

Each phase is a commit on `home`. Stop after phase 1 for the user's picks; otherwise run through
and report at the end.

1. **Art spike (the A/B gate).** Fetch CC0 furniture/prop packs, recolour candidates to the palette,
   render them, and put them on an artifact page grouped by room (bed, table, hearth, shelves,
   trade tools...). The user picks, or chooses B. Done: picks recorded here.
2. **Shell generator rework.** Proper proportions, thick walls, overhanging roofs, timber frames,
   tried on the woodcutter's lodge first. Done: before/after screenshots.
3. **Interior framework.** The tavern's room generalised: the "interior" group for every building,
   doors open/shut by the villager's day, beds villagers sleep in, evening at home, look-at objects
   (E, a line in the villager's voice). Done: a bot follows a villager from work to their bed.
4. **The home, tiers 1-2.** The site, the tent, the bedroll and fur patch, the spawn moved, the
   save migration; the Cabin; sleeping (midnight / dusk), the honest fast-forward, autosave, the
   dog's bedtime. Done: a bot sleeps a night and wakes at 06:00 with the world moved on.
5. **The building pass.** Every village building rebuilt bigger with its interior per tier and its
   look-at lines, one commit per building; Hearthvale re-laid around them. Done: screenshots of
   every building inside and out at every tier.
6. **The home, tiers 3-4.** Well rested, the desk (notes, hints, gifts), the trophy wall (empty),
   the Homestead, head home from the map at dusk. Done: a bot wakes rested and finds a note.
7. **Villagers come to you.** Visits, doorstep gifts, porch company, reactions. Done: a bot
   fast-forwards days and sees a visit and a porch evening.
8. **Add-on slots.** The framework (slots per tier, forks, swapping) and every building's forks.
   Done: a fork built, swapped, and its effect read by `Village.stat()`.
9. **Screenshots, README, TODO, the plan as built.**
