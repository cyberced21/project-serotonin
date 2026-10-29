"""The trophies for your wall (plans/trophies.md), painted from the palette like our other models.

    blender -b -P tools/blender/make_trophies.py -- models art/palette.json [kind ...]

Writes models/trophies/<kind>_<look>.glb: two looks of each kind (a and b) to pick from, and for
the fish, one per species (fish_<look>_<species>.glb, the species' own model on the mount). Each
hangs from its origin, the middle of the plaque it goes on, standing out toward -Y (the room).
The small ones (geode, feather, shell) also sit on the Homestead's mantel: their origin is then
the shelf.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from make_models import OUT_DIR, blob, box, export, make_object, paint, prism, reset  # noqa: E402
import make_village as mv  # noqa: E402

FISH = ["perch", "trout", "pike", "char", "grayling", "salmon"]
BRASS = "accent.3"


def label_plate(k, z):
    """The little brass label under it."""
    k.box("Label", (0.18, 0.012, 0.05), (0, -0.035, z), (BRASS, BRASS, "ore.copper_dark"))


def shield(k, w=0.5, h=0.58, colors=("wood.3", "wood.3", "wood.2", "wood.4")):
    """A wooden plaque, pointed at the bottom, flat on the wall."""
    k.box("Plaque", (w, 0.04, h * 0.75), (0, 0.0, h * 0.12), colors)
    k.box("PlaqueTip", (w * 0.7, 0.04, w * 0.7), (0, 0.0, -h * 0.25), colors, rot=(0, math.pi / 4, 0))


def rings(k, r, y, n=6, depth=0.03):
    """Tree rings on an end face at y (facing -Y): stepped discs, bark round the edge."""
    k.add("Bark", prism(16, r + 0.02, r + 0.02, depth * 0.8), ("wood.1", "wood.1", "wood.0"), (0, y + 0.004, 0),
          (math.pi / 2, 0, 0))
    for i in range(n):
        rr = r * (1.0 - i / n)
        k.add("Ring", prism(16, rr, rr, depth + i * 0.004), "wood.6" if i % 2 == 0 else "wood.5", (0, y - i * 0.002, 0),
              (math.pi / 2, 0, 0))


def log_a():
    k = mv.Kit("", 11)
    shield(k)
    rings(k, 0.2, -0.05)
    label_plate(k, -0.27)
    return "log_a"


def log_b():
    k = mv.Kit("", 12)
    k.box("Bracket", (0.36, 0.05, 0.36), (0, 0.0, 0.0), ("wood.2", "wood.2", "wood.1"))
    bm = prism(10, 0.15, 0.16, 0.34)
    k.add("Log", bm, ("wood.2", "wood.3", "wood.1"), (0, -0.19, 0), (math.pi / 2, 0, 0))
    rings(k, 0.14, -0.36, n=5, depth=0.02)
    label_plate(k, -0.24)
    return "log_b"


def fish_mount(look, species):
    """The species' own model on a board: an oval (a) or a shield, the fish leaping (b)."""
    k = mv.Kit("", 21 if look == "a" else 22)
    if look == "a":
        board = prism(14, 0.42, 0.42, 0.04)
        for v in board.verts:
            v.co.y *= 0.55
        k.add("Board", board, ("wood.4", "wood.4", "wood.3", "wood.5"), (0, 0.0, 0), (math.pi / 2, 0, 0))
    else:
        shield(k, 0.62, 0.62, ("wood.2", "wood.2", "wood.1", "wood.3"))
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT_DIR, "fish", species + ".glb"))
    parts = [o for o in bpy.data.objects if o not in before]
    tilt = 0.0 if look == "a" else 0.35
    for o in parts:
        if o.parent is None:  # side on along the board (the fish models swim along Y)
            o.location = (0, -0.1, 0.02)
            o.rotation_mode = "XYZ"  # (the importer leaves it on quaternions)
            o.rotation_euler = (0, tilt, math.pi / 2)
            o.scale = (0.95, 0.95, 0.95)  # (a fish model is already Huge-sized, ~0.85 m)
    bpy.context.view_layer.update()  # centred on the board (the fish models' origin is the head)
    meshes = [o for o in parts if o.type == "MESH"]
    corners = [o.matrix_world @ mv.Vector(c) for o in meshes for c in o.bound_box]
    mid = sum(corners, mv.Vector()) / len(corners)
    front = max(c.y for c in corners)
    for o in parts:
        if o.parent is None:
            o.location.x -= mid.x
            o.location.z -= mid.z - 0.02
            o.location.y -= front + 0.03  # its back just clear of the board
    for i, o in enumerate(o for o in parts if o.type == "MESH"):
        o.name = f"Fish{i:02d}"
    label_plate(k, -0.27 if look == "a" else -0.3)
    return f"fish_{look}_{species}"


def geode(look):
    """Half a geode, its crystals showing: amethyst on a stand (a), sapphire in a little box (b)."""
    k = mv.Kit("", 31 if look == "a" else 32)
    crystal = ("ore.amethyst", "accent.6", "accent.6") if look == "a" else ("ore.sapphire", "accent.4", "accent.5")
    shell = blob(0.16, k.rng, jitter_amount=0.25, squash=(1.0, 0.55, 0.9))
    k.add("GeodeRind", shell, ("stone.3", "stone.2", "stone.4"), (0, 0.02, 0.18))
    k.add("GeodeHollow", prism(10, 0.11, 0.11, 0.02), "neutral.1", (0, -0.065, 0.18), (math.pi / 2, 0, 0))
    for i in range(9):
        a = i * math.tau / 9
        h = 0.05 + (i % 3) * 0.02
        k.add("GeodeCrystal", prism(6, 0.022, 0.004, h), crystal,
              (math.cos(a) * 0.06, -0.07, 0.18 + math.sin(a) * 0.06), (math.pi / 2 + math.sin(a) * 0.5, math.cos(a) * 0.5, 0))
    if look == "a":
        k.add("Stand", prism(8, 0.12, 0.1, 0.04), ("wood.4", "wood.3", "wood.2"), (0, 0.0, 0.02))
    else:
        for x in (-0.22, 0.22):
            k.box("BoxSide", (0.03, 0.2, 0.42), (x, 0.0, 0.18), ("wood.2", "wood.2", "wood.1"))
        for z in (-0.02, 0.38):
            k.box("BoxSide", (0.47, 0.2, 0.03), (0, 0.0, z), ("wood.2", "wood.2", "wood.1"))
        k.box("BoxBack", (0.44, 0.02, 0.4), (0, 0.09, 0.18), "accent.0")
    label_plate(k, -0.06)
    return f"geode_{look}"


def sheaf(look):
    """Gold-tinted wheat: a bundle tied with a red ribbon (a), or a wreath (b)."""
    k = mv.Kit("", 41 if look == "a" else 42)
    stalk = ("accent.3", "accent.3", "terrain.sand")
    head = ("accent.3", "ore.gold", "accent.2")
    if look == "a":
        for i in range(11):
            a = (i - 5) * 0.07
            k.box("Stalk", (0.012, 0.012, 0.55), (math.sin(a) * 0.25, -0.04, 0.0), stalk, rot=(0, a, 0))
            k.add("Head", blob(0.03, k.rng, jitter_amount=0.15, squash=(0.7, 0.7, 2.2)), head,
                  (math.sin(a) * 0.53, -0.04, 0.27 * math.cos(a) + 0.02))
        k.add("Ribbon", prism(10, 0.05, 0.05, 0.05), ("accent.0", "accent.0", "accent.1"), (0, -0.04, -0.02))
        k.box("Bow", (0.16, 0.02, 0.05), (0, -0.07, -0.02), "accent.0", rot=(0, 0.4, 0))
    else:
        for i in range(16):
            a = i * math.tau / 16
            k.add("Head", blob(0.035, k.rng, jitter_amount=0.15, squash=(0.7, 0.7, 2.2)), head,
                  (math.cos(a) * 0.2, -0.04, math.sin(a) * 0.2), (0, -a, 0))
        k.add("Ribbon", prism(10, 0.04, 0.04, 0.04), ("accent.0", "accent.0", "accent.1"), (0, -0.05, -0.21))
    label_plate(k, -0.33)
    return f"sheaf_{look}"


def feather(look):
    """An eagle's feather: in a little glass-fronted frame (a), or standing on a pin (b)."""
    k = mv.Kit("", 51 if look == "a" else 52)

    def quill(x, z, rot, s=1.0):
        k.box("Quill", (0.012, 0.012, 0.42 * s), (x, -0.05, z), "wood.7", rot=(0, rot, 0))
        vane = box((0.08 * s, 0.01, 0.34 * s))
        for v in vane.verts:
            if v.co.z > 0:
                v.co.x *= 0.35  # narrowing to the tip
        k.add("Vane", vane, ("neutral.6", "wood.7", "neutral.5"), (x + math.sin(rot) * 0.03, -0.05, z + 0.03), (0, rot, 0))
        k.box("Tip", (0.06 * s, 0.011, 0.07 * s), (x + math.sin(rot) * 0.18, -0.05, z + 0.19 * s), "wood.1", rot=(0, rot, 0))

    if look == "a":
        for x in (-0.2, 0.2):
            k.box("Frame", (0.04, 0.06, 0.56), (x, -0.02, 0.0), ("wood.2", "wood.2", "wood.1"))
        for z in (-0.26, 0.26):
            k.box("Frame", (0.44, 0.06, 0.04), (0, -0.02, z), ("wood.2", "wood.2", "wood.1"))
        k.box("Back", (0.38, 0.01, 0.5), (0, 0.0, 0.0), "accent.4")
        quill(0.0, -0.02, 0.5)
        k.box("Glass", (0.38, 0.005, 0.5), (0, -0.05, 0.0), "neutral.7")
    else:
        k.add("Stand", prism(8, 0.08, 0.07, 0.03), ("wood.4", "wood.3", "wood.2"), (0, -0.05, 0.015))
        k.box("Pin", (0.01, 0.01, 0.1), (0, -0.05, 0.08), "metal.4")
        quill(0.0, 0.3, 0.12, 1.1)
    label_plate(k, -0.31 if look == "a" else -0.03)
    return f"feather_{look}"


def shell(look):
    """A big spiral shell: on a little stand (a), or in a wooden dish (b)."""
    k = mv.Kit("", 61 if look == "a" else 62)
    z0 = 0.13 if look == "a" else 0.11
    lean = (0.0, 0.9, 0.3)  # the spire lying back and to one side
    k.add("Spire", prism(14, 0.12, 0.008, 0.32), ("wood.7", "accent.7", "neutral.6"), (0.03, -0.03, z0), lean)
    for i in range(5):  # the spiral's ridges round it, tightening toward the tip
        t = i / 5
        k.add("Ridge", prism(14, 0.125 * (1 - t) + 0.01, 0.12 * (1 - t), 0.018), ("accent.7", "wood.6", "accent.7"),
              (0.03 + math.sin(0.9) * 0.3 * t, -0.03, z0 + math.cos(0.9) * 0.3 * t), lean)
    k.add("Lip", blob(0.1, k.rng, jitter_amount=0.15, squash=(1.3, 0.7, 0.8)), ("neutral.6", "accent.7", "neutral.7"),
          (-0.07, -0.05, z0 - 0.03))
    if look == "a":
        k.add("Stand", prism(8, 0.12, 0.1, 0.04), ("wood.4", "wood.3", "wood.2"), (0, 0.0, 0.02))
    else:
        k.add("Dish", prism(12, 0.2, 0.16, 0.04), ("wood.5", "wood.4", "wood.3"), (0, -0.02, 0.02))
    label_plate(k, -0.03)
    return f"shell_{look}"


def stick(look):
    """The dog's stick: on two brass brackets (a), or on a plaque with a red bow (b)."""
    k = mv.Kit("", 71 if look == "a" else 72)
    if look == "b":
        shield(k, 0.62, 0.5)
    for i, (x, rot) in enumerate(((-0.17, 0.12), (0.18, -0.08))):
        k.log("Stick", 0.38, 0.025, (x, -0.06, 0.04 + i * 0.015), "x", sides=("wood.3", "wood.2", "wood.4"), ends="wood.6")
    k.log("Twig", 0.12, 0.012, (0.05, -0.06, 0.1), "x", sides=("wood.3",), ends="wood.6")
    if look == "a":
        for x in (-0.2, 0.2):
            k.box("Bracket", (0.03, 0.08, 0.08), (x, -0.03, 0.0), (BRASS, BRASS, "ore.copper_dark"))
    else:
        k.box("Bow", (0.12, 0.02, 0.05), (0, -0.09, 0.05), "accent.0", rot=(0, 0.5, 0))
        k.box("Bow", (0.12, 0.02, 0.05), (0, -0.09, 0.05), "accent.0", rot=(0, -0.5, 0))
    label_plate(k, -0.12 if look == "a" else -0.2)
    return f"stick_{look}"


BUILDERS = {
    "log": lambda look: log_a() if look == "a" else log_b(),
    "geode": geode, "sheaf": sheaf, "feather": feather, "shell": shell, "stick": stick,
}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:]
    kinds = argv[2:] or list(BUILDERS) + ["fish"]
    os.makedirs(os.path.join(OUT_DIR, "trophies"), exist_ok=True)
    for kind in kinds:
        for look in ("a", "b"):
            if kind == "fish":
                for species in FISH:
                    reset()
                    name = fish_mount(look, species)
                    export(os.path.join("trophies", name))
                continue
            reset()
            name = BUILDERS[kind](look)
            export(os.path.join("trophies", name))
