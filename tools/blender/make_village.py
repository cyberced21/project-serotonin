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
    export_building("woodcutter")


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


def smithy_hall(k):
    """The smithy's top look (tier 3), also the base of the tier-4 crystal forge."""
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

    smithy_hall(Kit("T3", 203))
    # the crystal forge: the same smithy (same seed, so it looks the same), crystal set into the
    # forge, a rack of shards, crystal lanterns at the door and a crystal on the sign
    k = Kit("T4", 203)
    smithy_hall(k)
    for i, (x, h, tilt) in enumerate(((-0.5, 0.5, 0.3), (0.0, 0.7, 0.0), (0.5, 0.45, -0.35))):
        k.add("ForgeCrystal", prism(6, 0.09, 0.012, h), ("ore.amethyst", "accent.6", "accent.6"),
              (x * 1.2, 1.7 + 0.25, 1.0 + h / 2), (0, tilt, 0))
    k.box("CrystalRack", (0.1, 1.0, 0.7), (-2.85, 0.8, 1.2), "wood.3")
    for i in range(4):
        k.add("RackCrystal", prism(6, 0.06, 0.01, 0.3), ("ore.amethyst", "accent.6", "accent.6"),
              (-2.75, 0.45 + i * 0.24, 1.1), (0, math.pi / 2, 0))
    for x in (-1.0, 1.0):
        k.add("CrystalLantern", prism(6, 0.1, 0.02, 0.35), ("ore.amethyst", "ore.amethyst", "accent.6"),
              (x * 2.82, -2.62, 2.3))
    k.add("SignCrystal", prism(6, 0.07, 0.01, 0.26), ("ore.amethyst", "accent.6", "accent.6"), (3.15, -3.1, 2.15),
          (0, 0.4, 0))
    export_building("smithy")


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
    export_building("fisher")


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
    export_building("town_hall")


# --- cottages (unlocked by the town hall, then upgraded like the houses) ----------------------

def cottage_house(k, walls, roof):
    """A small cottage, 4 x 3.5 m: stone footing, walls, gable roof, chimney, door and windows."""
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


def side_annex(k, sx, walls, roof, front_wall=True, window=False):
    """A lean-to room against the cottage's gable end on side `sx` (-1 left, +1 right): x from the
    wall out to 4.2 m, y -1.4..1.5, roof sloping down away from the house."""
    x0, x1 = 2.08 * sx, 4.2 * sx
    xm = (x0 + x1) / 2
    w = abs(x1 - x0)
    for y in (-1.4, 1.5):
        k.stone("Footing", (w, 0.3, 0.2), (xm, y, 0.1))
    k.stone("Footing", (0.3, 2.9, 0.2), (x1, 0.05, 0.1))
    k.box("Wall", (w, 0.12, 1.6), (xm, 1.5, 1.0), walls)  # back
    k.box("Wall", (0.12, 3.0, 1.6), (x1, 0.05, 1.0), walls)  # outer end
    if window:
        k.window((x1 + sx * 0.08, 0.3, 1.2), (0.55, 0.5), facing="x")
    if front_wall:
        k.box("Wall", (w * 0.45, 0.12, 1.6), (x1 - sx * w * 0.225, -1.4, 1.0), walls)
    else:
        k.post("Post", 0.07, 0, 1.85, x1, -1.4)
    # the triangles between the walls' tops (1.8 m) and the roof rising toward the house
    for y in (1.5, -1.4) if front_wall else (1.5,):
        bm = bmesh.new()
        pts = [(x0, 1.8), (x1, 1.8), (x0, 2.3)]
        a_ = [bm.verts.new((x, y - 0.06, z)) for x, z in pts]
        b_ = [bm.verts.new((x, y + 0.06, z)) for x, z in pts]
        bm.faces.new(a_)
        bm.faces.new(b_[::-1])
        for i in range(len(pts)):
            j = (i + 1) % len(pts)
            bm.faces.new((a_[i], b_[i], b_[j], a_[j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        k.add("Gable", bm, walls, (0, 0, 0))
    a = math.atan2(0.5, w)  # 2.35 m at the wall down to 1.85 m at the end
    k.box("Roof", (w + 0.5, 3.4, 0.1), (xm + sx * 0.1, 0.05, 2.15), roof, rot=(0, sx * a, 0))


def birch_pile(k, x, y, rows=((3, 0.12), (2, 0.34))):
    """A little stack of white birch logs along Y."""
    for row, (n, z) in enumerate(rows):
        for i in range(n):
            k.log("Birch", 1.0, 0.12, (x + (i + row * 0.5 - (n - 1) / 2) * 0.25, y, z), "y",
                  sides=("neutral.6", "neutral.7", "neutral.6", "neutral.5"), ends="wood.7")


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
    n = 5 if big else 2  # in the bakehouse the flue goes up through the roof
    for i in range(n):
        k.stone("Flue", (0.28, 0.28, 0.3), (x, y + 0.35 * s, 1.18 * s + i * 0.28 + 0.1), ("stone.3", "stone.2", "stone.1"))
    k.empty("Smoke", (x, y + 0.35 * s, 1.2 * s + n * 0.28 + 0.15))


def hanging_sign(k, x, y, z, emblem):
    """A board on a bracket sticking out from a front wall (y), with an `emblem(k, x, y, z)` on it."""
    k.box("SignBracket", (0.05, 0.6, 0.05), (x, y - 0.3, z + 0.35), "metal.1")
    k.box("Sign", (0.6, 0.05, 0.42), (x, y - 0.5, z), ("wood.6", "wood.5", "wood.4"))
    emblem(k, x, y - 0.54, z)


def baker_cottage():
    walls = ("neutral.6", "neutral.6", "neutral.5", "wood.7")

    def garden(k, barrel=True):  # a flower bed with a little fence, front left
        k.box("Bed", (1.6, 0.9, 0.18), (-2.6, -3.0, 0.09), ("terrain.dirt", "wood.2", "wood.1"))
        colors = ["accent.7", "accent.3", "neutral.7", "accent.6", "accent.1"]
        for i in range(8):
            k.box("Flower", (0.14, 0.14, 0.2), (-3.2 + (i % 4) * 0.4, -3.2 + (i // 4) * 0.4, 0.28), colors[i % 5], jit=0.02)
        for x in (-3.5, -2.6, -1.7):
            k.post("FencePost", 0.04, 0, 0.6, x, -3.55, ("wood.5", "wood.4", "wood.3"))
        k.box("FenceRail", (1.9, 0.05, 0.06), (-2.6, -3.55, 0.45), "wood.5")
        if barrel:
            k.barrel((2.6, -1.0, 0), 0.26, 0.6)

    def loaf_sign(k, x, y, z):
        k.add("SignLoaf", blob(0.14, k.rng, jitter_amount=0.1, squash=(1.6, 0.5, 0.8)), ("wood.4", "wood.3", "wood.3"),
              (x, y, z))

    reset()
    k = Kit("T1", 801)
    cottage_house(k, walls, ("wood.2", "wood.2", "wood.1", "wood.3"))
    garden(k)

    # tier 2, Bakery: a clay bread oven out on the right under a little roof, birch for the fire
    k = Kit("T2", 811)
    cottage_house(k, walls, ("wood.2", "wood.2", "wood.1", "wood.3"))
    garden(k, barrel=False)
    bread_oven(k, 3.3, 0.5)
    for x in (2.45, 4.15):
        for y in (-0.5, 1.4):
            k.post("OvenPost", 0.06, 0, 2.0, x, y)
    k.box("OvenRoof", (2.2, 2.4, 0.08), (3.3, 0.45, 2.05), ("wood.2", "wood.2", "wood.1"), rot=(0, 0.12, 0))
    birch_pile(k, 3.3, 2.3)
    k.box("Bench", (1.0, 0.4, 0.06), (2.3, -2.4, 0.5), ("wood.6", "wood.5", "wood.4"))
    for x in (1.9, 2.7):
        k.box("BenchLeg", (0.06, 0.34, 0.47), (x, -2.4, 0.235), "wood.3")
    loaves(k, 2.3, -2.4, 0.53, 3)
    hanging_sign(k, -0.85, -1.83, 2.0, loaf_sign)

    # tier 3, Bakehouse: a red roof, the oven moved into a lean-to bakehouse, a shop counter under
    # a striped awning, a bigger woodpile, a lantern by the door
    k = Kit("T3", 821)
    cottage_house(k, walls, ("accent.0", "accent.0", "wood.1", "accent.1"))
    garden(k, barrel=False)
    side_annex(k, 1, walls, ("accent.0", "accent.0", "wood.1"), front_wall=False)
    bread_oven(k, 3.15, 0.55, big=True)
    k.box("Counter", (1.7, 0.55, 0.9), (3.15, -1.85, 0.45), ("wood.6", "wood.4", "wood.3", "wood.5"))
    loaves(k, 3.15, -1.85, 0.9, 4, spread=0.36)
    k.add("Basket", prism(8, 0.22, 0.26, 0.18), ("wood.6", "wood.5", "wood.4"), (2.25, -2.4, 0.09))
    loaves(k, 2.25, -2.4, 0.12, 2, spread=0.18)
    for i in range(6):  # the awning, red and white stripes
        k.box("Awning", (0.32, 1.2, 0.05), (2.35 + i * 0.32, -2.1, 2.05), "accent.1" if i % 2 else "neutral.7",
              rot=(0.35, 0, 0))
    for x in (2.25, 4.1):
        k.post("AwningPost", 0.05, 0, 1.85, x, -2.6, ("wood.5", "wood.4", "wood.3"))
    birch_pile(k, -1.0, 2.25, rows=((4, 0.12), (3, 0.34), (2, 0.56)))
    k.box("Lantern", (0.16, 0.16, 0.22), (0.85, -1.95, 2.0), ("accent.3", "accent.3", "neutral.1"))
    hanging_sign(k, -0.85, -1.83, 2.0, loaf_sign)
    export_building("baker_cottage")


def prospector_cottage():
    walls = ("stone.4", "stone.4", "stone.3", "stone.5")
    planks = ("wood.4", "wood.3", "wood.2", "wood.5")

    def ore_pile(k):  # sorted rocks out front right: coal, gold, copper
        for i, c in enumerate(("ore.coal", "ore.gold", "ore.copper", "ore.coal", "stone.3", "ore.gold")):
            a = i * math.tau / 6
            k.add("Ore", blob(0.18, k.rng, jitter_amount=0.3, squash=(1.1, 1.0, 0.75)), (c, c, "stone.2"),
                  (2.6 + math.cos(a) * 0.35, -2.9 + math.sin(a) * 0.35, 0.12))
        k.add("Ore", blob(0.22, k.rng, jitter_amount=0.3), ("stone.4", "stone.3", "stone.2"), (2.6, -2.9, 0.3))

    def sieve_crate(k):
        k.crate((-2.6, -2.4, 0), 0.55)
        k.box("Sieve", (0.6, 0.6, 0.08), (-2.6, -2.4, 0.55), ("metal.3", "wood.4", "wood.3"))

    def coal_bin(k, x, y):
        k.box("Bin", (0.9, 0.7, 0.5), (x, y, 0.25), ("wood.3", "wood.4", "wood.2", "wood.3"))
        for i in range(5):
            k.add("Coal", blob(0.15, k.rng, jitter_amount=0.3, squash=(1.0, 1.0, 0.7)), "ore.coal",
                  (x - 0.28 + i * 0.14, y + k.rng.uniform(-0.15, 0.15), 0.52))

    def pine_beams(k, x, y):
        for i, z in enumerate((0.09, 0.09, 0.27)):
            k.box("Beam", (1.8, 0.18, 0.18), (x, y + (i - 0.5) * 0.22 if i < 2 else y, z),
                  ("wood.6", "wood.5", "wood.5", "wood.7"))

    def sorting_table(k, x, y):
        k.box("Table", (1.4, 0.7, 0.07), (x, y, 0.85), ("wood.6", "wood.5", "wood.4"))
        for ox in (-0.6, 0.6):
            for oy in (-0.28, 0.28):
                k.box("TableLeg", (0.06, 0.06, 0.82), (x + ox, y + oy, 0.41), "wood.3")
        for i, c in enumerate(("ore.coal", "ore.gold", "ore.copper", "ore.iron")):
            k.add("Sample", blob(0.08, k.rng, jitter_amount=0.3), c, (x - 0.45 + i * 0.3, y, 0.94))

    def pick_sign(k, x, y, z):
        k.box("SignPick", (0.05, 0.02, 0.32), (x, y, z), "wood.3", rot=(0, 0.6, 0))
        k.box("SignPick", (0.36, 0.02, 0.06), (x - 0.04, y, z + 0.1), "metal.2", rot=(0, 0.6, 0))

    reset()
    k = Kit("T1", 802)
    cottage_house(k, walls, ("stone.1", "stone.1", "stone.0", "stone.2"))
    ore_pile(k)
    sieve_crate(k)

    # tier 2, Assay Shed: an open-fronted plank shed on the left with a sorting table, a coal bin
    k = Kit("T2", 812)
    cottage_house(k, walls, ("stone.1", "stone.1", "stone.0", "stone.2"))
    ore_pile(k)
    sieve_crate(k)
    side_annex(k, -1, planks, ("wood.2", "wood.2", "wood.1"), front_wall=False)
    sorting_table(k, -3.15, 0.6)
    coal_bin(k, -1.0, 2.25)
    pine_beams(k, 1.0, 2.35)

    # tier 3, Assay Office: the shed closed in with a window, a little crucible furnace at the
    # back right, scales on a table out front, gold bars, a sign and a lantern
    k = Kit("T3", 822)
    cottage_house(k, walls, ("accent.4", "accent.4", "stone.0", "metal.2"))
    ore_pile(k)
    side_annex(k, -1, planks, ("accent.4", "accent.4", "stone.0"), window=True)
    k.door((-2.67, -1.46, 0.0), (1.0, 1.75), "wood.2")
    sorting_table(k, -3.15, 0.6)
    coal_bin(k, -1.0, 2.25)
    for i in range(4):  # the crucible furnace
        k.stone("Furnace", (0.9, 0.9, 0.35), (2.9, 2.6, 0.18 + i * 0.35), ("stone.3", "stone.2", "stone.1", "stone.4"))
    k.box("FurnaceMouth", (0.4, 0.08, 0.3), (2.9, 2.14, 0.55), "accent.2")
    k.add("Crucible", prism(8, 0.2, 0.26, 0.3), ("ore.gold", "metal.1", "metal.0"), (2.9, 2.6, 1.55))
    k.empty("Smoke", (2.9, 2.6, 1.9))
    tx, ty = -3.3, -2.7  # the scales table, out front of the office
    k.box("Table", (1.1, 0.6, 0.07), (tx, ty, 0.8), ("wood.6", "wood.5", "wood.4"))
    for ox in (-0.45, 0.45):
        k.box("TableLeg", (0.06, 0.5, 0.77), (tx + ox, ty, 0.385), "wood.3")
    k.post("ScalePost", 0.03, 0.83, 1.35, tx - 0.15, ty, "ore.gold")
    k.box("ScaleBeam", (0.62, 0.03, 0.03), (tx - 0.15, ty, 1.35), "ore.gold")
    for ox in (-0.28, 0.28):
        k.add("ScalePan", prism(8, 0.1, 0.12, 0.03), "ore.gold", (tx - 0.15 + ox, ty, 1.12))
    for ox, z in ((-0.1, 0.87), (0.12, 0.87), (0.01, 0.95)):
        k.box("GoldBar", (0.2, 0.1, 0.07), (tx + 0.38 + ox, ty, z), ("ore.gold", "ore.gold", "accent.2"))
    hanging_sign(k, 0.85, -1.83, 2.0, pick_sign)
    k.box("Lantern", (0.16, 0.16, 0.22), (-0.85, -1.95, 2.0), ("accent.3", "accent.3", "neutral.1"))
    export_building("prospector_cottage")


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
        k.post("Post", 0.07, 0, 2.3, x, 0, ("wood.3", "wood.3", "wood.2"))
    k.box("Board", (1.75, 0.07, 1.05), (0, 0, 1.45), ("wood.5", "wood.4", "wood.3"), jit=0.004)
    k.box("Frame", (1.85, 0.09, 0.08), (0, 0, 2.0), "wood.2")
    k.box("Frame", (1.85, 0.09, 0.08), (0, 0, 0.9), "wood.2")
    for x, side in ((0, 1), (0, -1)):
        k.box("Roof", (2.1, 0.42, 0.04), (0, side * 0.19, 2.42), ("wood.2", "wood.1", "wood.1"), rot=(side * 0.55, 0, 0))
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
                  (x + rng.uniform(-0.06, 0.06), rng.uniform(-0.1, 0.1), 0.58 + rng.uniform(0, 0.06)))
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
        k.post("Post", 0.06, 0.6, 2.0, x, 0, ("wood.3", "wood.3", "wood.2"))
    k.box("Crank", (1.5, 0.08, 0.08), (0, 0, 1.55), "wood.2")
    k.box("Handle", (0.06, 0.25, 0.06), (0.8, -0.12, 1.55), "wood.2")
    k.box("Rope", (0.02, 0.02, 0.6), (0, 0, 1.22), ("neutral.5", "neutral.5", "neutral.4"))
    k.add("Bucket", prism(8, 0.12, 0.14, 0.2), ("wood.5", "wood.4", "wood.3"), (0, 0, 0.84))
    for side in (1, -1):
        k.box("Roof", (1.8, 0.55, 0.04), (0, side * 0.24, 2.12), ("wood.2", "wood.1", "wood.1"), rot=(side * 0.6, 0, 0))
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


def dogs():
    os.makedirs(os.path.join(OUT_DIR, "dogs"), exist_ok=True)
    for breed, coats in DOG_COATS.items():
        for coat_name in coats:
            dog(breed, coat_name)


os.makedirs(os.path.join(VILLAGE_DIR, "props"), exist_ok=True)
only = sys.argv[sys.argv.index("--") + 3:]  # optional: names of the builders to run (e.g. `smithy`)
for build in (woodcutter, smithy, fisher, town_hall, baker_cottage, prospector_cottage,
              woodcutter_villager, smith_villager, fisher_villager, mayor_villager,
              baker_villager, prospector_villager,
              bench, lamp_post, lamp_post_rustic, lantern, noticeboard, planter, well, fountain, barrel_prop, crate_prop, signpost, dogs,
              doghouse, doghouse_painted, doghouse_porch, dog_bowl, dog_blanket):
    if not only or build.__name__ in only:
        build()
