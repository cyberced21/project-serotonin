# Gathering sound sources

Picked by ear on the gathering page (plans/cozy-sound.md, phase 5). These **CC0** Freesound
recordings (128 kbps previews) replace the synthesized clips in place, matched to the loudness of
the clip each one replaced, so the playlists (`*.tres`) and the mix are unchanged. Species voices
(oak, birch, pine) and ore voices (iron, coal, gold, crystal) are the same recording resampled
slightly lower or higher.

| Files | Sound | Recording | Author | Source |
|-------|-------|-----------|--------|--------|
| wood/[species/]chop_01-08.wav | axe chop | chopping logs with an axe | hadescolossus | https://freesound.org/people/hadescolossus/sounds/703420/ |
| wood/fall_01-02.wav, wood/[species/]land_01-03.wav | tree falls, then lands (one recording split at the crash) | timber tree falling 1 | matt_beer | https://freesound.org/people/matt_beer/sounds/515313/ |
| stone/whoosh_01-06.wav | tool swing (axe and pickaxe) | SWOSH-01 44.1kHz | qubodup | https://freesound.org/people/qubodup/sounds/59988/ |
| stone/[ore/]mine_01-08.wav | pickaxe hit: stone crunch... | Foley_Impact_Stones_Strong_Debris | Nox_Sound | https://freesound.org/people/Nox_Sound/sounds/554148/ |
| (same files) | ...with a clink on top (3 dB under; louder on iron, gold, crystal, quieter on coal) | Clink2 | BMacZero | https://freesound.org/people/BMacZero/sounds/96135/ |
| stone/[ore/]split_01-04.wav, ../stone_break.wav | a piece breaks out (first second) / the rock shatters (whole) | Smashed/demolished brick wall crumbling/caving in | Squirrel_404 | https://freesound.org/people/Squirrel_404/sounds/829103/ |

Everything else in this folder is still synthesized by `tools/synth_gathering.py`. **Don't re-run
that script without excluding these files**: it would write over them.
