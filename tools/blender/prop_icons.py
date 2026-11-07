"""Renders the town designer's palette pictures (plans/town-designer.md, phase 5): one small picture
of each prop and garden fixture in data/layout/catalog.json, seen from above at an angle,
with Blender's Workbench engine. The map editor shows them on its Stamp, Scatter and Row tools.

Run headless from the project folder:

    blender -b -P tools/blender/prop_icons.py -- [id ...]

(name catalog ids to render only those). Writes tools/map_editor/icons/<id>.png (SIZE x SIZE,
transparent). A model the game paints from the palette (own_materials false) gets art/palette.png;
the rest keep their own textures, or their materials' colours if they have none. A kit model's T2_
pieces (its state once restored) are left out. (Buildings aren't drawn: the Building tool shows
their footprints.)
"""
import json
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set(argv)
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "tools", "map_editor", "icons")
PALETTE = os.path.join(ROOT, "art", "palette.png")
SIZE = 96
VIEW = (1.0, -1.0, 1.25)  # (the camera looks from here, Blender coords: above, at an angle)


def res(path):
    return os.path.join(ROOT, path.replace("res://", ""))


def entries():
    with open(os.path.join(ROOT, "data", "layout", "catalog.json"), encoding="utf-8") as f:
        cat = json.load(f)
    out = {}
    for k, v in cat["props"].items():
        out[k] = (v["model"], not v.get("own_materials", True))
    for k, v in cat.get("fixtures", {}).items():
        out[k] = (v["model"], True)
    return out


def palette_material():
    mat = bpy.data.materials.new("Palette")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(PALETTE)
    tex.interpolation = "Closest"
    bsdf = nodes.get("Principled BSDF")
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nodes.active = tex
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
    shading.object_outline_color = (0.08, 0.07, 0.06)
    shading.show_specular_highlight = False
    shading.show_shadows = True
    scene.view_settings.view_transform = "Standard"
    return scene


def render(item_id, model, palette):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = setup_scene()
    path = res(model)
    if not os.path.exists(path):
        print("missing", item_id, path)
        return
    bpy.ops.import_scene.gltf(filepath=path)
    for o in list(scene.objects):  # (a kit model: its first state only)
        if o.name.startswith("T2_") or o.name.startswith("T3_") or o.name.startswith("T4_"):
            bpy.data.objects.remove(o)
    meshes = [o for o in scene.objects if o.type == "MESH"]
    if not meshes:
        print("no meshes", item_id)
        return
    mat = palette_material() if palette else None
    textured = False
    for o in meshes:
        for m in o.data.materials:
            if m and m.use_nodes and any(n.type == "TEX_IMAGE" and n.image for n in m.node_tree.nodes):
                textured = True
    if not mat and not textured:  # (colours only: show each material's base colour)
        scene.display.shading.color_type = "MATERIAL"
        for o in meshes:
            for m in o.data.materials:
                if m and m.use_nodes and m.node_tree.nodes.get("Principled BSDF"):
                    m.diffuse_color = m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value
    for o in meshes:
        if mat:
            o.data.materials.clear()
            o.data.materials.append(mat)
            continue
        for m in o.data.materials:  # (Workbench's "Texture" colour shows each material's active image: its base colour's)
            if m and m.use_nodes:
                imgs = [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]
                base = [l.from_node for l in m.node_tree.links if l.to_socket.name == "Base Color" and l.from_node.type == "TEX_IMAGE"]
                for node in (base or imgs)[:1]:
                    node.interpolation = "Closest"
                    m.node_tree.nodes.active = node
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center, extent = (lo + hi) / 2, (hi - lo).length
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    direction = Vector(VIEW).normalized()
    cam.location = center + direction * extent * 3
    rot = (-direction).to_track_quat("-Z", "Y")
    cam.rotation_euler = rot.to_euler()
    right, up = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0))
    spread = max(max(c.dot(a) for c in corners) - min(c.dot(a) for c in corners) for a in (right, up))
    cam_data.ortho_scale = spread * 1.12
    mid = sum(corners, Vector()) / len(corners)
    cam.location += right * (mid - center).dot(right) + up * (mid - center).dot(up)
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT, item_id + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", item_id)


os.makedirs(OUT, exist_ok=True)
for item_id, (model, palette) in entries().items():
    if not ONLY or item_id in ONLY:
        render(item_id, model, palette)
