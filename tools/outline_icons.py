"""Adds a dark outline around every icon in art/icons/ (needs Pillow). Run after render_icons.py:

    python tools/outline_icons.py [id ...]

Name item ids to outline only those icons (the rest are already outlined).

The outline is the icon's silhouette grown by WIDTH pixels, drawn underneath it, so icons read
on top of any background.
"""
import glob
import os
import sys

from PIL import Image, ImageFilter

WIDTH = 3
COLOR = (18, 18, 22, 235)
ICONS = os.path.join(os.path.dirname(__file__), "..", "art", "icons")

only = sys.argv[1:]
for path in glob.glob(os.path.join(ICONS, "*.png")):
    if only and os.path.splitext(os.path.basename(path))[0] not in only:
        continue
    icon = Image.open(path).convert("RGBA")
    alpha = icon.split()[3].point(lambda a: 255 if a > 40 else 0)
    grown = alpha.filter(ImageFilter.MaxFilter(WIDTH * 2 + 1))
    out = Image.new("RGBA", icon.size, COLOR)
    out.putalpha(grown.point(lambda a: COLOR[3] if a else 0))
    out.alpha_composite(icon)
    out.save(path)
    print("outlined", os.path.basename(path))
