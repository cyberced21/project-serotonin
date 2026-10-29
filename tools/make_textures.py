"""Generates the game's surface textures: small, tileable, chunky greyscale detail that shaders
multiply over the palette colours (Valheim-style: low-res, nearest-filtered, painterly).

    python tools/make_textures.py

Writes, into art/textures/:
  detail.png   one 128 px slice per palette row (stone, ore, wood, leaves, terrain, metal, accent,
               neutral), stacked vertically: a Texture2DArray read by node_surface.gdshader and the
               sway shaders (the row a face's UV sits in picks its slice)
  ground.png   terrain slices (grass, dirt, rock, sand, snow, forest floor, path, field) for
               terrain.gdshader
  leaves.png   leaf-card slices (broadleaf cluster, pine needles), greyscale with alpha cut-outs,
               for the tree canopies (node_foliage.gdshader)
Greyscale, mean about 0.5: shaders scale colour by 1 + (d - 0.5) * strength.
Deterministic: the same code makes the same pixels. Every pattern tiles (noise is made in
frequency space or with wrapped distances, so it repeats at the edges).
"""
import os

import numpy as np
from PIL import Image

SIZE = 128
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "textures")


# --- tileable building blocks ------------------------------------------------------------------

def spectral(rng, size=SIZE, beta=2.0, sx=1.0, sy=1.0, lo=1.0, hi=None):
    """Tileable 1/f^beta noise, normalised to 0..1. sx/sy stretch it (sy < sx: vertical streaks),
    lo/hi band-limit it (in cycles per tile)."""
    fx = np.fft.fftfreq(size) * size
    kx, ky = np.meshgrid(fx * sx, fx * sy)
    k = np.sqrt(kx * kx + ky * ky)
    amp = np.where(k < lo, 0.0, 1.0 / np.maximum(k, 1e-6) ** (beta / 2.0))
    if hi is not None:
        amp *= np.exp(-(k / hi) ** 4)
    phase = rng.uniform(0, 2 * np.pi, (size, size))
    n = np.real(np.fft.ifft2(amp * np.exp(1j * phase)))
    return norm(n)


def worley(rng, cells, size=SIZE):
    """Tileable cellular noise: returns (F1, F2, cell id) arrays, distances in cell units."""
    pts = rng.uniform(0, size, (cells, 2))
    ys, xs = np.mgrid[0:size, 0:size].astype(float)
    d = np.full((cells, size, size), 1e9)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xs - px)
        dy = np.abs(ys - py)
        dx = np.minimum(dx, size - dx)
        dy = np.minimum(dy, size - dy)
        d[i] = np.sqrt(dx * dx + dy * dy)
    order = np.argsort(d, axis=0)
    ds = np.take_along_axis(d, order[:2], axis=0)
    scale = size / np.sqrt(cells)
    return ds[0] / scale, ds[1] / scale, order[0]


def norm(a):
    a = a - a.min()
    return a / max(a.max(), 1e-9)


def posterize(a, levels):
    return np.round(a * (levels - 1)) / (levels - 1)


def blur(a, r=1):
    """Box blur that wraps at the edges (keeps tiling)."""
    out = np.zeros_like(a)
    n = 0
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out += np.roll(np.roll(a, dy, 0), dx, 1)
            n += 1
    return out / n


def centre(a, contrast=1.0):
    """Shift to mean 0.5 and scale the spread, clipped to 0..1."""
    return np.clip(0.5 + (a - a.mean()) * contrast, 0.0, 1.0)


def speckle(rng, density, size=SIZE):
    return (rng.uniform(0, 1, (size, size)) < density).astype(float)


# --- materials ---------------------------------------------------------------------------------

def stone(rng):
    f1, f2, ids = worley(rng, 34)
    cracks = np.clip((f2 - f1) * 6.0, 0, 1)                # dark seams between plates
    plates = (ids * 0.6180339 % 1.0)                         # each plate a slightly different tone
    blot = spectral(rng, beta=2.2)
    a = 0.45 * plates + 0.35 * blot + 0.2 * spectral(rng, beta=1.0, lo=12)
    a = a * (0.55 + 0.45 * cracks)
    return centre(posterize(blur(norm(a)), 7), 0.9)


def ore(rng):
    a = 0.6 * spectral(rng, beta=2.0) + 0.4 * spectral(rng, beta=0.8, lo=10)
    a += 0.5 * speckle(rng, 0.02) - 0.35 * speckle(rng, 0.03)
    return centre(posterize(norm(a), 6), 0.8)


def wood(rng):
    # Bark / grain: long vertical streaks, a few dark fissures, knots.
    streak = spectral(rng, beta=2.0, sx=1.0, sy=8.0)
    fine = spectral(rng, beta=1.0, sx=1.0, sy=6.0, lo=8)
    fissure = 1.0 - np.clip((spectral(rng, beta=1.6, sx=1.0, sy=10.0) - 0.62) * 6.0, 0, 1)
    a = 0.55 * streak + 0.3 * fine + 0.15 * spectral(rng, beta=2.5)
    a = a * (0.6 + 0.4 * fissure)
    return centre(posterize(norm(a), 7), 0.85)


def leaves(rng):
    # Clumps of leaves: each cell a rounded blob, lit from above, dark gaps between.
    f1, f2, ids = worley(rng, 60)
    blob = np.clip(1.0 - f1 * 1.4, 0, 1)
    gap = np.clip((f2 - f1) * 4.0, 0, 1)
    tone = ids * 0.381966 % 1.0
    a = 0.5 * blob + 0.25 * tone + 0.25 * gap
    a = a * (0.7 + 0.3 * spectral(rng, beta=2.4))
    return centre(posterize(norm(a), 6), 0.9)


def terrain_generic(rng):
    a = 0.5 * spectral(rng, beta=2.2) + 0.5 * spectral(rng, beta=0.9, lo=14)
    return centre(posterize(norm(a), 6), 0.7)


def metal(rng):
    brushed = spectral(rng, beta=1.2, sx=10.0, sy=1.0, lo=4)
    scratches = speckle(rng, 0.004)
    scratches = np.maximum(scratches, np.roll(scratches, 1, 1))
    a = 0.7 * brushed + 0.3 * spectral(rng, beta=2.5) + 0.4 * scratches
    return centre(posterize(norm(a), 6), 0.45)


def cloth(rng):
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    weave = 0.5 + 0.25 * np.sign(np.sin(xs * np.pi / 2)) * np.sign(np.sin(ys * np.pi / 2))
    a = 0.45 * weave + 0.55 * spectral(rng, beta=2.0)
    return centre(posterize(norm(a), 6), 0.5)


def neutral(rng):
    a = 0.6 * spectral(rng, beta=2.0) + 0.4 * spectral(rng, beta=1.0, lo=12)
    return centre(posterize(norm(a), 6), 0.5)


# --- ground (terrain) ----------------------------------------------------------------------------

def grass(rng):
    # Tufts of blades: short vertical dashes on a mottled base.
    base = 0.6 * spectral(rng, beta=2.2) + 0.4 * spectral(rng, beta=1.0, lo=10)
    blades = spectral(rng, beta=1.0, sx=1.0, sy=3.0, lo=10, hi=40)
    a = 0.6 * base + 0.4 * (blades > 0.6)
    return centre(posterize(blur(norm(a)), 6), 0.8)


def dirt(rng):
    clods = worley(rng, 70)[0]
    a = 0.4 * spectral(rng, beta=2.3) + 0.35 * (1.0 - np.clip(clods, 0, 1)) + 0.25 * spectral(rng, beta=0.8, lo=16)
    a += 0.3 * speckle(rng, 0.01) - 0.3 * speckle(rng, 0.02)
    return centre(posterize(norm(a), 6), 0.85)


def sand(rng):
    ripples = spectral(rng, beta=2.0, sx=1.0, sy=5.0, lo=3)
    a = 0.5 * ripples + 0.5 * spectral(rng, beta=0.5, lo=24)
    return centre(posterize(norm(a), 6), 0.5)


def snow(rng):
    a = 0.7 * spectral(rng, beta=2.6) + 0.3 * spectral(rng, beta=1.0, lo=16)
    a += 0.25 * speckle(rng, 0.006)
    return centre(posterize(norm(a), 5), 0.35)


def forest_floor(rng):
    f1, f2, ids = worley(rng, 90)
    needles = spectral(rng, beta=0.5, sx=2.0, sy=0.5, lo=18)
    a = 0.35 * spectral(rng, beta=2.2) + 0.35 * (ids * 0.618 % 1.0) * np.clip(1 - f1, 0, 1) + 0.3 * needles
    return centre(posterize(norm(a), 6), 0.9)


def path(rng):
    f1, f2, _ = worley(rng, 40)
    pebbles = np.clip(1.0 - f1 * 1.8, 0, 1)
    a = 0.5 * spectral(rng, beta=2.0) + 0.35 * pebbles + 0.15 * spectral(rng, beta=0.7, lo=20)
    return centre(posterize(norm(a), 6), 0.75)


def field(rng):
    rows = spectral(rng, beta=1.8, sx=8.0, sy=1.0, lo=2)
    a = 0.5 * rows + 0.5 * spectral(rng, beta=0.7, lo=16)
    return centre(posterize(norm(a), 6), 0.7)


# --- leaf cards ----------------------------------------------------------------------------------

def _leaf_shape(xs, ys, cx, cy, angle, length, width):
    """Pointed leaf: (inside mask, along 0..1 from stem to tip, across -1..1)."""
    c, s_ = np.cos(angle), np.sin(angle)
    dx, dy = xs - cx, ys - cy
    u = (dx * c + dy * s_) / length          # along the leaf, 0 at the stem
    v = (-dx * s_ + dy * c) / width          # across
    half = np.sin(np.clip(u, 0, 1) * np.pi) ** 0.8  # widest in the middle, pointed at both ends
    inside = (u > 0) & (u < 1) & (np.abs(v) < half)
    return inside, u, v / np.maximum(half, 1e-6)


def broadleaf(rng, size=SIZE):
    """A cluster of leaves on twigs, filling a rough disc: grey (the palette colours it), alpha 1
    in the leaves, 0 in the gaps."""
    ys, xs = np.mgrid[0:size, 0:size].astype(float)
    grey = np.zeros((size, size))
    alpha = np.zeros((size, size))
    c = size / 2
    for _ in range(70):
        r = np.sqrt(rng.uniform(0, 1)) * size * 0.36
        a = rng.uniform(0, 2 * np.pi)
        cx, cy = c + np.cos(a) * r, c + np.sin(a) * r
        ang = a + rng.uniform(-0.9, 0.9)           # leaves point out from the middle
        ln = rng.uniform(16, 26)
        inside, u, v = _leaf_shape(xs, ys, cx - np.cos(ang) * ln * 0.3, cy - np.sin(ang) * ln * 0.3, ang, ln,
                                   ln * rng.uniform(0.28, 0.4))
        tone = rng.uniform(0.55, 1.0)
        shade = tone * (0.82 + 0.18 * u) * np.where(v > 0, 1.0, 0.86)   # one half lit, one in shade
        shade = np.where(np.abs(v) < 0.12, shade * 0.75, shade)          # midrib
        grey = np.where(inside, shade, grey)
        alpha = np.where(inside, 1.0, alpha)
    grey = posterize(np.clip(grey, 0, 1), 6)
    return grey, alpha


def needles(rng, size=SIZE):
    """A spray of pine needles: a few twigs with short dark strokes along both sides."""
    ys, xs = np.mgrid[0:size, 0:size].astype(float)
    grey = np.zeros((size, size))
    alpha = np.zeros((size, size))
    c = size / 2
    for _ in range(7):
        a = rng.uniform(0, 2 * np.pi)
        x0, y0 = c + rng.uniform(-10, 10), c + rng.uniform(-10, 10)
        length = rng.uniform(34, 52)
        for t in np.linspace(0.05, 1.0, 26):
            px, py = x0 + np.cos(a) * length * t, y0 + np.sin(a) * length * t
            for side in (-1, 1):
                na = a + side * rng.uniform(0.6, 1.1)
                nl = rng.uniform(7, 12) * (1.15 - 0.4 * t)
                inside, u, v = _leaf_shape(xs, ys, px, py, na, nl, 1.6)
                tone = rng.uniform(0.5, 1.0) * (0.85 + 0.15 * u)
                grey = np.where(inside, tone, grey)
                alpha = np.where(inside, 1.0, alpha)
    grey = posterize(np.clip(grey, 0, 1), 5)
    return grey, alpha


# --- cut from the CC0 kit's own textures (plans/mine.md: tiles picked on a page, look "D") -------
# Our stone, wood and plaster share the grain of the Quaternius village kit's (art/kit/village/), so
# our models sit beside the kit's houses: a patch of its texture, greyed, made to tile, posterized.

KIT = os.path.join(os.path.dirname(__file__), "..", "art", "kit", "village")


def tileable(a):
    """Cross-fades a patch with itself shifted half a tile, so its edges meet."""
    n = a.shape[0]
    shifted = np.roll(np.roll(a, n // 2, 0), n // 2, 1)
    ys, xs = np.mgrid[0:n, 0:n] / (n - 1)
    w = np.minimum(np.minimum(xs, 1 - xs), np.minimum(ys, 1 - ys)) * 2  # 0 at the edges, 1 mid-tile
    w = np.clip(w * 2.5, 0, 1)
    return a * w + shifted * (1 - w)


def from_kit(name, box, contrast, turn=False):
    im = Image.open(os.path.join(KIT, name)).convert("L").crop(box).resize((SIZE, SIZE), Image.LANCZOS)
    a = tileable(np.asarray(im, float) / 255.0)
    a = a.T if turn else a  # (the kit's planks run across its sheet; our grain runs up)
    return centre(posterize(norm(a), 8), contrast)


def kit_stone(_rng):
    return from_kit("T_RockTrim_BaseColor.jpg", (0, 330, 230, 560), 1.2)


def kit_wood(_rng):
    return from_kit("T_WoodTrim_BaseColor.jpg", (0, 0, 290, 290), 1.3, turn=True)


def kit_plaster(_rng):
    return from_kit("T_Plaster_BaseColor.jpg", (0, 0, 512, 512), 1.6)


DETAIL = [kit_stone, ore, kit_wood, leaves, terrain_generic, metal, cloth, kit_plaster]
GROUND = [grass, dirt, stone, sand, snow, forest_floor, path, field]


def stack(fns, seed):
    slices = []
    for i, fn in enumerate(fns):
        rng = np.random.default_rng(seed * 100 + i)
        slices.append(fn(rng))
    return np.vstack(slices)


def save_rgba(slices, name):
    grey = np.vstack([g for g, _ in slices])
    alpha = np.vstack([a for _, a in slices])
    g8 = (np.clip(grey, 0, 1) * 255).astype(np.uint8)
    rgba = np.dstack([g8, g8, g8, (alpha * 255).astype(np.uint8)])
    img = Image.fromarray(rgba, "RGBA")
    path_ = os.path.join(OUT, name)
    img.save(path_)
    print("wrote", os.path.normpath(path_), img.size)


def save(a, name):
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "L")
    path_ = os.path.join(OUT, name)
    img.save(path_)
    print("wrote", os.path.normpath(path_), img.size)


def main():
    os.makedirs(OUT, exist_ok=True)
    save(stack(DETAIL, 1), "detail.png")
    save(stack(GROUND, 2), "ground.png")
    save_rgba([broadleaf(np.random.default_rng(301)), needles(np.random.default_rng(302))], "leaves.png")


if __name__ == "__main__":
    main()
