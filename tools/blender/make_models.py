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

def rock(name="rock", seed=11, stone_shades=("stone.5", "stone.3", "stone.1", "stone.4"),
         ore=("ore.copper", "ore.copper_dark"), size=1.0, ore_chance=0.45, ore_everywhere=False):
    """Boulder with ore flecks: a core, five chunks that break off, and rubble.
    The default is the grey copper rock; iron_rock() is a bigger, darker one with iron."""
    reset()
    rng = random.Random(seed)
    top, side, bottom, alt = stone_shades
    stone = shade_by_normal(top, side, bottom, rng, side_alt=alt)

    bm = blob(0.46 * size, rng, squash=(1.1, 1.0, 0.62))
    paint(bm, stone)
    make_object("Body_Core", bm, (0, 0, 0.28 * size))

    chunks = [  # (location, radius, has copper)
        ((0.36, -0.2, 0.36), 0.27, False),
        ((-0.36, -0.16, 0.33), 0.27, True),
        ((0.04, 0.05, 0.62), 0.21, False),
        ((0.24, 0.38, 0.28), 0.22, True),
        ((-0.27, 0.34, 0.3), 0.26, False),
    ]
    for i, (loc, r, copper) in enumerate(chunks):
        bm = blob(r * size, rng, jitter_amount=0.25, squash=(1.0, 0.95, 0.85), subdiv=1)

        def choose(f, copper=copper):
            if (copper or ore_everywhere) and rng.random() < ore_chance:
                return ore[0] if f.normal.z > 0.2 else ore[1]
            return stone(f)
        paint(bm, choose)
        rot = (rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(0, math.tau))
        make_object(f"Chunk_{'ABCDE'[i]}", bm, tuple(c * size for c in loc), rot)

    for i, (loc, r) in enumerate([((0.15, 0.05, 0.07), 0.22), ((-0.2, -0.1, 0.06), 0.17), ((0.0, 0.25, 0.05), 0.14)]):
        bm = blob(r * size, rng, jitter_amount=0.3, squash=(1.2, 1.0, 0.4), subdiv=1)
        paint(bm, shade_by_normal("stone.4", "stone.2", "stone.1", rng))
        make_object(f"Rubble_{i}", bm, tuple(c * size for c in loc), (0, 0, rng.uniform(0, math.tau)))
    export(name)


def iron_rock():
    """Bigger, darker boulder streaked with iron (Mining 15)."""
    rock("iron_rock", seed=12, stone_shades=("stone.3", "stone.2", "stone.0", "stone.1"),
         ore=("metal.7", "ore.iron"), size=1.15, ore_chance=0.4, ore_everywhere=True)


# The starter tree's canopy: (radius, jitter, squash, location, rotation) per blob.
TREE_CANOPY = [
    (1.25, 0.2, (1.0, 1.0, 0.72), (0, 0, 3.5), (0, 0, 0.4)),
    (0.85, 0.22, (1.0, 1.0, 0.8), (0.15, -0.1, 4.45), (0, 0, 1.1)),
]


def tree(name="tree", seed=7, trunk=(0.24, 0.15, 3.2), bark=("wood.5", "wood.3", "wood.2", "wood.2"),
         leaf_shades=("leaves.5", "leaves.3", "leaves.1", "leaves.4"), canopy=TREE_CANOPY,
         slab=("wood.3", "wood.1", "wood.1", "wood.0"), slab_size=(0.34, 0.2), stump=(0.28, 0.23)):
    """Six-sided tapered trunk, lumpy canopy blobs, bark slabs that chip off, a stump.
    The default is the starter tree; oak() is a stouter, darker, wider one.
    slab_size: (width, distance from the trunk's centre) of the bark slabs."""
    reset()
    rng = random.Random(seed)
    r_bottom, r_top, height = trunk

    bm = prism(6, r_bottom, r_top, height)
    jitter(bm, 0.06, rng)
    paint(bm, shade_by_normal(bark[0], bark[1], bark[2], rng, side_alt=bark[3]))
    make_object("Body_Trunk", bm, (0, 0, height / 2))

    leaves = shade_by_normal(leaf_shades[0], leaf_shades[1], leaf_shades[2], rng, side_alt=leaf_shades[3])
    names = ["Body_Canopy", "Body_CanopyTop"] + [f"Body_Canopy{i}" for i in range(2, len(canopy))]
    for (radius, jit, squash, loc, rot), obj_name in zip(canopy, names):
        bm = blob(radius, rng, jitter_amount=jit, squash=squash)
        paint(bm, leaves)
        make_object(obj_name, bm, loc, rot)

    # bark slabs hugging the trunk at chopping height, one per side the axe can come from
    width, dist = slab_size
    for i in range(4):
        a = i * math.tau / 4 + 0.3
        bm = box((width, 0.07, 0.3))
        jitter(bm, 0.12, rng)
        paint(bm, shade_by_normal(slab[0], slab[1], slab[2], rng, side_alt=slab[3]))
        loc = (math.cos(a) * dist, math.sin(a) * dist, 1.3)
        make_object(f"Chunk_Bark{i}", bm, loc, (0, 0, a + math.pi / 2))

    bm = prism(6, stump[0], stump[1], 0.4)
    jitter(bm, 0.06, rng)
    paint(bm, lambda f: "wood.7" if f.normal.z > 0.9 else (bark[1] if rng.random() < 0.6 else bark[2]))
    make_object("Rubble_Stump", bm, (0, 0, 0.2))
    export(name)


def oak():
    """A stout oak (Woodcutting 15): thick dark trunk, one broad canopy of three dark blobs."""
    tree("oak", seed=8, trunk=(0.36, 0.24, 2.8), bark=("wood.3", "wood.1", "wood.0", "wood.2"),
         leaf_shades=("leaves.3", "leaves.2", "leaves.0", "leaves.1"),
         canopy=[
             (1.55, 0.2, (1.15, 1.1, 0.62), (0, 0, 3.2), (0, 0, 0.3)),
             (1.05, 0.22, (1.0, 1.0, 0.7), (0.95, 0.35, 3.55), (0, 0, 1.0)),
             (1.0, 0.22, (1.0, 1.0, 0.7), (-0.85, -0.45, 3.65), (0, 0, 2.2)),
         ],
         slab=("wood.2", "wood.0", "wood.0", "wood.1"), slab_size=(0.48, 0.3), stump=(0.4, 0.34))


def block_hand(along="z", grip=0.16):
    """A blocky fist gripping the tool `grip` metres up its handle (choked up, so it's in view in
    first person), with a sleeve cuff below it. `along` is the axis the handle runs along ("z" for
    the axe / pickaxe, "y" for the spear)."""
    skin, sleeve = "wood.7", "accent.4"
    parts = [  # (name, size along (x, across, handle), offset (x, across, handle), colour)
        ("HandFist", (0.085, 0.095, 0.1), (0.0, -0.012, grip), skin),
        ("HandThumb", (0.03, 0.035, 0.05), (0.035, -0.045, grip + 0.04), "wood.6"),
        ("HandCuff", (0.1, 0.11, 0.08), (0.0, -0.015, grip - 0.09), sleeve),
    ]
    for name, (sx, sa, sh), (ox, oa, oh), color in parts:
        if along == "z":
            make_object(name, _painted(box((sx, sa, sh)), color), (ox, oa, oh))
        else:  # handle along y: swap the across / along axes
            make_object(name, _painted(box((sx, sh, sa)), color), (ox, oh, oa))


def _painted(bm, color):
    paint(bm, lambda f: color)
    return bm


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
    block_hand("z")
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
    block_hand("z")
    export("axe")


def spear():
    """Fishing spear pointing forward (+Y, Godot -Z) from the grip at the origin: wooden shaft,
    a dark binding wrap, and a barbed metal tip at about 1.2 m."""
    reset()
    rng = random.Random(5)
    bm = prism(6, 0.022, 0.02, 1.45)
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Shaft", bm, (0, 0.45, 0), (-math.pi / 2, 0, 0))  # from -0.27 to 1.18 along Y
    bm = prism(6, 0.027, 0.027, 0.08)
    paint(bm, lambda f: "wood.1")
    make_object("Wrap", bm, (0, 1.12, 0), (-math.pi / 2, 0, 0))
    bm = prism(4, 0.03, 0.002, 0.2)
    paint(bm, shade_by_normal("metal.7", "metal.5", "metal.4", rng, side_alt="metal.6"))
    make_object("Tip", bm, (0, 1.28, 0), (-math.pi / 2, 0, math.pi / 4))
    for side in (1, -1):  # two barbs angled back from the tip
        bm = prism(3, 0.012, 0.001, 0.08)
        paint(bm, lambda f: "metal.5")
        make_object(f"Barb{'L' if side > 0 else 'R'}", bm, (side * 0.03, 1.27, 0),
                    (-math.pi / 2 - math.radians(150), 0, side * math.radians(25)))
    block_hand("y", grip=0.42)
    export("spear")


# --- fish -------------------------------------------------------------------------------------
# One mesh per fish ("Fish"), head toward +Y (Godot -Z, forward), origin at the body centre, so
# the swim shader can wiggle it by distance along the body. Length in metres.

def fish_mesh(length, width, height, tail_taper=0.85, snout=1.0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.5)
    half = length / 2.0
    for v in bm.verts:
        y = v.co.y  # -0.5 (tail) .. 0.5 (head)
        taper = 1.0 - tail_taper * max(-y * 2.0, 0.0) ** 1.5  # thin toward the tail
        if y > 0:
            taper *= 1.0 - (1.0 - snout) * (y * 2.0) ** 2      # pointy / flat snout
        v.co.x *= width * taper
        v.co.z *= height * taper
        v.co.y *= length
    # tail fin: a thin vertical fan behind the body; dorsal fin on top
    tail = [(0.0, -half * 0.92, 0.0), (0.0, -half - length * 0.22, height * 0.42),
            (0.0, -half - length * 0.16, 0.0), (0.0, -half - length * 0.22, -height * 0.42)]
    fin_tri(bm, tail[0], tail[1], tail[2])
    fin_tri(bm, tail[0], tail[2], tail[3])
    fin_tri(bm, (0.0, length * 0.12, height * 0.42), (0.0, -length * 0.12, height * 0.68),
            (0.0, -length * 0.2, height * 0.38))
    return bm


def fin_tri(bm, a, b, c):
    """A flat triangle visible from both sides (two faces, each with its own vertices)."""
    bm.faces.new([bm.verts.new(p) for p in (a, b, c)])
    bm.faces.new([bm.verts.new(p) for p in (c, b, a)])


def fish_painter(back, side, belly, fin, rng, bars=None, stripe=None, spots=None, length=1.0):
    def choose(f):
        c = f.calc_center_median()
        if abs(f.normal.x) > 0.95 and abs(c.x) < 0.002:  # the flat fins (they lie in the x = 0 plane)
            return fin
        if f.normal.z > 0.45:
            return back
        if f.normal.z < -0.45:
            return belly
        if bars and int((c.y / length + 0.5) * 6) % 2 == 1 and c.y > -length * 0.3:
            return bars  # perch: dark vertical bars
        if stripe and abs(c.z) < length * 0.03:
            return stripe  # trout: pink side stripe
        if spots and rng.random() < 0.3:
            return spots  # pike: pale spots
        return side
    return choose


def fish(name, length, width, height, painter, tail_taper=0.85, snout=1.0):
    reset()
    bm = fish_mesh(length, width, height, tail_taper, snout)
    paint(bm, painter)
    make_object("Fish", bm)
    export(os.path.join("fish", name))


def perch():
    rng = random.Random(21)
    fish("perch", 0.24, 0.07, 0.1, fish_painter("leaves.4", "leaves.6", "accent.3", "accent.2", rng,
                                                bars="leaves.1", length=0.24))


def trout():
    rng = random.Random(22)
    fish("trout", 0.34, 0.08, 0.1, fish_painter("leaves.1", "metal.6", "neutral.7", "leaves.2", rng,
                                                stripe="accent.7", length=0.34))


def pike():
    rng = random.Random(23)
    fish("pike", 0.7, 0.1, 0.11, fish_painter("leaves.2", "leaves.4", "wood.7", "leaves.3", rng,
                                              spots="accent.3", length=0.7), tail_taper=0.7, snout=0.55)


# --- item models (for icons, later maybe for pickups) -----------------------------------------

def log_item():
    reset()
    rng = random.Random(31)
    bm = prism(6, 0.09, 0.085, 0.42)
    jitter(bm, 0.05, rng)
    paint(bm, lambda f: "wood.7" if abs(f.normal.z) > 0.9 else ("wood.3" if rng.random() < 0.6 else "wood.2"))
    make_object("Item", bm, rotation=(math.pi / 2, 0, 0.3))  # lying down
    export(os.path.join("items", "wood"))


def oak_item():
    reset()
    rng = random.Random(33)
    bm = prism(6, 0.12, 0.115, 0.38)
    jitter(bm, 0.05, rng)
    paint(bm, lambda f: "wood.7" if abs(f.normal.z) > 0.9 else ("wood.2" if rng.random() < 0.6 else "wood.1"))
    make_object("Item", bm, rotation=(math.pi / 2, 0, 0.3))  # lying down
    # a sprig of oak leaves on top, so it reads apart from an ordinary log
    for i, (x, y) in enumerate(((0.02, 0.02), (0.09, -0.04), (-0.05, -0.06))):
        bm = blob(0.05, rng, jitter_amount=0.15, squash=(1.4, 0.8, 0.3))
        paint(bm, lambda f: "leaves.5" if f.normal.z > 0 else "leaves.3")
        make_object(f"Leaf{i}", bm, (x, y, 0.13), (0, 0, i * 1.1))
    export(os.path.join("items", "oak"))


def iron_item():
    reset()
    rng = random.Random(34)
    bm = blob(0.14, rng, jitter_amount=0.3, squash=(1.0, 0.9, 0.8))
    paint(bm, lambda f: ("metal.7" if f.normal.z > 0.5 else ("ore.iron" if f.normal.z > -0.2 else "ore.iron_dark"))
          if rng.random() < 0.75 else ("stone.2" if f.normal.z > 0.3 else "stone.0"))
    make_object("Item", bm)
    export(os.path.join("items", "iron"))


def ore_item():
    reset()
    rng = random.Random(32)
    bm = blob(0.13, rng, jitter_amount=0.3, squash=(1.0, 0.9, 0.8))
    paint(bm, lambda f: ("ore.copper" if f.normal.z > 0.0 else "ore.copper_dark") if rng.random() < 0.55
          else ("stone.4" if f.normal.z > 0.3 else "stone.2"))
    make_object("Item", bm)
    export(os.path.join("items", "ore"))


# --- pond scenery -----------------------------------------------------------------------------

def reeds():
    """A clump of tapered reed blades with a few cattail heads. Origin at the base (on the bed)."""
    reset()
    rng = random.Random(41)
    for i in range(9):
        h = rng.uniform(0.9, 1.6)
        bm = prism(3, 0.018, 0.002, h)
        paint(bm, lambda f: "leaves.5" if rng.random() < 0.5 else "leaves.3")
        a, r = rng.uniform(0, math.tau), rng.uniform(0.0, 0.18)
        tilt = (rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), rng.uniform(0, math.tau))
        make_object(f"Blade{i}", bm, (math.cos(a) * r, math.sin(a) * r, h / 2), tilt)
        if i % 3 == 0:  # cattail head near the top
            bm = prism(6, 0.025, 0.025, 0.16)
            paint(bm, lambda f: "wood.2")
            make_object(f"Cattail{i}", bm, (math.cos(a) * r, math.sin(a) * r, h * 0.82), tilt)
    export(os.path.join("scenery", "reeds"))


def lily_pad():
    """A flat floating pad with a notch cut out; origin at its centre on the water line."""
    reset()
    rng = random.Random(42)
    bm = bmesh.new()
    centre = bm.verts.new((0, 0, 0.0))
    ring = []
    for i in range(10):
        a = (i / 10) * math.tau
        if i == 0:
            ring.append(bm.verts.new((0.04, 0.0, 0.0)))  # the notch, pulled in toward the centre
            continue
        r = 0.22 * rng.uniform(0.92, 1.05)
        ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
    for i in range(len(ring)):
        if i == 0 or i == len(ring) - 1:
            continue  # leave the notch open
        bm.faces.new((centre, ring[i], ring[i + 1]))
    bm.faces.new((centre, ring[1], ring[0]))
    paint(bm, lambda f: "leaves.4" if rng.random() < 0.6 else "leaves.3")
    make_object("Pad", bm)
    export(os.path.join("scenery", "lily_pad"))


def lily_flower():
    """A lily pad with a small pink-white flower on it."""
    reset()
    rng = random.Random(43)
    bm = prism(8, 0.2, 0.2, 0.01)
    paint(bm, lambda f: "leaves.4")
    make_object("Pad", bm, (0, 0, 0.005))
    for i in range(6):
        a = i * math.tau / 6
        bm = prism(3, 0.03, 0.002, 0.09)
        paint(bm, lambda f: "neutral.7" if rng.random() < 0.6 else "accent.7")
        make_object(f"Petal{i}", bm, (math.cos(a) * 0.03, math.sin(a) * 0.03, 0.04),
                    (math.cos(a + math.pi / 2) * 0.7, math.sin(a + math.pi / 2) * 0.7, 0))
    bm = blob(0.025, rng, jitter_amount=0.1)
    paint(bm, lambda f: "accent.3")
    make_object("Heart", bm, (0, 0, 0.04))
    export(os.path.join("scenery", "lily_flower"))


def shore_stone():
    reset()
    rng = random.Random(44)
    bm = blob(0.28, rng, jitter_amount=0.28, squash=(1.2, 1.0, 0.55))
    paint(bm, shade_by_normal("stone.5", "stone.3", "stone.2", rng, side_alt="terrain.moss"))  # a little moss
    make_object("Stone", bm, (0, 0, 0.06))
    export(os.path.join("scenery", "shore_stone"))


# --- terrain scenery (scattered by scripts/scenery_scatter.gd with MultiMesh) -----------------
# Each is ONE merged mesh with its origin at the base (MultiMesh draws a single mesh), so the
# sway shader can lean it by height above the origin.

def merge_all(name):
    """Joins every mesh object in the scene into one called `name`, origin at the world origin."""
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def grass_tuft():
    reset()
    rng = random.Random(51)
    for i in range(7):
        h = rng.uniform(0.25, 0.5)
        bm = prism(3, 0.03, 0.002, h)
        shade = rng.choice(["leaves.4", "leaves.5", "leaves.6"])
        paint(bm, lambda f, shade=shade: shade)
        a, r = rng.uniform(0, math.tau), rng.uniform(0.0, 0.12)
        tilt = (rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), rng.uniform(0, math.tau))
        make_object(f"Blade{i}", bm, (math.cos(a) * r, math.sin(a) * r, h / 2), tilt)
    merge_all("Tuft")
    export(os.path.join("scenery", "grass_tuft"))


def flowers(name, seed, petals):
    reset()
    rng = random.Random(seed)
    for i in range(4):
        h = rng.uniform(0.22, 0.38)
        a, r = rng.uniform(0, math.tau), rng.uniform(0.03, 0.14)
        x, y = math.cos(a) * r, math.sin(a) * r
        bm = prism(3, 0.012, 0.006, h)
        paint(bm, lambda f: "leaves.3")
        make_object(f"Stem{i}", bm, (x, y, h / 2))
        bm = blob(0.04, rng, jitter_amount=0.2, squash=(1.0, 1.0, 0.6), subdiv=1)
        c = petals[i % len(petals)]
        paint(bm, lambda f, c=c: "accent.3" if f.normal.z > 0.85 else c)
        make_object(f"Head{i}", bm, (x, y, h))
    for i in range(3):  # a few leaves at the base
        bm = prism(3, 0.03, 0.002, 0.18)
        paint(bm, lambda f: "leaves.4")
        make_object(f"Leaf{i}", bm, (0, 0, 0.08), (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, math.tau)))
    merge_all("Flowers")
    export(os.path.join("scenery", name))


def bush(name, seed, blobs, shades):
    reset()
    rng = random.Random(seed)
    for i, (loc, r) in enumerate(blobs):
        bm = blob(r, rng, jitter_amount=0.22, squash=(1.0, 1.0, 0.8))
        paint(bm, shade_by_normal(shades[0], shades[1], shades[2], rng, side_alt=shades[3]))
        make_object(f"Blob{i}", bm, loc)
    merge_all("Bush")
    export(os.path.join("scenery", name))


def boulder(name, seed, size, squash):
    reset()
    rng = random.Random(seed)
    bm = blob(size, rng, jitter_amount=0.25, squash=squash, subdiv=1)
    paint(bm, shade_by_normal("stone.4", "stone.3", "stone.1", rng, side_alt="terrain.moss"))
    make_object("Boulder", bm, (0, 0, size * squash[2] * 0.6))  # sunk a little into the ground
    merge_all("Boulder")
    export(os.path.join("scenery", name))


# --- ruins: the parkour blocks in the clearing ------------------------------------------------
# Each fills exactly the box its collision uses (Godot size x, y, z = width, height, depth), centred
# on the origin, so step / ledge / mantle heights stay what they were with the greybox boxes.

def stone_block(name, size, seed, cap=False):
    """Courses of chunky stone bricks filling a box; staggered joints, a little moss on top."""
    reset()
    rng = random.Random(seed)
    w, h, d = size  # Godot x, y, z  ->  Blender x, z, y
    courses = max(1, round(h / 0.28))
    ch = h / courses
    for c in range(courses):
        z = -h / 2 + (c + 0.5) * ch
        along_x = w >= d
        length, across = (w, d) if along_x else (d, w)
        rows = max(1, round(across / 1.1))
        for r in range(rows):
            a0 = -across / 2 + r * across / rows
            pos = -length / 2
            first = True
            while pos < length / 2 - 0.05:
                bl = rng.uniform(0.45, 0.9) * (0.5 if first and c % 2 else 1.0)
                first = False
                bl = min(bl, length / 2 - pos)
                if length / 2 - (pos + bl) < 0.25:
                    bl = length / 2 - pos  # no sliver at the end
                inset = rng.uniform(0.0, 0.03)
                bw, bd, bh = bl - 0.03 - inset, across / rows - 0.03 - inset, ch - 0.025
                centre_l, centre_a = pos + bl / 2, a0 + across / rows / 2
                bm = box((bw, bd, bh) if along_x else (bd, bw, bh))
                for v in bm.verts:  # rough, but only ever inward, so it stays inside the collision box
                    v.co *= 1.0 - rng.uniform(0.0, 0.06)
                top_course = c == courses - 1
                stone = shade_by_normal("terrain.moss" if top_course and rng.random() < 0.35 else "stone.5",
                                        rng.choice(["stone.3", "stone.4"]), "stone.2", rng, side_alt="stone.3")
                paint(bm, stone)
                loc = (centre_l, centre_a, z) if along_x else (centre_a, centre_l, z)
                make_object(f"Brick{c}_{r}_{round(pos * 100)}", bm, loc)
                pos += bl
    if cap:  # a slab on top of a pillar
        bm = box((w + 0.12, d + 0.12, 0.14))
        paint(bm, shade_by_normal("stone.5", "stone.4", "stone.2", rng))
        make_object("Cap", bm, (0, 0, h / 2 - 0.07))
    export(os.path.join("ruins", name))


def plank_ramp(name, size, seed):
    """Planks across two long beams, filling the ramp's box."""
    reset()
    rng = random.Random(seed)
    w, h, d = size
    for x in (-w / 2 + 0.3, w / 2 - 0.3):
        bm = box((0.26, d - 0.04, h * 0.55))
        paint(bm, shade_by_normal("wood.3", "wood.2", "wood.1", rng))
        make_object(f"Beam{x:+.0f}", bm, (x, 0, -h / 2 + h * 0.275))
    n = int(d / 0.32)
    for i in range(n):
        bm = box((w - rng.uniform(0.0, 0.15), d / n - 0.03, h * 0.42))
        jitter(bm, 0.01, rng)
        paint(bm, shade_by_normal(rng.choice(["wood.5", "wood.6"]), "wood.4", "wood.3", rng))
        make_object(f"Plank{i:02d}", bm, (rng.uniform(-0.04, 0.04), -d / 2 + (i + 0.5) * d / n, h / 2 - h * 0.21))
    export(os.path.join("ruins", name))


def ruins():
    os.makedirs(os.path.join(OUT_DIR, "ruins"), exist_ok=True)
    stone_block("step_050", (1.5, 0.5, 1.5), 61)
    stone_block("step_100", (1.5, 1.0, 1.5), 62)
    stone_block("step_150", (1.5, 1.5, 1.5), 63)
    stone_block("ledge_120", (3.0, 1.2, 2.0), 64)
    stone_block("wall_250", (8.0, 2.5, 1.0), 65)
    stone_block("pillar", (1.0, 3.0, 1.0), 66, cap=True)
    plank_ramp("ramp", (3.0, 0.3, 7.0), 67)


def scenery():
    grass_tuft()
    flowers("flowers_warm", 52, ["accent.3", "accent.2", "neutral.7"])
    flowers("flowers_cool", 53, ["accent.7", "accent.6", "accent.5"])
    bush("bush_round", 54, [((0, 0, 0.35), 0.5), ((0.35, 0.15, 0.3), 0.38), ((-0.3, -0.2, 0.28), 0.36)],
         ("leaves.4", "leaves.3", "leaves.1", "leaves.2"))
    bush("bush_low", 55, [((0, 0, 0.22), 0.4), ((0.45, -0.1, 0.18), 0.32), ((-0.4, 0.2, 0.2), 0.34),
                          ((0.1, 0.4, 0.16), 0.28)],
         ("leaves.5", "leaves.4", "leaves.2", "leaves.3"))
    boulder("boulder_big", 56, 0.9, (1.2, 1.0, 0.75))
    boulder("boulder_flat", 57, 0.7, (1.4, 1.1, 0.5))


if __name__ == "__main__":  # make_village.py imports the helpers above without building these
    os.makedirs(os.path.join(OUT_DIR, "scenery"), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, "fish"), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, "items"), exist_ok=True)
    for build in (rock, iron_rock, tree, oak, pickaxe, axe, spear, perch, trout, pike, log_item, ore_item,
                  oak_item, iron_item, reeds, lily_pad, lily_flower, shore_stone, scenery, ruins):
        build()
