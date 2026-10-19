# Terrain detail: notes for later

Status: steps 1 and 4 done by the graphics overhaul (branch `graphics`, plans/graphics.md):
the terrain is smooth and textured (`shaders/terrain.gdshader`). Steps 2 and 3 not started.

## The problem

After playtesting, the terrain feels rough: too low poly, not enough detail, and
no real way to sculpt by hand.

## Decision: keep Terrain3D

We looked at the alternatives and the goal is **detailed rolling ground**, which
Terrain3D can do. Most of the roughness comes from how we set it up, not from the
plugin itself.

- **Low-poly look** (fixed): the old faceted `terrain_lowpoly.gdshader` is now
  `shaders/terrain.gdshader`, smooth and textured.
- **Coarse geometry**: the Terrain3D node uses the default `vertex_spacing` of
  1 m per vertex.
- **No sculpting**: Terrain3D has editor brushes (raise/lower, smooth, flatten,
  slope, height, holes, paint). But `tools/generate_test_terrain.gd` rebuilds the
  whole heightmap from noise, so re-running it wipes anything sculpted by hand.

## Plan (one commit per step, so each can be checked in the editor)

1. **Smooth shading.** Turn off the low-poly shader override and go back to
   Terrain3D's default shader. Bring back our sand/grass colouring (the
   `sand_height` param and friends), either by porting it or by setting up
   texture layers.
2. **More vertices.** Try `vertex_spacing = 0.5`. Spacing probably changes the
   terrain's size in world metres, so adjust the generator to keep biome
   positions (`WorldMap.*_CENTER`, pond, field, quarry, ring road) where they
   are. Then check the scripts that ask Terrain3D for heights: `road_course.gd`,
   `scenery_scatter.gd`, `node_spawner.gd`, `pond_dressing.gd`, `water_body.gd`,
   `villager.gd`, `prop.gd`, `footsteps.gd`.
3. **Sculpting workflow.** Make the generator a one-time base layer, then
   sculpt by hand in the editor. Add a guard so it can't be re-run by accident
   and overwrite the sculpted terrain. (Alternative, more work: the generator
   keeps running and a hand-sculpted layer is blended on top.)
4. **Detail without polygons.** Add detail normal maps and textures to the
   terrain texture layers.

Watch out for Terrain3D's `materials/terrain_assets.tres` filling up when the
editor re-saves it. Discard that bloat; don't commit it.

## Alternatives considered (not pursuing)

- **Outside heightmap tools** (Gaea, World Machine, World Creator, Blender):
  still an option on top of Terrain3D. Design the terrain there, import it with
  Terrain3D's importer, then touch it up. Good if we want erosion and natural
  river valleys.
- **HTerrain** (Zylann): similar heightmap plugin, written in GDScript, slower
  and less maintained. Switching means rewriting every terrain lookup for
  little gain.
- **Hand-made Blender mesh**: full control, but no LOD, no painting in the
  editor, and collision and the scatter/road scripts would need reworking.
- **Voxel Tools** (Zylann `godot_voxel`): caves, overhangs, runtime digging,
  node-based generator graph. Overkill for rolling ground; its editor sculpting
  is weak and we'd write our own texturing shader. Revisit only if we want caves
  or overhangs. A cheaper version of that idea is to keep Terrain3D and add
  hand-made meshes for the odd cave mouth or overhang.
