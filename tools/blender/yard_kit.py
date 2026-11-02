"""The work yards' pieces (plans/village-street.md, picked on a page 2026-11-01), one .glb each in
models/village/yard/.

    blender -b -P tools/blender/yard_kit.py -- models art/palette.json PACKS_DIR

PACKS_DIR holds the three CC0 packs as downloaded and unzipped (see art/kit/SOURCES.md):
  kenney/Models/GLB format/   Kenney's Survival Kit. A third of real size: KENNEY_SCALE.
  kaykit/KayKit_ResourceBits_1.0_FREE/Assets/gltf/   Kay Lousberg's Resource Bits (free).
  docks/WoodenDockSet_Final.blend   loafbrr's Modular Wooden Docks.
The Fantasy Props pieces come from art/kit/props/. All of them keep their own painted materials,
textures shrunk to 512 px JPEGs. The forge is ours, painted from the palette (Prop gives it the
palette material); its embers are a "LampEmbers" mesh so they glow.

Every piece stands on its origin (the middle of its base), Y up, its front toward +Z.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402
from make_models import swatch_uv  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.join(argv[0], "village", "yard")
PACKS = argv[2]
PROPS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "art", "kit", "props")
os.makedirs(OUT, exist_ok=True)
TEXTURE_SIZE = 512
KENNEY_SCALE = 3.0

FANTASY = {
    "table_large": "Table_Large", "flour_sack": "Bag", "scroll": "Scroll_1", "workbench": "Workbench",
    "anvil_log": "Anvil_Log", "quench_bucket": "Bucket_Metal", "metal_crate": "Crate_Metal",
    "whetstone": "Whetstone", "axe": "Axe_Bronze", "tub": "Bucket_Wooden_1",
}
KENNEY = {"firewood": "resource-wood"}
KAYKIT = {"chopping_log": "Wood_Log_A", "woodpile": "Wood_Log_Stack", "stone_heap": "Stone_Chunks_Large"}
DOCKS = {"fish": "Props_Fish_1", "fish_rack": "Props_Rack_Fish", "gutting_table": "Props_Table_1",
         "jetty_deck": "Floor_Dock"}


def mesh_tree(o):
    out = [o] if o.type == "MESH" else []
    for c in o.children:
        out += mesh_tree(c)
    return out


def bake(objs, scale):
    """Copies of `objs` and their mesh children with world transforms and `scale` in the mesh data."""
    copies = []
    for o in objs:
        for m in mesh_tree(o):
            c = m.copy()
            c.data = m.data.copy()
            c.parent = None
            c.data.transform(Matrix.Scale(scale, 4) @ m.matrix_world)
            c.matrix_world = Matrix.Identity(4)
            copies.append(c)
    return copies


def recentre(copies):
    pts = [v.co for c in copies for v in c.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    shift = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for c in copies:
        c.data.transform(Matrix.Translation(-shift))
    return hi - lo


def shrink_textures(copies):
    for c in copies:
        for mat in c.data.materials:
            if not mat or not mat.use_nodes:
                continue
            for n in mat.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > TEXTURE_SIZE:
                    n.image.scale(TEXTURE_SIZE, TEXTURE_SIZE)


def plain_base_colour(copies):
    """loafbrr's materials multiply the diffuse map by an ambient-occlusion map before Base Color;
    the glTF exporter would keep only the first image (the AO). Wire the diffuse map straight in."""
    for c in copies:
        for mat in c.data.materials:
            if not mat or not mat.node_tree:
                continue
            nodes = mat.node_tree.nodes
            bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
            diffuse = next((n for n in nodes if n.type == "TEX_IMAGE" and n.image and "Diffuse" in n.image.name), None)
            if bsdf and diffuse:
                mat.node_tree.links.new(diffuse.outputs["Color"], bsdf.inputs["Base Color"])


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


def from_file(path, scale):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return bake([o for o in bpy.data.objects if o not in before and o.parent is None], scale)


# --- the forge: a stone hearth with a coal bed, a back wall, a hood and a chimney ---

def _box(bm, lo, hi):
    """An axis-aligned box from corner `lo` to `hi` (Blender axes, Z up)."""
    vs = [bm.verts.new((x, y, z)) for z in (lo[2], hi[2]) for y in (lo[1], hi[1]) for x in (lo[0], hi[0])]
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new([vs[i] for i in f])


def _frustum(bm, z0, z1, w0, d0, w1, d1, y=0.0):
    """A tapered block: a w0 × d0 rectangle at z0 narrowing to w1 × d1 at z1, centred on (0, y)."""
    def ring(z, w, d):
        return [bm.verts.new((sx * w / 2, y + sy * d / 2, z)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    a, b = ring(z0, w0, d0), ring(z1, w1, d1)
    bm.faces.new(a[::-1])
    bm.faces.new(b)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((a[i], a[j], b[j], b[i]))


def _mesh(name, build, top, side, under=None):
    bm = bmesh.new()
    build(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    uv = bm.loops.layers.uv.verify()
    bm.normal_update()
    for f in bm.faces:
        s = top if f.normal.z > 0.5 else (under or side) if f.normal.z < -0.5 else side
        for loop in f.loops:
            loop[uv].uv = swatch_uv(s)
        f.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def forge():
    # front is -Y here (+Z in Godot); the back wall and chimney stand at +Y
    parts = [
        _mesh("Plinth", lambda bm: _box(bm, (-0.85, -0.6, 0.0), (0.85, 0.6, 0.12)), "stone.2", "stone.1"),
        _mesh("Hearth", lambda bm: _box(bm, (-0.78, -0.52, 0.12), (0.78, 0.52, 0.82)), "stone.4", "stone.3"),
        _mesh("Rim", lambda bm: (_box(bm, (-0.78, -0.52, 0.82), (0.78, -0.4, 0.9)),
                                 _box(bm, (-0.78, -0.4, 0.82), (-0.62, 0.3, 0.9)),
                                 _box(bm, (0.62, -0.4, 0.82), (0.78, 0.3, 0.9))), "stone.5", "stone.4"),
        _mesh("Coals", lambda bm: _box(bm, (-0.62, -0.4, 0.82), (0.62, 0.3, 0.86)), "ore.coal", "ore.coal"),
        _mesh("LampEmbers", lambda bm: _box(bm, (-0.38, -0.25, 0.86), (0.38, 0.15, 0.88)), "accent.2", "accent.1"),
        _mesh("BackWall", lambda bm: _box(bm, (-0.78, 0.3, 0.82), (0.78, 0.52, 1.6)), "stone.4", "stone.3"),
        _mesh("Hood", lambda bm: _frustum(bm, 1.6, 2.15, 1.5, 0.95, 0.56, 0.5, y=0.05), "stone.3", "stone.3", "stone.1"),
        _mesh("Chimney", lambda bm: _box(bm, (-0.26, -0.2, 2.15), (0.26, 0.3, 3.0)), "stone.2", "stone.3"),
        _mesh("ChimneyCap", lambda bm: _box(bm, (-0.34, -0.28, 3.0), (0.34, 0.38, 3.09)), "stone.1", "stone.2"),
        # the hood rests on two stone posts at the front corners
        _mesh("Posts", lambda bm: (_box(bm, (-0.78, -0.42, 0.9), (-0.64, -0.3, 1.6)),
                                   _box(bm, (0.64, -0.42, 0.9), (0.78, -0.3, 1.6))), "stone.4", "stone.3"),
    ]
    return parts


bpy.ops.wm.read_factory_settings(use_empty=True)
sizes = {}
pieces = []  # (name, copies, keep_materials)
for name, piece in FANTASY.items():
    pieces.append((name, from_file(os.path.join(PROPS, piece + ".gltf"), 1.0), True))
for name, piece in KENNEY.items():
    pieces.append((name, from_file(os.path.join(PACKS, "kenney", "Models", "GLB format", piece + ".glb"), KENNEY_SCALE), True))
for name, piece in KAYKIT.items():
    pieces.append((name, from_file(os.path.join(PACKS, "kaykit", "KayKit_ResourceBits_1.0_FREE", "Assets", "gltf", piece + ".gltf"), 1.0), True))
with bpy.data.libraries.load(os.path.join(PACKS, "docks", "WoodenDockSet_Final.blend")) as (src, dst):
    dst.objects = [n for n in src.objects if n in DOCKS.values()]
docks = {o.name: o for o in dst.objects if o}
for o in docks.values():
    o.location = (0, 0, 0)  # each sits somewhere in the set's scene
    bpy.context.scene.collection.objects.link(o)
bpy.context.view_layer.update()
for name, piece in DOCKS.items():
    copies = bake([docks[piece]], 1.0)
    plain_base_colour(copies)
    pieces.append((name, copies, True))
pieces.append(("forge", forge(), False))

for name, copies, keep in pieces:
    sizes[name] = recentre(copies)
    if keep:
        shrink_textures(copies)
    export(name, copies, keep)

json.dump({k: [round(v.x, 2), round(v.z, 2), round(v.y, 2)] for k, v in sizes.items()},
          open(os.path.join(OUT, "sizes.json"), "w"), indent=1)
print("SIZES", {k: tuple(round(x, 2) for x in v) for k, v in sizes.items()})
