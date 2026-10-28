# Interface sound sources

Picked by ear on the UI page (plans/cozy-sound.md, phase 7). **CC0** Freesound recordings (128 kbps
previews), wood and paper. Played by `Sfx.play_ui(id)`: every button clicks and every tab bar turns
a page on its own (`Sfx._on_node_added`, not the debug menu's); the villager panel and the world map
play open / close. Levels: all at the old pickup's loudness, each one's volume set in `Sfx.UI`.

| File | Sound | Recording | Author | Source |
|------|-------|-----------|--------|--------|
| click.wav | any button | User Interface Elegant Wooden Confirmation Sound | qubodup | https://freesound.org/people/qubodup/sounds/822568/ |
| open.wav | a villager's panel opens | Book_open | envirOmaniac2 | https://freesound.org/people/envirOmaniac2/sounds/393844/ |
| close.wav | the panel closes | bkClose | tia666 | https://freesound.org/people/tia666/sounds/156927/ |
| page.wav | a tab clicked (pause menu, skills, settings) | turnPage | partheeban | https://freesound.org/people/partheeban/sounds/457767/ |
| map.wav | the world map opens (and folds away, a touch lower) | Unfold a map | Breviceps | https://freesound.org/people/Breviceps/sounds/447931/ |
| tok.wav | each building piece popping in during an upgrade (pitch rises per piece) | Wood Knock | Mrguff | https://freesound.org/people/Mrguff/sounds/369710/ |
| ../pickup_01-03.wav | an item flying into your pack (pitch rises on quick combos) | ItemPickup | nicholasdaryl | https://freesound.org/people/nicholasdaryl/sounds/563465/ |
