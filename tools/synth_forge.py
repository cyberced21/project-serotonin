"""Synthesizes the forge cutscene's sounds (needs numpy):

    python tools/synth_forge.py

Writes audio/forge/<name>.wav, one take each: the cutscene plays every one once, in order, so
there's nothing to randomize. The blows come as blow_1..3, each heavier than the last.

  flare      the forge flaring up: a whoomp of air and fire, crackling on
  drone      a low swell under the blows, rising (about 4 s)
  blow_1..3  the hammer on the blank: a bright anvil ring with an echo off the buildings;
             each lower, longer and with more thud
  hiss       the quench: a huge hiss falling away into a boil
  reveal     the reveal: a choir-like swell on a major chord
  settle     the new tool landing in your hands: a heavy, clean thump
  glint      a sparkle as it settles
  thunder    iron and above: a long roll
  bell       iron and above: the town hall's bell, once
  beam       crystal: a rising shimmer as the beam goes up
  shockwave  the first swing with a new tool: a deep boom with a ring
  ring_copper, ring_iron, ring_crystal
             the tool itself ringing on a biting hit, layered quietly under the hit: copper a
             warm dull tone, iron a bright clang, crystal a glassy chime
"""
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "forge")


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


def secs(s):
    return int(s * RATE)


def times(n):
    return np.arange(n) / RATE


def env(n, attack, decay):
    t = times(n)
    e = np.exp(-np.maximum(t - attack, 0.0) / decay)
    if attack > 0:
        e *= np.clip(t / attack, 0.0, 1.0)
    return e


def swell(n, rise, fall):
    """Up over `rise` seconds, then down over the rest (a smooth hump)."""
    t = times(n)
    up = np.clip(t / rise, 0.0, 1.0) ** 2
    down = np.clip((t[-1] - t) / fall, 0.0, 1.0)
    return up * down


def place(buf, sound, at):
    i = int(at * RATE)
    end = min(len(buf), i + len(sound))
    if end > i:
        buf[i:end] += sound[: end - i]


def echo(x, delays, gains):
    """Copies of x arriving later and quieter (the ring bouncing off the buildings)."""
    out = np.concatenate([x, np.zeros(secs(max(delays) + 0.1))])
    for d, g in zip(delays, gains):
        place(out, lowpass(x, 3500) * g, d)
    return out


def crackle(rng, n, count, gain):
    out = np.zeros(n)
    for _ in range(count):
        k = secs(rng.uniform(0.002, 0.008))
        place(out, rng.standard_normal(k) * env(k, 0.0, 0.002) * gain * rng.uniform(0.3, 1.0), rng.uniform(0.0, n / RATE))
    return band(out, 1500, 9000)


# --- the sounds -------------------------------------------------------------------------------

def flare(rng):
    n = secs(1.8)
    t = times(n)
    air = band(rng.standard_normal(n), 80, 900) * swell(n, 0.12, 1.6) * 1.2
    thump = np.sin(2 * np.pi * (55 + 30 * np.exp(-t / 0.08)) * t) * env(n, 0.005, 0.25)
    return air + thump + crackle(rng, n, 60, 0.6)


def drone(rng):
    n = secs(4.2)
    t = times(n)
    rise = 1.0 + 0.06 * t / t[-1]  # creeps up in pitch as the blows come
    x = np.zeros(n)
    for f, g in ((55, 1.0), (55.4, 0.8), (82.5, 0.5), (110.2, 0.35)):
        phase = 2 * np.pi * np.cumsum(f * rise) / RATE
        x += g * (2 * ((phase / (2 * np.pi)) % 1.0) - 1.0)  # a saw
    x = lowpass(x, 420)
    return x * swell(n, 3.0, 0.6)


def anvil(rng, f0, ring, thud):
    """A struck steel bar: inharmonic partials over a click and a thud."""
    n = secs(ring * 1.6)
    t = times(n)
    x = np.zeros(n)
    for ratio, g, d in ((1.0, 1.0, 1.0), (2.76, 0.7, 0.6), (5.40, 0.45, 0.35), (8.93, 0.3, 0.2), (13.3, 0.15, 0.12)):
        f = f0 * ratio * rng.uniform(0.995, 1.005)
        x += g * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * env(n, 0.0005, ring * d)
    click = band(rng.standard_normal(n), 2500, 12000) * env(n, 0.0, 0.004) * 1.5
    body = np.sin(2 * np.pi * (70 + 60 * np.exp(-t / 0.03)) * t) * env(n, 0.002, 0.12) * thud
    return echo(x + click + body, (0.21, 0.37, 0.58), (0.35, 0.2, 0.1))


def blow(level):
    def make(rng):
        f0 = (920, 760, 600)[level]
        return anvil(rng, f0, (1.3, 1.8, 2.6)[level], (0.6, 1.2, 2.0)[level])
    return make


def hiss(rng):
    n = secs(3.0)
    t = times(n)
    e = env(n, 0.01, 0.9)
    bright = band(rng.standard_normal(n), 3000, 11000) * e * 1.4
    body = band(rng.standard_normal(n), 400, 3000) * env(n, 0.005, 0.5)
    boil = np.zeros(n)
    for _ in range(140):  # the water boiling round the blade as the hiss dies
        k = secs(rng.uniform(0.01, 0.03))
        f = rng.uniform(300, 900)
        at = rng.uniform(0.3, 2.8)
        boil_t = times(k)
        place(boil, np.sin(2 * np.pi * f * (1 + 2 * boil_t) * boil_t) * env(k, 0.001, 0.008) * 0.35, at)
    return bright + body + boil * np.clip(t / 0.6, 0, 1)


def reveal(rng):
    n = secs(3.6)
    t = times(n)
    x = np.zeros(n)
    root = 220.0
    for ratio in (1.0, 1.25, 1.5, 2.0, 2.5, 3.0):  # a major chord, spread up two octaves
        for voice in range(3):  # a few slightly detuned voices per note: a choir, not an organ
            f = root * ratio * (1 + rng.uniform(-0.004, 0.004))
            vib = 0.004 * np.sin(2 * np.pi * rng.uniform(4.5, 5.5) * t + rng.uniform(0, 6.28))
            ph = 2 * np.pi * np.cumsum(f * (1 + vib)) / RATE
            x += (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)) / (1 + ratio * 0.4)
    breath = band(rng.standard_normal(n), 900, 3500) * 0.08
    return lowpass(x + breath, 4000) * swell(n, 0.7, 2.2)


def settle(rng):
    n = secs(0.5)
    t = times(n)
    thump = np.sin(2 * np.pi * (90 + 70 * np.exp(-t / 0.02)) * t) * env(n, 0.002, 0.09)
    grip = band(rng.standard_normal(n), 300, 2500) * env(n, 0.001, 0.03) * 0.5
    ring = np.sin(2 * np.pi * 1320 * t) * env(n, 0.002, 0.18) * 0.12
    return thump + grip + ring


def glint(rng):
    n = secs(0.9)
    out = np.zeros(n)
    for k in range(14):
        m = secs(0.25)
        f = 2600 + 220 * k + rng.uniform(-60, 60)
        place(out, np.sin(2 * np.pi * f * times(m)) * env(m, 0.002, 0.07) * (1 - k / 16), k * 0.035)
    return out


def thunder(rng):
    n = secs(4.0)
    t = times(n)
    rumble = lowpass(rng.standard_normal(n), 160) * 6.0
    cracks = band(rng.standard_normal(n), 200, 1800) * env(n, 0.02, 0.35) * 0.8
    roll = 0.6 + 0.4 * np.sin(2 * np.pi * 1.3 * t) * np.sin(2 * np.pi * 0.45 * t)
    return (rumble * roll + cracks) * swell(n, 0.15, 3.4)


def bell(rng):
    n = secs(5.0)
    t = times(n)
    f0 = 196.0
    x = np.zeros(n)
    for ratio, g, d in ((0.5, 0.6, 2.5), (1.0, 1.0, 1.8), (1.19, 0.5, 1.4), (1.5, 0.45, 1.1),
                        (2.0, 0.4, 0.9), (2.51, 0.25, 0.6), (3.0, 0.2, 0.4)):
        x += g * np.sin(2 * np.pi * f0 * ratio * t) * env(n, 0.002, d)
    strike = band(rng.standard_normal(n), 800, 6000) * env(n, 0.0, 0.01) * 0.6
    return echo(x + strike, (0.4, 0.8), (0.3, 0.15))


def beam(rng):
    n = secs(3.4)
    t = times(n)
    rise = np.exp(np.log(2.0) * t / t[-1])  # an octave up over its length
    x = np.zeros(n)
    for f in (330, 495, 660, 990, 1320):
        x += np.sin(2 * np.pi * np.cumsum(f * rise * (1 + 0.003 * np.sin(2 * np.pi * 6 * t))) / RATE)
    air = band(rng.standard_normal(n), 2000, 9000) * 0.25
    return (x * 0.3 + air) * swell(n, 1.2, 1.4)


def shockwave(rng):
    n = secs(1.4)
    t = times(n)
    boom = np.sin(2 * np.pi * (45 + 80 * np.exp(-t / 0.05)) * t) * env(n, 0.002, 0.35) * 1.4
    blast = band(rng.standard_normal(n), 100, 2500) * env(n, 0.001, 0.12)
    ring = np.sin(2 * np.pi * 780 * t) * env(n, 0.002, 0.6) * 0.25
    return boom + blast + ring


def ring(f0, partials, decay, click):
    def make(rng):
        n = secs(decay * 2.5)
        t = times(n)
        x = np.zeros(n)
        for ratio, g, d in partials:
            x += g * np.sin(2 * np.pi * f0 * ratio * rng.uniform(0.997, 1.003) * t + rng.uniform(0, 6.28)) * env(n, 0.001, decay * d)
        x += band(rng.standard_normal(n), 3000, 11000) * env(n, 0.0, 0.003) * click
        return x
    return make


SOUNDS = {
    "flare": flare, "drone": drone, "blow_1": blow(0), "blow_2": blow(1), "blow_3": blow(2),
    "hiss": hiss, "reveal": reveal, "settle": settle, "glint": glint, "thunder": thunder,
    "bell": bell, "beam": beam, "shockwave": shockwave,
    "ring_copper": ring(520, ((1.0, 1.0, 1.0), (2.4, 0.4, 0.5), (4.1, 0.15, 0.3)), 0.28, 0.5),
    "ring_iron": ring(1180, ((1.0, 1.0, 1.0), (2.76, 0.6, 0.6), (5.4, 0.3, 0.35)), 0.45, 0.8),
    "ring_crystal": ring(1560, ((1.0, 1.0, 1.0), (2.0, 0.5, 0.9), (3.01, 0.35, 0.8), (4.2, 0.2, 0.6)), 0.7, 0.3),
}
## Quieter cues are written quieter, so the game's volumes stay simple (peak per sound).
PEAKS = {"drone": 0.45, "glint": 0.4, "reveal": 0.6, "beam": 0.5, "ring_copper": 0.5, "ring_iron": 0.5,
         "ring_crystal": 0.5}


def write_wav(path, x, peak=0.7):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = min(len(x), secs(0.02))
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    for k, (name, make) in enumerate(SOUNDS.items()):
        rng = np.random.default_rng(12000 + k)  # one seed per sound: adding one doesn't change the rest
        write_wav(os.path.join(OUT, f"{name}.wav"), make(rng), PEAKS.get(name, 0.8))
        print("wrote", name)


if __name__ == "__main__":
    main()
