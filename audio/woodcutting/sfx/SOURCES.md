# Woodcutting sound effects: sources

All synthesized by `tools/synth_wood_sounds.py` (`python tools/synth_wood_sounds.py`), no
recordings. Rerunning it rewrites every clip here and the randomizer `.tres` for each layer; the
layered stacks in `audio/woodcutting/` (volumes, delays, pitch) are hand-written and stay as they are.

| Clips | How it's made | Used in |
|---|---|---|
| `chop_thunk_*` | six low wooden resonances ringing down fast, a knock, a few fibre snaps | `axe_hit` |
| `chop_bite_*` | a short bright noise burst and two high rings: the edge going in | `axe_hit`, `axe_pull` |
| `clean_crack_*` | a hard broadband snap, then a quick run of smaller snaps, the trunk ringing | `clean_cut` (and, deeper, the hinge giving way) |
| `chip_scatter_*` | small chips landing and bouncing: high wooden ticks, each bounce quicker and quieter | `axe_hit`, `axe_pull` |
| `trunk_creak_*` | stick-slip friction (the wood grabbing and slipping 16–48 times a second, ringing three low resonances each time) | `trunk_creak` |
| `fibre_tear_*` | a crackle that thickens then thins out, over a slow groan | `tree_fall` |
| `crown_rush_*` | air and rustling leaves swelling as the crown falls, twigs snapping | `tree_fall` |
| `land_slump_*` | a heavy wooden thud and two bounces, leaves crashing, a few twigs | `tree_land` |
| `land_boom_*` | a deep thump under it | `tree_land` |
