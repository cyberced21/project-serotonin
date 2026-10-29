"""Draws tools/village_layout.gd's JSON as a top-down PNG: buildings per tier (tier 3 outline,
shown tier filled), spots, props, roads, trees and rocks, and the walking graph if there is one.
    python tools/plot_village.py layout.json village.png [--tier=3] [--mark=x,z,label ...]
North (-Z) is up. 1 m = SCALE px."""
import json
import sys

from PIL import Image, ImageDraw

CENTER = (100.0, 40.0)
HALF = 46.0
SCALE = 14


def to_px(x, z):
    return ((x - CENTER[0] + HALF) * SCALE, (z - CENTER[1] + HALF) * SCALE)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    tier = "3"
    marks = []
    for a in sys.argv[3:]:
        if a.startswith("--tier="):
            tier = a[7:]
        elif a.startswith("--mark="):
            x, z, label = a[7:].split(",", 2)
            marks.append((float(x), float(z), label))
    d = json.load(open(src, encoding="utf-8"))
    size = int(HALF * 2 * SCALE)
    img = Image.new("RGB", (size, size), (222, 230, 200))
    g = ImageDraw.Draw(img)
    # 5 m grid
    for i in range(-45, 46, 5):
        c = (205, 214, 184) if i % 10 else (190, 200, 170)
        x0, _ = to_px(CENTER[0] + i, 0)
        _, z0 = to_px(0, CENTER[1] + i)
        g.line([(x0, 0), (x0, size)], fill=c)
        g.line([(0, z0), (size, z0)], fill=c)
        if i % 10 == 0:
            g.text((x0 + 2, 2), str(int(CENTER[0] + i)), fill=(120, 120, 100))
            g.text((2, z0 + 2), str(int(CENTER[1] + i)), fill=(120, 120, 100))
    # square and pond
    cx, cz = to_px(*CENTER)
    r = 7.5 * SCALE
    g.ellipse([cx - r, cz - r, cx + r, cz + r], fill=(214, 196, 160))
    px, pz = to_px(88, 64)
    r = 7.0 * SCALE
    g.ellipse([px - r, pz - r, px + r, pz + r], fill=(150, 190, 215))
    for name, pts in d["roads"].items():
        g.line([to_px(x, z) for x, z in pts], fill=(196, 170, 120), width=int(2.6 * SCALE))
    for b in d["boxes"]:
        if b["tag"] == "node":
            x, z = to_px(*b["at"])
            col = (60, 120, 60) if "Tree" in b["name"] else (130, 130, 130)
            g.ellipse([x - 9, z - 9, x + 9, z + 9], fill=col)
            continue
        x0, z0, x1, z1 = b["r"]
        col = {"Village/Props": (150, 110, 70), "Village/Decor": (170, 90, 140), "PathLamps": (230, 170, 40)}.get(b["tag"], (110, 110, 160))
        g.rectangle([to_px(x0, z0), to_px(x1, z1)], outline=col, width=2)
    for b in d["buildings"]:
        for t, boxes in b["tiers"].items():
            for box in boxes:
                x0, z0, x1, z1 = box["r"]
                if t == tier:
                    g.rectangle([to_px(x0, z0), to_px(x1, z1)], fill=(176, 120, 96), outline=(110, 70, 50))
        x, z = to_px(*b["at"])
        g.text((x - 20, z - 6), b["id"], fill=(20, 20, 20))
    graph = d.get("graph") or {}
    pts = graph.get("points", {})
    for a, b in graph.get("links", []):
        g.line([to_px(*pts[a]), to_px(*pts[b])], fill=(40, 90, 200), width=3)
    for k, p in pts.items():
        x, z = to_px(*p)
        g.ellipse([x - 5, z - 5, x + 5, z + 5], fill=(40, 90, 200))
        g.text((x + 6, z - 12), k, fill=(20, 50, 150))
    for s in d["spots"]:
        x, z = to_px(*s["at"])
        fx, fz = s["face"]
        g.ellipse([x - 4, z - 4, x + 4, z + 4], fill=(200, 40, 40))
        g.line([(x, z), (x + fx * 14, z + fz * 14)], fill=(200, 40, 40), width=2)
        g.text((x + 5, z + 2), s["name"][:6], fill=(150, 20, 20))
    for x, z, label in marks:
        x, z = to_px(x, z)
        g.rectangle([x - 6, z - 6, x + 6, z + 6], outline=(0, 0, 0), width=3)
        g.text((x + 8, z - 6), label, fill=(0, 0, 0))
    img.save(dst)


if __name__ == "__main__":
    main()
