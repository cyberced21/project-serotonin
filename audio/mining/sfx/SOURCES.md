# Mining sound effects: sources

All synthesized by `tools/synth_mining_sounds.py` (`python tools/synth_mining_sounds.py`), no
recordings. (They used to be cut from the Sonniss GDC 2026 bundle by `tools/cut_sounds.py`, which
is kept but no longer used.) Rerunning it rewrites every clip here and the randomizer `.tres` for each
layer; the layered stacks in `audio/mining/` (volumes, delays, pitch) are hand-written and stay as
they are. Every clip is brought to the same loudness (its loudest 50 ms).

| Clips | How it's made | Used in |
|---|---|---|
| `hit_crack_*` | a hard bright crack, a stiff stone knock and a few snaps | `pickaxe_hit`, `split` |
| `hit_tink_*` | the steel pick ringing (three inharmonic modes) over the rock's own ring, kept 180 Hz clear of each other so they don't beat | `pickaxe_hit` |
| `hit_thump_*` | four low stone resonances dying almost at once, a low knock, a little grit | `pickaxe_hit` |
| `hit_gravel_*` | grit and chips pattering down, thinning out, a few bigger chips knocking | `pickaxe_hit`, `crack_tip` |
| `pull_scrape_*` | steel grinding on stone, catching at uneven moments | `pickaxe_pull` |
| `pull_pebbles_*` | a few pebbles knocked loose, rolling off | `pickaxe_pull` |
| `swing_whoosh_*` | noise whose band sweeps up to the swing's fastest moment and down | `pickaxe_swing` |
| `windup_creak_*` | a soft rustle of sleeves, the leather grip giving | `pickaxe_windup` |
| `crack_split_*` | snaps coming faster as a crack races along, ringing off the fresh faces | `crack_tip` |
| `split_crunch_*` | a heavy grinding crunch over the body's low thud, a spray of snaps | `split` |
| `split_rubble_*` | the piece tumbling down in a few knocks, grit settling | `split` |
| `debris_tick_*` | one chip landing: a tiny high tick | `debris_stone` |

**Per ore.** The layers that are the rock's own body (`hit_tink`, `hit_thump`, `crack_split`,
`split_crunch`) are baked again in a voice per ore, into `iron/`, `coal/`, `gold/` and `crystal/`,
with each ore's copies of `pickaxe_hit`, `crack_tip` and `split` in `audio/mining/<ore>/`: iron's
basalt rings harder and longer, coal is dull and crumbly, gold's quartz rim rings bright, crystal
chimes. Copper (the plain rock) plays the base layers.

Check the mix without listening: `blender -b -P tools/measure_mix.py --` mixes every event many
times and reports how loud each comes out and how much that varies.
