"""Generates the starter low-poly models as .glb files, using Blender's Python API.

Run headless from the project folder (Blender 4.2+ / 5.x):

    blender -b -P tools/blender/make_models.py -- models art/palette.json

Every model is built from a few primitives with jittered vertices, flat-shaded, and coloured by
pointing each face's UVs at a swatch of art/palette.png (looked up by name in palette.json).
Object names follow the ResourceNode convention: Body_*, Chunk_*, Rubble_*.

These are starters to learn from: open a .glb in Blender (File > Import > glTF), tweak, and
export back over it (File > Export > glTF 2.0, format .glb). Re-running this script overwrites
them, so rename yours if you want to keep both.

Coordinates here are Blender's (Z up, -Y toward the viewer); the glTF exporter converts to
Godot's Y-up, so Blender +Y becomes Godot -Z (forward).
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = argv[0]
SWATCHES = json.load(open(argv[1]))["swatches"]


# --- helpers ----------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def swatch_uv(name):
    u, v = SWATCHES[name]["uv"]  # image space, origin top-left
    return (u, 1.0 - v)          # Blender UV space, origin bottom-left


def paint(bm, choose):
    """Colour every face: choose(face) returns a palette swatch name. Also flat-shades."""
    uv_layer = bm.loops.layers.uv.verify()
    bm.normal_update()
    for f in bm.faces:
        uv = swatch_uv(choose(f))
        for loop in f.loops:
            loop[uv_layer].uv = uv
        f.smooth = False


def shade_by_normal(top, side, bottom, rng, side_alt=None):
    """Lighter on top, darker underneath, a little random variation on the sides."""
    def choose(f):
        if f.normal.z > 0.55:
            return top
        if f.normal.z < -0.4:
            return bottom
        return side_alt if side_alt and rng.random() < 0.35 else side
    return choose


def jitter(bm, amount, rng, squash=(1.0, 1.0, 1.0)):
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-amount, amount)
        v.co.x *= squash[0]
        v.co.y *= squash[1]
        v.co.z *= squash[2]


def make_object(name, bm, location=(0, 0, 0), rotation=(0, 0, 0)):
    """Object origin = its own centre (mesh built around 0), placed at `location`."""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = Euler(rotation)
    return obj


def blob(radius, rng, jitter_amount=0.18, squash=(1, 1, 0.75), subdiv=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    jitter(bm, jitter_amount, rng, squash)
    return bm


def box(size):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return bm


def prism(segments, r_bottom, r_top, height):
    """Upright n-sided column, centred on the origin."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r_bottom, radius2=r_top, depth=height)
    return bm


def export(name):
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                              export_apply=True, export_materials="NONE")
    print("exported", path)


# --- models -----------------------------------------------------------------------------------

def rock():
    """Grey boulder with copper flecks: a core, five chunks that break off, and rubble."""
    reset()
    rng = random.Random(11)
    stone = shade_by_normal("stone.5", "stone.3", "stone.1", rng, side_alt="stone.4")

    bm = blob(0.46, rng, squash=(1.1, 1.0, 0.62))
    paint(bm, stone)
    make_object("Body_Core", bm, (0, 0, 0.28))

    chunks = [  # (location, radius, has copper)
        ((0.36, -0.2, 0.36), 0.27, False),
        ((-0.36, -0.16, 0.33), 0.27, True),
        ((0.04, 0.05, 0.62), 0.21, False),
        ((0.24, 0.38, 0.28), 0.22, True),
        ((-0.27, 0.34, 0.3), 0.26, False),
    ]
    for i, (loc, r, copper) in enumerate(chunks):
        bm = blob(r, rng, jitter_amount=0.25, squash=(1.0, 0.95, 0.85), subdiv=1)

        def choose(f, copper=copper):
            if copper and rng.random() < 0.45:
                return "ore.copper" if f.normal.z > 0.2 else "ore.copper_dark"
            return stone(f)
        paint(bm, choose)
        rot = (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(0, math.tau))
        make_object(f"Chunk_{'ABCDE'[i]}", bm, loc, rot)

    for i, (loc, r) in enumerate([((0.15, 0.05, 0.07), 0.22), ((-0.2, -0.1, 0.06), 0.17), ((0.0, 0.25, 0.05), 0.14)]):
        bm = blob(r, rng, jitter_amount=0.3, squash=(1.2, 1.0, 0.4), subdiv=1)
        paint(bm, shade_by_normal("stone.4", "stone.2", "stone.1", rng))
        make_object(f"Rubble_{i}", bm, loc, (0, 0, rng.uniform(0, math.tau)))
    export("rock")


def tree():
    """Six-sided tapered trunk, two lumpy canopy blobs, bark slabs that chip off, a stump."""
    reset()
    rng = random.Random(7)

    bm = prism(6, 0.24, 0.15, 3.2)
    jitter(bm, 0.06, rng)
    paint(bm, shade_by_normal("wood.5", "wood.3", "wood.2", rng, side_alt="wood.2"))
    make_object("Body_Trunk", bm, (0, 0, 1.6))

    leaves = shade_by_normal("leaves.5", "leaves.3", "leaves.1", rng, side_alt="leaves.4")
    bm = blob(1.25, rng, jitter_amount=0.2, squash=(1.0, 1.0, 0.72))
    paint(bm, leaves)
    make_object("Body_Canopy", bm, (0, 0, 3.5), (0, 0, 0.4))
    bm = blob(0.85, rng, jitter_amount=0.22, squash=(1.0, 1.0, 0.8))
    paint(bm, leaves)
    make_object("Body_CanopyTop", bm, (0.15, -0.1, 4.45), (0, 0, 1.1))

    # bark slabs hugging the trunk at chopping height, one per side the axe can come from
    for i in range(4):
        a = i * math.tau / 4 + 0.3
        bm = box((0.34, 0.07, 0.3))
        jitter(bm, 0.12, rng)
        paint(bm, shade_by_normal("wood.3", "wood.1", "wood.1", rng, side_alt="wood.0"))
        loc = (math.cos(a) * 0.2, math.sin(a) * 0.2, 1.3)
        make_object(f"Chunk_Bark{i}", bm, loc, (0, 0, a + math.pi / 2))

    bm = prism(6, 0.28, 0.23, 0.4)
    jitter(bm, 0.06, rng)
    paint(bm, lambda f: "wood.7" if f.normal.z > 0.9 else ("wood.3" if rng.random() < 0.6 else "wood.2"))
    make_object("Rubble_Stump", bm, (0, 0, 0.2))
    export("tree")


def pickaxe():
    """Handle along +Z from the grip (origin) up; head with two drooping spikes, along Y."""
    reset()
    rng = random.Random(3)
    bm = box((0.038, 0.038, 0.5))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, 0.21))
    bm = box((0.06, 0.075, 0.075))
    paint(bm, shade_by_normal("metal.4", "metal.3", "metal.2", rng))
    make_object("Collar", bm, (0, 0, 0.42))
    for side in (1, -1):  # +1 = forward (Godot -Z)
        bm = prism(4, 0.032, 0.006, 0.24)  # tapered spike along its own Z
        paint(bm, shade_by_normal("metal.6", "metal.4", "metal.3", rng, side_alt="metal.5"))
        # lay it along Y, pointing away from the collar, tip drooping 10 degrees
        make_object(f"Spike{'Front' if side > 0 else 'Back'}", bm, (0, side * 0.14, 0.405),
                    (-side * math.radians(90 + 10), 0, 0))
    export("pickaxe")


def axe():
    """Handle along +Z; a fan-shaped blade sticking out forward (+Y) near the top."""
    reset()
    rng = random.Random(4)
    bm = box((0.038, 0.038, 0.5))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, 0.21))
    bm = box((0.03, 0.17, 0.11))
    for v in bm.verts:  # widen toward the cutting edge (far +Y end) and thin it to an edge
        if v.co.y > 0:
            v.co.z *= 1.7
            v.co.x *= 0.35
    edge = lambda f: "metal.7" if f.normal.y > 0.7 else ("metal.5" if abs(f.normal.x) > 0.5 else "metal.3")
    paint(bm, edge)
    make_object("Blade", bm, (0, 0.1, 0.38))
    export("axe")


os.makedirs(OUT_DIR, exist_ok=True)
for build in (rock, tree, pickaxe, axe):
    build()
