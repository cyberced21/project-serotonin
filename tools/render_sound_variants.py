"""Renders the chop and the pickaxe blow in a few variants, four blows each, so they can be
compared by ear and the closest one picked (needs numpy):

    python tools/render_sound_variants.py [out_dir]

Writes chop_A..D.wav and mine.wav (default docs/sound_preview/compare/). chop_A and mine are
what synth_gathering.py bakes for the game; the other chops lean it different ways.
"""
import functools
import os
import sys

import numpy as np

import synth_gathering as G

VARIANTS = {
    "chop_A": functools.partial(G.chop),  # the picked bite, its crack louder: what the game plays
    "chop_B": functools.partial(G.chop, crack=4.2),  # the crack louder still
    "chop_C": functools.partial(G.chop, snap=1.8),  # a longer, brighter crack
    "chop_D": functools.partial(G.chop, crack=3.6, snap=1.5, wedge=0.7),  # crack-led, less chunk under it
    "mine": functools.partial(G.mine),  # the one picked (B of the last round): what the game plays
}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(G.ROOT, "docs", "sound_preview", "compare")
    os.makedirs(out_dir, exist_ok=True)
    for name, build in VARIANTS.items():
        rng = np.random.default_rng(5)
        out = np.zeros(G.secs(4.6))
        for i in range(4):
            G.at(out, G.finish(build(rng)), 0.3 + 0.9 * i)
        G.write_wav(os.path.join(out_dir, name + ".wav"), out)
        print(name)


if __name__ == "__main__":
    main()
