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
    "chop_A": functools.partial(G.chop),  # the picked bite, sinking in: what the game plays
    "chop_B": functools.partial(G.chop, sink=2.2),  # sinks deeper and longer
    "chop_C": functools.partial(G.chop, sink=1.6, tone=1.05, weight=1.3),  # sinks, with more body under it
    "chop_D": functools.partial(G.chop, sink=2.6, wedge=1.3),  # drives right in, heavy wedge
    "chop_last": functools.partial(G.chop, sink=0.0),  # last round's C, for comparison
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
