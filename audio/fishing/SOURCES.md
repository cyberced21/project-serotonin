# Fishing sound sources

Picked by ear on the fishing page (plans/cozy-sound.md, phase 6). **CC0** Freesound recordings
(128 kbps previews) written over the synthesized clips in place, each matched to the loudness of
the clip it replaced, so the `*.tres` randomizers and the mix are unchanged.

| Files | Sound | Recording | Author | Source |
|-------|-------|-----------|--------|--------|
| cast_whip_01-04.wav | the cast | Casting Fishing Rod for Game Fishing SFX | el_boss | https://freesound.org/people/el_boss/sounds/853287/ |
| plip/plop/splosh_01-04.wav | the float landing (perfect: smaller, bad: bigger) | Water drop / Splash | bxyorna | https://freesound.org/people/bxyorna/sounds/410335/ |
| nibble_01-04.wav, tap_01-04.wav | nibbles, then firmer taps (a touch lower) | Water Drops | ReiyaManor | https://freesound.org/people/ReiyaManor/sounds/351623/ |
| flop_01-04.wav | the fish flopping on the bank | fish slap ground or snow writhing wet | kyles | https://freesound.org/people/kyles/sounds/450830/ |

The take (bloop, hooked), yank, spook, spear hit, rod creak/jerk and line snap are still
synthesized by `tools/synth_fishing.py`; don't re-run it without excluding the files above.
