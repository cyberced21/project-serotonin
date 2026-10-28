# Projects: things you pay for to make the village prettier

Chunk 5 of [cozy.md](cozy.md) (its section 5, without the café, landslide and market). Grilled
2026-10-28. Branch `projects` off `lamps` (it uses the road stretches from [lamps.md](lamps.md)).

Status: **grilled, nothing built.**

## Where we start (2026-10-28)

- Spending today is building tiers: a `BuildingDef` (data/buildings/*.tres) lists its `BuildingTier`s,
  each with a `cost` (item id -> amount) and a town hall tier it needs; the `Village` autoload saves the
  tiers; a villager's panel (`UpgradePanel`, E) shows the next one and upgrades it. A building grows
  piece by piece with a wooden tok (`Building`), then its villager cheers.
- Goods: logs (wood, birch, oak, pine), ores (ore, iron, coal, gold, crystal), crops (wheat, barley),
  fish (perch, trout, pike, char, grayling, salmon). Town hall 2 costs 20 logs, 10 copper, 5 perch.
- Road stretches and their lamps exist (`Lamps`, `PathLamps`); only the village path is lit, the rest
  is the debug menu's.
- Props (`Prop`, models/village/props: bench, lamp_post, barrel, crates, signpost) and the village
  layout in village-local offsets (procgen `VILLAGE_PROPS`; Hearthvale's in main.tscn).
- Villagers walk between their building's spots and can sit on a bench spot; no routines yet.

## Decisions

| # | Question | Decision |
|---|----------|----------|
| P1 | Where to buy | **A noticeboard in the square**: projects are notes pinned on it, paid there. |
| P2 | Placement | **Set spots**: each project has its place, chosen to look good. |
| P3 | First batch | **All four groups**: road lamps (per stretch), benches and flower boxes, a well and bunting, a fountain and a mended bridge. |
| P4 | Effects | **Mostly looks, a little life**: villagers sit on the new benches at dusk, someone draws water at the well now and then. No stat bonuses. |
| P5 | Cost | **Goods you gather**, from small treats (a bench: some logs) to bigger goals (the fountain). |
| P6 | Pacing | **Some from the start, more with the town hall**: benches, flower boxes and the nearest road lamps at first; the well, bunting and farther roads at hall 2; the fountain and the bridge at hall 3. |
| P7 | Appearing | **A villager comes and builds it**: the nearest one walks over, hammers a few seconds, the pieces pop in with the tok, a cheer. Paid road lamps light along the road in a wave instead. |
| P8 | Scope | **Both worlds** (spots set round the village square, so a generated village has them too). **The café waits** for villager routines (chunk 8). |
| P9 | Board panel | **Pinned paper notes** in the map's parchment style: title, what it adds, cost (have / need), Pay; done ones show a tick, then come off. |
| P10 | The bridge | **Over water you'd wade**: a plank footbridge where a trail fords the river nearest the village (generated worlds); Hearthvale's spans the gully's open gap. |
| P11 | Sounds | **CC0, picked by ear** on a page (fountain, well bucket and chain, building), downloads asked first. |

## A first price list (to tune by playing)

| Project | Needs hall | Cost |
|---------|-----------|------|
| Benches round the square (2) | 1 | 10 logs |
| Flower boxes on the cottages | 1 | 8 birch, 6 wheat |
| Road lamps, per stretch (near the village) | 1 | 10 logs, 5 copper, 3 coal |
| Road lamps, per stretch (far roads) | 2 | 15 logs, 8 iron, 5 coal |
| A well in the square | 2 | 25 stone-ish: 20 copper, 15 logs |
| Bunting between the houses | 2 | 10 birch, 8 barley |
| A fountain | 3 | 30 iron, 10 gold, 20 oak |
| The mended footbridge | 3 | 30 oak, 10 iron |

(No stone item exists: rocks give copper ore. "Stone-ish" means copper until stone is a thing.)

## Phases

One commit each; phases marked **(pick)** stop for your choice.

1. **Projects as data.** A `ProjectDef` resource (id, title, a line on what it adds, cost, hall tier,
   kind: spots or a road stretch) in data/projects/; a `Projects` autoload that saves what's done
   and pays (through `Inventory`); road stretches become projects that light through `Lamps`. Debug
   menu: complete or undo any project.
2. **The noticeboard.** A board model in the square (both worlds), E opens the notes panel (P9):
   pinned notes, have / need, Pay, done notes ticked; hall-locked notes say what they wait for.
3. **Spots and models.** Village-local spot sets for each project (benches, flower boxes, well,
   bunting, fountain), the same offsets in Hearthvale and generated villages; new models in
   make_village.py (flower box, planter, well, bunting strings, fountain); a project's props appear
   when it's done, and stay after loading.
4. **The build moment.** Paying sends the nearest villager to the spot to hammer, the pieces pop in
   one by one with the tok, then a cheer; road lamps light along their stretch in a wave.
5. **A little life.** Villagers sit on the new benches at dusk; someone draws water at the well now
   and then (bucket down, up, a pause).
6. **The bridge.** Hearthvale: a plank bridge over the gully's gap. Generated worlds: the ford
   nearest the village on a trail gets a footbridge (and footsteps on planks, with the sounds).
7. **Sounds (pick).** Listening page: fountain splash bed, well bucket and chain, a building sound
   under the toks, plank footsteps. Downloads asked first.
8. **Screenshots (pick).** The square before and after every project, the board, the bridge; you
   approve the look.

## Not in this chunk

The café (chunk 8, with routines), the landslide, market stall and traders (chunk 7), the doghouse
(chunk 6), free placement of decorations (maybe later), add-ons bolted onto buildings (chunk 9).
