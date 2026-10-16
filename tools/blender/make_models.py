"""Generates the starter low-poly models as .glb files, using Blender's Python API.

Run headless from the project folder (Blender 4.2+ / 5.x):

    blender -b -P tools/blender/make_models.py -- models art/palette.json [builder ...]

Name builders (e.g. `forest`) to rebuild only those models.

Every model is built from a few primitives with jittered vertices, flat-shaded, and coloured by
pointing each face's UVs at a swatch of art/palette.png (looked up by name in palette.json).
Object names follow the ResourceNode convention: Body_*, Chunk_*, Rubble_*.

These are starters to learn from: open a .glb in Blender (File > Import > glTF), tweak, and
export back over it (File > Export > glTF 2.0, format .glb). Re-running this script overwrites
them, so rename yours if you want to keep both.

Coordinates here are Blender's (Z up, -Y toward the viewer); the glTF exporter converts to
Godot's Y-up, so Blender +Y becomes Godot -Z (forward).
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = argv[0]
SWATCHES = json.load(open(argv[1]))["swatches"]


# --- helpers ----------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def swatch_uv(name):
    u, v = SWATCHES[name]["uv"]  # image space, origin top-left
    return (u, 1.0 - v)          # Blender UV space, origin bottom-left


def paint(bm, choose):
    """Colour every face: choose(face) returns a palette swatch name. Also flat-shades."""
    uv_layer = bm.loops.layers.uv.verify()
    bm.normal_update()
    for f in bm.faces:
        uv = swatch_uv(choose(f))
        for loop in f.loops:
            loop[uv_layer].uv = uv
        f.smooth = False


def shade_by_normal(top, side, bottom, rng, side_alt=None):
    """Lighter on top, darker underneath, a little random variation on the sides."""
    def choose(f):
        if f.normal.z > 0.55:
            return top
        if f.normal.z < -0.4:
            return bottom
        return side_alt if side_alt and rng.random() < 0.35 else side
    return choose


def jitter(bm, amount, rng, squash=(1.0, 1.0, 1.0)):
    for v in bm.verts:
        v.co *= 1.0 + rng.uniform(-amount, amount)
        v.co.x *= squash[0]
        v.co.y *= squash[1]
        v.co.z *= squash[2]


def make_object(name, bm, location=(0, 0, 0), rotation=(0, 0, 0)):
    """Object origin = its own centre (mesh built around 0), placed at `location`."""
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = Euler(rotation)
    return obj


def blob(radius, rng, jitter_amount=0.18, squash=(1, 1, 0.75), subdiv=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    jitter(bm, jitter_amount, rng, squash)
    return bm


def box(size):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return bm


def prism(segments, r_bottom, r_top, height):
    """Upright n-sided column, centred on the origin."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r_bottom, radius2=r_top, depth=height)
    return bm


def export(name, loose_edges=False):
    """Writes models/<name>.glb. With `loose_edges` (the breakable rocks), also the Seam_* lines and
    the "cut_mark" vertex colour (see mark_cut)."""
    path = os.path.join(OUT_DIR, name + ".glb")
    colours = {"export_vertex_color": "NAME", "export_vertex_color_name": "cut_mark"} if loose_edges else {}
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                              export_apply=True, export_materials="NONE", use_mesh_edges=loose_edges, **colours)
    print("exported", path)


# --- models -----------------------------------------------------------------------------------

def voronoi_cell(src, seeds, index):
    """The part of the closed mesh `src` nearer seeds[index] than any other seed (one Voronoi
    cell), capped where it was cut. Cap faces get 1 in the int face layer "cut"."""
    bm = src.copy()
    cut = bm.faces.layers.int.get("cut") or bm.faces.layers.int.new("cut")
    a = seeds[index]
    for j, b in enumerate(seeds):
        if j == index or not bm.faces:
            continue
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                     plane_co=(a + b) * 0.5, plane_no=(b - a).normalized(), clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
        if edges:
            for f in bmesh.ops.holes_fill(bm, edges=edges, sides=0)["faces"]:
                f[cut] = 1
    return bm


def mark_cut(bm, cut):
    """Writes which faces are cut faces into a vertex colour named "cut_mark" (red on them, black on
    the outside), so the game can tell a piece's outside from the faces it shares with its
    neighbours. (The rock shader doesn't use vertex colour; the glTF exporter drops extra UVs.)"""
    # (not "cut": that's the face layer, and a mesh keeps only one attribute per name)
    layer = bm.loops.layers.color.get("cut_mark") or bm.loops.layers.color.new("cut_mark")
    for f in bm.faces:
        for loop in f.loops:
            loop[layer] = (1.0, 0.0, 0.0, 1.0) if f[cut] else (0.0, 0.0, 0.0, 1.0)


def outline(bm, cut):
    """The edges of a Voronoi piece where its outside meets a cut face: where it splits from the
    rest, on the boulder's surface. A mesh of loose edges (exported as glTF lines)."""
    seam = bmesh.new()
    verts = {}
    for e in bm.edges:
        faces = e.link_faces
        if len(faces) == 2 and faces[0][cut] != faces[1][cut]:
            ends = []
            for v in e.verts:
                key = tuple(round(c, 4) for c in v.co)
                if key not in verts:
                    verts[key] = seam.verts.new(v.co)
                ends.append(verts[key])
            if ends[0] is not ends[1]:
                seam.edges.new(ends)
    return seam


# --- ore designs ------------------------------------------------------------------------------
# Candidate looks for each ore, two apiece, built to break apart like rock() (core, chunks, seams,
# rubble) so the crack minigame works on all of them. Exported to models/designs/ for review; the
# game doesn't use them until one is picked. Build them with the `designs` builder.

LETTERS = "ABCDEFGHIJKLMNOP"


def stretched_cell(src, seeds, index, stretch):
    """voronoi_cell, with distances measured as if the axes were scaled by `stretch`: a large z
    favours flat horizontal cuts (layers), a tiny z upright ones (columns)."""
    s = Vector(stretch)
    bm = src.copy()
    for v in bm.verts:
        v.co = Vector((v.co.x * s.x, v.co.y * s.y, v.co.z * s.z))
    cell = voronoi_cell(bm, [Vector((p.x * s.x, p.y * s.y, p.z * s.z)) for p in seeds], index)
    bm.free()
    for v in cell.verts:
        v.co = Vector((v.co.x / s.x, v.co.y / s.y, v.co.z / s.z))
    cell.normal_update()
    return cell


def chop(bm, point, normal, as_cut=False):
    """Cuts away everything on the `normal` side of the plane and caps the hole: as outside
    surface, or with `as_cut` as a cut face. (Set either way: a filled face copies the "cut" mark
    from its neighbours, so a cap on a piece's cut sides would otherwise pass for one.)"""
    res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                 plane_co=point, plane_no=normal, clear_outer=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
    if edges:
        layer = bm.faces.layers.int.get("cut")
        for f in bmesh.ops.holes_fill(bm, edges=edges, sides=0)["faces"]:
            if layer is not None:
                f[layer] = 1 if as_cut else 0


def boulder_mesh(rng, size=1.0, subdiv=3, squash=(1.2, 1.05, 0.7), lumps=6, lump_amp=(0.12, 0.24),
                 chops=5, chop_depth=(0.78, 0.88), noise=0.05):
    """rock()'s boulder, with the knobs exposed: an icosphere squashed, lumped, chopped flat in a
    few places and sat on the ground. Returns (mesh, centre height)."""
    radius, centre_z = size, size * squash[2] * 0.72
    whole = bmesh.new()
    bmesh.ops.create_icosphere(whole, subdivisions=subdiv, radius=radius)
    bumps = [(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 1))).normalized(),
              rng.uniform(*lump_amp)) for _ in range(lumps)]
    for v in whole.verts:
        d = v.co.normalized()
        v.co *= 1.0 + sum(amp * max(0.0, d.dot(l)) ** 2 for l, amp in bumps) + rng.uniform(-noise, noise)
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2] + centre_z))
    for _ in range(chops):
        a = rng.uniform(0, math.tau)
        n = Vector((math.cos(a), math.sin(a), rng.uniform(-0.1, 0.9))).normalized()
        chop(whole, Vector((n.x * radius * squash[0], n.y * radius * squash[1],
                            centre_z + n.z * radius * squash[2])) * rng.uniform(*chop_depth), n)
    chop(whole, Vector((0, 0, -0.04 * size)), Vector((0, 0, -1)))  # the base
    bmesh.ops.triangulate(whole, faces=whole.faces[:])
    return whole, centre_z


def shell_seeds(rng, size, squash, centre_z, sides=7, tops=3, out=(0.72, 0.62)):
    """rock()'s seeds: one for the core, `sides` round the sides, `tops` on top."""
    def at(azimuth, elevation, k):
        return Vector((math.cos(elevation) * math.cos(azimuth) * size * squash[0] * k,
                       math.cos(elevation) * math.sin(azimuth) * size * squash[1] * k,
                       centre_z + math.sin(elevation) * size * squash[2] * k))
    seeds = [Vector((0, 0, centre_z * 0.75))]
    seeds += [at(i * math.tau / sides + rng.uniform(-0.2, 0.2), rng.uniform(0.0, 0.3), out[0]) for i in range(sides)]
    seeds += [at(i * math.tau / tops + rng.uniform(0, 1.0), rng.uniform(0.6, 0.85), out[1]) for i in range(tops)]
    return seeds


def fractured(name, rng, whole, seeds, choose, stretch=None, post=None, rubble=("stone.4", "stone.2", "stone.1"),
              size=1.0, out="designs"):
    """Cuts `whole` into Voronoi pieces round `seeds` (the first is the core) and builds them as
    rock() does: Body_Core, Chunk_* each with its Seam_*, and Rubble_*. choose(face, is_cut, piece)
    picks each face's swatch; post(piece_mesh, piece, cut_layer) can reshape a piece first. Exports
    to models/<out>/<name>.glb (out="" for the game's own models/<name>.glb)."""
    for i in range(len(seeds)):
        bm = stretched_cell(whole, seeds, i, stretch) if stretch else voronoi_cell(whole, seeds, i)
        cut = bm.faces.layers.int.get("cut") or bm.faces.layers.int.new("cut")
        if post:
            post(bm, i, cut)
        if not bm.faces:
            continue
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        paint(bm, lambda f, i=i, cut=cut: choose(f, f[cut] == 1, i))
        mark_cut(bm, cut)
        if i > 0:
            make_object(f"Seam_{LETTERS[i - 1]}", outline(bm, cut))
        centre = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        bmesh.ops.translate(bm, vec=-centre, verts=bm.verts)
        make_object("Body_Core" if i == 0 else f"Chunk_{LETTERS[i - 1]}", bm, centre)
    whole.free()
    for i in range(4):
        a = i * math.tau / 4 + rng.uniform(-0.4, 0.4)
        d = rng.uniform(0.2, 0.6) * size
        bm = blob(rng.uniform(0.3, 0.45) * size, rng, jitter_amount=0.3, squash=(1.2, 1.0, 0.4), subdiv=1)
        paint(bm, shade_by_normal(*rubble, rng))
        make_object(f"Rubble_{i}", bm, (math.cos(a) * d, math.sin(a) * d, 0.08 * size), (0, 0, rng.uniform(0, math.tau)))
    export(os.path.join(out, name) if out else name, loose_edges=True)


def mirrored(s, n, p):
    """`s` reflected through the plane through `p` with normal `n`."""
    return s - 2.0 * (s - p).dot(n) * n


def near_plane(c, planes):
    """Whether a point is inside any of the bands (normal, point, half-width)."""
    return any(abs((c - p).dot(n)) < w for n, p, w in planes)


def slice_mesh(bm, cuts):
    """Cuts the mesh's faces along each plane (point, normal) without removing anything, so a band
    or vein painted by face position gets crisp straight edges instead of ragged triangles."""
    for p, n in cuts:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=p, plane_no=n)


def band_cuts(bands):
    """Both edges of every band (normal, point, half-width), for slice_mesh."""
    return [(p + n * w * side, n) for n, p, w in bands for side in (-1, 1)]


def layer_cuts(normal, spacing, lo, hi):
    """Parallel planes `spacing` apart along `normal`, from `lo` to `hi` (distances from the origin)."""
    return [(normal * (lo + k * spacing), normal) for k in range(int((hi - lo) / spacing) + 1)]


def copper_verdigris(name="copper_verdigris", out="designs"):
    """Copper A: a rounded warm-grey boulder crusted with green verdigris on top, cut by two
    copper veins. The pieces are seeded in pairs mirrored across each vein, so the seams run along
    the veins: every split opens up a bright sheet of copper."""
    reset()
    rng = random.Random(101)
    squash = (1.2, 1.05, 0.72)
    whole, cz = boulder_mesh(rng, 1.0, squash=squash, chops=3, lump_amp=(0.15, 0.28))
    centre = Vector((0, 0, cz))
    veins = [(Vector((1, 0.35, 0.25)).normalized(), centre + Vector((0.15, 0, 0)), 0.07),
             (Vector((-0.3, 1, -0.4)).normalized(), centre + Vector((0, -0.1, 0.1)), 0.06)]
    crust_z = cz + 0.38  # verdigris above this, where rain and weather get at it
    slice_mesh(whole, band_cuts(veins) + [(Vector((0, 0, crust_z)), Vector((0, 0, 1)))])
    seeds = [Vector((0, 0, cz * 0.7))]
    for n, p, _ in veins:  # pairs either side of each vein
        for a in (0.6, 2.2):
            s = centre + Vector((math.cos(a) * 0.75, math.sin(a) * 0.65, rng.uniform(-0.05, 0.2)))
            s += n * (0.28 - (s - p).dot(n))  # a fixed distance on one side ...
            seeds += [s, mirrored(s, n, p)]  # ... and its twin on the other
    seeds += [centre + Vector((0.2, 0.25, 0.42)), centre + Vector((-0.35, -0.2, 0.38))]
    stone = shade_by_normal("stone.5", "stone.4", "stone.2", rng, side_alt="terrain.rock")

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        if near_plane(c, veins):
            return "ore.copper" if is_cut or f.normal.z > 0.2 else "ore.copper_dark"
        if is_cut:
            return "stone.6"
        if c.z > crust_z and f.normal.z > 0.2:
            return "leaves.6" if f.normal.z > 0.6 else "leaves.5"
        return stone(f)
    fractured(name, rng, whole, seeds, choose, out=out)


def copper_malachite():
    """Copper B: a dark stone boulder under a thick green malachite crust; inside it's banded in
    stripes of light and dark green, so every break shows the banding."""
    reset()
    rng = random.Random(102)
    squash = (1.15, 1.05, 0.75)
    whole, cz = boulder_mesh(rng, 1.0, squash=squash, chops=4, lump_amp=(0.18, 0.3))
    axis = Vector((0.3, 0.2, 1)).normalized()
    slice_mesh(whole, layer_cuts(axis, 0.07, -0.3, 1.6))
    seeds = shell_seeds(rng, 1.0, squash, cz)
    stone = shade_by_normal("stone.3", "stone.2", "stone.1", rng)

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        if is_cut:
            band = int((c.dot(axis) + 0.3) / 0.07) % 4
            return ("leaves.6", "leaves.4", "leaves.2", "leaves.4")[band]
        if f.normal.z > 0.45:
            return "leaves.4" if f.normal.z > 0.75 else "leaves.3"
        return stone(f)
    fractured("copper_malachite", rng, whole, seeds, choose, rubble=("leaves.3", "stone.2", "stone.1"))


def iron_columns(name="iron_columns", out="designs"):
    """Iron A: a cluster of dark basalt columns of different heights (upright Voronoi cells of a
    tall prism, each with its own flat top), rust bleeding down from the tops; the faces a break
    opens glint with iron."""
    reset()
    rng = random.Random(103)
    size = 1.1
    whole = prism(9, 1.15 * size, 1.05 * size, 2.0 * size)
    bmesh.ops.translate(whole, vec=Vector((0, 0, 1.0 * size - 0.04)), verts=whole.verts)
    for v in whole.verts:
        v.co.x *= 1.05 + rng.uniform(-0.04, 0.04)
        v.co.y *= 0.95 + rng.uniform(-0.04, 0.04)
    seeds = [Vector((0, 0, 0.5))]
    for k in range(6):  # a ring round the middle column ...
        a = k * math.tau / 6 + rng.uniform(-0.15, 0.15)
        seeds.append(Vector((math.cos(a) * 0.52, math.sin(a) * 0.48, 0.5)))
    for k in range(5):  # ... and an outer one
        a = k * math.tau / 5 + 0.3 + rng.uniform(-0.2, 0.2)
        seeds.append(Vector((math.cos(a) * 1.0, math.sin(a) * 0.92, 0.5)))
    tops = [size * 1.55] + [size * rng.uniform(1.05, 1.4) for _ in range(6)] + [size * rng.uniform(0.55, 0.95) for _ in range(5)]
    rust = [size * rng.uniform(0.2, 0.4) for _ in seeds]  # how far rust runs down each one

    def post(bm, i, cut):  # a flat (slightly tilted) top at this column's height
        tilt = Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 1)).normalized()
        chop(bm, Vector((0, 0, tops[i])), tilt)
        slice_mesh(bm, [(Vector((0, 0, tops[i] - rust[i])), Vector((0, 0, 1)))])

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        if is_cut:
            return "metal.5" if rng.random() < 0.25 else "metal.3"
        if f.normal.z > 0.8:
            return "stone.3"
        if c.z > tops[i] - rust[i]:  # rust running down from the top
            return "wood.3" if i % 3 else "accent.0"
        return "stone.1" if i % 2 else "stone.2"
    fractured(name, rng, whole, seeds, choose, stretch=(1, 1, 0.02), post=post, size=size,
              rubble=("stone.2", "stone.1", "stone.0"), out=out)


def iron_banded():
    """Iron B: an angular slab of banded iron: layers of deep red jasper and steel-grey hematite,
    weathered paler on top. The pieces break mostly along the layers."""
    reset()
    rng = random.Random(104)
    size = 1.1
    squash = (1.25, 1.0, 0.68)
    whole, cz = boulder_mesh(rng, size, subdiv=2, squash=squash, lumps=3, lump_amp=(0.05, 0.12), chops=8,
                             chop_depth=(0.75, 0.9))
    tilt = Vector((0.12, 0.05, 1)).normalized()
    slice_mesh(whole, layer_cuts(tilt, 0.13, -0.26, 1.6))
    seeds = shell_seeds(rng, size, squash, cz)

    def choose(f, is_cut, i):
        band = int((f.calc_center_median().dot(tilt) + 0.26) / 0.13) % 2
        if f.normal.z > 0.75 and not is_cut:
            return "stone.4"
        if is_cut:
            return "accent.1" if band == 0 else "metal.5"
        return "accent.0" if band == 0 else "metal.2"
    fractured("iron_banded", rng, whole, seeds, choose, stretch=(1, 1, 1.6), size=size,
              rubble=("accent.0", "metal.2", "stone.1"))


def coal_strata(name="coal_strata", out="designs"):
    """Coal A: a low, wide outcrop of layered rock: thick black coal seams between grey shale,
    and the pieces come away as slabs along the layers."""
    reset()
    rng = random.Random(105)
    squash = (1.35, 1.1, 0.6)
    whole, cz = boulder_mesh(rng, 1.0, squash=squash, lumps=4, lump_amp=(0.08, 0.16), chops=4)
    thick = [0.16, 0.07, 0.2, 0.08, 0.14, 0.07, 0.18, 0.08, 0.2]  # coal, shale, coal ... upward
    edges, z = [], -0.04
    for t in thick:
        z += t
        edges.append(z)
    slice_mesh(whole, [(Vector((0, 0, e)), Vector((0, 0, 1))) for e in edges])
    seeds = [Vector((0, 0, 0.12))]
    for level, (lz, n) in enumerate(((0.3, 4), (0.62, 4), (0.9, 3))):
        for k in range(n):
            a = k * math.tau / n + level * 0.7 + rng.uniform(-0.2, 0.2)
            seeds.append(Vector((math.cos(a) * 0.6, math.sin(a) * 0.5, lz)))

    def is_coal(height):
        return next((k for k, e in enumerate(edges) if height < e), len(edges)) % 2 == 0

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        coal = is_coal(c.z)
        if is_cut:
            return ("neutral.2" if rng.random() < 0.25 else "ore.coal") if coal else "stone.4"
        if f.normal.z > 0.75:
            return "neutral.2" if coal else "stone.4"
        if coal:
            return "ore.coal" if f.normal.z > -0.3 else "neutral.0"
        return "stone.3" if f.normal.z > -0.3 else "stone.2"
    fractured(name, rng, whole, seeds, choose, stretch=(1, 1, 3.0),
              rubble=("neutral.2", "ore.coal", "neutral.0"), out=out)


def coal_lump():
    """Coal B: one big glossy lump of coal, all sharp facets: black, with bright glints where the
    light catches a face, and a little grey stone clinging to its base."""
    reset()
    rng = random.Random(106)
    squash = (1.15, 1.05, 0.8)
    whole, cz = boulder_mesh(rng, 1.0, subdiv=2, squash=squash, lumps=3, lump_amp=(0.1, 0.2), chops=10,
                             chop_depth=(0.7, 0.88), noise=0.08)
    seeds = shell_seeds(rng, 1.0, squash, cz)

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        if is_cut:
            return "neutral.3" if rng.random() < 0.12 else "neutral.1"
        if c.z < 0.18:
            return "stone.2"
        if f.normal.z > 0.55:
            return "neutral.4" if rng.random() < 0.15 else "neutral.2"
        return "ore.coal" if f.normal.z > -0.2 else "neutral.0"
    fractured("coal_lump", rng, whole, seeds, choose, rubble=("neutral.2", "ore.coal", "neutral.0"))


def gold_quartz():
    """Gold A: a milky-white quartz boulder threaded with thin gold veins, gold flecks scattered
    either side of them; the broken faces are clear white quartz with the veins running through."""
    reset()
    rng = random.Random(107)
    size = 0.95
    squash = (1.15, 1.05, 0.75)
    whole, cz = boulder_mesh(rng, size, squash=squash, chops=5, lump_amp=(0.12, 0.22))
    centre = Vector((0, 0, cz))
    veins = [(Vector((0.8, 0.3, 0.5)).normalized(), centre, 0.045),
             (Vector((-0.4, 0.9, 0.2)).normalized(), centre + Vector((0.2, 0.1, 0)), 0.035)]
    slice_mesh(whole, band_cuts(veins))
    halo = [(n, p, w * 3.0) for n, p, w in veins]
    seeds = shell_seeds(rng, size, squash, cz)

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        if near_plane(c, veins):
            return "ore.gold" if is_cut or f.normal.z > 0.0 else "accent.2"
        if near_plane(c, halo) and rng.random() < 0.3:
            return "ore.gold"
        if is_cut:
            return "neutral.7" if rng.random() < 0.7 else "neutral.6"
        if f.normal.z > 0.55:
            return "neutral.6"
        return "neutral.5" if f.normal.z > -0.3 else "stone.4"
    fractured("gold_quartz", rng, whole, seeds, choose, size=size, rubble=("neutral.6", "neutral.5", "stone.4"))


def gold_geode():
    """Gold B: a dull, rough brown boulder you would walk past, until a piece splits off and the
    inside glitters: a rim of white quartz, then gold crystal all the way in."""
    reset()
    rng = random.Random(108)
    size = 0.95
    squash = (1.1, 1.05, 0.8)
    whole, cz = boulder_mesh(rng, size, squash=squash, chops=2, lump_amp=(0.15, 0.25), noise=0.07)
    seeds = shell_seeds(rng, size, squash, cz)
    centre = Vector((0, 0, cz))
    stone = shade_by_normal("wood.3", "wood.2", "stone.1", rng, side_alt="stone.2")

    def post(bm, i, cut):  # break the big cut faces up, so the rim and the crystal read
        bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if any(f[cut] for f in e.link_faces)],
                                  cuts=2, use_grid_fill=True)

    def choose(f, is_cut, i):
        if not is_cut:
            return stone(f)
        depth = (f.calc_center_median() - centre).length / size
        if depth > 0.7:
            return "neutral.6"
        return "accent.3" if rng.random() < 0.35 else "ore.gold"
    fractured("gold_geode", rng, whole, seeds, choose, post=post, size=size, rubble=("wood.3", "wood.2", "stone.1"))


def gold_veined(name="gold_veined", out="designs"):
    """Gold (the pick): the geode, with a few thin gold veins on the outside so it can still be
    spotted from a distance. Dull brown outside, a quartz rim and gold crystal within."""
    reset()
    rng = random.Random(109)
    size = 0.95
    squash = (1.1, 1.05, 0.8)
    whole, cz = boulder_mesh(rng, size, squash=squash, chops=3, lump_amp=(0.15, 0.25), noise=0.06)
    centre = Vector((0, 0, cz))
    veins = [(Vector((0.7, 0.3, 0.65)).normalized(), centre + Vector((0.1, 0, 0)), 0.03),
             (Vector((-0.5, 0.85, 0.15)).normalized(), centre + Vector((0, 0.15, 0.05)), 0.025),
             (Vector((0.2, -0.6, 0.8)).normalized(), centre + Vector((-0.2, -0.1, 0.1)), 0.02)]
    slice_mesh(whole, band_cuts(veins))
    seeds = shell_seeds(rng, size, squash, cz)
    stone = shade_by_normal("wood.3", "wood.2", "stone.1", rng, side_alt="stone.2")

    def post(bm, i, cut):  # break the big cut faces up, so the rim and the crystal read
        bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if any(f[cut] for f in e.link_faces)],
                                  cuts=2, use_grid_fill=True)

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        if not is_cut:
            if near_plane(c, veins):
                return "ore.gold" if f.normal.z > -0.2 else "accent.2"
            return stone(f)
        if (c - centre).length / size > 0.7:
            return "neutral.6"
        return "accent.3" if rng.random() < 0.35 else "ore.gold"
    fractured(name, rng, whole, seeds, choose, post=post, size=size, rubble=("wood.3", "wood.2", "stone.1"), out=out)


def designs():
    os.makedirs(os.path.join(OUT_DIR, "designs"), exist_ok=True)
    for build in (copper_verdigris, copper_malachite, iron_columns, iron_banded,
                  coal_strata, coal_lump, gold_quartz, gold_geode, gold_veined):
        build()


def scale_scene(s):
    """Scales everything built so far about the origin (applied on export)."""
    for obj in bpy.data.objects:
        obj.location *= s
        obj.scale *= s


# The game's rocks: the ore designs picked for each (see "ore designs" above).

def rock():
    """Copper (Mining 1): the verdigris boulder."""
    copper_verdigris("rock", out="")


def iron_rock():
    """Iron (Mining 15): basalt columns."""
    iron_columns("iron_rock", out="")


def coal_rock():
    """Coal (Mining 20): coal seams between shale."""
    coal_strata("coal_rock", out="")


def gold_rock():
    """Gold (Mining 30): the veined geode."""
    gold_veined("gold_rock", out="")


def shard(rng, length, radius):
    """A six-sided crystal: a column ending in a point, base at the origin's -length/2."""
    bm = prism(6, radius, radius * 0.12, length)
    jitter(bm, 0.06, rng)
    paint(bm, lambda f: "ore.amethyst" if f.normal.z > 0.2 or rng.random() < 0.7 else "accent.6")
    return bm


def tilted(base, length, tilt, azimuth):
    """Centre of a column standing on `base`, leaning `tilt` out toward `azimuth` (Euler (0, tilt,
    azimuth) turns +Z into this direction)."""
    d = (math.sin(tilt) * math.cos(azimuth), math.sin(tilt) * math.sin(azimuth), math.cos(tilt))
    return tuple(b + c * length / 2 for b, c in zip(base, d))


def crystal_rock():
    """A dark stone base bristling with violet crystals (Mining 40): the crystals are the chunks
    that break off, the base stays, two stubs are left while it grows back. Each crystal is cut
    off flush where it comes out of the stone, and that cut is its seam: a ring round its foot, so
    the crack runs round the base of the crystal and finishing it snaps the crystal off."""
    reset()
    rng = random.Random(15)
    bm = blob(0.5, rng, squash=(1.15, 1.0, 0.5))
    paint(bm, shade_by_normal("stone.2", "stone.1", "stone.0", rng, side_alt="neutral.2"))
    stone = bm.copy()  # where the crystals come out of it (world space)
    bmesh.ops.translate(stone, vec=Vector((0, 0, 0.18)), verts=stone.verts)
    surface = BVHTree.FromBMesh(stone)
    make_object("Body_Core", bm, (0, 0, 0.18))
    shards = [  # (length, radius, tilt, azimuth)
        (1.15, 0.16, 0.12, 0.0), (0.85, 0.13, 0.55, 0.4), (0.75, 0.12, 0.6, 2.2),
        (0.9, 0.13, 0.5, 3.6), (0.6, 0.1, 0.75, 5.0),
    ]
    for i, (length, radius, tilt, a) in enumerate(shards):
        base = (math.cos(a) * 0.16 * (i > 0), math.sin(a) * 0.16 * (i > 0), 0.3)
        axis = Vector((math.sin(tilt) * math.cos(a), math.sin(tilt) * math.sin(a), math.cos(tilt)))
        hit = surface.ray_cast(Vector(base), axis)  # from inside the stone, out along the crystal
        buried = (hit[3] if hit[0] is not None else 0.0) + 0.01
        piece = prism(6, radius, radius * 0.12, length)
        jitter(piece, 0.06, rng)
        cut = piece.faces.layers.int.new("cut")
        chop(piece, Vector((0, 0, -length / 2 + buried)), Vector((0, 0, -1)), as_cut=True)
        paint(piece, lambda f, cut=cut: "accent.7" if f[cut] else
              ("ore.amethyst" if f.normal.z > 0.2 or rng.random() < 0.7 else "accent.6"))
        where, turn = tilted(base, length, tilt, a), (0, tilt, a)
        mark_cut(piece, cut)
        make_object(f"Seam_{'ABCDE'[i]}", outline(piece, cut), where, turn)
        make_object(f"Chunk_{'ABCDE'[i]}", piece, where, turn)
    stone.free()
    for i, (a, length) in enumerate(((1.2, 0.22), (4.2, 0.18))):
        base = (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.28)
        make_object(f"Rubble_{i}", shard(rng, length, 0.09), tilted(base, length, 0.4, a), (0, 0.4, a))
    scale_scene(1.5)  # as hefty as the boulders
    export("crystal_rock", loose_edges=True)


def crystal_item():
    reset()
    rng = random.Random(39)
    bm = blob(0.09, rng, jitter_amount=0.25, squash=(1.2, 1.0, 0.5))
    paint(bm, shade_by_normal("stone.3", "stone.2", "stone.1", rng))
    make_object("Base", bm, (0, 0, -0.02))
    for i, (length, tilt, a) in enumerate(((0.26, 0.15, 0.5), (0.2, 0.7, 2.6), (0.17, 0.75, 4.6))):
        base = (math.cos(a) * 0.04 * (i > 0), math.sin(a) * 0.04 * (i > 0), 0.0)
        make_object(f"Shard{i}", shard(rng, length, 0.045), tilted(base, length, tilt, a), (0, tilt, a))
    merge_all("Item")
    export(os.path.join("items", "crystal"))


# --- quarry props (scenes/biomes/quarry.tscn) -------------------------------------------------

def plank(name, size, loc, rng, rot=(0, 0, 0), shades=("wood.5", "wood.4", "wood.3", "wood.4")):
    bm = box(size)
    jitter(bm, 0.03, rng)
    paint(bm, shade_by_normal(shades[0], shades[1], shades[2], rng, side_alt=shades[3]))
    return make_object(name, bm, loc, rot)


def scaffold(name, seed, height, width=3.0, depth=1.6):
    """Timber scaffolding with a plank deck `height` up: posts, a cross brace, a toe board.
    Its whole box is solid in the game, so the deck is a step to mantle onto."""
    reset()
    rng = random.Random(seed)
    for x in (-width / 2 + 0.1, width / 2 - 0.1):
        for y in (-depth / 2 + 0.1, depth / 2 - 0.1):
            plank("Post", (0.14, 0.14, height), (x, y, height / 2), rng, shades=("wood.3", "wood.2", "wood.1", "wood.3"))
    for i in range(5):
        plank(f"Deck{i}", (width, depth / 5 - 0.02, 0.07), (0, -depth / 2 + depth / 10 + i * depth / 5, height - 0.035),
              rng, (0, 0, rng.uniform(-0.02, 0.02)))
    brace = math.atan2(height - 0.4, width - 0.3)
    plank("Brace", (math.hypot(width - 0.3, height - 0.4), 0.08, 0.1), (0, depth / 2 - 0.05, height / 2), rng,
          (0, -brace, 0), shades=("wood.3", "wood.3", "wood.2", "wood.2"))
    plank("ToeBoard", (width, 0.05, 0.18), (0, -depth / 2 + 0.03, height + 0.09), rng)
    merge_all("Scaffold")
    export(os.path.join("quarry", name))


def ladder(name="ladder", length=5.6, lean=0.22):
    """Two rails and rungs, leaning back `lean` radians (set against a wall). Just for looks."""
    reset()
    rng = random.Random(70)
    up = (0, math.sin(lean), math.cos(lean))
    for x in (-0.25, 0.25):
        plank("Rail", (0.08, 0.08, length), (x, up[1] * length / 2, up[2] * length / 2), rng, (-lean, 0, 0),
              shades=("wood.4", "wood.3", "wood.2", "wood.3"))
    for i in range(int(length / 0.35)):
        d = 0.3 + i * 0.35
        plank(f"Rung{i}", (0.5, 0.05, 0.05), (0, up[1] * d, up[2] * d), rng, (-lean, 0, 0))
    merge_all("Ladder")
    export(os.path.join("quarry", name))


def crane():
    """A timber derrick on the rim: an A-frame, a boom reaching out over the pit (-Y), a rope
    and a stone bucket hanging off its end, a winch drum and counterweight stones."""
    reset()
    rng = random.Random(71)
    wood = ("wood.3", "wood.2", "wood.1", "wood.3")
    plank("Base", (3.0, 2.4, 0.3), (0, 1.0, 0.15), rng, shades=wood)
    for x in (-1.1, 1.1):
        plank("Leg", (0.22, 0.22, 6.2), (x * 0.55, 0.6, 3.0), rng, (0, x * 0.17, 0), shades=wood)
    plank("BackLeg", (0.2, 0.2, 6.4), (0, 1.9, 3.0), rng, (-0.42, 0, 0), shades=wood)
    plank("Cap", (0.6, 0.6, 0.4), (0, 0.6, 6.0), rng, shades=wood)
    boom = 0.35  # rises toward its tip
    length = 7.5
    plank("Boom", (0.2, length, 0.2), (0, 0.6 - math.cos(boom) * length / 2, 5.9 + math.sin(boom) * length / 2), rng,
          (boom, 0, 0), shades=wood)
    tip = (0, 0.6 - math.cos(boom) * length, 5.9 + math.sin(boom) * length)
    rope = tip[2] - 2.0
    plank("Rope", (0.04, 0.04, rope), (0, tip[1], tip[2] - rope / 2), rng, shades=("wood.6",) * 4)
    bucket = prism(8, 0.45, 0.55, 0.6)
    paint(bucket, shade_by_normal("stone.3", "metal.2", "metal.1", rng, side_alt="metal.3"))
    make_object("Bucket", bucket, (0, tip[1], 1.7))
    for i, x in enumerate((-0.25, 0.25)):
        drum = prism(10, 0.3, 0.3, 0.5)
        paint(drum, shade_by_normal("wood.5", "wood.4", "wood.3", rng))
        make_object(f"Drum{i}", drum, (x * 3.6, 1.0, 0.75), (0, math.pi / 2, 0))
    for i in range(3):
        bm = blob(0.42, rng, jitter_amount=0.25, squash=(1.1, 1.0, 0.7))
        paint(bm, shade_by_normal("stone.5", "stone.4", "stone.2", rng))
        make_object(f"Weight{i}", bm, (-0.7 + i * 0.7, 1.9, 0.55))
    merge_all("Crane")
    export(os.path.join("quarry", "crane"))


def quarry_rubble():
    """Scenery: a little spill of pale broken stone, one merged mesh."""
    reset()
    rng = random.Random(72)
    for i in range(6):
        r = rng.uniform(0.1, 0.28)
        bm = blob(r, rng, jitter_amount=0.35, squash=(1.2, 1.0, 0.6), subdiv=0)
        paint(bm, shade_by_normal("stone.6", "stone.5", "stone.3", rng, side_alt="stone.4"))
        a, d = rng.uniform(0, math.tau), rng.uniform(0, 0.5)
        make_object(f"Stone{i}", bm, (math.cos(a) * d, math.sin(a) * d, r * 0.3))
    merge_all("Rubble")
    export(os.path.join("scenery", "quarry_rubble"))


def quarry():
    crystal_rock()
    crystal_item()
    scaffold("scaffold_low", 73, 1.8)
    scaffold("scaffold_high", 74, 3.6)
    ladder()
    crane()
    quarry_rubble()


# --- farming: the sickle, sheaves, and Goldmeadow's props --------------------------------------

def sickle():
    """Short handle along +Z; a crescent blade curving forward (+Y) and up from its top."""
    reset()
    rng = random.Random(80)
    bm = box((0.036, 0.036, 0.26))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, 0.13))
    bm = box((0.05, 0.05, 0.035))
    paint(bm, lambda f: "metal.2")
    make_object("Ferrule", bm, (0, 0, 0.27))
    centre, r = (0.0, 0.13, 0.29), 0.13
    steps = 8
    for i in range(steps):  # from straight up out of the handle, round to pointing back down
        a0 = math.pi + i * (math.pi * 1.05) / steps
        a1 = math.pi + (i + 1) * (math.pi * 1.05) / steps
        p0 = (centre[1] + math.cos(a0) * r, centre[2] - math.sin(a0) * r)
        p1 = (centre[1] + math.cos(a1) * r, centre[2] - math.sin(a1) * r)
        length = math.dist(p0, p1) + 0.008
        width = 0.03 * (1.0 - i / steps * 0.7)  # tapering to the point
        bm = box((0.012, length, width))
        paint(bm, lambda f: "metal.7" if f.normal.z < -0.5 else ("metal.5" if abs(f.normal.x) > 0.5 else "metal.4"))
        angle = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        make_object(f"Blade{i}", bm, (0, (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2), (angle, 0, 0))
    block_hand("z", grip=0.12)
    export("sickle")


def stalks(rng, count, spread, height, stalk, ear, ear_size, droop=0.0, awns=None, thick=0.012):
    """Upright stalks with an ear on top. Returns the (stalk, ear) objects made. droop tips the
    ears over (barley); awns colours a few whiskers sticking up out of each ear."""
    made = []
    for i in range(count):
        a, d = rng.uniform(0, math.tau), math.sqrt(rng.random()) * spread
        x, y = math.cos(a) * d, math.sin(a) * d
        h = height * rng.uniform(0.85, 1.1)
        lean = (rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 0)
        bm = prism(3, thick, thick * 0.7, h)
        paint(bm, lambda f: stalk)
        made.append(make_object(f"Stalk{i}", bm, (x, y, h / 2), lean))
        bm = prism(4, ear_size * 0.3, ear_size * 0.12, ear_size)
        paint(bm, lambda f: ear[0] if f.normal.z > -0.2 and rng.random() < 0.6 else ear[1])
        tip = (lean[0] + droop, lean[1], rng.uniform(0, math.tau))
        made.append(make_object(f"Ear{i}", bm, (x + lean[1] * h, y - lean[0] * h, h + ear_size * 0.4), tip))
        if awns:
            bm = prism(3, 0.004, 0.001, ear_size * 1.2)
            paint(bm, lambda f: awns)
            made.append(make_object(f"Awn{i}", bm, (x + lean[1] * h, y - lean[0] * h, h + ear_size), tip))
    return made


def join_named(name, objs):
    """Joins `objs` into one mesh object called `name` (origin of the first)."""
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    bpy.context.view_layer.objects.active.name = name


def sheaf(name, seed, stalk, ear, ear_size, droop=0.0, awns=None):
    """A gatherable stand of grain (Farming): the stalks are the body, the ears break off in
    bunches as chunks, and what's left is stubble with the cut stalks lying flat. Each part is
    one mesh, so a field of them stays cheap to draw."""
    reset()
    rng = random.Random(seed)
    made = stalks(rng, 14, 0.32, 0.95, stalk, ear, ear_size, droop, awns)
    body = [o for o in made if o.name.startswith("Stalk")]
    ears = [o for o in made if not o.name.startswith("Stalk")]
    join_named("Body_Stalks", body)
    for k in range(4):  # the ears in four bunches, each one chunk
        join_named(f"Chunk_{'ABCD'[k]}", ears[k::4])
    rubble = []
    for i in range(10):  # stubble, and the cut stalks lying flat
        a, d = rng.uniform(0, math.tau), math.sqrt(rng.random()) * 0.32
        bm = prism(3, 0.012, 0.01, 0.08)
        paint(bm, lambda f: stalk)
        rubble.append(make_object(f"Stub{i}", bm, (math.cos(a) * d, math.sin(a) * d, 0.04)))
    for i in range(6):
        a = rng.uniform(-0.5, 0.5)
        bm = prism(3, 0.012, 0.008, 0.8)
        paint(bm, lambda f: stalk if rng.random() < 0.8 else ear[0])
        rubble.append(make_object(f"Lying{i}", bm, (rng.uniform(-0.2, 0.2), rng.uniform(-0.25, 0.25), 0.03),
                                  (math.pi / 2, 0, a)))
    join_named("Rubble_Straw", rubble)
    export(name)


def grain_item(name, seed, stalk, ear, ear_size, droop=0.0, awns=None):
    """A little tied bundle of stalks standing up, ears on top."""
    reset()
    rng = random.Random(seed)
    stalks(rng, 7, 0.035, 0.2, stalk, ear, ear_size * 0.75, droop * 0.6, awns, thick=0.018)
    bm = prism(8, 0.045, 0.045, 0.03)
    paint(bm, lambda f: "wood.3")
    make_object("Tie", bm, (0, 0, 0.08))
    merge_all("Item")
    export(os.path.join("items", name))


def wheat_clump():
    """Scenery: a clump of ripe wheat for the crop squares (not gatherable), one merged mesh."""
    reset()
    rng = random.Random(81)
    stalks(rng, 9, 0.45, 0.9, "terrain.sand", ("accent.3", "wood.6"), 0.12)
    merge_all("Wheat")
    export(os.path.join("scenery", "wheat_clump"))


WHEAT = dict(stalk="terrain.sand", ear=("accent.3", "wood.6"), ear_size=0.13)
BARLEY = dict(stalk="leaves.7", ear=("wood.7", "terrain.sand"), ear_size=0.11, droop=0.9, awns="wood.7")


def hay_round():
    """A round bale lying on its side, 1.3 m tall: a mantle step."""
    reset()
    rng = random.Random(82)
    bm = prism(12, 0.65, 0.65, 1.2)
    jitter(bm, 0.03, rng)
    paint(bm, lambda f: "wood.7" if abs(f.normal.z) > 0.9 else ("accent.3" if rng.random() < 0.3 else "terrain.sand"))
    make_object("Bale", bm, (0, 0, 0.65), (0, math.pi / 2, 0))
    for x in (-0.3, 0.3):
        bm = prism(12, 0.66, 0.66, 0.05)
        paint(bm, lambda f: "wood.3")
        make_object("Twine", bm, (x, 0, 0.65), (0, math.pi / 2, 0))
    merge_all("Hay")
    export(os.path.join("field", "hay_round"))


def hay_stack():
    """Square bales stacked in two steps: 0.9 m, then 1.8 m at the back."""
    reset()
    rng = random.Random(83)
    hay = lambda f: "wood.7" if abs(f.normal.y) > 0.9 else ("accent.3" if rng.random() < 0.25 else "terrain.sand")
    for i, (x, y, z) in enumerate(((-0.6, -0.5, 0.45), (0.6, -0.5, 0.45), (-0.6, 0.5, 0.45), (0.6, 0.5, 0.45),
                                   (-0.6, 0.5, 1.35), (0.6, 0.5, 1.35))):
        bm = box((1.15, 0.95, 0.88))
        jitter(bm, 0.03, rng)
        paint(bm, hay)
        make_object(f"Bale{i}", bm, (x, y, z), (0, 0, rng.uniform(-0.04, 0.04)))
    merge_all("Hay")
    export(os.path.join("field", "hay_stack"))


def fence():
    """A 3 m length of rail fence, 1 m tall: two posts, two rails, a bit of lean."""
    reset()
    rng = random.Random(84)
    wood = ("wood.4", "wood.3", "wood.2", "wood.3")
    for x in (-1.45, 1.45):
        plank("Post", (0.12, 0.12, 1.05), (x, 0, 0.52), rng, (0, rng.uniform(-0.05, 0.05), 0), shades=wood)
    for z in (0.45, 0.85):
        plank("Rail", (3.0, 0.07, 0.11), (0, 0, z), rng, (rng.uniform(-0.03, 0.03), rng.uniform(-0.02, 0.02), 0),
              shades=("wood.5", "wood.4", "wood.3", "wood.4"))
    merge_all("Fence")
    export(os.path.join("field", "fence"))


def cart():
    """A hay cart: plank bed with sides, two big wheels, shafts resting on the ground, a load."""
    reset()
    rng = random.Random(85)
    wood = ("wood.5", "wood.4", "wood.3", "wood.4")
    plank("Bed", (1.4, 2.4, 0.1), (0, 0, 0.85), rng, shades=wood)
    for x in (-0.7, 0.7):
        plank("Side", (0.06, 2.4, 0.4), (x, 0, 1.1), rng, shades=wood)
    for y in (-1.2, 1.2):
        plank("End", (1.4, 0.06, 0.4), (0, y, 1.1), rng, shades=wood)
    for x in (-0.82, 0.82):
        wheel = prism(10, 0.55, 0.55, 0.1)
        paint(wheel, shade_by_normal("wood.3", "wood.2", "wood.1", rng))
        make_object("Wheel", wheel, (x, 0.2, 0.55), (0, math.pi / 2, 0))
    for x in (-0.35, 0.35):
        plank("Shaft", (0.08, 2.0, 0.08), (x, -2.0, 0.45), rng, (-0.38, 0, 0), shades=wood)
    for i in range(4):
        bm = blob(0.42, rng, jitter_amount=0.25, squash=(1.2, 1.4, 0.6))
        paint(bm, lambda f: "accent.3" if rng.random() < 0.4 else "terrain.sand")
        make_object(f"Load{i}", bm, ((i % 2 - 0.5) * 0.6, (i // 2 - 0.5) * 1.0, 1.2))
    merge_all("Cart")
    export(os.path.join("field", "cart"))


def windmill():
    """Goldmeadow's landmark: a tapering eight-sided tower 11 m tall with a cap, and sails on an
    axle out of the front (-Y). Two objects: Tower, and Sails with its origin on the hub, so the
    game can turn it (scripts/windmill.gd)."""
    reset()
    rng = random.Random(86)
    bm = prism(8, 2.6, 1.7, 9.0)
    jitter(bm, 0.02, rng)
    paint(bm, shade_by_normal("neutral.6", "neutral.6", "neutral.4", rng, side_alt="neutral.5"))
    make_object("Body", bm, (0, 0, 4.5), (0, 0, math.pi / 8))
    for i, z in enumerate((0.15, 3.0, 6.0)):
        bm = prism(8, 2.65 - z * 0.1, 2.6 - z * 0.1, 0.25)
        paint(bm, lambda f: "wood.3")
        make_object(f"Band{i}", bm, (0, 0, z + 0.12), (0, 0, math.pi / 8))
    bm = prism(8, 2.1, 0.3, 2.4)
    paint(bm, shade_by_normal("wood.2", "wood.2", "wood.1", rng, side_alt="wood.3"))
    make_object("Cap", bm, (0, 0, 10.2), (0, 0, math.pi / 8))
    plank("Door", (1.0, 0.1, 1.9), (0, -2.55, 0.95), rng, (-0.19, 0, 0), shades=("wood.3", "wood.3", "wood.2", "wood.2"))
    for i, z in enumerate((4.0, 7.0)):
        plank(f"Window{i}", (0.6, 0.1, 0.7), (0, -2.42 + z * 0.09, z), rng, (-0.19, 0, 0),
              shades=("neutral.2", "neutral.2", "neutral.1", "neutral.2"))
    bm = prism(6, 0.2, 0.2, 1.2)
    paint(bm, lambda f: "wood.2")
    make_object("Axle", bm, (0, -1.8, 9.3), (math.pi / 2, 0, 0))
    merge_all("Tower")
    tower = bpy.context.view_layer.objects.active
    tower.select_set(False)
    # the sails, built round the hub at the origin, then moved out to the axle's end
    names = []
    for i in range(4):
        a = i * math.pi / 2
        arm = box((0.18, 0.12, 5.2))
        paint(arm, lambda f: "wood.3")
        names.append(make_object(f"Arm{i}", arm, (math.sin(a) * 2.7, 0, math.cos(a) * 2.7), (0, a, 0)))
        sail = box((1.5, 0.04, 4.0))
        paint(sail, lambda f: "neutral.7" if rng.random() < 0.8 else "neutral.6")
        off = 0.85
        names.append(make_object(f"Sail{i}", sail, (math.sin(a) * 3.2 + math.cos(a) * off, -0.05,
                                                    math.cos(a) * 3.2 - math.sin(a) * off), (0, a, 0)))
    hub = blob(0.35, rng, squash=(1, 1, 1))
    paint(hub, lambda f: "wood.2")
    names.append(make_object("Hub", hub))
    for o in bpy.context.scene.objects:
        o.select_set(o in names)
    bpy.context.view_layer.objects.active = names[-1]  # the hub: the joined mesh keeps its origin
    bpy.ops.object.join()
    sails = bpy.context.view_layer.objects.active
    sails.name = "Sails"
    sails.location = (0, -2.45, 9.3)
    export(os.path.join("field", "windmill"))


def farming():
    sickle()
    sheaf("wheat_sheaf", 87, **WHEAT)
    sheaf("barley_sheaf", 88, **BARLEY)
    grain_item("wheat", 89, **WHEAT)
    grain_item("barley", 90, **BARLEY)
    wheat_clump()
    hay_round()
    hay_stack()
    fence()
    cart()
    windmill()


# --- the ring road's obstacle course and time-trial gates (scripts/road_course.gd) -----------
# Across the road is X, along it is Y (the player runs toward +Y, Godot -Z), origin on the ground
# in the middle.

ROAD_WOOD = ("wood.5", "wood.4", "wood.3", "wood.4")


def log_pile():
    """Three logs across the road, 0.8 m high: hop it without breaking the chain."""
    reset()
    rng = random.Random(100)
    for i, (x, z) in enumerate(((0, 0.22), (0, 0.22), (0, 0.6))):
        y = (-0.23, 0.23, 0.0)[i]
        bm = prism(8, 0.22, 0.22, 4.0)
        jitter(bm, 0.03, rng)
        paint(bm, lambda f: "wood.6" if abs(f.normal.z) > 0.9 else ("wood.2" if rng.random() < 0.5 else "wood.3"))
        make_object(f"Log{i}", bm, (x, y, z), (0, math.pi / 2, rng.uniform(0, 0.4)))
    merge_all("Logs")
    export(os.path.join("road", "log_pile"))


def low_wall():
    """A dry-stone wall 4 m long and 1.1 m high: jump it or slide-cancel over."""
    reset()
    rng = random.Random(101)
    for course, z in enumerate((0.28, 0.83)):
        for i in range(4):
            x = -1.5 + i + (0.25 if course else 0) - (0.12 if i == 3 and course else 0)
            w = 0.98 if not (course and i == 3) else 0.72
            bm = box((w, 0.5, 0.54))
            jitter(bm, 0.05, rng)
            paint(bm, shade_by_normal("stone.5", "stone.4", "stone.2", rng, side_alt="stone.3"))
            make_object(f"Stone{course}{i}", bm, (x, 0, z))
    merge_all("Wall")
    export(os.path.join("road", "low_wall"))


def crate_stack(name, seed, levels):
    """Crates 1.9 m square, `levels` of them stacked 1 m each: a step, or a mantle at 2."""
    reset()
    rng = random.Random(seed)
    for k in range(levels):
        plank(f"Crate{k}", (1.9, 1.9, 0.98), (0, 0, 0.5 + k), rng, (0, 0, rng.uniform(-0.05, 0.05)), shades=ROAD_WOOD)
        for y in (-0.96, 0.96):
            plank(f"Slat{k}{y}", (1.95, 0.04, 0.12), (0, y, 0.5 + k), rng, shades=("wood.3",) * 4)
    merge_all("Crates")
    export(os.path.join("road", name))


def wallrun_panel():
    """A timber wall 11 m long and 3 m tall beside the road: one full wall run."""
    reset()
    rng = random.Random(102)
    for i in range(5):
        plank(f"Post{i}", (0.24, 0.24, 3.2), (0, -5.5 + i * 2.75, 1.6), rng, shades=("wood.3", "wood.2", "wood.1", "wood.2"))
    for i in range(6):
        plank(f"Board{i}", (0.16, 11.0, 0.48), (0, 0, 0.3 + i * 0.5), rng,
              (rng.uniform(-0.01, 0.01), 0, 0), shades=("wood.5", "wood.5", "wood.4", "wood.6" if i % 2 else "wood.4"))
    merge_all("Panel")
    export(os.path.join("road", "wallrun_panel"))


def kicker():
    """A plank ramp 2 m wide rising 0.8 m over 2.6 m toward +Y: launch into a dash or long jump."""
    reset()
    rng = random.Random(103)
    bm = box((2.0, 2.6, 0.8))
    for v in bm.verts:
        if v.co.y < 0 and v.co.z > 0:
            v.co.z = -0.4  # the low end meets the ground
    paint(bm, shade_by_normal("wood.5", "wood.4", "wood.3", rng, side_alt="wood.3"))
    make_object("Ramp", bm, (0, 0, 0.4))
    for i in range(5):
        plank(f"Batten{i}", (2.0, 0.08, 0.04), (0, -1.0 + i * 0.55, 0.06 + (i * 0.55) * 0.8 / 2.6 + 0.04), rng,
              (math.atan2(0.8, 2.6), 0, 0), shades=("wood.3",) * 4)
    merge_all("Kicker")
    export(os.path.join("road", "kicker"))


def low_beam():
    """A log on two posts across the road, 1.1 m clear underneath: slide under it."""
    reset()
    rng = random.Random(104)
    for x in (-2.1, 2.1):
        plank(f"Post{x}", (0.22, 0.22, 1.6), (x, 0, 0.8), rng, shades=("wood.3", "wood.2", "wood.1", "wood.2"))
    bm = prism(8, 0.16, 0.16, 4.6)
    paint(bm, lambda f: "wood.6" if abs(f.normal.z) > 0.9 else ("wood.2" if rng.random() < 0.5 else "wood.3"))
    make_object("Beam", bm, (0, 0, 1.26), (0, math.pi / 2, 0))
    merge_all("Beam")
    export(os.path.join("road", "low_beam"))


def bridge():
    """A plank deck over the gully's earth bridge, with a rail on its outer (+X) side only, so
    you can still leap off the open side across the gap."""
    reset()
    rng = random.Random(105)
    for i in range(14):
        plank(f"Plank{i}", (6.2, 0.48, 0.1), (0, -3.25 + i * 0.5, 0.05), rng, (0, 0, rng.uniform(-0.01, 0.01)),
              shades=ROAD_WOOD)
    for i in range(4):
        plank(f"RailPost{i}", (0.14, 0.14, 1.1), (3.0, -3.2 + i * 2.13, 0.55), rng, shades=("wood.3",) * 4)
    plank("Rail", (0.1, 6.8, 0.12), (3.0, 0, 1.05), rng, shades=("wood.4",) * 4)
    merge_all("Bridge")
    export(os.path.join("road", "bridge"))


def gate():
    """The time trial's start and finish: two tall posts and a cross beam over the road, and three
    medal banners (BannerBronze, BannerSilver, BannerGold) the game shows as you earn them."""
    reset()
    rng = random.Random(106)
    for x in (-5.0, 5.0):
        plank(f"Post{x}", (0.4, 0.4, 5.6), (x, 0, 2.8), rng, shades=("wood.3", "wood.2", "wood.1", "wood.2"))
        for i in range(4):  # chequered start bands
            plank(f"Band{x}{i}", (0.44, 0.44, 0.3), (x, 0, 3.2 + i * 0.3), rng,
                  shades=(("neutral.7",) if i % 2 else ("neutral.1",)) * 4)
    plank("Beam", (10.8, 0.4, 0.45), (0, 0, 5.4), rng, shades=("wood.3", "wood.2", "wood.1", "wood.2"))
    plank("Board", (3.2, 0.1, 0.9), (0, -0.25, 5.0), rng, shades=("wood.6", "wood.6", "wood.5", "wood.6"))
    for i in range(6):  # a chequer strip on the board
        plank(f"Check{i}", (0.45, 0.02, 0.3), (-1.25 + i * 0.5, -0.31, 5.0 + (0.15 if i % 2 else -0.15)), rng,
              shades=("neutral.1",) * 4)
    merge_all("Frame")
    bpy.context.view_layer.objects.active.select_set(False)
    for name, x, colour in (("BannerBronze", -3.2, "accent.2"), ("BannerSilver", 0.0, "metal.6"),
                            ("BannerGold", 3.2, "accent.3")):
        bm = box((1.3, 0.05, 1.6))
        for v in bm.verts:  # a swallowtail notch at the bottom
            if v.co.z < 0 and abs(v.co.x) < 0.1:
                v.co.z += 0.25
        paint(bm, lambda f, c=colour: c)
        make_object(name, bm, (x, 0.0, 4.25))
    export(os.path.join("road", "gate"))


def checkpoint():
    """A checkpoint arch: two posts and a rope of pennants (Flags, lit up when it's next)."""
    reset()
    rng = random.Random(107)
    for x in (-4.6, 4.6):
        plank(f"Post{x}", (0.26, 0.26, 4.2), (x, 0, 2.1), rng, shades=("wood.3", "wood.2", "wood.1", "wood.2"))
    plank("Rope", (9.2, 0.04, 0.04), (0, 0, 3.95), rng, shades=("wood.6",) * 4)
    merge_all("Frame")
    bpy.context.view_layer.objects.active.select_set(False)
    flags = []
    for i in range(9):
        bm = bmesh.new()
        verts = [bm.verts.new(v) for v in ((-0.22, 0, 0), (0.22, 0, 0), (0, 0, -0.5))]
        bm.faces.new(verts)
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.03)
        paint(bm, lambda f, c=("accent.4", "accent.3", "accent.1")[i % 3]: c)
        flags.append(make_object(f"Flag{i}", bm, (-4.0 + i * 1.0, 0, 3.93)))
    join_named("Flags", flags)
    export(os.path.join("road", "checkpoint"))


def road():
    log_pile()
    low_wall()
    crate_stack("crate_low", 108, 1)
    crate_stack("crate_high", 109, 2)
    wallrun_panel()
    kicker()
    low_beam()
    bridge()
    gate()
    checkpoint()


# The starter tree's canopy: (radius, jitter, squash, location, rotation) per blob.
TREE_CANOPY = [
    (1.25, 0.2, (1.0, 1.0, 0.72), (0, 0, 3.5), (0, 0, 0.4)),
    (0.85, 0.22, (1.0, 1.0, 0.8), (0.15, -0.1, 4.45), (0, 0, 1.1)),
]


def tree(name="tree", seed=7, trunk=(0.24, 0.15, 3.2), bark=("wood.5", "wood.3", "wood.2", "wood.2"),
         leaf_shades=("leaves.5", "leaves.3", "leaves.1", "leaves.4"), canopy=TREE_CANOPY,
         slab=("wood.3", "wood.1", "wood.1", "wood.0"), slab_size=(0.34, 0.2), stump=(0.28, 0.23)):
    """Six-sided tapered trunk, lumpy canopy blobs, bark slabs that chip off, a stump.
    The default is the starter tree; oak() is a stouter, darker, wider one.
    slab_size: (width, distance from the trunk's centre) of the bark slabs."""
    reset()
    rng = random.Random(seed)
    r_bottom, r_top, height = trunk

    bm = prism(6, r_bottom, r_top, height)
    jitter(bm, 0.06, rng)
    paint(bm, shade_by_normal(bark[0], bark[1], bark[2], rng, side_alt=bark[3]))
    make_object("Body_Trunk", bm, (0, 0, height / 2))

    leaves = shade_by_normal(leaf_shades[0], leaf_shades[1], leaf_shades[2], rng, side_alt=leaf_shades[3])
    names = ["Body_Canopy", "Body_CanopyTop"] + [f"Body_Canopy{i}" for i in range(2, len(canopy))]
    for (radius, jit, squash, loc, rot), obj_name in zip(canopy, names):
        bm = blob(radius, rng, jitter_amount=jit, squash=squash)
        paint(bm, leaves)
        make_object(obj_name, bm, loc, rot)

    # bark slabs hugging the trunk at chopping height, one per side the axe can come from
    width, dist = slab_size
    for i in range(4):
        a = i * math.tau / 4 + 0.3
        bm = box((width, 0.07, 0.3))
        jitter(bm, 0.12, rng)
        paint(bm, shade_by_normal(slab[0], slab[1], slab[2], rng, side_alt=slab[3]))
        loc = (math.cos(a) * dist, math.sin(a) * dist, 1.3)
        make_object(f"Chunk_Bark{i}", bm, loc, (0, 0, a + math.pi / 2))

    bm = prism(6, stump[0], stump[1], 0.4)
    jitter(bm, 0.06, rng)
    paint(bm, lambda f: "wood.7" if f.normal.z > 0.9 else (bark[1] if rng.random() < 0.6 else bark[2]))
    make_object("Rubble_Stump", bm, (0, 0, 0.2))
    export(name)


def oak():
    """A stout oak (Woodcutting 15): thick dark trunk, one broad canopy of three dark blobs."""
    tree("oak", seed=8, trunk=(0.36, 0.24, 2.8), bark=("wood.3", "wood.1", "wood.0", "wood.2"),
         leaf_shades=("leaves.3", "leaves.2", "leaves.0", "leaves.1"),
         canopy=[
             (1.55, 0.2, (1.15, 1.1, 0.62), (0, 0, 3.2), (0, 0, 0.3)),
             (1.05, 0.22, (1.0, 1.0, 0.7), (0.95, 0.35, 3.55), (0, 0, 1.0)),
             (1.0, 0.22, (1.0, 1.0, 0.7), (-0.85, -0.45, 3.65), (0, 0, 2.2)),
         ],
         slab=("wood.2", "wood.0", "wood.0", "wood.1"), slab_size=(0.48, 0.3), stump=(0.4, 0.34))


def block_hand(along="z", grip=0.16):
    """A blocky fist gripping the tool `grip` metres up its handle (choked up, so it's in view in
    first person), with a sleeve cuff below it. `along` is the axis the handle runs along ("z" for
    the axe / pickaxe, "y" for the spear)."""
    skin, sleeve = "wood.7", "accent.4"
    parts = [  # (name, size along (x, across, handle), offset (x, across, handle), colour)
        ("HandFist", (0.085, 0.095, 0.1), (0.0, -0.012, grip), skin),
        ("HandThumb", (0.03, 0.035, 0.05), (0.035, -0.045, grip + 0.04), "wood.6"),
        ("HandCuff", (0.1, 0.11, 0.08), (0.0, -0.015, grip - 0.09), sleeve),
    ]
    for name, (sx, sa, sh), (ox, oa, oh), color in parts:
        if along == "z":
            make_object(name, _painted(box((sx, sa, sh)), color), (ox, oa, oh))
        else:  # handle along y: swap the across / along axes
            make_object(name, _painted(box((sx, sh, sa)), color), (ox, oh, oa))


def _painted(bm, color):
    paint(bm, lambda f: color)
    return bm


def birch():
    """A slim white birch with a light, airy canopy (Woodcutting 8)."""
    tree("birch", seed=9, trunk=(0.17, 0.11, 3.4), bark=("neutral.7", "neutral.6", "neutral.5", "neutral.1"),
         leaf_shades=("leaves.7", "leaves.6", "leaves.4", "leaves.5"),
         canopy=[
             (0.95, 0.22, (0.9, 0.9, 1.0), (0, 0, 3.6), (0, 0, 0.5)),
             (0.7, 0.24, (1.0, 1.0, 0.9), (0.3, -0.2, 4.4), (0, 0, 1.2)),
         ],
         slab=("neutral.6", "neutral.5", "neutral.5", "neutral.1"), slab_size=(0.26, 0.15), stump=(0.2, 0.17))


def pine():
    """A tall pine (Woodcutting 25): straight dark trunk, three stacked cones of needles."""
    reset()
    rng = random.Random(10)
    bm = prism(6, 0.3, 0.12, 5.0)
    jitter(bm, 0.05, rng)
    paint(bm, shade_by_normal("wood.3", "wood.1", "wood.0", rng, side_alt="wood.2"))
    make_object("Body_Trunk", bm, (0, 0, 2.5))
    needles = shade_by_normal("leaves.2", "leaves.1", "leaves.0", rng, side_alt="leaves.2")
    for i, (r, h, z) in enumerate(((1.7, 1.8, 2.6), (1.3, 1.6, 3.7), (0.85, 1.6, 4.8))):
        bm = prism(7, r, 0.05, h)
        jitter(bm, 0.08, rng)
        paint(bm, needles)
        make_object("Body_Canopy" if i == 0 else f"Body_Canopy{i}", bm, (0, 0, z), (0, 0, rng.uniform(0, math.tau)))
    for i in range(4):
        a = i * math.tau / 4 + 0.3
        bm = box((0.42, 0.07, 0.3))
        jitter(bm, 0.12, rng)
        paint(bm, shade_by_normal("wood.2", "wood.0", "wood.0", rng, side_alt="wood.1"))
        make_object(f"Chunk_Bark{i}", bm, (math.cos(a) * 0.25, math.sin(a) * 0.25, 1.3), (0, 0, a + math.pi / 2))
    bm = prism(6, 0.34, 0.3, 0.4)
    jitter(bm, 0.06, rng)
    paint(bm, lambda f: "wood.6" if f.normal.z > 0.9 else ("wood.1" if rng.random() < 0.6 else "wood.0"))
    make_object("Rubble_Stump", bm, (0, 0, 0.2))
    export("pine")


def pickaxe():
    """Handle along +Z from the grip (origin) up; head with two drooping spikes, along Y."""
    reset()
    rng = random.Random(3)
    bm = box((0.038, 0.038, 0.5))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, 0.21))
    bm = box((0.06, 0.075, 0.075))
    paint(bm, shade_by_normal("metal.4", "metal.3", "metal.2", rng))
    make_object("Collar", bm, (0, 0, 0.42))
    for side in (1, -1):  # +1 = forward (Godot -Z)
        bm = prism(4, 0.032, 0.006, 0.24)  # tapered spike along its own Z
        paint(bm, shade_by_normal("metal.6", "metal.4", "metal.3", rng, side_alt="metal.5"))
        # lay it along Y, pointing away from the collar, tip drooping 10 degrees
        make_object(f"Spike{'Front' if side > 0 else 'Back'}", bm, (0, side * 0.14, 0.405),
                    (-side * math.radians(90 + 10), 0, 0))
    block_hand("z")
    export("pickaxe")


def axe():
    """Handle along +Z; a fan-shaped blade sticking out forward (+Y) near the top."""
    reset()
    rng = random.Random(4)
    bm = box((0.038, 0.038, 0.5))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, 0.21))
    bm = box((0.03, 0.17, 0.11))
    for v in bm.verts:  # widen toward the cutting edge (far +Y end) and thin it to an edge
        if v.co.y > 0:
            v.co.z *= 1.7
            v.co.x *= 0.35
    edge = lambda f: "metal.7" if f.normal.y > 0.7 else ("metal.5" if abs(f.normal.x) > 0.5 else "metal.3")
    paint(bm, edge)
    make_object("Blade", bm, (0, 0.1, 0.38))
    block_hand("z")
    export("axe")


def spear():
    """Fishing spear pointing forward (+Y, Godot -Z) from the grip at the origin: wooden shaft,
    a dark binding wrap, and a barbed metal tip at about 1.2 m."""
    reset()
    rng = random.Random(5)
    bm = prism(6, 0.022, 0.02, 1.45)
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Shaft", bm, (0, 0.45, 0), (-math.pi / 2, 0, 0))  # from -0.27 to 1.18 along Y
    bm = prism(6, 0.027, 0.027, 0.08)
    paint(bm, lambda f: "wood.1")
    make_object("Wrap", bm, (0, 1.12, 0), (-math.pi / 2, 0, 0))
    bm = prism(4, 0.03, 0.002, 0.2)
    paint(bm, shade_by_normal("metal.7", "metal.5", "metal.4", rng, side_alt="metal.6"))
    make_object("Tip", bm, (0, 1.28, 0), (-math.pi / 2, 0, math.pi / 4))
    for side in (1, -1):  # two barbs angled back from the tip
        bm = prism(3, 0.012, 0.001, 0.08)
        paint(bm, lambda f: "metal.5")
        make_object(f"Barb{'L' if side > 0 else 'R'}", bm, (side * 0.03, 1.27, 0),
                    (-math.pi / 2 - math.radians(150), 0, side * math.radians(25)))
    block_hand("y", grip=0.42)
    export("spear")


# --- fish -------------------------------------------------------------------------------------
# One mesh per fish ("Fish"), head toward +Y (Godot -Z, forward), origin at the body centre, so
# the swim shader can wiggle it by distance along the body. Length in metres.

def fish_mesh(length, width, height, tail_taper=0.85, snout=1.0):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.5)
    half = length / 2.0
    for v in bm.verts:
        y = v.co.y  # -0.5 (tail) .. 0.5 (head)
        taper = 1.0 - tail_taper * max(-y * 2.0, 0.0) ** 1.5  # thin toward the tail
        if y > 0:
            taper *= 1.0 - (1.0 - snout) * (y * 2.0) ** 2      # pointy / flat snout
        v.co.x *= width * taper
        v.co.z *= height * taper
        v.co.y *= length
    # tail fin: a thin vertical fan behind the body; dorsal fin on top
    tail = [(0.0, -half * 0.92, 0.0), (0.0, -half - length * 0.22, height * 0.42),
            (0.0, -half - length * 0.16, 0.0), (0.0, -half - length * 0.22, -height * 0.42)]
    fin_tri(bm, tail[0], tail[1], tail[2])
    fin_tri(bm, tail[0], tail[2], tail[3])
    fin_tri(bm, (0.0, length * 0.12, height * 0.42), (0.0, -length * 0.12, height * 0.68),
            (0.0, -length * 0.2, height * 0.38))
    return bm


def fin_tri(bm, a, b, c):
    """A flat triangle visible from both sides (two faces, each with its own vertices)."""
    bm.faces.new([bm.verts.new(p) for p in (a, b, c)])
    bm.faces.new([bm.verts.new(p) for p in (c, b, a)])


def fish_painter(back, side, belly, fin, rng, bars=None, stripe=None, spots=None, length=1.0):
    def choose(f):
        c = f.calc_center_median()
        if abs(f.normal.x) > 0.95 and abs(c.x) < 0.002:  # the flat fins (they lie in the x = 0 plane)
            return fin
        if f.normal.z > 0.45:
            return back
        if f.normal.z < -0.45:
            return belly
        if bars and int((c.y / length + 0.5) * 6) % 2 == 1 and c.y > -length * 0.3:
            return bars  # perch: dark vertical bars
        if stripe and abs(c.z) < length * 0.03:
            return stripe  # trout: pink side stripe
        if spots and rng.random() < 0.3:
            return spots  # pike: pale spots
        return side
    return choose


def fish(name, length, width, height, painter, tail_taper=0.85, snout=1.0):
    reset()
    bm = fish_mesh(length, width, height, tail_taper, snout)
    paint(bm, painter)
    make_object("Fish", bm)
    export(os.path.join("fish", name))


def perch():
    rng = random.Random(21)
    fish("perch", 0.24, 0.07, 0.1, fish_painter("leaves.4", "leaves.6", "accent.3", "accent.2", rng,
                                                bars="leaves.1", length=0.24))


def trout():
    rng = random.Random(22)
    fish("trout", 0.34, 0.08, 0.1, fish_painter("leaves.1", "metal.6", "neutral.7", "leaves.2", rng,
                                                stripe="accent.7", length=0.34))


def pike():
    rng = random.Random(23)
    fish("pike", 0.7, 0.1, 0.11, fish_painter("leaves.2", "leaves.4", "wood.7", "leaves.3", rng,
                                              spots="accent.3", length=0.7), tail_taper=0.7, snout=0.55)


def arctic_char():
    """Deep-water fish of the lake: dark back, pale spots, a bright orange belly."""
    rng = random.Random(24)
    fish("char", 0.44, 0.09, 0.11, fish_painter("metal.1", "metal.3", "accent.2", "accent.1", rng,
                                               spots="neutral.6", length=0.44), tail_taper=0.8, snout=0.85)


# --- item models (for icons, later maybe for pickups) -----------------------------------------

def log_item():
    reset()
    rng = random.Random(31)
    bm = prism(6, 0.09, 0.085, 0.42)
    jitter(bm, 0.05, rng)
    paint(bm, lambda f: "wood.7" if abs(f.normal.z) > 0.9 else ("wood.3" if rng.random() < 0.6 else "wood.2"))
    make_object("Item", bm, rotation=(math.pi / 2, 0, 0.3))  # lying down
    export(os.path.join("items", "wood"))


def oak_item():
    reset()
    rng = random.Random(33)
    bm = prism(6, 0.12, 0.115, 0.38)
    jitter(bm, 0.05, rng)
    paint(bm, lambda f: "wood.7" if abs(f.normal.z) > 0.9 else ("wood.2" if rng.random() < 0.6 else "wood.1"))
    make_object("Item", bm, rotation=(math.pi / 2, 0, 0.3))  # lying down
    # a sprig of oak leaves on top, so it reads apart from an ordinary log
    for i, (x, y) in enumerate(((0.02, 0.02), (0.09, -0.04), (-0.05, -0.06))):
        bm = blob(0.05, rng, jitter_amount=0.15, squash=(1.4, 0.8, 0.3))
        paint(bm, lambda f: "leaves.5" if f.normal.z > 0 else "leaves.3")
        make_object(f"Leaf{i}", bm, (x, y, 0.13), (0, 0, i * 1.1))
    export(os.path.join("items", "oak"))


def iron_item():
    reset()
    rng = random.Random(34)
    bm = blob(0.14, rng, jitter_amount=0.3, squash=(1.0, 0.9, 0.8))
    paint(bm, lambda f: ("metal.7" if f.normal.z > 0.5 else ("ore.iron" if f.normal.z > -0.2 else "ore.iron_dark"))
          if rng.random() < 0.75 else ("stone.2" if f.normal.z > 0.3 else "stone.0"))
    make_object("Item", bm)
    export(os.path.join("items", "iron"))


def log_item_variant(name, seed, bark, end_grain, radius=0.09):
    reset()
    rng = random.Random(seed)
    bm = prism(6, radius, radius * 0.95, 0.42)
    jitter(bm, 0.05, rng)
    paint(bm, lambda f: end_grain if abs(f.normal.z) > 0.9 else (bark[0] if rng.random() < 0.6 else bark[1]))
    make_object("Item", bm, rotation=(math.pi / 2, 0, 0.3))  # lying down
    export(os.path.join("items", name))


def ore_item_variant(name, seed, ore, stone, ore_share):
    reset()
    rng = random.Random(seed)
    bm = blob(0.13, rng, jitter_amount=0.3, squash=(1.0, 0.9, 0.8))
    paint(bm, lambda f: (ore[0] if f.normal.z > 0.0 else ore[1]) if rng.random() < ore_share
          else (stone[0] if f.normal.z > 0.3 else stone[1]))
    make_object("Item", bm)
    export(os.path.join("items", name))


def more_items():
    log_item_variant("birch", 35, ("neutral.7", "neutral.5"), "wood.7", 0.08)
    log_item_variant("pine", 36, ("wood.1", "wood.2"), "wood.6", 0.1)
    ore_item_variant("coal", 37, ("ore.coal", "neutral.1"), ("stone.2", "stone.1"), 0.8)
    ore_item_variant("gold", 38, ("ore.gold", "accent.2"), ("stone.5", "stone.3"), 0.6)


def ore_item():
    reset()
    rng = random.Random(32)
    bm = blob(0.13, rng, jitter_amount=0.3, squash=(1.0, 0.9, 0.8))
    paint(bm, lambda f: ("ore.copper" if f.normal.z > 0.0 else "ore.copper_dark") if rng.random() < 0.55
          else ("stone.4" if f.normal.z > 0.3 else "stone.2"))
    make_object("Item", bm)
    export(os.path.join("items", "ore"))


# --- pond scenery -----------------------------------------------------------------------------

def reeds():
    """A clump of tapered reed blades with a few cattail heads. Origin at the base (on the bed)."""
    reset()
    rng = random.Random(41)
    for i in range(9):
        h = rng.uniform(0.9, 1.6)
        bm = prism(3, 0.018, 0.002, h)
        paint(bm, lambda f: "leaves.5" if rng.random() < 0.5 else "leaves.3")
        a, r = rng.uniform(0, math.tau), rng.uniform(0.0, 0.18)
        tilt = (rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), rng.uniform(0, math.tau))
        make_object(f"Blade{i}", bm, (math.cos(a) * r, math.sin(a) * r, h / 2), tilt)
        if i % 3 == 0:  # cattail head near the top
            bm = prism(6, 0.025, 0.025, 0.16)
            paint(bm, lambda f: "wood.2")
            make_object(f"Cattail{i}", bm, (math.cos(a) * r, math.sin(a) * r, h * 0.82), tilt)
    export(os.path.join("scenery", "reeds"))


def lily_pad():
    """A flat floating pad with a notch cut out; origin at its centre on the water line."""
    reset()
    rng = random.Random(42)
    bm = bmesh.new()
    centre = bm.verts.new((0, 0, 0.0))
    ring = []
    for i in range(10):
        a = (i / 10) * math.tau
        if i == 0:
            ring.append(bm.verts.new((0.04, 0.0, 0.0)))  # the notch, pulled in toward the centre
            continue
        r = 0.22 * rng.uniform(0.92, 1.05)
        ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0)))
    for i in range(len(ring)):
        if i == 0 or i == len(ring) - 1:
            continue  # leave the notch open
        bm.faces.new((centre, ring[i], ring[i + 1]))
    bm.faces.new((centre, ring[1], ring[0]))
    paint(bm, lambda f: "leaves.4" if rng.random() < 0.6 else "leaves.3")
    make_object("Pad", bm)
    export(os.path.join("scenery", "lily_pad"))


def lily_flower():
    """A lily pad with a small pink-white flower on it."""
    reset()
    rng = random.Random(43)
    bm = prism(8, 0.2, 0.2, 0.01)
    paint(bm, lambda f: "leaves.4")
    make_object("Pad", bm, (0, 0, 0.005))
    for i in range(6):
        a = i * math.tau / 6
        bm = prism(3, 0.03, 0.002, 0.09)
        paint(bm, lambda f: "neutral.7" if rng.random() < 0.6 else "accent.7")
        make_object(f"Petal{i}", bm, (math.cos(a) * 0.03, math.sin(a) * 0.03, 0.04),
                    (math.cos(a + math.pi / 2) * 0.7, math.sin(a + math.pi / 2) * 0.7, 0))
    bm = blob(0.025, rng, jitter_amount=0.1)
    paint(bm, lambda f: "accent.3")
    make_object("Heart", bm, (0, 0, 0.04))
    export(os.path.join("scenery", "lily_flower"))


def shore_stone():
    reset()
    rng = random.Random(44)
    bm = blob(0.28, rng, jitter_amount=0.28, squash=(1.2, 1.0, 0.55))
    paint(bm, shade_by_normal("stone.5", "stone.3", "stone.2", rng, side_alt="terrain.moss"))  # a little moss
    make_object("Stone", bm, (0, 0, 0.06))
    export(os.path.join("scenery", "shore_stone"))


# --- terrain scenery (scattered by scripts/scenery_scatter.gd with MultiMesh) -----------------
# Each is ONE merged mesh with its origin at the base (MultiMesh draws a single mesh), so the
# sway shader can lean it by height above the origin.

def merge_all(name):
    """Joins every mesh object in the scene into one called `name`, origin at the world origin."""
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def grass_tuft():
    reset()
    rng = random.Random(51)
    for i in range(7):
        h = rng.uniform(0.25, 0.5)
        bm = prism(3, 0.03, 0.002, h)
        shade = rng.choice(["leaves.4", "leaves.5", "leaves.6"])
        paint(bm, lambda f, shade=shade: shade)
        a, r = rng.uniform(0, math.tau), rng.uniform(0.0, 0.12)
        tilt = (rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), rng.uniform(0, math.tau))
        make_object(f"Blade{i}", bm, (math.cos(a) * r, math.sin(a) * r, h / 2), tilt)
    merge_all("Tuft")
    export(os.path.join("scenery", "grass_tuft"))


def flowers(name, seed, petals):
    reset()
    rng = random.Random(seed)
    for i in range(4):
        h = rng.uniform(0.22, 0.38)
        a, r = rng.uniform(0, math.tau), rng.uniform(0.03, 0.14)
        x, y = math.cos(a) * r, math.sin(a) * r
        bm = prism(3, 0.012, 0.006, h)
        paint(bm, lambda f: "leaves.3")
        make_object(f"Stem{i}", bm, (x, y, h / 2))
        bm = blob(0.04, rng, jitter_amount=0.2, squash=(1.0, 1.0, 0.6), subdiv=1)
        c = petals[i % len(petals)]
        paint(bm, lambda f, c=c: "accent.3" if f.normal.z > 0.85 else c)
        make_object(f"Head{i}", bm, (x, y, h))
    for i in range(3):  # a few leaves at the base
        bm = prism(3, 0.03, 0.002, 0.18)
        paint(bm, lambda f: "leaves.4")
        make_object(f"Leaf{i}", bm, (0, 0, 0.08), (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), rng.uniform(0, math.tau)))
    merge_all("Flowers")
    export(os.path.join("scenery", name))


def bush(name, seed, blobs, shades):
    reset()
    rng = random.Random(seed)
    for i, (loc, r) in enumerate(blobs):
        bm = blob(r, rng, jitter_amount=0.22, squash=(1.0, 1.0, 0.8))
        paint(bm, shade_by_normal(shades[0], shades[1], shades[2], rng, side_alt=shades[3]))
        make_object(f"Blob{i}", bm, loc)
    merge_all("Bush")
    export(os.path.join("scenery", name))


def boulder(name, seed, size, squash):
    reset()
    rng = random.Random(seed)
    bm = blob(size, rng, jitter_amount=0.25, squash=squash, subdiv=1)
    paint(bm, shade_by_normal("stone.4", "stone.3", "stone.1", rng, side_alt="terrain.moss"))
    make_object("Boulder", bm, (0, 0, size * squash[2] * 0.6))  # sunk a little into the ground
    merge_all("Boulder")
    export(os.path.join("scenery", name))


# --- forest scenery: the Pinewood's canopy and floor (not gatherable) --------------------------

def canopy_pine(name, seed, height, cones, needles):
    """A background pine: like pine() but taller, darker and one merged mesh. cones: (radius,
    height, z) per cone of needles, bottom up; needles: (top, side, bottom, side_alt) swatches."""
    reset()
    rng = random.Random(seed)
    bm = prism(6, 0.32, 0.1, height)
    jitter(bm, 0.05, rng)
    paint(bm, shade_by_normal("wood.2", "wood.1", "wood.0", rng, side_alt="wood.2"))
    make_object("Trunk", bm, (0, 0, height / 2))
    for i, (r, h, z) in enumerate(cones):
        bm = prism(7, r, 0.05, h)
        jitter(bm, 0.09, rng)
        paint(bm, shade_by_normal(needles[0], needles[1], needles[2], rng, side_alt=needles[3]))
        make_object(f"Cone{i}", bm, (0, 0, z), (0, 0, rng.uniform(0, math.tau)))
    merge_all("Pine")
    export(os.path.join("scenery", name))


def canopy_birch():
    """A background birch: pale trunk, airy canopy of three blobs, one merged mesh."""
    reset()
    rng = random.Random(61)
    bm = prism(6, 0.16, 0.1, 4.2)
    jitter(bm, 0.06, rng)
    paint(bm, shade_by_normal("neutral.6", "neutral.5", "neutral.4", rng, side_alt="neutral.1"))
    make_object("Trunk", bm, (0, 0, 2.1))
    leaves = shade_by_normal("leaves.5", "leaves.4", "leaves.2", rng, side_alt="leaves.3")
    for i, (r, loc) in enumerate(((1.0, (0, 0, 4.0)), (0.75, (0.35, -0.2, 4.8)), (0.7, (-0.4, 0.3, 4.5)))):
        bm = blob(r, rng, jitter_amount=0.22, squash=(0.95, 0.95, 1.0))
        paint(bm, leaves)
        make_object(f"Canopy{i}", bm, loc)
    merge_all("Birch")
    export(os.path.join("scenery", "canopy_birch"))


def fern():
    """A low fan of fronds: flat tapering blades arching out from the middle."""
    reset()
    rng = random.Random(62)
    for i in range(7):
        a = i * math.tau / 7 + rng.uniform(-0.2, 0.2)
        length = rng.uniform(0.45, 0.65)
        bm = prism(3, 0.09, 0.005, length)
        bmesh.ops.scale(bm, vec=Vector((1.0, 0.25, 1.0)), verts=bm.verts)  # flatten into a frond
        shade = rng.choice(["leaves.3", "leaves.4", "leaves.2"])
        paint(bm, lambda f, shade=shade: shade)
        tilt = rng.uniform(0.9, 1.2)  # lean out from upright
        reach = math.sin(tilt) * length / 2
        make_object(f"Frond{i}", bm, (math.cos(a) * reach, math.sin(a) * reach, math.cos(tilt) * length / 2 + 0.04),
                    (0, tilt, a))
    merge_all("Fern")
    export(os.path.join("scenery", "fern"))


def mushrooms():
    """A little cluster of red-capped toadstools on pale stems."""
    reset()
    rng = random.Random(63)
    for i in range(4):
        h = rng.uniform(0.07, 0.16)
        a, r = rng.uniform(0, math.tau), rng.uniform(0.0, 0.12)
        x, y = math.cos(a) * r, math.sin(a) * r
        bm = prism(5, 0.018, 0.014, h)
        paint(bm, lambda f: "neutral.6")
        make_object(f"Stem{i}", bm, (x, y, h / 2))
        cap = rng.uniform(0.04, 0.07)
        bm = blob(cap, rng, jitter_amount=0.15, squash=(1.0, 1.0, 0.55), subdiv=1)
        c = "accent.0" if i % 3 else "wood.5"
        paint(bm, lambda f, c=c: c if f.normal.z > -0.2 else "neutral.5")
        make_object(f"Cap{i}", bm, (x, y, h + cap * 0.2))
    merge_all("Mushrooms")
    export(os.path.join("scenery", "mushrooms"))


def forest():
    canopy_pine("canopy_pine", 60, 6.5, ((2.1, 2.2, 2.9), (1.65, 2.0, 4.3), (1.15, 1.9, 5.7), (0.6, 1.4, 6.9)),
                ("leaves.1", "leaves.0", "leaves.0", "leaves.1"))
    canopy_pine("canopy_pine_young", 64, 3.6, ((1.3, 1.6, 1.7), (0.95, 1.4, 2.7), (0.55, 1.2, 3.6)),
                ("leaves.2", "leaves.1", "leaves.0", "leaves.2"))
    canopy_birch()
    fern()
    mushrooms()


# --- ruins: the parkour blocks in the clearing ------------------------------------------------
# Each fills exactly the box its collision uses (Godot size x, y, z = width, height, depth), centred
# on the origin, so step / ledge / mantle heights stay what they were with the greybox boxes.

def stone_block(name, size, seed, cap=False):
    """Courses of chunky stone bricks filling a box; staggered joints, a little moss on top."""
    reset()
    rng = random.Random(seed)
    w, h, d = size  # Godot x, y, z  ->  Blender x, z, y
    courses = max(1, round(h / 0.28))
    ch = h / courses
    for c in range(courses):
        z = -h / 2 + (c + 0.5) * ch
        along_x = w >= d
        length, across = (w, d) if along_x else (d, w)
        rows = max(1, round(across / 1.1))
        for r in range(rows):
            a0 = -across / 2 + r * across / rows
            pos = -length / 2
            first = True
            while pos < length / 2 - 0.05:
                bl = rng.uniform(0.45, 0.9) * (0.5 if first and c % 2 else 1.0)
                first = False
                bl = min(bl, length / 2 - pos)
                if length / 2 - (pos + bl) < 0.25:
                    bl = length / 2 - pos  # no sliver at the end
                inset = rng.uniform(0.0, 0.03)
                bw, bd, bh = bl - 0.03 - inset, across / rows - 0.03 - inset, ch - 0.025
                centre_l, centre_a = pos + bl / 2, a0 + across / rows / 2
                bm = box((bw, bd, bh) if along_x else (bd, bw, bh))
                for v in bm.verts:  # rough, but only ever inward, so it stays inside the collision box
                    v.co *= 1.0 - rng.uniform(0.0, 0.06)
                top_course = c == courses - 1
                stone = shade_by_normal("terrain.moss" if top_course and rng.random() < 0.35 else "stone.5",
                                        rng.choice(["stone.3", "stone.4"]), "stone.2", rng, side_alt="stone.3")
                paint(bm, stone)
                loc = (centre_l, centre_a, z) if along_x else (centre_a, centre_l, z)
                make_object(f"Brick{c}_{r}_{round(pos * 100)}", bm, loc)
                pos += bl
    if cap:  # a slab on top of a pillar
        bm = box((w + 0.12, d + 0.12, 0.14))
        paint(bm, shade_by_normal("stone.5", "stone.4", "stone.2", rng))
        make_object("Cap", bm, (0, 0, h / 2 - 0.07))
    export(os.path.join("ruins", name))


def plank_ramp(name, size, seed):
    """Planks across two long beams, filling the ramp's box."""
    reset()
    rng = random.Random(seed)
    w, h, d = size
    for x in (-w / 2 + 0.3, w / 2 - 0.3):
        bm = box((0.26, d - 0.04, h * 0.55))
        paint(bm, shade_by_normal("wood.3", "wood.2", "wood.1", rng))
        make_object(f"Beam{x:+.0f}", bm, (x, 0, -h / 2 + h * 0.275))
    n = int(d / 0.32)
    for i in range(n):
        bm = box((w - rng.uniform(0.0, 0.15), d / n - 0.03, h * 0.42))
        jitter(bm, 0.01, rng)
        paint(bm, shade_by_normal(rng.choice(["wood.5", "wood.6"]), "wood.4", "wood.3", rng))
        make_object(f"Plank{i:02d}", bm, (rng.uniform(-0.04, 0.04), -d / 2 + (i + 0.5) * d / n, h / 2 - h * 0.21))
    export(os.path.join("ruins", name))


def ruins():
    os.makedirs(os.path.join(OUT_DIR, "ruins"), exist_ok=True)
    stone_block("step_050", (1.5, 0.5, 1.5), 61)
    stone_block("step_100", (1.5, 1.0, 1.5), 62)
    stone_block("step_150", (1.5, 1.5, 1.5), 63)
    stone_block("ledge_120", (3.0, 1.2, 2.0), 64)
    stone_block("wall_250", (8.0, 2.5, 1.0), 65)
    stone_block("pillar", (1.0, 3.0, 1.0), 66, cap=True)
    plank_ramp("ramp", (3.0, 0.3, 7.0), 67)


def scenery():
    grass_tuft()
    flowers("flowers_warm", 52, ["accent.3", "accent.2", "neutral.7"])
    flowers("flowers_cool", 53, ["accent.7", "accent.6", "accent.5"])
    bush("bush_round", 54, [((0, 0, 0.35), 0.5), ((0.35, 0.15, 0.3), 0.38), ((-0.3, -0.2, 0.28), 0.36)],
         ("leaves.4", "leaves.3", "leaves.1", "leaves.2"))
    bush("bush_low", 55, [((0, 0, 0.22), 0.4), ((0.45, -0.1, 0.18), 0.32), ((-0.4, 0.2, 0.2), 0.34),
                          ((0.1, 0.4, 0.16), 0.28)],
         ("leaves.5", "leaves.4", "leaves.2", "leaves.3"))
    boulder("boulder_big", 56, 0.9, (1.2, 1.0, 0.75))
    boulder("boulder_flat", 57, 0.7, (1.4, 1.1, 0.5))


if __name__ == "__main__":  # make_village.py imports the helpers above without building these
    os.makedirs(os.path.join(OUT_DIR, "scenery"), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, "fish"), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, "items"), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, "quarry"), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, "field"), exist_ok=True)
    os.makedirs(os.path.join(OUT_DIR, "road"), exist_ok=True)
    builds = (rock, iron_rock, tree, oak, pickaxe, axe, spear, perch, trout, pike, log_item, ore_item,
              oak_item, iron_item, reeds, lily_pad, lily_flower, shore_stone, scenery, ruins,
              coal_rock, gold_rock, birch, pine, more_items, arctic_char, forest, quarry, farming, road)
    only = argv[2:]  # optional: names of the builders to run (e.g. `forest`), instead of all of them
    for build in builds:
        if not only or build.__name__ in only:
            build()
    for build in (designs,):  # only when asked for by name: candidates, not game models
        if build.__name__ in only:
            build()
