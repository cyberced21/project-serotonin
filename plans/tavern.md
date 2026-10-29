# Villager days, the tavern and the bakery terrace

Chunk 8 of [cozy.md](cozy.md) (its section 7: villager life). Grilled 2026-10-29. Branch `tavern`
off `main`.

Status (2026-10-29): **all phases built** on branch `tavern`, sounds picked by ear
(https://claude.ai/artifact/SsVfYHdugLLt1r2gyZyHsZ; the band plays "Rejoicing"). Screenshots: docs/images/tavern/
(`tools/tavern_shots.gd`). Bot-tested only: `tools/test_paths.gd`, `tools/test_day.gd`, `tools/test_dice.gd`. Open
items: docs/TODO.md, "Villager days and the tavern".

### Built, and what changed on the way

- **The walking network** is data in `scripts/village_paths.gd` (points and links, world XZ, like
  VillageDecor's spots), not markers placed in the editor. A route skips points it can see past;
  close places are walked to straight when nothing's in the way (a sphere cast on the world layer).
  `tools/village_layout.gd` + `tools/plot_village.py` draw the village from above with it.
- **Times are clock hours** (sunrise 06:00, sunset 20:00, DayNight's clock), per villager in
  `VillagerDay.PEOPLE`. An hour of night is only ~36 s, so the walk home takes most of one.
- **Seats** are markers in a "seat" group with a kind (bench, terrace, tavern), claimed by meta;
  the decor's dusk bench routine went. Rosa does the rounds of her terrace's tables at breakfast.
- **The tavern** is called the Sleepy Hound; Maud keeps it. Its tier 1 is the ruin (every building
  starts at tier 1), so its three restored tiers are 2-4. Seats, the stage, dance spots and the
  dice table are empties in the model, shown with their tier (`Building.marks`); after an upgrade
  anyone on a vanished seat finds another. Lamps, fire and windows follow its opening hours.
  Inside, the reverb is a small room (`Acoustics`, the "interior" group). Building also no longer
  loses a tier change made mid-animation.
- **The dice game** is "Hound's Luck": all scoring dice are set aside for you (no choosing which),
  so the only choice is roll or stop. Five 7 cm physics dice on their own layer in a felt tray with
  invisible walls; you play from a panel (the mouse freed), villagers by `DiceRules.STYLES`.
- **The musician is Ollie** (the fisher's "plays" quirk), with a fiddle and bow made in code; the
  band is a 3D player on the Music bus, muffled with distance, playing the library's "tavern" slot.
- Dancing: every so often during a tune at the top tier, two get up for 25 s.
- **Villagers with a seat** (sat in it, or on their way) don't stop for you coming near, only when
  you talk to them: the screenshots showed whoever came over to play dice stopping to chat with
  you (sat right across) and never sitting down.

## Where we start (2026-10-29)

- Seven villagers (`Villager`), each a child of their `Building`, walking in straight lines
  between that building's `Spots/` markers (Door, Work1..3, optional Bench and Square). There's no
  navmesh and no schedule: they pick a random spot, mostly work.
- At dark (`DayNight.is_night()`) they walk to their door and go inside till daybreak, stepping out
  if you come to the door. `VillageDecor` sends one to each project bench at dusk.
- `DayNight.time` runs 0..1 over a 20 min day (`DAY_LENGTH`), sunrise 0.15, sunset 0.85, so a
  night is about 6 min and midnight is 0.0. There's no day count.
- Window glass (`windowglass` meshes) glows the same in every house from dusk.
- Music (`Music`) plays CC0 pieces in waves by area and time of day (data/music/library.tres).
- Rosa runs the bakery (`baker_cottage`), so she gets the café.
- There are no interiors yet (chunk 9).

## Decisions (grilled 2026-10-29)

- **A day for everyone, with quirks.** One shared day shape, times staggered per villager so they
  don't move as a herd:
  1. **Morning**: breakfast at Rosa's bakery terrace (tables outside, she serves).
  2. **Day**: at their work spots, as now.
  3. **Dusk**: the square and the benches.
  4. **After dark**: the tavern.
  5. **About midnight**: home one by one, windows dark soon after.
  Each villager gets one or two quirks: Ollie fishes at dawn before breakfast, Greta skips the
  tavern some nights, the mayor makes a round of the square, and so on.
- **The bakery terrace** is a project (an entry in `Projects.SPOTS`): tables and an awning outside
  Rosa's bakery. No new building. Before it's built, breakfast is at home.
- **Getting around: a waypoint graph.** Hand-placed markers along the lanes and the square, linked
  into a network; villagers take the shortest chain, so they stay on the paths. Editable in the
  editor. No navmesh.
- **Talk anywhere.** Walk up to a villager wherever their day has taken them: they stop, face you,
  and the upgrade panel opens as now (on a tavern stool they turn round).
- **The tavern** is an upgradable building (a `BuildingDef`, 3 tiers, capped by the town hall like
  the houses) with **a new villager, the keeper**, behind the bar (the TEND work loop).
  - **On the square**, facing the town hall, so its windows and the murmur are the first thing you
    meet walking in at night. A spot is found from the terrain and props and shown in a screenshot
    before it's built.
  - **There from the start as a boarded-up ruin**; the first tier is a modest pile of logs and
    stone, so nights come alive early.
  - **You can go in.** A small, seamless interior (walk in, no fade), the first one in the game and
    the pattern chunk 9 reuses.
  - Tiers: **T1** a small taproom, a bar, two tables and the dice table; villagers drink and murmur.
    **T2** a fireplace, more seats, a musician on a little stage. **T3** a bigger room, lanterns and
    bunting, and a little dance when the music is lively.
  - **Open from dark to about midnight** (the first half of the night). The second half the
    village sleeps: crickets, lamps, the dog.
- **Chatter: murmur and gestures.** Villagers at a table face each other, nod, wave their hands,
  laugh and clink mugs, over a crowd murmur that swells as the room fills. No words on screen.
- **Music: a villager plays it**, from T2: CC0 tavern tracks picked by ear on a page, from a 3D
  source in the room, so it's heard through the door and fades as you walk off. The background
  music waves hold off near the tavern.
- **Sit and play dice.** E on a free seat: you sit, the camera settles low; any movement key stands
  you up. At the dice table, a free villager joins you:
  - **A press-your-luck game** (in the family of Pig and Farkle): roll, bank what scores, roll the
    rest again or stop; roll nothing that scores and you lose the turn's points. Exact rules to be
    settled in phase 6.
  - **Just for fun**: no bets. The winner gets a cheer and a line ("Best of three, then!"), and a
    chalkboard keeps the tally of wins per villager (saved).
  - **Any villager at the tavern**, each with a slight style (Bram plays it safe, Greta pushes her
    luck). Tavern hours only.
  - **Real 3D dice**: physics dice thrown on the table, settling where they land, the camera
    looking down at them; a wooden clatter (CC0, picked by ear). A die that lands cocked gets a
    nudge.
- **Windows follow who's home**: a house is dark while its villager is out at the tavern, lights
  up when they get home, and goes dark a little later when they go to bed. The tavern stays lit
  till closing.
- Not grilled, decided here (veto any of them): the dog lies by the tavern fire when you're inside;
  the trader (chunk 7) has a drink at the tavern before she leaves on her days; the keeper's name
  is picked with the model.

## Phases (one commit each)

1. **Waypoint graph.** A `VillagePaths` node of linked markers along the lanes and square, with a
   shortest-path query; villagers follow chains of waypoints instead of straight lines. Debug draw
   of the graph. Done: a test walks a villager from every building to every other, staying on the
   graph.
2. **The day.** A schedule (data per villager: the shared shape, their offsets and quirks) read
   against `DayNight.time`; replaces the random spot picking and the night routine, keeps the
   door visits and upgrade watching. Bench life moves into it. Done: a bot fast-forwards a day and
   checks where everyone is at each part of it.
3. **Windows by occupancy.** Per-building window light driven by whether its villager is home and
   awake. Done: screenshots at dusk, tavern time and after midnight.
4. **The bakery terrace.** Project, tables and awning model (make_village.py), breakfast seats in
   the schedule. Done: test builds it and the morning sends villagers there.
5. **The tavern building.** `BuildingDef` + `.tres`, the 3 tiers plus the ruin as one `.glb`
   (`T0_*`..`T3_*` pieces), placed on the square, the keeper villager, the seamless interior (walk
   in through the door, light from windows, lamps and the fire, interior acoustics). Tavern evening
   in the schedule: seats, tables, murmur and gestures. Done: screenshots of each tier inside and
   out, at night.
6. **Sitting and dice.** Sit on any seat (E, camera settle, stand on move). The dice table: the
   game's rules, physics dice, the camera, villager opponents with styles, the chalkboard tally
   (saved). Done: a test plays full games against a scripted villager; rules unit-tested.
7. **Music and dance.** The musician from T2 (pose loop, 3D music source), background music held
   off near the tavern, the T3 dance. Done: the music fades by distance in a test.
8. **Sounds, picked by ear.** Crowd murmur, laughs, mug clinks, dice clatter, tavern tracks: CC0
   candidates on an Artifact page, picked by the user.
9. **Docs.** README, docs/TODO.md, docs/village-design.md (schedules no longer parked), this plan
   as built; screenshots.

## Open

- Prices for the tavern tiers and the terrace (placeholders, tuned in play).
- Whether the keeper or the musician has their own house (as built: Maud goes in at the tavern's
  door; Ollie goes home to the fisher's hut).
