"""Crumbs (plans/crumbs.md): cuts every piece ("block") of the breakable rocks and the ore wall
panels into crumbs, so a swing takes out a pickaxe-sized bit rather than a whole piece.

    blender -b -P tools/blender/make_crumbs.py -- models [rock iron_rock coal_rock gold_rock walls]

It reads the models as committed (models/<name>.glb and .pieces.json) rather than baking them
again, so the blocks, and every save that names them, stay exactly as they are. Each block gets a
skin of crumb seeds CRUMB apart, SKIN in under its faces that can be struck (a rock's outside; the
face side of a wall's piece), and one core seed deeper in for the rest; the block is cut into the
Voronoi cells round them. The crumbs keep the block's paint, baked weathering and smooth normals
on its outside; their new faces are fresh cut stone.

Writes models/<name>_crumbs.glb (walls: models/walls/panel_<n>_L<k>_crumbs.glb, a layer each) of
Crumb objects, each placed at its own centre, and adds to the .pieces.json:
    "crumbs": {crumb: {"block": block, "core": bool, "volume": m3, "links": [crumbs]}}
"""

import bmesh
import bpy
import json
import math
import os
import random
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

argv = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = argv[0]
ONLY = argv[1:]

ROCKS = ["rock", "iron_rock", "coal_rock", "gold_rock"]  # (crystal: its prisms snap off whole)
WALL_TEMPLATES = 4
WALL_LAYERS = 8
CRUMB = 0.13  # skin seeds at least this far apart (m)
SKIN = 0.065  # ... and this far in under the surface
CORE_IN = 0.12  # the core seed: this far in from the block's middle, away from its skin
LINK = 1.9  # crumbs of touching blocks link when their seeds are within this many CRUMBs


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path):
    """The model's mesh objects by name, transforms applied (Blender space, z up)."""
    bpy.ops.import_scene.gltf(filepath=path)
    objs = {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs.values():
        o.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(objs.values()))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return objs


class Block:
    """One piece as imported: its mesh merged into a closed shell for cutting, which faces are cut
    faces (fresh, alpha 0), and what's needed to give a crumb's outside the block's normals."""

    def __init__(self, obj):
        self.name = obj.name
        me = obj.data
        self.mesh = me
        colour = me.color_attributes[0] if len(me.color_attributes) else None
        self.colour_name = colour.name if colour else None
        cut = []
        for p in me.polygons:
            if colour is None:
                cut.append(False)
                continue
            if colour.domain == "CORNER":
                a = sum(colour.data[i].color[3] for i in p.loop_indices) / p.loop_total
            else:
                a = sum(colour.data[v].color[3] for v in p.vertices) / p.loop_total
            cut.append(a < 0.5)
        self.bvh = BVHTree.FromPolygons([v.co for v in me.vertices], [p.vertices for p in me.polygons])
        self.corner_normals = [n.vector.copy() for n in me.corner_normals]
        bm = bmesh.new()
        bm.from_mesh(me)
        flag = bm.faces.layers.int.new("cutflag")
        cap = bm.faces.layers.int.new("cap")
        across = bm.faces.layers.int.new("across")
        bm.faces.ensure_lookup_table()
        for f, c in zip(bm.faces, cut):
            f[flag] = 1 if c else 0
            f[cap] = 0
            f[across] = -1
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
        bm.normal_update()
        self.bm = bm
        self.uv_cut = None  # the fresh-stone swatch of its cut faces
        uv = bm.loops.layers.uv.active
        for f in bm.faces:
            if f[flag] and uv:
                self.uv_cut = f.loops[0][uv].uv.copy()
                break
        self.centre = sum((v.co for v in bm.verts), Vector()) / max(len(bm.verts), 1)

    def normal_at(self, p, fallback):
        """The block's own (smooth) normal at a point of its surface."""
        loc, _n, index, dist = self.bvh.find_nearest(p)
        if index is None or dist > 0.01:
            return fallback
        poly = self.mesh.polygons[index]
        weights = poly_3d_calc([self.mesh.vertices[v].co for v in poly.vertices], loc)
        n = Vector()
        for w, li in zip(weights, poly.loop_indices):
            n += self.corner_normals[li] * w
        return n.normalized() if n.length > 1e-6 else fallback


def skin_seeds(block, rng, faces_out):
    """Seeds CRUMB apart, SKIN in under the faces `faces_out(face)` picks."""
    bm = block.bm
    flag = bm.faces.layers.int.get("cutflag")
    faces = [f for f in bm.faces if faces_out(f, flag)]
    area = sum(f.calc_area() for f in faces)
    if area < CRUMB * CRUMB * 0.6:
        return []
    tries = int(area / (CRUMB * CRUMB) * 8) + 8
    weights = [f.calc_area() for f in faces]
    points = []
    for _ in range(tries):
        f = rng.choices(faces, weights)[0]
        a, b, c = (v.co for v in f.verts[:3])
        r1, r2 = rng.random(), rng.random()
        if r1 + r2 > 1.0:
            r1, r2 = 1.0 - r1, 1.0 - r2
        p = a + (b - a) * r1 + (c - a) * r2 - f.normal * SKIN
        if all((p - q).length >= CRUMB for q in points):
            points.append(p)
    return points


def cut_cell(block, seeds, i):
    """The part of the block nearer seeds[i] than its other seeds, capped where cut ("cap" 1,
    "across" the seed on the other side)."""
    bm = block.bm.copy()
    cap = bm.faces.layers.int.get("cap")
    across = bm.faces.layers.int.get("across")
    a = seeds[i]
    for j, b in enumerate(seeds):
        if j == i or not bm.faces or (b - a).length > CRUMB * 6.0 and j != len(seeds) - 1:
            continue
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                     plane_co=(a + b) * 0.5, plane_no=(b - a).normalized(), clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
        if edges:
            for f in bmesh.ops.holes_fill(bm, edges=edges, sides=0)["faces"]:
                f[cap] = 1
                f[across] = j
    return bm


def crumbs_of(block, seeds, prefix):
    """Cuts the block round `seeds` (the last is its core). [(name, bmesh, seed, core, [neighbour
    seed indices], volume)], empty cells left out."""
    out = []
    for i in range(len(seeds)):
        bm = cut_cell(block, seeds, i) if len(seeds) > 1 else block.bm.copy()
        if not bm.faces or bm.calc_volume() < 1e-6:
            bm.free()
            continue
        cap = bm.faces.layers.int.get("cap")
        across = bm.faces.layers.int.get("across")
        near = sorted({f[across] for f in bm.faces if f[cap] and f[across] >= 0 and f.calc_area() > 1e-5})
        out.append([f"{prefix}c{i:02d}", bm, seeds[i], i == len(seeds) - 1, near, abs(bm.calc_volume())])
    return out


def finish(block, bm, name):
    """A crumb's mesh as an object at its centre: caps painted fresh cut stone (white, alpha 0)
    with flat normals; the rest keeps the block's paint, weathering and normals."""
    cap = bm.faces.layers.int.get("cap")
    flag = bm.faces.layers.int.get("cutflag")
    uv = bm.loops.layers.uv.active
    col = bm.loops.layers.float_color.active or bm.loops.layers.color.active
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    for f in bm.faces:
        if f[cap]:
            f[flag] = 1
            for loop in f.loops:
                if uv and block.uv_cut is not None:
                    loop[uv].uv = block.uv_cut
                if col:
                    loop[col] = (1.0, 1.0, 1.0, 0.0)
        f.smooth = True
    normals = []
    for f in bm.faces:
        for loop in f.loops:
            normals.append(f.normal.copy() if f[flag] else block.normal_at(loop.vert.co, f.normal))
    centre = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    bmesh.ops.translate(bm, vec=-centre, verts=bm.verts)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.normals_split_custom_set(normals)
    if block.colour_name and len(me.color_attributes):
        me.color_attributes[0].name = "cut_mark"
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    obj.location = centre
    return obj


def bake(blocks, faces_out, rng, prefix_of, links):
    """Crumbs for `blocks` (Block by name); `links` block -> touching blocks. Returns the crumbs'
    json and leaves their objects in the scene (the blocks removed)."""
    made = {}  # block -> [(name, seed, core)]
    data = {}
    pending = []
    for name, block in blocks.items():
        seeds = skin_seeds(block, rng, faces_out)
        if seeds:
            out_dir = sum(((block.centre - s) for s in seeds), Vector())
            out_dir = out_dir.normalized() if out_dir.length > 1e-6 else Vector((0, 0, 0))
            seeds.append(block.centre + out_dir * CORE_IN)
        else:
            seeds = [block.centre]
        cells = crumbs_of(block, seeds, prefix_of(name))
        made[name] = []
        for cname, bm, seed, core, near, volume in cells:
            pending.append((block, bm, cname))
            made[name].append((cname, seed, core))
            data[cname] = {"block": name, "core": core, "volume": round(volume, 6),
                           "links": [f"{prefix_of(name)}c{j:02d}" for j in near]}
    names = {c for c in data}
    for c in data.values():  # (a neighbour whose cell came out empty isn't one)
        c["links"] = [l for l in c["links"] if l in names and not data[l]["core"]]
    for a, others in links.items():  # crumbs of touching blocks, near enough, touch too
        for b in others:
            for an, aseed, acore in made.get(a, []):
                for bn, bseed, bcore in made.get(b, []):
                    if not acore and not bcore and (aseed - bseed).length < CRUMB * LINK and bn not in data[an]["links"]:
                        data[an]["links"].append(bn)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for block, bm, cname in pending:
        finish(block, bm, cname)
    return data


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                              export_materials="NONE", export_vertex_color="NAME",
                              export_vertex_color_name="cut_mark")
    print("exported", path)


def rock(name):
    reset()
    base = os.path.join(OUT_DIR, name)
    pieces = json.load(open(base + ".pieces.json"))
    objs = import_model(base + ".glb")
    blocks = {n: Block(o) for n, o in objs.items() if n in pieces["links"]}
    rng = random.Random("crumbs:" + name)
    # the outside, but not the underside (it sits on the ground)
    data = bake(blocks, lambda f, flag: not f[flag] and f.normal.z > -0.6, rng,
                lambda n: n.replace("Chunk_", "Crumb_") + "_", pieces["links"])
    export(base + "_crumbs.glb")
    pieces["crumbs"] = data
    with open(base + ".pieces.json", "w") as f:
        json.dump(pieces, f, indent=1)
    skins = sum(1 for c in data.values() if not c["core"])
    print(f"{name}: {len(blocks)} blocks, {len(data)} crumbs ({skins} skin)")


def walls():
    for n in range(WALL_TEMPLATES):
        base = os.path.join(OUT_DIR, "walls", f"panel_{n}")
        pieces = json.load(open(base + ".pieces.json"))
        crumbs = {}
        for k in range(WALL_LAYERS):
            reset()
            objs = import_model(base + ".glb")
            layer = set(pieces["layers"][k])
            blocks = {nm: Block(o) for nm, o in objs.items() if nm in layer}
            rng = random.Random(f"crumbs:panel_{n}:{k}")
            # the face side: out of the wall is -y (Blender space)
            data = bake(blocks, lambda f, flag: f.normal.y < -0.5, rng, lambda nm: nm + "_",
                        {a: b for a, b in pieces["links"].items() if a in layer})
            export(f"{base}_L{k}_crumbs.glb")
            crumbs.update(data)
            print(f"panel_{n} layer {k}: {len(blocks)} blocks, {len(data)} crumbs")
        pieces["crumbs"] = crumbs
        with open(base + ".pieces.json", "w") as f:
            json.dump(pieces, f, indent=1)


if __name__ == "__main__":
    for r in ROCKS:
        if not ONLY or r in ONLY:
            rock(r)
    if not ONLY or "walls" in ONLY:
        walls()
