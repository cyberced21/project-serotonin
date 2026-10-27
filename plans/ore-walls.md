# Ore walls: quarry faces you excavate over time

## Why

Ore rocks are one-off nodes: walk up, break, walk on. The break-where-struck tech (Voronoi pieces,
adjacency, one merged mesh with a bit mask) can carry something bigger: a quarry whose walls are
solid rock threaded with ore veins, dug back layer by layer over many visits until the pit is
a row of carved, roofed cave mouths the player made. Tunnels come later, building on this.

## Decisions (grilled 2026-10-26)

1. **Alongside ore rocks.** Overworld ore rocks, tool gates and themed nodes stay. The walls are
   the quarry's thing.
2. **Permanent, in layers.** Dug pieces stay gone (saved). A cleared layer exposes the next one.
3. **Veins to follow.** Ore runs as 3D seams through pieces *and* layers. What shows on the face
   continues behind it, so the player reads the face and digs along a seam.
4. **Tool gating per piece.** Stone pieces break with any pick. A vein piece needs its ore's tier
   (Tools.LADDER), and a weaker pick deflects with the usual red "needs X". Exposing a vein you
   can't take yet is the intended tease.
5. **Grain and pace.** Pieces 0.3–0.5 m. Panels about 3 m wide. Each layer is 0.5 m deep and has
   ≤ 96 pieces, which fits today's `pieces_gone` mask. A biting hit knocks 1–3 pieces, so a layer
   takes about 40–60 swings.
6. **Support.** The rock behind holds every piece (no collapse by default, so digging stays clean).
   Each layer has a few **loose slabs**, marked by a dark crack like ore faults. Undercut one or
   strike its crack and the whole cluster drops at once. No player damage.
7. **Real depth, 8 layers (4 m).** At build time the terrain behind each panel is cut back 4 m and
   the gap is filled with the layer stack. Ore table by layer: stone/copper near the face, iron,
   then crystal, gold at the back. After layer 8 the panel is down to **bedrock**: done for good.
8. **Roofed cave mouths.** The top ~1 m of each panel is unbreakable cap rock, and the upper
   terrace stays walkable over it. Terrain3D punches a hole in the heightmap over the alcove's
   footprint; the cap mesh is the ground above, and a floor slab mesh is the ground below (a
   heightmap holds one height per point, so both have to be meshes).
9. **Pillars.** An unbreakable ~1 m rock pillar between panels (room-and-pillar). Each alcove is
   its own room, and nothing digs sideways.
10. **Yield.** 1 ore per vein piece. Stone pieces drop stone 1 time in 4. A slab pays its whole
    contents. About 10–15 ore per layer, a little ahead of rocks per minute. XP per piece as with
    rocks, weighted by ore.
11. **Generation.** Blender (`make_models.py`) bakes ~4 panel templates: 8 layers of Voronoi cells
    each, with `.pieces.json`-style adjacency. At world build each panel picks a template and the
    game threads veins through it from the world seed. A small per-panel data texture tells the
    shader which piece holds which ore. A handful of meshes, every panel unique.
12. **Rings.** The ore table shifts by ring: the top ring is mostly stone/copper, the middle brings
    iron forward, the bottom ring puts crystal/gold in reach. The scattered ore rocks leave the
    quarry terraces; the regrowing crystal clusters stay on the pit floor.
13. **Where.** Both quarries, from one placer: hand-built Greystone (world_map.gd) first, then the
    procgen pit's three kinds (QUARRY_KIND_WALLS). The placer walks each ring wall, skips the
    haul-road ramp stretches, and lays panel / pillar / panel.
14. **Light.** Each alcove gets an automatic warm fill light that grows as it deepens, and vein
    pieces glint so seams read in the gloom. Placeable lanterns wait for tunnels.

Defaults taken without asking: hit / deflect / spark sounds reuse the synthesized rock set; a new
synthesized slab rumble (synth_gathering.py); debris thrown and faded as today (DEBRIS_LIFETIME).

## Shape of the code

- New `OreWall` (scenes/ore_wall.tscn, scripts/ore_wall.gd): one panel holds its layer stack,
  cap, pillar half and floor slab. It draws only the face layer and the one behind it.
- The breaking-where-struck code in resource_node.gd (pieces, links, mask, knock, throw, spill)
  is pulled into a shared helper both use, so ResourceNode doesn't grow and rocks keep working
  unchanged. Back-anchored support is a rule flag next to today's grounded support.
- Save: per panel id → `{layer, gone: 96-bit mask}`. About 100 panels at Greystone: tiny.
- Collision: boxes for the remaining face-layer pieces plus a back plane (the next layer), refit
  on change.

## Phases (commit each)

1. **One panel, one layer, stone only.** Bake a template layer in make_models.py. OreWall with
   back-anchored pieces, hits, knock, debris. Hand-placed in a test scene;
   `tools/wall_closeup.gd` for screenshots.
2. **Veins.** Seeded 3D vein field → per-piece ore ids → data texture → shader. Per-piece tier
   gating with deflect, drops, XP.
3. **Layers, cap, pillars, bedrock, save.** The 8-layer stack, advancing on clear; cap rock,
   pillar and floor meshes; save/load round-trip test (headless, `--save-root=user://tmp`).
4. **Loose slabs.** Marked crack clusters, undercut/crack trigger, cluster drop, rumble sound.
5. **Placer on Greystone.** Walk the rings, skip ramps, cut terrain back + holes, ring ore tables,
   clear ore rocks off the terraces.
6. **Light.** Depth-driven alcove fill light, vein glint.
7. **Procgen pit.** The same placer for terraced / deep / broken pits, saved in the world's file.
8. **Tour + polish.** Graphics-tour stop, screenshots, docs/TODO.md items.

## Later

Tunnels: an alcove's back opens into a drift you keep digging (needs a different support rule,
lanterns, and darkness as a mechanic).
