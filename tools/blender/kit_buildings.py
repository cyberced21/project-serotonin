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


# --- the bakery ---------------------------------------------------------------------------------

def bakery_home(k, hw, hd, z=0.0, shelves=True):
    """Rosa's room at the back of a storey hw x hd metres from the centre: bed, table, shelves
    (not by the oven)."""
    bed(k, -hw + 1.1, hd - 1.45, z)
    prop(k, "Nightstand_Shelf", -hw + 2.45, hd - 0.35, z)
    prop(k, "Table_Large", hw - 1.6, 0.2, z, facing="+x")
    chair(k, "Seat1", hw - 2.4, -0.5, z)
    chair(k, "Seat2", hw - 2.4, 0.9, z)
    if shelves:
        prop(k, "Bookcase_2", hw - 1.1, hd - 0.35, z)
        look(k, "Recipes", hw - 1.1, hd - 0.5, z + 1.4)
    prop(k, "Chandelier", 0, 0, z + WALL_TOP - 0.1)


def bakery_shop(k, hw, hd):
    """The shop at the front: a counter facing the door, bread on shelves, flour and crates."""
    prop(k, "Table_Large", 0.6, -hd + 2.6)
    prop(k, "Shelf_Simple", hw - 1.0, -hd + 0.35, 1.6)
    mv.loaves(k, hw - 1.0, -hd + 0.55, 1.63, 3, 0.25)
    prop(k, "Bag", -hw + 0.8, -hd + 0.7)
    prop(k, "FarmCrate_Empty", -hw + 0.8, -hd + 1.5)
    prop(k, "Barrel", hw - 0.6, -hd + 3.4)
    look(k, "Flour", -hw + 0.8, -hd + 0.7, 0.5)

def baker_cottage():
    mv.reset()
    # Cottage: one room, 6 x 8 m, gable to the street, a chimney
    k = mv.Kit("T1", 201)
    storey(k, 3, 4, "plaster", front="odo", back="wnw", left="wowo", right="owow")
    gable_roof(k, 3, 4, WALL_TOP)
    bakery_home(k, 3, 4)
    prop(k, "Bag", -2.4, -3.3)
    look(k, "Flour", -2.4, -3.3, 0.5)
    place(k, "Prop_Chimney", (1.8, 2.0, WALL_TOP + 0.6), 0)
    k.empty("Smoke", (1.8, 2.0, WALL_TOP + 3.9))

    # Bakery: 8 x 10 m, a stone shop front, the oven at the back
    k = mv.Kit("T2", 202)
    storey(k, 4, 5, "brick", front="odoo", back="wwnw", left="wowow", right="owowo")
    gable_roof(k, 4, 5, WALL_TOP)
    bakery_home(k, 4, 5, shelves=False)
    bakery_shop(k, 4, 5)
    mv.bread_oven(k, 2.4, 3.6, big=True)
    place(k, "Prop_Chimney", (2.4, 3.0, WALL_TOP + 1.2), 0)
    k.empty("Smoke", (2.4, 3.0, WALL_TOP + 4.5))
    mv.hanging_sign(k, -2.4, -5.1, 2.4, lambda k, x, y, z: mv.loaves(k, x, y, z - 0.08, 2, 0.2))

    # Bakehouse: two storeys, the shop below, Rosa's rooms above (a stair up the left wall)
    k = mv.Kit("T3", 203)
    storey(k, 4, 5, "brick", front="odoo", back="wwnw", left="wowow", right="owowo")
    storey(k, 4, 5, "plaster", front="toot", back="tnnt", left="totot", right="totot", z0=WALL_TOP,
           floor="Floor_WoodLight", holes={(0, 1), (0, 2)})
    place(k, "Stair_Interior_Solid", (-3.0, -3.0, 0.0), 0)
    marker(k, "Stair0", -3.0, -3.6, 0.0, (0, 1))
    marker(k, "Stair1", -3.0, 1.6, WALL_TOP, (0, 1))
    gable_roof(k, 4, 5, 2 * WALL_TOP)
    bakery_shop(k, 4, 5)
    bakery_home(k, 4, 5, WALL_TOP)  # upstairs: Rosa's rooms
    mv.bread_oven(k, 2.4, 3.6, big=True)
    place(k, "Prop_Chimney", (2.4, 3.0, 2 * WALL_TOP + 1.2), 0)
    k.empty("Smoke", (2.4, 3.0, 2 * WALL_TOP + 4.5))
    mv.hanging_sign(k, -2.4, -5.1, 2.4, lambda k, x, y, z: mv.loaves(k, x, y, z - 0.08, 3, 0.16))
    export_kit_building("baker_cottage")


def export_kit_building(name):
    """models/village/<name>.gltf with its textures in models/village/textures/ (shared)."""
    weather_stonework()
    path = os.path.join(OUT_DIR, "village", name + ".gltf")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              export_yup=True, export_apply=True, export_materials="EXPORT",
                              export_image_format="AUTO")
    print("exported", path)


BUILDERS = {"baker_cottage": baker_cottage}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv[2:] or list(BUILDERS)  # (argv: models, palette.json, as make_models takes them)
    for n in names:
        BUILDERS[n]()
