# Kit sources

`village/` holds pieces of the **Medieval Village MegaKit** (Standard, free) by Quaternius,
CC0 1.0 (public domain, no credit needed): https://quaternius.com/packs/medievalvillagemegakit.html
(downloaded from https://opengameart.org/content/medieval-village-megakit on 2026-10-29).

Only the pieces `tools/blender/kit_buildings.py` uses are copied, by `tools/import_kit.py`, with
their textures converted to JPEG. Godot ignores this folder (`.gdignore`): the game loads the
buildings exported from it, in `models/village/` (textures in `models/village/textures/`).

`props/` holds all 94 pieces of the **Fantasy Props MegaKit** (Standard, free), same author and
licence: https://quaternius.com/packs/fantasypropsmegakit.html (downloaded from
https://opengameart.org/content/fantasy-props-megakit on 2026-10-29), textures shrunk to 1024 px
JPEGs. Furniture and things for the interiors, in their own colours (plans/home.md).
