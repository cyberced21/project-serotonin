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

## The work yards' packs (plans/village-street.md)

Not copied here either: `tools/blender/yard_kit.py` reads them from where they were unzipped
(`E:\Godot\downloads\street-props\`, downloaded 2026-11-01) and writes the picked pieces to
`models/village/yard/`, one .glb each, in their own painted materials (textures 512 px JPEGs).

- **Survival Kit** by Kenney, CC0 1.0: https://www.kenney.nl/assets/survival-kit
  (`kenney_survival-kit.zip`, unzipped as `kenney/`). The firewood. A third of real size.
- **Resource Bits** (free) by Kay Lousberg, CC0 1.0: https://kaylousberg.itch.io/resource-bits
  (`KayKit_ResourceBits_1.0_FREE.zip`, unzipped as `kaykit/`). The chopping log, woodpile, ore heap.
- **Modular Wooden Docks** by loafbrr, CC0 1.0: https://loafbrr.itch.io/wooden-docks
  (`WoodenDock_blend_glb_Fbx.zip`, unzipped as `docks/`; read from `WoodenDockSet_Final.blend`,
  whose glb has no textures). The jetty deck, fish-drying rack, gutting table, a fish.

The rest of the yards' pieces are Fantasy Props (`props/` above); the forge is ours.
