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

## The mine's packs (plans/mine.md)

Not copied here (13 MB and 16 MB as downloaded): `tools/blender/mine_kit.py` reads them from
wherever they were unzipped and writes the picked pieces to `models/mine/`, one .glb each.

- **Mine Object collection** by loafbrr_1, CC0 1.0:
  https://opengameart.org/content/mine-object-collection (`mines_asset_fbx_gltf_blend.zip`,
  unzipped as `loaf/`, downloaded 2026-10-29). Rails, carts, stone pillars, posts, tools; kept in
  their own painted materials.
- **free mine assets pack** by rubberduck, CC0 1.0:
  https://opengameart.org/content/free-mine-assets-pack (`free_mine_assets.zip`, unzipped as
  `duck/`, downloaded 2026-10-29). Timber frames, hanging lamps, rocks, stalactites; painted from
  our palette.
