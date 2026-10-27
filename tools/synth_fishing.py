"""Synthesizes rod fishing's sounds (needs numpy):

    python tools/synth_fishing.py

Writes audio/fishing/<name>_01..04.wav and an AudioStreamRandomizer audio/fishing/<name>.tres per
sound (a little random pitch and volume), the same layout as synth_movement_sounds.py. Every cue
in the minigame is one of these, so each has to be told apart at a glance by ear:

  cast_whip   the rod whipping through the sweet spot of the forward stroke (the release cue)
  plip        a perfect cast: the float kissing the water
  plop        a good cast: a fuller drop
  splosh      a bad cast: a slap and a spray
  nibble      a fish mouthing the float: a tiny high tick of water
  tap         the tap-tap before the take: two of these, a little firmer
  bloop       the take: the float dunked under, a hollow gulp and a line twang
  reel        one click of the reel's ratchet (played as line comes in)
  creak       the rod loading up under a pull or before a headshake
  jerk        the rod tip snapping down in a headshake
  hiss        a run: line tearing off the reel, rising (about a second)
  bulge       the water swelling before a jump: a low whoomp
  jump        the fish clearing the water and crashing back
  strain      a notch lost: the line groaning near breaking
  snap        the line parting: a crack and a whip
  thrash      the fish thrashing at your feet
  hoist       the fish lifted out: a big spray and a drip-off
  spook       a fish bolting: a quick swirl
  hooked      the take, the moment to pull: a heavy plunge, the line zinging tight, a bell
  yank        the strike that lands it: a whoosh and the water tearing open
  flop        the fish hitting the bank, and each flop after

(reel, hiss, bulge, strain, snap, thrash and hoist were the old fight's; nothing plays them now.)
"""
import os
import wave

import numpy as np

RATE = 44100
VARIANTS = 4
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "fishing")


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
    if end > i:
        buf[i:end] += sound[: end - i]


def secs(s):
    return int(s * RATE)


def sweep(n, f0, f1, curve=1.0):
    """A sine gliding from f0 to f1 Hz over n samples."""
    t = np.linspace(0.0, 1.0, n) ** curve
    return np.sin(2 * np.pi * np.cumsum(f0 + (f1 - f0) * t) / RATE)


def bubbles(rng, out, count, start, end, gain, lo=500, hi=1400):
    """Little rising 'plip's: short sines sweeping upward, like air bubbles popping."""
    for _ in range(count):
        n = secs(rng.uniform(0.02, 0.05))
        f0 = rng.uniform(lo, hi)
        place(out, sweep(n, f0, f0 * 1.8) * env(n, 0.001, 0.012) * gain * rng.uniform(0.4, 1.0),
              rng.uniform(start, end))


def drop(rng, f0, f1, length, decay):
    """The 'plunk' of something small hitting water: a resonant cavity sweeping up in pitch."""
    n = secs(length)
    return sweep(n, f0, f1, 0.6) * env(n, 0.001, decay)


# --- the cast ---------------------------------------------------------------------------------

def cast_whip(rng):
    n = secs(0.32)
    t = np.arange(n) / RATE
    # air past a thin blank: band noise whose centre and loudness swell and fall
    swell = np.exp(-((t - 0.13) / 0.06) ** 2)
    hi = band(rng.standard_normal(n), 2500, 9000) * swell
    lo = band(rng.standard_normal(n), 500, 2000) * swell * 0.6
    whistle = sweep(n, rng.uniform(900, 1100), rng.uniform(1500, 1800)) * swell * 0.12
    return hi + lo + whistle


def plip(rng):
    out = np.zeros(secs(0.3))
    place(out, drop(rng, rng.uniform(900, 1100), rng.uniform(1700, 2100), 0.06, 0.018), 0.0)
    place(out, band(rng.standard_normal(secs(0.05)), 2000, 7000) * env(secs(0.05), 0.0, 0.008) * 0.25, 0.0)
    bubbles(rng, out, 2, 0.03, 0.15, 0.25, 1200, 2200)
    return out


def plop(rng):
    out = np.zeros(secs(0.45))
    place(out, drop(rng, rng.uniform(380, 460), rng.uniform(800, 950), 0.12, 0.04), 0.0)
    n = secs(0.18)
    place(out, band(rng.standard_normal(n), 400, 4000) * env(n, 0.002, 0.04) * 0.6, 0.0)
    bubbles(rng, out, 5, 0.04, 0.35, 0.3)
    return out


def splosh(rng):
    out = np.zeros(secs(0.8))
    n = secs(0.5)
    t = np.arange(n) / RATE
    place(out, band(rng.standard_normal(n), 250, 6500) * env(n, 0.003, 0.11) * 1.4, 0.0)
    place(out, np.sin(2 * np.pi * rng.uniform(70, 90) * t) * env(n, 0.002, 0.05) * 0.7, 0.0)
    place(out, drop(rng, 260, 520, 0.15, 0.05) * 0.6, 0.005)
    bubbles(rng, out, rng.integers(9, 14), 0.05, 0.6, 0.3)
    return out


# --- the bite ---------------------------------------------------------------------------------

def nibble(rng):
    out = np.zeros(secs(0.12))
    place(out, drop(rng, rng.uniform(1500, 1900), rng.uniform(2400, 2900), 0.03, 0.008) * 0.8, 0.0)
    place(out, highpass(rng.standard_normal(secs(0.02)), 3000) * env(secs(0.02), 0.0, 0.004) * 0.2, 0.0)
    return out


def tap(rng):
    out = np.zeros(secs(0.16))
    place(out, drop(rng, rng.uniform(1100, 1300), rng.uniform(1900, 2200), 0.045, 0.012), 0.0)
    n = secs(0.06)
    place(out, band(rng.standard_normal(n), 1500, 5000) * env(n, 0.0, 0.01) * 0.35, 0.0)
    return out


def bloop(rng):
    out = np.zeros(secs(0.7))
    # the gulp: a hollow downward-then-up cavity as the float is pulled under
    n = secs(0.22)
    place(out, sweep(n, rng.uniform(520, 600), rng.uniform(180, 220), 0.5) * env(n, 0.004, 0.07) * 0.9, 0.0)
    place(out, drop(rng, 300, 700, 0.12, 0.04) * 0.5, 0.06)
    bubbles(rng, out, 6, 0.08, 0.4, 0.3, 400, 1000)
    # the line coming tight: a short bright twang
    m = secs(0.35)
    t = np.arange(m) / RATE
    f = rng.uniform(310, 360)
    twang = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.01 * t) + 0.25 * np.sin(2 * np.pi * f * 3.03 * t))
    place(out, twang * env(m, 0.002, 0.09) * 0.35, 0.02)
    return out


# --- the fight --------------------------------------------------------------------------------

def reel(rng):
    """One ratchet click: a hard tick and a tiny metallic ring."""
    n = secs(0.05)
    t = np.arange(n) / RATE
    tick = highpass(rng.standard_normal(n), 3500) * env(n, 0.0, 0.0025)
    ring = np.sin(2 * np.pi * rng.uniform(4200, 4800) * t) * env(n, 0.0, 0.008) * 0.3
    return tick + ring


def creak(rng):
    """The rod loading: a slow stick-slip of graphite/wood, rough pulses at a low rate."""
    n = secs(0.5)
    t = np.arange(n) / RATE
    rate = rng.uniform(55, 75)
    pulses = (np.sin(2 * np.pi * rate * t + 2.0 * np.sin(2 * np.pi * 3 * t)) > 0.92).astype(float)
    grain = lowpass(pulses, 2500) * band(rng.standard_normal(n), 300, 3000) * 3.0
    shape = np.sin(np.pi * np.clip(t / 0.5, 0, 1)) ** 0.7
    body = sweep(n, 180, 140) * 0.15
    return (grain + body) * shape


def jerk(rng):
    """The tip snapping down: a short swish and a little line pluck."""
    out = np.zeros(secs(0.2))
    n = secs(0.09)
    t = np.arange(n) / RATE
    swell = np.exp(-((t - 0.03) / 0.02) ** 2)
    place(out, band(rng.standard_normal(n), 1500, 6000) * swell * 0.8, 0.0)
    m = secs(0.15)
    f = rng.uniform(400, 470)
    place(out, np.sin(2 * np.pi * f * np.arange(m) / RATE) * env(m, 0.001, 0.035) * 0.45, 0.03)
    return out


def hiss(rng):
    """Line tearing off the reel: a fast buzz of ratchet clicks plus a hiss, both rising."""
    n = secs(1.1)
    t = np.arange(n) / RATE
    rate = 60 + 260 * (t / t[-1]) ** 0.7  # clicks per second, speeding up
    phase = np.cumsum(rate) / RATE
    clicks = (np.diff(np.floor(phase), prepend=0.0) > 0).astype(float)
    clicky = highpass(lowpass(clicks, 9000), 2500) * 4.0
    air = band(rng.standard_normal(n), 3000, 9000) * 0.25 * (t / t[-1])
    shape = np.clip(t / 0.05, 0, 1) * np.clip((t[-1] - t) / 0.12, 0, 1)
    return (clicky + air) * shape


def bulge(rng):
    """The water heaving before a jump: a low swell and a slurp."""
    n = secs(0.5)
    t = np.arange(n) / RATE
    swell = np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 2
    low = lowpass(rng.standard_normal(n), 220) * 2.5 * swell
    gulp = sweep(n, 110, 70) * swell * 0.6
    slosh = band(rng.standard_normal(n), 300, 1500) * swell * 0.3
    return low + gulp + slosh


def jump(rng):
    """Out of the water (a tearing spray), a beat in the air, then crashing back in."""
    out = np.zeros(secs(1.0))
    n = secs(0.25)
    place(out, band(rng.standard_normal(n), 600, 7000) * env(n, 0.005, 0.05) * 0.9, 0.0)
    bubbles(rng, out, 4, 0.0, 0.12, 0.25)
    at = rng.uniform(0.32, 0.4)
    m = secs(0.55)
    tt = np.arange(m) / RATE
    place(out, band(rng.standard_normal(m), 200, 6000) * env(m, 0.003, 0.13) * 1.5, at)
    place(out, np.sin(2 * np.pi * rng.uniform(55, 70) * tt) * env(m, 0.002, 0.08) * 0.9, at)
    bubbles(rng, out, 12, at + 0.03, at + 0.55, 0.3)
    return out


def strain(rng):
    """The line near breaking: a tense, rising groan with a fizz on it."""
    n = secs(0.4)
    t = np.arange(n) / RATE
    f = rng.uniform(220, 260)
    tone = sweep(n, f, f * 1.35, 0.8)
    tone += 0.6 * sweep(n, f * 2.02, f * 2.7, 0.8)
    rough = 1.0 + 0.6 * np.sign(np.sin(2 * np.pi * 37 * t))  # rasp
    fizz = band(rng.standard_normal(n), 2500, 7000) * 0.15
    shape = np.clip(t / 0.03, 0, 1) * np.exp(-np.maximum(t - 0.25, 0) / 0.05)
    return (tone * rough * 0.3 + fizz) * shape


def snap(rng):
    """The line parting: a sharp crack, then the slack line whipping through the air."""
    out = np.zeros(secs(0.55))
    n = secs(0.03)
    place(out, highpass(rng.standard_normal(n), 2000) * env(n, 0.0, 0.004) * 1.4, 0.0)
    m = secs(0.12)
    place(out, np.sin(2 * np.pi * rng.uniform(700, 900) * np.arange(m) / RATE) * env(m, 0.0, 0.02) * 0.4, 0.0)
    w = secs(0.35)
    t = np.arange(w) / RATE
    swell = np.exp(-((t - 0.12) / 0.07) ** 2)
    place(out, band(rng.standard_normal(w), 1500, 8000) * swell * 0.7, 0.04)
    return out


def thrash(rng):
    out = np.zeros(secs(0.5))
    for k in range(rng.integers(3, 5)):  # several quick slaps of the tail
        n = secs(0.12)
        place(out, band(rng.standard_normal(n), 400, 6000) * env(n, 0.002, 0.03) * rng.uniform(0.5, 1.0),
              k * rng.uniform(0.07, 0.11))
    bubbles(rng, out, 6, 0.02, 0.42, 0.25)
    return out


def hoist(rng):
    out = np.zeros(secs(1.0))
    n = secs(0.35)
    place(out, band(rng.standard_normal(n), 300, 7000) * env(n, 0.01, 0.09) * 1.3, 0.0)
    place(out, sweep(secs(0.2), 140, 90) * env(secs(0.2), 0.004, 0.06) * 0.6, 0.0)
    for _ in range(rng.integers(8, 12)):  # drips running off the fish
        d = secs(0.04)
        place(out, drop(rng, rng.uniform(1200, 1800), rng.uniform(2200, 3000), 0.04, 0.01) * 0.25,
              rng.uniform(0.25, 0.9))
    return out


def spook(rng):
    """A fish bolting: a quick swirl and a tail slap."""
    out = np.zeros(secs(0.35))
    n = secs(0.2)
    t = np.arange(n) / RATE
    place(out, band(rng.standard_normal(n), 250, 2500) * np.sin(np.pi * np.clip(t / 0.2, 0, 1)) * 0.9, 0.0)
    m = secs(0.08)
    place(out, band(rng.standard_normal(m), 800, 6000) * env(m, 0.001, 0.02) * 0.7, 0.07)
    bubbles(rng, out, 3, 0.05, 0.25, 0.2)
    return out


# --- the hook and the yank ------------------------------------------------------------------------

def hooked(rng):
    """The take, the one moment that matters: a heavy plunge, the line zinging tight, and a bright
    bell on top so it cuts through anything else that's playing."""
    out = np.zeros(secs(0.9))
    n = secs(0.32)
    t = np.arange(n) / RATE
    place(out, sweep(n, rng.uniform(430, 480), rng.uniform(110, 130), 0.45) * env(n, 0.003, 0.09), 0.0)
    place(out, np.sin(2 * np.pi * rng.uniform(55, 65) * t) * env(n, 0.002, 0.07) * 0.9, 0.0)
    m = secs(0.3)
    place(out, band(rng.standard_normal(m), 300, 6000) * env(m, 0.002, 0.06) * 1.1, 0.0)
    bubbles(rng, out, 10, 0.05, 0.5, 0.3, 350, 1100)
    # the line coming tight: a rising zing with a little wobble
    z = secs(0.4)
    tz = np.arange(z) / RATE
    f0 = rng.uniform(560, 620)
    wob = 1.0 + 0.012 * np.sin(2 * np.pi * 23 * tz)
    zing = sweep(z, f0, f0 * 2.2, 0.35) * wob + 0.4 * sweep(z, f0 * 2.01, f0 * 4.4, 0.35)
    place(out, zing * env(z, 0.004, 0.12) * 0.35, 0.025)
    # the bell: two bright, slightly inharmonic partials
    b = secs(0.8)
    tb = np.arange(b) / RATE
    fb = rng.uniform(1300, 1340)
    bell = np.sin(2 * np.pi * fb * tb) + 0.5 * np.sin(2 * np.pi * fb * 2.76 * tb) * np.exp(-tb / 0.08)
    place(out, bell * env(b, 0.001, 0.22) * 0.32, 0.0)
    return out


def yank(rng):
    """The strike that lands it: the rod whooshing up and the fish tearing out of the water."""
    out = np.zeros(secs(0.9))
    n = secs(0.3)
    t = np.arange(n) / RATE
    swell = np.exp(-((t - 0.07) / 0.035) ** 2)
    place(out, band(rng.standard_normal(n), 1200, 8000) * swell * 1.0, 0.0)
    place(out, sweep(n, 700, 2600, 0.6) * swell * 0.12, 0.0)
    # the water tearing open, and the spray falling back
    m = secs(0.5)
    place(out, band(rng.standard_normal(m), 400, 7000) * env(m, 0.004, 0.1) * 1.4, 0.04)
    place(out, np.sin(2 * np.pi * rng.uniform(70, 85) * np.arange(m) / RATE) * env(m, 0.002, 0.05) * 0.6, 0.04)
    bubbles(rng, out, 8, 0.06, 0.3, 0.3, 600, 1600)
    for _ in range(rng.integers(10, 15)):  # spray pattering back down
        place(out, drop(rng, rng.uniform(1300, 2000), rng.uniform(2300, 3200), 0.035, 0.008) * 0.25,
              rng.uniform(0.3, 0.85))
    return out


def flop(rng):
    """A wet fish hitting the ground: a soft thud and a slap."""
    out = np.zeros(secs(0.3))
    n = secs(0.12)
    t = np.arange(n) / RATE
    place(out, np.sin(2 * np.pi * rng.uniform(85, 110) * t) * env(n, 0.001, 0.03) * 0.9, 0.0)
    place(out, band(rng.standard_normal(n), 500, 5000) * env(n, 0.0, 0.018) * 1.0, 0.0)
    place(out, drop(rng, rng.uniform(700, 800), rng.uniform(350, 420), 0.06, 0.02) * 0.3, 0.008)
    return out


## (New sounds go at the end: each one's seed is its place in this list.)
SOUNDS = {
    "cast_whip": cast_whip, "plip": plip, "plop": plop, "splosh": splosh,
    "nibble": nibble, "tap": tap, "bloop": bloop,
    "reel": reel, "creak": creak, "jerk": jerk, "hiss": hiss, "bulge": bulge, "jump": jump,
    "strain": strain, "snap": snap, "thrash": thrash, "hoist": hoist, "spook": spook,
    "hooked": hooked, "yank": yank, "flop": flop,
}


# --- output -----------------------------------------------------------------------------------

def write_wav(path, x, peak=0.7):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak  # about -3 dBFS
    fade = min(len(x), secs(0.01))
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def write_randomizer(path, name, pitch=1.06):
    lines = ['[gd_resource type="AudioStreamRandomizer" format=3]', ""]
    for i in range(VARIANTS):
        lines.append(f'[ext_resource type="AudioStream" path="res://audio/fishing/{name}_{i + 1:02d}.wav" id="{i + 1}"]')
    lines += ["", "[resource]", "playback_mode = 0", f"random_pitch = {pitch}",
              "random_volume_offset_db = 1.5", f"streams_count = {VARIANTS}"]
    for i in range(VARIANTS):
        lines += [f'stream_{i}/stream = ExtResource("{i + 1}")', f"stream_{i}/weight = 1.0"]
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


## Quieter cues are written quieter, so the game's volumes stay simple (peak per sound).
PEAKS = {"nibble": 0.4, "tap": 0.5, "reel": 0.45, "plip": 0.5, "creak": 0.5, "jerk": 0.6}


def main():
    os.makedirs(OUT, exist_ok=True)
    for k, (name, make) in enumerate(SOUNDS.items()):
        rng = np.random.default_rng(9000 + k)  # one seed per sound: adding one doesn't change the rest
        for i in range(VARIANTS):
            write_wav(os.path.join(OUT, f"{name}_{i + 1:02d}.wav"), make(rng), PEAKS.get(name, 0.7))
        write_randomizer(os.path.join(OUT, f"{name}.tres"), name, 1.02 if name in ("reel", "hiss") else 1.06)
        print("wrote", name)


if __name__ == "__main__":
    main()
