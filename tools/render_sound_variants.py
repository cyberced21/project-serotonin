"""Renders the chop and the pickaxe blow in a few variants, four blows each, so they can be
compared by ear and the closest one picked (needs numpy):

    python tools/render_sound_variants.py [out_dir]

Writes chop_A/B/C.wav and mine_A/B/C.wav (default docs/sound_preview/compare/). A is what
synth_gathering.py bakes for the game; B and C lean each sound one way and the other.
"""
import functools
import os
import sys

import numpy as np

import synth_gathering as G

VARIANTS = {
    "chop_A": functools.partial(G.chop),
    "chop_B": functools.partial(G.chop, tone=0.75, crack=0.8, weight=1.6),  # deeper, chunkier
    "chop_C": functools.partial(G.chop, tone=1.3, crack=1.4, weight=0.7),  # higher, snappier
    "mine_A": functools.partial(G.mine),
    "mine_B": functools.partial(G.mine, ring=1.6, echoes=1.6),  # rings longer, more echo
    "mine_C": functools.partial(G.mine, clink=1.25, ring=0.7, echoes=0.5),  # higher, tighter, drier
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
