"""Synthesizes placeholder footstep sounds into audio/footsteps/ (needs numpy).

    python tools/synth_footsteps.py

Each surface gets VARIANTS slightly different steps (heel + toe hits made of filtered noise,
plus a thump or ring where it fits), and an AudioStreamRandomizer .tres that picks one with a
little random pitch/volume. Replace the .wav files with real recordings whenever you like —
the game only references the .tres files.
"""
import os
import wave

import numpy as np

RATE = 44100
VARIANTS = 4
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "footsteps")


def lowpass(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def band(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def env(n, attack, decay):
    t = np.arange(n) / RATE
    e = np.exp(-np.maximum(t - attack, 0.0) / decay)
    if attack > 0:
        e *= np.clip(t / attack, 0.0, 1.0)
    return e


def place(buf, sound, at):
    i = int(at * RATE)
    end = min(len(buf), i + len(sound))
    buf[i:end] += sound[: end - i]


def secs(s):
    return int(s * RATE)


# --- surfaces ---------------------------------------------------------------------------------

def grass(rng):
    out = np.zeros(secs(0.22))
    for at, gain in ((0.0, 1.0), (rng.uniform(0.03, 0.05), 0.7)):  # heel, toe
        n = secs(0.12)
        crackle = (rng.random(n) < 0.08) * rng.uniform(0.5, 1.5, n)  # sparse snapping blades
        hit = band(rng.standard_normal(n), 1500, 7000) * (0.6 + crackle)
        place(out, hit * env(n, 0.002, 0.035) * gain, at)
    return out


def dirt(rng):
    out = np.zeros(secs(0.2))
    for at, gain in ((0.0, 1.0), (rng.uniform(0.03, 0.05), 0.6)):
        n = secs(0.12)
        t = np.arange(n) / RATE
        thump = np.sin(2 * np.pi * rng.uniform(75, 100) * t) * env(n, 0.001, 0.03) * 0.8
        grit = lowpass(rng.standard_normal(n), 1200) * env(n, 0.002, 0.05) * 1.6
        place(out, (thump + grit) * gain, at)
    return out


def rock(rng):
    out = np.zeros(secs(0.18))
    for at, gain in ((0.0, 1.0), (rng.uniform(0.025, 0.045), 0.75)):
        n = secs(0.1)
        t = np.arange(n) / RATE
        click = highpass(rng.standard_normal(n), 3000) * env(n, 0.0, 0.003)
        scuff = lowpass(rng.standard_normal(n), 2500) * env(n, 0.001, 0.022) * 0.9
        ring = (np.sin(2 * np.pi * rng.uniform(380, 460) * t)
                + 0.5 * np.sin(2 * np.pi * rng.uniform(720, 840) * t)) * env(n, 0.0, 0.018) * 0.25
        place(out, (click + scuff + ring) * gain, at)
    return out


def sand(rng):
    n = secs(0.26)
    body = lowpass(rng.standard_normal(n), 1800) * env(n, 0.018, 0.08) * 1.5
    hiss = highpass(rng.standard_normal(n), 4000) * env(n, 0.03, 0.06) * 0.25
    return body + hiss


def snow(rng):
    out = np.zeros(secs(0.28))
    for at, gain in ((0.0, 1.0), (rng.uniform(0.05, 0.07), 0.8)):
        n = secs(0.18)
        grains = np.repeat(rng.random(n // 120 + 1) ** 3, 120)[:n]  # ~3 ms crunchy grains
        crunch = band(rng.standard_normal(n), 800, 5000) * grains * 2.2
        place(out, crunch * env(n, 0.01, 0.07) * gain, at)
    return out


SURFACES = {"grass": grass, "dirt": dirt, "rock": rock, "sand": sand, "snow": snow}


# --- output -----------------------------------------------------------------------------------

def write_wav(path, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.7  # about -3 dBFS
    fade = min(len(x), secs(0.01))
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def write_randomizer(path, name):
    lines = ['[gd_resource type="AudioStreamRandomizer" format=3]', ""]
    for i in range(VARIANTS):
        lines.append(f'[ext_resource type="AudioStream" path="res://audio/footsteps/{name}_{i + 1:02d}.wav" id="{i + 1}"]')
    lines += ["", "[resource]", "playback_mode = 0", "random_pitch = 1.1",
              "random_volume_offset_db = 2.0", f"streams_count = {VARIANTS}"]
    for i in range(VARIANTS):
        lines += [f'stream_{i}/stream = ExtResource("{i + 1}")', f"stream_{i}/weight = 1.0"]
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(1234)
    for name, make in SURFACES.items():
        for i in range(VARIANTS):
            write_wav(os.path.join(OUT, f"{name}_{i + 1:02d}.wav"), make(rng))
        write_randomizer(os.path.join(OUT, f"{name}.tres"), name)
        print("wrote", name)


if __name__ == "__main__":
    main()
