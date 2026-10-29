"""A contact sheet of the dogs (plans/dog.md): every breed (rows) in every coat (columns), seen
from the front-left, with Blender's Workbench engine. Run headless from the project folder, after
make_village.py's `dogs` builder:

    blender -b -P tools/blender/render_dogs.py -- models art/palette.png docs/images/dog/models.png
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
MODELS, PALETTE, OUT = argv[0], argv[1], argv[2]
BREEDS = ["terrier", "shepherd", "fluffy"]
SPACING = Vector((1.3, 0, 0))  # between coats
ROW = Vector((0, 1.4, 0))      # between breeds

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = 1500
scene.render.resolution_y = 1100
scene.render.image_settings.file_format = "PNG"
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "TEXTURE"
shading.show_object_outline = True
shading.object_outline_color = (0.05, 0.05, 0.07)
shading.show_specular_highlight = False
scene.view_settings.view_transform = "Standard"
scene.world = bpy.data.worlds.new("Sky")
scene.world.color = (0.55, 0.62, 0.5)

mat = bpy.data.materials.new("Palette")
mat.use_nodes = True
tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
tex.image = bpy.data.images.load(os.path.abspath(PALETTE))
tex.interpolation = "Closest"
mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"])
mat.node_tree.nodes.active = tex

files = sorted(os.listdir(os.path.join(MODELS, "dogs")))
for r, breed in enumerate(BREEDS):
    coats = [f for f in files if f.startswith(f"dog_{breed}_") and f.endswith(".glb")]
    for col, name in enumerate(coats):
        before = set(scene.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, "dogs", name))
        new = [o for o in scene.objects if o not in before]
        for o in new:
            if o.parent is None:
                o.location += SPACING * col + ROW * r
            if o.type == "MESH":
                o.data.materials.clear()
                o.data.materials.append(mat)

meshes = [o for o in scene.objects if o.type == "MESH"]
corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
center = (lo + hi) / 2
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
scene.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = (hi - lo).length * 0.95
view = Vector((-0.8, -1.0, 0.75)).normalized()
cam.location = center + view * 20.0
cam.rotation_euler = (-view).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
scene.render.filepath = os.path.abspath(OUT)
bpy.ops.render.render(write_still=True)
print("rendered", scene.render.filepath)
