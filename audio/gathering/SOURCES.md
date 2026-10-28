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
| stone/[ore/]split_01-04.wav, ../stone_break.wav | a piece breaks out (first second) / the rock shatters (whole, 8 dB down after playtest) | Smashed/demolished brick wall crumbling/caving in | Squirrel_404 | https://freesound.org/people/Squirrel_404/sounds/829103/ |
| wood/[species/]creak_01-04.wav | trunk straining before the fall | knakande träd 1 (creaking tree) | Ryding | https://freesound.org/people/Ryding/sounds/94359/ |
| wood/clean_cut_01-04.wav | the last blow, clean through (the chop's hits, a touch deeper) | chopping logs with an axe | hadescolossus | https://freesound.org/people/hadescolossus/sounds/703420/ |
| wood/pull_01-04.wav | the axe worked loose (unused since playtest: a chop is the axe alone) | wood crackling-31 | wavecal22 | https://freesound.org/people/wavecal22/sounds/537459/ |
| stone/rustle_01-04.wav | raising the tool (wind-up) | Stretch - Short | NearTheAtmoshphere | https://freesound.org/people/NearTheAtmoshphere/sounds/676988/ |
| stone/pebble_01-06.wav | a chip landing | Stone dropping | alegemaate | https://freesound.org/people/alegemaate/sounds/364711/ |
| stone/[ore/]crack_01-05.wav | a crack running through the stone | crackle | stone21 | https://freesound.org/people/stone21/sounds/245659/ |
| stone/scrape_01-04.wav | the pick point dragged out (unused since playtest: out of place after the hit) | Metal Grinding 2 | qubodup | https://freesound.org/people/qubodup/sounds/743239/ |
| stone/slab_01-03.wav | an ore-wall slab sliding off and falling | rock slide | 21100495 | https://freesound.org/people/21100495/sounds/655368/ |

Every gathering sound is now a recording; `tools/synth_gathering.py` is kept only as history. **Don't
re-run it**: it would write over all of these.

**Playtest (2026-10-28): the axe's punch.** The chops and clean cuts were EQ'd for impact: +6 dB
body under ~160 Hz, a little thump round 350 Hz, the top softened above 6 kHz, the first ~20 ms
lifted, the tail cut short (0.4 s; clean cuts 0.6 s), every chop's hit levelled to -15 dBFS RMS.
Chops 03 and 07 and clean cut 03 (all hiss, no body) were dropped, then 04 and 08 (muffled: nothing
above 800 Hz); 01 and 05 got more body and 02 and 06 a little bite, so every chop is one kind of hit. The axe's wind-up and whoosh
play quieter than the pickaxe's (audio/woodcutting/axe_swing.tres, axe_windup.tres).
