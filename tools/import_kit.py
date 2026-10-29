"""Copies Quaternius Medieval Village kit pieces (CC0) into art/kit/village/ for kit_buildings.py,
with their textures as JPEGs (the kit's PNGs are ~60 MB) and the .gltf files pointed at them.

    python tools/import_kit.py PACK_GLTF_DIR [piece ...]

PACK_GLTF_DIR is the kit's glTF folder (from medieval_village_megakitstandard.zip). With no pieces
named, copies every piece kit_buildings.py's tables mention plus anything already in art/kit/village.
"""
import json
import os
import re
import shutil
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DEST = os.path.join(ROOT, "art", "kit", "village")
QUALITY = 88


def used_pieces():
    src = open(os.path.join(ROOT, "tools", "blender", "kit_buildings.py"), encoding="utf-8").read()
    names = set(re.findall(r'"((?:Wall|Window|Door|Floor|Roof|Corner|Prop|Stair|Balcony|Overhang|HoleCover)[A-Za-z0-9_]*)', src))
    have = {f[:-5] for f in os.listdir(DEST) if f.endswith(".gltf")} if os.path.isdir(DEST) else set()
    return names | have


def main():
    pack = sys.argv[1]
    pieces = sys.argv[2:] or sorted(used_pieces())
    available = {f[:-5] for f in os.listdir(pack) if f.endswith(".gltf")}
    # roof and gable sizes are built from f-strings: copy every size of those families
    families = [p for p in pieces if p.endswith("_") or p in ("Roof_RoundTiles", "Roof_Front_Brick")]
    pieces = [p for p in pieces if p in available]
    for fam in families:
        pieces += [a for a in available if a.startswith(fam) and not a.endswith(("_L", "_R"))]
    os.makedirs(DEST, exist_ok=True)
    textures = set()
    for p in sorted(set(pieces)):
        with open(os.path.join(pack, p + ".gltf"), encoding="utf-8") as f:
            data = json.load(f)
        for img in data.get("images", []):
            textures.add(img["uri"])
            img["uri"] = os.path.splitext(img["uri"])[0] + ".jpg"
            img["mimeType"] = "image/jpeg"
        for buf in data.get("buffers", []):
            shutil.copy(os.path.join(pack, buf["uri"]), os.path.join(DEST, buf["uri"]))
        with open(os.path.join(DEST, p + ".gltf"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=1)
    for t in sorted(textures):
        out = os.path.join(DEST, os.path.splitext(t)[0] + ".jpg")
        Image.open(os.path.join(pack, t)).convert("RGB").save(out, quality=QUALITY)
    print(f"copied {len(set(pieces))} pieces and {len(textures)} textures to {DEST}")


if __name__ == "__main__":
    main()
