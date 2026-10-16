"""Mixes the mining sound events offline, many times over with random variations, and reports how
loud each comes out and how much that varies, so the mix can be checked without listening.

    blender -b -P tools/measure_mix.py

Reads the layer stacks in audio/mining/ (each layer's randomizer, delay, volume, pitch and jitter)
and mirrors how ResourceNode plays them: a plain hit, a hit on a crack tip (the hit ducked under the
crack sound) and a hit that splits a piece off (the hit ducked further, the split on top). Loudness
is the loudest 50 ms of the mix (RMS, dBFS): roughly how loud a short impact feels.
"""
import os
import re
import struct
import sys

import numpy as np

RATE = 48000
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TRIALS = 150
rng = np.random.default_rng(1)

# Mirrors ResourceNode._hit_sounds(): how far the plain hit is ducked when a bigger sound plays,
# and how much quieter a crack creaking on plays.
HIT_DUCK_TIP = -6.0
HIT_DUCK_SPLIT = -9.0
CRACK_CREAK_DB = -12.0


def res(path):
    return os.path.join(ROOT, path.replace("res://", ""))


def read_clip(path):
    data = open(path, "rb").read()
    return np.frombuffer(data[44:], dtype="<i2").astype(np.float32) / 32768.0


def randomizer(path):
    text = open(res(path)).read()
    ids = dict(re.findall(r'path="([^"]+)" id="([^"]+)"', text))
    clips = [read_clip(res(p)) for p in ids]
    offset = float((re.search(r"random_volume_offset_db = ([\d.]+)", text) or [0, 0])[1])
    return clips, offset


def stack(name):
    text = open(os.path.join(ROOT, "audio", "mining", name + ".tres")).read()
    streams = {i: p for p, i in re.findall(r'path="([^"]+\.tres)" id="([^"]+)"', text)}
    layers = []
    for block in re.split(r"\n\[sub_resource", text)[1:]:
        get = lambda key, d: float((re.search(rf"^{key} = ([-\d.]+)", block, re.M) or [0, d])[1])
        sid = re.search(r'stream = ExtResource\("([^"]+)"\)', block)[1]
        clips, offset = randomizer(streams[sid])
        layers.append({"clips": clips, "offset": offset, "delay": get("delay", 0.0), "volume": get("volume_db", 0.0),
                       "pitch": get("pitch", 1.0), "jitter": get("pitch_jitter", 0.0),
                       "follows": "follows_pitch = false" not in block})
    return layers


def render(layers, gain_db=0.0, pitch=1.0, length=2.0):
    out = np.zeros(int(length * RATE), dtype=np.float32)
    for L in layers:
        clip = L["clips"][rng.integers(len(L["clips"]))]
        p = L["pitch"] * (pitch if L["follows"] else 1.0) * (1 + rng.uniform(-L["jitter"], L["jitter"]))
        resampled = np.interp(np.arange(0, len(clip) - 1, p), np.arange(len(clip)), clip)  # pitch by speed
        g = 10 ** ((L["volume"] + gain_db + rng.uniform(-L["offset"], L["offset"])) / 20)
        start = int(L["delay"] * RATE)
        end = min(start + len(resampled), len(out))
        out[start:end] += resampled[: end - start] * g
    return out


def loudness(x, window=0.05):
    n = int(window * RATE)
    rms = np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="valid"))
    return 20 * np.log10(rms.max() + 1e-9)


def report(label, make):
    values = np.array([loudness(make()) for _ in range(TRIALS)])
    print(f"{label:28s} mean {values.mean():6.1f} dB   min {values.min():6.1f}   max {values.max():6.1f}"
          f"   spread {values.max() - values.min():5.1f} dB   (90% within {np.percentile(values, 95) - np.percentile(values, 5):4.1f})")
    return values.mean()


hit, tip, split, pull = stack("pickaxe_hit"), stack("crack_tip"), stack("split"), stack("pickaxe_pull")
swing, debris = stack("pickaxe_swing"), stack("debris_stone")
duck = "--no-duck" not in sys.argv
print("ducking", "on" if duck else "off (as before)")
a = report("hit", lambda: render(hit, 0.0, rng.uniform(1.0, 1.2)))
if duck:
    report("hit, crack creaking on", lambda: render(hit, 0.0, rng.uniform(1.0, 1.2)) + render(tip, CRACK_CREAK_DB, 1.12))
b = report("hit on a crack tip", lambda: render(hit, HIT_DUCK_TIP if duck else 0.0, 1.1) + render(tip, 0.0, 1.0 + 0.12 * rng.integers(1, 3)))
c = report("hit that splits a piece", lambda: render(hit, HIT_DUCK_SPLIT if duck else 0.0, 1.15) + render(split)
           + (0 if duck else render(tip, 0.0, 1.36)))
report("pull-out", lambda: render(pull, 0.0, rng.uniform(1.0, 1.1)))
report("swing", lambda: render(swing))
report("debris tick", lambda: render(debris))
print(f"tip hit is {b - a:+.1f} dB over a plain hit, a split {c - a:+.1f} dB")
