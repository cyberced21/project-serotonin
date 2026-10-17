# Woodcutting sound effects: sources

Cut from the **Sonniss GDC 2026 Game Audio Bundle** with `tools/cut_sounds.py ... woodcutting` (which
lists exactly which file each clip comes from and how it's cut). Licence: royalty free for use in
games, commercial included, no attribution required; the raw files may not be redistributed, so only
these processed clips are in the project. To recut them, download the bundle and see the top of
`tools/cut_sounds.py`.

The bundle has no forestry pack, so these are the woodiest sounds in it. They're placeholders until
a real wood / foley library replaces them: repoint the `WOOD_RECIPES` in `tools/cut_sounds.py` and
recut, and the stacks in `audio/woodcutting/` pick the new clips up.

| Clips | Source (library — file) | Used as |
|---|---|---|
| `chop_thunk_*` | 344 Audio, Haunting Ambiences Vol. 3 — Wooden Hit, Dark, Heavy Hit | the axe's thunk into the trunk |
| `chop_bite_*` | 344 Audio, Historical Weapons Vol. 2 — Spear And Stick Impact, Wooden | the edge's knock, and the yank |
| `clean_crack_*` | David Dumais Audio, Melee Weapons 2 — Whip Snap Crack 05 | a clean cut's snap; the hinge giving way |
| `chip_scatter_*` | Epic Stock Media, Board Game — Organic Multiple Pieces Wood Small | chips skittering off |
| `trunk_creak_*` | 344 Audio, Cinema Experience Vol. 1 — Sitting Down, Creaky Seat | the trunk creaking as it sways |
| `fibre_tear_*` | Ivo Vicic, Campfire — Dropping Fresh Pine Branches in Fire, Crackling | the last fibres tearing as it goes |
| `crown_rush_*` | Epic Stock Media, Public Spaces — Strong Wind On Trees Foliage | the crown rushing down |
| `land_slump_*` | 344 Audio, Antique Books — Pile Of Antique Books Falling Over | the trunk slumping onto the ground |
| `land_boom_*` | Federico Soler, Effective Trailer Booms Vol. 2 — 011 | the low thud under it |
