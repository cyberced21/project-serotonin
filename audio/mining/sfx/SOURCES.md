# Mining sound effects: sources

Cut from the **Sonniss GDC 2026 Game Audio Bundle** with `tools/cut_sounds.py` (which lists exactly
which file each clip comes from and how it's cut). Licence: royalty free for use in games, commercial
included, no attribution required; the raw files may not be redistributed, so only these processed
clips are in the project. To recut them, download the bundle and see the top of `tools/cut_sounds.py`.

| Clips | Source (library — file) |
|---|---|
| `hit_crack_*` | Alexander Kopeikin, 100 kHz Designed Ice — ice, crack, ice block snapping |
| `hit_tink_*` | InMotionAudio, Sinister Textures 5 — Concrete MetalPipe 02 |
| `hit_thump_*` | 344 Audio, Cinematic Fight Vol. 1 — 4 x Punch, Body 02 |
| `hit_gravel_*` | 344 Audio, Cinema Experience Vol. 1 — Broom Sweeping Up Snacks On Hard Floor 2 |
| `pull_scrape_*` | InMotionAudio, Sinister Textures 5 — Cladding Scratch 06 |
| `pull_pebbles_*` | Epic Stock Media, Board Game — Board Reset Organic Multiple Pieces Wood Small 02 |
| `swing_whoosh_*` | David Dumais Audio, Melee Weapons Pack 2 — Swing Impacts Quick Heavy Weapon Swing To Thud (the swing before each impact) |
| `windup_creak_*` | InMotionAudio, Foley T-Shirt — Cloth Movement 29 |
| `crack_split_*` | Alexander Kopeikin, 100 kHz Designed Ice — ice, surface cracking, fissure, fast, hard |
| `split_crunch_*` | Epic Stock Media, Halloween Game — Gore Designed Transient Heavy Impact Smash 01 |
| `split_rubble_*` | Cinematic Sound Design, Colossal Impacts — Woosh Debris |
| `debris_tick_*` | Epic Stock Media, Board Game — Piece Action Connect Dots Fall Bounce 04 |

One source per layer, every clip brought to the same loudness (its loudest 50 ms). Each
`<layer>.tres` is a randomizer over that layer's clips; the layer stacks in `audio/mining/`
(`pickaxe_hit.tres` and the rest) set each layer's timing, volume and pitch.

Check the mix without listening: `blender -b -P tools/measure_mix.py --` mixes every event many
times and reports how loud each comes out and how much that varies.
