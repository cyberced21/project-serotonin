"""Generates the starter low-poly models as .glb files, using Blender's Python API.

Run headless from the project folder (Blender 4.2+ / 5.x):

    blender -b -P tools/blender/make_models.py -- models art/palette.json [builder ...]

Name builders (e.g. `forest`) to rebuild only those models.

Every model is built from a few primitives with jittered vertices, coloured by
pointing each face's UVs at a swatch of art/palette.png (looked up by name in palette.json).
Organic models (rocks, trees, plants, fish) are smooth-shaded at export (see SMOOTH); the rest
stay flat-shaded.
Object names follow the ResourceNode convention: Body_*, Chunk_*, Rubble_*.

These are starters to learn from: open a .glb in Blender (File > Import > glTF), tweak, and
export back over it (File > Export > glTF 2.0, format .glb). Re-running this script overwrites
them, so rename yours if you want to keep both.

Coordinates here are Blender's (Z up, -Y toward the viewer); the glTF exporter converts to
Godot's Y-up, so Blender +Y becomes Godot -Z (forward).
"""
import fnmatch
import json
import math
import os
import random
import sys
import types

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR = argv[0]
SWATCHES = json.load(open(argv[1]))["swatches"]
## How many variants the `variants` builder makes of each ore rock and choppable tree, and of the
## scenery (see variants()).
VARIANTS = 8
SCENERY_VARIANTS = 4
## The variants are spread over this many shape families (see recipe()): the model and variants
## 4 and 8 are family 0, as designed; variants 1 and 5 family 1, and so on. A procgen cluster
## takes its nodes from one family, so neighbours share their proportions.
FAMILIES = 4
_variant = 0  # 0 = the model itself; 1..VARIANTS while variants() is baking
_size = 1.0  # the whole model scaled by this on export (a recipe's "size")




# --- helpers ----------------------------------------------------------------------------------

def seeded(seed):
    """The random generator every model is built from. Its seed is the model's own, shifted while
    variants() bakes, so a variant is the same model drawn from a different seed."""
    return random.Random(seed + 7919 * _variant)


def recipe(seed, **ranges):
    """The shape of the model being built, by its family (see FAMILIES): each `ranges` entry is
    (low, as designed, high); family 0 takes the designed value, the others a draw between low and
    high that every variant in the family shares (its own seed, so the model's rng is untouched).
    A "size" entry also scales the whole model on export. Returns the values as attributes."""
    global _size
    family = _variant % FAMILIES
    rng = random.Random(seed * 131 + family * 7907)
    out = types.SimpleNamespace()
    for k, (lo, made, hi) in ranges.items():
        v = made if family == 0 else rng.uniform(lo, hi)
        setattr(out, k, round(v) if isinstance(made, int) else v)
    _size = getattr(out, "size", 1.0)
    return out


def reset():
    global _size
    _size = 1.0
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


## Smooth shading (Valheim-style: low-poly, but soft): models matching a pattern (fnmatch, on the
## name passed to export(), folders included) are smooth-shaded with edges sharper than the angle
## kept hard, so cut faces, seams and caps stay crisp. Everything else stays flat-shaded (crystals,
## tools, planks, buildings, props, items).
SMOOTH = [
    # ore rocks and boulders: soft outer faces, hard cut faces and seams
    ("rock", 50), ("iron_rock", 50), ("coal_rock", 50), ("gold_rock", 50),
    ("designs/copper_*", 50), ("designs/iron_*", 50), ("designs/coal_*", 50), ("designs/gold_*", 50),
    ("scenery/boulder_*", 50), ("scenery/shore_stone", 50), ("scenery/quarry_rubble", 45),
    # trees: round trunks and limbs, hard cut ends
    ("tree", 70), ("oak", 70), ("birch", 70), ("pine", 70), ("designs/tree_*", 70),
    ("designs/oak_*", 70), ("designs/birch_*", 70), ("designs/pine_*", 70), ("scenery/canopy_*", 70),
    # fish and plants
    ("fish/*", 60), ("scenery/bush_*", 60), ("scenery/fern", 60), ("scenery/mushrooms", 60),
    ("scenery/grass_tuft", 60), ("scenery/flowers_*", 60), ("scenery/reeds", 60),
    ("scenery/wheat_clump", 60), ("scenery/lily_pad", 60),
]


def smooth_angle(name):
    """The auto-smooth angle (degrees) for the model `name` (see SMOOTH), or None for flat."""
    key = name.replace(os.sep, "/")
    for pattern, angle in SMOOTH:
        if fnmatch.fnmatchcase(key, pattern):
            return angle
    return None


def auto_smooth(angle):
    """Smooth-shades every mesh in the scene, keeping edges sharper than `angle` degrees hard."""
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and len(obj.data.polygons) and not obj.data.has_custom_normals:
            obj.data.shade_smooth()
            obj.data.set_sharp_from_angle(angle=math.radians(angle))


def export(name, loose_edges=False):
    """Writes models/<name>.glb. With `loose_edges` (the breakable rocks), also the Seam_* lines and
    the "cut_mark" vertex colour (see mark_cut). Smooth-shades it first if SMOOTH says so."""
    angle = smooth_angle(name)
    if angle is not None:
        auto_smooth(angle)
    if _size != 1.0:
        scale_scene(_size)
    if _variant:  # a variant: models/variants/<name>_v<n>.glb, whatever folder the model lives in
        name = os.path.join("variants", f"{os.path.basename(name)}_v{_variant}")
    path = os.path.join(OUT_DIR, name + ".glb")
    colours = {"export_vertex_color": "NAME", "export_vertex_color_name": "cut_mark"} if loose_edges else {}
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                              export_apply=True, export_materials="NONE", use_mesh_edges=loose_edges, **colours)
    print("exported", path)


# --- leaf cards -------------------------------------------------------------------------------
# Valheim-style canopies: a solid, darker inner core with leaf cards round it, small quads that
# show a cut-out leaf cluster (art/textures/leaves.png, see tools/make_textures.py). A card's
# palette colour is in the first UV layer like every face; the second layer, "cards", holds the
# card's own 0..1 coordinates, offset by 1 + the leaves.png slice (CARD_BROADLEAF / CARD_NEEDLES),
# so faces with u >= 1 there are cards (node_foliage.gdshader cuts them out) and anything else
# (0, 0) is solid. Normals point out from the clump's centre, so the canopy lights softly as one.

CARD_BROADLEAF = 0
CARD_NEEDLES = 1


def leafy(bm, rng, shades, card_size, density, kind=CARD_BROADLEAF, core=(0.72, 0.72, 0.72), droop=0.0,
          open_bottom=False):
    """Turns a canopy shape into a darker core plus leaf cards spread over its surface.
    shades: (top, side, bottom, side_alt) swatches; density: cards per m² of the shape's surface;
    core: how far the shape shrinks (per axis) to become the core; droop: tilts cards downward
    (pine boughs); open_bottom: drops the core's flat underside (a pine tier, seen from below)."""
    bm.normal_update()
    faces = [(f.calc_area(), f.normal.copy(), [v.co.copy() for v in f.verts]) for f in bm.faces]
    total = sum(a for a, _, _ in faces)
    top_z = max(v.co.z for v in bm.verts)
    bottom_z = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co = Vector((v.co.x * core[0], v.co.y * core[1], v.co.z * core[2]))
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        f.smooth = True
        for loop in f.loops:
            loop[uv].uv = swatch_uv(shades[2])  # the core: the darkest leaves, seen through gaps
    cards = bm.loops.layers.uv.new("cards")
    weights = [a for a, _, _ in faces]
    if open_bottom:
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.9], context="FACES_ONLY")
    for _ in range(max(4, round(total * density))):
        _, n, pts = rng.choices(faces, weights)[0]
        # a random point on that face (fan triangles from its first corner)
        i = rng.randrange(1, len(pts) - 1)
        a, b = rng.random(), rng.random()
        if a + b > 1:
            a, b = 1 - a, 1 - b
        p = pts[0] + (pts[i] - pts[0]) * a + (pts[i + 1] - pts[0]) * b
        p += n * rng.uniform(-0.05, 0.12) * card_size
        rnd = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        facing = (n + rnd * 0.5 + Vector((0, 0, -droop))).normalized()
        t1 = facing.orthogonal().normalized()
        t1.rotate(Matrix.Rotation(rng.uniform(0, math.tau), 3, facing))
        t2 = facing.cross(t1)
        size = card_size * rng.uniform(0.75, 1.25)
        corners = [p + (t1 * sx + t2 * sy) * size * 0.5 for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        face = bm.faces.new([bm.verts.new(c) for c in corners])
        face.smooth = True
        h = (p.z - bottom_z) / max(top_z - bottom_z, 1e-6)
        if h > 0.7:
            swatch = shades[0]
        elif h > 0.25:
            swatch = shades[3] if rng.random() < 0.4 else shades[1]
        else:
            swatch = shades[1]
        for loop, (cu, cv) in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv].uv = swatch_uv(swatch)
            loop[cards].uv = (1 + kind + cu * 0.998, cv)
    return bm


def spherical_normals(obj, centre=(0, 0, 0), squash=(1, 1, 1)):
    """Points every normal of `obj` out from `centre` (object space; an ellipsoid's if squashed),
    so a leafy clump shades like one soft ball instead of a scatter of flat cards."""
    mesh = obj.data
    mesh.shade_smooth()
    c = Vector(centre)
    normals = []
    for loop in mesh.loops:
        d = mesh.vertices[loop.vertex_index].co - c
        d = Vector((d.x / squash[0] ** 2, d.y / squash[1] ** 2, d.z / squash[2] ** 2))
        normals.append(d.normalized() if d.length > 1e-6 else Vector((0, 0, 1)))
    mesh.normals_split_custom_set(normals)
    return obj


# --- models -----------------------------------------------------------------------------------

def voronoi_cell(src, seeds, index):
    """The part of the closed mesh `src` nearer seeds[index] than any other seed (one Voronoi
    cell), capped where it was cut. Cap faces get 1 in the int face layer "cut", and the index + 1
    of the seed across them in the int face layer "across" (so the cell's neighbours are the
    seeds named by the cut faces that survive)."""
    bm = src.copy()
    cut = bm.faces.layers.int.get("cut") or bm.faces.layers.int.new("cut")
    across = bm.faces.layers.int.get("across") or bm.faces.layers.int.new("across")
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
                f[across] = j + 1
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


# --- organic shaping ----------------------------------------------------------------------------
# Little in nature is ruler-straight: a rock's flat faces have rounded shoulders, its veins and
# strata wander, the breaks between its pieces bow a little, and a branch arches.

## How far a slice (see slice_mesh) wanders from its plane (m), and how tight the wander is (per m).
WAVE = (0.1, 1.4)
UP = Vector((0, 0, 1))


def fbm(p, octaves=2):
    """Smooth noise about 0 (about -1..1) at point `p`, a couple of octaves."""
    total, amp = 0.0, 1.0
    for _ in range(octaves):
        total += noise.noise(p) * amp
        p = p * 2.03
        amp *= 0.5
    return total / 1.5


def wave(c, n):
    """How far the wavy sheet of a slice with normal `n` sits from its plane at `c` (see WAVE).
    Parallel slices wander together, like folded strata."""
    return WAVE[0] * noise.noise(c * WAVE[1] + n * 5.3)


def soft_chop(bm, point, normal, soft):
    """Flattens the mesh on the `normal` side of the plane, as chop() cuts it, but with a rounded
    shoulder `soft` metres wide instead of a sharp edge: the vertices past the plane are pressed
    onto it, easing in (a smooth minimum). A weathered facet, not a saw cut."""
    n = normal.normalized()
    for v in bm.verts:
        d = (v.co - point).dot(n)
        h = max(soft - abs(d), 0.0) / soft
        v.co += n * (min(d, 0.0) - h * h * soft * 0.25 - d)


def smooth_blob(radius, rng, lumpy=0.22, squash=(1, 1, 0.75), subdiv=2):
    """blob(), lumpy rather than jagged: the surface swells and dips with smooth noise instead of
    every corner jittering on its own."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    for v in bm.verts:
        v.co *= 1.0 + lumpy * fbm(v.co.normalized() * 1.6 + off)
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2]))
    return bm


def warp(bm, amount, offset, scale=1.3):
    """Bends the whole mesh with a smooth field (the same everywhere for the same `offset`), so the
    pieces of one rock, warped alike, still fit together while their flat breaks bow."""
    for v in bm.verts:
        v.co += noise.noise_vector(v.co * scale + offset) * amount


def split_long_edges(bm, longest):
    """Adds vertices along edges longer than `longest` (m), so a warp can bend them. Decided by
    length alone, so two pieces sharing an edge split it alike."""
    for e in [e for e in bm.edges if e.calc_length() > longest]:
        bmesh.ops.bisect_edges(bm, edges=[e], cuts=int(e.calc_length() / longest))


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
    """rock()'s boulder, with the knobs exposed: an icosphere squashed, lumped, flattened in a few
    places (rounded facets, see soft_chop) and sat on the ground. `noise` swells and dips the
    surface smoothly. Returns (mesh, centre height)."""
    radius, centre_z = size, size * squash[2] * 0.72
    whole = bmesh.new()
    bmesh.ops.create_icosphere(whole, subdivisions=subdiv, radius=radius)
    bumps = [(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 1))).normalized(),
              rng.uniform(*lump_amp)) for _ in range(lumps)]
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    for v in whole.verts:
        d = v.co.normalized()
        v.co *= 1.0 + sum(amp * max(0.0, d.dot(l)) ** 2 for l, amp in bumps) + noise * 1.6 * fbm(d * 1.8 + off)
        v.co = Vector((v.co.x * squash[0], v.co.y * squash[1], v.co.z * squash[2] + centre_z))
    for _ in range(chops):
        a = rng.uniform(0, math.tau)
        n = Vector((math.cos(a), math.sin(a), rng.uniform(-0.1, 0.9))).normalized()
        soft_chop(whole, Vector((n.x * radius * squash[0], n.y * radius * squash[1],
                                 centre_z + n.z * radius * squash[2])) * rng.uniform(*chop_depth), n, 0.22 * size)
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


def shatter_seeds(rng, size, squash, centre_z, outer=30, inner=6):
    """Seeds for a rock that breaks where it's struck: `outer` spread evenly just under the
    surface (small pieces, the flakes), `inner` deep inside (the big slabs of the middle)."""
    def at(azimuth, elevation, k):
        return Vector((math.cos(elevation) * math.cos(azimuth) * size * squash[0] * k,
                       math.cos(elevation) * math.sin(azimuth) * size * squash[1] * k,
                       centre_z + math.sin(elevation) * size * squash[2] * k))
    seeds = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(outer):  # a Fibonacci spiral over the upper part of the shape: even, not gridded
        h = -0.15 + 1.1 * (i + 0.5) / outer
        seeds.append(at(i * golden + rng.uniform(-0.25, 0.25), math.asin(max(-1.0, min(1.0, h))),
                        rng.uniform(0.7, 0.86)))
    for i in range(inner):
        seeds.append(at(i * math.tau / inner + rng.uniform(-0.4, 0.4), rng.uniform(-0.1, 0.6), rng.uniform(0.15, 0.4)))
    return seeds


## Directions over a hemisphere round +Z (a spiral, denser toward the pole), for baking shade.
AO_RAYS = [(math.cos(i * 2.39996) * math.sqrt(1 - (0.1 + 0.85 * i / 11) ** 2),
            math.sin(i * 2.39996) * math.sqrt(1 - (0.1 + 0.85 * i / 11) ** 2),
            0.1 + 0.85 * i / 11) for i in range(12)]


## What the ground leaves on a rock's foot (multiplied in, like the moss): earthy and warm, so the
## rock comes up out of the soil instead of standing on it.
SOIL = (0.86, 0.72, 0.55)


def bake_weathering(bm, cut, bvh, top_z, moss=(0.55, 0.82, 0.42), moss_amount=0.85, reach=0.7, ground=0.0,
                    only=None, soil=0.0):
    """Weathered outside, fresh inside: writes the "cut_mark" colour (float, linear) of every
    face corner. Outside faces get a baked shade the rock shader multiplies in: crevices and the
    foot darker (rays against `bvh`, the whole rock, and the ground at z = 0), the top lighter,
    worn convex edges lighter, a little mottling, and moss patches low down and on ledges.
    Cut faces are (1, 1, 1) with alpha 0: the shader shows them clean and fresh, and the game
    tells them from the outside by that alpha. `ground`: the ground's height (None: no ground,
    for something placed anywhere); `only(face)`: bake just those faces, the rest stay white;
    `soil`: how much of a ragged band of SOIL the foot wears (0..1)."""
    layer = bm.loops.layers.float_color.get("cut_mark") or bm.loops.layers.float_color.new("cut_mark")
    bm.normal_update()
    shade = {}
    for v in bm.verts:
        outside = [f for f in v.link_faces if not f[cut] and (only is None or only(f))]
        if not outside:
            continue
        n = sum((f.normal for f in outside), Vector()).normalized()
        t = n.orthogonal().normalized()
        b = n.cross(t)
        o = v.co + n * 0.02
        occluded = 0
        for x, y, z in AO_RAYS:
            d = t * x + b * y + n * z
            if ground is not None and d.z < 0 and o.z + d.z * reach < ground:  # into the ground (half: it's bright open ground)
                occluded += 0.5
            elif bvh.ray_cast(o, d, reach)[0] is not None:
                occluded += 1
        ao = 1.0 - 0.65 * occluded / len(AO_RAYS)
        h = max(0.0, min(1.0, (v.co.z - (ground or 0.0)) / max(top_z - (ground or 0.0), 0.01)))
        convex, edges = 0.0, 0
        for e in v.link_edges:
            if not any(f[cut] for f in e.link_faces):
                convex -= (e.other_vert(v).co - v.co).normalized().dot(n)
                edges += 1
        wear = 1.0 + 0.6 * max(0.0, convex / edges if edges else 0.0)
        s = ao * (0.72 + 0.28 * h) * wear * (1.0 + 0.14 * noise.noise(v.co * 4.0))
        s = max(0.0, min(1.0, s))
        patch = noise.noise(v.co * 2.2 + Vector((7.0, 3.0, 1.0))) * 0.5 + 0.5
        low = 1.0 - max(0.0, min(1.0, (v.co.z - (ground or 0.0)) / 0.5))
        mossy = max(0.0, min(1.0, (low * 0.9 + max(0.0, n.z) * 0.45) * patch * 1.7 - 0.45)) * moss_amount
        foot = (v.co.z - (ground or 0.0)) / 0.3 + noise.noise(v.co * 3.1 + Vector((2.0, 9.0, 4.0))) * 0.45
        dirty = max(0.0, min(1.0, 1.0 - foot)) * soil * (1.0 - mossy * 0.5)
        shade[v] = tuple(s * (1.0 + (m - 1.0) * mossy) * (1.0 + (d - 1.0) * dirty) for m, d in zip(moss, SOIL)) + (1.0,)
    for f in bm.faces:
        for loop in f.loops:
            if f[cut]:
                loop[layer] = (1.0, 1.0, 1.0, 0.0)
            elif only is not None and not only(f):
                loop[layer] = (1.0, 1.0, 1.0, 1.0)
            else:
                loop[layer] = shade.get(loop.vert, (1.0, 1.0, 1.0, 1.0))


def swatch_names():
    """Palette UV (rounded) -> swatch name, to tell what a painted face is."""
    return {tuple(round(c, 4) for c in swatch_uv(n)): n for n in SWATCHES}


def weather_stonework(ground=0.0, moss_amount=0.5, prefix="stone."):
    """Weathers the stone of everything built so far, as bake_weathering does a rock: the faces
    painted a `prefix` swatch get dark joints where blocks meet (rays against the whole scene),
    worn edges and moss low down and on top; anything else (wood, cloth, metal) stays as it is.
    Export with loose_edges=True to keep it (the vertex colour). A building's upgrade tiers
    (objects named T<n>_..., all standing in one place) each cast shade only on themselves."""
    groups = {}
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and len(o.data.polygons):
            tier = o.name.split("_")[0] if o.name[:1] == "T" and o.name.split("_")[0][1:].isdigit() else ""
            groups.setdefault(tier, []).append(o)
    names = swatch_names()
    for objs in groups.values():
        _weather_group(objs, names, ground, moss_amount, prefix)


def _weather_group(objs, names, ground, moss_amount, prefix):
    verts, polys = [], []
    for o in objs:  # the whole group in world space, for the rays
        base = len(verts)
        verts += [o.matrix_world @ v.co for v in o.data.vertices]
        polys += [[base + i for i in p.vertices] for p in o.data.polygons]
    bvh = BVHTree.FromPolygons(verts, polys)
    top = max(v.z for v in verts)
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        uv = bm.loops.layers.uv.active
        if uv is None:
            bm.free()
            continue
        bm.transform(o.matrix_world)
        cut = bm.faces.layers.int.get("cut") or bm.faces.layers.int.new("cut")
        stony = lambda f: names.get(tuple(round(c, 4) for c in f.loops[0][uv].uv), "").startswith(prefix)
        bake_weathering(bm, cut, bvh, top, moss_amount=moss_amount, reach=0.5, ground=ground, only=stony)
        bm.transform(o.matrix_world.inverted())
        bm.to_mesh(o.data)
        bm.free()


def shattered(name, rng, whole, seeds, choose, rubble=("stone.4", "stone.2", "stone.1"), size=1.0, out="",
              stretch=None, post=None, ore_swatches=("ore.",), rules=None, moss_amount=0.85, body=None, bend=0.06):
    """Cuts `whole` into Voronoi pieces round `seeds`, all alike (no core): Chunk_NN, plus
    Rubble_*, weathered by bake_weathering. The game knocks pieces off where they're struck and
    drops whatever's left hanging, so it needs to know which pieces touch, and which carry ore
    (they spill some as they come out): models/<out>/<name>.pieces.json, {"links": piece ->
    its neighbours, "ore": [pieces]}, plus the ore's own breaking `rules` (see ResourceNode:
    "support" "below" = a piece rests only on pieces under it; "shatter_at"; "knock", extra
    neighbours a hit takes; "tough", pieces taking two hits; "grounded", pieces held up anyway).
    choose(face, is_cut, piece) picks each face's swatch; post(piece_mesh, piece, cut_layer)
    can reshape a piece; `stretch` scales the cells (see stretched_cell); `body`, a bmesh,
    becomes Body_Core, a part that never breaks (painted and weathered by the caller); `bend`, how
    far (m, per metre of `size`) the warp bows the pieces."""
    names = [f"Chunk_{i:02d}" for i in range(len(seeds))]
    links = {n: set() for n in names}
    ore_area = {}  # piece -> m² of ore faces
    # every piece is bent by the same field afterwards (see warp), so its flat breaks bow and the
    # outline wanders; the shade is baked against the rock as bent
    field = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    bent = whole.copy()
    warp(bent, bend * size, field)
    bvh = BVHTree.FromBMesh(bent)
    top_z = max(v.co.z for v in bent.verts)
    bent.free()
    for i in range(len(seeds)):
        bm = stretched_cell(whole, seeds, i, stretch) if stretch else voronoi_cell(whole, seeds, i)
        cut = bm.faces.layers.int.get("cut")
        across = bm.faces.layers.int.get("across")
        if post and bm.faces:
            post(bm, i, cut)
        if not bm.faces:
            continue
        split_long_edges(bm, 0.15 * size)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        for f in bm.faces:
            if f[cut] and f[across] > 0 and f.calc_area() > 1e-4:
                links[names[i]].add(names[f[across] - 1])
                links[names[f[across] - 1]].add(names[i])

        def pick(f, i=i, cut=cut):
            swatch = choose(f, f[cut] == 1, i)
            if swatch.startswith(ore_swatches):
                ore_area[names[i]] = ore_area.get(names[i], 0.0) + f.calc_area()
            return swatch
        paint(bm, pick)  # (before the warp: the veins are where they were sliced)
        warp(bm, bend * size, field)
        bake_weathering(bm, cut, bvh, top_z, moss_amount=moss_amount, soil=1.0)
        centre = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        bmesh.ops.translate(bm, vec=-centre, verts=bm.verts)
        make_object(names[i], bm, centre)
    whole.free()
    if body:
        warp(body, bend * size, field)
        make_object("Body_Core", body)
    for i in range(4):
        a = i * math.tau / 4 + rng.uniform(-0.4, 0.4)
        d = rng.uniform(0.2, 0.6) * size
        bm = smooth_blob(rng.uniform(0.3, 0.45) * size, rng, lumpy=0.3, squash=(1.2, 1.0, 0.4), subdiv=1)
        paint(bm, shade_by_normal(*rubble, rng))
        make_object(f"Rubble_{i}", bm, (math.cos(a) * d, math.sin(a) * d, 0.08 * size), (0, 0, rng.uniform(0, math.tau)))
    export_pieces(os.path.join(out, name) if out else name, links,
                  {n for n, a in ore_area.items() if a > 0.04}, rules)  # (ore: a real share of vein, not a sliver)


def export_pieces(name, links, ore, rules=None):
    """Exports the scene as models/<name>.glb (see export) plus <name>.pieces.json for a rock
    that breaks where it's struck: {"links": piece -> the pieces it touches, "ore": [pieces],
    and any `rules`} (see shattered), naming only pieces that were built."""
    export(name, loose_edges=True)
    if _variant:
        name = os.path.join("variants", f"{os.path.basename(name)}_v{_variant}")
    present = {o.name for o in bpy.context.scene.objects}
    data = {"links": {n: sorted(set(l) & present) for n, l in links.items() if n in present},
            "ore": sorted(set(ore) & present)}
    for k, v in (rules or {}).items():
        data[k] = sorted(set(v) & present) if isinstance(v, (set, list)) else v
    with open(os.path.join(OUT_DIR, name + ".pieces.json"), "w") as f:
        json.dump(data, f, indent=1)


def mirrored(s, n, p):
    """`s` reflected through the plane through `p` with normal `n`."""
    return s - 2.0 * (s - p).dot(n) * n


def near_plane(c, planes):
    """Whether a point is inside any of the bands (normal, point, half-width), as they wander (see
    wave)."""
    return any(abs((c - p).dot(n) - wave(c, n)) < w for n, p, w in planes)


def slice_mesh(bm, cuts):
    """Cuts the mesh's faces along each plane (point, normal) without removing anything, so a band
    or vein painted by face position gets crisp edges instead of ragged triangles. The cut follows
    the plane's wavy sheet (see wave): the mesh is pushed so the sheet lies flat, cut, and put back."""
    for p, n in cuts:
        before = {v: v.co.copy() for v in bm.verts}
        for v in bm.verts:
            v.co -= n * wave(v.co, n)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=p, plane_no=n)
        for v in bm.verts:
            if v in before:
                v.co = before[v]
            else:  # a new vertex on the cut: find where it came from (a few steps converge)
                w = v.co.copy()
                x = w.copy()
                for _ in range(4):
                    x = w + n * wave(x, n)
                v.co = x


def band_cuts(bands):
    """Both edges of every band (normal, point, half-width), for slice_mesh."""
    return [(p + n * w * side, n) for n, p, w in bands for side in (-1, 1)]


def ore_lenses(rng, bm, centre, count, width, reach):
    """Ore the way it shows in a real boulder: `count` short lenses (normal, middle, half-width,
    reach), instead of bands round the rock. Each is middled on the surface of `bm`, spread round
    the rock from `centre` so every side shows one, and stands across the surface so it breaks it
    as a streak; `width` (low, high) at its fattest, `reach` (low, high) metres out before it
    tapers to a point."""
    lenses = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(count):
        h = 0.75 - 0.9 * (i + 0.5) / count  # (the upper part and the sides, not underneath)
        a = i * golden + rng.uniform(-0.3, 0.3)
        out = Vector((math.cos(a) * math.sqrt(1 - h * h), math.sin(a) * math.sqrt(1 - h * h), h))
        p = max((v.co for v in bm.verts), key=lambda co: (co - centre).normalized().dot(out))
        n = out.orthogonal().normalized()
        n.rotate(Matrix.Rotation(rng.uniform(0, math.tau), 3, out))
        lenses.append((n, p - out * 0.05, rng.uniform(*width), rng.uniform(*reach)))
    return lenses


def lens_ratio(c, lenses, stretch=1.0):
    """How deep in an ore lens (see ore_lenses) a point is: its distance from the lens's wavy
    middle over the lens's width there, under 1 = inside. A lens is fattest in its middle, tapers
    to a point at its reach (`stretch` times it), and swells and narrows along the way."""
    best = math.inf
    for k, (n, p, w, reach) in enumerate(lenses):
        d = c - p
        across = d.dot(n)
        t = (d - n * across).length / (reach * stretch)
        if t >= 1.0:
            continue
        swell = 0.7 + 0.5 * noise.noise(c * 2.6 + Vector((k * 7.0, 3.0, 1.0)))
        best = min(best, abs(across - wave(c, n)) / max(w * (1.0 - t * t) * swell, 1e-4))
    return best


def snap_to_outline(bm, field, level, lo, hi):
    """Moves each vertex whose `field` value is between `lo` and `hi` onto the nearest point along
    its edges where the field crosses `level`, so faces painted by which side of `level` they're on
    meet in a smooth outline instead of a zigzag of triangles."""
    value = {v: field(v.co) for v in bm.verts}
    moves = {}
    for v, r in value.items():
        if not lo <= r <= hi:
            continue
        best = None
        for e in v.link_edges:
            u = e.other_vert(v)
            ru = value[u]
            if ru != math.inf and (r - level) * (ru - level) < 0:
                t = (level - r) / (ru - r)
                if best is None or t < best[0]:
                    best = (t, v.co.lerp(u.co, t))
        if best is not None and best[0] < 0.6:
            moves[v] = best[1]
    for v, co in moves.items():
        v.co = co


def snap_lenses(bm, lenses):
    """The outlines of the lenses and of their hearts (half their width) made smooth (see
    snap_to_outline)."""
    snap_to_outline(bm, lambda c: lens_ratio(c, lenses), 1.0, 0.75, 2.0)
    snap_to_outline(bm, lambda c: lens_ratio(c, lenses), 0.5, 0.0, 0.75)


def refine_near(bm, near, cuts=2):
    """Divides the faces `near(face)` picks `cuts` + 1 ways each side, so colour painted face by
    face there (ore) follows a curve instead of stepping in big triangles."""
    edges = {e for f in bm.faces if near(f) for e in f.edges}
    if edges:
        bmesh.ops.subdivide_edges(bm, edges=list(edges), cuts=cuts, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])


def layer_cuts(normal, spacing, lo, hi):
    """Parallel planes `spacing` apart along `normal`, from `lo` to `hi` (distances from the origin)."""
    return [(normal * (lo + k * spacing), normal) for k in range(int((hi - lo) / spacing) + 1)]


def copper_verdigris(name="copper_verdigris", out="designs", shatter=False):
    """Copper A: a rounded warm-grey boulder crusted with green verdigris on top, cut by two
    copper veins. The pieces are seeded in pairs mirrored across each vein, so the seams run along
    the veins: every split opens up a bright sheet of copper."""
    reset()
    rng = seeded(101)
    r = recipe(101, wide=(1.05, 1.2, 1.38), deep=(0.92, 1.05, 1.15), tall=(0.58, 0.72, 0.88),
               lumpy=(0.75, 1.0, 1.35), chops=(2, 3, 5), size=(0.9, 1.0, 1.15))
    squash = (r.wide, r.deep, r.tall)
    whole, cz = boulder_mesh(rng, 1.0, subdiv=4 if shatter else 3, squash=squash, chops=r.chops,
                             lump_amp=(0.15 * r.lumpy, 0.28 * r.lumpy))
    if shatter:  # sunk into the ground, not sat on it
        bmesh.ops.translate(whole, vec=Vector((0, 0, -0.06)), verts=whole.verts)
        cz -= 0.06
    centre = Vector((0, 0, cz))
    veins = [(Vector((1, 0.35, 0.25)).normalized(), centre + Vector((0.15, 0, 0)), 0.07),
             (Vector((-0.3, 1, -0.4)).normalized(), centre + Vector((0, -0.1, 0.1)), 0.06)]
    crust_z = cz + 0.38 * r.tall / 0.72  # verdigris above this, where rain and weather get at it
    if shatter:  # ore in lenses, not bands round the rock
        veins = ore_lenses(rng, whole, centre, 5, (0.05, 0.08), (0.35, 0.55))
        refine_near(whole, lambda f: lens_ratio(f.calc_center_median(), veins, 1.2) < 3.5, cuts=3)
        snap_lenses(whole, veins)
        slice_mesh(whole, [(Vector((0, 0, crust_z)), Vector((0, 0, 1)))])
    else:
        slice_mesh(whole, band_cuts(veins) + [(Vector((0, 0, crust_z)), Vector((0, 0, 1)))])
    seeds = [Vector((0, 0, cz * 0.7))]
    for n, p, *_ in veins:  # pairs either side of each vein
        for a in (0.6, 2.2):
            s = centre + Vector((math.cos(a) * 0.75, math.sin(a) * 0.65, rng.uniform(-0.05, 0.2)))
            s += n * (0.28 - (s - p).dot(n))  # a fixed distance on one side ...
            seeds += [s, mirrored(s, n, p)]  # ... and its twin on the other
    seeds += [centre + Vector((0.2, 0.25, 0.42)), centre + Vector((-0.35, -0.2, 0.38))]
    stone = shade_by_normal("stone.5", "stone.4", "stone.2", rng, side_alt="terrain.rock")

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        if shatter:  # lenses of copper weathered dark, green staining round them
            v = lens_ratio(c, veins, 1.6 if is_cut else 1.0)  # (a break opens a wider sheet of copper)
            if v < 1.0:
                return "ore.copper" if is_cut or (v < 0.5 and f.normal.z > 0.2) else "ore.copper_dark"
            if is_cut:
                return "stone.6"
            if v < 2.8 and noise.noise(c * 6.0 + Vector((3.0, 1.0, 2.0))) > -0.2:
                return "leaves.5"
        elif near_plane(c, veins):
            return "ore.copper" if is_cut or f.normal.z > 0.2 else "ore.copper_dark"
        if is_cut:
            return "stone.6"
        edge = crust_z + (0.14 * noise.noise(c * 2.5) if shatter else 0.0)  # (a ragged edge, not a line)
        if c.z > edge and f.normal.z > 0.2:
            return "leaves.6" if f.normal.z > 0.6 else "leaves.5"
        return stone(f)
    if shatter:
        shattered(name, rng, whole, shatter_seeds(rng, 1.0, squash, cz), choose, out=out)
    else:
        fractured(name, rng, whole, seeds, choose, out=out)


def copper_malachite():
    """Copper B: a dark stone boulder under a thick green malachite crust; inside it's banded in
    stripes of light and dark green, so every break shows the banding."""
    reset()
    rng = seeded(102)
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


def iron_columns(name="iron_columns", out="designs", shatter=False):
    """Iron A: a cluster of dark basalt columns of different heights (upright Voronoi cells of a
    tall prism, each with its own flat top), rust bleeding down from the tops; the faces a break
    opens glint with iron. With `shatter`, each column is jointed into stacked segments that rest
    on the one below: knock out a column's foot and the rest of it topples; and the columns are
    weathered: tops worn round, rust in streaks, set a little out of line."""
    reset()
    rng = seeded(103)
    r = recipe(103, tall=(0.8, 1.0, 1.25), spread=(0.88, 1.0, 1.15), size=(0.9, 1.0, 1.12))
    size = 1.1
    whole = prism(9, 1.15 * size, 1.05 * size, 2.0 * size * r.tall)
    bmesh.ops.translate(whole, vec=Vector((0, 0, 1.0 * size * r.tall - 0.04)), verts=whole.verts)
    for v in whole.verts:
        v.co.x *= (1.05 + rng.uniform(-0.04, 0.04)) * r.spread
        v.co.y *= (0.95 + rng.uniform(-0.04, 0.04)) * r.spread
    # finely divided, so the columns can swell and lean (the warp in shattered()) instead of
    # standing as ruled prisms
    bmesh.ops.subdivide_edges(whole, edges=whole.edges[:], cuts=8, use_grid_fill=True)
    bmesh.ops.triangulate(whole, faces=whole.faces[:])
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), 0.0))
    for v in whole.verts:
        k = 1.0 + 0.06 * fbm(Vector((v.co.x, v.co.y, v.co.z * 0.8)) * 1.2 + off)
        v.co.x *= k
        v.co.y *= k
    seeds = [Vector((0, 0, 0.5))]
    for k in range(6):  # a ring round the middle column ...
        a = k * math.tau / 6 + rng.uniform(-0.15, 0.15)
        k = rng.uniform(0.9, 1.12) if shatter else 1.0  # (not quite a ring: out of line)
        seeds.append(Vector((math.cos(a) * 0.52 * k, math.sin(a) * 0.48 * k, 0.5)) * Vector((r.spread, r.spread, 1)))
    for k in range(5):  # ... and an outer one
        a = k * math.tau / 5 + 0.3 + rng.uniform(-0.2, 0.2)
        k = rng.uniform(0.9, 1.08) if shatter else 1.0
        seeds.append(Vector((math.cos(a) * 1.0 * k, math.sin(a) * 0.92 * k, 0.5)) * Vector((r.spread, r.spread, 1)))
    tops = [size * 1.55] + [size * rng.uniform(1.05, 1.4) for _ in range(6)] + [size * rng.uniform(0.55, 0.95) for _ in range(5)]
    tops = [t * r.tall for t in tops]
    rust = [size * rng.uniform(0.2, 0.4) for _ in seeds]  # how far rust runs down each one
    if shatter:
        rust = [x * 1.4 for x in rust]  # (in streaks: further, but not all the way round)
        columns = seeds
        tilts = [Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), 1)).normalized() for _ in columns]
        seeds, column_of = [], []
        for c, (s, top) in enumerate(zip(columns, tops)):
            joints = max(1, round(top / (0.42 * size)))
            for k in range(joints):
                z = (k + 0.5 + rng.uniform(-0.15, 0.15)) * top / joints
                seeds.append(Vector((s.x, s.y, z)))
                column_of.append(c)
        whole.normal_update()

        def dome(c, p):
            """How far column c's worn top drops below its flat (tilted) top at p: more out
            toward its edges, and unevenly."""
            d2 = (p.x - columns[c].x) ** 2 + (p.y - columns[c].y) ** 2
            return 0.9 * d2 + 0.03 * noise.noise(Vector((p.x * 4.0, p.y * 4.0, c * 1.7)))

        def top_at(c, p):
            t = tilts[c]
            return tops[c] - (p.x * t.x + p.y * t.y) / t.z - dome(c, p)

        def domed_top(bm, c, cut):
            """Cuts the column off at its top, worn round (dome) rather than flat: the mesh is
            raised so the dome lies flat, cut, lowered again, and the cap pushed up into a dome."""
            for v in bm.verts:
                v.co.z += dome(c, v.co)
            res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                         plane_co=Vector((0, 0, tops[c])), plane_no=tilts[c], clear_outer=True)
            for v in bm.verts:
                v.co.z -= dome(c, v.co)
            edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge) and e.is_boundary]
            if not edges:
                return
            caps = bmesh.ops.holes_fill(bm, edges=edges, sides=0)["faces"]
            for f in caps:
                f[cut] = 0
            for _ in range(2):  # points inside the cap to round it
                res = bmesh.ops.poke(bm, faces=caps)
                for v in res["verts"]:
                    v.co.z = top_at(c, v.co)
                caps = res["faces"]

        def post_joint(bm, i, cut):
            c = column_of[i]
            domed_top(bm, c, cut)
            slice_mesh(bm, [(Vector((0, 0, tops[c] - rust[c])), Vector((0, 0, 1)))])
            # a side standing clear of a shorter neighbour column is weathered outside, not a break
            across = bm.faces.layers.int.get("across")
            for f in bm.faces:
                centre = f.calc_center_median()
                if f[cut] and f[across] > 0 and centre.z > top_at(column_of[f[across] - 1], centre) - 0.03:
                    f[cut] = 0
                    f[across] = 0

        def choose_joint(f, is_cut, i):
            c, centre = column_of[i], f.calc_center_median()
            if is_cut:
                return "metal.5" if rng.random() < 0.25 else "metal.3"
            if f.normal.z > 0.8:
                return "stone.3"
            # rust running down from the top, in streaks
            streak = noise.noise(Vector((centre.x * 5.0, centre.y * 5.0, c * 2.1)))
            if centre.z - wave(centre, UP) > tops[c] - rust[c] * (0.55 + 0.45 * streak):
                return "wood.3" if streak > -0.1 else "wood.2"
            return "stone.2" if c % 2 else "stone.3"
        shattered(name, rng, whole, seeds, choose_joint, stretch=(1, 1, 0.02), post=post_joint, size=size,
                  rubble=("stone.2", "stone.1", "stone.0"), out=out, ore_swatches=("metal.",), moss_amount=0.45,
                  rules={"support": "below", "knock": 0, "shatter_at": 0.5}, bend=0.17)
        return

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
        if c.z - wave(c, UP) > tops[i] - rust[i]:  # rust running down from the top
            return "wood.3" if i % 3 else "accent.0"
        return "stone.1" if i % 2 else "stone.2"
    fractured(name, rng, whole, seeds, choose, stretch=(1, 1, 0.02), post=post, size=size,
              rubble=("stone.2", "stone.1", "stone.0"), out=out)


def iron_banded():
    """Iron B: an angular slab of banded iron: layers of deep red jasper and steel-grey hematite,
    weathered paler on top. The pieces break mostly along the layers."""
    reset()
    rng = seeded(104)
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


def coal_strata(name="coal_strata", out="designs", shatter=False):
    """Coal A: a low, wide outcrop of layered rock: thick black coal seams between grey shale,
    and the pieces come away as slabs along the layers. With `shatter`, it's stacked plates that
    rest on the ones beneath: undercut it and a whole layer drops."""
    reset()
    rng = seeded(105)
    r = recipe(105, wide=(1.2, 1.35, 1.55), deep=(0.95, 1.1, 1.22), tall=(0.5, 0.6, 0.72),
               lumpy=(0.7, 1.0, 1.4), chops=(3, 4, 6), size=(0.9, 1.0, 1.12))
    squash = (r.wide, r.deep, r.tall)
    whole, cz = boulder_mesh(rng, 1.0, subdiv=4 if shatter else 3, squash=squash, lumps=4,
                             lump_amp=(0.08 * r.lumpy, 0.16 * r.lumpy), chops=r.chops)
    if shatter:
        bmesh.ops.translate(whole, vec=Vector((0, 0, -0.05)), verts=whole.verts)
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
        coal = is_coal(c.z - wave(c, UP))
        if is_cut:
            return ("neutral.2" if rng.random() < 0.25 else "ore.coal") if coal else "stone.4"
        if f.normal.z > 0.75:
            return "neutral.2" if coal else "stone.4"
        if coal:
            return "ore.coal" if f.normal.z > -0.3 else "neutral.0"
        return "stone.3" if f.normal.z > -0.3 else "stone.2"
    if shatter:
        def choose(f, is_cut, i):  # weathered: dull charcoal seams in pale shale; broken: glossy coal
            c = f.calc_center_median()
            coal = is_coal(c.z - wave(c, UP))
            if is_cut:
                return "ore.coal" if coal else "stone.5"
            if coal:
                return "neutral.3" if f.normal.z > 0.5 else "neutral.2"
            return "stone.5" if f.normal.z > 0.5 else "stone.4"
        top = max(v.co.z for v in whole.verts)
        plates = []
        for level in range(5):  # five courses of plates, each offset from the one under it
            z = (level + 0.5) * top / 5
            ring = 6 if level < 3 else 5 if level < 4 else 3
            for k in range(ring):
                a = k * math.tau / ring + level * 0.55 + rng.uniform(-0.2, 0.2)
                r = rng.uniform(0.35, 0.8) * (1.0 - 0.12 * level)
                plates.append(Vector((math.cos(a) * r * squash[0], math.sin(a) * r * squash[1], z)))
            plates.append(Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), z)))
        shattered(name, rng, whole, plates, choose, stretch=(1, 1, 3.0), out=out,
                  rubble=("neutral.2", "ore.coal", "neutral.0"), moss_amount=0.6,
                  rules={"support": "below", "knock": 0, "shatter_at": 0.5})
        return
    fractured(name, rng, whole, seeds, choose, stretch=(1, 1, 3.0),
              rubble=("neutral.2", "ore.coal", "neutral.0"), out=out)


def coal_lump():
    """Coal B: one big glossy lump of coal, all sharp facets: black, with bright glints where the
    light catches a face, and a little grey stone clinging to its base."""
    reset()
    rng = seeded(106)
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
    rng = seeded(107)
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
    rng = seeded(108)
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
    rng = seeded(109)
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


def gold_geode_shatter(name="gold_rock", out="", heart="gold"):
    """Gold, breaking where it's struck: the veined geode as a tough shell of a few big pieces
    (each takes two hits, unless it's the fault) round a crystal heart of small ones. `heart`
    "gold" (the game's): solid gold crystal, quartz-rimmed; "quartz" (the other candidate, models/
    designs/gold_geode_quartz): white quartz studded with gold nuggets, which get lost in the
    shade of the hole. The thin gold veins outside stay, so it's spotted from a distance."""
    reset()
    rng = seeded(109)
    r = recipe(109, wide=(1.0, 1.1, 1.25), tall=(0.68, 0.8, 0.92), lumpy=(0.75, 1.0, 1.3), chops=(2, 3, 5),
               size=(0.88, 1.0, 1.1))
    size = 0.95
    squash = (r.wide, 1.05, r.tall)
    whole, cz = boulder_mesh(rng, size, subdiv=4, squash=squash, chops=r.chops,
                             lump_amp=(0.15 * r.lumpy, 0.25 * r.lumpy), noise=0.06)
    bmesh.ops.translate(whole, vec=Vector((0, 0, -0.05)), verts=whole.verts)
    cz -= 0.05
    centre = Vector((0, 0, cz))
    veins = ore_lenses(rng, whole, centre, 6, (0.035, 0.055), (0.28, 0.45))  # quartz lenses
    refine_near(whole, lambda f: lens_ratio(f.calc_center_median(), veins, 1.2) < 3.5, cuts=3)
    snap_lenses(whole, veins)
    shell = shell_seeds(rng, size, squash, cz, sides=7, tops=3, out=(0.8, 0.72))[1:]
    inner = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(18):  # the heart: small pieces filling the middle
        h = -0.6 + 1.5 * (i + 0.5) / 18
        k = rng.uniform(0.15, 0.42)
        e = math.asin(max(-1.0, min(1.0, h)))
        inner.append(centre + Vector((math.cos(e) * math.cos(i * golden) * size * squash[0] * k,
                                      math.cos(e) * math.sin(i * golden) * size * squash[1] * k,
                                      math.sin(e) * size * squash[2] * k)))
    seeds = shell + inner
    nuggets = {i for i in range(len(shell), len(seeds)) if rng.random() < 0.4}
    stone = shade_by_normal("wood.3", "wood.2", "wood.1", rng)  # (no random dark faces: a checkerboard)

    def choose(f, is_cut, i):
        c = f.calc_center_median()
        if not is_cut:  # quartz veins that swell and pinch out, gold in their hearts, flecks round them
            v = lens_ratio(c, veins)
            if v < 1.0:
                gold = v < 0.5 and f.normal.z > -0.2 and noise.noise(c * 9.0) > -0.25
                return "ore.gold" if gold else "neutral.6"
            if v < 3.0 and rng.random() < 0.06:
                return "ore.gold"
            return stone(f)
        if i < len(shell):  # the shell's breaks: brown stone, quartz where it meets the heart
            return "neutral.6" if (c - centre).length < 0.5 * size else "wood.2"
        if heart == "gold":
            return "neutral.6" if (c - centre).length > 0.46 * size else ("accent.3" if rng.random() < 0.3 else "ore.gold")
        if i in nuggets:
            return "ore.gold" if rng.random() < 0.75 else "accent.3"
        return "neutral.6" if rng.random() < 0.7 else "neutral.5"
    names = [f"Chunk_{i:02d}" for i in range(len(shell))]
    shattered(name, rng, whole, seeds, choose, size=size, rubble=("wood.3", "wood.2", "stone.1"), out=out,
              ore_swatches=("ore.gold",), moss_amount=0.5,
              rules={"knock": 1, "shatter_at": 0.55, "tough": names})


def designs():
    os.makedirs(os.path.join(OUT_DIR, "designs"), exist_ok=True)
    for build in (copper_verdigris, copper_malachite, iron_columns, iron_banded,
                  coal_strata, coal_lump, gold_quartz, gold_geode, gold_veined):
        build()
    gold_geode_shatter("gold_geode_quartz", out="designs", heart="quartz")


def scale_scene(s):
    """Scales everything built so far about the origin (applied on export)."""
    for obj in bpy.data.objects:
        obj.location *= s
        obj.scale *= s


# The game's rocks: the ore designs picked for each (see "ore designs" above).

def rock():
    """Copper (Mining 1): the verdigris boulder, breaking where it's struck."""
    copper_verdigris("rock", out="", shatter=True)


def iron_rock():
    """Iron (Mining 15): basalt columns, jointed so they topple."""
    iron_columns("iron_rock", out="", shatter=True)


def coal_rock():
    """Coal (Mining 20): coal seams between shale, in plates that drop when undercut."""
    coal_strata("coal_rock", out="", shatter=True)


def gold_rock():
    """Gold (Mining 30): the veined geode, a tough shell round a crystal heart."""
    gold_geode_shatter("gold_rock", out="")


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


def mark_fresh(bm, cut):
    """Unweathered (glassy crystal): the "cut_mark" colour white, alpha 0 on cut faces."""
    layer = bm.loops.layers.float_color.get("cut_mark") or bm.loops.layers.float_color.new("cut_mark")
    for f in bm.faces:
        for loop in f.loops:
            loop[layer] = (1.0, 1.0, 1.0, 0.0 if f[cut] else 1.0)


def crystal_rock():
    """A dark stone base bristling with violet crystals (Mining 40). The base stays; each crystal
    is two or three shards end to end, the foot one resting on the stone: hit a shard and it
    breaks out, knock out a foot and the rest of that crystal comes down with it. Two stubs are
    left while it grows back. The stone is weathered; the crystals clean and glassy."""
    reset()
    rng = seeded(15)
    r = recipe(15, long=(0.82, 1.0, 1.22), lean=(0.65, 1.0, 1.35), base=(0.4, 0.5, 0.62), size=(0.9, 1.0, 1.1))
    bm = blob(0.5, rng, squash=(1.15, 1.0, r.base))
    paint(bm, shade_by_normal("stone.3", "stone.2", "stone.1", rng))
    stone = bm.copy()  # where the crystals come out of it (world space)
    bmesh.ops.translate(stone, vec=Vector((0, 0, 0.18)), verts=stone.verts)
    surface = BVHTree.FromBMesh(stone)
    body_cut = bm.faces.layers.int.new("cut")
    bake_weathering(bm, body_cut, BVHTree.FromBMesh(bm), 0.5, moss_amount=0.5)
    make_object("Body_Core", bm, (0, 0, 0.18))
    links, ore, grounded = {}, set(), []
    shards = [  # (length, radius, tilt, azimuth)
        (1.15, 0.16, 0.12, 0.0), (0.85, 0.13, 0.55, 0.4), (0.75, 0.12, 0.6, 2.2),
        (0.9, 0.13, 0.5, 3.6), (0.6, 0.1, 0.75, 5.0),
    ]
    for i, (length, radius, tilt, a) in enumerate(shards):
        length, tilt = length * r.long, min(tilt * r.lean, 0.95)
        base = (math.cos(a) * 0.16 * (i > 0), math.sin(a) * 0.16 * (i > 0), 0.3)
        axis = Vector((math.sin(tilt) * math.cos(a), math.sin(tilt) * math.sin(a), math.cos(tilt)))
        hit = surface.ray_cast(Vector(base), axis)  # from inside the stone, out along the crystal
        buried = (hit[3] if hit[0] is not None else 0.0) + 0.01
        whole = prism(6, radius, radius * 0.12, length)
        jitter(whole, 0.06, rng)
        whole.faces.layers.int.new("cut")
        chop(whole, Vector((0, 0, -length / 2 + buried)), Vector((0, 0, -1)), as_cut=True)
        where, turn = tilted(base, length, tilt, a), (0, tilt, a)
        bottom = -length / 2 + buried
        count = 3 if length > 0.8 else 2
        joints = [bottom + (length / 2 - bottom) * (k / count + rng.uniform(-0.06, 0.06)) for k in range(1, count)]
        names = [f"Chunk_{'ABCDE'[i]}{k}" for k in range(count)]
        for k in range(count):  # the shards, foot to tip, split across the crystal
            piece = whole.copy()
            cut = piece.faces.layers.int.get("cut")
            if k < count - 1:
                chop(piece, Vector((0, 0, joints[k])), Vector((0, 0, 1)), as_cut=True)
            if k > 0:
                chop(piece, Vector((0, 0, joints[k - 1])), Vector((0, 0, -1)), as_cut=True)
            paint(piece, lambda f, cut=cut: "accent.7" if f[cut] else
                  ("ore.amethyst" if f.normal.z > 0.2 or rng.random() < 0.7 else "accent.6"))
            mark_fresh(piece, cut)
            make_object(names[k], piece, where, turn)
            links[names[k]] = [n for n in (names[k - 1] if k else None, names[k + 1] if k < count - 1 else None) if n]
            ore.add(names[k])
        grounded.append(names[0])
        whole.free()
    stone.free()
    for i, (a, length) in enumerate(((1.2, 0.22), (4.2, 0.18))):
        base = (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.28)
        make_object(f"Rubble_{i}", shard(rng, length, 0.09), tilted(base, length, 0.4, a), (0, 0.4, a))
    scale_scene(1.5)  # as hefty as the boulders
    export_pieces("crystal_rock", links, ore, {"grounded": grounded, "knock": 0, "shatter_at": 0.7,
                                               "tough": list(links)})  # (crystal is hard: two hits a shard)


def crystal_item():
    reset()
    rng = seeded(39)
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
    rng = seeded(seed)
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
    rng = seeded(70)
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
    rng = seeded(71)
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


def weathered(bm, at=(0, 0, 0), moss_amount=0.6, soil=0.0):
    """A whole stone (no breaks) weathered like the ore rocks (bake_weathering), moved to `at`
    first so its foot sits in the ground the bake darkens against (and, with `soil`, dirties)."""
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    cut = bm.faces.layers.int.get("cut") or bm.faces.layers.int.new("cut")
    bake_weathering(bm, cut, BVHTree.FromBMesh(bm), max(v.co.z for v in bm.verts), moss_amount=moss_amount,
                    soil=soil)
    return bm


def quarry_rubble():
    """Scenery: a little spill of pale broken stone, one merged mesh."""
    reset()
    rng = seeded(72)
    for i in range(6):
        r = rng.uniform(0.1, 0.28)
        bm = blob(r, rng, jitter_amount=0.35, squash=(1.2, 1.0, 0.6), subdiv=1)
        paint(bm, shade_by_normal("stone.6", "stone.5", "stone.4", rng))
        a, d = rng.uniform(0, math.tau), rng.uniform(0, 0.5)
        make_object(f"Stone{i}", weathered(bm, (math.cos(a) * d, math.sin(a) * d, r * 0.3), moss_amount=0.1))
    merge_all("Rubble")
    export(os.path.join("scenery", "quarry_rubble"), loose_edges=True)


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
    rng = seeded(80)
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
    rng = seeded(seed)
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
    rng = seeded(seed)
    stalks(rng, 7, 0.035, 0.2, stalk, ear, ear_size * 0.75, droop * 0.6, awns, thick=0.018)
    bm = prism(8, 0.045, 0.045, 0.03)
    paint(bm, lambda f: "wood.3")
    make_object("Tie", bm, (0, 0, 0.08))
    merge_all("Item")
    export(os.path.join("items", name))


def wheat_clump():
    """Scenery: a clump of ripe wheat for the crop squares (not gatherable), one merged mesh."""
    reset()
    rng = seeded(81)
    stalks(rng, 9, 0.45, 0.9, "terrain.sand", ("accent.3", "wood.6"), 0.12)
    merge_all("Wheat")
    export(os.path.join("scenery", "wheat_clump"))


WHEAT = dict(stalk="terrain.sand", ear=("accent.3", "wood.6"), ear_size=0.13)
BARLEY = dict(stalk="leaves.7", ear=("wood.7", "terrain.sand"), ear_size=0.11, droop=0.9, awns="wood.7")


def hay_round():
    """A round bale lying on its side, 1.3 m tall: a mantle step."""
    reset()
    rng = seeded(82)
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
    rng = seeded(83)
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
    rng = seeded(84)
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
    rng = seeded(85)
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
    rng = seeded(86)
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
    rng = seeded(100)
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
    rng = seeded(101)
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
    rng = seeded(seed)
    for k in range(levels):
        plank(f"Crate{k}", (1.9, 1.9, 0.98), (0, 0, 0.5 + k), rng, (0, 0, rng.uniform(-0.05, 0.05)), shades=ROAD_WOOD)
        for y in (-0.96, 0.96):
            plank(f"Slat{k}{y}", (1.95, 0.04, 0.12), (0, y, 0.5 + k), rng, shades=("wood.3",) * 4)
    merge_all("Crates")
    export(os.path.join("road", name))


def wallrun_panel():
    """A timber wall 11 m long and 3 m tall beside the road: one full wall run."""
    reset()
    rng = seeded(102)
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
    rng = seeded(103)
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
    rng = seeded(104)
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
    rng = seeded(105)
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
    rng = seeded(106)
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
    rng = seeded(107)
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


## The chopping band of a carved trunk: rings this far apart from CARVE_BAND[0] to CARVE_BAND[1]
## up the trunk (m), so the notch (ResourceNode's TrunkCarve) has vertices to push in. The notch
## sits on one of these rings, and the tree splits there when it falls.
CARVE_BAND = (0.55, 1.45)
CARVE_RING_STEP = 0.05


def ringed_trunk(rng, sides, r_bottom, r_top, height, bark, wobble=0.035, flare=0.0, lobes=5,
                 lean=(0.0, 0.0), marks=None, upper=(2.0, 2.6), furrows=0.0):
    """A tapered trunk standing on the origin, built as rings: sparse up the trunk and dense
    through the chopping band (CARVE_BAND), every ring level so the notch can find them. Each
    column of the bark wobbles in or out a little as a whole, and is shaded as one strip.
    flare: roots spreading at the foot (extra radius at the ground, as a share, in `lobes` lobes);
    lean: how far the top drifts sideways (m), bending only above the chopping band, so the notch
    still cuts a straight column; marks: (swatch, share) bark marks dashed across the strips (the
    birch's black lenticels); upper: ring heights above the band (more rings bend more smoothly).
    Nothing runs ruler-straight: rings above the band come every few tens of centimetres, the bark
    swells and dips in wandering lumps (smooth noise round and up the trunk), the taper eases, and
    above the band the trunk sways gently from side to side on top of its lean. furrows: the bark's
    ridges (every other column stands out by this share of the radius, more in some places)."""
    zs = [0.0, 0.12, 0.25] if flare else [0.0, 0.25]
    z = CARVE_BAND[0]
    while z <= CARVE_BAND[1] + 1e-6:
        zs.append(round(z, 4))
        z += CARVE_RING_STEP
    above = {z for z in upper if z < height - 0.3}
    k = 1
    while CARVE_BAND[1] + 0.3 * k < height - 0.2:
        above.add(round(CARVE_BAND[1] + 0.3 * k, 4))
        k += 1
    for z in sorted(above):
        if z - zs[-1] > 0.12:
            zs.append(z)
    zs.append(height)
    wobble_of = [1.0 + rng.uniform(-wobble, wobble) * 0.5 / max(r_bottom, 0.1) for _ in range(sides)]
    strip = [bark[1] if rng.random() < 0.6 else bark[3] for _ in range(sides)]
    lobe_of = [max(math.cos(lobes * i * math.tau / sides + rng.uniform(-0.4, 0.4)), 0.0) for i in range(sides)] \
        if flare else [0.0] * sides
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    sway = min(0.6 * r_top, 0.1)
    bm = bmesh.new()
    rings = []
    for z in zs:
        r = r_bottom + (r_top - r_bottom) * (z / height) ** 0.85
        bend = max(z - CARVE_BAND[1], 0.0) / max(height - CARVE_BAND[1], 0.01)
        ox = lean[0] * bend * bend + sway * bend * noise.noise(Vector((z * 0.6, 0.0, 0.0)) + off)
        oy = lean[1] * bend * bend + sway * bend * noise.noise(Vector((0.0, z * 0.6, 3.0)) + off)
        ring = []
        for i in range(sides):
            a = i * math.tau / sides
            foot = flare * max(1.0 - z / 0.5, 0.0) ** 2 * (0.4 + 1.2 * lobe_of[i])
            lump = 1.0 + wobble * 1.5 / max(r_bottom, 0.1) * noise.noise(Vector((math.cos(a), math.sin(a), z * 1.1)) * 1.4 + off)
            ridge = furrows * (1.0 if i % 2 else -1.0) * (0.7 + 0.3 * noise.noise(Vector((a, z * 0.8, 5.0)) + off))
            k = r * wobble_of[i] * lump * (1.0 + foot) * (1.0 + ridge)
            ring.append(bm.verts.new((math.cos(a) * k + ox, math.sin(a) * k + oy, z)))
        rings.append(ring)
    for lo, hi in zip(rings, rings[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bm.normal_update()
    bm.faces.index_update()
    marked = set()
    if marks:
        marked = {f.index for f in bm.faces if abs(f.normal.z) < 0.9 and rng.random() < marks[1]}

    def shade(f):
        if f.normal.z > 0.9:
            return bark[0]
        if f.normal.z < -0.9:
            return bark[2]
        if f.index in marked:
            return marks[0]
        c = f.calc_center_median()
        return strip[round(math.atan2(c.y, c.x) / (math.tau / sides) - 0.5) % sides]
    paint(bm, shade)
    return bm


def limb(a, b, r0, r1, rng, bark, sides=6, segments=5, arch=0.14):
    """A tapered branch from point a to point b, as a bmesh in place (not centred). It arches
    rather than running straight: it bows up off the line between its ends by about `arch` of its
    length (a little sideways too), its taper eases, and each joint kinks a touch."""
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length
    side = d.cross(UP)
    side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
    up = side.cross(d).normalized()
    if up.z < 0:
        up = -up
    bow = arch * length * rng.uniform(0.6, 1.3)
    swing = arch * length * rng.uniform(-0.5, 0.5)
    points = []
    for k in range(segments + 1):
        t = k / segments
        p = a + d * t + (up * bow + side * swing) * math.sin(math.pi * t)
        if 0 < k < segments:
            p += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.02 * length
        points.append(p)
    bm = bmesh.new()
    rings = []
    normal = None
    for k, p in enumerate(points):
        tangent = (points[min(k + 1, segments)] - points[max(k - 1, 0)]).normalized()
        # carried along from ring to ring, so the tube doesn't twist
        if normal is None:
            normal = tangent.orthogonal()
        normal = (normal - tangent * normal.dot(tangent)).normalized()
        binormal = tangent.cross(normal)
        r = r0 + (r1 - r0) * (k / segments) ** 0.8
        rings.append([bm.verts.new(p + (normal * math.cos(i * math.tau / sides) + binormal * math.sin(i * math.tau / sides)) * r)
                      for i in range(sides)])
    strip = [bark[1] if rng.random() < 0.6 else bark[3] for _ in range(sides)]
    column = {}
    for lo, hi in zip(rings, rings[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            column[bm.faces.new((lo[i], lo[j], hi[j], hi[i]))] = i
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    paint(bm, lambda f: strip[column[f]] if f in column else bark[1])
    return bm


def jitter_in_place(bm, amount, rng):
    """Nudges every vertex by up to `amount` (m) in each axis, wherever the mesh is."""
    for v in bm.verts:
        v.co += Vector((rng.uniform(-amount, amount), rng.uniform(-amount, amount), rng.uniform(-amount, amount)))


# --- trees ----------------------------------------------------------------------------------
# Two candidate looks per tree (models/designs/), all on a ringed trunk the axe can notch; the
# picked one of each also builds the game's tree (tree_round -> tree, birch_airy -> birch,
# oak_spreading -> oak, pine_classic -> pine). Every tree: a rounder trunk with a root flare and
# a little lean or curve above the chopping band, a few branches, and the canopy as more, smaller
# clumps on the branch ends.

STARTER_BARK = ("wood.5", "wood.3", "wood.2", "wood.2")
STARTER_LEAVES = ("leaves.5", "leaves.3", "leaves.1", "leaves.4")
BIRCH_BARK = ("neutral.7", "neutral.6", "neutral.5", "neutral.7")
BIRCH_LEAVES = ("leaves.7", "leaves.6", "leaves.4", "leaves.5")
OAK_BARK = ("wood.3", "wood.1", "wood.0", "wood.2")
OAK_LEAVES = ("leaves.3", "leaves.2", "leaves.0", "leaves.1")
PINE_BARK = ("wood.3", "wood.1", "wood.0", "wood.2")
PINE_NEEDLES = ("leaves.2", "leaves.1", "leaves.0", "leaves.2")


def clumps(rng, spots, leaves, name="Body_Canopy"):
    """Canopy clumps: (radius, (x, y, z), squash) each: lumpy leafy blobs (leaf cards round a
    dark core, see leafy())."""
    for i, (r, loc, squash) in enumerate(spots):
        bm = blob(r, rng, jitter_amount=0.2, squash=squash)
        leafy(bm, rng, leaves, card_size=0.55 + r * 0.45, density=4.5)
        spherical_normals(make_object(f"{name}{i}", bm, loc, (0, 0, rng.uniform(0, math.tau))), squash=squash)


def limbs(rng, pairs, bark, name="Body_Limb"):
    """Branches: (from, to, base radius, tip radius) each."""
    for i, (a, b, r0, r1) in enumerate(pairs):
        make_object(f"{name}{i}", limb(a, b, r0, r1, rng, bark))


def fork(rng, branches, reach, r0, count=(2, 3), rise=0.3):
    """Twigs forking from each branch's end, so the crown hangs off a branching frame instead of
    sitting on a few sticks: `branches` are (from, end) points; each end puts out `count` (low,
    high) twigs fanning round the way its branch was heading and a little up, about `reach` metres
    long and `r0` thick where they fork. Returns (twig pairs for limbs(), twig tips)."""
    pairs, tips = [], []
    for base, end in branches:
        end = Vector(end)
        d = end - Vector(base)
        d.z = 0.0
        d = d.normalized() if d.length > 1e-4 else Vector((1, 0, 0))
        n = rng.randint(*count)
        for k in range(n):
            a = (k - (n - 1) / 2) * 0.9 + rng.uniform(-0.25, 0.25)
            way = Matrix.Rotation(a, 3, "Z") @ d + Vector((0, 0, rise + rng.uniform(-0.15, 0.2)))
            tip = end + way.normalized() * reach * rng.uniform(0.75, 1.2)
            pairs.append((tuple(end), tuple(tip), r0, r0 * 0.4))
            tips.append(tuple(tip))
    return pairs, tips


def add_roots(trunk, rng, count, r_base, reach, bark):
    """Surface roots, part of the trunk's own mesh (so they stay with the stump when it's felled):
    `count` of them arching out of the flare and down into the ground, `reach` metres out. Kept
    under the chopping band, whose rings the notch reads."""
    mesh = bpy.data.meshes.new("roots")
    for i in range(count):
        a = i * math.tau / count + rng.uniform(-0.35, 0.35)
        out = Vector((math.cos(a), math.sin(a), 0.0))
        far = r_base + reach * rng.uniform(0.7, 1.2)
        bm = limb(out * r_base * 0.4 + Vector((0, 0, 0.25)), out * far + Vector((0, 0, -0.12)),
                  r_base * 0.42, r_base * 0.1, rng, bark, segments=4, arch=0.12)
        for v in bm.verts:
            v.co.z = min(v.co.z, CARVE_BAND[0] - 0.08)
        bm.to_mesh(mesh)
        bm.free()
        trunk.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    return trunk


def join_parts(prefix, name, groups=1):
    """Joins the objects named `prefix`* into `groups` objects (named `name`, or `name`0, 1 ...
    when more than one), by which way round the tree they sit: fewer meshes to draw, while the
    canopy still shakes in a few separate parts on a hit."""
    objs = sorted((o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith(prefix)),
                  key=lambda o: o.name)
    if not objs:
        return
    bpy.context.view_layer.update()
    buckets = [[] for _ in range(groups)]
    for o in objs:
        c = o.matrix_world @ (sum((v.co for v in o.data.vertices), Vector()) / max(len(o.data.vertices), 1))
        buckets[int((math.atan2(c.y, c.x) / math.tau + 0.5) * groups) % groups].append(o)
    k = 0
    for bucket in buckets:
        if not bucket:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in bucket:
            o.select_set(True)
        bpy.context.view_layer.objects.active = bucket[0]
        bpy.ops.object.join()
        bucket[0].name = f"{name}{k}" if groups > 1 else name
        k += 1


def fan(n, radius, z, rng, start=0.0, jit=0.25):
    """n points round a circle (radius, at height z), a little uneven."""
    return [(math.cos(start + i * math.tau / n + rng.uniform(-jit, jit)) * radius,
             math.sin(start + i * math.tau / n + rng.uniform(-jit, jit)) * radius, z + rng.uniform(-0.15, 0.15))
            for i in range(n)]


## How big each choppable tree grows, by species: (out, up, girth). The trees are drawn at a
## smaller size and grown at the end (grow_crown): the crown and limbs spread `out` and rise `up`
## above the chopping band, which stays at the axe's height; the trunk is built that tall and
## `girth` thicker. Oaks are the broad, stout ones, pines the tall ones, birches tall and slim.
TREE_SIZE = {"tree": (1.5, 1.5, 1.25), "birch": (1.5, 1.8, 1.15), "oak": (2.0, 2.0, 1.5), "pine": (1.5, 1.9, 1.35)}


def lifted(up):
    """Heights stretched `up` times above the chopping band (the band itself stays put)."""
    return lambda z: z if z <= CARVE_BAND[1] else CARVE_BAND[1] + (z - CARVE_BAND[1]) * up


def grow_crown(out, up):
    """Grows everything built so far but the trunk and the stump (the limbs and canopy): `out`
    times as far from the trunk and `up` times as high above the chopping band (see lifted). The
    trunk is built at the grown height, its lean `out` times as far, so the limbs still meet it."""
    lift = lifted(up)
    bpy.context.view_layer.update()  # (or a new object's matrix_world is still the identity)
    for o in bpy.context.scene.objects:
        if o.type != "MESH" or o.name == "Body_Trunk" or o.name.startswith("Rubble_"):
            continue
        m = o.matrix_world.copy()
        inv = m.inverted()
        for v in o.data.vertices:
            p = m @ v.co
            v.co = inv @ Vector((p.x * out, p.y * out, lift(p.z)))


def cut_stump(r_bottom, r_top, bark, rng):
    """Rubble_Stump: what shows while a tree regrows if its notch wasn't saved (the game leaves
    the real cut stump otherwise, see TrunkCarve)."""
    bm = prism(12, r_bottom * 1.1, r_top, 0.4)
    paint(bm, lambda f: "wood.7" if f.normal.z > 0.9 else (bark[1] if rng.random() < 0.6 else bark[3]))
    make_object("Rubble_Stump", bm, (0, 0, 0.2))


def tree_round(name="tree_round", out_dir="designs"):
    """Starter A (picked: the game's tree): a rounded crown of clumps on three spreading branches,
    a little root flare."""
    reset()
    rng = seeded(70)
    r = recipe(70, tall=(-0.3, 0.0, 0.45), spread=(0.8, 0.95, 1.2), bushy=(0.85, 1.0, 1.18), lean=(0.3, 1.0, 2.2))
    up = r.tall  # (everything above the trunk's foot moves up with it)
    out, rise, girth = TREE_SIZE["tree"]
    trunk = ringed_trunk(rng, 12, 0.24 * girth, 0.15 * girth, lifted(rise)(2.9 + up), STARTER_BARK,
                         flare=0.3, lean=(0.12 * r.lean * out, 0.05 * r.lean * out), furrows=0.03)
    make_object("Body_Trunk", add_roots(trunk, rng, 3, 0.24 * girth, 0.55, STARTER_BARK))
    base = (0.1, 0.03, 2.5 + up)
    ends = fan(3, r.spread, 3.5 + up, rng, 0.4)
    twigs, tips = fork(rng, [(base, e) for e in ends], 0.5, 0.045)
    limbs(rng, [(base, e, 0.09, 0.04) for e in ends] + twigs, STARTER_BARK)
    spots = [(0.62 * r.bushy, e, (1, 1, 0.8)) for e in ends]
    spots += [(0.45 * r.bushy * rng.uniform(0.8, 1.15), t, (1, 1, 0.85)) for t in tips]
    spots += [(0.8 * r.bushy, (0.1, 0.0, 3.95 + up), (1, 1, 0.8)), (0.5 * r.bushy, (0.5, -0.4, 4.3 + up), (1, 1, 0.85)),
              (0.45 * r.bushy, (-0.45, 0.35, 4.25 + up), (1, 1, 0.85))]
    clumps(rng, spots, STARTER_LEAVES)
    grow_crown(out, rise)
    join_parts("Body_Limb", "Body_Limbs")
    join_parts("Body_Canopy", "Body_Canopy", 3)
    cut_stump(0.24 * girth, 0.22 * girth, STARTER_BARK, rng)
    export(os.path.join(out_dir, name))


def tree_tiered():
    """Starter B: a straighter trunk with two tiers of flat clumps and a small crown on top."""
    reset()
    rng = seeded(71)
    make_object("Body_Trunk", ringed_trunk(rng, 12, 0.23, 0.13, 3.9, STARTER_BARK, flare=0.2, lean=(-0.06, 0.08),
                                           upper=(2.0, 2.6, 3.2)))
    low = fan(4, 1.0, 2.75, rng, 0.2)
    high = fan(3, 0.7, 3.55, rng, 1.0)
    limbs(rng, [((0, 0, 2.4), e, 0.08, 0.035) for e in low] + [((0, 0, 3.2), e, 0.06, 0.03) for e in high],
          STARTER_BARK)
    spots = [(0.7, e, (1.15, 1.15, 0.55)) for e in low] + [(0.6, e, (1.1, 1.1, 0.6)) for e in high]
    spots.append((0.55, (-0.05, 0.08, 4.2), (1, 1, 0.8)))
    clumps(rng, spots, STARTER_LEAVES)
    export(os.path.join("designs", "tree_tiered"))


def birch_airy(name="birch_airy", out_dir="designs"):
    """Birch A (picked: the game's birch): a slim white trunk dashed with black, curving gently,
    and small upright clumps hung along its upper half."""
    reset()
    rng = seeded(72)
    r = recipe(72, tall=(0.85, 1.0, 1.18), lean=(0.3, 1.0, 1.8), bushy=(0.85, 1.0, 1.18), reach=(0.8, 1.0, 1.3))
    top = 4.3 * r.tall
    lean = (0.3 * r.lean, -0.1 * r.lean)
    out, rise, girth = TREE_SIZE["birch"]
    trunk = ringed_trunk(rng, 10, 0.17 * girth, 0.09 * girth, lifted(rise)(top), BIRCH_BARK,
                         flare=0.15, lobes=4, lean=(lean[0] * out, lean[1] * out), marks=("neutral.1", 0.16))
    make_object("Body_Trunk", add_roots(trunk, rng, 3, 0.17 * girth, 0.3, ("neutral.4", "neutral.5", "neutral.4", "neutral.6")))
    spots = []
    pairs = []
    for i, z in enumerate((2.3, 2.6, 2.9, 3.2, 3.5, 3.8)):  # (a tall birch: more of them)
        z = 1.45 + (z - 1.45) * (top - 1.45) / (4.3 - 1.45)
        a = i * 2.2 + rng.uniform(-0.3, 0.3)
        bend = ((z - 1.45) / (top - 1.45)) ** 2
        base = (lean[0] * bend, lean[1] * bend, z)
        tip = (base[0] + math.cos(a) * 0.4 * r.reach, base[1] + math.sin(a) * 0.4 * r.reach, z + 0.4)
        pairs.append((base, tip, 0.05, 0.025))
        spots.append((0.42 * r.bushy, tip, (0.8, 0.8, 1.25)))
        twigs, tips = fork(rng, [(base, tip)], 0.3, 0.025, count=(1, 2), rise=0.6)
        pairs += twigs
        spots += [(0.32 * r.bushy, t, (0.8, 0.8, 1.3)) for t in tips]
    spots.append((0.5 * r.bushy, (0.32 * r.lean, lean[1], top + 0.25), (0.85, 0.85, 1.3)))
    limbs(rng, pairs, BIRCH_BARK)
    clumps(rng, spots, BIRCH_LEAVES)
    grow_crown(out, rise)
    join_parts("Body_Limb", "Body_Limbs")
    join_parts("Body_Canopy", "Body_Canopy", 3)
    cut_stump(0.17 * girth, 0.16 * girth, BIRCH_BARK, rng)
    export(os.path.join(out_dir, name))


def birch_forked():
    """Birch B: a white trunk that forks above head height into two slender leaders, each with
    a loose crown."""
    reset()
    rng = seeded(73)
    make_object("Body_Trunk", ringed_trunk(rng, 10, 0.17, 0.11, 2.6, BIRCH_BARK, flare=0.15, lobes=4,
                                           lean=(0.05, 0.05), marks=("neutral.1", 0.16)))
    tops = [(0.55, 0.2, 4.4), (-0.45, -0.25, 4.1)]
    limbs(rng, [((0, 0, 2.5), t, 0.1, 0.05) for t in tops], BIRCH_BARK, name="Body_Leader")
    spots = []
    for t in tops:
        spots += [(0.55, (t[0], t[1], t[2] + 0.15), (0.85, 0.85, 1.2))]
        spots += [(0.42, (t[0] + dx, t[1] + dy, t[2] - 0.5), (0.85, 0.85, 1.2)) for dx, dy in ((0.35, -0.2), (-0.25, 0.3))]
    clumps(rng, spots, BIRCH_LEAVES)
    export(os.path.join("designs", "birch_forked"))


def oak_spreading(name="oak_spreading", out_dir="designs"):
    """Oak A (picked: the game's oak): a stout trunk on big buttress roots, four thick limbs
    reaching out wide, a broad crown of heavy clumps."""
    reset()
    rng = seeded(74)
    r = recipe(74, tall=(-0.2, 0.0, 0.4), spread=(1.3, 1.6, 1.95), bushy=(0.88, 1.0, 1.15), limbs=(3, 4, 5))
    up = r.tall
    out, rise, girth = TREE_SIZE["oak"]
    trunk = ringed_trunk(rng, 12, 0.36 * girth, 0.26 * girth, lifted(rise)(2.4 + up), OAK_BARK,
                         flare=0.5, lobes=6, lean=(0.08 * out, 0.0), furrows=0.05)
    make_object("Body_Trunk", add_roots(trunk, rng, 5, 0.36 * girth, 0.7, OAK_BARK))
    base = (0, 0, 2.1 + up)
    ends = fan(r.limbs, r.spread, 3.0 + up, rng, 0.5)
    twigs, tips = fork(rng, [(base, e) for e in ends], 0.75, 0.07, rise=0.5)
    limbs(rng, [(base, e, 0.16, 0.07) for e in ends] + twigs, OAK_BARK)
    spots = [(0.8 * r.bushy, (e[0], e[1], e[2] + 0.2), (1.15, 1.15, 0.75)) for e in ends]
    spots += [(0.62 * r.bushy * rng.uniform(0.8, 1.15), t, (1.15, 1.15, 0.8)) for t in tips]
    # a domed crown, not a flat table: a ring of clumps above the limbs and one on top
    spots += [(0.85 * r.bushy, (x * 0.45, y * 0.45, 3.95 + up), (1.1, 1.1, 0.85))
              for x, y, _ in fan(r.limbs, r.spread, 0.0, rng, 0.5 + math.pi / r.limbs)]
    spots += [(1.0 * r.bushy, (0.05, 0.0, 4.25 + up), (1.1, 1.1, 0.8))]
    # (grown this big, the crown wants filling in between the limbs' clumps)
    spots += [(0.75 * r.bushy, (e[0] * 0.55, e[1] * 0.55, e[2] + 0.45), (1.1, 1.1, 0.7)) for e in fan(r.limbs, r.spread, 3.0 + up, rng, 0.5 + math.pi / r.limbs)]
    clumps(rng, spots, OAK_LEAVES)
    grow_crown(out, rise)
    join_parts("Body_Limb", "Body_Limbs")
    join_parts("Body_Canopy", "Body_Canopy", 3)
    cut_stump(0.36 * girth, 0.33 * girth, OAK_BARK, rng)
    export(os.path.join(out_dir, name))


def oak_gnarled():
    """Oak B: a thick leaning trunk, crooked limbs (two bends each), a wide flat-topped crown."""
    reset()
    rng = seeded(75)
    make_object("Body_Trunk", ringed_trunk(rng, 12, 0.38, 0.27, 2.5, OAK_BARK, flare=0.4, lobes=5, lean=(0.45, 0.2),
                                           wobble=0.05))
    top = (0.45, 0.2, 2.35)
    pairs, spots = [], []
    for i in range(3):
        a = 0.6 + i * math.tau / 3 + rng.uniform(-0.3, 0.3)
        mid = (top[0] + math.cos(a) * 0.7, top[1] + math.sin(a) * 0.7, 2.85 + rng.uniform(-0.1, 0.2))
        end = (mid[0] + math.cos(a + 0.6) * 0.75, mid[1] + math.sin(a + 0.6) * 0.75, mid[2] + 0.35)
        pairs += [(top, mid, 0.15, 0.1), (mid, end, 0.1, 0.05)]
        spots += [(1.0, (end[0], end[1], end[2] + 0.15), (1.25, 1.25, 0.55))]
    spots.append((1.15, (top[0], top[1], 3.45), (1.3, 1.3, 0.5)))
    limbs(rng, pairs, OAK_BARK)
    clumps(rng, spots, OAK_LEAVES)
    export(os.path.join("designs", "oak_gnarled"))


def needle_cone(rng, r, h, tip=0.05):
    """One tier of a pine (leafy() needles it), centred on the origin: not a smooth cone but a
    whorl of boughs: its rim lobed into bough tips that droop and stick out unevenly, its sides
    sagging (a hollow profile) up to the leader."""
    sides = 14
    off = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
    lobe = [1.0 + 0.25 * noise.noise(Vector((math.cos(i * math.tau / sides), math.sin(i * math.tau / sides), 0.0)) * 1.7 + off)
            + (0.14 if i % 2 else -0.1) for i in range(sides)]
    bm = bmesh.new()
    rings = []
    for t in (0.0, 0.3, 0.62):
        rr = r * (1.0 - t) ** 1.35 + tip
        ring = []
        for i in range(sides):
            a = i * math.tau / sides
            k = rr * (1.0 + (lobe[i] - 1.0) * (1.0 - t))
            z = -h / 2 + h * t
            if t == 0.0:  # bough tips droop, some further
                k *= rng.uniform(0.9, 1.08)
                z -= rng.uniform(0.05, 0.3) * (1.6 if i % 2 else 0.8)
            ring.append(bm.verts.new((math.cos(a) * k, math.sin(a) * k, z)))
        rings.append(ring)
    apex = bm.verts.new((0, 0, h / 2))
    for lo, hi in zip(rings, rings[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    for i in range(sides):
        bm.faces.new((rings[-1][i], rings[-1][(i + 1) % sides], apex))
    bm.faces.new(list(reversed(rings[0])))
    bm.normal_update()
    return bm


def pine_classic(name="pine_classic", out_dir="designs"):
    """Pine A (picked: the game's pine): a tall straight trunk with stacked cones of needles,
    their rims drooping and ragged. The lowest rim stays above the chopping band."""
    reset()
    rng = seeded(76)
    shape = recipe(76, tall=(0.85, 1.0, 1.2), wide=(0.82, 1.0, 1.15))
    lift = lambda z: 2.65 + (z - 2.65) * shape.tall  # (the lowest rim stays put, above the chopping band)
    out, rise, girth = TREE_SIZE["pine"]
    trunk = ringed_trunk(rng, 10, 0.3 * girth, 0.1 * girth, lifted(rise)(lift(5.9)), PINE_BARK,
                         flare=0.25, lobes=5, furrows=0.04)
    make_object("Body_Trunk", add_roots(trunk, rng, 4, 0.3 * girth, 0.55, PINE_BARK))
    for i, (r, h, z) in enumerate(((1.9, 1.5, 2.65), (1.6, 1.4, 3.4), (1.25, 1.3, 4.1), (0.9, 1.2, 4.75), (0.5, 1.1, 5.4))):
        r, h, z = r * shape.wide, h * shape.tall, lift(z)
        bm = needle_cone(rng, r, h, 0.06)
        leafy(bm, rng, PINE_NEEDLES, card_size=0.8, density=4.2, kind=CARD_NEEDLES, core=(0.72, 0.72, 0.92),
              droop=0.5, open_bottom=True)
        spherical_normals(make_object(f"Body_Canopy{i}", bm, (0, 0, z), (0, 0, rng.uniform(0, math.tau))),
                          centre=(0, 0, -h * 0.3))
    grow_crown(out, rise)
    join_parts("Body_Canopy", "Body_Canopy", 3)
    cut_stump(0.3 * girth, 0.28 * girth, PINE_BARK, rng)
    export(os.path.join(out_dir, name))


def pine_scots():
    """Pine B: a tall bare trunk, warm-barked toward the top, with a crown of flat dark tufts on
    short branches."""
    reset()
    rng = seeded(77)
    bark = ("wood.4", "wood.2", "wood.1", "wood.4")
    make_object("Body_Trunk", ringed_trunk(rng, 10, 0.27, 0.1, 5.4, bark, flare=0.2, lean=(-0.25, 0.15),
                                           upper=(2.0, 2.8, 3.6, 4.4)))
    pairs, spots = [], []
    for i, z in enumerate((3.9, 4.3, 4.6, 4.9, 5.2)):
        a = i * 2.4 + rng.uniform(-0.3, 0.3)
        bend = ((z - 1.45) / (5.4 - 1.45)) ** 2
        base = (-0.25 * bend, 0.15 * bend, z)
        reach = 0.9 - i * 0.12
        tip = (base[0] + math.cos(a) * reach, base[1] + math.sin(a) * reach, z + 0.2)
        pairs.append((base, tip, 0.06, 0.03))
        spots.append((0.75 - i * 0.05, tip, (1.3, 1.3, 0.5)))
    spots.append((0.45, (-0.25, 0.15, 5.6), (1.2, 1.2, 0.55)))
    limbs(rng, pairs, bark)
    clumps(rng, spots, PINE_NEEDLES)
    export(os.path.join("designs", "pine_scots"))


def tree_designs():
    os.makedirs(os.path.join(OUT_DIR, "designs"), exist_ok=True)
    for build in (tree_round, tree_tiered, birch_airy, birch_forked, oak_spreading, oak_gnarled,
                  pine_classic, pine_scots):
        build()


def tree():
    """The starter tree (Woodcutting 1)."""
    tree_round("tree", "")


def oak():
    """A stout oak (Woodcutting 15)."""
    oak_spreading("oak", "")


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
    """A slim white birch (Woodcutting 8)."""
    birch_airy("birch", "")


def pine():
    """A tall pine (Woodcutting 25)."""
    pine_classic("pine", "")


def pickaxe():
    """Handle along +Z from the grip (origin) up; head with two drooping spikes, along Y."""
    reset()
    rng = seeded(3)
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


def hull(points):
    """The convex hull of `points` as a bmesh."""
    bm = bmesh.new()
    for p in points:
        bm.verts.new(p)
    out = bmesh.ops.convex_hull(bm, input=bm.verts)
    inside = [g for g in out["geom_interior"] + out["geom_unused"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.delete(bm, geom=inside, context="VERTS")
    bm.normal_update()
    return bm


# The felling axe's head, its eye on the origin, the handle running through it along Z and the
# bit pointing +Y. Sections across the bit: (distance out along Y, half thickness in X, half height
# in Z, and how far the bit droops at that point). A narrow neck, then the cheeks flare out to a
# tall edge, a little curved and a little lower than the eye, the way a felling bit sweeps down.
AXE_NECK = [(0.02, 0.026, 0.036, 0.0), (0.085, 0.017, 0.04, -0.004)]
AXE_BIT = [(0.08, 0.018, 0.042, -0.004), (0.15, 0.009, 0.074, -0.012), (0.172, 0.002, 0.08, -0.014)]
AXE_EDGE_BULGE = 0.012  # how far the middle of the edge stands out past its corners
AXE_EDGE_FROM = 0.148  # past this the faces are the honed edge (bright)


def felling_head():
    """The felling axe's head as one bmesh: a square poll behind, the eye round the handle, a narrow
    neck and a flaring, thin-ground bit with a curved edge. Painted: dark poll and eye, mid cheeks,
    a bright honed strip along the edge."""
    parts = []
    for sections in (AXE_NECK, AXE_BIT):
        points = []
        for y, hx, hz, droop in sections:
            for sx in (-1, 1):
                for sz in (-1, 1):
                    points.append((sx * hx, y, sz * hz + droop))
        if sections is AXE_BIT:  # the edge bows out in the middle
            y, hx, hz, droop = sections[-1]
            for sx in (-1, 1):
                for t in (-0.5, 0.0, 0.5):
                    bulge = AXE_EDGE_BULGE * (1.0 - t * t * 2.5)
                    points.append((sx * hx, y + bulge, t * hz * 1.6 + droop))
        parts.append(hull(points))
    # the eye (wrapped round the handle) and the poll behind it, one block
    parts.append(box((0.05, 0.075, 0.084)))
    for v in parts[-1].verts:
        v.co.y -= 0.012
    bm = bmesh.new()
    for part in parts:
        mesh = bpy.data.meshes.new("tmp")
        part.to_mesh(mesh)
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        part.free()
    paint(bm, axe_head_shade)
    return bm


def axe_head_shade(f):
    """felling_head's paint (in its own space): a dark poll and eye, mid cheeks, a bright edge."""
    c = f.calc_center_median()
    if c.y > AXE_EDGE_FROM:
        return "metal.7"
    if c.y < 0.03:
        return "metal.2" if f.normal.y < -0.7 else "metal.3"
    return "metal.5" if abs(f.normal.x) > 0.6 else "metal.4"


AXE_HANDLE = 0.6  # long enough to swing from the end; the hand chokes up on it (block_hand)
AXE_HEAD_Z = 0.5  # where the eye sits up the handle


def axe():
    """A felling axe: a long handle along +Z, a little thicker at the knob end, and a felling head
    (felling_head) near the top with its bit pointing forward (+Y)."""
    reset()
    rng = seeded(4)
    bm = prism(4, 0.024, 0.02, AXE_HANDLE)
    for v in bm.verts:  # a knob at the very end so it doesn't slip out of the hands
        if v.co.z < -AXE_HANDLE / 2 + 0.01:
            v.co.x *= 1.35
            v.co.y *= 1.5
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 4, 3, "Z"))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, AXE_HEAD_Z + 0.04 - AXE_HANDLE / 2))
    make_object("Head", felling_head(), (0, 0, AXE_HEAD_Z))
    block_hand("z")
    export("axe")


# --- tool tiers -------------------------------------------------------------------------------
# The forged tools (scripts/autoload/tools.gd LADDER): stone, copper, iron, crystal picks and axes,
# stone and copper sickles, in models/tools/<tool>_<tier>.glb. The same shapes as the pickaxe, axe
# and sickle above with the metal swatches swapped per tier, and a few changes of shape: stone is
# chipped and lashed on with cord, crystal has faceted crystal spikes on a gold collar.

TOOL_TIER_SWATCHES = [
    {"metal.0": "stone.2", "metal.1": "stone.3", "metal.2": "stone.3", "metal.3": "stone.4",
     "metal.4": "stone.5", "metal.5": "stone.5", "metal.6": "stone.6", "metal.7": "stone.7"},
    {"metal.0": "ore.copper_dark", "metal.1": "ore.copper_dark", "metal.2": "ore.copper_dark",
     "metal.3": "ore.copper_dark", "metal.4": "ore.copper", "metal.5": "ore.copper", "metal.6": "ore.copper",
     "metal.7": "ore.gold"},
    {},  # iron: the metal as it is
    {"metal.0": "accent.6", "metal.1": "accent.6", "metal.2": "accent.6", "metal.3": "ore.amethyst",
     "metal.4": "ore.amethyst", "metal.5": "ore.amethyst", "metal.6": "accent.7", "metal.7": "neutral.6"},
]


def tiered(tier, choose):
    """`choose` (a face -> swatch name) with the metal swapped for `tier`'s."""
    swap = TOOL_TIER_SWATCHES[tier]
    return lambda f: swap.get(choose(f), choose(f))


def lashing(z, width, rng):
    """Cord bound round a stone head: a couple of pale wraps."""
    for i, dz in enumerate((-0.022, 0.022)):
        bm = box((width, width * 1.15, 0.016))
        paint(bm, lambda f: "wood.7" if f.normal.z > 0.5 else "wood.6")
        make_object(f"Lashing{i}", bm, (0, 0, z + dz))


def pickaxe_tier(tier):
    reset()
    rng = seeded(3)
    bm = box((0.038, 0.038, 0.5))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, 0.21))
    if tier == 0:
        lashing(0.42, 0.07, rng)
    else:
        bm = box((0.06, 0.075, 0.075))
        collar = shade_by_normal("ore.gold", "ore.gold", "wood.7", rng) if tier == 3 else shade_by_normal("metal.4", "metal.3", "metal.2", rng)
        paint(bm, tiered(tier, collar))
        make_object("Collar", bm, (0, 0, 0.42))
    for side in (1, -1):
        if tier == 0:  # a blunt chipped wedge
            bm = prism(5, 0.058, 0.022, 0.19)
            jitter(bm, 0.12, rng)
            length = 0.115
        elif tier == 3:  # a long faceted crystal
            bm = prism(6, 0.034, 0.002, 0.28)
            length = 0.15
        else:
            bm = prism(4, 0.032, 0.006, 0.24)
            length = 0.14
        paint(bm, tiered(tier, shade_by_normal("metal.6", "metal.4", "metal.3", rng, side_alt="metal.5")))
        make_object(f"Spike{'Front' if side > 0 else 'Back'}", bm, (0, side * length, 0.405),
                    (-side * math.radians(90 + 10), 0, 0))
    block_hand("z")
    export(f"tools/pickaxe_{tier}")


def axe_tier(tier):
    reset()
    rng = seeded(4)
    bm = prism(4, 0.024, 0.02, AXE_HANDLE)
    for v in bm.verts:
        if v.co.z < -AXE_HANDLE / 2 + 0.01:
            v.co.x *= 1.35
            v.co.y *= 1.5
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 4, 3, "Z"))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, AXE_HEAD_Z + 0.04 - AXE_HANDLE / 2))
    head = felling_head()
    if tier == 0:  # knapped stone: thicker, rougher
        for v in head.verts:
            v.co.x *= 1.6
        jitter(head, 0.05, rng)
    paint(head, tiered(tier, axe_head_shade))
    make_object("Head", head, (0, 0, AXE_HEAD_Z))
    if tier == 0:
        lashing(AXE_HEAD_Z, 0.06, rng)
    elif tier == 3:  # a gold band round the eye
        bm = box((0.056, 0.082, 0.02))
        paint(bm, lambda f: "ore.gold")
        make_object("Band", bm, (0, -0.012, AXE_HEAD_Z + 0.046))
    block_hand("z")
    export(f"tools/axe_{tier}")


def sickle_tier(tier):
    reset()
    rng = seeded(80)
    bm = box((0.036, 0.036, 0.26))
    paint(bm, shade_by_normal("wood.6", "wood.4", "wood.3", rng, side_alt="wood.5"))
    make_object("Handle", bm, (0, 0, 0.13))
    if tier == 0:
        lashing(0.27, 0.05, rng)
    else:
        bm = box((0.05, 0.05, 0.035))
        paint(bm, tiered(tier, lambda f: "metal.2"))
        make_object("Ferrule", bm, (0, 0, 0.27))
    centre, r = (0.0, 0.13, 0.29), 0.13
    steps = 8
    for i in range(steps):
        a0 = math.pi + i * (math.pi * 1.05) / steps
        a1 = math.pi + (i + 1) * (math.pi * 1.05) / steps
        p0 = (centre[1] + math.cos(a0) * r, centre[2] - math.sin(a0) * r)
        p1 = (centre[1] + math.cos(a1) * r, centre[2] - math.sin(a1) * r)
        length = math.dist(p0, p1) + 0.008
        width = 0.03 * (1.0 - i / steps * 0.7)
        bm = box((0.02 if tier == 0 else 0.012, length, width * (1.2 if tier == 0 else 1.0)))
        paint(bm, tiered(tier, lambda f: "metal.7" if f.normal.z < -0.5 else ("metal.5" if abs(f.normal.x) > 0.5 else "metal.4")))
        angle = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        make_object(f"Blade{i}", bm, (0, (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2), (angle, 0, 0))
    block_hand("z", grip=0.12)
    export(f"tools/sickle_{tier}")


def tool_tiers():
    """Every tier of the forged tools, into models/tools/."""
    os.makedirs(os.path.join(OUT_DIR, "tools"), exist_ok=True)
    for tier in range(4):
        pickaxe_tier(tier)
        axe_tier(tier)
    for tier in range(2):
        sickle_tier(tier)


def spear():
    """Fishing spear pointing forward (+Y, Godot -Z) from the grip at the origin: wooden shaft,
    a dark binding wrap, and a barbed metal tip at about 1.2 m."""
    reset()
    rng = seeded(5)
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


def _section(name, segments, r_bottom, r_top, length, base_y, shades, rng):
    """A rod section along +Y (Godot -Z) whose origin is its base, so RodFishing can bend the rod
    by turning each section about its own base."""
    bm = prism(segments, r_bottom, r_top, length)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, length / 2))
    paint(bm, shade_by_normal(*shades, rng))
    return make_object(name, bm, (0, base_y, 0), (-math.pi / 2, 0, 0))


def rod():
    """Fishing rod pointing forward (+Y, Godot -Z) from the grip at the origin: a cork handle and
    reel, then three bendable sections (Butt, Mid, Tip, each with its origin at its base) with line
    guides, 1.8 m long. RodFishing finds the sections by name and finds the tip end at Tip's +1 length
    (ROD_TIP_LENGTH there)."""
    reset()
    rng = seeded(6)
    # handle: cork grip from just behind the hand, a dark reel seat ahead of it
    bm = prism(8, 0.019, 0.017, 0.36)
    paint(bm, shade_by_normal("wood.7", "wood.6", "wood.5", rng, side_alt="wood.6"))
    make_object("Cork", bm, (0, 0.05, 0), (-math.pi / 2, 0, 0))
    bm = prism(8, 0.016, 0.016, 0.07)
    paint(bm, lambda f: "metal.1")
    make_object("Seat", bm, (0, -0.18, 0), (-math.pi / 2, 0, 0))
    # the reel: a drum hanging under the seat on a short foot, its handle sticking out to the right
    bm = prism(10, 0.042, 0.042, 0.03)
    paint(bm, shade_by_normal("metal.5", "metal.3", "metal.2", rng, side_alt="metal.4"))
    make_object("Reel", bm, (0, -0.18, -0.06), (0, math.pi / 2, 0))
    bm = box((0.012, 0.02, 0.04))
    paint(bm, lambda f: "metal.2")
    make_object("ReelFoot", bm, (0, -0.18, -0.03))
    bm = box((0.05, 0.008, 0.008))
    paint(bm, lambda f: "metal.1")
    make_object("ReelArm", bm, (0.04, -0.18, -0.06))
    bm = box((0.012, 0.012, 0.03))
    paint(bm, lambda f: "wood.2")
    make_object("ReelKnob", bm, (0.065, -0.18, -0.045))
    block_hand("y", grip=0.0)
    # the blank, in three sections, thinning to the tip
    blank = ("wood.2", "wood.1", "wood.0")
    _section("Butt", 6, 0.013, 0.01, 0.6, 0.23, blank, rng)
    _section("Mid", 6, 0.01, 0.006, 0.55, 0.83, blank, rng)
    _section("Tip", 5, 0.006, 0.0025, 0.45, 1.38, blank, rng)
    for i, y in enumerate((0.55, 0.95, 1.25, 1.55, 1.8)):  # line guides: little rings under the blank
        bm = prism(6, 0.009 - i * 0.001, 0.009 - i * 0.001, 0.004)
        paint(bm, lambda f: "metal.5")
        make_object(f"Guide{i}", bm, (0, y, -0.012), (0, 0, 0))
    export("rod")


def fishing_float():
    """The float: a red-capped body with a white belly and a thin antenna, its origin at the
    waterline (the belly sits under the surface)."""
    reset()
    rng = seeded(7)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.5)
    for v in bm.verts:
        v.co.x *= 0.045
        v.co.y *= 0.045
        v.co.z *= 0.09 if v.co.z > 0 else 0.07
    paint(bm, lambda f: "accent.1" if f.calc_center_median().z > 0.005 else "neutral.6")
    make_object("Body", bm)
    bm = prism(5, 0.005, 0.003, 0.08)
    paint(bm, lambda f: "accent.3")
    make_object("Antenna", bm, (0, 0, 0.07))
    bm = prism(6, 0.006, 0.006, 0.006)
    paint(bm, lambda f: "neutral.1")
    make_object("Ring", bm, (0, 0, 0.004))
    export("fishing_float")


# --- fish -------------------------------------------------------------------------------------
# One mesh per fish ("Fish"), head toward +Y (Godot -Z, forward), origin at the body centre, so
# the swim shader can wiggle it by distance along the body. Length in metres.

def fish_mesh(length, width, height, tail_taper=0.85, snout=1.0, dorsal=1.0):
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
    # dorsal: `dorsal` > 1 stretches it into a sail (grayling), forward and up
    fin_tri(bm, (0.0, length * 0.12 * dorsal, height * 0.42), (0.0, -length * 0.12, height * (0.42 + 0.26 * dorsal)),
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


def fish(name, length, width, height, painter, tail_taper=0.85, snout=1.0, dorsal=1.0):
    reset()
    bm = fish_mesh(length, width, height, tail_taper, snout, dorsal)
    paint(bm, painter)
    make_object("Fish", bm)
    export(os.path.join("fish", name))


def perch():
    rng = seeded(21)
    fish("perch", 0.24, 0.07, 0.1, fish_painter("leaves.4", "leaves.6", "accent.3", "accent.2", rng,
                                                bars="leaves.1", length=0.24))


def trout():
    rng = seeded(22)
    fish("trout", 0.34, 0.08, 0.1, fish_painter("leaves.1", "metal.6", "neutral.7", "leaves.2", rng,
                                                stripe="accent.7", length=0.34))


def pike():
    rng = seeded(23)
    fish("pike", 0.7, 0.1, 0.11, fish_painter("leaves.2", "leaves.4", "wood.7", "leaves.3", rng,
                                              spots="accent.3", length=0.7), tail_taper=0.7, snout=0.55)


def arctic_char():
    """Deep-water fish of the lake: dark back, pale spots, a bright orange belly."""
    rng = seeded(24)
    fish("char", 0.44, 0.09, 0.11, fish_painter("metal.1", "metal.3", "accent.2", "accent.1", rng,
                                               spots="neutral.6", length=0.44), tail_taper=0.8, snout=0.85)


def grayling():
    """River fish: slate-silver with dark flecks and the tall violet sail of a dorsal fin."""
    rng = seeded(25)
    fish("grayling", 0.36, 0.075, 0.1, fish_painter("metal.2", "metal.4", "metal.6", "accent.6", rng,
                                                    spots="metal.1", length=0.36), tail_taper=0.82, dorsal=2.0)


def salmon():
    """The big river fish: a long silver body, a blue-grey back speckled black, a hooked snout."""
    rng = seeded(26)
    fish("salmon", 0.82, 0.13, 0.17, fish_painter("metal.2", "metal.6", "neutral.6", "metal.3", rng,
                                                  spots="neutral.1", length=0.82), tail_taper=0.75, snout=0.8)


# --- item models (for icons, later maybe for pickups) -----------------------------------------

def log_item():
    reset()
    rng = seeded(31)
    bm = prism(6, 0.09, 0.085, 0.42)
    jitter(bm, 0.05, rng)
    paint(bm, lambda f: "wood.7" if abs(f.normal.z) > 0.9 else ("wood.3" if rng.random() < 0.6 else "wood.2"))
    make_object("Item", bm, rotation=(math.pi / 2, 0, 0.3))  # lying down
    export(os.path.join("items", "wood"))


def oak_item():
    reset()
    rng = seeded(33)
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
    """Iron ore: a chunk of basalt column, glinting iron where it broke."""
    ore_chunk("iron", 34, ("stone.3", "stone.2"), "metal.3", ("metal.6", "ore.iron"), 0.85, size=0.14)


def log_item_variant(name, seed, bark, end_grain, radius=0.09):
    reset()
    rng = seeded(seed)
    bm = prism(6, radius, radius * 0.95, 0.42)
    jitter(bm, 0.05, rng)
    paint(bm, lambda f: end_grain if abs(f.normal.z) > 0.9 else (bark[0] if rng.random() < 0.6 else bark[1]))
    make_object("Item", bm, rotation=(math.pi / 2, 0, 0.3))  # lying down
    export(os.path.join("items", name))


def ore_chunk(name, seed, skin, fresh, ore, ore_share, size=0.13):
    """An ore pickup: a chunk knocked out of its rock, flat fresh breaks all round (ore on a
    share of them, `ore` (lit, shaded) swatches, the rest `fresh` stone) over a weathered underside
    of the rock's skin (`skin` (lit, shaded)), shaded like the rocks (bake_weathering). The breaks
    face up, so the ore is what shows lying on the ground and in its icon."""
    reset()
    rng = seeded(seed)
    bm = blob(size, rng, jitter_amount=0.15, squash=(1.1, 0.95, 0.85), subdiv=2)
    bmesh.ops.translate(bm, vec=Vector((0, 0, size)), verts=bm.verts)
    cut = bm.faces.layers.int.new("cut")
    for k in range(6):  # the breaks: over the top and round the sides, the underside left weathered
        a = k * math.tau / 5 + rng.uniform(-0.3, 0.3)
        n = Vector((math.cos(a), math.sin(a), rng.uniform(0.1, 0.9))).normalized() if k < 5 else Vector((0, 0, 1))
        chop(bm, Vector((0, 0, size)) + n * size * rng.uniform(0.5, 0.72), n, as_cut=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    veins = {f.index for f in bm.faces if f[cut] and rng.random() < ore_share}
    paint(bm, lambda f: (ore[0] if f.normal.z > -0.3 else ore[1]) if f.index in veins
          else fresh if f[cut] else (skin[0] if f.normal.z > 0.4 else skin[1]))
    bake_weathering(bm, cut, BVHTree.FromBMesh(bm), 2 * size, moss_amount=0.3, reach=size)
    bmesh.ops.translate(bm, vec=Vector((0, 0, -size)), verts=bm.verts)
    make_object("Item", bm)
    export(os.path.join("items", name), loose_edges=True)


def more_items():
    log_item_variant("birch", 35, ("neutral.7", "neutral.5"), "wood.7", 0.08)
    log_item_variant("pine", 36, ("wood.1", "wood.2"), "wood.6", 0.1)
    ore_chunk("coal", 37, ("neutral.3", "neutral.2"), "stone.5", ("ore.coal", "ore.coal"), 0.9)
    ore_chunk("gold", 38, ("wood.3", "wood.2"), "neutral.6", ("ore.gold", "accent.3"), 0.7)


def ore_item():
    """Copper ore: a chunk of the verdigris boulder."""
    ore_chunk("ore", 32, ("leaves.5", "stone.4"), "stone.6", ("ore.copper", "ore.copper_dark"), 0.7)


# --- pond scenery -----------------------------------------------------------------------------

def reeds():
    """A clump of tapered reed blades with a few cattail heads. Origin at the base (on the bed)."""
    reset()
    rng = seeded(41)
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
    rng = seeded(42)
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
    rng = seeded(43)
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
    rng = seeded(44)
    bm = smooth_blob(0.28, rng, lumpy=0.26, squash=(1.2, 1.0, 0.55), subdiv=2)
    paint(bm, shade_by_normal("stone.5", "stone.4", "stone.3", rng))
    make_object("Stone", weathered(bm, (0, 0, 0.06), moss_amount=0.9, soil=0.6))  # (by the water: mossy)
    export(os.path.join("scenery", "shore_stone"), loose_edges=True)


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
    rng = seeded(51)
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
    rng = seeded(seed)
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
    rng = seeded(seed)
    for i, (loc, r) in enumerate(blobs):
        bm = blob(r, rng, jitter_amount=0.22, squash=(1.0, 1.0, 0.8))
        leafy(bm, rng, shades, card_size=0.45, density=4.0, core=(0.75, 0.75, 0.75))
        spherical_normals(make_object(f"Blob{i}", bm, loc), squash=(1.0, 1.0, 0.8))
    merge_all("Bush")
    export(os.path.join("scenery", name))


def boulder(name, seed, size, squash):
    reset()
    rng = seeded(seed)
    bm = smooth_blob(size, rng, lumpy=0.24, squash=squash, subdiv=3)
    paint(bm, shade_by_normal("stone.5", "stone.4", "stone.3", rng))
    make_object("Boulder", weathered(bm, (0, 0, size * squash[2] * 0.6), soil=1.0))  # sunk a little into the ground
    merge_all("Boulder")
    export(os.path.join("scenery", name), loose_edges=True)


# --- forest scenery: the Pinewood's canopy and floor (not gatherable) --------------------------

def canopy_pine(name, seed, height, cones, needles):
    """A background pine in the game pine's look (pine_classic): taller, darker and one merged
    mesh, its cones' rims ragged and drooping. cones: (radius, height, z) per cone of needles,
    bottom up; needles: (top, side, bottom, side_alt) swatches."""
    reset()
    rng = seeded(seed)
    bm = prism(8, 0.32, 0.1, height)
    for v in bm.verts:  # a little root flare
        if v.co.z < -height / 2 + 0.01:
            v.co.x *= 1.3
            v.co.y *= 1.3
    jitter(bm, 0.05, rng)
    paint(bm, shade_by_normal("wood.2", "wood.1", "wood.0", rng, side_alt="wood.2"))
    make_object("Trunk", bm, (0, 0, height / 2))
    for i, (r, h, z) in enumerate(cones):
        bm = needle_cone(rng, r, h)
        leafy(bm, rng, needles, card_size=0.95, density=3.2, kind=CARD_NEEDLES, core=(0.72, 0.72, 0.92), droop=0.5,
              open_bottom=True)
        spherical_normals(make_object(f"Cone{i}", bm, (0, 0, z), (0, 0, rng.uniform(0, math.tau))),
                          centre=(0, 0, -h * 0.3))
    merge_all("Pine")
    export(os.path.join("scenery", name))


def canopy_birch():
    """A background birch in the game birch's look (birch_airy): a slim white trunk dashed with
    black, small upright clumps up its top half; one merged mesh."""
    reset()
    rng = seeded(61)
    bm = prism(8, 0.16, 0.09, 4.6)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1.0],
                              cuts=7)  # rings up the trunk, for the dashes to sit on
    jitter(bm, 0.03, rng)
    paint(bm, lambda f: "neutral.1" if abs(f.normal.z) < 0.9 and rng.random() < 0.16
          else ("neutral.7" if rng.random() < 0.6 else "neutral.6"))
    make_object("Trunk", bm, (0, 0, 2.3))
    spots = [(0.55, (math.cos(i * 2.2) * 0.4, math.sin(i * 2.2) * 0.4, z)) for i, z in enumerate((2.9, 3.4, 3.85, 4.3))]
    spots.append((0.55, (0.0, 0.0, 4.8)))
    for i, (r, loc) in enumerate(spots):
        bm = blob(r, rng, jitter_amount=0.2, squash=(0.8, 0.8, 1.25))
        leafy(bm, rng, BIRCH_LEAVES, card_size=0.6, density=2.6)
        spherical_normals(make_object(f"Canopy{i}", bm, loc), squash=(0.8, 0.8, 1.25))
    merge_all("Birch")
    export(os.path.join("scenery", "canopy_birch"))


def fern():
    """A low fan of fronds: flat tapering blades arching out from the middle."""
    reset()
    rng = seeded(62)
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
    rng = seeded(63)
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
    canopies()
    fern()
    mushrooms()


def canopies():
    """The forest's background trees."""
    canopy_pine("canopy_pine", 60, 6.5, ((2.1, 2.2, 2.9), (1.65, 2.0, 4.3), (1.15, 1.9, 5.7), (0.6, 1.4, 6.9)),
                ("leaves.1", "leaves.0", "leaves.0", "leaves.1"))
    canopy_pine("canopy_pine_young", 64, 3.6, ((1.3, 1.6, 1.7), (0.95, 1.4, 2.7), (0.55, 1.2, 3.6)),
                ("leaves.2", "leaves.1", "leaves.0", "leaves.2"))
    canopy_birch()


def variants():
    """More of every model a procgen world picks from (models/variants/<name>_v<n>.glb): VARIANTS
    of the ore rocks and choppable trees, spread over the shape families (see recipe()), and
    SCENERY_VARIANTS of the bushes, boulders and background trees. Each is its model built again
    from a shifted seed: the same design, every piece and crack its own."""
    ore_variants()
    tree_variants()
    bake_variants((big_scenery, canopies), SCENERY_VARIANTS)


def ore_variants():
    """Just the ore rocks' variants (see variants()), so they can be rebuilt on their own."""
    bake_variants((rock, iron_rock, coal_rock, gold_rock, crystal_rock), VARIANTS)


def tree_variants():
    """Just the choppable trees' variants (see variants())."""
    bake_variants((tree, birch, oak, pine), VARIANTS)


def bake_variants(builds, count):
    global _variant
    os.makedirs(os.path.join(OUT_DIR, "variants"), exist_ok=True)
    for v in range(1, count + 1):
        _variant = v
        for build in builds:
            build()
    _variant = 0


# --- ruins: the parkour blocks in the clearing ------------------------------------------------
# Each fills exactly the box its collision uses (Godot size x, y, z = width, height, depth), centred
# on the origin, so step / ledge / mantle heights stay what they were with the greybox boxes.

def stone_block(name, size, seed, cap=False):
    """Courses of chunky stone bricks filling a box; staggered joints, a little moss on top."""
    reset()
    rng = seeded(seed)
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
    weather_stonework(ground=None, moss_amount=0.7)  # (blocks stand at any height)
    export(os.path.join("ruins", name), loose_edges=True)


def plank_ramp(name, size, seed):
    """Planks across two long beams, filling the ramp's box."""
    reset()
    rng = seeded(seed)
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
    big_scenery()


def big_scenery():
    """The bushes and boulders: big enough that repeats of one shape are noticed."""
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
              coal_rock, gold_rock, birch, pine, more_items, arctic_char, forest, quarry, farming, road,
              rod, fishing_float, grayling, salmon, tool_tiers)
    only = argv[2:]  # optional: names of the builders to run (e.g. `forest`), instead of all of them
    for build in builds:
        if not only or build.__name__ in only:
            build()
    for build in (designs, tree_designs, variants, ore_variants, tree_variants):  # only when asked for by name: not the game's own models
        if build.__name__ in only:
            build()
