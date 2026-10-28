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
| bloop_01-04.wav, hooked_01-04.wav | the take (float pulled under), and the strike moment (a touch lower) | Pebbles into a pond | HenKonen | https://freesound.org/people/HenKonen/sounds/682165/ |
| yank_01-04.wav | the yank that lands the fish | Medium Splash 1 | timgormly | https://freesound.org/people/timgormly/sounds/148317/ |
| spook_01-04.wav | a fish bolting | Stick Splashing Water Around | jc144940 | https://freesound.org/people/jc144940/sounds/178730/ |
| spear_hit_01-04.wav | the spear into the water | Splash 1 | lurpsis | https://freesound.org/people/lurpsis/sounds/444017/ |
| creak_01-04.wav, jerk_01-04.wav | the rod loading up, and its tip jerking (a touch higher) | Wood Creak Single V10 | Rudmer_Rotteveel | https://freesound.org/people/Rudmer_Rotteveel/sounds/506665/ |
| snap_01-04.wav | the line breaking | Rubber Band Snap | baidonovan | https://freesound.org/people/baidonovan/sounds/187354/ |

Every fishing sound in use is now a recording. The unused clips from the old fight (reel, hiss,
bulge, strain, thrash, hoist, jump) are still synthesized; nothing plays them. Don't re-run
`tools/synth_fishing.py`: it would write over the recordings.
