"""The mine's pack pieces (plans/mine.md, picked on a page 2026-10-29), one .glb each in models/mine/.

    blender -b -P tools/blender/mine_kit.py -- models art/palette.json PACKS_DIR

PACKS_DIR holds the two CC0 packs from OpenGameArt, unzipped as downloaded (see art/kit/SOURCES.md):
  loaf/GLTF/MinesPack.gltf   loafbrr_1's "Mine Object collection": rails, carts, pillars, tools.
                             Kept in their own painted materials, textures shrunk to 512 px JPEGs.
  duck/mine_parts.blend      rubberduck's "free mine assets": timber, lamps, rocks, stalactites. Its
                             old Blender Internal materials come through as flat colours, so they're
                             painted from our palette like our own models (Prop gives them the
                             palette material); a lamp's glass is its own "LampGlass" mesh so it glows.
The Fantasy Props pieces (art/kit/props/) come along in their own materials, as the houses use them.

Every piece stands on its origin (the middle of its base), Y up, except hanging lamps, which hang
from theirs. Scales: loafbrr's are in metres; rubberduck's are about 5.5 times too big (DUCK_SCALE).
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from make_models import swatch_uv  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.join(argv[0], "mine")
PACKS = argv[2]
PROPS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "art", "kit", "props")
os.makedirs(OUT, exist_ok=True)
DUCK_SCALE = 0.18
TEXTURE_SIZE = 512

# name -> (source objects, hangs from its origin)
DUCK = {
    "frame_square": (["Wooden_14"], False), "frame_braced": (["Wooden_09"], False),
    "frame_arched": (["Wooden_16"], False), "post_cap": (["Wooden_04"], False),
    "post_crossbraced": (["Wooden_01"], False), "post_brackets": (["Wooden_02"], False),
    "gate_posts": (["Wooden_29"], False), "planks": (["Wooden_21"], False),
    "boardwalk": (["Wooden_33"], False), "lamp_hanging": (["Lamp_01"], True),
    "lamp_hanging_plain": (["Lamp_02"], True), "chest": (["chest", "chest_top.001"], False),
    "boulder_small": (["rock_5_low"], False), "rubble_pile": (["rocks_1_low"], False),
    "stalactite": (["stalag_3_low"], True), "stalactite_cluster": (["stalags_4_low"], True),
}
# rubberduck material -> palette swatches (lit from above, side, underneath)
DUCK_PAINT = {
    "wood": ("wood.5", "wood.4", "wood.2"), "metal": ("metal.3", "metal.2", "metal.1"),
    "light": ("accent.6", "accent.6", "accent.6"), "rock": ("stone.4", "stone.3", "stone.2"),
    "stalags": ("stone.5", "stone.4", "stone.3"), "gold_coins": ("ore.gold", "ore.gold", "ore.gold"),
    "cable": ("metal.1", "metal.1", "metal.1"),
}
LOAF = {
    "rail": ["Rail"], "rail_curve": ["Rail_C"], "rail_junction": ["Rail_T"],
    "cart_tall": ["Cart_1"], "cart_low": ["Cart_2"], "cart_chassis": ["CartFrame", "CartWheels_1", "CartWheel_2"],
    "pillar": ["Post_1"], "pillar_ribbed": ["Post_2"], "pillar_half": ["Post_Half_1"],
    "post": ["WoodPost"], "beam": ["WoodPostBeams_2"], "brace": ["WoodSupport_2"],
    "fence": ["Fence"], "door": ["Door"], "chain": ["Chain"],
    "pickaxe": ["PickAxe"], "shovel": ["Shovel"], "hammer": ["Hammer"],
    "tub": ["JarWood"], "jar": ["Jar_1"], "basin": ["StoneBowl"], "rock_a": ["Rocks_5"], "rock_b": ["Rocks_8"],
}
HANGS = {"chain"}
PROPS_PICKED = {
    "lantern_wall": "Lantern_Wall", "torch": "Torch_Metal", "pickaxe_bronze": "Pickaxe_Bronze",
    "crate": "Crate_Wooden", "barrel": "Barrel", "bucket": "Bucket_Wooden_1", "rope": "Rope_1",
    "chain_coil": "Chain_Coil",
}


def mesh_tree(o, children=True):
    out = [o] if o.type == "MESH" else []
    for c in o.children if children else ():
        out += mesh_tree(c)
    return out


def bake(objs, scale, children=True):
    """Copies of `objs` (and their mesh children) with their world transforms and `scale` applied
    to the mesh data, moved so the base's middle is at the origin. Returns them and the bounds."""
    copies = []
    for o in objs:
        for m in mesh_tree(o, children):
            c = m.copy()
            c.data = m.data.copy()
            c.parent = None
            c.data.transform(Matrix.Scale(scale, 4) @ m.matrix_world)
            c.matrix_world = Matrix.Identity(4)
            copies.append(c)
    return copies


def recentre(copies, hangs):
    pts = [v.co for c in copies for v in c.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    shift = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, hi.z if hangs else lo.z))
    for c in copies:
        c.data.transform(Matrix.Translation(-shift))
    return hi - lo


def paint_duck(copies):
    """Palette UVs per face from its rubberduck material, shaded by which way the face points; the
    lamp glass split into its own LampGlass object."""
    out = []
    for c in copies:
        me = c.data
        uv = me.uv_layers.new(name="palette") if "palette" not in me.uv_layers else me.uv_layers["palette"]
        for layer in [l for l in me.uv_layers if l.name != "palette"]:
            me.uv_layers.remove(layer)
        glass = []
        for p in me.polygons:
            mat = me.materials[p.material_index].name if me.materials and me.materials[p.material_index] else "wood"
            key = next((k for k in DUCK_PAINT if mat.startswith(k)), "wood")
            top, side, under = DUCK_PAINT[key]
            name = top if p.normal.z > 0.5 else under if p.normal.z < -0.5 else side
            for li in p.loop_indices:
                uv.data[li].uv = swatch_uv(name)
            if key == "light":
                glass.append(p.index)
        me.materials.clear()
        if glass:
            g = c.copy()
            g.data = me.copy()
            _keep_faces(g.data, set(glass))
            _keep_faces(me, set(range(len(me.polygons))) - set(glass))
            g.name = "LampGlass"
            out.append(g)
        out.append(c)
    return out


def _keep_faces(me, keep):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bm.to_mesh(me)
    bm.free()


def shrink_textures(copies):
    for c in copies:
        for mat in c.data.materials:
            if not mat or not mat.use_nodes:
                continue
            for n in mat.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > TEXTURE_SIZE:
                    n.image.scale(TEXTURE_SIZE, TEXTURE_SIZE)


def export(name, copies, keep_materials):
    scene = bpy.data.scenes.new(name)
    for c in copies:
        scene.collection.objects.link(c)
    bpy.context.window.scene = scene
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, use_active_scene=True,
                              export_apply=True, export_materials="EXPORT" if keep_materials else "NONE",
                              export_image_format="JPEG", export_jpeg_quality=85)
    print("exported", path)


bpy.ops.wm.read_factory_settings(use_empty=True)
sizes = {}

# loafbrr_1: import the whole pack once.
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=os.path.join(PACKS, "loaf", "GLTF", "MinesPack.gltf"))
loaf = {o.name: o for o in bpy.data.objects if o not in before}
for name, parts in LOAF.items():
    copies = bake([loaf[p] for p in parts], 1.0, children=False)  # (a post's beams hang off it)
    sizes[name] = recentre(copies, name in HANGS)
    shrink_textures(copies)
    export(name, copies, True)

# rubberduck: the objects straight out of the .blend.
with bpy.data.libraries.load(os.path.join(PACKS, "duck", "mine_parts.blend")) as (src, dst):
    dst.objects = [n for n in src.objects if n in {p for parts, _ in DUCK.values() for p in parts}]
duck = {o.name: o for o in dst.objects if o}
for name, (parts, hangs) in DUCK.items():
    copies = bake([duck[p] for p in parts], DUCK_SCALE)
    sizes[name] = recentre(copies, hangs)
    export(name, paint_duck(copies), False)

# Fantasy Props kit pieces, as they are.
for name, piece in PROPS_PICKED.items():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(PROPS, piece + ".gltf"))
    new = [o for o in bpy.data.objects if o not in before and o.parent is None]
    copies = bake(new, 1.0)
    sizes[name] = recentre(copies, False)
    export(name, copies, True)

json.dump({k: [round(v.x, 2), round(v.z, 2), round(v.y, 2)] for k, v in sizes.items()},
          open(os.path.join(OUT, "sizes.json"), "w"), indent=1)
print("SIZES", {k: tuple(round(x, 2) for x in v) for k, v in sizes.items()})
