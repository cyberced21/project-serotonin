"""Cuts the mining and woodcutting sound effects out of the Sonniss GDC 2026 game audio bundle.

The bundle can't be redistributed, so it isn't in the project: download it, then run (Blender's
bundled Python has numpy, which this needs):

    blender -b --python-exit-code 1 -P tools/cut_sounds.py -- <bundle folder> audio/mining/sfx
    blender -b --python-exit-code 1 -P tools/cut_sounds.py -- <bundle folder> audio/woodcutting/sfx woodcutting

Each RECIPE takes clips out of one source file: the takes in it (split where it goes quiet), or
evenly spaced slices of a continuous texture, or just the swoosh before a swing's impact. Every clip
is mixed to mono, resampled to 48 kHz, trimmed, faded and normalised, and written as 16-bit WAV
named <layer>_NN.wav. Licence: Sonniss GDC bundle, royalty free for games, no attribution needed.
"""
import os
import struct
import sys

import numpy as np

RATE = 48000
MIN_TAKE = 0.08  # shorter "takes" are clicks, not sounds
LOUDNESS = -14.0  # dBFS, the loudest 50 ms of every clip (the layer stacks then set the mix)

# (layer, source file name, how to cut it, at most this many clips, longest clip in seconds)
#   takes  - one clip per take, split where the sound drops away
#   slices - the busiest stretches of a continuous sound
#   whoosh - the swing before each impact (each loudest moment)
#   whole  - the whole file, trimmed
# One source per layer, so its variations differ in detail, not in kind (mixing a case dropped on
# concrete with body punches made every hit a different recipe).
RECIPES = [
    ("hit_crack", "ice, crack, ice block snapping-001.wav", "takes", 5, 0.45),
    ("hit_tink", "GOREMisc_Concrete_MetalPipe02_InMotionAudio_SinisterTextures5.wav", "whole", 1, 0.4),
    ("hit_thump", "FGHTImpt_4 x Punch, Body 02_344 Audio_Cinematic Fight Vol 1.wav", "takes", 4, 0.5),
    ("hit_gravel", "FOODMisc_Broom Sweeping Up Snacks On Hard Floor 2_344 Audio_CInema Experience.wav", "slices", 5, 0.45),
    ("pull_scrape", "GOREMisc_Cladding_Scratch06_InMotionAudio_SinisterTextures5.wav", "takes", 3, 0.6),
    ("pull_pebbles", "GAMEBoard_Event Board Reset Organic Multiple Pieces Wood Small 02_ESM_BG.wav", "whole", 1, 0.9),
    ("swing_whoosh", "SWSH_SWING IMPACTS Quick Heavy Weapon Swing To Thud Impact Var 01_DDUMAIS_MWP2.wav", "whoosh", 5, 0.3),
    ("windup_creak", "FOLYClth_ClothMovement29_InMotionAudio_FoleyT-Shirt.wav", "takes", 2, 0.6),
    ("crack_split", "ice, surface cracking, fissure, fast, hard-003.wav", "takes", 4, 0.6),
    ("split_crunch", "GORESplt_Gore Designed Transient Heavy Impact Smash 01_ESM_HALG.wav", "whole", 1, 1.2),
    ("split_rubble", "Woosh Debris.wav", "whole", 1, 1.8),
    ("debris_tick", "GAMEBoard_Game Play Piece Action Organic Connect Dots Fall Bounce 04_ESM_BG.wav", "whole", 1, 0.2),
]

# Woodcutting. The bundle has no forestry pack, so these are the woodiest things in it: a heavy
# wooden door hit for the axe's thunk, wooden staff hits for the bite of the edge, a whip crack for
# a clean cut, a creaking wooden seat for the trunk, pine branches crackling for its fibres giving
# way, wind through trees for the crown rushing down, and a pile of books slumping over a low boom
# for it landing.
WOOD_RECIPES = [
    ("chop_thunk", "WOODImpt_Wooden Hit, Dark, Heavy Hit, Vampire's Prison_344 Audio_Haunting Ambiences Vol 3.wav", "takes", 4, 0.5),
    ("chop_bite", "WEAPBlnt_Spear And Stick Impact, Wooden MKH 2_344 Audio_Medieval Weapons Vol 2.wav", "takes", 4, 0.3),
    ("clean_crack", "WEAPWhip_WHIP Snap Crack 05_DDUMAIS_MWP2.wav", "takes", 2, 0.35),
    ("chip_scatter", "GAMEBoard_Event Board Reset Organic Multiple Pieces Wood Small 02_ESM_BG.wav", "slices", 2, 0.5),
    ("trunk_creak", "FOLYProp_Sitting Down, Creaky Seat, Squeaks 3_344 Audio_CInema Experience.wav", "takes", 3, 1.2),
    ("fibre_tear", "24 Campfire, Dropping Fresh Pine Branches in Fire, Crackling, Sizzling Strong, Close 02.wav", "slices", 2, 1.1),
    ("crown_rush", "AMBPark_Berlin City Humboldthain Park Strong Wind On Trees Foliage Traffic Wash 03_ESM_CPS.wav", "slices", 2, 2.2),
    ("land_slump", "PAPRMisc_Pile Of Antique Books Falling Over 8_344 Audio_Antiques - Books.wav", "whole", 1, 1.6),
    ("land_boom", "EffectiveTrailer_Booms_Vol2_011.wav", "whole", 1, 1.8),
]
SETS = {"mining": RECIPES, "woodcutting": WOOD_RECIPES}


def read_wav(path):
    """(samples as float32 [frames, channels], sample rate). PCM 16/24/32 or float 32."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a WAV file")
    pos, fmt, body = 12, None, None
    while pos + 8 <= len(data):
        cid, size = struct.unpack_from("<4sI", data, pos)
        chunk = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            tag, ch, rate, _, _, bits = struct.unpack_from("<HHIIHH", chunk)
            if tag == 0xFFFE:  # extensible: the real format is in the sub-format GUID
                tag = struct.unpack_from("<H", chunk, 24)[0]
            fmt = (tag, ch, rate, bits)
        elif cid == b"data":
            body = chunk
        pos += 8 + size + (size & 1)
    tag, ch, rate, bits = fmt
    if tag == 3 and bits == 32:
        x = np.frombuffer(body, dtype="<f4").astype(np.float32)
    elif bits == 16:
        x = np.frombuffer(body, dtype="<i2").astype(np.float32) / 32768.0
    elif bits == 24:
        b = np.frombuffer(body[: len(body) // 3 * 3], dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v >= 1 << 23, v - (1 << 24), v)
        x = v.astype(np.float32) / float(1 << 23)
    elif bits == 32:
        x = np.frombuffer(body, dtype="<i4").astype(np.float32) / float(1 << 31)
    else:
        raise ValueError(f"unsupported WAV format {tag}/{bits}")
    return x[: len(x) // ch * ch].reshape(-1, ch), rate


def to_mono_48k(x, rate):
    """Mono, at 48 kHz: low-passed (windowed sinc) and decimated, or linearly resampled."""
    mono = x.mean(axis=1)
    if rate == RATE:
        return mono
    if rate % RATE == 0:
        k = rate // RATE
        taps = np.arange(-64, 65)
        h = np.sinc(taps / k) * np.hamming(len(taps))
        h /= h.sum()
        return np.convolve(mono, h, mode="same")[::k]
    t = np.arange(0, len(mono) * RATE / rate) * rate / RATE
    return np.interp(t, np.arange(len(mono)), mono)


def envelope(x, window=0.005):
    n = max(int(RATE * window), 1)
    return np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same"))


def takes(x, max_len, floor_db=-32.0, gap=0.06):
    """(start, end) of each take: loud stretches split by `gap` s below floor_db of the peak."""
    env = envelope(x)
    loud = env > env.max() * 10 ** (floor_db / 20)
    out, i, n, quiet = [], 0, len(x), int(gap * RATE)
    while i < n:
        if not loud[i]:
            i += 1
            continue
        start, j, silent = max(i - int(0.004 * RATE), 0), i, 0
        while j < n and silent < quiet:
            silent = 0 if loud[j] else silent + 1
            j += 1
        end = min(j - silent + int(0.02 * RATE), start + int(max_len * RATE), n)
        if end - start > int(0.03 * RATE):
            out.append((start, end))
        i = j
    return out


def loudness(clip, window=0.05):
    """How loud a short sound feels: the RMS of its loudest 50 ms."""
    n = min(int(window * RATE), len(clip))
    return np.sqrt(np.convolve(clip * clip, np.ones(n) / n, mode="valid")).max()


def finish(clip):
    """Faded in and out, and brought to the same loudness as every other clip (LOUDNESS), with a
    soft limit on peaks so a sharp click can't stick out above a dense crackle (or clip)."""
    clip = clip - clip.mean()
    fade_in, fade_out = min(int(0.002 * RATE), len(clip) // 4), min(int(0.03 * RATE), len(clip) // 3)
    clip[:fade_in] *= np.linspace(0, 1, fade_in)
    clip[len(clip) - fade_out:] *= np.linspace(1, 0, fade_out)
    level = loudness(clip)
    if level <= 0:
        return clip
    clip = clip * (10 ** (LOUDNESS / 20) / level)
    knee, ceiling = 10 ** (-6 / 20), 10 ** (-1 / 20)
    over = np.abs(clip) > knee  # above the knee, peaks are bent smoothly toward the ceiling
    clip[over] = np.sign(clip[over]) * (knee + (ceiling - knee) * np.tanh((np.abs(clip[over]) - knee) / (ceiling - knee)))
    return clip


def cut(x, how, count, max_len):
    if how == "whole":
        found = takes(x, max_len, floor_db=-45.0, gap=0.25)
        return [x[found[0][0]:found[0][1]]] if found else []
    if how == "slices":  # the busiest stretches of it, not overlapping (a texture has pauses)
        length = int(max_len * RATE)
        run = np.concatenate(([0.0], np.cumsum(x.astype(np.float64) ** 2)))
        energy = run[length:] - run[:-length]  # (a running sum: long ambiences stay quick)
        starts = []
        for i in np.argsort(-energy[:: length // 8]) * (length // 8):
            if all(abs(i - s) >= length for s in starts):
                starts.append(int(i))
            if len(starts) == count:
                break
        return [x[s:s + length] for s in sorted(starts)]
    if how == "whoosh":
        # the swing is much quieter than the hit that ends it, so find the hits (the loudest
        # moments, at least a second apart) and take the max_len just before each
        env = envelope(x, 0.01)
        hits, order = [], np.argsort(-env)
        for i in order:
            if env[i] < env[order[0]] * 0.25 or len(hits) >= count:
                break
            if all(abs(i - h) > RATE for h in hits):
                hits.append(int(i))
        return [x[max(h - int((max_len + 0.015) * RATE), 0): h - int(0.015 * RATE)] for h in sorted(hits)]
    found = [se for se in takes(x, max_len) if se[1] - se[0] >= int(MIN_TAKE * RATE)]
    found.sort(key=lambda se: -np.abs(x[se[0]:se[1]]).max())  # the strongest takes
    return [x[start:end] for start, end in sorted(found[:count])]


def write_wav(path, clip):
    pcm = (np.clip(clip, -1, 1) * 32767).astype("<i2").tobytes()
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, RATE, RATE * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", len(pcm)) + pcm)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    bundle, out_dir = args[0], args[1]
    recipes = SETS[args[2] if len(args) > 2 else "mining"]
    os.makedirs(out_dir, exist_ok=True)
    layers = {r[0] for r in recipes}
    for old in os.listdir(out_dir):  # this script's own clips only: recipes may make fewer now
        if old.endswith(".wav") and old.rsplit("_", 1)[0] in layers:
            os.remove(os.path.join(out_dir, old))
    paths = {name: os.path.join(d, name) for d, _, names in os.walk(bundle) for name in names}
    counts = {}
    for layer, name, how, count, max_len in recipes:
        if name not in paths:
            print("MISSING", name)
            continue
        x, rate = read_wav(paths[name])
        mono = to_mono_48k(x, rate)
        for clip in cut(mono, how, count, max_len):
            if len(clip) < int(0.02 * RATE):
                continue
            counts[layer] = counts.get(layer, 0) + 1
            path = os.path.join(out_dir, f"{layer}_{counts[layer]:02d}.wav")
            write_wav(path, finish(clip.copy()))
            print(f"{os.path.basename(path)}  {len(clip) / RATE:5.2f}s  from {name[:60]}")


main()
