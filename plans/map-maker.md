# The map maker: new maps from scratch

Asked 2026-11-03: the map editor ([map-editor.md](map-editor.md), [map-editor-places.md](map-editor-places.md),
[terrain-editing.md](terrain-editing.md)) edits Hearthvale, but the world's big pieces are fixed in code
(`scripts/world_map.gd`): the map's size (768 m square), where the Pinewood, Greystone Quarry, Goldmeadow,
Frostpeak, the lake, the clearing and the village bowl sit and how big they are, the creek, and the main
roads. The goal: start a blank map of any size and lay out a whole new world in the editor, by
placing the areas, drawing the roads and naming places.

## Picked (2026-11-03)

- **Several maps, one played:** the editor gets New map / Open map. Each map is its own set of files;
  one is marked as the map the game plays. Hearthvale stays exactly as it is until you switch.
- **Width x depth:** each a multiple of 256 m (the land's tiles), set when the map is made.
- **Areas bring their land, name and starter nodes:** dropping the quarry digs its stepped pit,
  names it on the map, gives it its mood and music, and adds its usual rock patches (editable after).
  Same for the Pinewood (forest floor + trees), Goldmeadow (plain + fields), Frostpeak, the lake,
  the clearing. Areas move, turn and resize. One of each kind.
- **Roads route between clicked points:** click a start, any in-between points, an end; the
  generator finds a gentle way over the hills between them (as it does now). Shift: pin the exact line.
  Every road becomes drawn and editable, the ones fixed in code today too.
- **(Decided while planning)** The village is an area too: placing it brings the whole street
  (buildings, green, walkways, plots), and moving it carries them. The mill, orchard, shepherd's
  hill and haven stay single places you drag. Anything a map hasn't placed is kept out of the game.

## Where things live

- `data/maps.json`: the maps (`{id, name, layout, ...their files}`) and which one is `active`.
  Hearthvale keeps today's paths (`data/layout/hearthvale.json`, `terrain_data/`, `scenes/layout.tscn`,
  ...) so nothing moves; a new map's files are under `data/maps/<id>/`.
- `Maps` (`scripts/maps.gd`, static): the active map and its paths, read by the game and every tool.
- A layout gains `world: {size: [w, d], origin: [x, z]}`, `areas: [...]`, and its roads as terrain lines.

## Phases

One commit a phase, on branch `mapmaker` (worktree `../project-serotonin-mapmaker`). Hearthvale's
land must come out the same after each phase (its heights and ground ids hashed before and after).

1. **Maps:** `data/maps.json`, `Maps`, the game and tools reading paths from it; the server's
   list / new / open / play APIs; the editor's map menu and a New map dialog (name, width, depth).
2. **Any size:** the generator, map export, the editor and the game's map work from the map's size
   and origin; a blank map generates as open rolling hills rising at its edges.
3. **Roads drawn:** `WorldMap.ROADS` (and the street, the road east, the clearing path) move into
   Hearthvale's layout as road/path lines; the road tool takes waypoints (routed) or a pinned line,
   and a road can start on another.
4. **Areas as data:** `areas` in the layout; WorldMap's place constants become reads of them (Hearthvale's
   written to match); the generator, Biome, the mine, home and the map export use them; no area,
   nothing of it. The creek becomes Hearthvale's `creek` river line.
5. **Areas in the editor:** an Areas tool to place one from a palette, move, turn and resize it; their
   names on the editor's map and the game's map; free name labels.
6. **What comes with an area:** its starter patches (templates in the catalog) placed with it and
   carried when it moves; the village carrying its buildings, walkways and plots; unplaced
   buildings and places kept out of the game.
7. **Checked:** the tests, the audit, Hearthvale unchanged, and a new blank map built start to finish.

## As built

(filled in as the phases land)
