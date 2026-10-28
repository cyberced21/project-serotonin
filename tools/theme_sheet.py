"""Theme contact sheet: renders tools/theme_gallery.gd once per theme (one row of nodes each, seen
close) and tiles the shots into one labelled image, docs/images/themes/<label>.png.

    python tools/theme_sheet.py --godot <godot console exe> --nodes rock,iron_rock --label rocks
    python tools/theme_sheet.py ... --themes plain,pinewood,frostpeak --copies 2 --hit 2
    python tools/theme_sheet.py ... --nodes rock,iron_rock --themes plain --looks --per-node

--looks shows each node in all its baked looks, grouped by shape family; --per-node gives each
node its own tile instead of each theme (with one theme).

Themes default to "plain" and every data/themes/*.tres. The single shots are deleted once tiled.
"""
import argparse
import os
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ap = argparse.ArgumentParser()
ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
ap.add_argument("--nodes", default="rock")
ap.add_argument("--themes", default="")
ap.add_argument("--copies", default="2")
ap.add_argument("--gap", default="2.8")
ap.add_argument("--hit", default="0")
ap.add_argument("--view", default="22")
ap.add_argument("--label", default="sheet")
ap.add_argument("--columns", type=int, default=3)
ap.add_argument("--looks", action="store_true")
ap.add_argument("--per-node", action="store_true")
args = ap.parse_args()

themes = args.themes.split(",") if args.themes else ["plain"] + sorted(
    f[:-5] for f in os.listdir(os.path.join(ROOT, "data", "themes")) if f.endswith(".tres"))
shots = os.path.join(ROOT, "docs", "images", "themes", args.label)
os.makedirs(shots, exist_ok=True)
tiles = []
if args.per_node:  # (title, nodes, theme) per tile
    runs = [(n, n, themes[0]) for n in args.nodes.split(",")]
else:
    runs = [(t, args.nodes, t) for t in themes]
for title, nodes, theme in runs:
    title = title.replace("/", "_")  # (rare/<id> themes)
    name = f"{args.label}/{title}"
    subprocess.run([args.godot, "--path", ROOT, "--screen", "1", "--resolution", "1280x720",
                    "-s", "res://tools/theme_gallery.gd", "--", f"--nodes={nodes}",
                    f"--themes={theme}", f"--copies={args.copies}", f"--gap={args.gap}",
                    f"--hit={args.hit}", f"--view={args.view}", f"--label={name}"]
                   + (["--looks"] if args.looks else []),
                   check=True, timeout=300, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    tiles.append((title, Image.open(os.path.join(shots, title + ".png")).convert("RGB")))
    print("shot", title)

w, h = 640, 360
cols = min(args.columns, len(tiles))
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * h), (20, 20, 20))
draw = ImageDraw.Draw(sheet)
font = ImageFont.load_default(size=22)
for i, (theme, img) in enumerate(tiles):
    x, y = i % cols * w, i // cols * h
    sheet.paste(img.resize((w, h)), (x, y))
    draw.rectangle((x, y, x + 12 + draw.textlength(theme, font=font), y + 32), fill=(0, 0, 0))
    draw.text((x + 6, y + 4), theme, fill=(255, 255, 255), font=font)
out = os.path.join(ROOT, "docs", "images", "themes", args.label + ".png")
sheet.save(out)
shutil.rmtree(shots)
print("saved", out)
