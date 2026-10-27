"""Synthesizes every gathering sound, woodcutting and mining (needs numpy):

    python tools/synth_gathering.py

Writes the clips to audio/gathering/<wood|stone>/[<voice>/]<sound>_NN.wav, an
AudioStreamRandomizer per sound beside them, and the layer stacks the scenes play
(audio/woodcutting/*.tres, audio/mining/*.tres, and each species' and ore's own copies in
audio/woodcutting/<species>/ and audio/mining/<ore>/).

Each event is one finished clip, mixed here, rather than layers summed in the game: an axe
blow is one sound with its bite, its body, its chips and the space round it already balanced.

How a sound is made (impact()): an object is a resonating body, dozens of resonances
(modes) spread over the spectrum with the levels and decay times measured off real wood and
stone strikes (see TARGETS), and a strike is a contact force: a short pulse whose length sets
how hard the meeting is (steel on stone is a fraction of a millisecond, a trunk on the ground
several). Everything else that happens in the blow, the crush of fibres, grit crumbling, chips
landing, goes through a body too, so it sounds like wood or stone and never like hiss. Then a
little outdoor space: a few early echoes off the ground and the trees, and a short, quiet,
dark tail.
"""
import os
import wave

import numpy as np

RATE = 48000
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "audio", "gathering")
LOUDNESS = -16.0  # dBFS, every clip's loudest 50 ms; the stacks set the mix from there
CEILING = -3.0  # dBFS, every clip's peaks (limit())

# The levels (dB per octave, relative) and how quickly each part of the spectrum dies that the
# bodies are built to, measured off real recordings of wooden and metal impacts: wood carries
# its strike at 250-1000 Hz and is quiet past 4 kHz; its mids fall 20 dB in 50-90 ms, its lows in
# 150-250. Stone is brighter (1-2 kHz) and deader still. Everything is short. (The levels are the
# body's; the contact pulse rolls the highs off on top, so wood's look brighter here than it ends.)
WOOD_LEVELS = ((60, -16), (125, -6), (250, 2), (500, 0), (1000, -1), (2000, -1), (4000, -4), (8000, -14))
STONE_LEVELS = ((60, -24), (125, -14), (250, -7), (500, -2), (1000, 0), (2000, -1), (4000, -5), (8000, -14))
TWIG_LEVELS = ((500, -14), (1000, -4), (2000, 0), (4000, -4), (8000, -16))
PEBBLE_LEVELS = ((1000, -10), (2000, -2), (4000, 0), (8000, -10))

# Each species' wood and each ore's stone next to the plain ones: `pitch` moves the body's
# resonances, `damp` how quickly they die (more = deader), `bright` tilts the spectrum
# (dB per octave above 1 kHz), `ring` is how long the pick rings off it, `crumble` how much grit
# a blow knocks loose. A thin birch is high, bright and quick; an oak low, dense and long.
# Iron's basalt is hard and rings; coal is soft, dull and crumbly; gold's quartz rings bright;
# crystal chimes.
SPECIES = {
    "birch": {"pitch": 1.22, "damp": 1.2, "bright": 1.5},
    "oak": {"pitch": 0.8, "damp": 0.85, "bright": -1.5},
    "pine": {"pitch": 0.93, "damp": 0.95, "bright": 0.0},
}
ORES = {
    "iron": {"pitch": 1.1, "damp": 0.85, "bright": 0.5, "ring": 1.5, "crumble": 0.6, "chime": 0.0},
    "coal": {"pitch": 0.8, "damp": 1.4, "bright": -2.5, "ring": 0.45, "crumble": 1.8, "chime": 0.0},
    "gold": {"pitch": 1.05, "damp": 0.95, "bright": 1.0, "ring": 1.25, "crumble": 0.8, "chime": 0.35},
    "crystal": {"pitch": 1.3, "damp": 0.7, "bright": 2.0, "ring": 1.6, "crumble": 0.4, "chime": 1.0},
}
PLAIN_WOOD = {"pitch": 1.0, "damp": 1.0, "bright": 0.0}
PLAIN_STONE = {"pitch": 1.0, "damp": 1.0, "bright": 0.0, "ring": 1.0, "crumble": 1.0, "chime": 0.0}


def secs(s):
    return int(round(s * RATE))


def t_axis(n):
    return np.arange(n) / RATE


# --- bodies and strikes ------------------------------------------------------------------------

def body(rng, lo, hi, count, tau200, levels, damp_exp=0.5, bright=0.0, spread=3.0):
    """A resonating body: `count` modes spread evenly (per octave) from lo to hi Hz, as
    (freq, decay, amp). A mode at 200 Hz dies over `tau200` s (to 1/e), higher ones faster
    ((f/200)^-damp_exp). Amplitudes put each octave's energy at `levels` ((Hz, dB) points),
    tilted by `bright` dB per octave above 1 kHz, give or take `spread` dB per mode."""
    f = np.sort(np.exp(rng.uniform(np.log(lo), np.log(hi), count)))
    tau = tau200 * (f / 200.0) ** -damp_exp * rng.uniform(0.8, 1.25, count)
    lf, ldb = np.log([p[0] for p in levels]), np.array([p[1] for p in levels], float)
    db = np.interp(np.log(f), lf, ldb) + bright * np.maximum(np.log2(f / 1000.0), 0) + rng.normal(0, spread, count)
    amp = 10 ** (db / 20) / np.sqrt(tau)  # energy per mode ~ amp^2 * tau: this sets energy, not peak
    return list(zip(f, tau, amp * rng.choice([-1.0, 1.0], count)))


def ring_of(modes, n):
    """A body's response to one sharp tap: every mode ringing down at once."""
    t = t_axis(n)
    out = np.zeros(n)
    for f, tau, a in modes:
        if f < RATE / 2.2:
            out += a * np.exp(-t / tau) * np.sin(2 * np.pi * f * t)
    return out


def pulse(length):
    """A contact force: half a sine `length` s long. A hard, quick meeting (steel on stone) is a
    fraction of a millisecond and bright; a soft or heavy one is longer and duller."""
    n = max(secs(length), 2)
    return np.sin(np.pi * (np.arange(n) + 0.5) / n)


def grains(rng, n, times, gains, length=(0.00008, 0.0002)):
    """Tiny contacts at `times` (s): crumbling, crushing, chips and grit landing."""
    out = np.zeros(n)
    for at, g in zip(times, gains):
        p = pulse(rng.uniform(*length)) * g * rng.choice([-1.0, 1.0])
        i = secs(at)
        if i < n:
            out[i:i + len(p)] += p[: n - i]
    return out


def strike(force, modes, n):
    """`force` (a contact signal) driving a body: the body's tap response convolved with it."""
    size = len(force) + n
    out = np.fft.irfft(np.fft.rfft(force, size) * np.fft.rfft(ring_of(modes, n), size), size)
    return out[:n]


def stick_slip(rng, n, rate_from, rate_to, wobble=0.3, contact=0.0004):
    """Friction grabbing and letting go at a rate sliding from rate_from to rate_to Hz, unevenly
    (an even rate is heard as a buzz): the contact signal of a creak or a scrape."""
    times, t, total = [], 0.0, n / RATE
    while t < total:
        times.append(t)
        rate = rate_from + (rate_to - rate_from) * t / total
        t += 1.0 / max(rate * (1.0 + rng.uniform(-wobble, wobble)), 1.0)
    return grains(rng, n, times, rng.uniform(0.5, 1.0, len(times)), (contact * 0.7, contact * 1.3))


def env(n, attack, hold, release):
    t = t_axis(n)
    e = np.clip(t / max(attack, 1e-6), 0, 1)
    return e * np.exp(-np.maximum(t - attack - hold, 0) / max(release, 1e-6))


def at(buf, sound, when, gain=1.0):
    i = secs(when)
    if i < len(buf):
        end = min(len(buf), i + len(sound))
        buf[i:end] += sound[: end - i] * gain


def lowpass_noise(rng, n, lo, hi):
    """Noise kept between lo and hi Hz with steep edges, for air and leaves only."""
    s = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    g = 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 6) / (1.0 + (f / hi) ** 8)
    out = np.fft.irfft(s * g, n)
    return out / (np.abs(out).max() + 1e-9)


def space(rng, x, size=1.0, wet=0.12):
    """The clip outdoors: a short, quiet, diffuse tail after it, darker as it goes (above 300 Hz
    only: a low noise tail rumbles and flickers). No single early echoes: one arriving a few ms
    after the sound fuses with it and notches its spectrum, and that's heard as hollow.
    `size` stretches the tail, `wet` sets its level."""
    m = secs(0.6 * size)
    n = len(x) + m
    t = t_axis(m)
    ir = np.zeros(m)
    for lo, hi, rt in ((300, 1500, 0.5 * size), (1500, 6000, 0.28 * size)):
        ir += lowpass_noise(rng, m, lo, hi) * np.exp(-t * 6.91 / rt) * (1.0 - np.exp(-t / 0.015))
    tail = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    tail *= np.sqrt(np.sum(x ** 2) / (np.sum(tail ** 2) + 1e-12)) * wet
    out = tail
    out[: len(x)] += x
    return out


def echo(rng, x, amount=1.0, size=1.0):
    """A rock face throwing the blow back: two slapbacks far enough behind it (about 0.12 and
    0.26 s) to be heard as echoes rather than colour, each darker and a little smeared, and a
    short tail after them. `amount` scales the echoes, `size` how far off the wall is."""
    n = len(x) + secs(0.9 * size)
    out = np.zeros(n)
    out[: len(x)] += x
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    X = np.fft.rfft(x, n)
    smear = np.fft.rfft(np.hanning(secs(0.004)) / np.hanning(secs(0.004)).sum(), n)
    for delay, gain, cutoff in ((0.12, 0.32, 4000), (0.26, 0.16, 2600)):
        d = delay * size * rng.uniform(0.92, 1.08)
        out += np.fft.irfft(X * smear * np.exp(-2j * np.pi * f * d) / (1 + (f / cutoff) ** 4), n) * gain * amount
    return space(rng, out, size * 1.2, 0.1)


def dsine(n, freq, tau, amp=1.0, phase=0.0):
    """One clean resonance: a sine dying over `tau` s, eased in over 0.1 ms so it doesn't click."""
    t = t_axis(n)
    return amp * np.sin(2 * np.pi * freq * t + phase) * np.exp(-t / tau) * (1.0 - np.exp(-t / 0.0001))


def burst(rng, n, lo, hi, decay, amp=1.0):
    """The crack of a hard meeting: a burst of bright noise only a millisecond or two long. That
    short, it's heard as crispness, not hiss."""
    t = t_axis(n)
    return amp * lowpass_noise(rng, n, lo, hi) * np.exp(-t / decay) * (1.0 - np.exp(-t / 0.00008))


def splinters(rng, n, count, span, lo, hi, gain, tau=0.0008):
    """A quick crackle of fibres or grit giving way: `count` tiny clean ticks over `span` s,
    thinning out."""
    out = np.zeros(n)
    for when in np.sort(rng.uniform(0.001, span, count)):
        g = gain * rng.uniform(0.3, 1.0) * np.exp(-when / (span * 0.4))
        at(out, dsine(secs(0.01), np.exp(rng.uniform(np.log(lo), np.log(hi))), tau, g, rng.uniform(0, 6.28)), when)
    return out


# --- finishing --------------------------------------------------------------------------------

def loudness(x, window=0.05):
    k = min(secs(window), len(x))
    return np.sqrt(np.convolve(x * x, np.ones(k) / k, mode="valid")).max()


def limit(x, ceiling_db=CEILING, ahead=0.0015, release=0.04):
    """Peaks held under the ceiling by turning the sound down smoothly round them (never by
    bending samples, which crackles)."""
    ceiling = 10 ** (ceiling_db / 20)
    need = np.minimum(1.0, ceiling / np.maximum(np.abs(x), 1e-9))
    if need.min() >= 1.0:
        return x
    w = max(secs(ahead), 1)
    gain = np.lib.stride_tricks.sliding_window_view(np.concatenate([np.ones(w), need, np.ones(w)]), 2 * w + 1).min(axis=1)
    i = np.arange(len(gain)) / secs(release)
    gain = 1.0 - np.exp(np.maximum.accumulate(np.log(np.maximum(1.0 - gain, 1e-12)) + i) - i)
    gain = np.convolve(gain, np.ones(w) / w, mode="same")
    return x * np.minimum(gain, need)


def highpass(x, cutoff=20.0):
    """Everything under `cutoff` Hz taken out, the offset (DC) above all. A struck body's thump
    leaves a net push in the waveform; left in, it rides under the whole clip, eats headroom,
    and the fade at the end turns it into a thump of its own."""
    size = len(x) + secs(0.2)
    f = np.fft.rfftfreq(size, 1.0 / RATE)
    g = f ** 4 / (f ** 4 + cutoff ** 4)
    return np.fft.irfft(np.fft.rfft(x, size) * g, size)[: len(x)]


def finish(x, tail_db=-60.0):
    """Offset and rumble out (highpass()), cut once it has died `tail_db` under its peak, fade
    the ends, bring it to LOUDNESS, keep its peaks under CEILING."""
    x = highpass(x)
    k = secs(0.02)
    lev = np.sqrt(np.convolve(x * x, np.ones(k) / k, mode="same"))
    alive = np.nonzero(lev > lev.max() * 10 ** (tail_db / 20))[0]
    x = x[: alive[-1] + 1] if len(alive) else x
    fade_in, fade_out = min(secs(0.0005), len(x) // 4), min(secs(0.04), len(x) // 3)
    x[:fade_in] *= np.linspace(0, 1, fade_in)
    x[len(x) - fade_out:] *= np.linspace(1, 0, fade_out) ** 2
    x *= 10 ** (LOUDNESS / 20) / max(loudness(x), 1e-9)
    return limit(x)


def punch(n, f_from, f_to, sweep, decay, amp=1.0):
    """Weight under a blow: a low note dropping from f_from to f_to Hz within `sweep` s, dying
    over `decay` s, like a kick drum's; it starts on a zero crossing so it thumps without a click."""
    t = t_axis(n)
    f = f_to + (f_from - f_to) * np.exp(-t / sweep)
    return amp * np.sin(2 * np.pi * np.cumsum(f) / RATE) * (1.0 - np.exp(-t / 0.0006)) * np.exp(-t / decay)


# --- woodcutting ------------------------------------------------------------------------------

def trunk(rng, v, lo=130.0, hi=7000.0, count=56, tau=0.075):
    """A standing trunk's body."""
    return body(rng, lo * v["pitch"], hi, count, tau / v["damp"], WOOD_LEVELS, 0.5, v["bright"])


def twigs(rng):
    return body(rng, 900, 9000, 24, 0.012, TWIG_LEVELS, 0.4)


def gsine(n, freq, tau, amp, phase, drop, over):
    """A resonance whose pitch sinks by `drop` (a share) over `over` s as it rings: a body
    being loaded as something drives into it."""
    t = t_axis(n)
    f = freq * (1.0 - drop * (1.0 - np.exp(-t / over)))
    return amp * np.sin(2 * np.pi * np.cumsum(f) / RATE + phase) * np.exp(-t / tau) * (1.0 - np.exp(-t / 0.0001))


def chop(rng, v=PLAIN_WOOD, tone=1.05, crack=3.0, wedge=1.15, weight=1.3, length=0.75, snap=1.8, sink=2.1):
    """An axe biting deep into a dense log, one solid blow and nothing after it:
    - the edge's crack: a couple of ms of noise and the steel's tick (dense wood doesn't
      splinter, so it's a 'tchak', not a crackle);
    - the sink: the blade driving on into the wood for 10-25 ms after the crack: the wedge's
      'chunk' sliding lower as it slows, the fibres packing under the edge (a dense, dull crunch
      inside the blow), a second, lower push from the follow-through ~8 ms on;
    - the log: a dense, heavily damped body (its note around 330 Hz on a plain trunk, bending a
      little down as the blade loads it, a lower one under it), over in ~40 ms;
    - the weight: a low thump dropping to ~95 Hz.
    Almost dry. `tone` moves the log's pitch, `length` how long it rings, `crack`, `wedge` and
    `weight` scale those parts, `snap` stretches the crack (longer, brighter), `sink` how deep
    and long the blade drives in (0: it stops dead). The defaults are the takes picked by ear
    (C of the deep-bite round, then C of the crack round), with the sink set between the sink
    round's C and D, which were judged about equal."""
    n = secs(0.4)
    p, d, b = v["pitch"], v["damp"], 10 ** (v["bright"] / 20)
    out = burst(rng, n, 1800, 7000 + 2000 * (snap - 1.0), 0.0012 * snap, 0.8 * crack * b)
    out += dsine(n, rng.uniform(2300, 2700), 0.003 * snap, 0.3 * crack * b)
    out += dsine(n, rng.uniform(3600, 4100), 0.002 * snap, 0.15 * crack * b)  # the steel's edge ringing a hair
    out += burst(rng, n, 250, 1600, 0.006, 0.9 * wedge)
    if sink > 0:
        drive = burst(rng, n, 100, 500, 0.018 * sink, 1.0 * wedge * sink)  # the chunk going on, lower, as it slows
        at(out, drive * (1.0 - np.exp(-t_axis(n) / 0.004)), 0.004)
        out += splinters(rng, n, int(rng.integers(8, 12) * sink) + 1, 0.025 * sink, 200, 700, 0.15 * sink, 0.003)
        at(out, punch(secs(0.15), 160 * p, 75 * p, 0.008, 0.04, 0.7 * sink * weight), 0.01 * rng.uniform(0.9, 1.15))
    f1 = rng.uniform(290, 330) * p * tone
    drop = 0.1 * sink
    for ratio, tau, amp in ((1.0, 0.022, 1.0), (1.93, 0.013, 0.5), (3.3, 0.007, 0.28)):
        out += gsine(n, f1 * ratio * rng.uniform(0.99, 1.01), tau * length / d, amp, rng.uniform(0, 0.4), drop, 0.02)
    out += gsine(n, f1 * 0.55, 0.03 * length / d, 0.55, 0.0, drop, 0.02)  # the log's mass, under its note
    out += punch(n, 230 * p, 95 * p, 0.007, 0.04 * length, 0.75 * weight)
    return space(rng, out, 0.6, 0.04)


def clean_cut(rng, v=PLAIN_WOOD):
    """The blow that goes clean through: a harder, heavier bite that sinks further."""
    return chop(rng, v, tone=0.95, crack=3.3, wedge=1.2, weight=1.3, length=1.15, sink=1.4)


def pull(rng, v=PLAIN_WOOD):
    """The axe worked loose: the head grinding in the cut for a moment, a creak, a last tick."""
    n = secs(rng.uniform(0.18, 0.26))
    grip = stick_slip(rng, n, rng.uniform(55, 70), rng.uniform(110, 150), contact=0.0005)
    grip *= env(n, n / RATE * 0.3, 0.0, n / RATE * 0.35)
    out = strike(grip, trunk(rng, v, lo=300, count=40, tau=0.03), n + secs(0.15))
    at(out, strike(pulse(0.0004), trunk(rng, v, lo=500, count=30, tau=0.02), secs(0.12)), n / RATE * 0.9, 0.5)
    return space(rng, out, wet=0.08)


def creak(rng, v=PLAIN_WOOD):
    """The trunk straining as the cut opens: wood grinding on wood in slow, uneven grabs."""
    length = rng.uniform(0.6, 1.0)
    n = secs(length)
    grabs = stick_slip(rng, n, rng.uniform(16, 22), rng.uniform(30, 44), wobble=0.35, contact=0.0012)
    grabs *= env(n, length * 0.3, length * 0.25, length * 0.2)
    modes = body(rng, 140 * v["pitch"], 2500, 36, 0.05 / v["damp"], WOOD_LEVELS, 0.6, v["bright"] - 2)
    return space(rng, strike(grabs, modes, n + secs(0.15)), 1.1)


def fall(rng, v=PLAIN_WOOD):
    """The crown sweeping down: leaves and twigs rushing through the air, swelling as it falls
    faster, twigs snapping on the way."""
    n = secs(2.2)
    t = t_axis(n)
    swell = np.clip(t / 1.6, 0, 1) ** 2.4 * np.clip((2.15 - t) / 0.12, 0, 1)
    flutter = np.convolve(np.repeat(rng.uniform(0.45, 1.0, n // secs(0.03) + 1), secs(0.03))[:n],
                          np.ones(secs(0.02)) / secs(0.02), mode="same")
    air = lowpass_noise(rng, n, 250, 1400) * 0.8 + lowpass_noise(rng, n, 1200, 4200) * 0.35 * flutter
    out = air * swell * 0.25
    snaps = np.sort(rng.uniform(0.5, 2.0, 14))
    out += strike(grains(rng, n, snaps, rng.uniform(0.2, 0.7, 14) * np.interp(snaps, [0, 2.2], [0.3, 1.0])),
                  twigs(rng), n) * 0.5
    return space(rng, out, 1.4)


def land(rng, v=PLAIN_WOOD):
    """The trunk landing: a heavy wooden thud and the ground taking it, a bounce or two, and the
    crown crashing down round it in a burst of breaking twigs."""
    n = secs(1.4)
    modes = body(rng, 55 * v["pitch"], 3000, 48, 0.12 / v["damp"], WOOD_LEVELS, 0.55, v["bright"] - 1)
    ground = [(rng.uniform(48, 56), 0.07, 3.0), (rng.uniform(78, 90), 0.05, 2.0)]
    force = np.zeros(n)
    for when, g in ((0.0, 1.0), (rng.uniform(0.17, 0.21), 0.4), (rng.uniform(0.31, 0.36), 0.15)):
        at(force, pulse(rng.uniform(0.003, 0.005)), when, g)
        at(force, pulse(0.0005), when, g * 0.35)  # the bark and branches meeting the ground first: the crack in it
    out = strike(force, modes + ground, n)
    crash = np.sort(rng.gamma(1.4, 0.08, rng.integers(60, 90)))
    crash = crash[crash < 0.9]
    out += strike(grains(rng, n, crash, rng.uniform(0.2, 1.0, len(crash)) * np.exp(-crash / 0.3), (0.0001, 0.0004)),
                  twigs(rng), n) * 0.9
    leaves = lowpass_noise(rng, n, 400, 3500) * env(n, 0.01, 0.05, 0.18) * 0.05
    return space(rng, out + leaves, 1.5, 0.16)


# --- mining -----------------------------------------------------------------------------------

def stone(rng, v, lo=260.0, hi=10000.0, count=64, tau=0.036):
    """A boulder's face: dense, stiff, lossy."""
    return body(rng, lo * v["pitch"], hi, count, tau / v["damp"], STONE_LEVELS, 0.5, v["bright"])


def pebbles(rng):
    return body(rng, 1500, 10000, 20, 0.008, PEBBLE_LEVELS, 0.4)


def pick_ring(rng, v, n):
    """The pick's steel ringing off the rock: a bar's partials (1 : 2.76 : 5.40), the clink.
    How long it rings is the rock's: a hard ore lets it sing, coal smothers it. Crystal and
    gold add their own glassy chime."""
    f0 = rng.uniform(1900, 2250)
    tau = 0.055 * v["ring"]
    modes = [(f0, tau, 1.0), (f0 * 2.756, tau * 0.55, 0.5), (f0 * 5.404, tau * 0.3, 0.22)]
    if v["chime"] > 0:
        base = rng.uniform(2600, 3000)
        modes += [(base * r, 0.16 * v["chime"] + 0.05, 0.5 * v["chime"]) for r in (1.0, 1.5, 2.25)]
    return strike(pulse(0.00025), modes, n)


def mine(rng, v=PLAIN_STONE, ring=1.6, echoes=1.6, clink=1.0):
    """A pickaxe blow, metally and clinky: the stone's tick as the point bites (a burst of
    crack and a short knock), the steel ringing out over it (a bar's partials, the lead of the
    sound), a short thump for weight, a little grit, and the rock face throwing it back
    (echo()). `ring` stretches the ring, `echoes` scales the echo, `clink` moves its pitch."""
    n = secs(1.0)
    p = v["pitch"]
    out = burst(rng, n, 2000, 8000, 0.0009, 0.6)
    out += dsine(n, rng.uniform(1150, 1450) * p, 0.009 / v["damp"], 0.4) + \
        dsine(n, rng.uniform(1900, 2300) * p, 0.005 / v["damp"], 0.22) +         dsine(n, rng.uniform(640, 780) * p, 0.012 / v["damp"], 0.35)  # the boulder's own knock
    f0 = rng.uniform(2350, 2650) * clink * (1.0 + 0.15 * (p - 1.0))
    tau = 0.13 * v["ring"] * ring
    for r, k, amp in ((1.0, 1.0, 0.8), (1.47, 0.65, 0.3), (2.76, 0.45, 0.4), (5.40, 0.2, 0.16)):
        out += dsine(n, f0 * r * rng.uniform(0.997, 1.003), tau * k, amp, rng.uniform(0, 0.5))
    if v["chime"] > 0:  # gold's and crystal's own glassy notes ringing with it
        base = rng.uniform(3300, 3700)
        for r in (1.0, 1.33, 1.78):
            out += dsine(n, base * r, (0.12 + 0.25 * v["chime"]) * ring, 0.25 * v["chime"], rng.uniform(0, 6.28))
    out += punch(n, 300 * p, 130 * p, 0.006, 0.026, 0.65)
    out += splinters(rng, n, int(rng.integers(5, 9) * v["crumble"]) + 1, 0.2, 2500, 7000, 0.06, 0.002)
    return echo(rng, out, echoes)


def crack(rng, v=PLAIN_STONE):
    """A crack running through the stone: snaps coming faster as it races along, each with a
    little ring off the fresh faces, echoing."""
    length = rng.uniform(0.22, 0.36)
    n = secs(length + 0.3)
    out = np.zeros(n)
    gaps = np.geomspace(0.035, 0.005, rng.integers(9, 14))
    for k, when in enumerate(np.cumsum(gaps)):
        if when > length:
            break
        g = (0.4 + 0.6 * k / len(gaps)) * rng.uniform(0.7, 1.0)
        snap = burst(rng, secs(0.03), 2200, 8000, 0.0006, g * 0.6)
        snap += dsine(secs(0.03), rng.uniform(1600, 2600) * v["pitch"], 0.004, g * 0.4, rng.uniform(0, 6.28))
        at(out, snap, when)
    out += dsine(n, rng.uniform(2800, 3300) * v["pitch"], 0.05 * v["ring"], 0.12)
    return echo(rng, out, 1.3)


def split(rng, v=PLAIN_STONE):
    """A piece breaking away: a heavy crack and knock, a grinding crunch as it parts, the pick's
    ring, the chunk tumbling down in a few knocks, all echoing off the rock."""
    n = secs(1.0)
    p = v["pitch"]
    out = burst(rng, n, 1500, 7000, 0.0016, 0.7)
    out += punch(n, 220 * p, 85 * p, 0.01, 0.05, 1.0)
    for f, tau, amp in ((rng.uniform(380, 460), 0.025, 0.6), (rng.uniform(900, 1100), 0.014, 0.4)):
        out += dsine(n, f * p, tau / v["damp"], amp)
    out += splinters(rng, n, int(rng.integers(30, 45) * v["crumble"]) + 6, 0.07, 1200, 6000, 0.3, 0.0012)
    f0 = rng.uniform(2350, 2650)
    for r, k, amp in ((1.0, 1.0, 0.35), (2.76, 0.45, 0.18)):
        out += dsine(n, f0 * r, 0.1 * v["ring"] * k, amp)
    when, g = rng.uniform(0.16, 0.22), 0.5
    for _ in range(rng.integers(2, 4)):
        knock = burst(rng, secs(0.1), 1000, 5000, 0.001, g * 0.5)
        knock += dsine(secs(0.1), rng.uniform(600, 900) * p, 0.012, g) + punch(secs(0.1), 200 * p, 110 * p, 0.005, 0.02, g * 0.6)
        at(out, knock, when)
        when += rng.uniform(0.1, 0.17)
        g *= rng.uniform(0.4, 0.6)
    return echo(rng, out, 1.4, 1.1)


def slab(rng, v=PLAIN_STONE):
    """A loose slab of an ore wall coming away: a deep crack, the slab grinding as it slides off
    the rock behind, then the heavy fall, its pieces knocking apart on the ground and a patter of
    grit after, all thrown back by the quarry walls."""
    n = secs(1.7)
    out = burst(rng, n, 900, 5000, 0.0025, 0.6)
    out += punch(n, 160, 55, 0.02, 0.09, 1.2)
    out += splinters(rng, n, int(rng.integers(40, 60)), 0.12, 800, 5000, 0.25, 0.0015)
    slide = secs(rng.uniform(0.28, 0.36))
    grip = stick_slip(rng, slide, rng.uniform(40, 60), rng.uniform(90, 130), wobble=0.5, contact=0.0006)
    grip *= env(slide, 0.03, slide / RATE * 0.4, slide / RATE * 0.4)
    at(out, strike(grip, stone(rng, v, lo=250, count=40, tau=0.03), slide + secs(0.1)) * 0.5, 0.06)
    when, g = rng.uniform(0.42, 0.5), 1.0
    for _ in range(rng.integers(4, 6)):
        knock = burst(rng, secs(0.15), 700, 4000, 0.0015, g * 0.5)
        knock += punch(secs(0.15), rng.uniform(150, 190), rng.uniform(65, 85), 0.008, 0.05, g)
        knock += dsine(secs(0.15), rng.uniform(380, 620), 0.018, g * 0.6)
        at(out, knock, when)
        when += rng.uniform(0.05, 0.13)
        g *= rng.uniform(0.55, 0.8)
    grit = grains(rng, secs(0.6), np.sort(rng.uniform(0.0, 0.45, 40)), rng.uniform(0.2, 0.7, 40))
    at(out, strike(grit, pebbles(rng), secs(0.7)), when, 0.4)
    return echo(rng, out, 1.6, 1.3)


def scrape(rng, v=PLAIN_STONE):
    """The point dragged out of the rock: steel grinding on stone, catching unevenly."""
    n = secs(rng.uniform(0.16, 0.24))
    grip = stick_slip(rng, n, rng.uniform(90, 130), rng.uniform(160, 240), wobble=0.4, contact=0.00025)
    grip *= env(n, 0.01, n / RATE * 0.3, n / RATE * 0.3)
    out = strike(grip, stone(rng, v, lo=700, count=40, tau=0.02), n + secs(0.1))
    out += strike(grip, [(rng.uniform(1900, 2250), 0.015, 1.0)], n + secs(0.1)) * 0.05
    return space(rng, out, wet=0.08)


def pebble(rng, v=PLAIN_STONE):
    """One chip landing on stone: a tiny, bright, dead tick."""
    n = secs(0.08)
    return strike(pulse(rng.uniform(0.0001, 0.0002)), pebbles(rng), n)


def whoosh(rng, v=None):
    """The tool coming down: air rushing past it, its pitch rising to the fastest moment and
    falling. Air is the one sound here that's noise; kept below 2.5 kHz, it's a 'whum', not a
    hiss."""
    n = secs(rng.uniform(0.24, 0.32))
    win, hop = secs(0.02), secs(0.01)
    out = np.zeros(n + win)
    f = np.fft.rfftfreq(win, 1.0 / RATE)
    peak = rng.uniform(550, 800)
    centres = np.interp(np.linspace(0, 1, n // hop + 1), [0, 0.6, 1], [220, peak, 260])
    for k, start in enumerate(range(0, n, hop)):
        g = np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / centres[k]) / 0.55) ** 2) / (1 + (f / 2500) ** 6)
        out[start:start + win] += np.fft.irfft(np.fft.rfft(rng.standard_normal(win)) * g, win) * np.hanning(win)
    out = out[:n]
    t = np.linspace(0, 1, n)
    return out * np.sin(np.pi * t ** 0.8) ** 2


def rustle(rng, v=None):
    """Raising the tool: sleeves and the leather grip, soft."""
    n = secs(rng.uniform(0.3, 0.4))
    t = np.linspace(0, 1, n)
    cloth = lowpass_noise(rng, n, 300, 2200) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * rng.uniform(5, 8) * t * n / RATE)))
    out = cloth * np.sin(np.pi * t) ** 1.5 * 0.3
    leather = body(rng, 300, 2500, 16, 0.02, ((300, 0), (1000, -4), (2500, -12)), 0.5)
    out += strike(stick_slip(rng, n, 25, 40, contact=0.0015) * env(n, 0.08, 0.05, 0.06), leather, n) * 0.4
    return out


# --- the sets and their stacks -----------------------------------------------------------------

# (sound, variants, build): a clip set per sound, baked plain and, for VOICED ones, per voice.
WOOD = [("chop", 8, chop), ("clean_cut", 4, clean_cut), ("pull", 4, pull), ("creak", 4, creak),
        ("fall", 2, fall), ("land", 3, land)]
STONE = [("mine", 8, mine), ("crack", 5, crack), ("split", 4, split), ("scrape", 4, scrape),
         ("pebble", 6, pebble), ("whoosh", 6, whoosh), ("rustle", 4, rustle), ("slab", 3, slab)]
WOOD_VOICED = ("chop", "creak", "land")
STONE_VOICED = ("mine", "crack", "split")

# Each stack: (file under audio/, its layers, the voiced folder it gets per species or ore or
# None). A layer: (group/sound, volume dB, pitch jitter, follows the caller's pitch, delay s).
# bus / unit_size / max_distance as before.
STACKS = {
    "woodcutting/axe_hit": ([("wood/chop", 3.0, 0.04, True, 0.0)], "voiced", {}),
    "woodcutting/clean_cut": ([("wood/clean_cut", 1.0, 0.04, True, 0.0)], None, {}),
    "woodcutting/axe_pull": ([("wood/pull", -6.0, 0.06, True, 0.0)], None, {}),
    "woodcutting/trunk_creak": ([("wood/creak", -3.0, 0.05, True, 0.0)], "voiced", {"unit_size": 5.0, "max_distance": 45.0}),
    "woodcutting/tree_fall": ([("wood/fall", -2.0, 0.04, True, 0.0)], None, {"unit_size": 8.0, "max_distance": 70.0}),
    "woodcutting/tree_land": ([("wood/land", 2.0, 0.04, True, 0.0)], "voiced", {"unit_size": 8.0, "max_distance": 80.0}),
    "mining/pickaxe_hit": ([("stone/mine", 0.0, 0.04, True, 0.0)], "voiced", {}),
    "mining/crack_tip": ([("stone/crack", 2.0, 0.04, True, 0.0)], "voiced", {}),
    "mining/split": ([("stone/split", 2.0, 0.04, True, 0.0)], "voiced", {}),
    "mining/slab": ([("stone/slab", 3.0, 0.05, True, 0.0)], None, {"unit_size": 6.0, "max_distance": 60.0}),
    "mining/pickaxe_pull": ([("stone/scrape", -8.0, 0.06, True, 0.0)], None, {}),
    "mining/debris_stone": ([("stone/pebble", -2.0, 0.12, True, 0.0)], None,
                            {"bus": "Debris", "unit_size": 2.5, "max_distance": 30.0}),
    "mining/pickaxe_swing": ([("stone/whoosh", -6.0, 0.06, True, 0.0)], None, {}),
    "mining/pickaxe_windup": ([("stone/rustle", -10.0, 0.06, True, 0.0)], None, {}),
}


def write_wav(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def write_randomizer(folder, sound, count):
    res = "res://" + os.path.relpath(folder, ROOT).replace(os.sep, "/")
    lines = ['[gd_resource type="AudioStreamRandomizer" format=3]', ""]
    lines += [f'[ext_resource type="AudioStream" path="{res}/{sound}_{i + 1:02d}.wav" id="{i + 1}"]' for i in range(count)]
    lines += ["", "[resource]", "playback_mode = 0", "random_pitch = 1.0", "random_volume_offset_db = 0.5",
              f"streams_count = {count}"]
    for i in range(count):
        lines += [f'stream_{i}/stream = ExtResource("{i + 1}")', f"stream_{i}/weight = 1.0"]
    with open(os.path.join(folder, sound + ".tres"), "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def bake(group, sounds, voice, voice_name, seed):
    folder = os.path.join(OUT, group, voice_name) if voice_name else os.path.join(OUT, group)
    os.makedirs(folder, exist_ok=True)
    keep = set()
    for k, (sound, count, build) in enumerate(sounds):
        rng = np.random.default_rng(seed * 100 + k)  # each sound its own stream: one changing leaves the rest
        for i in range(count):
            name = f"{sound}_{i + 1:02d}.wav"
            write_wav(os.path.join(folder, name), finish(build(rng, voice) if voice else build(rng)))
            keep |= {name, name + ".import"}
        write_randomizer(folder, sound, count)
        keep.add(sound + ".tres")
        print(f"{group}/{voice_name + '/' if voice_name else ''}{sound} x{count}")
    for old in os.listdir(folder):  # clips a smaller set no longer makes
        if os.path.isfile(os.path.join(folder, old)) and old not in keep:
            os.remove(os.path.join(folder, old))


def write_stack(path, layers, settings, voice_name=None):
    lines = ['[gd_resource type="Resource" script_class="SoundLayers" format=3]', "",
             '[ext_resource type="Script" path="res://scripts/sound_layers.gd" id="1_layers"]',
             '[ext_resource type="Script" path="res://scripts/sound_layer.gd" id="2_layer"]']
    for i, (stream, *_rest) in enumerate(layers):
        group, sound = stream.split("/")
        res = f"res://audio/gathering/{group}/" + (f"{voice_name}/" if voice_name else "") + f"{sound}.tres"
        lines.append(f'[ext_resource type="AudioStream" path="{res}" id="s{i}"]')
    for i, (stream, volume, jitter, follows, delay) in enumerate(layers):
        lines += ["", f'[sub_resource type="Resource" id="Layer_{i}"]', 'script = ExtResource("2_layer")',
                  f'stream = ExtResource("s{i}")']
        if delay:
            lines.append(f"delay = {delay}")
        if volume:
            lines.append(f"volume_db = {volume}")
        lines.append(f"pitch_jitter = {jitter}")
        if not follows:
            lines.append("follows_pitch = false")
        lines.append(f'resource_name = "{stream.split("/")[1]}"')
    lines += ["", "[resource]", 'script = ExtResource("1_layers")',
              'layers = Array[ExtResource("2_layer")]([' + ", ".join(f'SubResource("Layer_{i}")' for i in range(len(layers))) + "])"]
    if "bus" in settings:
        lines.append(f'bus = &"{settings["bus"]}"')
    for key in ("unit_size", "max_distance"):
        if key in settings:
            lines.append(f"{key} = {settings[key]}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    bake("wood", WOOD, None, None, 1)
    bake("stone", STONE, None, None, 2)
    for k, (name, voice) in enumerate(SPECIES.items()):
        bake("wood", [s for s in WOOD if s[0] in WOOD_VOICED], voice, name, 10 + k)
    for k, (name, voice) in enumerate(ORES.items()):
        bake("stone", [s for s in STONE if s[0] in STONE_VOICED], voice, name, 20 + k)
    for stack, (layers, voiced, settings) in STACKS.items():
        write_stack(os.path.join(ROOT, "audio", stack + ".tres"), layers, settings)
        if voiced:
            area, name = stack.split("/")
            for voice_name in (SPECIES if area == "woodcutting" else ORES):
                write_stack(os.path.join(ROOT, "audio", area, voice_name, name + ".tres"), layers, settings, voice_name)
    print("stacks written")


if __name__ == "__main__":
    main()
