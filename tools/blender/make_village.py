"""Generates the village models as .glb files: four buildings (three tiers each), their villagers
and a few props. Uses the helpers in make_models.py. Run headless from the project folder:

    blender -b -P tools/blender/make_village.py -- models art/palette.json

Outputs into models/village/:
  <building>.glb           every tier's pieces in one file, named T1_*, T2_*, T3_*. The game
                           shows one tier at a time and builds the next one piece by piece,
                           lowest piece first. Empties named *Smoke* get chimney smoke.
  villager_<id>.glb        a toy villager in separate parts the game animates in code:
                           Body (pivot at the hips), Head (pivot at the neck), ArmL / ArmR
                           (pivots at the shoulders, the held tool is a child of ArmR),
                           LegL / LegR (pivots at the hips).
  props/<name>.glb         benches, lamp posts, barrels, crates, the signpost.

Buildings face Blender -Y (Godot +Z, "front"), origin at ground level in the middle.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_models import (OUT_DIR, blob, box, bmesh, bpy, export, make_object, paint, prism,  # noqa: E402
                         reset, Vector)

VILLAGE_DIR = os.path.join(OUT_DIR, "village")


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


def log_cabin(k, roof):
    """Tiers 2 and 3: a log cabin, 5 x 4 m, door at the front, gable roof along X."""
    r = 0.16
    for i in range(8):
        z = 0.16 + i * 0.3
        if i < 7:  # door gap
            for sx in (-1, 1):
                k.log("Log", 2.15, r, (sx * 1.675, -2.0, z), "x")
        else:
            k.log("Log", 5.5, r, (0, -2.0, z), "x")
        k.log("Log", 5.5, r, (0, 2.0, z), "x")
        for sx in (-1, 1):
            k.log("Log", 4.5, r, (sx * 2.5, 0, z + 0.15), "y")
    for sx in (-1, 1):
        k.gable("Gable", 2.05, 2.4, 3.55, sx * 2.5, 0.2, ("wood.4", "wood.4", "wood.3"))
        k.window((sx * 2.7, 0, 1.4), (0.7, 0.6), facing="x")
    k.window((1.55, -2.2, 1.35), (0.7, 0.6))
    k.door((0, -2.06, 0.0), (1.1, 2.0))
    k.gable_roof("Roof", 6.1, 2.0, 2.45, 3.6, 0.45, 3, roof)
    k.log("Ridge", 6.2, 0.1, (0, 0, 3.68), "x", sides=("wood.2",), ends="wood.6")


def woodcutter():
    reset()
    k = Kit("T1", 101)
    lean_to(k)

    k = Kit("T2", 102)
    log_cabin(k, ("wood.2", "wood.2", "wood.1", "wood.3"))
    k.chopping_block((-3.4, -2.9, 0))
    for x, z in ((3.15, 0.13), (3.42, 0.13), (3.28, 0.37)):
        k.log("Firewood", 1.1, 0.13, (x, 0.3, z), "y")

    k = Kit("T3", 103)
    log_cabin(k, ("accent.0", "accent.0", "wood.1", "accent.1"))
    # porch: planks on two beams, posts, a gently sloping roof, a step
    for y in (-2.45, -3.4):
        k.log("PorchBeam", 6.0, 0.12, (0, y, 0.12), "x")
    for i in range(5):
        k.box("PorchPlank", (6.0, 0.31, 0.08), (0, -2.3 - i * 0.33, 0.3), ("wood.6", "wood.5", "wood.4"), jit=0.01)
    for sx in (-1, 1):
        k.post("PorchPost", 0.09, 0.34, 2.3, sx * 2.8, -3.5)
    k.box("PorchRoof", (6.3, 1.85, 0.1), (0, -2.95, 2.33), ("wood.2", "wood.2", "wood.1"), rot=(0.17, 0, 0))
    k.box("Step", (1.4, 0.4, 0.18), (0, -3.95, 0.09), ("wood.5", "wood.4", "wood.3"))
    # stone chimney up the right-hand wall
    for i in range(10):
        s = 0.82 if i < 8 else 0.66
        k.stone("Chimney", (s, s, 0.46), (3.12, 0.6, 0.23 + i * 0.46))
    k.empty("Smoke", (3.12, 0.6, 4.75))
    # a big woodpile under a little roof on the left
    for row, (n, z) in enumerate(((4, 0.14), (3, 0.4), (2, 0.66))):
        for i in range(n):
            k.log("Woodpile", 1.6, 0.14, (-3.05 - (i + row * 0.5) * 0.28, 0.0, z), "y")
    k.box("WoodpileRoof", (1.4, 2.0, 0.08), (-3.5, 0.0, 1.2), ("wood.2", "wood.2", "wood.1"), rot=(0, 0.25, 0))
    # window boxes with flowers, a lantern by the door, the chopping block
    for sx in (-1, 1):
        k.box("WindowBox", (0.22, 0.9, 0.18), (sx * 2.85, 0, 0.98), ("wood.3", "wood.3", "wood.2"))
        for j, c in enumerate(("accent.7", "accent.3", "accent.7")):
            k.box("Flower", (0.12, 0.16, 0.12), (sx * 2.87, -0.3 + j * 0.3, 1.13), c, jit=0.02)
    k.box("Lantern", (0.16, 0.16, 0.22), (0.95, -2.3, 2.0), ("accent.3", "accent.3", "neutral.1"))
    k.chopping_block((-3.6, -4.5, 0))
    export(os.path.join("village", "woodcutter"))


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


def smithy():
    reset()
    k = Kit("T1", 201)
    # an open-air camp: fire pit, anvil on a stump, a bucket, tools on a leaning board, a tarp
    k.fire((-0.9, 0.2, 0))
    k.anvil((0.9, -0.5, 0))
    k.add("Bucket", prism(8, 0.18, 0.2, 0.3), ("accent.4", "wood.3", "wood.2"), (1.7, 0.5, 0.15))
    k.box("ToolBoard", (1.0, 0.06, 1.4), (-0.2, 1.3, 0.68), ("wood.4", "wood.4", "wood.3"), rot=(0.25, 0, 0))
    for x, h in ((-0.5, 0.5), (-0.2, 0.42), (0.1, 0.55)):
        k.box("Tool", (0.05, 0.05, h), (x, 1.17, 0.85), "metal.2", rot=(0.25, 0, 0))
    for x in (-1.5, 1.5):
        k.post("TarpPole", 0.05, 0, 1.9 if x < 0 else 1.6, x, -0.9)
    k.box("Tarp", (3.2, 1.6, 0.04), (0, -0.25, 1.65), ("neutral.4", "neutral.3", "neutral.3"), rot=(-0.35, 0.06, 0))
    k.crate((-1.9, -0.9, 0), 0.55)

    k = Kit("T2", 202)
    # a stone forge under a roof on four posts
    for x in (-2.4, 2.4):
        for y in (-2.0, 2.0):
            k.post("Post", 0.11, 0, 2.65, x, y)
    for y in (-2.0, 2.0):
        k.log("Beam", 5.2, 0.11, (0, y, 2.62), "x", sides=("wood.3", "wood.2"))
    k.gable_roof("Roof", 5.8, 2.0, 2.68, 3.5, 0.45, 3, ("wood.2", "wood.2", "wood.1", "wood.3"))
    for x in (-2.4, 2.4):
        k.gable("Gable", 2.05, 2.68, 3.45, x, 0.12, ("wood.3", "wood.3", "wood.2"))
    forge(k, 1.4, 4.4)
    k.anvil((0.4, -0.6, 0))
    k.barrel((-1.7, -0.5, 0), 0.3, 0.7)
    k.add("Water", prism(10, 0.27, 0.27, 0.03), "accent.4", (-1.7, -0.5, 0.69))
    k.box("ToolRack", (0.08, 0.9, 0.6), (2.32, 0.6, 1.4), "wood.4")
    for i in range(3):
        k.box("Tool", (0.04, 0.05, 0.45), (2.26, 0.3 + i * 0.3, 1.25), "metal.2")

    k = Kit("T3", 203)
    # a proper smithy: stone walls, timber above, slate roof, big chimney, bellows, sign
    for course in range(3):
        z = 0.2 + course * 0.4
        for x in (-1.5, 1.5):
            k.stone("Wall", (3.0, 0.45, 0.4), (x, 2.5, z), ("stone.4", "stone.3", "stone.2", "stone.5"))
        for sx in (-1, 1):
            for y in (-1.25, 1.25):
                k.stone("Wall", (0.45, 2.5, 0.4), (sx * 3.0, y, z), ("stone.4", "stone.3", "stone.2", "stone.5"))
    for x, y in ((-3.0, 2.5), (3.0, 2.5), (-3.0, 0.0), (3.0, 0.0), (0.0, 2.5)):
        k.post("Post", 0.1, 1.2, 3.05, x, y, ("wood.2", "wood.2", "wood.1"))
    for x in (-3.0, 3.0):
        k.post("Post", 0.13, 0.0, 3.05, x, -2.5, ("wood.2", "wood.2", "wood.1"))
    for x in (-1.5, 1.5):
        k.box("Panel", (3.0, 0.12, 1.8), (x, 2.5, 2.1), ("wood.5", "wood.5", "wood.4", "wood.6"))
    for sx in (-1, 1):
        for y in (-1.25, 1.25):
            k.box("Panel", (0.12, 2.5, 1.8), (sx * 3.0, y, 2.1), ("wood.5", "wood.5", "wood.4", "wood.6"))
    for y in (-2.5, 2.5):
        k.log("Beam", 6.4, 0.12, (0, y, 3.05), "x", sides=("wood.2", "wood.1"))
    k.gable_roof("Roof", 7.0, 2.5, 3.1, 4.3, 0.5, 3, ("stone.1", "stone.1", "stone.0", "stone.2"))
    for x in (-3.0, 3.0):
        k.gable("Gable", 2.55, 3.1, 4.25, x, 0.14, ("wood.5", "wood.5", "wood.4"))
    top = forge(k, 1.7, 5.6, wide=1.2)
    k.empty("Smoke", (0, 1.8, top + 0.3))
    # bellows beside the forge
    k.box("BellowsLow", (0.55, 0.95, 0.06), (1.35, 1.6, 0.55), "wood.3", rot=(0.1, 0, 0))
    k.box("BellowsLeather", (0.5, 0.8, 0.22), (1.35, 1.65, 0.68), ("wood.1", "wood.1", "wood.0"), rot=(0.1, 0, 0))
    k.box("BellowsTop", (0.55, 0.95, 0.06), (1.35, 1.6, 0.84), "wood.3", rot=(0.25, 0, 0))
    k.box("BellowsHandle", (0.06, 0.5, 0.06), (1.35, 0.95, 0.85), "wood.5")
    k.add("BellowsNozzle", prism(6, 0.06, 0.03, 0.4), "metal.2", (0.9, 1.75, 0.6), (0, math.pi / 2, 0))
    k.anvil((0.5, -0.7, 0), 1.15)
    k.box("Trough", (0.6, 1.4, 0.5), (-1.9, -0.6, 0.25), ("wood.3", "wood.3", "wood.2", "wood.4"))
    k.box("TroughWater", (0.48, 1.28, 0.04), (-1.9, -0.6, 0.48), "accent.4")
    k.barrel((-2.3, 1.7, 0), 0.28, 0.7)
    # grindstone
    for y in (-1.55, -0.95):
        k.post("GrindFrame", 0.05, 0, 0.75, 2.3, y)
    k.add("Grindstone", prism(12, 0.36, 0.36, 0.12), ("stone.5", "stone.4", "stone.3"), (2.3, -1.25, 0.6),
          (math.pi / 2, 0, 0))
    # hanging sign out front
    k.post("SignPost", 0.08, 0, 2.7, 3.7, -3.0, ("wood.2", "wood.2", "wood.1"))
    k.box("SignArm", (0.9, 0.06, 0.06), (3.3, -3.0, 2.55), "wood.2")
    k.box("Sign", (0.7, 0.06, 0.5), (3.15, -3.0, 2.15), ("wood.6", "wood.6", "wood.5"))
    k.box("SignAnvil", (0.4, 0.08, 0.14), (3.15, -3.04, 2.15), "metal.1")
    export(os.path.join("village", "smithy"))


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


def stilt_shack(k, roof):
    """Tiers 2 and 3: a plank shack on stilts, floor at 0.6 m, door at the front, shed roof."""
    for x in (-1.65, 1.65):
        for y in (-1.45, 0.0, 1.45):
            k.post("Stilt", 0.09, -0.3, 0.55, x, y, ("wood.3", "wood.2", "wood.1"))
    for i in range(6):
        k.box("Floor", (3.8, 0.52, 0.1), (0, -1.33 + i * 0.533, 0.55), ("wood.5", "wood.4", "wood.3"), jit=0.01)
    k.plank_walls(-1.75, 1.75, -1.55, 1.55, 0.6, 2.7, 0.95, ["wood.4", "wood.5", "wood.4", "wood.3"])
    k.door((0, -1.6, 0.6), (0.85, 1.9), "wood.2")
    k.window((1.82, 0.2, 1.75), (0.6, 0.5), facing="x")
    k.shed_roof("Roof", 4.1, -1.95, 1.95, 3.05, 2.65, 3, roof)
    front_steps(k, 0, -1.6, 0.6, 0.95, 0.3, ("wood.5", "wood.4", "wood.3"))


def fisher():
    reset()
    k = Kit("T1", 301)
    # a canvas tent, a drying rack, a crate and a rod
    for side in (-1, 1):
        k.box("Tent", (1.3, 2.2, 0.05), (-1.0 + side * 0.45, 0.3, 0.68), ("neutral.6", "neutral.5", "neutral.4"),
              rot=(0, side * 0.9, 0))
    k.post("TentPole", 0.04, 0, 1.4, -1.0, -0.8)
    k.box("TentRidge", (0.05, 2.3, 0.05), (-1.0, 0.3, 1.38), "wood.3")
    drying_rack(k, 0.8, 2.6, -0.6)
    k.crate((-2.4, -1.2, 0), 0.55)
    k.box("Rod", (0.03, 0.03, 2.4), (1.0, 0.9, 1.1), "wood.5", rot=(0.4, 0, 0.2))
    k.add("Bucket", prism(8, 0.18, 0.2, 0.3), ("accent.4", "wood.3", "wood.2"), (0.3, -1.4, 0.15))

    k = Kit("T2", 302)
    stilt_shack(k, ("wood.3", "wood.3", "wood.2", "wood.4"))
    drying_rack(k, 2.3, 3.8, -0.4)
    k.barrel((-2.4, -1.0, 0), 0.28, 0.7)

    k = Kit("T3", 303)
    stilt_shack(k, ("accent.4", "accent.4", "metal.1", "accent.5"))
    k.add("StovePipe", prism(8, 0.1, 0.1, 1.0), "metal.2", (-1.1, 1.0, 3.3))
    k.empty("Smoke", (-1.1, 1.0, 3.9))
    # the dock, out over the pond
    for y in (-2.2, -4.3, -6.4):
        for x in (0.65, 1.95):
            k.post("DockPost", 0.09, -1.3, 0.55, x, y, ("wood.3", "wood.2", "wood.1"))
    for x in (0.75, 1.85):
        k.log("DockBeam", 5.0, 0.09, (x, -4.25, 0.3), "y", sides=("wood.3", "wood.2"))
    for i in range(10):
        k.box("DockPlank", (1.5, 0.46, 0.08), (1.3, -2.0 - i * 0.5, 0.42), ("wood.6", "wood.5", "wood.4"), jit=0.01)
    k.post("LanternPost", 0.06, 0.45, 1.85, 1.95, -6.55, ("wood.2", "wood.2", "wood.1"))
    k.box("Lantern", (0.18, 0.18, 0.24), (1.95, -6.55, 1.95), ("accent.3", "accent.3", "neutral.1"))
    # a little rowboat tied up alongside
    bm = box((0.95, 2.3, 0.36))
    for v in bm.verts:
        if abs(v.co.y) > 1.0:
            v.co.x *= 0.3  # pointed ends
        if v.co.z < 0:
            v.co.x *= 0.7  # narrower keel
    k.add("Boat", bm, ("wood.2", "wood.4", "wood.3", "wood.5"), (2.75, -4.9, -0.05))
    k.box("BoatSeat", (0.8, 0.25, 0.05), (2.75, -4.9, 0.08), "wood.6")
    # nets drying on a rack, barrels
    for y in (-1.0, 0.8):
        k.post("NetPost", 0.06, 0, 1.9, -2.7, y)
    k.box("NetBar", (0.06, 2.0, 0.06), (-2.7, -0.1, 1.85), "wood.4")
    k.box("Net", (0.04, 1.7, 1.25), (-2.7, -0.1, 1.15), ("neutral.3", "neutral.3", "neutral.2"), jit=0.03)
    for i in range(4):
        k.add("Float", blob(0.06, k.rng, jitter_amount=0.1), "accent.1", (-2.73, -0.8 + i * 0.47, 1.8))
    drying_rack(k, 2.3, 3.8, -0.4)
    k.barrel((-2.5, -1.9, 0), 0.28, 0.7)
    k.barrel((-1.9, -2.2, 0), 0.25, 0.6)
    export(os.path.join("village", "fisher"))


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


def town_hall():
    reset()
    k = Kit("T1", 401)
    # a draughty plank meeting hut, a notice board, a bell on a frame
    k.plank_walls(-2.0, 2.0, -1.2, 2.0, 0.0, 2.4, 1.0, ["wood.3", "wood.4", "wood.2", "wood.3"], plank=0.5)
    k.door((0, -1.26, 0), (1.0, 2.0), "wood.2")
    k.shed_roof("Roof", 4.5, -1.6, 2.4, 2.75, 2.3, 3, ("wood.2", "wood.2", "wood.1", "neutral.4"))
    notice_board(k, -2.2, -2.6)
    for x in (1.8, 2.7):
        k.post("BellPost", 0.07, 0, 2.3, x, -2.4)
    k.box("BellBar", (1.1, 0.08, 0.08), (2.25, -2.4, 2.25), "wood.3")
    k.add("Bell", prism(8, 0.22, 0.1, 0.32), ("ore.copper", "ore.copper", "ore.copper_dark"), (2.25, -2.4, 1.95))

    k = Kit("T2", 402)
    # a timber hall on a stone footing, red roof, double doors, steps, a flag
    for x in (-3.0, -1.0, 1.0, 3.0):
        k.stone("Footing", (2.0, 0.5, 0.4), (x, -3.0, 0.2))
        k.stone("Footing", (2.0, 0.5, 0.4), (x, 3.0, 0.2))
    for sx in (-1, 1):
        for y in (-1.75, 0.0, 1.75):
            k.stone("Footing", (0.5, 1.75, 0.4), (sx * 4.0, y, 0.2))
    for x, y in ((-4.0, -3.0), (4.0, -3.0), (-4.0, 3.0), (4.0, 3.0), (-1.25, -3.0), (1.25, -3.0)):
        k.post("Post", 0.13, 0.4, 3.4, x, y, ("wood.2", "wood.2", "wood.1"))
    wall = ("wood.5", "wood.5", "wood.4", "wood.6")
    for sx in (-1, 1):
        k.box("Wall", (2.6, 0.14, 3.0), (sx * 2.62, -3.0, 1.9), wall)
        k.window((sx * 2.62, -3.1, 2.0), (0.8, 0.9))
        for y in (-1.5, 1.5):
            k.box("Wall", (0.14, 2.9, 3.0), (sx * 4.0, y, 1.9), wall)
        k.window((sx * 4.1, 0.0, 2.0), (0.8, 0.9), facing="x")
    k.box("Wall", (2.4, 0.14, 0.8), (0, -3.0, 3.0), wall)
    for x in (-2.7, 0.0, 2.7):
        k.box("Wall", (2.7, 0.14, 3.0), (x, 3.0, 1.9), wall)
    for sx in (-1, 1):
        k.door((sx * 0.56, -3.04, 0.4), (1.1, 2.2), "wood.1")
    for sx in (-1, 1):
        k.gable("Gable", 3.05, 3.4, 5.0, sx * 4.0, 0.16, wall)
    k.gable_roof("Roof", 9.0, 3.0, 3.42, 5.1, 0.5, 3, ("accent.0", "accent.0", "wood.1", "accent.1"))
    front_steps(k, 0, -3.25, 0.4, 2.8, 0.35)
    k.post("FlagPole", 0.05, 0, 5.2, 4.9, -3.6, ("metal.4", "metal.3", "metal.2"))
    k.box("Flag", (1.0, 0.04, 0.6), (5.42, -3.6, 4.85), "accent.4")
    notice_board(k, -5.2, -3.4, 1.0, roofed=True)

    k = Kit("T3", 403)
    # a stone hall with a timber upper storey, a bell and clock tower, banners and lamps
    stone = ("stone.5", "stone.4", "stone.2", "stone.3")
    for course in range(4):
        z = 0.375 + course * 0.75
        if course < 3:  # door gap in the front
            for sx in (-1, 1):
                k.stone("Wall", (3.4, 0.6, 0.75), (sx * 2.8, -3.5, z), stone)
        else:
            k.stone("Wall", (9.0, 0.6, 0.75), (0, -3.5, z), stone)
        for x in (-2.25, 2.25):
            k.stone("Wall", (4.5, 0.6, 0.75), (x, 3.5, z), stone)
        for sx in (-1, 1):
            for y in (-1.6, 1.6):
                k.stone("Wall", (0.6, 3.2, 0.75), (sx * 4.5, y, z), stone)
    for sx in (-1, 1):
        k.window((sx * 2.8, -3.82, 1.6), (0.9, 1.1), frame="stone.6")
        k.window((sx * 4.82, 0.0, 1.6), (0.9, 1.1), facing="x", frame="stone.6")
        k.box("FlowerBox", (1.1, 0.22, 0.18), (sx * 2.8, -3.95, 0.95), ("wood.3", "wood.3", "wood.2"))
        for j, c in enumerate(("accent.7", "accent.3", "accent.6", "accent.7")):
            k.box("Flower", (0.16, 0.12, 0.12), (sx * 2.8 - 0.42 + j * 0.28, -3.97, 1.1), c, jit=0.02)
    k.stone("Lintel", (2.6, 0.7, 0.3), (0, -3.55, 2.6), ("stone.6", "stone.5", "stone.4"))
    for sx in (-1, 1):
        k.door((sx * 0.55, -3.55, 0.0), (1.08, 2.45), "wood.1")
    # upper storey
    beam = ("wood.1", "wood.1", "wood.0")
    plaster = ("neutral.6", "neutral.6", "neutral.5", "wood.7")
    for x in (-2.25, 2.25):
        k.box("UpperWall", (4.5, 0.2, 2.2), (x, -3.4, 4.1), plaster)
        k.box("UpperWall", (4.5, 0.2, 2.2), (x, 3.4, 4.1), plaster)
    for sx in (-1, 1):
        for y in (-1.7, 1.7):
            k.box("UpperWall", (0.2, 3.4, 2.2), (sx * 4.4, y, 4.1), plaster)
    for y in (-3.52, 3.52):
        k.box("Beam", (9.2, 0.18, 0.2), (0, y, 3.05), beam)
        k.box("Beam", (9.2, 0.18, 0.2), (0, y, 5.15), beam)
    for x in (-4.4, -1.5, 1.5, 4.4):
        k.box("UpperPost", (0.18, 0.18, 2.2), (x, -3.54, 4.1), beam)
    for x in (-3.0, 0.0, 3.0):
        k.window((x, -3.56, 4.1), (0.7, 0.9))
    for sx in (-1, 1):
        k.gable("Gable", 3.55, 5.2, 7.0, sx * 4.4, 0.2, plaster)
    k.gable_roof("Roof", 10.0, 3.5, 5.22, 7.2, 0.5, 4, ("accent.0", "accent.0", "wood.1", "accent.1"))
    # the tower on the ridge: base, open belfry with the bell, pointed roof, clock
    k.box("Tower", (1.8, 1.8, 2.6), (0, 0, 7.3), ("wood.5", "wood.5", "wood.4", "wood.6"))
    for x in (-0.8, 0.8):
        for y in (-0.8, 0.8):
            k.post("Belfry", 0.08, 8.6, 9.8, x, y, beam)
    k.add("Bell", prism(8, 0.36, 0.16, 0.5), ("ore.gold", "ore.gold", "ore.copper_dark"), (0, 0, 9.15))
    k.add("TowerRoof", prism(4, 1.45, 0.04, 1.6), ("accent.0", "accent.0", "wood.1", "accent.1"), (0, 0, 10.6),
          (0, 0, math.pi / 4))
    k.add("Vane", prism(4, 0.04, 0.01, 0.8), "metal.2", (0, 0, 11.75))
    k.add("Clock", prism(12, 0.55, 0.55, 0.06), "neutral.6", (0, -0.93, 7.7), (math.pi / 2, 0, 0))
    k.box("ClockHand", (0.05, 0.04, 0.42), (0, -0.98, 7.86), "neutral.1")
    k.box("ClockHand", (0.3, 0.04, 0.05), (0.13, -0.98, 7.7), "neutral.1")
    front_steps(k, 0, -3.8, 0.45, 4.0, 0.36)
    for sx in (-1, 1):
        k.box("Banner", (0.6, 0.05, 1.5), (sx * 1.75, -3.84, 1.9), ("accent.6", "accent.6", "accent.6"))
        k.box("BannerTrim", (0.62, 0.06, 0.12), (sx * 1.75, -3.86, 1.2), "accent.3")
        k.post("LampPost", 0.06, 0, 2.5, sx * 3.0, -5.2, ("metal.1", "metal.1", "metal.0"))
        k.box("Lamp", (0.26, 0.26, 0.32), (sx * 3.0, -5.2, 2.65), ("neutral.1", "accent.3", "neutral.1"))
    export(os.path.join("village", "town_hall"))


# --- cottages (unlocked by the town hall; one tier) -------------------------------------------

def cottage(name, seed, walls, roof, extra):
    """A small cottage, 4 x 3.5 m: stone footing, walls, gable roof, chimney, door and windows.
    `extra(k)` adds the yard (garden bed, ore pile...)."""
    reset()
    k = Kit("T1", seed)
    for x in (-1.35, 0.0, 1.35):
        k.stone("Footing", (1.35, 0.4, 0.3), (x, -1.75, 0.15))
        k.stone("Footing", (1.35, 0.4, 0.3), (x, 1.75, 0.15))
    for sx in (-1, 1):
        k.stone("Footing", (0.4, 3.1, 0.3), (sx * 2.0, 0, 0.15))
    for sx in (-1, 1):
        k.box("Wall", (1.45, 0.16, 2.1), (sx * 1.27, -1.75, 1.35), walls)
        k.window((sx * 1.27, -1.85, 1.5), (0.6, 0.55))
        k.box("Wall", (0.16, 3.4, 2.1), (sx * 2.0, 0, 1.35), walls)
    k.box("Wall", (1.1, 0.16, 0.4), (0, -1.75, 2.2), walls)
    k.box("Wall", (4.0, 0.16, 2.1), (0, 1.75, 1.35), walls)
    for sx in (-1, 1):
        k.gable("Gable", 1.8, 2.4, 3.4, sx * 2.0, 0.16, walls)
    k.door((0, -1.8, 0.3), (0.95, 1.85), "wood.2")
    k.gable_roof("Roof", 4.6, 1.75, 2.42, 3.5, 0.4, 2, roof)
    for i in range(6):
        k.stone("Chimney", (0.5, 0.5, 0.45), (1.3, 0.8, 2.6 + i * 0.4), ("stone.4", "stone.3", "stone.2", "stone.5"))
    k.empty("Smoke", (1.3, 0.8, 5.1))
    k.box("Step", (1.1, 0.35, 0.18), (0, -2.05, 0.09), ("stone.5", "stone.4", "stone.3"))
    extra(k)
    export(os.path.join("village", name))


def baker_cottage():
    def garden(k):  # a flower bed with a little fence, front left
        k.box("Bed", (1.6, 0.9, 0.18), (-2.6, -3.0, 0.09), ("terrain.dirt", "wood.2", "wood.1"))
        colors = ["accent.7", "accent.3", "neutral.7", "accent.6", "accent.1"]
        for i in range(8):
            k.box("Flower", (0.14, 0.14, 0.2), (-3.2 + (i % 4) * 0.4, -3.2 + (i // 4) * 0.4, 0.28), colors[i % 5], jit=0.02)
        for x in (-3.5, -2.6, -1.7):
            k.post("FencePost", 0.04, 0, 0.6, x, -3.55, ("wood.5", "wood.4", "wood.3"))
        k.box("FenceRail", (1.9, 0.05, 0.06), (-2.6, -3.55, 0.45), "wood.5")
        k.barrel((2.6, -1.0, 0), 0.26, 0.6)
    cottage("baker_cottage", 801, ("neutral.6", "neutral.6", "neutral.5", "wood.7"),
            ("wood.2", "wood.2", "wood.1", "wood.3"), garden)


def prospector_cottage():
    def ore_pile(k):  # sorted rocks out front right: coal, gold, copper
        for i, c in enumerate(("ore.coal", "ore.gold", "ore.copper", "ore.coal", "stone.3", "ore.gold")):
            a = i * math.tau / 6
            k.add("Ore", blob(0.18, k.rng, jitter_amount=0.3, squash=(1.1, 1.0, 0.75)), (c, c, "stone.2"),
                  (2.6 + math.cos(a) * 0.35, -2.9 + math.sin(a) * 0.35, 0.12))
        k.add("Ore", blob(0.22, k.rng, jitter_amount=0.3), ("stone.4", "stone.3", "stone.2"), (2.6, -2.9, 0.3))
        k.crate((-2.6, -2.4, 0), 0.55)
        k.box("Sieve", (0.6, 0.6, 0.08), (-2.6, -2.4, 0.55), ("metal.3", "wood.4", "wood.3"))
    cottage("prospector_cottage", 802, ("stone.4", "stone.4", "stone.3", "stone.5"),
            ("stone.1", "stone.1", "stone.0", "stone.2"), ore_pile)


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
        attach(k, p["ArmR"], "PropBlade", box((0.03, 0.16, 0.2)), "metal.5", (0.32, -0.5, 0.58))

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


os.makedirs(os.path.join(VILLAGE_DIR, "props"), exist_ok=True)
for build in (woodcutter, smithy, fisher, town_hall, baker_cottage, prospector_cottage,
              woodcutter_villager, smith_villager, fisher_villager, mayor_villager,
              baker_villager, prospector_villager,
              bench, lamp_post, barrel_prop, crate_prop, signpost):
    build()
