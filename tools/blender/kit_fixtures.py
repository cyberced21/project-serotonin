"""The village's fixtures (plans/world-pass.md, phase 5): farm buildings, stores, the washhouse, the
chapel, empty and ruined cottages, built like the houses from the Quaternius Medieval Village kit
(kit_buildings.py) with make_village's planks, posts and stones where the kit has no piece.

    blender -b -P tools/blender/kit_fixtures.py -- models art/palette.json [fixture ...]

Each is centred on the origin with its front (door) facing -Y. Pieces named T1_* are the fixture as
you find it; T2_* (when there are any) as it is once its noticeboard project is done (Fixture shows
one or the other). Markers: Doorway (just inside a walk-in one's door), Seat* (a bench or pew
anyone may sit on), Smoke (chimney smoke while shown).

Writes models/village/fx_<name>.gltf, sharing models/village/textures/ with the houses.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import kit_buildings as kb  # noqa: E402
import make_village as mv  # noqa: E402
from kit_buildings import WALL_TOP, gable_roof, marker, place, prop, storey  # noqa: E402

PLANKS = ["wood.3", "wood.4", "wood.5"]
OLD_PLANKS = ["wood.2", "wood.3", "neutral.4"]
HAY = ("terrain.sand", "terrain.sand", "wood.5")


def _since():
    return set(bpy.data.objects)


def _drop_some(before, k, base, share):
    """Takes away a share of the pieces named `base` made since `before` (gaps in an old wall)."""
    for o in list(bpy.data.objects):
        if o not in before and base in o.name and k.rng.random() < share:
            bpy.data.objects.remove(o, do_unlink=True)


def _floor(k, hw, hd, piece="Floor_WoodLight", z=0.01):
    for i in range(int(hw)):
        for j in range(int(hd)):
            place(k, piece, (-hw + 1 + 2 * i, -hd + 1 + 2 * j, z), 0)


def _bale(k, x, y, z=0.0, along="x"):
    size = (1.1, 0.55, 0.45) if along == "x" else (0.55, 1.1, 0.45)
    k.box("HayBale", size, (x, y, z + 0.225), HAY, jit=0.02)


def _lantern(k, x, y, z):
    k.box("Lantern", (0.16, 0.16, 0.22), (x, y, z), ("accent.3", "accent.3", "neutral.1"))


def _barn_shell(k, worn):
    """8 x 14 m of planks on a stone footing, the kit's tiled roof, a wide doorway at the front."""
    before = _since()
    k.plank_walls(-4.0, 4.0, -7.0, 7.0, 0.0, WALL_TOP, 3.6, OLD_PLANKS if worn else PLANKS, plank=0.5, thickness=0.1)
    if worn:
        _drop_some(before, k, "Plank", 0.12)
    for x in (-4.0, 4.0):
        for y in (-7.0, 0.0, 7.0):
            k.post("Post", 0.13, 0.0, WALL_TOP, x, y)
    for y in (-7.0, 7.0):
        k.log("Plate", 8.2, 0.12, (0, y, WALL_TOP - 0.05), "x")
    gable_roof(k, 4, 7, WALL_TOP)
    _floor(k, 4, 7, "Floor_WoodLight")
    marker(k, "Doorway", 0.0, -6.0, 0.0, (0, 1))


def barn():
    """The old barn by the farm yard; restored (the "restore_barn" project): doors open, hay in."""
    kb.reset()
    k = mv.Kit("T1", 501)
    _barn_shell(k, True)
    k.box("DoorLeaf", (1.8, 0.1, 2.6), (-0.95, -7.05, 1.3), ("wood.2", "wood.2", "wood.1"))
    k.box("DoorLeaf", (1.8, 0.1, 2.4), (2.2, -7.6, 0.4), ("wood.2", "wood.2", "wood.1"), rot=(1.25, 0, 0.3))  # fallen
    for i, (x, y) in enumerate(((-2.6, 5.5), (2.4, 4.8), (-2.2, 1.0))):
        k.box("Junk", (0.8, 0.8, 0.5), (x, y, 0.25), ("wood.2", "wood.1", "wood.1"), rot=(0, 0, 0.4 * i))
    k = mv.Kit("T2", 502)
    _barn_shell(k, False)
    for sx in (-1, 1):  # the two leaves swung open against the front
        k.box("DoorLeaf", (0.1, 1.8, 2.6), (sx * 2.85, -7.95, 1.3), ("wood.5", "wood.4", "wood.3"))
    for row in range(3):  # hay stacked along the back and one side
        for i in range(6):
            _bale(k, -3.0 + i * 1.15, 6.2, row * 0.45)
    for i in range(4):
        _bale(k, -3.4, 2.0 - i * 1.15, 0.0, along="y")
        _bale(k, -3.4, 2.0 - i * 1.15, 0.45, along="y")
    prop(k, "Barrel", 3.3, 5.8)
    prop(k, "FarmCrate_Apple", 3.2, 4.6)
    prop(k, "Bag", 3.3, 3.5)
    _lantern(k, 2.2, -7.2, 2.4)
    k.box("LanternBracket", (0.04, 0.3, 0.04), (2.2, -7.05, 2.52), "metal.1")
    kb.export_kit_building("fx_barn")


def _granary_body(k, worn):
    """A 4 x 4 m plank store on nine staddle stones (stone stems, flat caps): rats can't climb in."""
    for i in (-1, 0, 1):
        for j in (-1, 0, 1):
            x, y = i * 1.6, j * 1.6
            k.add("Staddle", mv.prism(6, 0.16, 0.12, 0.5), ("stone.4", "stone.3", "stone.2"), (x, y, 0.25))
            k.add("StaddleCap", mv.prism(8, 0.34, 0.34, 0.1), ("stone.5", "stone.3", "stone.2"), (x, y, 0.55))
    k.box("Platform", (4.2, 4.2, 0.14), (0, 0, 0.67), ("wood.5", "wood.4", "wood.3"))
    before = _since()
    k.plank_walls(-2.0, 2.0, -2.0, 2.0, 0.74, 0.74 + 2.3, 1.0, OLD_PLANKS if worn else PLANKS, plank=0.4)
    if worn:
        _drop_some(before, k, "Plank", 0.15)
    place(k, "Roof_RoundTiles_4x4", (0, 0, 0.74 + 2.3), 0)
    for y, r in ((-2.0, 0), (2.0, 180)):
        place(k, "Roof_Front_Brick4", (0, y, 0.74 + 2.3), r)
    for i in range(3):  # steps up to the door, each a block down to the ground
        top = 0.66 - i * 0.22
        k.box("Step", (1.0, 0.35, top), (0, -2.35 - i * 0.35, top / 2), ("wood.5", "wood.4", "wood.3"))
    k.box("Door", (1.0, 0.08, 1.9), (0, -2.04, 0.74 + 0.95), ("wood.2", "wood.2", "wood.1"),
          rot=(0, 0.06 if worn else 0.0, 0))


def granary():
    """The granary on staddle stones; mended (the "mend_granary" project)."""
    kb.reset()
    k = mv.Kit("T1", 511)
    _granary_body(k, True)
    k.box("Prop", (0.12, 0.12, 2.4), (2.4, 0.4, 1.1), ("wood.2", "wood.2", "wood.1"), rot=(0, -0.45, 0))  # propped up
    k = mv.Kit("T2", 512)
    _granary_body(k, False)
    for x in (-1.1, 1.1):
        k.box("Sack", (0.45, 0.35, 0.5), (x, -2.6, 0.25), ("neutral.6", "neutral.5", "neutral.4"))
    kb.export_kit_building("fx_granary")


def cart_shed():
    """A 6 x 4 m open-fronted shed for the farm cart: posts at the front, planks behind, a lean roof."""
    kb.reset()
    k = mv.Kit("T1", 521)
    for x in (-3.0, -1.0, 1.0, 3.0):
        k.post("Post", 0.12, 0.0, 2.7, x, -2.0)
    k.plank_walls(-3.0, 3.0, -1.9, 2.0, 0.0, 2.3, 6.2, PLANKS)  # (the front all doorway)
    k.shed_roof("Roof", 6.6, -2.5, 2.4, 2.75, 2.25, 6, ("accent.0", "accent.0", "wood.1"))
    k.box("Wheel", (0.1, 0.9, 0.9), (2.4, 1.6, 0.45), ("wood.4", "wood.3", "wood.2"), rot=(0, 0, 0.1))
    kb.export_kit_building("fx_cart_shed")


def stable():
    """A 6 x 10 m stable: timbered walls, two stalls each side, hay racks."""
    kb.reset()
    k = mv.Kit("T1", 531)
    storey(k, 3, 5, "plaster", front="tdt", back="ttt", left="tntnt", right="tntnt", floor="Floor_UnevenBrick")
    gable_roof(k, 3, 5, WALL_TOP)
    for y in (-1.5, 1.5):  # stall partitions
        for sx in (-1, 1):
            k.box("Stall", (2.2, 0.1, 1.4), (sx * 1.85, y, 0.7), ("wood.4", "wood.3", "wood.2"))
    for sx in (-1, 1):
        for y in (-3.2, 0.0, 3.2):
            k.box("Rack", (0.2, 1.2, 0.5), (sx * 2.75, y, 1.5), HAY)
    marker(k, "Doorway", 0.0, -4.1, 0.0, (0, 1))
    kb.export_kit_building("fx_stable")


def storehouse():
    """An 8 x 10 m brick storehouse you can walk into: crates, barrels and sacks on shelves."""
    kb.reset()
    k = mv.Kit("T1", 541)
    storey(k, 4, 5, "brick", front="wdow", back="wnnw", left="wnwnw", right="wnwnw")
    gable_roof(k, 4, 5, WALL_TOP)
    for i, y in enumerate((-2.5, -0.5, 1.5, 3.5)):
        prop(k, "Crate_Wooden", -3.1, y)
        prop(k, "Barrel", 3.2, y)
        if i % 2:
            prop(k, "Crate_Wooden", -3.1, y, 0.8)
    for x in (-1.2, 0.0, 1.2):
        prop(k, "Bag", x, 4.2)
    prop(k, "Shelf_Simple", 0.0, 4.65, 1.0)
    prop(k, "Table_Large", 1.5, -2.6, facing="+x")
    prop(k, "Lantern_Wall", 0.0, -4.65, 2.0, facing="+y")
    kb.chandelier(k, 0, 0.5, 0.0, 4)
    marker(k, "Doorway", -1.0, -4.1, 0.0, (0, 1))
    kb.export_kit_building("fx_storehouse")


def ore_store():
    """Three open bays for ore and coal by the smithy: stone dividers, a lean roof on posts, heaps."""
    kb.reset()
    k = mv.Kit("T1", 551)
    for x in (-3.0, -1.0, 1.0, 3.0):
        for i in range(3):
            k.stone("Divider", (0.4, 2.8, 0.35), (x, 0.3, 0.18 + i * 0.32))
        k.post("Post", 0.11, 0.0, 2.6, x, -1.2)
    k.stone("Back", (6.4, 0.4, 1.0), (0, 1.6, 0.5))
    k.shed_roof("Roof", 6.6, -1.6, 2.0, 2.65, 2.2, 5, ("wood.2", "wood.2", "wood.1"))
    for x, colors in ((-2.0, ("stone.2", "stone.1", "stone.1")), (0.0, ("metal.1", "stone.1", "stone.1")),
                      (2.0, ("stone.5", "stone.4", "stone.3"))):  # coal, iron ore, stone
        for i in range(7):
            k.add("Heap", mv.blob(0.32, k.rng, squash=(1.0, 1.0, 0.7)), colors,
                  (x + k.rng.uniform(-0.5, 0.5), 0.6 + k.rng.uniform(-0.6, 0.5), 0.2 + (i % 3) * 0.18))
    kb.export_kit_building("fx_ore_store")


def woodshed():
    """A lean-to woodshed: firewood stacked to the roof under a plank lean roof."""
    kb.reset()
    k = mv.Kit("T1", 561)
    for x in (-2.0, 2.0):
        for y in (-1.3, 1.3):
            k.post("Post", 0.1, 0.0, 2.4 if y < 0 else 2.0, x, y)
    k.shed_roof("Roof", 4.6, -1.7, 1.7, 2.45, 2.05, 4, ("wood.2", "wood.2", "wood.1"))
    for row in range(5):
        for i in range(12):
            k.log("Firewood", 1.1, 0.13, (-1.75 + i * 0.32 + (row % 2) * 0.16, 0.4, 0.14 + row * 0.26), "y")
    kb.export_kit_building("fx_woodshed")


def timber_yard():
    """The timber yard by the woodcutter's: trunks stacked between stakes, a sawhorse, planks."""
    kb.reset()
    k = mv.Kit("T1", 571)
    for stack, (x0, y0) in enumerate(((-2.5, 1.5), (2.5, 1.5))):
        for row, n in enumerate((4, 3, 2)):
            for i in range(n):
                k.log("Trunk", 5.0, 0.26, (x0 + (i - (n - 1) / 2) * 0.54, y0, 0.26 + row * 0.46), "y")
        for sx in (-1, 1):
            for sy in (-1, 1):
                k.post("Stake", 0.07, 0.0, 1.4, x0 + sx * 1.3, y0 + sy * 2.3)
    for x in (-0.8, 0.8):  # a sawhorse with a log on it
        for sx in (-1, 1):
            k.box("SawhorseLeg", (0.08, 0.08, 1.0), (x + sx * 0.25, -2.5, 0.45), ("wood.4", "wood.3", "wood.2"),
                  rot=(0, sx * 0.3, 0))
    k.log("Log", 2.6, 0.18, (0, -2.5, 0.95), "x")
    for i in range(6):
        k.box("Plank", (3.2, 0.3, 0.06), (0, -4.2, 0.03 + i * 0.07), ("wood.6", "wood.5", "wood.4"), jit=0.01)
    kb.export_kit_building("fx_timber_yard")


def washhouse():
    """A 6 x 6 m washhouse, open at the front: tubs, a copper over a fire, washing lines outside."""
    kb.reset()
    k = mv.Kit("T1", 581)
    storey(k, 3, 3, "plaster", front="t-t", back="tnt", left="tot", right="tot", floor="Floor_UnevenBrick")
    gable_roof(k, 3, 3, WALL_TOP)
    for x in (-1.6, 0.0):
        k.add("Tub", mv.prism(10, 0.45, 0.4, 0.5), ("wood.5", "wood.4", "wood.3"), (x, 1.8, 0.25))
        k.box("Water", (0.62, 0.62, 0.02), (x, 1.8, 0.45), "accent.4")
    prop(k, "Cauldron", 1.8, 1.7)
    k.fire((1.8, 1.7, 0.0), r=0.45, stones=7)
    prop(k, "Bucket_Wooden_1", -2.3, 0.2)
    k.box("Washboard", (0.4, 0.06, 0.6), (-1.6, 2.3, 0.6), ("wood.6", "wood.5", "wood.4"), rot=(0.3, 0, 0))
    k.empty("Smoke", (1.8, 1.7, WALL_TOP + 2.5))
    # washing lines on posts out to the right, sheets and shirts pegged on them
    for y in (-1.5, 1.5):
        for x in (4.2, 9.8):
            k.post("LinePost", 0.06, 0.0, 2.1, x, y)
        k.box("Line", (5.6, 0.02, 0.02), (7.0, y, 2.0), "neutral.6")
        for i, c in enumerate(("neutral.7", "accent.1", "neutral.6", "accent.4")):
            w = 0.9 if i % 2 == 0 else 0.6
            k.box("Washing", (w, 0.03, 0.8 if i % 2 == 0 else 0.6), (5.0 + i * 1.3, y, 1.6), c)
    marker(k, "Doorway", 0.0, -2.1, 0.0, (0, 1))
    kb.export_kit_building("fx_washhouse")


def chapel():
    """A 6 x 12 m brick chapel: a bell turret over the door, pews in two rows, a table altar."""
    kb.reset()
    k = mv.Kit("T1", 591)
    storey(k, 3, 6, "brick", front="wdw", back="wnw", left="wnwnwn", right="nwnwnw", floor="Floor_Brick")
    gable_roof(k, 3, 6, WALL_TOP)
    # the turret: a timber box on the front gable, a little pyramid roof, the bell
    k.box("TurretBase", (1.4, 1.4, 1.6), (0, -5.2, WALL_TOP + 4.3), ("wood.2", "wood.3", "wood.2"))
    k.box("TurretOpen", (1.0, 1.5, 0.8), (0, -5.2, WALL_TOP + 4.4), "neutral.1")
    k.add("TurretRoof", mv.prism(4, 1.05, 0.02, 1.2), ("accent.0", "accent.0", "wood.1"),
          (0, -5.2, WALL_TOP + 5.7), (0, 0, math.pi / 4))
    k.add("Bell", mv.prism(10, 0.3, 0.18, 0.45), ("metal.4", "metal.3", "metal.2"), (0, -5.2, WALL_TOP + 4.3))
    for row in range(4):  # pews: benches either side of the aisle, facing the altar (+Y)
        for sx in (-1, 1):
            y = -2.6 + row * 1.6
            prop(k, "Bench", sx * 1.6, y, facing="+y")
            marker(k, "Seat%d" % (row * 2 + (sx + 1) // 2 + 1), sx * 1.6, y, 0.0, (0, 1))
    prop(k, "Table_Large", 0, 4.6, facing="-y")
    prop(k, "CandleStick_Triple", -0.6, 4.6, 0.82)
    prop(k, "CandleStick_Triple", 0.6, 4.6, 0.82)
    prop(k, "Banner_1", 0, 5.85, 1.3)
    kb.chandelier(k, 0, 0.0, 0.0, 3)
    marker(k, "Doorway", -0.0, -5.1, 0.0, (0, 1))
    kb.export_kit_building("fx_chapel")


def dovecote():
    """A dovecote on a post: a little boarded house with holes, a pyramid roof."""
    kb.reset()
    k = mv.Kit("T1", 601)
    k.post("Pole", 0.12, 0.0, 3.2, 0, 0)
    k.box("House", (1.4, 1.4, 1.1), (0, 0, 3.75), ("neutral.7", "neutral.6", "wood.3"))
    for side in range(4):
        a = side * math.pi / 2
        for i in (-1, 1):
            x, y = math.cos(a) * 0.71 + -math.sin(a) * i * 0.35, math.sin(a) * 0.71 + math.cos(a) * i * 0.35
            k.box("Hole", (0.2 if abs(math.cos(a)) < 0.5 else 0.04, 0.04 if abs(math.cos(a)) < 0.5 else 0.2, 0.2),
                  (x, y, 3.85), "neutral.0")
    k.add("Roof", mv.prism(4, 1.15, 0.02, 0.8), ("accent.0", "accent.0", "wood.1"), (0, 0, 4.7), (0, 0, math.pi / 4))
    kb.export_kit_building("fx_dovecote")


def pump():
    """A village pump: a timber post with an iron spout and handle over a stone trough."""
    kb.reset()
    k = mv.Kit("T1", 611)
    k.box("PumpPost", (0.32, 0.32, 1.5), (0, 0.3, 0.75), ("wood.3", "wood.2", "wood.2"))
    k.box("Spout", (0.08, 0.4, 0.08), (0, 0.0, 1.05), "metal.2")
    k.box("Handle", (0.06, 0.06, 0.7), (0.0, 0.42, 1.65), "metal.3", rot=(0.7, 0, 0))
    k.stone("Trough", (1.3, 0.6, 0.45), (0, -0.25, 0.22))
    k.box("TroughWater", (1.1, 0.45, 0.02), (0, -0.25, 0.4), "accent.4")
    kb.export_kit_building("fx_pump")


def _cottage_shell(k, open_):
    shutters = "WindowShutters_Wide_Round_Open" if open_ else "WindowShutters_Wide_Round_Closed"
    kb.FILL["o"] = ("Window_Wide_Round1", shutters)
    storey(k, 3, 3, "plaster", front="odo", back="wnw", left="wow", right="wow")
    kb.FILL["o"] = ("Window_Wide_Round1", "WindowShutters_Wide_Round_Open")
    gable_roof(k, 3, 3, WALL_TOP)
    place(k, "Prop_Chimney", (2.0, 1.0, WALL_TOP + 0.5), 0)


def empty_cottage():
    """A shuttered cottage with a "to let" board; opened up (the "open_cottage" project): shutters
    open, flower boxes, a fire lit (smoke) for whoever comes."""
    kb.reset()
    k = mv.Kit("T1", 621)
    _cottage_shell(k, False)
    k.post("BoardPost", 0.06, 0.0, 1.5, 2.2, -4.2)
    k.box("ToLet", (0.9, 0.06, 0.55), (2.2, -4.27, 1.25), ("neutral.7", "neutral.6", "neutral.5"))
    k.box("ToLetWriting", (0.6, 0.02, 0.08), (2.2, -4.31, 1.3), "neutral.1")
    k = mv.Kit("T2", 622)
    _cottage_shell(k, True)
    for x in (-2.0, 2.0):
        k.box("FlowerBox", (1.2, 0.3, 0.25), (x, -3.2, 0.95), ("wood.4", "wood.3", "wood.2"))
        for i in range(4):
            k.add("Flower", mv.blob(0.12, k.rng), "accent.%d" % (1 + i % 3), (x - 0.45 + i * 0.3, -3.2, 1.15))
    k.empty("Smoke", (2.0, 1.0, WALL_TOP + 3.8))
    kb.export_kit_building("fx_empty_cottage")


def ruined_cottage():
    """A cottage fallen in long ago: walls standing to half their height in places, no roof,
    fallen beams and rubble inside."""
    kb.reset()
    k = mv.Kit("T1", 631)
    storey(k, 3, 3, "brick", front="w-w", back="-ww", left="w--", right="ww-", floor=None)
    for i in range(14):
        k.stone("Rubble", (k.rng.uniform(0.3, 0.7), k.rng.uniform(0.3, 0.6), k.rng.uniform(0.2, 0.4)),
                (k.rng.uniform(-2.4, 2.4), k.rng.uniform(-2.4, 2.4), 0.12))
    for a in (0.3, -0.5):
        k.log("FallenBeam", 5.0, 0.12, (0.0, 0.5 + a, 0.35), "x", sides=("wood.2", "wood.1", "wood.2"))
    kb.export_kit_building("fx_ruined_cottage")


BUILDERS = {"barn": barn, "granary": granary, "cart_shed": cart_shed, "stable": stable, "storehouse": storehouse,
            "ore_store": ore_store, "woodshed": woodshed, "timber_yard": timber_yard, "washhouse": washhouse,
            "chapel": chapel, "dovecote": dovecote, "pump": pump, "empty_cottage": empty_cottage,
            "ruined_cottage": ruined_cottage}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for n in argv[2:] or list(BUILDERS):
        BUILDERS[n]()
