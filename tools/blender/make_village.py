"""Generates the village models as .glb files: six buildings (three tiers each; the smithy has a fourth), their villagers
and a few props. Uses the helpers in make_models.py. Run headless from the project folder:

    blender -b -P tools/blender/make_village.py -- models art/palette.json [builder ...]

(name builders, e.g. `smithy`, to rebuild only those)

Outputs into models/village/:
  <building>.glb           every tier's pieces in one file, named T1_*, T2_*... The game
                           shows one tier at a time and builds the next one piece by piece,
                           lowest piece first. Empties named *Smoke* get chimney smoke.
  villager_<id>.glb        a toy villager in separate parts the game animates in code:
                           Body (pivot at the hips), Head (pivot at the neck), ArmL / ArmR
                           (pivots at the shoulders, the held tool is a child of ArmR),
                           LegL / LegR (pivots at the hips).
  props/<name>.glb         benches, lamp posts, barrels, crates, the signpost.
  ../dogs/dog_<breed>_<coat>.glb   the dog (plans/dog.md) in parts the game poses: see dog().

Buildings face Blender -Y (Godot +Z, "front"), origin at ground level in the middle.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix  # noqa: E402
from make_models import (OUT_DIR, axe_head_shade, blob, box, bmesh, bpy, export, felling_head, weather_stonework,  # noqa: E402
                         make_object, paint, prism, reset, Vector)

VILLAGE_DIR = os.path.join(OUT_DIR, "village")


def export_building(name):
    """models/village/<name>.glb, its stonework weathered like the rocks (weather_stonework)."""
    weather_stonework()
    export(os.path.join("village", name), loose_edges=True)


# --- kit: named, painted pieces ---------------------------------------------------------------

class Kit:
    """Adds pieces named <prefix>_<Base><n>, coloured by a swatch name or (top, side, bottom[, alt])."""

    def __init__(self, prefix, seed):
        self.prefix = prefix
        self.rng = random.Random(seed)
        self.n = 0

    def name(self, base):
        self.n += 1
        return f"{self.prefix}_{base}{self.n:03d}" if self.prefix else base

    def tone(self, colors):
        if isinstance(colors, str):
            return lambda f: colors
        top, side, bottom = colors[:3]
        alt = colors[3] if len(colors) > 3 else None
        rng = self.rng

        def choose(f):
            if f.normal.z > 0.55:
                return top
            if f.normal.z < -0.4:
                return bottom
            return alt if alt and rng.random() < 0.35 else side
        return choose

    def add(self, base, bm, colors, loc, rot=(0, 0, 0)):
        paint(bm, colors if callable(colors) else self.tone(colors))
        return make_object(self.name(base), bm, loc, rot)

    def box(self, base, size, loc, colors, rot=(0, 0, 0), jit=0.0):
        bm = box(size)
        if jit:
            for v in bm.verts:
                v.co += Vector((self.rng.uniform(-jit, jit), self.rng.uniform(-jit, jit), self.rng.uniform(-jit, jit)))
        return self.add(base, bm, colors, loc, rot)

    def post(self, base, r, z0, z1, x, y, colors=("wood.4", "wood.3", "wood.2"), segments=6):
        bm = prism(segments, r, r * 0.9, z1 - z0)
        return self.add(base, bm, colors, (x, y, (z0 + z1) / 2))

    def log(self, base, length, r, loc, axis="x", sides=("wood.4", "wood.3", "wood.5"), ends="wood.7"):
        bm = prism(6, r, r, length)
        for v in bm.verts:  # a little irregular
            v.co.x *= 1.0 + self.rng.uniform(-0.06, 0.06)
            v.co.y *= 1.0 + self.rng.uniform(-0.06, 0.06)
        rng = self.rng
        choose = lambda f: ends if abs(f.normal.z) > 0.9 else rng.choice(sides)
        rot = (0, math.pi / 2, 0) if axis == "x" else (math.pi / 2, 0, 0)
        return self.add(base, bm, choose, loc, rot)

    def stone(self, base, size, loc, colors=("stone.5", "stone.3", "stone.2", "stone.4")):
        return self.box(base, size, loc, colors, jit=min(size) * 0.12)

    def empty(self, name, loc):
        obj = bpy.data.objects.new(f"{self.prefix}_{name}", None)
        bpy.context.collection.objects.link(obj)
        obj.location = loc
        return obj

    # -- bigger shapes --

    def gable(self, base, half_depth, z0, z1, x, thickness, colors):
        """Triangular wall filling a gable end: base from y=-half_depth..half_depth at z0, apex at z1."""
        bm = bmesh.new()
        t = thickness / 2
        pts = [(-half_depth, z0), (half_depth, z0), (0.0, z1)]
        a = [bm.verts.new((-t, y, z)) for y, z in pts]
        b = [bm.verts.new((t, y, z)) for y, z in pts]
        bm.faces.new(a[::-1])
        bm.faces.new(b)
        for i in range(3):
            j = (i + 1) % 3
            bm.faces.new((a[i], a[j], b[j], b[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self.add(base, bm, colors, (x, 0, 0))

    def gable_roof(self, base, length, half_depth, wall_z, ridge_z, overhang, rows, colors,
                   thickness=0.12, y0=0.0):
        """Two roof slopes meeting at a ridge along X (centred at y=y0), each split into `rows` strips."""
        a = math.atan2(ridge_z - wall_z, half_depth)
        slope_len = (half_depth + overhang) / math.cos(a)
        strip = slope_len / rows
        for side in (-1, 1):
            for i in range(rows):
                d = (i + 0.5) * strip
                y = y0 + side * math.cos(a) * d
                z = ridge_z - math.sin(a) * d + thickness * 0.5
                self.box(base, (length, strip + 0.04, thickness), (0, y, z), colors, rot=(side * -a, 0, 0))

    def shed_roof(self, base, length, y_front, y_back, z_front, z_back, rows, colors, thickness=0.1, x=0.0):
        a = math.atan2(z_back - z_front, y_back - y_front)
        slope_len = math.hypot(y_back - y_front, z_back - z_front)
        strip = slope_len / rows
        for i in range(rows):
            t = (i + 0.5) / rows
            y = y_front + (y_back - y_front) * t
            z = z_front + (z_back - z_front) * t + thickness * 0.5
            self.box(base, (length, strip + 0.04, thickness), (x, y, z), colors, rot=(a, 0, 0))

    def plank_walls(self, x0, x1, y0, y1, z0, z1, door, colors, plank=0.45, thickness=0.08, window=None):
        """Four walls of vertical planks around x0..x1, y0..y1 (front = y0) with a door gap of width
        `door` in the middle of the front. Returns nothing; adds a lintel over the door."""
        h = z1 - z0
        zc = (z0 + z1) / 2
        rng = self.rng

        def run(axis, a0, a1, fixed, gap=0.0):
            n = max(int(round((a1 - a0) / plank)), 1)
            w = (a1 - a0) / n
            for i in range(n):
                c = a0 + (i + 0.5) * w
                if gap and abs(c) < gap / 2:
                    continue
                hh = h * rng.uniform(0.97, 1.0)
                size = (w - 0.02, thickness, hh) if axis == "x" else (thickness, w - 0.02, hh)
                loc = (c, fixed, z0 + hh / 2) if axis == "x" else (fixed, c, z0 + hh / 2)
                self.box("Plank", size, loc, rng.choice(colors) if isinstance(colors, list) else colors,
                         rot=(0, 0, 0), jit=0.01)

        run("x", x0, x1, y0, door)
        run("x", x0, x1, y1)
        run("y", y0 + thickness, y1 - thickness, x0)
        run("y", y0 + thickness, y1 - thickness, x1)
        if door:
            self.box("Lintel", (door + 0.1, thickness, max(z1 - (z0 + 2.0), 0.1)),
                     (0, y0, (z0 + 2.0 + z1) / 2), colors[0] if isinstance(colors, list) else colors)

    def window(self, loc, size, facing="y", frame="wood.6", glass="neutral.2"):
        w, h = size
        if facing == "y":
            self.box("WindowFrame", (w + 0.12, 0.08, h + 0.12), loc, frame)
            self.box("WindowGlass", (w, 0.1, h), loc, glass)
        else:
            self.box("WindowFrame", (0.08, w + 0.12, h + 0.12), loc, frame)
            self.box("WindowGlass", (0.1, w, h), loc, glass)

    def door(self, loc, size=(1.0, 2.0), color="wood.2", facing="y"):
        w, h = size
        x, y, z = loc
        if facing == "y":
            self.box("Door", (w, 0.08, h), (x, y, z + h / 2), color)
            self.box("Handle", (0.06, 0.06, 0.06), (x + w * 0.35, y - 0.06, z + h * 0.5), "metal.4")
        else:
            self.box("Door", (0.08, w, h), (x, y, z + h / 2), color)

    def barrel(self, loc, r=0.3, h=0.75):
        x, y, z = loc
        self.add("Barrel", prism(10, r, r, h), ("wood.5", "wood.3", "wood.2", "wood.4"), (x, y, z + h / 2))
        for zz in (0.18, h - 0.18):
            self.add("Band", prism(10, r + 0.015, r + 0.015, 0.05), "metal.2", (x, y, z + zz))

    def crate(self, loc, s=0.6):
        x, y, z = loc
        self.box("Crate", (s, s, s * 0.85), (x, y, z + s * 0.425), ("wood.6", "wood.5", "wood.3", "wood.4"),
                 rot=(0, 0, self.rng.uniform(-0.3, 0.3)))

    def chopping_block(self, loc, with_axe=True):
        x, y, z = loc
        bm = prism(7, 0.32, 0.3, 0.5)
        rng = self.rng
        self.add("Block", bm, lambda f: "wood.7" if f.normal.z > 0.9 else rng.choice(["wood.3", "wood.2"]),
                 (x, y, z + 0.25))
        if with_axe:  # stuck in the top, handle leaning back
            self.box("AxeHandle", (0.04, 0.04, 0.6), (x + 0.05, y + 0.12, z + 0.72), ("wood.6", "wood.4", "wood.3"),
                     rot=(0.55, 0, 0))
            self.box("AxeBlade", (0.03, 0.2, 0.14), (x + 0.05, y - 0.03, z + 0.5), "metal.5", rot=(0.55, 0, 0))

    def anvil(self, loc, s=1.0):
        x, y, z = loc
        bm = prism(7, 0.28 * s, 0.26 * s, 0.5)
        self.add("AnvilStump", bm, ("wood.7", "wood.3", "wood.2"), (x, y, z + 0.25))
        self.box("AnvilBase", (0.26 * s, 0.18 * s, 0.16), (x, y, z + 0.58), "metal.1")
        self.box("AnvilTop", (0.52 * s, 0.22 * s, 0.14), (x, y, z + 0.72), ("metal.4", "metal.2", "metal.1"))
        horn = prism(4, 0.08 * s, 0.01, 0.24 * s)
        self.add("AnvilHorn", horn, "metal.2", (x + 0.36 * s, y, z + 0.73), (0, math.pi / 2, math.pi / 4))

    def fire(self, loc, r=0.55, stones=8):
        x, y, z = loc
        for i in range(stones):
            a = i * math.tau / stones
            self.add("FireStone", blob(0.15, self.rng, jitter_amount=0.25, squash=(1.2, 1.0, 0.7)),
                     ("stone.4", "stone.2", "stone.1"), (x + math.cos(a) * r, y + math.sin(a) * r, z + 0.07))
        for i, c in enumerate(("accent.1", "accent.2", "accent.3")):
            a = i * math.tau / 3
            self.add("Ember", blob(0.13, self.rng, jitter_amount=0.3, squash=(1.0, 1.0, 0.6)), c,
                     (x + math.cos(a) * 0.15, y + math.sin(a) * 0.15, z + 0.06))


def front_steps(k, x, y_front, top, width, depth=0.32, colors=("stone.5", "stone.3", "stone.2")):
    """Steps descending toward -Y from a floor at height `top` at y_front."""
    n = max(int(round(top / 0.2)), 1)
    for i in range(n):
        h = top * (n - i) / (n + 0.0)
        k.box("Step", (width, depth, h), (x, y_front - depth * (i + 0.5), h / 2), colors, jit=0.01)


# --- woodcutter's lodge -----------------------------------------------------------------------

def lean_to(k):
    """Tier 1: a lean-to of rough planks against a log wall, a bedroll, a chopping block."""
    for x in (-1.4, 1.4):
        k.post("Post", 0.08, 0, 2.05, x, -1.0)
        k.post("Post", 0.08, 0, 1.15, x, 0.85)
    for i, z in enumerate((0.15, 0.45, 0.75)):
        k.log("WallLog", 3.1, 0.14, (0, 0.95, z), "x")
    a = math.atan2(-0.9, 2.0)
    for x, c in ((-1.15, "wood.3"), (-0.4, "wood.2"), (0.95, "neutral.4")):  # a gap, and a tarp patch
        w = 1.3 if c == "neutral.4" else 0.7
        k.box("RoofPlank", (w, 2.35, 0.06), (x, -0.08, 1.67), c, rot=(a, 0, 0), jit=0.02)
    k.box("Bedroll", (0.75, 1.5, 0.14), (0.55, 0.05, 0.07), ("accent.0", "accent.0", "wood.1"))
    k.chopping_block((-2.3, -1.9, 0))
    for i, (x, z) in enumerate(((2.1, 0.13), (2.38, 0.13), (2.24, 0.37))):
        k.log("Firewood", 1.0, 0.13, (x, -0.2, z), "y")


# --- smithy -----------------------------------------------------------------------------------

def forge(k, y, chimney_top, wide=1.0):
    """Stone hearth with glowing coals, a hood and a chimney, at the back (y)."""
    for course, z in enumerate((0.225, 0.675)):
        for i, x in enumerate((-0.55, 0.0, 0.55)):
            k.stone("Forge", (0.56 * wide, 1.0, 0.45), (x * wide, y, z))
    k.box("Coals", (1.2 * wide, 0.7, 0.08), (0, y - 0.05, 0.94), "accent.2")
    for i, c in enumerate(("accent.1", "accent.3", "accent.1")):
        k.add("Coal", blob(0.11, k.rng, jitter_amount=0.3, squash=(1.0, 1.0, 0.6)), c, ((i - 1) * 0.35, y, 1.0))
    k.add("Hood", prism(4, 0.85 * wide, 0.32, 1.2), ("stone.3", "stone.2", "stone.1"), (0, y + 0.1, 1.65),
          (0, 0, math.pi / 4))
    z = 2.25
    while z < chimney_top:
        k.stone("Chimney", (0.55, 0.55, 0.45), (0, y + 0.1, z + 0.225), ("stone.3", "stone.2", "stone.1", "stone.4"))
        z += 0.45
    return z


# --- fisher's hut -----------------------------------------------------------------------------

def drying_rack(k, x0, x1, y):
    for x in (x0, x1):
        k.post("RackPost", 0.05, 0, 1.55, x, y)
    k.box("RackBar", (x1 - x0 + 0.2, 0.06, 0.06), ((x0 + x1) / 2, y, 1.5), "wood.4")
    colors = ("metal.5", "leaves.4", "metal.6", "accent.7")
    n = 4
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        k.box("String", (0.015, 0.015, 0.25), (x, y, 1.36), "neutral.4")
        k.add("DryingFish", blob(0.06, k.rng, jitter_amount=0.1, squash=(0.7, 0.6, 2.6)), colors[i % 4],
              (x, y, 1.1))


# --- town hall --------------------------------------------------------------------------------

def notice_board(k, x, y, s=1.0, roofed=False):
    for dx in (-0.65 * s, 0.65 * s):
        k.post("BoardPost", 0.06, 0, 1.9 * s, x + dx, y)
    k.box("Board", (1.4 * s, 0.08, 0.9 * s), (x, y, 1.3 * s), ("wood.5", "wood.5", "wood.4"))
    for i, (dx, dz, c) in enumerate(((-0.35, 0.1, "neutral.6"), (0.05, -0.12, "neutral.7"), (0.38, 0.12, "wood.7"))):
        k.box("Notice", (0.28 * s, 0.1, 0.34 * s), (x + dx * s, y - 0.02, 1.3 * s + dz * s), c,
              rot=(0, k.rng.uniform(-0.15, 0.15), 0))
    if roofed:
        k.box("BoardRoof", (1.7 * s, 0.5, 0.06), (x, y, 1.95 * s), ("wood.2", "wood.2", "wood.1"))


# --- cottages (unlocked by the town hall, then upgraded like the houses) ----------------------


def loaves(k, x, y, z, n, spread=0.3):
    for i in range(n):
        k.add("Loaf", blob(0.13, k.rng, jitter_amount=0.12, squash=(1.5, 1.0, 0.7)), ("wood.6", "wood.5", "wood.4"),
              (x + (i - (n - 1) / 2) * spread, y + k.rng.uniform(-0.05, 0.05), z + 0.06))


def bread_oven(k, x, y, big=False):
    """A domed clay oven on a stone plinth, mouth facing -Y, with a flue (smoke) at the back."""
    s = 1.1 if big else 1.0
    for i, (ox, oy) in enumerate(((-0.4, -0.35), (0.4, -0.35), (-0.4, 0.35), (0.4, 0.35))):
        k.stone("Plinth", (0.8 * s, 0.7 * s, 0.6), (x + ox * s, y + oy * s, 0.3))
    k.add("Oven", blob(0.72 * s, k.rng, jitter_amount=0.06, squash=(1.0, 1.0, 0.72)),
          ("ore.copper", "ore.copper_dark", "stone.2"), (x, y, 0.62))
    k.box("OvenMouth", (0.5 * s, 0.2, 0.36 * s), (x, y - 0.66 * s, 0.82), "neutral.1")
    k.box("OvenEmbers", (0.36 * s, 0.1, 0.1), (x, y - 0.62 * s, 0.7), "accent.2")
    n = 6 if big else 3  # in the bakehouse the flue goes up through the roof
    base = 0.62 + 0.4 * s  # (on the dome, over the back of it)
    for i in range(n):
        k.stone("Flue", (0.28, 0.28, 0.3), (x, y + 0.35 * s, base + 0.15 + i * 0.28), ("stone.3", "stone.2", "stone.1"))
    k.empty("Smoke", (x, y + 0.35 * s, base + n * 0.28 + 0.2))


def hanging_sign(k, x, y, z, emblem):
    """A board on a bracket sticking out from a front wall (y), with an `emblem(k, x, y, z)` on it."""
    k.box("SignBracket", (0.05, 0.6, 0.05), (x, y - 0.3, z + 0.35), "metal.1")
    k.box("Sign", (0.6, 0.05, 0.42), (x, y - 0.5, z), ("wood.6", "wood.5", "wood.4"))
    k.box("SignBar", (0.5, 0.03, 0.03), (x, y - 0.5, z + 0.33), "metal.1")  # across under the bracket
    for dx in (-0.2, 0.2):
        k.box("SignChain", (0.015, 0.015, 0.12), (x + dx, y - 0.5, z + 0.26), "metal.1")
    emblem(k, x, y - 0.54, z)


def baker_villager():
    def hat(k, p):  # a tall white baker's hat
        attach(k, p["Head"], "HatBand", prism(10, 0.2, 0.2, 0.08), "neutral.6", (0, 0, 1.47))
        attach(k, p["Head"], "HatPuff", blob(0.2, k.rng, jitter_amount=0.12, squash=(1.1, 1.1, 0.9)), "neutral.7", (0, 0, 1.62))

    def extra(k, p):  # flour-dusted apron
        attach(k, p["Body"], "Apron", box((0.44, 0.04, 0.6)), ("neutral.7", "neutral.6", "neutral.6"), (0, -0.18, 0.66))

    def prop(k, p):  # a rolling pin
        attach(k, p["ArmR"], "PropPin", prism(8, 0.04, 0.04, 0.4), "wood.6", (0.32, -0.08, 0.5), (0, math.pi / 2, 0))

    villager("baker", "accent.7", "neutral.7", "wood.2", hat=hat, extra=extra, prop=prop)


def prospector_villager():
    def hat(k, p):  # a miner's helmet with a lamp
        attach(k, p["Head"], "Helmet", prism(10, 0.22, 0.17, 0.16), ("wood.5", "wood.4", "wood.3"), (0, 0, 1.5))
        attach(k, p["Head"], "HelmetBrim", prism(10, 0.26, 0.26, 0.03), "wood.4", (0, 0, 1.43))
        attach(k, p["Head"], "HelmetLamp", box((0.08, 0.05, 0.07)), "accent.3", (0, -0.24, 1.52))

    def extra(k, p):  # braces and a beard
        for sx in (-1, 1):
            attach(k, p["Body"], "Brace", box((0.06, 0.34, 0.5)), "wood.1", (sx * 0.13, 0, 0.8))
        attach(k, p["Head"], "Beard", box((0.32, 0.08, 0.16)), "neutral.5", (0, -0.2, 1.12))

    def prop(k, p):  # a small pick
        attach(k, p["ArmR"], "PropHandle", box((0.04, 0.45, 0.04)), ("wood.6", "wood.4", "wood.3"), (0.32, -0.18, 0.5))
        attach(k, p["ArmR"], "PropHead", box((0.04, 0.05, 0.34)), "metal.3", (0.32, -0.4, 0.5))

    villager("prospector", "accent.2", "accent.2", "accent.4", hat=hat, extra=extra, prop=prop)


# --- villagers --------------------------------------------------------------------------------

def pivot_box(k, name, size, pivot, offset, colors, parent=None):
    """A box whose object origin is `pivot` (the joint it rotates around), mesh shifted by `offset`."""
    bm = box(size)
    bmesh.ops.translate(bm, vec=Vector(offset), verts=bm.verts)
    obj = k.add(name, bm, colors, pivot)
    if parent:
        set_parent(obj, parent)
    return obj


def set_parent(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def villager(vid, shirt, sleeves, pants, skin="wood.7", hat=None, extra=None, prop=None):
    """A toy villager about 1.45 m tall. hat/extra/prop(k, parts) add the character's details."""
    reset()
    k = Kit("", 500 + sum(map(ord, vid)))
    bpy.context.view_layer.update()
    parts = {}
    parts["LegL"] = pivot_box(k, "LegL", (0.17, 0.2, 0.5), (-0.12, 0, 0.5), (0, 0, -0.25),
                              lambda f: "wood.0" if f.calc_center_median().z < -0.4 else pants)
    parts["LegR"] = pivot_box(k, "LegR", (0.17, 0.2, 0.5), (0.12, 0, 0.5), (0, 0, -0.25),
                              lambda f: "wood.0" if f.calc_center_median().z < -0.4 else pants)
    parts["Body"] = pivot_box(k, "Body", (0.5, 0.32, 0.56), (0, 0, 0.5), (0, 0, 0.28), (shirt, shirt, pants))
    bpy.context.view_layer.update()
    parts["Belt"] = pivot_box(k, "Belt", (0.52, 0.34, 0.07), (0, 0, 0.55), (0, 0, 0), "wood.1", parts["Body"])
    parts["Head"] = pivot_box(k, "Head", (0.38, 0.36, 0.36), (0, 0, 1.06), (0, 0, 0.19), skin, parts["Body"])
    bpy.context.view_layer.update()
    for sx, side in ((-1, "L"), (1, "R")):
        eye = make_named(k, f"Eye{side}", box((0.05, 0.02, 0.07)), "neutral.1", (sx * 0.08, -0.185, 1.29))
        set_parent(eye, parts["Head"])
    nose = make_named(k, "Nose", box((0.07, 0.07, 0.08)), "wood.6", (0, -0.2, 1.22))
    set_parent(nose, parts["Head"])
    for sx, side in ((-1, "L"), (1, "R")):
        arm = pivot_box(k, f"Arm{side}", (0.13, 0.15, 0.46), (sx * 0.32, 0, 1.0), (0, 0, -0.22), sleeves, parts["Body"])
        parts[f"Arm{side}"] = arm
        bpy.context.view_layer.update()
        hand = make_named(k, f"Hand{side}", box((0.12, 0.13, 0.11)), skin, (sx * 0.32, 0, 0.5))
        set_parent(hand, arm)
    bpy.context.view_layer.update()
    if hat:
        hat(k, parts)
    if extra:
        extra(k, parts)
    if prop:
        prop(k, parts)
    export(os.path.join("village", f"villager_{vid}"))


def make_named(k, name, bm, colors, loc, rot=(0, 0, 0)):
    paint(bm, colors if callable(colors) else k.tone(colors))
    return make_object(name, bm, loc, rot)


def attach(k, parent, name, bm, colors, loc, rot=(0, 0, 0)):
    obj = make_named(k, name, bm, colors, loc, rot)
    set_parent(obj, parent)
    return obj


def woodcutter_villager():
    def hat(k, p):  # green beanie with a turn-up
        attach(k, p["Head"], "Hat", box((0.4, 0.38, 0.16)), ("leaves.2", "leaves.2", "leaves.1"), (0, 0, 1.47))
        attach(k, p["Head"], "HatBand", box((0.42, 0.4, 0.06)), "leaves.1", (0, 0, 1.4))

    def extra(k, p):  # big brown beard
        attach(k, p["Head"], "Beard", box((0.36, 0.08, 0.2)), "wood.2", (0, -0.2, 1.12))

    def prop(k, p):  # axe held forward
        attach(k, p["ArmR"], "PropHandle", box((0.045, 0.6, 0.045)), ("wood.6", "wood.4", "wood.3"), (0.32, -0.25, 0.5))
        # the player's felling axe head, turned so its bit points up off the handle
        attach(k, p["ArmR"], "PropBlade", felling_head(), axe_head_shade, (0.32, -0.5, 0.5), (math.pi / 2, 0, 0))

    villager("woodcutter", "accent.1", "accent.0", "wood.1", hat=hat, extra=extra, prop=prop)


def smith_villager():
    def hat(k, p):  # dark hair in a bun
        attach(k, p["Head"], "Hair", box((0.4, 0.38, 0.12)), "neutral.1", (0, 0.02, 1.47))
        attach(k, p["Head"], "HairBack", box((0.4, 0.08, 0.3)), "neutral.1", (0, 0.19, 1.3))
        attach(k, p["Head"], "Bun", box((0.16, 0.14, 0.14)), "neutral.1", (0, 0.2, 1.48))

    def extra(k, p):  # leather apron
        attach(k, p["Body"], "Apron", box((0.44, 0.04, 0.62)), ("wood.2", "wood.2", "wood.1"), (0, -0.18, 0.66))

    def prop(k, p):  # hammer
        attach(k, p["ArmR"], "PropHandle", box((0.04, 0.45, 0.04)), ("wood.6", "wood.4", "wood.3"), (0.32, -0.18, 0.5))
        attach(k, p["ArmR"], "PropHead", box((0.1, 0.1, 0.2)), "metal.2", (0.32, -0.4, 0.5))

    villager("smith", "neutral.4", "wood.7", "neutral.2", hat=hat, extra=extra, prop=prop)


def fisher_villager():
    def hat(k, p):  # wide straw hat
        attach(k, p["Head"], "HatBrim", prism(10, 0.42, 0.42, 0.04), ("wood.7", "wood.6", "wood.5"), (0, 0, 1.45))
        attach(k, p["Head"], "HatCrown", prism(10, 0.2, 0.17, 0.16), ("wood.7", "wood.6", "wood.5"), (0, 0, 1.54))
        attach(k, p["Head"], "HatBand", prism(10, 0.205, 0.205, 0.04), "accent.0", (0, 0, 1.49))

    def extra(k, p):  # overall straps
        for sx in (-1, 1):
            attach(k, p["Body"], "Strap", box((0.07, 0.34, 0.5)), "accent.4", (sx * 0.14, 0, 0.8))

    def prop(k, p):  # fishing rod, tip up and forward
        attach(k, p["ArmR"], "PropRod", box((0.03, 0.03, 1.6)), "wood.5", (0.32, -0.45, 1.1), (-0.6, 0, 0))
        attach(k, p["ArmR"], "PropReel", prism(8, 0.05, 0.05, 0.05), "metal.3", (0.36, -0.05, 0.55), (0, math.pi / 2, 0))

    villager("fisher", "accent.5", "accent.5", "accent.4", hat=hat, extra=extra, prop=prop)


def mayor_villager():
    def hat(k, p):  # tall black hat with a gold band
        attach(k, p["Head"], "HatBrim", prism(10, 0.3, 0.3, 0.04), "neutral.1", (0, 0, 1.45))
        attach(k, p["Head"], "HatCrown", prism(10, 0.17, 0.17, 0.36), ("neutral.2", "neutral.1", "neutral.1"), (0, 0, 1.64))
        attach(k, p["Head"], "HatBand", prism(10, 0.175, 0.175, 0.06), "ore.gold", (0, 0, 1.5))

    def extra(k, p):  # grey moustache, a gold sash, coat tails
        attach(k, p["Head"], "Moustache", box((0.24, 0.05, 0.06)), "neutral.6", (0, -0.2, 1.16))
        attach(k, p["Body"], "Sash", box((0.12, 0.36, 0.7)), "accent.3", (0, 0, 0.8), (0, -0.75, 0))
        attach(k, p["Body"], "CoatTail", box((0.46, 0.06, 0.32)), "accent.6", (0, 0.17, 0.42))

    def prop(k, p):  # a rolled-up scroll
        attach(k, p["ArmR"], "PropScroll", prism(8, 0.05, 0.05, 0.32), ("neutral.7", "neutral.6", "neutral.6"),
               (0.32, -0.08, 0.5), (0, math.pi / 2, 0))

    villager("mayor", "accent.6", "accent.6", "neutral.1", hat=hat, extra=extra, prop=prop)


# --- props ------------------------------------------------------------------------------------

def bench():
    reset()
    k = Kit("", 601)
    for x in (-0.7, 0.7):
        k.box("Leg", (0.12, 0.4, 0.42), (x, 0, 0.21), ("wood.3", "wood.3", "wood.2"))
    k.box("Seat", (1.8, 0.45, 0.08), (0, 0, 0.46), ("wood.6", "wood.5", "wood.4"))
    k.box("Back", (1.8, 0.06, 0.3), (0, 0.24, 0.78), ("wood.6", "wood.5", "wood.4"), rot=(-0.15, 0, 0))
    for x in (-0.7, 0.7):
        k.box("BackPost", (0.08, 0.06, 0.45), (x, 0.22, 0.65), "wood.3")
    export(os.path.join("village", "props", "bench"))


def lamp_post():
    reset()
    k = Kit("", 602)
    k.post("Post", 0.07, 0, 2.6, 0, 0, ("wood.2", "wood.2", "wood.1"))
    k.box("Arm", (0.5, 0.06, 0.06), (0.22, 0, 2.5), "wood.2")
    k.box("Lamp", (0.2, 0.2, 0.26), (0.42, 0, 2.3), ("neutral.1", "accent.3", "neutral.1"))
    k.box("Cap", (0.26, 0.26, 0.05), (0.42, 0, 2.45), "neutral.1")
    export(os.path.join("village", "props", "lamp_post"))


def lamp_post_rustic():
    """The far roads' lamp: a rough leaning log with a bracket, a lantern hanging from it on a
    short chain, and a few stones heaped round its foot."""
    reset()
    k = Kit("", 606)
    k.add("Post", prism(7, 0.09, 0.07, 2.45), ("wood.3", "wood.3", "wood.2"), (0, 0, 1.22), (0.03, -0.02, 0))
    k.box("Arm", (0.6, 0.06, 0.07), (0.27, 0, 2.3), "wood.3")
    k.box("Brace", (0.38, 0.05, 0.05), (0.14, 0, 2.12), "wood.2", rot=(0, 0.75, 0))
    k.box("Chain", (0.02, 0.02, 0.16), (0.5, 0, 2.19), "neutral.1")
    k.add("Cap", prism(4, 0.13, 0.03, 0.1), ("neutral.1", "neutral.1", "neutral.1"), (0.5, 0, 2.07), (0, 0, math.pi / 4))
    k.box("Lamp", (0.15, 0.15, 0.2), (0.5, 0, 1.92), ("neutral.1", "accent.3", "neutral.1"))
    k.box("Base", (0.18, 0.18, 0.03), (0.5, 0, 1.8), "neutral.1")
    for i, (x, y, s) in enumerate(((0.16, 0.05, 0.16), (-0.12, 0.12, 0.13), (0.02, -0.16, 0.14), (-0.14, -0.08, 0.1))):
        k.box("Stone", (s, s * 0.9, s * 0.7), (x, y, s * 0.3), ("neutral.4", "neutral.3", "neutral.3"),
              rot=(0, 0, i * 1.3), jit=0.02)
    export(os.path.join("village", "props", "lamp_post_rustic"))


def noticeboard():
    """The village noticeboard (plans/projects.md): a plank board on two posts under a little
    shingle roof, a few paper notes pinned on it. Faces Blender -Y (Godot +Z)."""
    reset()
    k = Kit("", 608)
    for x in (-0.85, 0.85):
        k.post("Post", 0.07, 0, 2.52, x, 0, ("wood.3", "wood.3", "wood.2"))
    k.box("Board", (1.75, 0.07, 1.05), (0, 0, 1.45), ("wood.5", "wood.4", "wood.3"), jit=0.004)
    k.box("Frame", (1.85, 0.09, 0.08), (0, 0, 2.0), "wood.2")
    k.box("Frame", (1.85, 0.09, 0.08), (0, 0, 0.9), "wood.2")
    for x, side in ((0, 1), (0, -1)):
        k.box("Roof", (2.1, 0.42, 0.04), (0, side * 0.19, 2.42), ("wood.2", "wood.1", "wood.1"), rot=(-side * 0.55, 0, 0))
    k.box("Ridge", (2.15, 0.07, 0.07), (0, 0, 2.53), "wood.1")
    notes = ((-0.55, 1.68, 0.36, 0.28, 0.05), (-0.05, 1.62, 0.3, 0.38, -0.08), (0.48, 1.7, 0.34, 0.26, 0.1),
             (-0.42, 1.18, 0.32, 0.3, -0.06), (0.22, 1.2, 0.4, 0.3, 0.04), (0.66, 1.14, 0.22, 0.28, -0.12))
    for i, (x, z, w, h, rot) in enumerate(notes):
        paper = ("neutral.7", "neutral.6", "neutral.6") if i % 2 else ("wood.7", "wood.6", "wood.6")
        k.box("Note", (w, 0.01, h), (x, -0.045, z), paper, rot=(0, rot, 0))
        k.box("Pin", (0.025, 0.02, 0.025), (x, -0.055, z + h * 0.4), "accent.3")
    export(os.path.join("village", "props", "noticeboard"))


def planter():
    """A wooden planter full of flowers (the flower boxes project): plank box, dark soil, leafy
    clumps and bright flower heads."""
    reset()
    k = Kit("", 609)
    rng = random.Random(609)
    k.box("Box", (1.1, 0.42, 0.4), (0, 0, 0.2), ("wood.5", "wood.4", "wood.3"), jit=0.005)
    for y in (-0.21, 0.21):
        k.box("Rim", (1.16, 0.05, 0.05), (0, y, 0.41), "wood.2")
    k.box("Soil", (1.0, 0.34, 0.04), (0, 0, 0.39), ("wood.0", "wood.0", "wood.0"))
    for i in range(6):
        x = -0.42 + i * 0.17 + rng.uniform(-0.03, 0.03)
        k.add("Leaves", blob(0.13, rng, squash=(1, 0.8, 0.7)), ("leaves.4", "leaves.3", "leaves.2"), (x, rng.uniform(-0.06, 0.06), 0.48))
        c = rng.choice(("accent.5", "accent.6", "accent.2", "accent.4"))
        for j in range(2):
            k.add("Flower", blob(0.05, rng, squash=(1, 1, 0.6)), (c, c, c),
                  (x + rng.uniform(-0.06, 0.06), rng.uniform(-0.1, 0.1), 0.53 + rng.uniform(0, 0.04)))
    export(os.path.join("village", "props", "planter"))


def well():
    """The village well: a round stone wall, two posts and a little roof, a crank with the rope
    down to a bucket. Origin at the middle, on the ground."""
    reset()
    k = Kit("", 610)
    rng = random.Random(610)
    n = 10
    for i in range(n):
        a = i * math.tau / n
        k.box("Stone", (0.42, 0.24, 0.7), (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.35),
              ("stone.5", "stone.4", "stone.3"), rot=(0, 0, a + math.pi / 2), jit=0.02)
    k.add("Water", prism(10, 0.52, 0.52, 0.02), ("accent.4", "accent.4", "accent.4"), (0, 0, 0.45))
    for x in (-0.72, 0.72):
        k.post("Post", 0.06, 0.6, 2.26, x, 0, ("wood.3", "wood.3", "wood.2"))
    k.box("Crank", (1.5, 0.08, 0.08), (0, 0, 1.55), "wood.2")
    k.box("Handle", (0.06, 0.25, 0.06), (0.8, -0.12, 1.55), "wood.2")
    k.box("Rope", (0.02, 0.02, 0.6), (0, 0, 1.22), ("neutral.5", "neutral.5", "neutral.4"))
    k.add("Bucket", prism(8, 0.12, 0.14, 0.2), ("wood.5", "wood.4", "wood.3"), (0, 0, 0.84))
    for side in (1, -1):
        k.box("Roof", (1.8, 0.55, 0.04), (0, side * 0.24, 2.12), ("wood.2", "wood.1", "wood.1"), rot=(-side * 0.6, 0, 0))
    k.box("Ridge", (1.85, 0.07, 0.07), (0, 0, 2.27), "wood.1")
    export(os.path.join("village", "props", "well"))


def fountain():
    """The square's fountain: a low eight-sided stone basin of water, a column with a bowl on top
    that spills into it. Origin at the middle, on the ground."""
    reset()
    k = Kit("", 611)
    n = 8
    for i in range(n):
        a = i * math.tau / n
        k.box("Basin", (0.95, 0.22, 0.5), (math.cos(a) * 1.25, math.sin(a) * 1.25, 0.25),
              ("stone.6", "stone.5", "stone.4"), rot=(0, 0, a + math.pi / 2), jit=0.01)
    k.add("Water", prism(8, 1.2, 1.2, 0.03), ("accent.5", "accent.4", "accent.4"), (0, 0, 0.38), (0, 0, math.pi / 8))
    k.add("Column", prism(8, 0.18, 0.14, 1.1), ("stone.5", "stone.4", "stone.3"), (0, 0, 0.75))
    k.add("Bowl", prism(8, 0.25, 0.5, 0.18), ("stone.6", "stone.5", "stone.4"), (0, 0, 1.36))
    k.add("Spout", prism(6, 0.06, 0.04, 0.25), ("stone.6", "stone.5", "stone.4"), (0, 0, 1.55))
    export(os.path.join("village", "props", "fountain"))


def lantern():
    """The lantern you carry (models/lantern.glb): a small iron-framed lantern, origin at the top
    of its handle ring, where it hangs from the belt (or the hand) and swings from."""
    reset()
    k = Kit("", 607)
    iron = ("neutral.4", "neutral.3", "neutral.2")
    k.add("Ring", prism(8, 0.035, 0.035, 0.012), iron, (0, 0, -0.03), (math.pi / 2, 0, 0))
    k.add("Cap", prism(6, 0.075, 0.02, 0.06), iron, (0, 0, -0.08))
    k.add("Rim", prism(6, 0.075, 0.075, 0.015), iron, (0, 0, -0.115))
    k.add("Lamp", prism(6, 0.06, 0.06, 0.13), ("neutral.3", "accent.3", "accent.3"), (0, 0, -0.19))
    for i in range(3):
        a = i * math.tau / 3 + math.pi / 6
        k.box("Bar", (0.012, 0.012, 0.14), (math.cos(a) * 0.066, math.sin(a) * 0.066, -0.19), iron)
    k.add("Base", prism(6, 0.08, 0.08, 0.025), iron, (0, 0, -0.265))
    export("lantern")


def barrel_prop():
    reset()
    k = Kit("", 603)
    k.barrel((0, 0, 0))
    export(os.path.join("village", "props", "barrel"))


def crate_prop():
    reset()
    k = Kit("", 604)
    k.crate((0, 0, 0), 0.65)
    k.crate((0.1, 0.05, 0.56), 0.45)
    export(os.path.join("village", "props", "crates"))


def signpost():
    """Two arrow boards on a post: one back to the clearing, one into the village."""
    reset()
    k = Kit("", 605)
    k.post("Post", 0.07, 0, 2.1, 0, 0, ("wood.3", "wood.3", "wood.2"))
    for z, rot, c in ((1.85, 0.5, "wood.6"), (1.5, -2.4, "wood.5")):
        bm = box((0.9, 0.05, 0.22))
        for v in bm.verts:  # point one end
            if v.co.x > 0.4:
                v.co.z *= 0.1
                v.co.x += 0.12
        k.add("Arrow", bm, (c, c, "wood.4"), (math.cos(rot) * 0.4, math.sin(rot) * 0.4, z), (0, 0, rot))
    export(os.path.join("village", "props", "signpost"))


# --- the dog (plans/dog.md) ---------------------------------------------------------------------

## Three breeds sharing one set of parts, so the game poses them all the same way. Sizes in metres:
## body length / width / height, leg length (ground to the body's underside), head size, snout
## length, and the shape of the ears and tail.
DOG_BREEDS = {
    "terrier": {"body": (0.40, 0.20, 0.21), "leg": 0.16, "leg_w": 0.065, "head": 0.18, "snout": 0.09,
                "ears": "folded", "tail": "up", "fur": 0.012, "beard": True, "ruff": False},
    "shepherd": {"body": (0.62, 0.25, 0.27), "leg": 0.31, "leg_w": 0.08, "head": 0.22, "snout": 0.16,
                 "ears": "upright", "tail": "low", "fur": 0.006, "beard": False, "ruff": False},
    "fluffy": {"body": (0.76, 0.36, 0.37), "leg": 0.28, "leg_w": 0.13, "head": 0.29, "snout": 0.13,
               "ears": "floppy", "tail": "bushy", "fur": 0.025, "beard": False, "ruff": True},
}
## Coats per breed: main, under (belly, chest), muzzle, ears, points (paws, lower legs), tail tip,
## and a saddle over the back (or None).
DOG_COATS = {
    "terrier": {
        "wheaten": dict(main="wood.6", under="wood.7", muzzle="wood.7", ears="wood.5", points="wood.6", tip="wood.7", saddle=None),
        "grey": dict(main="neutral.4", under="neutral.5", muzzle="neutral.5", ears="neutral.3", points="neutral.4", tip="neutral.5", saddle=None),
        "black_tan": dict(main="neutral.1", under="wood.5", muzzle="wood.5", ears="neutral.1", points="wood.5", tip="neutral.1", saddle=None),
    },
    "shepherd": {
        "saddle": dict(main="wood.5", under="wood.6", muzzle="neutral.1", ears="neutral.1", points="wood.5", tip="neutral.1", saddle="neutral.1"),
        "brown": dict(main="wood.3", under="wood.5", muzzle="wood.5", ears="wood.2", points="wood.6", tip="wood.6", saddle=None),
        "cream": dict(main="wood.7", under="neutral.6", muzzle="wood.7", ears="wood.6", points="neutral.6", tip="neutral.6", saddle=None),
    },
    "fluffy": {
        "tricolour": dict(main="neutral.1", under="neutral.6", muzzle="neutral.6", ears="neutral.1", points="wood.4", tip="neutral.6", saddle=None),
        "golden": dict(main="wood.6", under="wood.7", muzzle="wood.7", ears="wood.5", points="wood.7", tip="wood.7", saddle=None),
        "white": dict(main="neutral.6", under="neutral.7", muzzle="neutral.7", ears="neutral.5", points="neutral.6", tip="neutral.7", saddle=None),
    },
}


def dog_part(k, name, size, pivot, offset, choose, parent=None, jit=0.0, taper=0.0):
    """A box whose origin is its joint `pivot`, the mesh shifted by `offset`, coloured by choose(face).
    `jit` roughens it (fur), `taper` narrows its far end along +Y/-Y offset (a snout, a tail)."""
    bm = box(size)
    if taper:
        half = size[1] / 2
        for v in bm.verts:
            t = (v.co.y + half) / (2 * half)  # 0 at -Y, 1 at +Y
            far = t if offset[1] > 0 else 1 - t
            v.co.x *= 1 - taper * far
            v.co.z *= 1 - taper * 0.6 * far
    if jit:
        for v in bm.verts:
            v.co += Vector((k.rng.uniform(-jit, jit), k.rng.uniform(-jit, jit), k.rng.uniform(-jit, jit)))
    bmesh.ops.translate(bm, vec=Vector(offset), verts=bm.verts)
    paint(bm, choose)
    obj = make_object(name, bm, pivot)
    if parent:
        set_parent(obj, parent)
    bpy.context.view_layer.update()
    return obj


def dog(breed, coat_name):
    """A toy dog in parts the game poses in code (scripts/dog.gd), facing Blender -Y:
    Body (origin at its middle), Head (at the neck) with Jaw (at its hinge, LanternSocket at its
    tip), EarL / EarR (on top of the head), Tail (at the rump), LegFL / LegFR / LegBL / LegBR (at
    the shoulders and hips). Written to models/dogs/dog_<breed>_<coat>.glb."""
    reset()
    b = DOG_BREEDS[breed]
    c = DOG_COATS[breed][coat_name]
    k = Kit("", 700 + sum(map(ord, breed + coat_name)))
    bpy.context.view_layer.update()
    length, width, height = b["body"]
    leg = b["leg"]
    bz = leg + height / 2  # the body's middle
    fur = b["fur"]

    def body_colour(f):
        n = f.normal
        if n.z > 0.55:
            return c["saddle"] or c["main"]
        if n.z < -0.4 or n.y < -0.7:
            return c["under"]
        return c["main"]

    body = dog_part(k, "Body", (width, length, height), (0, 0, bz), (0, 0, 0), body_colour, jit=fur)
    if b["ruff"]:  # a thick collar of fur round the neck
        dog_part(k, "Ruff", (width * 1.12, length * 0.28, height * 1.05), (0, -length * 0.36, bz + height * 0.06),
                 (0, 0, 0), lambda f: c["under"] if f.normal.y < -0.5 or f.normal.z < -0.4 else c["main"], body, jit=fur * 1.4)

    # legs: pivots inside the body at the shoulders and hips, reaching the ground
    for fb, along in (("F", -1), ("B", 1)):
        for side, sx in (("L", -1), ("R", 1)):
            pivot = (sx * width * 0.3, along * length * 0.36, leg + height * 0.2)
            reach = pivot[2]
            lw = b["leg_w"]
            dog_part(k, f"Leg{fb}{side}", (lw, lw * 1.1, reach), pivot, (0, 0, -reach / 2),
                     lambda f, reach=reach: c["points"] if f.calc_center_median().z < -reach * 0.62 else c["main"],
                     body, jit=fur * 0.5)

    # head: on a short neck at the front top of the body
    hs = b["head"]
    neck = (0, -length * 0.42, bz + height * 0.28)
    head = dog_part(k, "Head", (hs * 0.95, hs, hs * 0.9), neck, (0, -hs * 0.38, hs * 0.42),
                    lambda f: c["muzzle"] if f.normal.y < -0.7 and breed == "fluffy" else c["main"], body, jit=fur * 0.6)
    face_y = neck[1] - hs * 0.38 - hs / 2  # the front of the head
    sl = b["snout"]
    snout_z = neck[2] + hs * 0.3
    dog_part(k, "Snout", (hs * 0.55, sl, hs * 0.3), (0, face_y, snout_z), (0, -sl / 2, 0),
             lambda f: c["muzzle"], head, taper=0.25)
    dog_part(k, "Nose", (hs * 0.2, hs * 0.1, hs * 0.13), (0, face_y - sl + hs * 0.02, snout_z + hs * 0.11),
             (0, 0, 0), lambda f: "neutral.0", head)
    jaw = dog_part(k, "Jaw", (hs * 0.45, sl * 0.9, hs * 0.12), (0, face_y + hs * 0.05, snout_z - hs * 0.17),
                   (0, -sl * 0.45 - hs * 0.05, 0), lambda f: c["muzzle"], head, taper=0.2)
    socket = bpy.data.objects.new("LanternSocket", None)
    bpy.context.collection.objects.link(socket)
    socket.location = (0, face_y - sl * 0.75, snout_z - hs * 0.15)
    set_parent(socket, jaw)
    if b["beard"]:
        dog_part(k, "Beard", (hs * 0.5, sl * 0.8, hs * 0.18), (0, face_y - sl * 0.45, snout_z - hs * 0.24),
                 (0, 0, 0), lambda f: c["muzzle"], jaw, jit=fur * 1.5)
    for side, sx in (("L", -1), ("R", 1)):
        dog_part(k, f"Eye{side}", (hs * 0.13, hs * 0.04, hs * 0.13),
                 (sx * hs * 0.24, face_y + hs * 0.01, neck[2] + hs * 0.55), (0, 0, 0), lambda f: "neutral.0", head)
        top = (sx * hs * 0.3, neck[1] - hs * 0.28, neck[2] + hs * 0.82)
        if b["ears"] == "upright":
            ear = dog_part(k, f"Ear{side}", (hs * 0.28, hs * 0.08, hs * 0.5), top, (0, 0, hs * 0.22),
                           lambda f: c["ears"], head, taper=0.0)
            for v in ear.data.vertices:  # to a point
                if v.co.z > hs * 0.3:
                    v.co.x *= 0.2
        elif b["ears"] == "floppy":
            dog_part(k, f"Ear{side}", (hs * 0.1, hs * 0.38, hs * 0.55), (sx * hs * 0.48, neck[1] - hs * 0.35, neck[2] + hs * 0.75),
                     (sx * hs * 0.02, 0, -hs * 0.28), lambda f: c["ears"], head, jit=fur * 0.6)
        else:  # folded: small flaps tipping forward
            dog_part(k, f"Ear{side}", (hs * 0.3, hs * 0.08, hs * 0.26), top, (0, -hs * 0.06, hs * 0.1),
                     lambda f: c["ears"], head)
    # tail: from the rump, angled by breed (the game wags it round its pivot)
    rump = (0, length * 0.48, bz + height * 0.3)
    tl = {"up": length * 0.35, "low": length * 0.55, "bushy": length * 0.36}[b["tail"]]
    tw = {"up": 0.05, "low": 0.06, "bushy": 0.11}[b["tail"]]
    tail = dog_part(k, "Tail", (tw, tl, tw), rump, (0, tl / 2, 0),
                    lambda f, tl=tl: c["tip"] if f.calc_center_median().y > tl * 0.7 else c["main"],
                    body, jit=fur * (1.5 if b["tail"] == "bushy" else 0.3), taper=0.0 if b["tail"] == "bushy" else 0.4)
    tail.rotation_euler = ({"up": (math.radians(55), 0, 0), "low": (math.radians(-50), 0, 0),
                            "bushy": (math.radians(20), 0, 0)}[b["tail"]])
    export(os.path.join("dogs", f"dog_{breed}_{coat_name}"))


def _doghouse(name, walls, roof, trim, sign=False):
    """A doghouse big enough for the big fluffy dog: plank walls with a door hole in the front
    (Blender -Y), a pitched roof. `sign`: a board over the door, with a SignText empty where the
    game writes his name."""
    reset()
    k = Kit("", 640 + len(name))
    w, d, h = 1.1, 1.3, 0.8      # width, depth, wall height
    door_w, door_h = 0.5, 0.62
    t = 0.06                      # plank thickness
    k.box("Floor", (w, d, 0.06), (0, 0, 0.03), (trim, trim, trim))
    k.box("Back", (w, t, h), (0, d / 2 - t / 2, h / 2), walls, jit=0.004)
    for sx in (-1, 1):
        k.box("Side", (t, d, h), (sx * (w / 2 - t / 2), 0, h / 2), walls, jit=0.004)
        side_w = (w - door_w) / 2
        k.box("Front", (side_w, t, h), (sx * (door_w / 2 + side_w / 2), -d / 2 + t / 2, h / 2), walls, jit=0.004)
    k.box("Lintel", (door_w, t, h - door_h), (0, -d / 2 + t / 2, door_h + (h - door_h) / 2), walls)
    for sy in (-1, 1):  # gable ends: wedges filling the roof's triangle front and back
        bm = box((w, t, 0.4))
        for v in bm.verts:
            if v.co.z > 0:
                v.co.x = 0.0
        k.add("Gable", bm, walls, (0, sy * (d / 2 - t / 2), h + 0.2))
    for sx in (-1, 1):  # two roof slabs meeting over the ridge
        k.box("Roof", (w * 0.62, d + 0.2, 0.05), (sx * w * 0.25, 0, h + 0.22), (roof, roof, trim),
              rot=(0, sx * math.radians(34), 0))
    k.box("Ridge", (0.08, d + 0.22, 0.08), (0, 0, h + 0.4), (trim, trim, trim))
    if sign:
        k.box("Sign", (0.62, 0.04, 0.16), (0, -d / 2 - 0.03, h + 0.12), ("wood.6", "wood.6", "wood.5"))
        mark = bpy.data.objects.new("SignText", None)
        bpy.context.collection.objects.link(mark)
        mark.location = (0, -d / 2 - 0.06, h + 0.12)
    export(os.path.join("village", "props", name))


def doghouse():
    _doghouse("doghouse", ("wood.4", "wood.3", "wood.2", "wood.5"), "wood.2", "wood.1")


def doghouse_painted():
    _doghouse("doghouse_painted", ("wood.7", "wood.6", "wood.5"), "accent.0", "wood.3", sign=True)


def doghouse_porch():
    """A little deck in front of the doghouse's door, with a post at each front corner."""
    reset()
    k = Kit("", 646)
    for i in range(4):
        k.box("Board", (1.2, 0.14, 0.05), (0, -0.3 + i * 0.16, 0.06), ("wood.5", "wood.4", "wood.3"), jit=0.006)
    for sx in (-1, 1):
        k.post("Post", 0.035, 0, 0.5, sx * 0.55, -0.3, ("wood.4", "wood.3", "wood.2"))
    k.box("Rail", (1.15, 0.05, 0.05), (0, -0.3, 0.5), ("wood.4", "wood.3", "wood.2"))
    export(os.path.join("village", "props", "doghouse_porch"))


def dog_bowl():
    reset()
    k = Kit("", 647)
    k.add("Bowl", prism(8, 0.16, 0.2, 0.08), ("accent.1", "accent.0", "accent.0"), (0, 0, 0.04))
    k.add("Water", prism(8, 0.16, 0.16, 0.01), ("accent.5", "accent.5", "accent.5"), (0, 0, 0.07))
    export(os.path.join("village", "props", "dog_bowl"))


def dog_blanket():
    """A folded, checked blanket for him to lie on."""
    reset()
    k = Kit("", 648)
    bm = box((0.8, 0.62, 0.06))
    paint(bm, lambda f: "accent.6" if int((f.calc_center_median().x + 0.4) / 0.2) % 2 else "neutral.6")
    make_object("Blanket", bm, (0, 0, 0.03))
    export(os.path.join("village", "props", "dog_blanket"))


def landslide_mud():
    """The landslide's fan of mud and stones over the road east (plans/market.md): a long low
    mound, highest at its uphill side (Blender +Y), spilling down across the road. 12 m by 9 m."""
    reset()
    k = Kit("", 660)
    rng = k.rng
    for i in range(9):  # overlapping squashed lumps make the fan
        x = rng.uniform(-4.5, 4.5)
        y = rng.uniform(-2.5, 3.0)
        r = rng.uniform(1.8, 2.8) * (1.0 + 0.2 * (y + 2.5) / 5.5)
        bm = blob(r, rng, 0.2, (1.4, 1.0, 0.24), subdiv=2)
        k.add("Mud", bm, ("terrain.dirt", "wood.3", "wood.2", "wood.4"), (x, y, r * 0.12 + (y + 2.5) * 0.08))
    for i in range(14):  # stones and broken branches in the mud
        x, y = rng.uniform(-5, 5), rng.uniform(-3, 3)
        s = rng.uniform(0.18, 0.45)
        k.add("Stone", blob(s, rng, 0.3, (1.0, 1.0, 0.7)), ("stone.4", "stone.3", "stone.2"), (x, y, 0.5 + (y + 3) * 0.12))
    for i in range(4):
        x, y = rng.uniform(-4, 4), rng.uniform(-2, 2.5)
        k.log("Branch", rng.uniform(1.0, 2.2), 0.07, (x, y, 0.7 + (y + 3) * 0.1))
    export(os.path.join("village", "props", "landslide_mud"))


def retaining_wall():
    """Timber cribbing that holds the slope back above the road east once the slide is cleared:
    stacked logs along the uphill side (Blender +Y is the slope), cross-ties into it every few
    metres, the face leaning back a little. 12 m long, 2 m high."""
    reset()
    k = Kit("", 661)
    length, rows, r = 12.0, 6, 0.16
    for i in range(rows):
        z = r + i * r * 1.9
        lean = i * 0.12  # each row set a little further back into the slope
        k.log("Log", length + k.rng.uniform(-0.2, 0.2), r, (k.rng.uniform(-0.1, 0.1), lean, z))
        if i % 2 == 1:
            for x in [-5.0, -2.5, 0.0, 2.5, 5.0]:
                k.log("Tie", 1.6, r * 0.85, (x, lean + 0.7, z + r * 0.9), axis="y")
    for x in [-5.6, 5.6]:  # stakes at the ends
        k.post("Stake", 0.09, 0.0, 2.3, x, -0.15, ("wood.3", "wood.2", "wood.1"))
    export(os.path.join("village", "props", "retaining_wall"))


def market_stall():
    """The market stall in the square (plans/market.md): a plank counter on trestles, four posts
    holding a striped awning, crates of goods on the counter and beside it. Faces Blender -Y (Godot
    +Z, the customer's side); the stallkeeper stands behind it, at +Y. 3 m wide."""
    reset()
    k = Kit("", 670)
    w, d = 3.0, 1.0
    wood = ("wood.5", "wood.4", "wood.3")
    k.box("Counter", (w, d * 0.7, 0.08), (0, -0.1, 0.95), ("wood.6", "wood.5", "wood.4"), jit=0.004)
    k.box("Front", (w, 0.05, 0.85), (0, -0.45, 0.5), ("wood.4", "wood.4", "wood.3", "wood.5"), jit=0.004)
    for sx in (-1, 1):
        k.box("Trestle", (0.08, d * 0.6, 0.9), (sx * (w / 2 - 0.15), -0.1, 0.45), wood)
    for sx in (-1, 1):
        for sy, h in ((-1, 2.3), (1, 2.6)):
            k.post("Post", 0.05, 0, h, sx * (w / 2 - 0.05), sy * (d / 2 + 0.1), ("wood.3", "wood.3", "wood.2"))
    for i in range(8):  # the awning: alternating stripes, sloping down toward the customer
        x = -w / 2 + (i + 0.5) * (w / 8)
        c = "accent.1" if i % 2 == 0 else "neutral.6"
        k.box("Awning", (w / 8 + 0.005, d + 0.6, 0.03), (x, -0.05, 2.47), (c, c, c), rot=(math.radians(10), 0, 0))
    for i in range(8):  # scalloped edge
        x = -w / 2 + (i + 0.5) * (w / 8)
        c = "accent.1" if i % 2 == 0 else "neutral.6"
        k.box("Flap", (w / 8 - 0.02, 0.02, 0.16), (x, -0.86, 2.27), (c, c, c))
    goods = [("Apples", "accent.0"), ("Bread", "wood.6"), ("Fish", "stone.5"), ("Ore", "ore.copper")]
    for i, (name, col) in enumerate(goods):  # crates of goods on the counter
        x = -1.05 + i * 0.7
        k.box("Crate", (0.5, 0.4, 0.22), (x, -0.05, 1.1), ("wood.4", "wood.3", "wood.2"))
        for j in range(5):
            k.add(name, blob(0.07, k.rng, 0.2, (1, 1, 0.8)), (col, col, col),
                  (x + k.rng.uniform(-0.16, 0.16), -0.05 + k.rng.uniform(-0.1, 0.1), 1.24))
    k.barrel((1.9, 0.2, 0))
    k.crate((-2.0, 0.1, 0), 0.55)
    k.crate((-1.95, 0.15, 0.5), 0.4)
    export(os.path.join("village", "props", "market_stall"))


def stallkeeper_villager():
    def hat(k, p):  # a headscarf
        attach(k, p["Head"], "Scarf", box((0.4, 0.38, 0.14)), "accent.2", (0, 0.01, 1.4))
        attach(k, p["Head"], "Knot", box((0.1, 0.08, 0.1)), "accent.2", (0, 0.2, 1.36))

    def extra(k, p):  # a green apron
        attach(k, p["Body"], "Apron", box((0.44, 0.04, 0.5)), "leaves.3", (0, -0.17, 0.72))

    villager("stallkeeper", "accent.5", "accent.5", "wood.2", hat=hat, extra=extra)


def trader_cart():
    """The travelling trader's cart and horse (plans/market.md), in parts the game moves: Cart
    (the bed, canopy and goods), WheelL / WheelR (pivots on the axle), Horse (body) with Head and
    LegFL / LegFR / LegBL / LegBR (pivots at the shoulders and hips). Faces Blender -Y (the horse in
    front); origin on the ground under the axle."""
    reset()
    k = Kit("", 680)
    bpy.context.view_layer.update()
    wood = ("wood.5", "wood.4", "wood.3")
    cart = pivot_box(k, "Cart", (1.4, 2.2, 0.12), (0, 0, 0.75), (0, 0, 0), ("wood.5", "wood.4", "wood.3"))
    bpy.context.view_layer.update()  # (children take the parent's world matrix: it must be current)
    for sx in (-1, 1):
        attach(k, cart, "Side", box((0.06, 2.2, 0.4)), wood, (sx * 0.67, 0, 0.98))
    attach(k, cart, "Back", box((1.4, 0.06, 0.4)), wood, (0, 1.08, 0.98))
    for sx in (-1, 1):  # hoops and a canvas canopy
        for y in (-0.9, 0.0, 0.9):
            attach(k, cart, "Hoop", box((0.05, 0.05, 1.0)), "wood.3", (sx * 0.66, y, 1.6))
    attach(k, cart, "Canopy", box((1.5, 2.1, 0.06)), ("neutral.6", "wood.7", "wood.6"), (0, 0, 2.12))
    for sx in (-1, 1):
        attach(k, cart, "CanopySide", box((0.04, 2.1, 0.5)), ("wood.7", "neutral.6", "wood.6"), (sx * 0.73, 0, 1.85))
    for i, col in enumerate(["accent.0", "accent.3", "leaves.4", "accent.6"]):  # bundles of goods
        attach(k, cart, "Goods", box((0.38, 0.38, 0.3)), (col, col, col), (-0.4 + (i % 2) * 0.8, 0.5 - (i // 2) * 0.6, 0.98))
    for sx in (-1, 1):  # shafts reaching forward to the horse
        attach(k, cart, "Shaft", box((0.06, 1.8, 0.06)), "wood.3", (sx * 0.42, -1.9, 0.85))
    for side, sx in (("L", -1), ("R", 1)):
        rim = prism(12, 0.5, 0.5, 0.08)
        bmesh.ops.rotate(rim, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=rim.verts)
        wh = k.add(f"Wheel{side}", rim, ("wood.3", "wood.3", "wood.2"), (sx * 0.78, 0.2, 0.5))
        bpy.context.view_layer.update()
        for a in range(4):  # spokes, so the turning shows
            attach(k, wh, "Spoke", box((0.1, 0.06, 0.9)), "wood.6", (sx * 0.78, 0.2, 0.5), (math.pi / 4 * a, 0, 0))
    horse = pivot_box(k, "Horse", (0.5, 1.4, 0.6), (0, -2.9, 1.25), (0, 0, 0), ("wood.2", "wood.2", "wood.1"))
    bpy.context.view_layer.update()
    head = pivot_box(k, "Head", (0.28, 0.65, 0.3), (0, -3.5, 1.5), (0, -0.25, 0.25), ("wood.2", "wood.2", "wood.1"), horse)
    bpy.context.view_layer.update()
    attach(k, head, "Mane", box((0.08, 0.5, 0.18)), "neutral.1", (0, -3.5, 1.82))
    attach(k, head, "Muzzle", box((0.24, 0.2, 0.22)), "wood.1", (0, -3.98, 1.68))
    for side, sx in (("L", -1), ("R", 1)):
        attach(k, head, f"Ear{side}", box((0.06, 0.05, 0.14)), "wood.1", (sx * 0.1, -3.55, 2.02))
    for fb, y in (("F", -3.45), ("B", -2.35)):
        for side, sx in (("L", -1), ("R", 1)):
            pivot_box(k, f"Leg{fb}{side}", (0.13, 0.15, 1.0), (sx * 0.17, y, 1.05), (0, 0, -0.5),
                      lambda f: "neutral.1" if f.calc_center_median().z < -0.85 else "wood.2", horse)
    attach(k, horse, "Tail", box((0.1, 0.1, 0.6)), "neutral.1", (0, -2.2, 1.2), (0.4, 0, 0))
    export(os.path.join("village", "props", "trader_cart"))


def trader_villager():
    def hat(k, p):  # a wide straw hat
        attach(k, p["Head"], "HatBrim", prism(12, 0.42, 0.42, 0.04), "wood.7", (0, 0, 1.44))
        attach(k, p["Head"], "HatCrown", prism(12, 0.2, 0.18, 0.18), ("wood.7", "wood.6", "wood.6"), (0, 0, 1.54))
        attach(k, p["Head"], "HatBand", prism(12, 0.205, 0.205, 0.05), "accent.6", (0, 0, 1.48))

    def extra(k, p):  # a long patterned scarf and a satchel
        attach(k, p["Body"], "Scarf", box((0.52, 0.34, 0.1)), "accent.7", (0, 0, 1.0))
        attach(k, p["Body"], "Satchel", box((0.1, 0.3, 0.25)), "wood.3", (0.3, 0.02, 0.62))

    villager("trader", "accent.6", "accent.6", "wood.3", hat=hat, extra=extra)


def flower_basket():
    """A basket of flowers hanging from a small iron bracket (plans/market.md, from the trader).
    Origin on the ground at a lamp post's foot: the bracket sticks out from 2.1 m up."""
    reset()
    k = Kit("", 690)
    iron = ("neutral.3", "neutral.2", "neutral.2")
    k.box("Bracket", (0.04, 0.5, 0.04), (0, -0.3, 2.1), iron)
    for sx in (-1, 1):
        k.box("Chain", (0.015, 0.015, 0.3), (sx * 0.1, -0.5, 1.95), iron)
    k.add("Basket", prism(8, 0.14, 0.2, 0.18), ("wood.5", "wood.4", "wood.3"), (0, -0.5, 1.75))
    for i in range(10):
        col = k.rng.choice(["accent.7", "accent.3", "accent.6", "neutral.7", "accent.1"])
        a = k.rng.uniform(0, math.tau)
        r = k.rng.uniform(0.0, 0.17)
        k.add("Flower", blob(0.05, k.rng, 0.2), (col, col, col), (math.cos(a) * r, -0.5 + math.sin(a) * r, 1.88 + k.rng.uniform(0, 0.06)))
    for i in range(6):
        a = i * math.tau / 6
        k.box("Trail", (0.04, 0.04, 0.22), (math.cos(a) * 0.19, -0.5 + math.sin(a) * 0.19, 1.62), ("leaves.4", "leaves.3", "leaves.3"))
    export(os.path.join("village", "props", "flower_basket"))


def weathervane():
    """A copper rooster turning on top of a tall pole (plans/market.md): Vane (pivot on the pole's
    top) turns with the wind in the game."""
    reset()
    k = Kit("", 691)
    bpy.context.view_layer.update()
    k.post("Pole", 0.06, 0, 4.2, 0, 0, ("wood.4", "wood.3", "wood.2"))
    k.box("Base", (0.5, 0.5, 0.25), (0, 0, 0.12), ("stone.5", "stone.4", "stone.3"))
    for i, (dx, dy) in enumerate([(1, 0), (0, 1)]):  # the compass arms
        k.box("Arm", (0.7 if dx else 0.03, 0.7 if dy else 0.03, 0.03), (0, 0, 3.9), ("ore.copper_dark",) * 3)
    vane = pivot_box(k, "Vane", (0.03, 0.03, 0.03), (0, 0, 4.2), (0, 0, 0), ("ore.copper",) * 3)
    bpy.context.view_layer.update()
    copper = ("ore.copper", "ore.copper", "ore.copper_dark")
    attach(k, vane, "Body", blob(0.16, k.rng, 0.1, (1.4, 0.4, 0.9)), copper, (0, 0, 4.42))
    attach(k, vane, "Neck", box((0.06, 0.08, 0.2)), copper, (0, -0.16, 4.58))
    attach(k, vane, "Head", blob(0.07, k.rng, 0.1), copper, (0, -0.2, 4.72))
    attach(k, vane, "Comb", box((0.02, 0.08, 0.06)), ("accent.0",) * 3, (0, -0.2, 4.8))
    attach(k, vane, "Tail", box((0.02, 0.22, 0.26)), copper, (0, 0.2, 4.56), (math.radians(-30), 0, 0))
    attach(k, vane, "Arrow", box((0.02, 0.8, 0.03)), copper, (0, 0, 4.25))
    export(os.path.join("village", "props", "weathervane"))


def painted_cart():
    """A little handcart painted with flowers, full of pumpkins, by the market (plans/market.md)."""
    reset()
    k = Kit("", 692)
    k.box("Bed", (0.8, 1.2, 0.08), (0, 0, 0.55), ("accent.4", "accent.4", "wood.2"))
    for sx in (-1, 1):
        k.box("Side", (0.05, 1.2, 0.3), (sx * 0.38, 0, 0.72), ("accent.4", "accent.4", "accent.4", "accent.5"))
        for j in range(3):  # painted flowers
            k.box("Paint", (0.01, 0.08, 0.08), (sx * 0.41, -0.35 + j * 0.35, 0.74), ("accent.3",) * 3)
    k.box("Back", (0.8, 0.05, 0.3), (0, 0.58, 0.72), ("accent.4", "accent.4", "accent.4"))
    for sx in (-1, 1):
        rim = prism(10, 0.3, 0.3, 0.05)
        bmesh.ops.rotate(rim, cent=Vector((0, 0, 0)), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=rim.verts)
        k.add("Wheel", rim, ("wood.3", "wood.3", "wood.2"), (sx * 0.45, 0.2, 0.3))
        k.box("Handle", (0.04, 0.9, 0.04), (sx * 0.3, -1.0, 0.62), ("wood.4", "wood.3", "wood.2"), rot=(math.radians(8), 0, 0))
    k.box("Leg", (0.6, 0.04, 0.04), (0, -0.5, 0.25), ("wood.3",) * 3)
    for i in range(6):
        k.add("Pumpkin", blob(0.13, k.rng, 0.1, (1.15, 1.15, 0.8)), ("accent.2", "accent.2", "ore.copper_dark"),
              (k.rng.uniform(-0.22, 0.22), k.rng.uniform(-0.4, 0.4), 0.72 + k.rng.uniform(0, 0.1)))
    export(os.path.join("village", "props", "painted_cart"))


def mark(name, loc, facing=(0.0, -1.0)):
    """An empty the game reads as a Marker3D: at `loc`, its front (Godot +Z, Blender -Y) turned
    toward `facing` (a Blender XY direction)."""
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (0, 0, math.atan2(facing[0], -facing[1]))
    return obj


def cafe_table(k, x, y):
    """A little round table on a pedestal, with two mugs and a plate of bread."""
    k.add("TableTop", prism(8, 0.42, 0.42, 0.05), ("wood.6", "wood.5", "wood.4"), (x, y, 0.75))
    k.post("TableLeg", 0.05, 0.0, 0.73, x, y, ("wood.3", "wood.3", "wood.2"))
    k.add("TableFoot", prism(6, 0.22, 0.22, 0.04), ("wood.3", "wood.3", "wood.2"), (x, y, 0.02))
    for sx in (-1, 1):
        k.add("Mug", prism(8, 0.05, 0.05, 0.11), ("neutral.6", "neutral.5", "neutral.5"), (x + sx * 0.2, y + 0.08 * sx, 0.83))
    k.add("Plate", prism(10, 0.13, 0.13, 0.02), ("neutral.7", "neutral.6", "neutral.6"), (x, y - 0.1, 0.785))
    loaves(k, x, y - 0.1, 0.82, 2, 0.12)


def stool(k, x, y, seat_name, facing):
    """A three-legged stool with a Seat empty (where a villager sits) facing `facing`."""
    k.add("StoolSeat", prism(8, 0.19, 0.19, 0.05), ("wood.6", "wood.5", "wood.4"), (x, y, 0.44))
    for i in range(3):
        a = i * math.tau / 3 + 0.4
        k.box("StoolLeg", (0.04, 0.04, 0.44), (x + math.cos(a) * 0.12, y + math.sin(a) * 0.12, 0.21), "wood.3")
    mark(seat_name, (x, y, 0), facing)


def terrace():
    """Rosa's bakery terrace (plans/tavern.md): two little tables with two stools each under a
    striped awning that leans against the bakery's wall (+Y). Faces Blender -Y (Godot +Z), toward
    the path. Empties: Seat1..4 (on the stools, facing their table), Serve (where Rosa stands
    between rounds) and Table1..2 (where she stops to serve each table)."""
    reset()
    k = Kit("", 701)
    w = 5.2
    for i in range(10):  # the awning: warm stripes sloping down toward the path
        x = -w / 2 + (i + 0.5) * (w / 10)
        c = "accent.7" if i % 2 == 0 else "neutral.7"
        k.box("Awning", (w / 10 + 0.005, 2.5, 0.03), (x, 0.2, 2.38), (c, c, c), rot=(math.radians(9), 0, 0))
    for i in range(10):  # scalloped edge
        x = -w / 2 + (i + 0.5) * (w / 10)
        c = "accent.7" if i % 2 == 0 else "neutral.7"
        k.box("Flap", (w / 10 - 0.02, 0.02, 0.16), (x, -1.04, 2.1), (c, c, c))
    for sx in (-1, 1):
        k.post("Post", 0.05, 0, 2.2, sx * (w / 2 - 0.1), -1.0, ("wood.3", "wood.3", "wood.2"))
        k.post("Post", 0.05, 0, 2.6, sx * (w / 2 - 0.1), 1.4, ("wood.3", "wood.3", "wood.2"))
    k.box("Boards", (w, 2.5, 0.06), (0, 0.2, 0.03), ("wood.5", "wood.4", "wood.3", "wood.6"), jit=0.004)
    for t, tx in enumerate((-1.25, 1.25)):
        cafe_table(k, tx, 0.1)
        stool(k, tx - 0.72, 0.1, f"Seat{t * 2 + 1}", (1, 0))
        stool(k, tx + 0.72, 0.1, f"Seat{t * 2 + 2}", (-1, 0))
        mark(f"Table{t + 1}", (tx, -0.75, 0), (0, 1))
    mark("Serve", (0.0, 0.95, 0), (0, -1))
    # a chalkboard of the day's bakes by the front post
    k.box("Board", (0.5, 0.04, 0.7), (w / 2 - 0.45, -1.15, 0.6), ("wood.1", "wood.1", "wood.1"), rot=(math.radians(12), 0, 0))
    k.box("BoardFrame", (0.56, 0.05, 0.05), (w / 2 - 0.45, -1.16, 0.97), "wood.5")
    export(os.path.join("village", "props", "terrace"))


TAVERN_W, TAVERN_D, TAVERN_H = 4.0, 3.5, 3.0  # half width (X), half depth (Y), wall height
TAVERN_FLOOR = 0.08


def tavern_table(k, x, y, seats, prefix, w=1.1, d=0.8):
    """A plank table with stools round it. seats: which sides get a stool ("x-", "x+", "y-", "y+");
    each stool gets a <prefix><n> empty facing the table."""
    k.box("TableTop", (w, d, 0.07), (x, y, 0.78), ("wood.5", "wood.4", "wood.3", "wood.6"), jit=0.005)
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.box("TableLeg", (0.07, 0.07, 0.74), (x + sx * (w / 2 - 0.1), y + sy * (d / 2 - 0.1), 0.38), "wood.3")
    k.add("Mug", prism(8, 0.05, 0.05, 0.12), ("wood.6", "wood.4", "wood.4"), (x - 0.2, y + 0.1, 0.875))
    k.add("Mug", prism(8, 0.05, 0.05, 0.12), ("wood.6", "wood.4", "wood.4"), (x + 0.25, y - 0.12, 0.875))
    n = 0
    for side in seats:
        n += 1
        if side[0] == "x":
            sx = -1 if side[1] == "-" else 1
            sxy, face = (x + sx * (w / 2 + 0.28), y), (-sx, 0)
        else:
            sy = -1 if side[1] == "-" else 1
            sxy, face = (x, y + sy * (d / 2 + 0.28)), (0, -sy)
        k.add("StoolSeat", prism(8, 0.19, 0.19, 0.05), ("wood.6", "wood.5", "wood.4"), (sxy[0], sxy[1], 0.46))
        k.add("StoolLeg", prism(6, 0.05, 0.05, 0.44), "wood.3", (sxy[0], sxy[1], 0.24))
        mark(f"{k.prefix}_{prefix}{n}", (sxy[0], sxy[1], TAVERN_FLOOR), face)


def tavern_bar(k, tier):
    """The bar along the back wall, left of the middle, with shelves of bottles behind it and the
    keeper's place; three bar stools (Seat empties) in front and a Stand at its end."""
    x0, x1, y = -3.6, -0.6, 2.0
    k.box("Counter", (x1 - x0, 0.6, 0.08), ((x0 + x1) / 2, y, 1.08), ("wood.6", "wood.5", "wood.4"), jit=0.004)
    k.box("BarFront", (x1 - x0, 0.08, 1.04), ((x0 + x1) / 2, y - 0.26, 0.56), ("wood.3", "wood.3", "wood.2", "wood.4"))
    k.box("BarEnd", (0.08, 0.6, 1.04), (x1, y, 0.56), ("wood.3", "wood.3", "wood.2"))
    for z in (1.4, 2.0):
        k.box("Shelf", (2.8, 0.3, 0.05), (-2.1, 3.3, z), "wood.4")
        for i in range(7):
            c = ("leaves.2", "accent.0", "wood.2", "accent.4")[(i + int(z * 10)) % 4]
            k.add("Bottle", prism(6, 0.045, 0.03, 0.26), (c, c, c), (-3.3 + i * 0.4, 3.3, z + 0.16))
    for i in range(2 if tier == 2 else 3):  # casks on their sides by the back wall
        k.log("Cask", 0.6, 0.27, (-0.2 + 0, 2.95 - i * 0.0, 0.32 + i * 0.55), axis="x",
              sides=("wood.4", "wood.3", "wood.5"), ends="wood.6")
    for i in range(4):
        k.add("Mug", prism(8, 0.05, 0.05, 0.12), ("wood.6", "wood.4", "wood.4"), (-3.3 + i * 0.25, y + 0.1, 1.18))
    for n, x in enumerate((-3.0, -2.1, -1.2)):
        k.add("StoolSeat", prism(8, 0.19, 0.19, 0.05), ("wood.6", "wood.5", "wood.4"), (x, y - 0.75, 0.7))
        k.add("StoolLeg", prism(6, 0.05, 0.05, 0.68), "wood.3", (x, y - 0.75, 0.36))
        # (raised to the stool's height above an ordinary seat's, so they sit on it)
        mark(f"{k.prefix}_SeatBar{n + 1}", (x, y - 0.75, TAVERN_FLOOR + 0.24), (0, 1))
    mark(f"{k.prefix}_Stand1", (-0.25, 1.35, TAVERN_FLOOR), (-1, 0.4))


def tavern_lantern(k, x, y):
    """A lantern hanging on a chain from a tie beam (glows and lights the room after dark)."""
    k.box("Chain", (0.02, 0.02, 0.45), (x, y, TAVERN_H - 0.42), "metal.1")
    k.box("Cage", (0.2, 0.2, 0.04), (x, y, TAVERN_H - 0.66), "metal.1")
    k.box("Lantern", (0.15, 0.15, 0.22), (x, y, TAVERN_H - 0.8), "accent.3")
    k.box("Cage", (0.2, 0.2, 0.04), (x, y, TAVERN_H - 0.93), "metal.1")


def tavern_fireplace(k):
    """A stone fireplace against the +X wall with a fire in it, and its chimney outside."""
    W = TAVERN_W
    y = 0.6
    k.stone("Hearth", (0.9, 1.8, 0.14), (W - 0.55, y, 0.07))
    for sy in (-1, 1):
        k.stone("Jamb", (0.5, 0.35, 1.2), (W - 0.36, y + sy * 0.72, 0.6))
    k.stone("Mantel", (0.6, 1.8, 0.3), (W - 0.38, y, 1.35))
    k.stone("Breast", (0.45, 1.3, 1.5), (W - 0.33, y, 2.25))
    k.box("FireBack", (0.08, 1.1, 1.1), (W - 0.15, y, 0.6), "stone.1")
    k.log("FireLog", 0.7, 0.07, (W - 0.45, y - 0.08, 0.2), axis="y")
    k.log("FireLog", 0.7, 0.07, (W - 0.5, y + 0.1, 0.27), axis="y")
    k.add("LanternFire", blob(0.16, k.rng, jitter_amount=0.3, squash=(1.0, 1.6, 0.9)), "accent.2", (W - 0.48, y, 0.36))
    k.add("Ember", blob(0.1, k.rng, jitter_amount=0.3, squash=(1.2, 1.2, 0.5)), "accent.1", (W - 0.42, y - 0.2, 0.18))
    for i in range(16):  # the chimney, outside
        k.stone("Chimney", (0.55, 0.9, 0.45), (W + 0.4, y, 0.25 + i * 0.4), ("stone.4", "stone.3", "stone.2", "stone.5"))
    k.empty("Smoke", (W + 0.4, y, 6.8))


def tavern_junk(k):
    """The ruin's mess: fallen planks, a tipped barrel, weeds against the walls."""
    D = TAVERN_D
    for i in range(3):
        k.box("Plank", (1.6, 0.18, 0.05), (-2.0 + i * 0.5, -D - 0.9 - i * 0.25, 0.03 + i * 0.04),
              ("wood.3", "wood.2", "wood.2"), rot=(0, 0, k.rng.uniform(-0.6, 0.6)))
    k.add("Barrel", prism(10, 0.3, 0.3, 0.75), ("wood.4", "wood.3", "wood.2"), (2.9, -D - 0.8, 0.3), (math.pi / 2, 0, 0.4))
    for i in range(10):
        x = k.rng.uniform(-3.8, 3.8)
        k.box("Weed", (0.25, 0.2, k.rng.uniform(0.25, 0.5)), (x, -D - 0.3, 0.2), ("leaves.3", "leaves.2", "leaves.2"), jit=0.05)


def keeper_villager():
    def hat(k, p):  # a flat cap
        attach(k, p["Head"], "Cap", box((0.42, 0.42, 0.08)), "wood.2", (0, -0.02, 1.47))
        attach(k, p["Head"], "Peak", box((0.34, 0.16, 0.04)), "wood.2", (0, -0.26, 1.45))

    def extra(k, p):  # a long apron and a cloth over the shoulder
        attach(k, p["Body"], "Apron", box((0.46, 0.04, 0.7)), ("neutral.6", "neutral.5", "neutral.5"), (0, -0.18, 0.6))
        attach(k, p["Body"], "Cloth", box((0.12, 0.34, 0.06)), "accent.4", (0.2, 0, 1.06))

    def prop(k, p):  # a tankard
        attach(k, p["ArmR"], "PropMug", prism(8, 0.07, 0.07, 0.14), ("wood.6", "wood.4", "wood.4"), (0.32, -0.1, 0.48))

    villager("keeper", "accent.0", "neutral.6", "wood.1", hat=hat, extra=extra, prop=prop)


def dogs():
    os.makedirs(os.path.join(OUT_DIR, "dogs"), exist_ok=True)
    for breed, coats in DOG_COATS.items():
        for coat_name in coats:
            dog(breed, coat_name)


if __name__ == "__main__":  # (kit_buildings.py imports this for Kit without building everything)
    os.makedirs(os.path.join(VILLAGE_DIR, "props"), exist_ok=True)
    only = sys.argv[sys.argv.index("--") + 3:]  # optional: names of the builders to run (e.g. `smithy`)
    for build in (woodcutter_villager, smith_villager, fisher_villager, mayor_villager,
                  baker_villager, prospector_villager,
                  bench, lamp_post, lamp_post_rustic, lantern, noticeboard, planter, well, fountain, barrel_prop, crate_prop, signpost, dogs,
                  doghouse, doghouse_painted, doghouse_porch, dog_bowl, dog_blanket,
                  landslide_mud, retaining_wall, market_stall, stallkeeper_villager,
                  trader_cart, trader_villager, flower_basket, weathervane, painted_cart, terrace, keeper_villager):
        if not only or build.__name__ in only:
            build()
