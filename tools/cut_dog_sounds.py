"""Cuts the dog's sound candidates (plans/dog.md) out of Freesound preview MP3s, for the listening
page and then the game. Blender's bundled Python decodes the MP3s (its `aud` module) and has numpy:

    blender -b --python-exit-code 1 -P tools/cut_dog_sounds.py -- <folder of <id>.mp3> <meta.json> <out folder>

meta.json maps each sound id to {"kind": pant | sniff | whine | woof | shake, ...} (or the
trader's and the tavern's kinds: see MAX_LEN). Every clip is
mixed to mono at 48 kHz, cut to the loudest stretch no longer than its kind's MAX_LEN (a woof:
the loudest single bark), faded in and out, levelled to LOUDNESS (the game sets each kind's mix),
and written as 16-bit WAV <out>/<id>.wav. The recordings are CC0.
"""
import json
import os
import struct
import sys

import aud
import numpy as np

RATE = 48000
LOUDNESS = -20.0  # dBFS RMS over the clip's loud part
## Longest clip per kind (s), and the fades (s).
MAX_LEN = {"pant": 2.6, "sniff": 2.0, "whine": 2.2, "woof": 0.9, "shake": 1.8,
           "cart": 6.0, "snort": 2.5, "trade": 1.4,  # (the trader too: plans/market.md)
           "murmur": 30.0, "fire": 25.0, "laugh": 4.0, "clink": 1.6, "dice": 2.5}  # (and the tavern: plans/tavern.md)
FADE = 0.03

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, META, OUT = argv[0], argv[1], argv[2]
os.makedirs(OUT, exist_ok=True)


def decode(path: str) -> np.ndarray:
    s = aud.Sound(path).resample(RATE, False).rechannel(1)
    return np.asarray(s.data(), dtype=np.float32).reshape(-1)


def loudest(x: np.ndarray, length: float) -> np.ndarray:
    n = int(length * RATE)
    if len(x) <= n:
        return x
    c = np.concatenate([[0.0], np.cumsum(x.astype(np.float64) ** 2)])
    start = int(np.argmax(c[n:] - c[:-n]))  # (a running sum: the energy in every window)
    return x[start:start + n]


def one_bark(x: np.ndarray, length: float) -> np.ndarray:
    """The loudest peak, from just before its onset to where it dies away (at most `length`)."""
    win = int(0.01 * RATE)
    c = np.concatenate([[0.0], np.cumsum(x.astype(np.float64) ** 2)])
    env = np.sqrt(np.maximum(c[win:] - c[:-win], 0.0) / win)
    peak = int(np.argmax(env))
    floor = env[peak] * 0.03
    a = peak
    while a > 0 and env[a] > floor and peak - a < int(0.15 * RATE):
        a -= 1
    b = peak
    while b < len(env) - 1 and (env[b] > floor or b - a < int(0.35 * RATE)) and b - a < int(length * RATE):
        b += 1  # (at least 0.35 s: the bark's ring)
    return x[max(a - int(0.01 * RATE), 0):b]


def level(x: np.ndarray) -> np.ndarray:
    x = x - np.mean(x)
    win = int(0.05 * RATE)
    frames = [x[i:i + win] for i in range(0, max(len(x) - win, 1), win)] or [x]
    rms = np.array([np.sqrt(np.mean(f * f)) for f in frames])
    loud = np.mean(rms[rms >= np.percentile(rms, 60)]) if len(rms) > 1 else rms[0]
    x = x * (10 ** (LOUDNESS / 20.0) / max(loud, 1e-6))
    peak = np.max(np.abs(x))
    return x * (0.89 / peak) if peak > 0.89 else x


def fade(x: np.ndarray) -> np.ndarray:
    n = min(int(FADE * RATE), len(x) // 4)
    if n > 0:
        ramp = np.linspace(0.0, 1.0, n, dtype=np.float32)
        x[:n] *= ramp
        x[-n:] *= ramp[::-1]
    return x


def write_wav(path: str, x: np.ndarray) -> None:
    pcm = (np.clip(x, -1.0, 1.0) * 32767).astype("<i2").tobytes()
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", len(pcm)) + pcm)


meta = json.load(open(META))
for sid, m in meta.items():
    x = decode(os.path.join(SRC, sid + ".mp3"))
    kind = m["kind"]
    clip = one_bark(x, MAX_LEN[kind]) if kind == "woof" else loudest(x, MAX_LEN[kind])
    clip = fade(level(clip.copy()))
    write_wav(os.path.join(OUT, sid + ".wav"), clip)
    print(f"{sid} {kind:6} {len(x) / RATE:6.1f}s -> {len(clip) / RATE:4.2f}s")
