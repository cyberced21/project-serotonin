"""Cuts the mining sound effects out of the Sonniss GDC 2026 game audio bundle.

The bundle can't be redistributed, so it isn't in the project: download it, then run (Blender's
bundled Python has numpy, which this needs):

    blender -b --python-exit-code 1 -P tools/cut_sounds.py -- <bundle folder> audio/mining/sfx

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

# (layer, source file name, how to cut it, at most this many clips, longest clip in seconds)
#   takes  - one clip per take, split where the sound drops away
#   slices - evenly spaced slices of a continuous sound
#   whoosh - each take up to (not including) its loudest moment: the swing before the hit
#   whole  - the whole file, trimmed
RECIPES = [
    ("hit_crack", "ice, crack, ice block snapping-001.wav", "takes", 5, 0.45),
    ("hit_tink", "GOREMisc_Concrete_MetalPipe02_InMotionAudio_SinisterTextures5.wav", "whole", 1, 0.4),
    ("hit_tink", "METLImpt_Metal Old File Impact Tap Against Tire Iron Metallic Hit 01_ESM_HDGM.wav", "whole", 1, 0.4),
    ("hit_thump", "OBJLug_CaseDown_Concrete12_InMotionAudio_InstrumentCase.wav", "takes", 1, 0.6),
    ("hit_thump", "FGHTImpt_4 x Punch, Body 02_344 Audio_Cinematic Fight Vol 1.wav", "takes", 4, 0.5),
    ("hit_gravel", "FOODMisc_Broom Sweeping Up Snacks On Hard Floor 2_344 Audio_CInema Experience.wav", "slices", 5, 0.45),
    ("pull_scrape", "GOREMisc_Cladding_Scratch06_InMotionAudio_SinisterTextures5.wav", "takes", 3, 0.6),
    ("pull_scrape", "GOREMisc_Cladding_NailScratch19_InMotionAudio_SinisterTextures5.wav", "takes", 2, 0.6),
    ("pull_pebbles", "GAMEBoard_Event Board Reset Organic Multiple Pieces Wood Small 02_ESM_BG.wav", "whole", 1, 0.9),
    ("pull_pebbles", "Arrow Hit Rattle.wav", "whole", 1, 0.9),
    ("swing_whoosh", "SWSH_SWING IMPACTS Quick Heavy Weapon Swing To Thud Impact Var 01_DDUMAIS_MWP2.wav", "whoosh", 5, 0.3),
    ("windup_creak", "OBJLug_Handle_Movement15_InMotionAudio_InstrumentCase.wav", "whole", 1, 0.8),
    ("windup_creak", "FOLYClth_ClothMovement29_InMotionAudio_FoleyT-Shirt.wav", "takes", 2, 0.6),
    ("crack_split", "ice, surface cracking, fissure, fast, hard-003.wav", "takes", 4, 0.6),
    ("split_crunch", "GORESplt_Gore Designed Transient Heavy Impact Smash 01_ESM_HALG.wav", "whole", 1, 1.2),
    ("split_crunch", "ICEBrk_Skill Freeze Whoosh Break Impact Layered Movement Shatter 03_ESM_TDG.wav", "whole", 1, 1.4),
    ("split_rubble", "Woosh Debris.wav", "whole", 1, 1.8),
    ("split_rubble", "GAMEBoard_Event Board Reset Organic Multiple Pieces Wood Small 02_ESM_BG.wav", "whole", 1, 0.9),
    ("debris_tick", "GAMEBoard_Game Play Piece Action Organic Connect Dots Fall Bounce 04_ESM_BG.wav", "whole", 1, 0.2),
    ("debris_tick", "Arrow Hit Rattle.wav", "takes", 3, 0.15),
]


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


def finish(clip):
    """Faded in and out, peak normalised to -1 dBFS."""
    clip = clip - clip.mean()
    fade_in, fade_out = min(int(0.002 * RATE), len(clip) // 4), min(int(0.03 * RATE), len(clip) // 3)
    clip[:fade_in] *= np.linspace(0, 1, fade_in)
    clip[len(clip) - fade_out:] *= np.linspace(1, 0, fade_out)
    peak = np.abs(clip).max()
    return clip * (10 ** (-1 / 20) / peak) if peak > 0 else clip


def cut(x, how, count, max_len):
    if how == "whole":
        found = takes(x, max_len, floor_db=-45.0, gap=0.25)
        return [x[found[0][0]:found[0][1]]] if found else []
    if how == "slices":  # the busiest stretches of it, not overlapping (a texture has pauses)
        length = int(max_len * RATE)
        energy = np.convolve(x * x, np.ones(length), mode="valid")
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
    os.makedirs(out_dir, exist_ok=True)
    layers = {r[0] for r in RECIPES}
    for old in os.listdir(out_dir):  # this script's own clips only: recipes may make fewer now
        if old.endswith(".wav") and old.rsplit("_", 1)[0] in layers:
            os.remove(os.path.join(out_dir, old))
    paths = {name: os.path.join(d, name) for d, _, names in os.walk(bundle) for name in names}
    counts = {}
    for layer, name, how, count, max_len in RECIPES:
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
