"""Renders a village building, every tier, outside and cut away (plans/home.md): Eevee, a warm sun,
kit pieces in their own materials and our pieces in the palette.

    blender -b -P tools/blender/render_building.py -- models/village/baker_cottage.gltf art/palette.png OUT_DIR [addon ...]

Writes OUT_DIR/<name>_t<tier>_out.png (front-left, outside) and _t<tier>_cut.png (roof and the front
half lifted off, looking in from above). Add-ons named after OUT_DIR (AddonDef ids) are shown
with every tier (their pieces are "AO-<id>_..."), and the files get "_<ids>" on the end.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
MODEL, PALETTE, OUT = argv[0], argv[1], argv[2]
ADDONS = argv[3:]
NAME = os.path.splitext(os.path.basename(MODEL))[0] + "".join("_" + a for a in ADDONS)
os.makedirs(OUT, exist_ok=True)


def scene_setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1100
    scene.render.resolution_y = 800
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.68, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.data.color = (1.0, 0.9, 0.78)
    sun.data.angle = math.radians(6)
    sun.rotation_euler = (math.radians(48), math.radians(8), math.radians(-30))
    scene.collection.objects.link(sun)
    bpy.ops.mesh.primitive_plane_add(size=80)
    g = bpy.data.materials.new("Ground")
    g.use_nodes = True
    g.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.3, 0.12, 1)
    bpy.context.object.data.materials.append(g)
    return scene


def palette_material():
    mat = bpy.data.materials.new("Palette")
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.abspath(PALETTE), check_existing=True)
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    return mat


def camera(scene, center, size, view, lens=35):
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = center + view.normalized() * size
    cam.rotation_euler = (-view).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    return cam


scene = scene_setup()
bpy.ops.import_scene.gltf(filepath=os.path.abspath(MODEL))
pal = palette_material()
meshes = [o for o in scene.objects if o.type == "MESH" and o.name[:1] == "T" and o.name[2:3] == "_"]
extras = [o for o in scene.objects if o.type == "MESH" and any(o.name.startswith(f"AO-{a}_") for a in ADDONS)]
for o in [o for o in scene.objects if o.type == "MESH" and o.name.startswith("AO-") and o not in extras]:
    o.hide_render = True
for o in meshes + extras:  # the kit's materials are all MI_*; anything else is ours, painted from the palette
    m = o.data.materials[0] if o.data.materials else None
    if m is None or not m.name.startswith("MI_"):
        o.data.materials.clear()
        o.data.materials.append(pal)
tiers = sorted({int(o.name[1]) for o in meshes})
for t in tiers:
    mine = [o for o in meshes if int(o.name[1]) == t] + extras
    for o in meshes + extras:  # (the cutaway hid some of the add-on's pieces: back on)
        o.hide_render = o not in mine
    cs = [o.matrix_world @ Vector(c) for o in mine for c in o.bound_box]
    lo = Vector([min(c[i] for c in cs) for i in range(3)])
    hi = Vector([max(c[i] for c in cs) for i in range(3)])
    center = (lo + hi) / 2
    size = (hi - lo).length
    camera(scene, center, size * 1.25, Vector((-0.8, -1.0, 0.55)))
    scene.render.filepath = os.path.join(OUT, f"{NAME}_t{t}_out.png")
    bpy.ops.render.render(write_still=True)
    # cut away: drop the roof, everything above 2.2 m and the front half's walls
    for o in mine:
        c = o.matrix_world @ (sum((Vector(v) for v in o.bound_box), Vector()) / 8)
        roofish = "Roof" in o.name or "Chimney" in o.name
        o.hide_render = roofish or c.z > 2.9 or (c.y < lo.y + 1.0 and "Floor" not in o.name)
    camera(scene, Vector((center.x, center.y, 0.5)), size * 0.95, Vector((-0.25, -0.6, 1.0)))
    scene.render.filepath = os.path.join(OUT, f"{NAME}_t{t}_cut.png")
    bpy.ops.render.render(write_still=True)
print("rendered", NAME, tiers)
