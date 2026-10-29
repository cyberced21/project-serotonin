"""A picture of the trophy wall full (plans/trophies.md): your home at tier `T`, a trophy of each
kind on its plaques (and the mantel, at the Homestead), looked at from across the room.

    blender -b -P tools/blender/render_trophy_wall.py -- models art/palette.png OUT.png [tier]
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
MODELS, PALETTE, OUT = argv[0], argv[1], argv[2]
TIER = int(argv[3]) if len(argv) > 3 else 3
WALL = ["log_b", "fish_a_pike", "sheaf_b", "stick_b", "fish_a_salmon", "feather_a"]
MANTEL = ["geode_b", "shell_b", "feather_a"]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 1200, 800
scene.view_settings.view_transform = "AgX"
world = bpy.data.worlds.new("Sky")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.5, 0.45, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
scene.world = world
lamp = bpy.data.objects.new("Lamp", bpy.data.lights.new("Lamp", "POINT"))
lamp.data.energy = 300
lamp.data.color = (1.0, 0.82, 0.6)
scene.collection.objects.link(lamp)

pal = bpy.data.materials.new("Palette")
pal.use_nodes = True
tex = pal.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(os.path.abspath(PALETTE))
tex.interpolation = "Closest"
pal.node_tree.links.new(tex.outputs["Color"], pal.node_tree.nodes["Principled BSDF"].inputs["Base Color"])


def ours(objs):
    for o in objs:
        if o.type == "MESH":
            m = o.data.materials[0] if o.data.materials else None
            if m is None or not m.name.startswith("MI_"):
                o.data.materials.clear()
                o.data.materials.append(pal)


before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "village", "home.gltf"))
house = [o for o in bpy.data.objects if o not in before]
ours(house)
for o in house:  # just this tier, and its roof and upstairs off
    keep = o.name.startswith(f"T{TIER}_") and "Roof" not in o.name and "Chimney" not in o.name
    keep = keep and (o.matrix_world.translation.z < 2.9 or "Trophy" in o.name or o.type != "MESH")
    o.hide_render = not keep
spots = {o.name.split("_", 1)[1].split(".")[0]: o for o in house if o.name.startswith(f"T{TIER}_") and o.type == "EMPTY"}


def hang(name, spot):
    b = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "trophies", name + ".glb"))
    new = [o for o in bpy.data.objects if o not in b]
    ours(new)
    for o in new:
        if o.parent is None:
            o.matrix_world = spot.matrix_world @ Matrix.Scale(0.8, 4) @ o.matrix_world  # (TrophyPlaque.SCALE)


for i, name in enumerate(WALL):
    if f"TrophySlot{i + 1}" in spots:
        hang(name, spots[f"TrophySlot{i + 1}"])
for i, name in enumerate(MANTEL):
    if f"MantelSpot{i + 1}" in spots:
        hang(name, spots[f"MantelSpot{i + 1}"])

slots = [spots[k].matrix_world.translation for k in spots if k.startswith("TrophySlot")]
mid = sum(slots, Vector()) / len(slots)
facing = spots["TrophySlot2"].matrix_world.to_3x3() @ Vector((0, -1, 0))  # (a marker's front is -Y)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
cam.data.lens = 28
cam.location = mid + facing * 3.2 + Vector((0, 0, 0.1))
cam.rotation_euler = (-facing).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
lamp.location = mid + facing * 1.8 + Vector((0, 0, 0.8))
scene.render.filepath = os.path.abspath(OUT)
bpy.ops.render.render(write_still=True)
print("rendered", OUT)
