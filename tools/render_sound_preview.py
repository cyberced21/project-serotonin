"""Renders a short listening preview of the gathering sounds (needs numpy), so they can be judged
by ear without playing:

    python tools/render_sound_preview.py OUT.wav [--dry]

Plays the layer stacks the way ResourceNode does: four axe blows on an oak, the clean cut and the
trunk landing; then three pickaxe blows on iron, a blow on a crack tip and one that splits a
piece off; then the same on crystal. `--dry` leaves out the reverberant layers (bloom, clink) and
is roughly how it sounded before them. The in-game SFX bus adds a little more room on top.
"""
import os
import re
import sys
import wave

import numpy as np

RATE = 48000
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
WET_LAYERS = ("bloom", "clink")
rng = np.random.default_rng(3)


def randomizer(path):
    """The clips an AudioStreamRandomizer .tres picks from."""
    text = open(os.path.join(ROOT, path.replace("res://", ""))).read()
    clips = []
    for p in re.findall(r'path="([^"]+\.wav)"', text):
        with wave.open(os.path.join(ROOT, p.replace("res://", ""))) as w:
            clips.append(np.frombuffer(w.readframes(w.getnframes()), "<i2") / 32768.0)
    return clips, float((re.search(r"random_volume_offset_db = ([\d.]+)", text) or [0, 0])[1])


def stack(path, dry):
    text = open(os.path.join(ROOT, path)).read()
    streams = {i: p for p, i in re.findall(r'path="([^"]+\.tres)" id="([^"]+)"', text)}
    layers = []
    for block in re.split(r"\n\[sub_resource", text)[1:]:
        if dry and re.search(rf'resource_name = "({"|".join(WET_LAYERS)})"', block):
            continue
        get = lambda key, d: float((re.search(rf"^{key} = ([-\d.]+)", block, re.M) or [0, d])[1])
        clips, offset = randomizer(streams[re.search(r'stream = ExtResource\("([^"]+)"\)', block)[1]])
        layers.append({"clips": clips, "offset": offset, "delay": get("delay", 0.0), "volume": get("volume_db", 0.0),
                       "pitch": get("pitch", 1.0), "jitter": get("pitch_jitter", 0.0),
                       "follows": "follows_pitch = false" not in block})
    return layers


def play(out, layers, at, gain_db=0.0, pitch=1.0):
    for L in layers:
        clip = L["clips"][rng.integers(len(L["clips"]))]
        p = L["pitch"] * (pitch if L["follows"] else 1.0) * (1 + rng.uniform(-L["jitter"], L["jitter"]))
        clip = np.interp(np.arange(0, len(clip) - 1, p), np.arange(len(clip)), clip)
        start = int((at + L["delay"]) * RATE)
        end = min(start + len(clip), len(out))
        out[start:end] += clip[: end - start] * 10 ** ((L["volume"] + gain_db) / 20)


def main():
    path, dry = sys.argv[1], "--dry" in sys.argv[2:]
    out = np.zeros(RATE * 22)
    wood = {k: stack(f"audio/woodcutting/{d}{k}.tres", dry)
            for k, d in (("axe_hit", "oak/"), ("clean_cut", ""), ("tree_land", "oak/"))}
    for i in range(4):
        play(out, wood["axe_hit"], 0.5 + 0.9 * i, pitch=1.0 + 0.03 * i)
    play(out, wood["clean_cut"], 4.1)
    play(out, wood["tree_land"], 6.0)
    for k, ore in enumerate(("iron", "crystal")):
        hit, tip, split = (stack(f"audio/mining/{ore}/{s}.tres", dry) for s in ("pickaxe_hit", "crack_tip", "split"))
        t0 = 10.0 + 6.0 * k
        for i in range(3):
            play(out, hit, t0 + 0.85 * i, pitch=1.0 + 0.05 * i)
        play(out, hit, t0 + 2.55, -6.0, 1.1)  # a crack tip: the hit ducked under the crack running
        play(out, tip, t0 + 2.55, pitch=1.12)
        play(out, hit, t0 + 3.4, -9.0, 1.15)  # a piece splitting off
        play(out, split, t0 + 3.4)
    out *= 10 ** (-1 / 20) / max(np.abs(out).max(), 1e-9)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((out * 32767).astype("<i2").tobytes())
    print(path, "dry" if dry else "with the reverberant layers")


if __name__ == "__main__":
    main()
