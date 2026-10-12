"""Synthesizes placeholder movement sounds (needs numpy):

    python tools/synth_movement_sounds.py

- audio/footsteps/: per surface, VARIANTS steps (heel + toe hits made of filtered noise, plus a
  thump or ring where it fits) and an AudioStreamRandomizer .tres picking one with a little
  random pitch/volume.
- audio/movement/: a seamless slide-scrape loop, mantle sounds (both hands slapping onto the
  ledge, then a clothing rustle as you pull up) and water splashes, with their randomizers.

Replace any .wav with a real recording whenever you like — the game only references the
.tres randomizers and slide_loop.wav.
"""
import os
import wave

import numpy as np

RATE = 44100
VARIANTS = 4
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "footsteps")
OUT_MOVE = os.path.join(os.path.dirname(__file__), "..", "audio", "movement")


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


def bubbles(rng, out, count, start, end, gain):
    """Little rising 'plip's: short sines sweeping upward, like air bubbles popping."""
    for _ in range(count):
        n = secs(rng.uniform(0.02, 0.05))
        t = np.arange(n) / RATE
        f0 = rng.uniform(500, 1400)
        phase = 2 * np.pi * np.cumsum(f0 * (1.0 + 0.8 * t / t[-1])) / RATE
        place(out, np.sin(phase) * env(n, 0.001, 0.012) * gain * rng.uniform(0.4, 1.0), rng.uniform(start, end))


def water(rng):
    """Wading step: a slosh of water around the leg, then a few bubbles."""
    out = np.zeros(secs(0.38))
    n = secs(0.3)
    place(out, band(rng.standard_normal(n), 300, 2500) * env(n, 0.012, 0.11) * 1.4, 0.0)
    bubbles(rng, out, rng.integers(4, 8), 0.02, 0.28, 0.35)
    return out


SURFACES = {"grass": grass, "dirt": dirt, "rock": rock, "sand": sand, "snow": snow, "water": water}


# --- movement -------------------------------------------------------------------------------

def slide_loop(rng):
    """1.2 s of gritty scrape that loops seamlessly (the end is crossfaded into the start)."""
    n, xf = secs(1.2), secs(0.15)
    total = n + xf
    body = lowpass(rng.standard_normal(total), 900) * 1.4
    grit = band(rng.standard_normal(total), 2000, 6000)
    grains = np.repeat(rng.random(total // 200 + 1) ** 2, 200)[:total]  # little stones catching
    x = body + grit * (0.25 + grains)
    fade = np.linspace(0.0, 1.0, xf)
    x[:xf] = x[:xf] * fade + x[n:] * (1.0 - fade)
    return x[:n]


def splash(rng):
    """Big splash: landing in water, a spear plunging in, fish breaking the surface."""
    out = np.zeros(secs(0.85))
    n = secs(0.6)
    t = np.arange(n) / RATE
    place(out, band(rng.standard_normal(n), 200, 6000) * env(n, 0.004, 0.16) * 1.6, 0.0)
    place(out, np.sin(2 * np.pi * rng.uniform(60, 80) * t) * env(n, 0.002, 0.07) * 0.8, 0.0)
    bubbles(rng, out, rng.integers(10, 16), 0.05, 0.7, 0.3)
    return out


def mantle(rng):
    out = np.zeros(secs(0.45))
    for at in (0.0, rng.uniform(0.03, 0.06)):  # left hand, right hand
        n = secs(0.06)
        t = np.arange(n) / RATE
        slap = highpass(rng.standard_normal(n), 800) * env(n, 0.0, 0.008)
        thump = np.sin(2 * np.pi * rng.uniform(110, 140) * t) * env(n, 0.001, 0.02) * 0.6
        place(out, slap + thump, at)
    n = secs(0.34)  # clothes rustling as you haul yourself up
    rustle = band(rng.standard_normal(n), 400, 3000)
    wobble = lowpass(rng.random(n), 12) * 4.0  # slow random swells
    place(out, rustle * wobble * env(n, 0.08, 0.15) * 0.35, 0.07)
    return out


# --- output -----------------------------------------------------------------------------------

def write_wav(path, x, fade_out=True):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.7  # about -3 dBFS
    if fade_out:  # (not for loops — it would click at the seam)
        fade = min(len(x), secs(0.01))
        x[-fade:] *= np.linspace(1.0, 0.0, fade)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def write_randomizer(path, name, folder="footsteps"):
    lines = ['[gd_resource type="AudioStreamRandomizer" format=3]', ""]
    for i in range(VARIANTS):
        lines.append(f'[ext_resource type="AudioStream" path="res://audio/{folder}/{name}_{i + 1:02d}.wav" id="{i + 1}"]')
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

    os.makedirs(OUT_MOVE, exist_ok=True)
    write_wav(os.path.join(OUT_MOVE, "slide_loop.wav"), slide_loop(rng), fade_out=False)
    for i in range(VARIANTS):
        write_wav(os.path.join(OUT_MOVE, f"mantle_{i + 1:02d}.wav"), mantle(rng))
    write_randomizer(os.path.join(OUT_MOVE, "mantle.tres"), "mantle", "movement")
    for i in range(VARIANTS):
        write_wav(os.path.join(OUT_MOVE, f"splash_{i + 1:02d}.wav"), splash(rng))
    write_randomizer(os.path.join(OUT_MOVE, "splash.tres"), "splash", "movement")
    print("wrote slide_loop, mantle, splash")


if __name__ == "__main__":
    main()
