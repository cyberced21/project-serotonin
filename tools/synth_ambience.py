"""Synthesizes placeholder ambience beds for the biomes (needs numpy):

    python tools/synth_ambience.py

audio/ambience/: forest.wav (a soft breeze, birdsong, the odd creaking trunk), field.wav
(two crickets chirping over open wind) and quarry.wav (a low echoey hum, water dripping somewhere below).
Each is LENGTH seconds and loops seamlessly (the end is crossfaded into the start). The Biome
autoload crossfades them as you move between biomes. Replace any with a real recording.
"""
import os

import numpy as np

from synth_movement_sounds import RATE, band, env, lowpass, place, secs, write_wav

OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "ambience")
LENGTH = 12.0
SEAM = 1.0


def seamless(x):
    """Folds the extra SEAM seconds at the end over the start, so the loop point can't be heard."""
    n, xf = secs(LENGTH), secs(SEAM)
    fade = np.linspace(0.0, 1.0, xf)
    x[:xf] = x[:xf] * fade + x[n:n + xf] * (1.0 - fade)
    return x[:n]


def breeze(rng, total, low, high, depth=0.35, period=4.0):
    t = np.arange(total) / RATE
    swell = 1.0 - depth + depth * np.sin(2 * np.pi * t / period) * np.sin(2 * np.pi * t / (period * 2.3) + 0.7)
    return band(rng.standard_normal(total), low, high) * swell


def chirp(rng):
    """One little bird phrase: two to four quick whistles sliding in pitch."""
    out = np.zeros(secs(0.8))
    at = 0.0
    base = rng.uniform(2600, 4200)
    for _ in range(rng.integers(2, 5)):
        n = secs(rng.uniform(0.05, 0.11))
        t = np.arange(n) / RATE
        f = base * (1.0 + rng.uniform(-0.25, 0.3) * t / t[-1])
        tone = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.sin(np.pi * t / t[-1])
        place(out, tone, at)
        at += n / RATE + rng.uniform(0.03, 0.09)
    return out


def creak(rng):
    """A trunk straining in the wind, off in the trees: wood catching and slipping in slow,
    uneven grabs, each one knocking the trunk's low resonances. The grabs are too slow and too
    irregular to fuse into a pitch, so it reads as a creak, not a buzz (a steady tone made of
    grabs, like the sawtooth this replaced, is heard as an electric buzz)."""
    length = rng.uniform(0.8, 1.4)
    n = secs(length)
    out = np.zeros(n)
    body = [(f * rng.uniform(0.9, 1.1), d) for f, d in ((95, 0.05), (170, 0.035), (290, 0.022), (460, 0.014))]
    m = secs(0.12)
    tm = np.arange(m) / RATE
    at = 0.0
    while at < length:
        swell = np.sin(np.pi * at / length)  # slow, strained, then slow again
        pulse = sum(np.sin(2 * np.pi * f * tm + rng.uniform(0, 6.28)) * np.exp(-tm / d) for f, d in body)
        place(out, pulse * rng.uniform(0.5, 1.0) * (0.3 + 0.7 * swell), at)
        rate = 9.0 + 14.0 * swell  # grabs per second
        at += rng.uniform(0.6, 1.5) / rate
    t = np.arange(n) / RATE
    return lowpass(out, 1100) * np.sin(np.pi * t / t[-1]) ** 2


def forest(rng):
    total = secs(LENGTH + SEAM)
    x = breeze(rng, total, 150, 900) * 0.5
    for at in np.sort(rng.uniform(0.3, LENGTH - 0.5, 7)):
        place(x, chirp(rng) * rng.uniform(0.25, 0.5), at)
    for at in rng.uniform(1.0, LENGTH - 1.5, 2):
        place(x, creak(rng) * 0.06, at)
    return seamless(x)


def cricket_chirp(rng, pitch):
    """One chirp: three or four quick pulses of a pure tone, each faded in and out (a hard on/off
    gate makes every edge a click, and thirty clicks a second is a rasp)."""
    pulses = rng.integers(3, 5)
    pulse = secs(0.018)
    gap = secs(rng.uniform(0.012, 0.016))
    out = np.zeros(pulses * (pulse + gap))
    t = np.arange(pulse) / RATE
    shape = np.sin(np.pi * t / t[-1]) ** 2
    for k in range(pulses):
        tone = np.sin(2 * np.pi * pitch * (1.0 - 0.02 * t / t[-1]) * t) * shape
        out[k * (pulse + gap):k * (pulse + gap) + pulse] += tone
    return out


def field(rng):
    total = secs(LENGTH + SEAM)
    x = breeze(rng, total, 200, 1400, depth=0.5, period=5.0) * 0.45
    for voice in range(2):  # two crickets off in the grass, each its own pitch, pace and pauses
        pitch = rng.uniform(4000, 4800)
        gain = rng.uniform(0.025, 0.04)
        at = rng.uniform(0.0, 1.0)
        while at < LENGTH + SEAM - 0.3:
            if rng.random() < 0.15:  # now and then one stops for a moment
                at += rng.uniform(1.0, 2.5)
                continue
            place(x, cricket_chirp(rng, pitch) * gain * rng.uniform(0.7, 1.0), at)
            at += rng.uniform(0.45, 0.7)
    return seamless(lowpass(x, 6000))


def drip(rng):
    """A drop landing in a pool, and its echoes off the quarry walls."""
    n = secs(1.6)
    out = np.zeros(n)
    m = secs(0.12)
    t = np.arange(m) / RATE
    f = rng.uniform(1300, 2300) * (1.0 + 0.6 * t / t[-1])
    plink = np.sin(2 * np.pi * np.cumsum(f) / RATE) * env(m, 0.002, 0.03)
    for k in range(5):
        place(out, plink * (0.55 ** k), 0.27 * k)
    return lowpass(out, 5000)


def quarry(rng):
    total = secs(LENGTH + SEAM)
    t = np.arange(total) / RATE
    # periods that divide LENGTH, so the hum's slow beating lines up at the seam too
    hum = np.sin(2 * np.pi * 55.0 * t) * 0.5 + np.sin(2 * np.pi * 82.5 * t) * 0.25
    hum *= 0.75 + 0.25 * np.sin(2 * np.pi * t / 6.0)
    x = hum * 0.35 + lowpass(rng.standard_normal(total), 200) * 0.6
    for at in rng.uniform(0.5, LENGTH - 1.8, 5):
        place(x, drip(rng) * rng.uniform(0.2, 0.35), at)
    return seamless(x)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(21)
    for name, make in (("forest", forest), ("field", field), ("quarry", quarry)):
        path = os.path.join(OUT, name + ".wav")
        write_wav(path, make(rng), fade_out=False)
        print("wrote", path)
