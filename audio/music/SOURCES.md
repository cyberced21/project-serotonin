# Music sources

Every track here is **CC0** (public domain): no credit required. Picked 2026-10-27 from the
shortlist page (plans/cozy-sound.md, phase 2). The files are OpenGameArt's own preview copies
(Ogg Vorbis, about 112 kbps), except Deep Humidity (the original file); the originals on each
page can replace them if higher quality is wanted.

| File | Title | Author | Slot | Source |
|------|-------|--------|------|--------|
| sunset_plains.ogg | Sunset Plains | Yoiyami | morning | https://opengameart.org/content/sunset-plains |
| harvest.ogg | Medieval: Harvest Season | RandomMind | day | https://opengameart.org/content/medieval-harvest-season |
| new_town.ogg | A New Town (RPG Theme) | cynicmusic | evening | https://opengameart.org/content/a-new-town-rpg-theme |
| another_august.ogg | Another August | cynicmusic | night | https://opengameart.org/content/another-august |
| town3.ogg | Town 3 | Pro Sensory (Alex McCulloch) | village | https://opengameart.org/content/town-3 |
| forest_amb.ogg | Forest Ambience | TinyWorlds | forest | https://opengameart.org/content/forest-ambience |
| first_light.ogg | First Light Particles | Yoiyami | lake | https://opengameart.org/content/first-light-particles-%E2%80%93-cc0-atmospheric-pianoambient-track |
| deep_humidity.ogg | Deep Humidity | TinyWorlds | mine | https://opengameart.org/content/deep-humidity |
| just_you.ogg | Just you and me | Pro Sensory (Alex McCulloch) | main menu | https://opengameart.org/content/just-you-and-me-guitar |
| tower_inn.ogg | Medieval: The Old Tower Inn | RandomMind | tavern (later) | https://opengameart.org/content/medieval-the-old-tower-inn |

cynicmusic asks for a credit to The Cynic Project and Alex McCulloch appreciates one; neither is
required by the licence, but a credits line would be a kind touch.

Levels: `tools/measure_music.gd` measures each file; the trims in `data/music/library.tres` bring
them to about -20 dB RMS without peaks passing -1 dB.
