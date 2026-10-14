"""Renders inventory icons from the item / fish models, with Blender's Workbench engine.

Run headless from the project folder, after make_models.py:

    blender -b -P tools/blender/render_icons.py -- models art/palette.png art/icons

For each entry in ICONS: import the .glb, give it the palette texture (nearest filtering, so each
face is one flat colour), frame it with an orthographic camera from the given direction, and
render a transparent SIZE x SIZE PNG. Then run tools/outline_icons.py to add the dark outline.
The game finds icons by item id: art/icons/<id>.png (see scripts/items.gd).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
MODELS, PALETTE, OUT = argv[0], argv[1], argv[2]
SIZE = 128

# item id -> (model path inside MODELS, view direction the camera looks FROM, Blender coords)
ICONS = {
    "wood": ("items/wood.glb", (1.0, -1.0, 0.9)),
    "ore": ("items/ore.glb", (1.0, -1.0, 0.8)),
    "oak": ("items/oak.glb", (1.0, -1.0, 0.9)),
    "iron": ("items/iron.glb", (1.0, -1.0, 0.8)),
    "perch": ("fish/perch.glb", (1.0, 0.25, 0.45)),
    "trout": ("fish/trout.glb", (1.0, 0.25, 0.45)),
    "pike": ("fish/pike.glb", (1.0, 0.25, 0.45)),
}


def palette_material():
    mat = bpy.data.materials.new("Palette")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.abspath(PALETTE))
    tex.interpolation = "Closest"
    bsdf = nodes.get("Principled BSDF")
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nodes.active = tex  # Workbench "Texture" colour uses the active image node
    return mat


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_object_outline = True
    shading.object_outline_color = (0.05, 0.05, 0.07)
    shading.show_specular_highlight = False
    scene.view_settings.view_transform = "Standard"
    return scene


def render(item_id, model, view):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = setup_scene()
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, model))
    mat = palette_material()
    meshes = [o for o in scene.objects if o.type == "MESH"]
    for o in meshes:
        o.data.materials.clear()
        o.data.materials.append(mat)

    # bounding box of everything, in world space
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center, extent = (lo + hi) / 2, (hi - lo).length

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    direction = Vector(view).normalized()
    cam.location = center + direction * extent * 3
    rot = (-direction).to_track_quat("-Z", "Y")
    cam.rotation_euler = rot.to_euler()
    # frame what the camera actually sees: the corners' spread across its right / up axes
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    spread = max(max(c.dot(axis) for c in corners) - min(c.dot(axis) for c in corners) for axis in (right, up))
    cam_data.ortho_scale = spread * 1.12  # a little room for the outline
    mid = sum(corners, Vector()) / len(corners)
    cam.location += right * (mid - center).dot(right) + up * (mid - center).dot(up)
    scene.camera = cam

    scene.render.filepath = os.path.abspath(os.path.join(OUT, item_id + ".png"))
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)


os.makedirs(OUT, exist_ok=True)
for item_id, (model, view) in ICONS.items():
    render(item_id, model, view)
