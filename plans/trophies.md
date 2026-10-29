# Trophies for your wall

The trophy wall from [home.md](home.md) (the Cottage's six empty plaques, `TrophySlot1..6`).
Grilled 2026-10-29. Branch `home` (on top of chunk 9).

Status (2026-10-29): phases 1-2 built (`Trophies`, the finds, `test_trophies.gd`); phase 3's
models made (`tools/blender/make_trophies.py` -> `models/trophies/`, two looks each, the fish per
species) and waiting on picks: https://claude.ai/artifact/PNsWV5QD83YmXJdtMeRGHz (db `picks/main`).
Phases 4-6 (hanging, villagers and the full wall, docs) after the picks.

## Where we start (2026-10-29)

- The Cottage and Homestead have six empty plaques by the desk (`trophy_wall()` in
  `tools/blender/kit_buildings.py`, markers `TrophySlot1..6`).
- A `trophy_log` item exists: a woodcutting talent drops one now and then when a tree falls
  (`ResourceNode._bonus_items`). It does nothing yet.
- Fish come in sizes, Big and Huge (`FishSize`); a Huge catch is rare.
- The inventory is item counts only (`Inventory`): nothing in it can carry a label.
- Villagers already visit your home and comment on what's new (`Home.visited`, `REACT`).

## Decisions (grilled 2026-10-29)

- **What a trophy is:** a rare find you carry home and choose to hang. Swap them whenever you like.
- **Keepsakes only:** no perks, no stats. You hang what you love.
- **The kinds**, each with a look on the wall and a rate:

  | Trophy | Found | On the wall |
  |---|---|---|
  | Trophy log | ~1 in 150 trees anyone fells (the talent raises it; today only the talent drops it) | A polished cross-section, rings to count |
  | Huge fish | Every Huge catch (kept, not sold) | Mounted on a board, per species |
  | Geode | ~1 in 120 ore veins broken, iron up | Cracked open, crystals inside |
  | Golden sheaf | ~1 in 200 harvests | Gold-tinted wheat tied with ribbon |
  | Peak feather | One glinting in Frostpeak's snow every 2-3 in-game days, at a random spot (the dog may sniff it out) | An eagle's feather under glass |
  | Lake shell | One on Stillwater's shore every 2-3 days, in the mornings | A big spiral shell |
  | The dog's stick | Once, ~5 days after he became yours (rarely after) | A stick, mounted with great ceremony |

  About one trophy an hour or two of ordinary play. Duplicates allowed (a bigger pike can replace
  the first).
- **Each trophy is a record, not a stack:** what it is, where, which day, and a fish's size.
  Labels like "Huge pike, 1.4 m, Stillwater, day 12". The pack shows them in their own Trophies
  row; the market never buys them.
- **Finding one:** a gold popup ("A trophy! Take it home for your wall") and a soft chime.
- **Hanging:** E on an empty plaque opens a small panel of the trophies you're carrying; pick one
  and it pops onto the plaque with a little brass label and a wooden knock. E on a hung one:
  its label up close, Take down (back to your pack) or Swap. Looking at it shows the label.
- **Places:** Cottage: the 6 plaques. Homestead: the 6 plaques plus a mantel shelf over the
  hearth with 3 spots for the small ones (shell, feather, geode). Going up a tier, whatever's
  hung moves plaque for plaque. Before the Cottage, trophies wait in your pack.
- **Villagers:** on a visit, a villager notices a trophy they haven't seen, once each, in their
  own voice (Ollie on a fish, Bram on the log, Edda on a geode, Greta on the dog's stick...).
- **A full wall** (all 6, or all 9 at the Homestead): the mayor leaves a framed note on your desk,
  "Hearthvale's proudest wall", and it hangs by the door. Cosmetic, once.
- **Not doing:** perks or set bonuses, villagers asking for trophies or giving theirs.

## Phases

Each phase a commit on `home`; run through and report at the end.

1. **Trophies as records.** A `Trophies` autoload: the list you carry and what's hung where
   (saved), each record's label; a Trophies row in the pack; the popup and chime on finding one.
   The trophy log becomes a record (and its base drop chance). Done: a test finds, saves and loads
   one with its label.
2. **The other finds.** Huge fish kept as trophies (at the landing), geodes from veins, golden
   sheaves from harvests, the peak feather and lake shell (spawned in the world, saved), the dog's
   stick. Done: a test forces each and checks the record.
3. **The models.** Each kind on the wall (Blender, ours and kit props), the fish per species,
   the plaque labels; the Homestead's mantel with 3 spots. A render sheet on a pick page
   (pick-on-a-page) before going on.
4. **Hanging.** The plaques as interactables, the pick panel, take down and swap, look-at labels,
   moving up a tier. Done: a test hangs, swaps and takes down.
5. **Villagers and the full wall.** Visit comments per villager per trophy, the mayor's framed
   note. Done: a test fills the wall and sees the note.
6. **Screenshots, README, TODO, the plan as built.**
