# Procedural generation, part 2: variety

Agreed on 2026-10-18, after the first pass ([procgen.md](procgen.md)). On the `procgen` branch, one
commit per phase. Every seed still has every biome, since progression needs them all. Variety comes
from what each biome is like, where things sit, and what turns up between them.

## Decisions

| Question | Answer |
|---|---|
| Which biomes | **All of them, every seed**, plus a new one: **Hearthvale**, the village |
| Where the village goes | **Inner ring**, next to the hub, joined by a trail (the hub stays a quiet clearing) |
| Biome variations | **2–3 named kinds per biome**, rolled per seed. A kind changes the ground's shape, the scenery and the node mix, and its name goes on the arrival card ("The Pinewood · Birch Grove") |
| Start | The hub (and the ring round it) sits **off-centre** |
| Water | **Rivers** from the mountains to the lake; **island lakes** (a Stillwater kind) |
| Mountains | A **second peak** (a Frostpeak kind, Twin Peaks) |
| Between biomes | **Ruins**, **rare spots** and **abandoned camps** |
| Resources | **One rich, one lean** resource per seed (×2 and ×½, nothing removed), shown in the debug menu and the preview |

## Biome kinds

| Biome | Kinds |
|---|---|
| The Clearing (hub) | Meadow (open, gentle), Hollow (hills rise close and steep round it) |
| The Pinewood | Pine Forest (dense pines), Birch Grove (light, birch-heavy), Old Growth (tall canopies, steep ground, more pine nodes) |
| Goldmeadow | Grainfields (wheat and barley), Orchard Downs (oaks and flowers, fewer crops), Rolling Downs (big swells) |
| Stillwater | Great Lake (one big lake), Marsh (a cluster of small ponds and reeds), Island Lake (a lake with an island in it) |
| Greystone Quarry | Terraced Pit (three wide levels), Deep Pit (four narrower levels), Broken Pit (three levels, a boulder field round it) |
| Frostpeak | Lone Peak, Twin Peaks (two summits and a saddle), Ridge (a long spine) |
| Hearthvale | Valley Village, Lakeside Village (a village pond by the square) |

## Terms

- **Kind**: one named variation of a biome. The seed rolls one per biome.
- **Stamp**: a designed height shape pressed into the heightmap (a village's flat ground, an island).
- **Landmark**: a one-off place built from existing models (ruins, a camp) or a special cluster of
  nodes (a rare spot).
- **Rich / lean**: the seed's favoured and scarce resource. Spawner weights and counts for that
  item are doubled or halved.

## Phases

1. **Biome kinds and an off-centre hub** ✅: the kind table, rolled per seed; each kind's height
   profile, scenery and node mix; Twin Peaks, Ridge, Marsh, Island Lake and the quarry kinds as
   shapes; the kind on the arrival card; the hub moved off the map's centre.
2. **Hearthvale** ✅: a village biome on the inner ring. A flattened valley, a square and lanes, the
   six village buildings with their villagers, upgrades saved with the seed, and lamps and benches.
3. **Rivers** ✅: a channel from the rim down to the lake, carved to the water line, its water built
   in segments, trails fording it.
4. **Landmarks** ✅: ruins (the parkour blocks as a broken tower or wall, a reward on top), rare spots
   (a crystal outcrop, a gold vein, a pike pond, an ancient oak stand, a flower meadow; 1–3 per
   seed) and an abandoned camp or two (cart, hay, log pile, crates).
5. **Rich and lean seeds** ✅: one resource doubled, one halved; shown in the debug menu's Procgen tab
   and the preview tool's output.
6. **Wrap-up**: README, TODO, screenshots.

## Verifying

As before: `tools/procgen_preview.gd` across several seeds for layout, and a throwaway in-game shot
script with `user://save.json` backed up and restored around it.
