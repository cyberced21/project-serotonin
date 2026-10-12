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

ROWS = [
    ("stone", ["#2f2f33", "#45454b", "#5a5a61", "#727279", "#8a8a90", "#a3a3a8", "#bdbdc1", "#d6d6d9"]),
    ("ore", ["#b0643a", "#d98a52", "#8f8f99", "#b9bac6", "#e2b53b", "#262629", "#6fa0d8", "#7a5ec9"]),
    ("wood", ["#3b2618", "#4f3322", "#5f4029", "#734f33", "#8a6142", "#a37a55", "#c2996c", "#dcbc8f"]),
    ("leaves", ["#1f3d22", "#2a5230", "#356a3b", "#3f7f45", "#4f9452", "#64a860", "#7fbd72", "#a3d18c"]),
    ("terrain", ["#5c8c4d", "#6b9a50", "#85674c", "#787573", "#cdbd8c", "#ebeff5", "#4a6b3c", "#a18566"]),
    ("metal", ["#2b3138", "#3c4550", "#525d6b", "#6c7886", "#8994a2", "#a9b2bd", "#c9d0d8", "#e8ecf0"]),
    ("accent", ["#9e2b25", "#d0453a", "#e88a2c", "#f2cf4a", "#3d7fc4", "#64b5e8", "#8d4fb0", "#e66fa1"]),
    ("neutral", ["#0d0d0f", "#232326", "#3a3a3e", "#5e5e63", "#8c8c91", "#b8b8bc", "#e0e0e3", "#ffffff"]),
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
