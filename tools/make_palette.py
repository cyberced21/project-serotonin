"""Builds the shared palette atlas: art/palette.png (+ art/palette.json with swatch UVs).

    python tools/make_palette.py

An 8x8 grid of flat colour swatches, 8 px each (64x64). Every model in the game maps its faces
onto these swatches (in Blender: select faces, scale their UVs to a point inside a swatch), so the
whole world shares one texture + one material, and recolouring something is a palette edit.

Rows are families. Keep a swatch's position stable once models use it — models store UVs, not
names. palette.json lists each swatch's name and its centre UV for scripts (e.g. Blender).
"""
import json
import os

from PIL import Image

CELL = 8
GRID = 8
OUT = os.path.join(os.path.dirname(__file__), "..", "art")

# Colours taken from the Quaternius CC0 packs' textures (plans/home.md, 2026-10-29, the "gentle"
# pick): their hue and saturation at our old lightness steps; greens moved halfway, sapphire and
# amethyst kept so the ores stay apart.
ROWS = [
    ("stone", ["#362e26", "#4a453e", "#615951", "#7d7163", "#95897a", "#aea293", "#c9bbab", "#e3d4c2"]),
    ("ore", ["#b26336", "#e78252", "#8f8f99", "#b9bac6", "#edb04a", "#262629", "#6fa0d8", "#7a5ec9"]),
    ("wood", ["#442207", "#543113", "#663d1c", "#794d29", "#8e5f39", "#ab774d", "#cc9568", "#f0b583"]),
    ("leaves", ["#283c12", "#38511b", "#486826", "#577c30", "#69913d", "#7ca54b", "#94ba5b", "#b0cf70"]),
    ("terrain", ["#678b36", "#74993c", "#866749", "#787573", "#d1bc85", "#ebeff5", "#516b20", "#9f8666"]),
    ("metal", ["#372e33", "#48424a", "#605a62", "#7b757d", "#979199", "#b6afb7", "#d3cdd6", "#eceaf5"]),
    ("accent", ["#94371d", "#bf5634", "#e38c48", "#ffc660", "#647cae", "#99afc5", "#66678b", "#da7998"]),
    ("neutral", ["#100c0c", "#272221", "#3f393a", "#645c62", "#928a8d", "#c2b6ad", "#e7dfdc", "#fffff7"]),
]

NAMES = {
    "ore": ["copper_dark", "copper", "iron_dark", "iron", "gold", "coal", "sapphire", "amethyst"],
    "terrain": ["grass", "grass_light", "dirt", "rock", "sand", "snow", "moss", "path"],
}


def main():
    img = Image.new("RGB", (CELL * GRID, CELL * GRID))
    swatches = {}
    for r, (family, colors) in enumerate(ROWS):
        names = NAMES.get(family, [str(i) for i in range(GRID)])
        for c, hexcol in enumerate(colors):
            rgb = tuple(int(hexcol[i:i + 2], 16) for i in (1, 3, 5))
            for y in range(CELL):
                for x in range(CELL):
                    img.putpixel((c * CELL + x, r * CELL + y), rgb)
            swatches[f"{family}.{names[c]}"] = {
                "uv": [(c + 0.5) / GRID, (r + 0.5) / GRID],
                "color": hexcol,
            }
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, "palette.png"))
    with open(os.path.join(OUT, "palette.json"), "w", newline="\n") as f:
        json.dump({"grid": GRID, "swatches": swatches}, f, indent=1)
    print("wrote art/palette.png and art/palette.json,", len(swatches), "swatches")


if __name__ == "__main__":
    main()
