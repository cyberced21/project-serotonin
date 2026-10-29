# Kit sources

`village/` holds pieces of the **Medieval Village MegaKit** (Standard, free) by Quaternius,
CC0 1.0 (public domain, no credit needed): https://quaternius.com/packs/medievalvillagemegakit.html
(downloaded from https://opengameart.org/content/medieval-village-megakit on 2026-10-29).

Only the pieces `tools/blender/kit_buildings.py` uses are copied, by `tools/import_kit.py`, with
their textures converted to JPEG. Godot ignores this folder (`.gdignore`): the game loads the
buildings exported from it, in `models/village/` (textures in `models/village/textures/`).

The **Fantasy Props MegaKit** (Standard, same author and licence) is picked for the interiors
(plans/home.md); its pieces come in with the interiors phase.
