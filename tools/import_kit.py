"""Copies Quaternius kit pieces (CC0) into art/kit/<kit>/ for kit_buildings.py, with their
textures as JPEGs no bigger than 1024 px (the packs' PNGs run to ~60 MB) and the .gltf files
pointed at them.

    python tools/import_kit.py village PACK_GLTF_DIR [piece ...]
    python tools/import_kit.py props PACK_GLTF_DIR [piece ...]

village: the Medieval Village MegaKit's glTF folder; with no pieces named, copies every piece
kit_buildings.py mentions plus anything already copied. props: the Fantasy Props MegaKit's
Exports/glTF folder (with its Textures copied beside the .gltf files); with no pieces named,
copies them all (every prop was picked, plans/home.md).
"""
import json
import os
import re
import shutil
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
QUALITY = 88
MAX_SIZE = 1024


def used_pieces(dest):
    src = open(os.path.join(ROOT, "tools", "blender", "kit_buildings.py"), encoding="utf-8").read()
    names = set(re.findall(r'"((?:Wall|Window|Door|Floor|Roof|Corner|Prop|Stair|Balcony|Overhang|HoleCover)[A-Za-z0-9_]*)', src))
    have = {f[:-5] for f in os.listdir(dest) if f.endswith(".gltf")} if os.path.isdir(dest) else set()
    return names | have


def main():
    kit, pack = sys.argv[1], sys.argv[2]
    dest = os.path.join(ROOT, "art", "kit", kit)
    available = {f[:-5] for f in os.listdir(pack) if f.endswith(".gltf")}
    pieces = sys.argv[3:]
    if not pieces:
        pieces = sorted(available) if kit == "props" else sorted(used_pieces(dest))
    # roof and gable sizes are built from f-strings: copy every size of those families
    families = [p for p in pieces if p.endswith("_") or p in ("Roof_RoundTiles", "Roof_Front_Brick")]
    pieces = [p for p in pieces if p in available]
    for fam in families:
        pieces += [a for a in available if a.startswith(fam) and not a.endswith(("_L", "_R"))]
    os.makedirs(dest, exist_ok=True)
    textures = set()
    for p in sorted(set(pieces)):
        with open(os.path.join(pack, p + ".gltf"), encoding="utf-8") as f:
            data = json.load(f)
        for img in data.get("images", []):
            textures.add(img["uri"])
            img["uri"] = os.path.splitext(img["uri"])[0] + ".jpg"
            img["mimeType"] = "image/jpeg"
        for buf in data.get("buffers", []):
            shutil.copy(os.path.join(pack, buf["uri"]), os.path.join(dest, buf["uri"]))
        with open(os.path.join(dest, p + ".gltf"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=1)
    for t in sorted(textures):
        out = os.path.join(dest, os.path.splitext(t)[0] + ".jpg")
        im = Image.open(os.path.join(pack, t)).convert("RGB")
        if max(im.size) > MAX_SIZE:
            im = im.resize((MAX_SIZE, MAX_SIZE * im.size[1] // im.size[0]), Image.LANCZOS)
        im.save(out, quality=QUALITY)
    print(f"copied {len(set(pieces))} pieces and {len(textures)} textures to {dest}")


if __name__ == "__main__":
    main()
