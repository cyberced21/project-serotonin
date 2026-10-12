"""Adds a dark outline around every icon in art/icons/ (needs Pillow). Run after render_icons.py:

    python tools/outline_icons.py

The outline is the icon's silhouette grown by WIDTH pixels, drawn underneath it, so icons read
on top of any background.
"""
import glob
import os

from PIL import Image, ImageFilter

WIDTH = 3
COLOR = (18, 18, 22, 235)
ICONS = os.path.join(os.path.dirname(__file__), "..", "art", "icons")

for path in glob.glob(os.path.join(ICONS, "*.png")):
    icon = Image.open(path).convert("RGBA")
    alpha = icon.split()[3].point(lambda a: 255 if a > 40 else 0)
    grown = alpha.filter(ImageFilter.MaxFilter(WIDTH * 2 + 1))
    out = Image.new("RGBA", icon.size, COLOR)
    out.putalpha(grown.point(lambda a: COLOR[3] if a else 0))
    out.alpha_composite(icon)
    out.save(path)
    print("outlined", os.path.basename(path))
