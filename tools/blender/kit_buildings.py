"""Village buildings put together from the Quaternius Medieval Village kit (CC0), in the kit's own
colours (plans/home.md, phase 2). Our own generated pieces (make_village.Kit) still go alongside
for what the kit lacks: ovens, signs, gardens.

    blender -b -P tools/blender/kit_buildings.py -- models art/palette.json [building ...]

The kit's modules sit on a 2 m grid: walls are 2 m wide and 3 m to the top of their trim, floors
are 2 x 2 m tiles, roofs come in footprint sizes (Roof_RoundTiles_<width>x<depth>, ridge along Y)
with a matching gable infill (Roof_Front_Brick<width>). A building is centred on the origin with
its front (door) facing -Y, like make_village's.

Pieces are named like make_village's (T<tier>_Kit<Piece><n>), so Building shows them by tier. Kit
pieces keep their materials (Building leaves them alone) and window glass is split off into its own
palette-painted "WindowGlass" mesh, so the windows still light up at night.

Writes models/village/<name>.gltf, sharing its textures in models/village/textures/ with every other
kit building. The kit's source files live in art/kit/village/ (see its SOURCES.md).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from make_models import OUT_DIR, swatch_uv, weather_stonework  # noqa: E402
import make_village as mv  # noqa: E402

KIT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "art", "kit")
KIT_DIRS = [os.path.join(KIT_ROOT, "village"), os.path.join(KIT_ROOT, "props")]  # walls etc., then furniture
GLASS = "MI_WindowGlass"
WALL_TOP = 3.0  # where a wall's trim ends and the next storey or roof starts

_cache = {}  # piece -> [(mesh, is_glass)]


def _load(piece):
    """The piece's meshes (transforms applied, glass split out), imported once."""
    if piece in _cache:
        return _cache[piece]
    before = set(bpy.data.objects)
    path = next(p for p in (os.path.join(d, piece + ".gltf") for d in KIT_DIRS) if os.path.exists(p))
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    parts = []
    for o in new:
        if o.type != "MESH":
            continue
        me = o.data.copy()
        me.transform(o.matrix_world)
        glass = [i for i, m in enumerate(me.materials) if m and m.name.startswith(GLASS)]
        if glass:
            parts.append((_split(me, glass, keep=False), False))
            parts.append((_split(me, glass, keep=True), True))
        else:
            parts.append((me, False))
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    _cache[piece] = [(m, g) for m, g in parts if len(m.polygons)]
    return _cache[piece]


def _split(me, slots, keep):
    """A copy of `me` with only the faces whose material is (keep=True) or isn't in `slots`."""
    out = me.copy()
    bm = bmesh.new()
    bm.from_mesh(out)
    drop = [f for f in bm.faces if (f.material_index in slots) != keep]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    if keep:  # glass: palette-painted (no material) so Building can light it
        uv = bm.loops.layers.uv.active or bm.loops.layers.uv.new()
        u = swatch_uv("neutral.2")
        for f in bm.faces:
            for loop in f.loops:
                loop[uv].uv = u
    bm.to_mesh(out)
    bm.free()
    if keep:
        out.materials.clear()
    return out


def reset():
    """A fresh scene for the next building (the cached kit meshes go with the old one)."""
    mv.reset()
    _cache.clear()


def place(k, piece, loc, rot=0.0):
    """Adds the kit piece at `loc`, turned `rot` degrees about Z. Named <tier>_Kit<Piece><n>."""
    objs = []
    for me, glass in _load(piece):
        base = "WindowGlass" if glass else "Kit" + piece.replace("_", "")
        o = bpy.data.objects.new(k.name(base), me)
        bpy.context.collection.objects.link(o)
        o.location = loc
        o.rotation_euler = (0, 0, math.radians(rot))
        objs.append(o)
    return objs


# --- walls ------------------------------------------------------------------------------------

WALLS = {  # style -> what each letter in a wall's pattern places
    "plaster": {"w": "Wall_Plaster_Straight", "t": "Wall_Plaster_WoodGrid", "o": "Wall_Plaster_Window_Wide_Round",
                "n": "Wall_Plaster_Window_Thin_Round", "d": "Wall_Plaster_Door_Round"},
    "brick": {"w": "Wall_UnevenBrick_Straight", "t": "Wall_UnevenBrick_Straight", "o": "Wall_UnevenBrick_Window_Wide_Round",
              "n": "Wall_UnevenBrick_Window_Thin_Round", "d": "Wall_UnevenBrick_Door_Round"},
}
FILL = {"o": ("Window_Wide_Round1", "WindowShutters_Wide_Round_Open"), "n": ("Window_Thin_Round1", None)}


def wall_run(k, style, pattern, start, step, out_rot, z0):
    """One side of a storey: a module per letter of `pattern` (w plain, t timbered, o wide window,
    n thin window, d door, - nothing), from `start` stepping `step`, facing out at `out_rot`."""
    x, y = start
    for c in pattern:
        if c != "-":
            place(k, WALLS[style][c], (x, y, z0), out_rot)
            if c in FILL:
                win, shutters = FILL[c]
                place(k, win, (x, y, z0), out_rot)
                if shutters:
                    place(k, shutters, (x, y, z0), out_rot)
            if c == "d":
                place(k, "DoorFrame_Round_WoodDark", (x, y, z0), out_rot)
                # the leaf, hinged at the doorway's left edge (Building swings it about its origin)
                a = math.radians(out_rot)
                hx, hy = -0.53, 0.1
                place(k, "Door_1_Round", (x + hx * math.cos(a) - hy * math.sin(a), y + hx * math.sin(a) + hy * math.cos(a), z0),
                      out_rot)
                # just inside it: villagers come and go by here (Villager._route_to)
                inward = (-math.sin(a), math.cos(a))
                marker(k, "Doorway", x + inward[0] * 0.9, y + inward[1] * 0.9, z0, inward)
        x += step[0]
        y += step[1]


def storey(k, nx, ny, style, front, back, left, right, z0=0.0, floor="Floor_WoodDark", corners="Corner_Exterior_Wood",
           holes=()):
    """A box of walls nx x ny modules (2 m each) round the origin, front at -Y. Each side's pattern
    is read left to right as seen from outside. `holes`: floor cells (i, j) left open (a stairwell)."""
    hw, hd = nx, ny  # half width and depth in metres (2 m modules)
    wall_run(k, style, front, (-hw + 1, -hd), (2, 0), 0, z0)
    wall_run(k, style, back, (hw - 1, hd), (-2, 0), 180, z0)
    wall_run(k, style, left, (-hw, hd - 1), (0, -2), -90, z0)
    wall_run(k, style, right, (hw, -hd + 1), (0, 2), 90, z0)
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        place(k, corners, (sx * hw, sy * hd, z0), 0)
    if floor:
        for i in range(nx):
            for j in range(ny):
                if (i, j) not in holes:
                    place(k, floor, (-hw + 1 + 2 * i, -hd + 1 + 2 * j, z0 + 0.01), 0)


def gable_roof(k, nx, ny, z0, gables="Roof_Front_Brick"):
    """The kit's tiled roof for an nx x ny storey whose walls end at z0, with gable infills."""
    w, d = 2 * nx, 2 * ny
    place(k, f"Roof_RoundTiles_{w}x{d}", (0, 0, z0), 0)
    for y, r in ((-ny, 0), (ny, 180)):
        place(k, f"{gables}{w}", (0, y, z0), r)


# --- furniture and the places it makes ---------------------------------------------------------
# Markers (empties the game reads as Marker3Ds, see make_village.mark): Bed (foot of the mattress,
# facing the pillow), Seat* (a chair: anyone sits, the villager first), Look* (something to look
# at: BuildingDef.looks), Stair0/Stair1 (the stair's foot and head, for villagers going up).

DIRS = {"-y": 0, "+x": 90, "+y": 180, "-x": -90}  # a prop's front (its -Y) turned to face this way


def prop(k, piece, x, y, z=0.0, facing="-y"):
    return place(k, piece, (x, y, z), DIRS[facing])


def marker(k, name, x, y, z=0.0, facing=(0.0, -1.0)):
    return mv.mark(f"{k.prefix}_{name}", (x, y, z), facing)


VEC = {"+y": (0, 1), "-y": (0, -1), "+x": (1, 0), "-x": (-1, 0)}
BACK = {"+y": "-y", "-y": "+y", "+x": "-x", "-x": "+x"}


def bed(k, x, y, z=0.0, pillow="+y", piece="Bed_Twin1"):
    """A bed centred at x, y with its pillow toward `pillow`, and the Bed marker at its foot."""
    prop(k, piece, x, y, z, facing=BACK[pillow])
    d = VEC[pillow]
    marker(k, "Bed", x - d[0] * 0.95, y - d[1] * 0.95, z + 0.45, d)


def chair(k, name, x, y, z=0.0, facing="+x"):
    """A chair whose sitter faces `facing`, with its Seat marker."""
    prop(k, "Chair_1", x, y, z, facing=BACK[facing])
    marker(k, name, x, y, z, VEC[facing])


def look(k, name, x, y, z):
    marker(k, "Look" + name, x, y, z)


# --- moving a house back on its plot -------------------------------------------------------------
# The village's buildings keep their fronts (and so their doors, spots and paths) where the old
# models had them and grow toward the back: a house is built round the origin, then moved back.

def built(k):
    """Everything made since now (call .back(dy) to move it all back by dy along +Y)."""
    return _Since()


class _Since:
    def __init__(self):
        self.before = set(bpy.data.objects)

    def back(self, dy):
        for o in bpy.data.objects:
            if o not in self.before and o.parent is None:
                o.location.y += dy


# --- the bakery ---------------------------------------------------------------------------------

def bakery_room(k, hw, hd, z=0.0):
    """Rosa's room (tier 1, and upstairs at the top): bed, table and chairs, her recipes."""
    bed(k, -hw + 1.1, hd - 1.45, z)
    prop(k, "Nightstand_Shelf", -hw + 2.45, hd - 0.35, z)
    prop(k, "Table_Large", hw - 1.6, 0.2, z, facing="+x")
    chair(k, "Seat1", hw - 2.4, -0.5, z)
    chair(k, "Seat2", hw - 2.4, 0.9, z)
    prop(k, "Bookcase_2", hw - 1.1, hd - 0.35, z)
    look(k, "Recipes", hw - 1.1, hd - 0.5, z + 1.4)
    prop(k, "Chandelier", 0, 0, z + WALL_TOP - 0.1)


def bakery_shop(k):
    """The shop in a 6 x 8 storey: a counter facing the door, bread on a shelf, flour, the oven."""
    prop(k, "Table_Large", 0.9, -1.4)
    prop(k, "Shelf_Simple", 2.65, -0.8, 1.6, facing="-x")
    mv.loaves(k, 2.45, -0.8, 1.63, 3, 0.25)
    mv.loaves(k, 0.9, -1.4, 0.82, 4, 0.3)
    prop(k, "FarmCrate_Empty", 2.3, -3.5)
    mv.bread_oven(k, 1.6, 2.9, big=True)
    look(k, "Oven", 1.6, 2.4, 1.0)


def baker_cottage():
    reset()
    # Cottage: one room, 6 x 6 m, gable to the lane, a chimney
    k = mv.Kit("T1", 201)
    storey(k, 3, 3, "plaster", front="odo", back="wnw", left="wow", right="wow")
    gable_roof(k, 3, 3, WALL_TOP)
    bakery_room(k, 3, 3)
    prop(k, "Bag", -2.4, -2.3)
    look(k, "Flour", -2.4, -2.3, 0.5)
    place(k, "Prop_Chimney", (1.8, 1.5, WALL_TOP + 0.5), 0)
    k.empty("Smoke", (1.8, 1.5, WALL_TOP + 3.8))

    # Bakery: 6 x 8 m on a stone base, the shop at the front, the oven and her bed at the back
    k = mv.Kit("T2", 202)
    house = built(k)
    storey(k, 3, 4, "brick", front="odo", back="wnw", left="wowo", right="owow")
    gable_roof(k, 3, 4, WALL_TOP)
    bakery_shop(k)
    bed(k, -1.9, 2.55)
    prop(k, "Nightstand_Shelf", -0.55, 3.65)
    prop(k, "Barrel", -0.4, 0.9)
    chair(k, "Seat1", -1.1, 0.9, facing="+x")
    chair(k, "Seat2", 0.35, 0.9, facing="-x")
    prop(k, "Bag", -2.4, -3.3)
    look(k, "Flour", -2.4, -3.3, 0.5)
    prop(k, "Chandelier", 0, 0, WALL_TOP - 0.1)
    place(k, "Prop_Chimney", (1.6, 2.4, WALL_TOP + 1.0), 0)
    k.empty("Smoke", (1.6, 2.4, WALL_TOP + 4.3))
    mv.hanging_sign(k, -2.0, -4.1, 2.4, lambda k, x, y, z: mv.loaves(k, x, y, z - 0.08, 2, 0.2))
    house.back(1.0)

    # Bakehouse: two storeys, the shop below, Rosa's rooms above (a stair up the left wall)
    k = mv.Kit("T3", 203)
    house = built(k)
    storey(k, 3, 4, "brick", front="odo", back="wnw", left="wowo", right="owow")
    storey(k, 3, 4, "plaster", front="tot", back="tnt", left="toto", right="toto", z0=WALL_TOP,
           floor="Floor_WoodLight", holes={(0, 1), (0, 2)})
    place(k, "Stair_Interior_Solid", (-2.1, -3.0, 0.0), 0)
    marker(k, "Stair0", -2.1, -3.6, 0.0, (0, 1))
    marker(k, "Stair1", -2.1, 1.6, WALL_TOP, (0, 1))
    gable_roof(k, 3, 4, 2 * WALL_TOP)
    bakery_shop(k)
    prop(k, "Bag", -2.4, 3.3)
    look(k, "Flour", -2.4, 3.3, 0.5)
    z = WALL_TOP  # upstairs
    bed(k, 1.9, 2.55, z)
    prop(k, "Nightstand_Shelf", 0.55, 3.65, z)
    prop(k, "Bookcase_2", -0.5, 3.65, z)
    look(k, "Recipes", -0.5, 3.5, z + 1.4)
    prop(k, "Table_Large", 1.4, -1.6, z, facing="+x")
    chair(k, "Seat1", 0.6, -2.3, z)
    chair(k, "Seat2", 0.6, -0.9, z)
    prop(k, "Chandelier", 0.6, 0, z + WALL_TOP - 0.1)
    place(k, "Prop_Chimney", (1.6, 2.4, 2 * WALL_TOP + 1.0), 0)
    k.empty("Smoke", (1.6, 2.4, 2 * WALL_TOP + 4.3))
    mv.hanging_sign(k, -2.0, -4.1, 2.4, lambda k, x, y, z: mv.loaves(k, x, y, z - 0.08, 3, 0.16))
    house.back(1.0)
    export_kit_building("baker_cottage")


# --- the woodcutter's lodge ---------------------------------------------------------------------

def woodcutter():
    reset()
    k = mv.Kit("T1", 101)
    mv.lean_to(k)  # the lean-to camp, as it was

    # Log Cabin: 6 x 6 m of timber and plaster, the chopping block and firewood outside
    k = mv.Kit("T2", 102)
    house = built(k)
    storey(k, 3, 3, "plaster", front="tdt", back="tot", left="tot", right="tot")
    gable_roof(k, 3, 3, WALL_TOP)
    bed(k, -1.9, 1.5)
    prop(k, "Table_Large", 1.5, 2.3)
    chair(k, "Seat1", 0.9, 1.5, facing="+y")
    chair(k, "Seat2", 2.1, 1.5, facing="+y")
    prop(k, "WeaponStand", -0.2, 2.5)
    prop(k, "Axe_Bronze", -0.2, 2.45, 0.6)
    look(k, "Axe", -0.2, 2.35, 1.0)
    prop(k, "Lantern_Wall", -2.6, -1.0, 1.0, facing="+x")
    house.back(1.0)
    k.chopping_block((-3.4, -2.9, 0))
    for x, z in ((3.45, 0.13), (3.72, 0.13), (3.58, 0.37)):
        k.log("Firewood", 1.1, 0.13, (x, 0.3, z), "y")

    # Lodge: 6 x 6 m with a porch, a chimney, a workbench and a woodpile
    k = mv.Kit("T3", 103)
    house = built(k)
    storey(k, 3, 3, "plaster", front="tdt", back="tot", left="tot", right="tot")
    gable_roof(k, 3, 3, WALL_TOP)
    bed(k, -1.9, 1.55)
    prop(k, "Table_Large", 1.6, -0.4, facing="+x")
    chair(k, "Seat1", 0.8, -1.1)
    chair(k, "Seat2", 0.8, 0.3)
    prop(k, "Workbench", 1.6, 2.4, facing="-y")
    look(k, "Bench", 1.6, 2.2, 1.1)
    prop(k, "WeaponStand", -0.2, 2.65)
    prop(k, "Axe_Bronze", -0.2, 2.6, 0.6)
    look(k, "Axe", -0.2, 2.5, 1.0)
    prop(k, "Chandelier", 0, 0, WALL_TOP - 0.1)
    place(k, "Prop_Chimney", (2.0, 1.0, WALL_TOP + 0.5), 0)
    k.empty("Smoke", (2.0, 1.0, WALL_TOP + 3.8))
    house.back(1.0)
    # the porch along the front: planks on two beams, posts, a gently sloping roof, a step
    for y in (-2.45, -3.4):
        k.log("PorchBeam", 6.0, 0.12, (0, y, 0.12), "x")
    for i in range(5):
        k.box("PorchPlank", (6.0, 0.31, 0.08), (0, -2.3 - i * 0.33, 0.3), ("wood.6", "wood.5", "wood.4"), jit=0.01)
    for sx in (-1, 1):
        k.post("PorchPost", 0.09, 0.34, 2.6, sx * 2.8, -3.5)
    k.box("PorchRoof", (6.3, 1.85, 0.1), (0, -2.95, 2.63), ("wood.2", "wood.2", "wood.1"), rot=(0.17, 0, 0))
    k.box("Step", (1.4, 0.4, 0.18), (0, -3.95, 0.09), ("wood.5", "wood.4", "wood.3"))
    # a big woodpile under a little roof on the left, a lantern by the door, the chopping block
    for row, (n, z) in enumerate(((4, 0.14), (3, 0.4), (2, 0.66))):
        for i in range(n):
            k.log("Woodpile", 1.6, 0.14, (-3.35 - (i + row * 0.5) * 0.28, 0.6, z), "y")
    k.box("WoodpileRoof", (1.4, 2.0, 0.08), (-3.8, 0.6, 1.2), ("wood.2", "wood.2", "wood.1"), rot=(0, 0.25, 0))
    k.box("Lantern", (0.16, 0.16, 0.22), (0.95, -2.3, 2.0), ("accent.3", "accent.3", "neutral.1"))
    k.chopping_block((-3.6, -4.5, 0))
    export_kit_building("woodcutter")


# --- the fisher's hut ---------------------------------------------------------------------------

FLOOR = 0.6  # the hut stands on stilts


def stilt_hut(k):
    """A 4 x 4 m hut on stilts, its door at the front right with steps down."""
    storey(k, 2, 2, "plaster", front="od", back="tw", left="ow", right="wo", z0=FLOOR)
    gable_roof(k, 2, 2, FLOOR + WALL_TOP)
    for x in (-1.9, 0.0, 1.9):
        for y in (-1.9, 0.0, 1.9):
            k.post("Stilt", 0.1, -0.3, FLOOR, x, y, ("wood.3", "wood.2", "wood.1"))
    mv.front_steps(k, 1.0, -2.1, FLOOR, 1.0, 0.3, ("wood.5", "wood.4", "wood.3"))
    bed(k, -0.95, 0.8, FLOOR, piece="Bed_Twin2")
    chair(k, "Seat1", 1.1, 1.3, FLOOR, facing="-y")
    prop(k, "Stool", 1.1, -0.1, FLOOR)
    marker(k, "Seat2", 1.1, -0.1, FLOOR, (-1, 0))
    prop(k, "Peg_Rack", -1.0, -1.85, FLOOR + 1.6)
    prop(k, "Lantern_Wall", 1.85, 0.4, FLOOR + 1.0, facing="-x")
    look(k, "Rod", -1.0, -1.7, FLOOR + 1.5)


def fisher():
    reset()
    k = mv.Kit("T1", 301)
    for side in (-1, 1):  # the camp, as it was: a canvas tent, a drying rack, a crate and a rod
        k.box("Tent", (1.3, 2.2, 0.05), (-1.0 + side * 0.45, 0.3, 0.68), ("neutral.6", "neutral.5", "neutral.4"),
              rot=(0, side * 0.9, 0))
    k.post("TentPole", 0.04, 0, 1.4, -1.0, -0.8)
    k.box("TentRidge", (0.05, 2.3, 0.05), (-1.0, 0.3, 1.38), "wood.3")
    mv.drying_rack(k, 0.8, 2.6, -0.6)
    k.crate((-2.4, -1.2, 0), 0.55)
    k.box("Rod", (0.03, 0.03, 2.4), (1.0, 0.9, 1.1), "wood.5", rot=(0.4, 0, 0.2))
    k.add("Bucket", mv.prism(8, 0.18, 0.2, 0.3), ("accent.4", "wood.3", "wood.2"), (0.3, -1.4, 0.15))

    k = mv.Kit("T2", 302)
    stilt_hut(k)
    mv.drying_rack(k, 2.5, 4.0, -0.4)
    k.barrel((-2.6, -1.0, 0), 0.28, 0.7)

    k = mv.Kit("T3", 303)
    stilt_hut(k)
    place(k, "Prop_Chimney", (-1.0, 1.0, FLOOR + WALL_TOP + 0.2), 0)
    k.empty("Smoke", (-1.0, 1.0, FLOOR + WALL_TOP + 3.5))
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
    bm = mv.box((0.95, 2.3, 0.36))  # a little rowboat tied up alongside
    for v in bm.verts:
        if abs(v.co.y) > 1.0:
            v.co.x *= 0.3
        if v.co.z < 0:
            v.co.x *= 0.7
    k.add("Boat", bm, ("wood.2", "wood.4", "wood.3", "wood.5"), (2.75, -4.9, -0.05))
    k.box("BoatSeat", (0.8, 0.25, 0.05), (2.75, -4.9, 0.08), "wood.6")
    for y in (-1.0, 0.8):  # nets drying on a rack, barrels
        k.post("NetPost", 0.06, 0, 1.9, -2.9, y)
    k.box("NetBar", (0.06, 2.0, 0.06), (-2.9, -0.1, 1.85), "wood.4")
    k.box("Net", (0.04, 1.7, 1.25), (-2.9, -0.1, 1.15), ("neutral.3", "neutral.3", "neutral.2"), jit=0.03)
    mv.drying_rack(k, 2.5, 4.0, -0.4)
    k.barrel((-2.6, -1.9, 0), 0.28, 0.7)
    k.barrel((-2.0, -2.4, 0), 0.25, 0.6)
    export_kit_building("fisher")


# --- the prospector's cottage -------------------------------------------------------------------

def assay_things(k, z=0.0):
    """Edda's work: a bench of drawers, bottles on a shelf, her ledger on its stand."""
    prop(k, "Workbench_Drawers", 1.6, -1.3, z, facing="+x")
    prop(k, "Shelf_Small_Bottles", 2.65, 0.6, z + 1.5, facing="-x")
    look(k, "Samples", 2.5, 0.6, z + 1.5)
    prop(k, "BookStand", 1.5, 0.4, z, facing="+x")
    look(k, "Ledger", 1.5, 0.4, z + 1.1)


def prospector_cottage():
    reset()
    # Cottage: 6 x 6 m, its front where the old one's was
    k = mv.Kit("T1", 501)
    house = built(k)
    storey(k, 3, 3, "plaster", front="odo", back="wnw", left="wow", right="wow")
    gable_roof(k, 3, 3, WALL_TOP)
    bed(k, -1.9, 1.55)
    prop(k, "Table_Large", 1.6, 0.3, facing="+x")
    chair(k, "Seat1", 0.8, -0.4)
    chair(k, "Seat2", 0.8, 1.0)
    prop(k, "Bookcase_2", 1.9, 2.65)
    look(k, "Maps", 1.9, 2.5, 1.4)
    prop(k, "Chandelier", 0, 0, WALL_TOP - 0.1)
    place(k, "Prop_Chimney", (-1.8, 1.5, WALL_TOP + 0.5), 0)
    k.empty("Smoke", (-1.8, 1.5, WALL_TOP + 3.8))
    house.back(1.0)

    # Assay Shed: 6 x 8 m, her bench, samples and ledger at the front
    k = mv.Kit("T2", 502)
    house = built(k)
    storey(k, 3, 4, "brick", front="odo", back="wnw", left="wowo", right="owow")
    gable_roof(k, 3, 4, WALL_TOP)
    assay_things(k)
    bed(k, -1.9, 2.55)
    prop(k, "Nightstand_Shelf", -0.55, 3.65)
    chair(k, "Seat1", 0.7, -1.3, facing="+x")
    prop(k, "Stool", -1.4, -2.5)
    marker(k, "Seat2", -1.4, -2.5, 0.0, (0, -1))
    prop(k, "Crate_Wooden", -2.4, -3.3)
    prop(k, "Chandelier", 0, 0, WALL_TOP - 0.1)
    place(k, "Prop_Chimney", (-1.8, 2.4, WALL_TOP + 1.0), 0)
    k.empty("Smoke", (-1.8, 2.4, WALL_TOP + 4.3))
    house.back(2.0)

    # Assay Office: two storeys, the office below, her rooms above
    k = mv.Kit("T3", 503)
    house = built(k)
    storey(k, 3, 4, "brick", front="odo", back="wnw", left="wowo", right="owow")
    storey(k, 3, 4, "plaster", front="tot", back="tnt", left="toto", right="toto", z0=WALL_TOP,
           floor="Floor_WoodLight", holes={(0, 1), (0, 2)})
    place(k, "Stair_Interior_Solid", (-2.1, -3.0, 0.0), 0)
    marker(k, "Stair0", -2.1, -3.6, 0.0, (0, 1))
    marker(k, "Stair1", -2.1, 1.6, WALL_TOP, (0, 1))
    gable_roof(k, 3, 4, 2 * WALL_TOP)
    assay_things(k)
    chair(k, "Seat1", 0.7, -1.3, facing="+x")
    prop(k, "Bookcase_2", 1.9, 3.65)
    look(k, "Maps", 1.9, 3.5, 1.4)
    z = WALL_TOP
    bed(k, 1.9, 2.55, z)
    prop(k, "Nightstand_Shelf", 0.55, 3.65, z)
    prop(k, "Table_Large", 1.4, -1.6, z, facing="+x")
    chair(k, "Seat2", 0.6, -2.3, z)
    chair(k, "Seat3", 0.6, -0.9, z)
    prop(k, "Chandelier", 0.6, 0, z + WALL_TOP - 0.1)
    place(k, "Prop_Chimney", (-1.8, 2.4, 2 * WALL_TOP + 1.0), 0)
    k.empty("Smoke", (-1.8, 2.4, 2 * WALL_TOP + 4.3))
    house.back(2.0)
    export_kit_building("prospector_cottage")


# --- the town hall ------------------------------------------------------------------------------

def hall_front(k, flag=True):
    """The notice board and the flag out front."""
    mv.notice_board(k, -5.2, -3.4, 1.0, roofed=True)
    if flag:
        k.post("FlagPole", 0.05, 0, 5.2, 4.9, -3.6, ("metal.4", "metal.3", "metal.2"))
        k.box("Flag", (1.0, 0.04, 0.6), (5.42, -3.6, 4.85), "accent.4")


def hall_inside(k, hw, hd):
    """The meeting hall: a long table with benches either side, banners, the town charter."""
    prop(k, "Table_Large", 0.5, 0.0, facing="+x")
    for i, (x, f) in enumerate(((-0.35, "+x"), (1.35, "-x"))):
        prop(k, "Bench", x, 0.0, facing=BACK[f])
        marker(k, f"Seat{i + 1}", x, -0.6, 0.0, VEC[f])
        marker(k, f"Seat{i + 3}", x, 0.6, 0.0, VEC[f])
    prop(k, "BookStand", -hw + 1.0, -hd + 1.2, facing="+x")
    look(k, "Charter", -hw + 1.0, -hd + 1.2, 1.1)
    for x in (-hw + 1.6, hw - 1.6):
        prop(k, "Banner_1", x, hd - 0.45, 1.4)
        prop(k, "Banner_1_Cloth", x, hd - 0.45, 1.4)
    prop(k, "Chandelier", 0.5, 0, WALL_TOP - 0.1)


def bell_tower(k, z):
    """The tower on the ridge from `z` up: base, open belfry with the bell, pointed roof, clock."""
    beam = ("wood.1", "wood.1", "wood.0")
    k.box("Tower", (1.8, 1.8, 2.6), (0, 0, z + 1.3), ("wood.5", "wood.5", "wood.4", "wood.6"))
    for x in (-0.8, 0.8):
        for y in (-0.8, 0.8):
            k.post("Belfry", 0.08, z + 2.6, z + 3.8, x, y, beam)
    k.add("Bell", mv.prism(8, 0.36, 0.16, 0.5), ("ore.gold", "ore.gold", "ore.copper_dark"), (0, 0, z + 3.15))
    k.add("TowerRoof", mv.prism(4, 1.45, 0.04, 1.6), ("accent.0", "accent.0", "wood.1", "accent.1"), (0, 0, z + 4.6),
          (0, 0, math.pi / 4))
    k.add("Vane", mv.prism(4, 0.04, 0.01, 0.8), "metal.2", (0, 0, z + 5.75))
    k.add("Clock", mv.prism(12, 0.55, 0.55, 0.06), "neutral.6", (0, -0.93, z + 1.7), (math.pi / 2, 0, 0))
    k.box("ClockHand", (0.05, 0.04, 0.42), (0, -0.98, z + 1.86), "neutral.1")
    k.box("ClockHand", (0.3, 0.04, 0.05), (0.13, -0.98, z + 1.7), "neutral.1")


def town_hall():
    reset()
    k = mv.Kit("T1", 401)
    # the draughty plank meeting hut, a notice board, a bell on a frame (as it was)
    k.plank_walls(-2.0, 2.0, -1.2, 2.0, 0.0, 2.4, 1.0, ["wood.3", "wood.4", "wood.2", "wood.3"], plank=0.5)
    k.door((0, -1.26, 0), (1.0, 2.0), "wood.2")
    k.shed_roof("Roof", 4.5, -1.6, 2.4, 2.75, 2.3, 3, ("wood.2", "wood.2", "wood.1", "neutral.4"))
    mv.notice_board(k, -2.2, -2.6)
    for x in (1.8, 2.7):
        k.post("BellPost", 0.07, 0, 2.3, x, -2.4)
    k.box("BellBar", (1.1, 0.08, 0.08), (2.25, -2.4, 2.25), "wood.3")
    k.add("Bell", mv.prism(8, 0.22, 0.1, 0.32), ("ore.copper", "ore.copper", "ore.copper_dark"), (2.25, -2.4, 1.95))

    # Town Hall: 8 x 8 m, plaster and timber, the meeting hall inside, the mayor's bed at the back
    k = mv.Kit("T2", 402)
    house = built(k)
    storey(k, 4, 4, "plaster", front="todt", back="toot", left="toot", right="toot")
    gable_roof(k, 4, 4, WALL_TOP)
    hall_inside(k, 4, 4)
    bed(k, -2.7, 2.4)
    house.back(1.0)
    hall_front(k)

    # Grand Hall: two storeys of stone and timber with the bell tower, the mayor's rooms upstairs
    k = mv.Kit("T3", 403)
    house = built(k)
    storey(k, 4, 5, "brick", front="oodo", back="wnnw", left="wowow", right="owowo")
    storey(k, 4, 5, "plaster", front="toot", back="tnnt", left="totot", right="totot", z0=WALL_TOP,
           floor="Floor_WoodLight", holes={(0, 1), (0, 2)})
    place(k, "Stair_Interior_Solid", (-3.1, -3.5, 0.0), 0)
    marker(k, "Stair0", -3.1, -4.1, 0.0, (0, 1))
    marker(k, "Stair1", -3.1, 1.1, WALL_TOP, (0, 1))
    gable_roof(k, 4, 5, 2 * WALL_TOP)
    hall_inside(k, 4, 5)
    z = WALL_TOP
    bed(k, 2.7, 3.4, z)
    prop(k, "Nightstand_Shelf", 1.4, 4.45, z)
    prop(k, "Bookcase_2", 0.0, 4.45, z)
    prop(k, "Table_Large", 2.4, -1.6, z, facing="+x")
    chair(k, "Seat5", 1.6, -1.6, z)
    prop(k, "Chandelier", 0.5, 0, z + WALL_TOP - 0.1)
    bell_tower(k, 2 * WALL_TOP + 5.6)
    house.back(2.0)
    hall_front(k)
    for sx in (-1, 1):
        k.box("Banner", (0.6, 0.05, 1.5), (sx * 1.9, -3.25, 1.9), ("accent.6", "accent.6", "accent.6"))
        k.box("BannerTrim", (0.62, 0.06, 0.12), (sx * 1.9, -3.27, 1.2), "accent.3")
        k.post("LampPost", 0.06, 0, 2.5, sx * 3.0, -5.2, ("metal.1", "metal.1", "metal.0"))
        k.box("Lamp", (0.26, 0.26, 0.32), (sx * 3.0, -5.2, 2.65), ("neutral.1", "accent.3", "neutral.1"))
    export_kit_building("town_hall")


# --- the smithy ---------------------------------------------------------------------------------

def smithy_workshop(k):
    """The top smithy (tiers 3 and 4): kit walls of stone on three sides, open to the front, round
    the old forge, bellows, anvil, trough and grindstone; Greta's bed in the back corner."""
    house = built(k)
    storey(k, 3, 3, "brick", front="---", back="www", left="wow", right="wow", floor="Floor_UnevenBrick")
    gable_roof(k, 3, 3, WALL_TOP)
    bed(k, -1.9, 1.2)
    chair(k, "Seat1", 2.1, 2.2, facing="-y")
    house.back(0.5)
    top = mv.forge(k, 1.7, 8.6, wide=1.2)
    k.empty("Smoke", (0, 1.8, top + 0.3))
    k.box("BellowsLow", (0.55, 0.95, 0.06), (1.35, 1.6, 0.55), "wood.3", rot=(0.1, 0, 0))
    k.box("BellowsLeather", (0.5, 0.8, 0.22), (1.35, 1.65, 0.68), ("wood.1", "wood.1", "wood.0"), rot=(0.1, 0, 0))
    k.box("BellowsTop", (0.55, 0.95, 0.06), (1.35, 1.6, 0.84), "wood.3", rot=(0.25, 0, 0))
    k.box("BellowsHandle", (0.06, 0.5, 0.06), (1.35, 0.95, 0.85), "wood.5")
    k.add("BellowsNozzle", mv.prism(6, 0.06, 0.03, 0.4), "metal.2", (0.9, 1.75, 0.6), (0, math.pi / 2, 0))
    k.anvil((0.5, -0.7, 0), 1.15)
    look(k, "Hammer", 0.5, -0.7, 1.1)
    k.box("Trough", (0.6, 1.4, 0.5), (-1.9, -0.9, 0.25), ("wood.3", "wood.3", "wood.2", "wood.4"))
    k.box("TroughWater", (0.48, 1.28, 0.04), (-1.9, -0.9, 0.48), "accent.4")
    for y in (-1.55, -0.95):
        k.post("GrindFrame", 0.05, 0, 0.75, 2.3, y)
    k.add("Grindstone", mv.prism(12, 0.36, 0.36, 0.12), ("stone.5", "stone.4", "stone.3"), (2.3, -1.25, 0.6),
          (math.pi / 2, 0, 0))
    prop(k, "WeaponStand", -0.3, 3.1)
    k.post("SignPost", 0.08, 0, 2.7, 3.7, -3.0, ("wood.2", "wood.2", "wood.1"))
    k.box("SignArm", (0.9, 0.06, 0.06), (3.3, -3.0, 2.55), "wood.2")
    k.box("Sign", (0.7, 0.06, 0.5), (3.15, -3.0, 2.15), ("wood.6", "wood.6", "wood.5"))
    k.box("SignAnvil", (0.4, 0.08, 0.14), (3.15, -3.04, 2.15), "metal.1")


def smithy():
    """Tiers 1 and 2 as they were (the camp, the open forge); 3 and 4 in the kit's stone."""
    reset()
    k = mv.Kit("T1", 201)
    k.fire((-0.9, 0.2, 0))
    k.anvil((0.9, -0.5, 0))
    k.add("Bucket", mv.prism(8, 0.18, 0.2, 0.3), ("accent.4", "wood.3", "wood.2"), (1.7, 0.5, 0.15))
    k.box("ToolBoard", (1.0, 0.06, 1.4), (-0.2, 1.3, 0.68), ("wood.4", "wood.4", "wood.3"), rot=(0.25, 0, 0))
    for x, h in ((-0.5, 0.5), (-0.2, 0.42), (0.1, 0.55)):
        k.box("Tool", (0.05, 0.05, h), (x, 1.17, 0.85), "metal.2", rot=(0.25, 0, 0))
    for x in (-1.5, 1.5):
        k.post("TarpPole", 0.05, 0, 1.9 if x < 0 else 1.6, x, -0.9)
    k.box("Tarp", (3.2, 1.6, 0.04), (0, -0.25, 1.65), ("neutral.4", "neutral.3", "neutral.3"), rot=(-0.35, 0.06, 0))
    k.crate((-1.9, -0.9, 0), 0.55)

    k = mv.Kit("T2", 202)
    for x in (-2.4, 2.4):
        for y in (-2.0, 2.0):
            k.post("Post", 0.11, 0, 2.65, x, y)
    for y in (-2.0, 2.0):
        k.log("Beam", 5.2, 0.11, (0, y, 2.62), "x", sides=("wood.3", "wood.2"))
    k.gable_roof("Roof", 5.8, 2.0, 2.68, 3.5, 0.45, 3, ("wood.2", "wood.2", "wood.1", "wood.3"))
    for x in (-2.4, 2.4):
        k.gable("Gable", 2.05, 2.68, 3.45, x, 0.12, ("wood.3", "wood.3", "wood.2"))
    mv.forge(k, 1.4, 4.4)
    k.anvil((0.4, -0.6, 0))
    k.barrel((-1.7, -0.5, 0), 0.3, 0.7)
    k.add("Water", mv.prism(10, 0.27, 0.27, 0.03), "accent.4", (-1.7, -0.5, 0.69))
    k.box("ToolRack", (0.08, 0.9, 0.6), (2.32, 0.6, 1.4), "wood.4")
    for i in range(3):
        k.box("Tool", (0.04, 0.05, 0.45), (2.26, 0.3 + i * 0.3, 1.25), "metal.2")

    smithy_workshop(mv.Kit("T3", 203))
    # the crystal forge: the same smithy, crystal set into the forge, a rack of shards, crystal
    # lanterns at the front and a crystal on the sign
    k = mv.Kit("T4", 203)
    smithy_workshop(k)
    for i, (x, h, tilt) in enumerate(((-0.5, 0.5, 0.3), (0.0, 0.7, 0.0), (0.5, 0.45, -0.35))):
        k.add("ForgeCrystal", mv.prism(6, 0.09, 0.012, h), ("ore.amethyst", "accent.6", "accent.6"),
              (x * 1.2, 1.7 + 0.25, 1.0 + h / 2), (0, tilt, 0))
    k.box("CrystalRack", (0.1, 1.0, 0.7), (-2.75, -0.2, 1.2), "wood.3")
    for i in range(4):
        k.add("RackCrystal", mv.prism(6, 0.06, 0.01, 0.3), ("ore.amethyst", "accent.6", "accent.6"),
              (-2.65, -0.55 + i * 0.24, 1.1), (0, math.pi / 2, 0))
    for x in (-1.0, 1.0):
        k.add("CrystalLantern", mv.prism(6, 0.1, 0.02, 0.35), ("ore.amethyst", "ore.amethyst", "accent.6"),
              (x * 2.82, -2.62, 2.3))
    k.add("SignCrystal", mv.prism(6, 0.07, 0.01, 0.26), ("ore.amethyst", "accent.6", "accent.6"), (3.15, -3.1, 2.15),
          (0, 0.4, 0))
    export_kit_building("smithy")


# --- your home ----------------------------------------------------------------------------------
# Markers of its own (scripts/home.gd): Bed, DogBed (where the dog curls up), Plans (the board that
# opens the home's upgrades), Wake (where you stand up in the morning, facing the room).

def tent(k):
    """Tier 1: a canvas ridge tent (open to the front), a bedroll inside, the dog's fur patch and a
    campfire out front, a log to sit on, and the plans pinned to a post."""
    canvas = ("wood.7", "wood.7", "wood.6", "wood.6")
    half, ridge, length = 1.15, 1.65, 2.6
    a = math.atan2(ridge, half)
    side = math.hypot(half, ridge)
    for sx in (-1, 1):
        k.box("Canvas", (0.05, length, side), (sx * half / 2, 0.2, ridge / 2), canvas, rot=(0, sx * -(math.pi / 2 - a), 0))
    back = k.gable("CanvasBack", half, 0.0, ridge, 0.0, 0.05, canvas)  # (a triangle across Y: turned to face)
    back.rotation_euler = (0, 0, math.pi / 2)
    back.location = (0, 0.2 + length / 2, 0)
    for sx in (-1, 1):  # front flaps tied back
        k.box("Flap", (0.05, 0.5, side * 0.8), (sx * (half * 0.75), 0.2 - length / 2 - 0.15, ridge * 0.38), canvas,
              rot=(0, sx * -(math.pi / 2 - a), sx * 0.6))
    for y in (0.2 - length / 2, 0.2 + length / 2):
        k.post("Pole", 0.035, 0, ridge + 0.1, 0, y)
    k.log("RidgePole", length + 0.3, 0.035, (0, 0.2, ridge + 0.02), "y", sides=("wood.3",), ends="wood.6")
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):  # guy ropes' pegs
        k.post("Peg", 0.025, 0, 0.18, sx * (half + 0.7), 0.2 + sy * (length / 2 + 0.2), ("wood.6", "wood.5", "wood.4"))
    # the bedroll (pillow at the back) and a blanket folded on it
    k.box("Bedroll", (0.75, 1.9, 0.12), (0, 0.35, 0.06), ("accent.0", "accent.0", "wood.1"))
    k.box("Pillow", (0.55, 0.3, 0.12), (0, 1.1, 0.16), ("neutral.6", "neutral.5", "neutral.4"))
    marker(k, "Bed", 0, -0.55, 0.12, (0, 1))
    # out front: the fire, a log to sit on, the dog's fur patch
    k.fire((0, -2.6, 0))
    k.empty("Smoke", (0, -2.6, 0.5))
    k.log("SeatLog", 1.3, 0.2, (-1.6, -2.7, 0.2), "y")
    marker(k, "Seat1", -1.6, -2.7, 0.0, (1, 0))
    fur = mv.blob(0.55, k.rng, jitter_amount=0.25, squash=(1.3, 1.0, 0.12))
    k.add("FurPatch", fur, ("wood.6", "wood.5", "wood.4", "wood.7"), (1.5, -2.2, 0.03))
    marker(k, "DogBed", 1.5, -2.2, 0.0, (-1, -0.3))
    # the plans, pinned to a post
    k.post("PlansPost", 0.06, 0, 1.3, 2.2, -0.6)
    k.box("Plans", (0.5, 0.04, 0.4), (2.2, -0.68, 1.05), ("neutral.6", "neutral.6", "neutral.5"), rot=(0.1, 0, 0))
    marker(k, "Plans", 2.2, -0.8, 1.0)
    marker(k, "Wake", 0.0, -1.6, 0.0, (0, -1))
    k.crate((-1.6, 0.9, 0))


def cabin(k):
    """Tier 2: a 6 x 6 m timber-and-plaster cabin: a real bed, a stove, the dog's basket."""
    storey(k, 3, 3, "plaster", front="odt", back="tnt", left="tot", right="tot")
    gable_roof(k, 3, 3, WALL_TOP)
    place(k, "Prop_Chimney", (1.9, 1.6, WALL_TOP + 0.4), 0)
    k.empty("Smoke", (1.9, 1.6, WALL_TOP + 3.7))
    bed(k, -1.9, 1.6)
    marker(k, "Wake", -1.0, 0.4, 0.0, (1, -1))
    prop(k, "Nightstand_Shelf", -0.55, 2.65)
    # the stove: a stone box with a pot on it, under the chimney
    for i, (x, y) in enumerate(((1.6, 2.5), (2.3, 2.5), (1.6, 1.9), (2.3, 1.9))):
        k.stone("Stove", (0.72, 0.62, 0.8), (x, y, 0.4), ("stone.4", "stone.3", "stone.2", "stone.5"))
    k.box("StoveMouth", (0.5, 0.06, 0.32), (1.95, 1.56, 0.42), "neutral.1")
    k.box("StoveEmbers", (0.36, 0.05, 0.08), (1.95, 1.55, 0.3), "accent.2")
    prop(k, "Pot_1", 1.95, 2.2, 0.8)
    # the dog's basket by the stove
    k.add("Basket", mv.prism(10, 0.42, 0.46, 0.18), ("wood.6", "wood.4", "wood.3", "wood.5"), (1.9, 0.6, 0.09))
    k.add("Cushion", mv.prism(10, 0.36, 0.36, 0.08), ("accent.0", "accent.0", "accent.0"), (1.9, 0.6, 0.16))
    marker(k, "DogBed", 1.9, 0.6, 0.12, (-1, 0))
    # a table by the window with the plans on it, a chair, pegs by the door
    prop(k, "Table_Large", -1.9, -1.1, facing="+x")
    chair(k, "Seat1", -1.1, -1.5, facing="-x")
    k.box("Plans", (0.55, 0.42, 0.01), (-2.0, -1.2, 0.82), ("neutral.6", "neutral.6", "neutral.5"), rot=(0, 0, 0.2))
    marker(k, "Plans", -2.0, -1.2, 0.9)
    prop(k, "Peg_Rack", 1.2, -2.85, 1.6)
    prop(k, "Lantern_Wall", -2.85, 0.4, 1.0, facing="+x")


def home():
    reset()
    tent(mv.Kit("T1", 301))
    cabin(mv.Kit("T2", 302))
    export_kit_building("home")


def export_kit_building(name):
    """models/village/<name>.gltf with its textures in models/village/textures/ (shared)."""
    weather_stonework()
    path = os.path.join(OUT_DIR, "village", name + ".gltf")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              export_yup=True, export_apply=True, export_materials="EXPORT",
                              export_image_format="AUTO")
    print("exported", path)


BUILDERS = {"baker_cottage": baker_cottage, "woodcutter": woodcutter, "fisher": fisher,
            "prospector_cottage": prospector_cottage, "town_hall": town_hall, "smithy": smithy, "home": home}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv[2:] or list(BUILDERS)  # (argv: models, palette.json, as make_models takes them)
    for n in names:
        BUILDERS[n]()
