"""Synthesizes the woodcutting sounds (needs numpy):

    python tools/synth_wood_sounds.py

Writes audio/woodcutting/sfx/<layer>_NN.wav and <layer>.tres (an AudioStreamRandomizer picking
one), which the layered stacks in audio/woodcutting/ play (axe_hit, axe_pull, clean_cut,
trunk_creak, tree_fall, tree_land). Every clip is mono, 48 kHz, faded, and brought to the same loudness (its loudest
50 ms at LOUDNESS), so the stacks set the mix.

Built from a few physical pieces rather than recordings:
- mode(): a struck wooden body is a handful of resonances ringing down at once, low ones longest.
- shaped(): noise filtered to a band, for the scuff of fibres, air and leaves.
- clicks(): many tiny snaps in a row: fibres giving way, chips landing.
- stick_slip(): friction that grabs and lets go dozens of times a second, ringing the body each
  time: a creak.
"""
import os
import wave

import numpy as np

RATE = 48000
LOUDNESS = -14.0  # dBFS, the loudest 50 ms of every clip
OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "woodcutting", "sfx")


def secs(s):
    return int(s * RATE)


def t_axis(n):
    return np.arange(n) / RATE


def mode(n, freq, decay, amp=1.0, phase=0.0, glide=0.0, attack=0.0):
    """One resonance: a sine at `freq` (Hz) dying away over `decay` (s), its pitch sliding by
    `glide` (a share, down as it rings) the way a struck plank's does. `attack` (s) eases it in:
    a rub or a heavy body swells up, where a strike starts at once (and clicks)."""
    t = t_axis(n)
    f = freq * (1.0 - glide * (1.0 - np.exp(-t / max(decay, 1e-4))))
    e = np.exp(-t / decay)
    if attack > 0:
        e *= 1.0 - np.exp(-t / attack)
    return amp * np.sin(2 * np.pi * np.cumsum(f) / RATE + phase) * e


def shaped(rng, n, lo, hi, tilt=0.0):
    """White noise kept between lo and hi Hz (soft edges), tilted darker by `tilt` dB/octave."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    gain = 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4) / (1.0 + (f / hi) ** 4)
    if tilt:
        gain *= (np.maximum(f, 20.0) / 1000.0) ** (tilt / 6.02)
    out = np.fft.irfft(spec * gain, n)
    return out / (np.abs(out).max() + 1e-9)


def env(n, attack, decay, hold=0.0):
    t = t_axis(n)
    e = np.exp(-np.maximum(t - attack - hold, 0.0) / decay)
    if attack > 0:
        e *= np.clip(t / attack, 0.0, 1.0)
    return e


def place(buf, sound, at, gain=1.0):
    i = secs(at)
    if i >= len(buf):
        return
    end = min(len(buf), i + len(sound))
    buf[i:end] += sound[: end - i] * gain


def snap(rng, lo=1200, hi=6000, length=0.006, ring=None):
    """One tiny crack: a few ms of bright noise, and optionally the splinter ringing after."""
    n = secs(length)
    s = shaped(rng, n, lo, hi) * env(n, 0.0003, length / 4)
    if ring:
        m = secs(ring[1] * 6)
        s = np.concatenate([s, np.zeros(max(m - n, 0))])
        s[:m] += mode(m, ring[0], ring[1], 0.4, rng.uniform(0, 6.28))
    return s


def clicks(rng, n, times, gains, lo=1200, hi=6000, length=0.005, ring=None):
    """Snaps at `times` (s), each at its gain."""
    out = np.zeros(n)
    for at, g in zip(times, gains):
        r = (ring[0] * rng.uniform(0.8, 1.25), ring[1]) if ring else None
        place(out, snap(rng, lo, hi, length * rng.uniform(0.6, 1.4), r), at, g)
    return out


def stick_slip(rng, n, rate_from, rate_to, body, wobble=0.25):
    """Friction grabbing and slipping at a rate sliding from rate_from to rate_to (Hz), every slip
    ringing `body` ((freq, decay, amp) modes). That's a creak."""
    out = np.zeros(n)
    t = 0.0
    total = n / RATE
    while t < total:
        rate = rate_from + (rate_to - rate_from) * t / total
        rate *= 1.0 + rng.uniform(-wobble, wobble)
        m = secs(0.06)
        pulse = np.zeros(m)
        for freq, decay, amp in body:
            pulse += mode(m, freq * rng.uniform(0.97, 1.03), decay, amp, rng.uniform(0, 6.28), attack=0.002)
        place(out, pulse, t, rng.uniform(0.6, 1.0))
        t += 1.0 / max(rate, 1.0)
    return out


SPLIT_HZ = 280


def reverb(rng, clip, length, high_t, predelay=0.02, taps=6):
    """The space round a blow, baked in (wet only, about as loud as `clip` above SPLIT_HZ): an
    impulse response of noise dying away, the highs (lasting `high_t` s to -60 dB) faster than
    the mids, so the tail darkens as it goes. A few early echoes (`taps`, 15-90 ms) are the trunks
    and rocks close by. The lows aren't reverberated: a noise tail down there is a band of rumble
    a couple of hundred Hz wide whose loudness flickers every few ms, heard as grit at the end of
    a boom. bloom() lets the low notes ring on instead."""
    n = secs(length)
    t = t_axis(n)
    swell = 1.0 - np.exp(-t / 0.012)  # the tail builds up from the echoes rather than jumping in
    ir = sum(shaped(rng, n, lo, hi) * np.exp(-t * 6.91 / rt) * g
             for lo, hi, rt, g in ((SPLIT_HZ, 1800, high_t * 1.6, 1.0), (1800, 9000, high_t, 0.45))) * swell
    for at in rng.uniform(0.015, 0.09, taps):
        echo = shaped(rng, secs(0.01), 120, 4000, tilt=-2) * env(secs(0.01), 0.0005, 0.002)
        place(ir, echo, at, rng.uniform(0.3, 0.7) * np.exp(-at / 0.05))
    ir = np.concatenate([np.zeros(secs(predelay)), ir])
    size = len(clip) + len(ir)
    highs = np.fft.rfft(clip, size) * (1.0 - 1.0 / (1.0 + (np.fft.rfftfreq(size, 1.0 / RATE) / SPLIT_HZ) ** 8))
    wet = np.fft.irfft(highs * np.fft.rfft(ir, size), size)
    return wet * np.sqrt(np.sum(np.abs(highs) ** 2) / (np.sum(np.abs(np.fft.rfft(wet)) ** 2) + 1e-12))


def bloom(rng, body, length, high_t, notes=(), low_t=1.5, dry=0.6, wet=1.0, hang=0.35):
    """`body` with its tail after it, as one clip: the dry blow, its space, and its low `notes`
    ((Hz, amp) pairs, the amps those of the body's own modes) ringing on, swelling in over 40 ms
    and dying over `low_t` s (to -60 dB): pure tones, so the boom hangs smoothly. Each is a hair
    off the body's note, so the two drift slowly in and out, the way a boom swims in a space.
    Cut where it has died 60 dB under the blow (a long silent end only holds a voice)."""
    out = reverb(rng, body, length, high_t) * wet
    out[: len(body)] += body * dry
    for freq, amp in notes:
        out += mode(len(out), freq * rng.uniform(0.996, 1.004), low_t / 6.91, amp * hang, rng.uniform(0, 6.28),
                    attack=0.04)
    level = np.sqrt(np.convolve(out * out, np.ones(secs(0.02)) / secs(0.02), mode="same"))
    alive = np.nonzero(level > level.max() * 1e-3)[0]
    return out[: alive[-1] + 1] if len(alive) else out


# --- the sounds ------------------------------------------------------------------------------

# How each species' wood rings next to the starter tree's: its resonances shifted in pitch and
# lasting longer or shorter. A thin birch rings high and dies fast, a dense oak low and long, a
# pine in between, a little longer. Only the layers that are the trunk's own body are voiced
# (VOICED); the edge's bite, the chips and the leaves sound the same on any tree.
NEUTRAL = {"pitch": 1.0, "decay": 1.0}
VOICES = {
    "birch": {"pitch": 1.3, "decay": 0.75},
    "oak": {"pitch": 0.78, "decay": 1.35},
    "pine": {"pitch": 0.92, "decay": 1.2},
}


def chop_thunk(rng, voice=NEUTRAL):
    """The axe going into the trunk: a dull wooden 'thock'. The body's low resonances ring down
    fast, under a short crunch of fibres where the edge goes in."""
    n = secs(0.42)
    k = rng.uniform(0.9, 1.12)  # every trunk a little different
    out = np.zeros(n)
    for freq, decay, amp in ((92, 0.11, 1.0), (151, 0.08, 0.7), (238, 0.06, 0.5), (367, 0.04, 0.35),
                             (540, 0.03, 0.22), (790, 0.02, 0.12)):
        out += mode(n, freq * k * voice["pitch"] * rng.uniform(0.96, 1.04),
                    decay * voice["decay"] * rng.uniform(0.85, 1.15), amp, rng.uniform(0, 6.28), glide=0.06)
    out += shaped(rng, n, 200, 1800, tilt=-3) * env(n, 0.0008, 0.018) * 0.9  # the knock itself
    out += clicks(rng, n, np.sort(rng.uniform(0.002, 0.03, 6)), rng.uniform(0.08, 0.2, 6), 900, 4000)
    return out


def chop_bloom(rng, voice=NEUTRAL):
    """The trunk booming under the blow and the forest answering: one deep, hollow note (its
    partials harmonic, so they fuse into a 'thoom' instead of beating into a growl), then a long
    dark tail."""
    n = secs(0.7)
    f = rng.uniform(56, 64) * voice["pitch"]
    body = np.zeros(n)
    partials = ((1.0, 0.2, 1.0), (2.0, 0.12, 0.55), (3.0, 0.07, 0.3), (5.0, 0.035, 0.12))
    for ratio, decay, amp in partials:
        body += mode(n, f * ratio, decay * voice["decay"], amp, rng.uniform(0, 6.28), glide=0.03, attack=0.003)
    body += shaped(rng, n, 40, 450, tilt=-3) * env(n, 0.001, 0.03) * 0.5
    notes = [(f * ratio * 0.97, amp) for ratio, _, amp in partials[:3]]  # where the glide leaves them
    return bloom(rng, body, 1.8, 0.4, notes, low_t=1.4 * voice["decay"], wet=0.55)


def chop_bite(rng):
    """The edge biting: a short, bright 'tchk', the sharp end of the blow."""
    n = secs(0.2)
    out = shaped(rng, n, 1400, 7000, tilt=-2) * env(n, 0.0003, 0.007)
    out += mode(n, rng.uniform(1050, 1350), 0.018, 0.5, rng.uniform(0, 6.28))
    out += mode(n, rng.uniform(1900, 2400), 0.01, 0.3, rng.uniform(0, 6.28))
    out += clicks(rng, n, np.sort(rng.uniform(0.004, 0.04, 4)), rng.uniform(0.1, 0.25, 4), 1500, 6000)
    return out


def clean_crack(rng):
    """A clean cut: a hard snap through the fibres, then a quick run of smaller ones and the
    trunk ringing for a moment."""
    n = secs(0.34)
    out = shaped(rng, n, 600, 9000, tilt=-1.5) * env(n, 0.0002, 0.006) * 1.2
    times = 0.004 + np.cumsum(rng.exponential(0.01, 14))
    out += clicks(rng, n, times[times < 0.2], np.linspace(0.6, 0.12, 14), 900, 6000, ring=(1400, 0.012))
    for freq, decay, amp in ((420, 0.06, 0.45), (690, 0.04, 0.3), (1020, 0.025, 0.2)):
        out += mode(n, freq * rng.uniform(0.95, 1.05), decay, amp, rng.uniform(0, 6.28))
    return out


def chip_scatter(rng):
    """A small handful of chips pattering down onto the forest floor, like dropped gravel: a
    quick cluster of tiny dull taps that thins out, no tick ringing long enough to have a pitch.
    (Chips that ring and bounce, each on its own note, sound like plastic bricks.)"""
    n = secs(0.5)
    out = np.zeros(n)
    count = rng.integers(26, 40)
    times = np.sort(rng.gamma(1.6, 0.045, count)) + 0.003  # most land at once, a few straggle in
    times = times[times < 0.42]
    gains = rng.lognormal(0.0, 0.5, len(times)) * np.exp(-times / 0.18)
    for at, g in zip(times, gains):
        m = secs(0.012)
        hi = rng.uniform(2500, 4500)  # each a little duller or brighter: dirt, leaves, a twig
        tap = shaped(rng, m, 350, hi, tilt=-3) * env(m, 0.0004, rng.uniform(0.0008, 0.002))
        tap += mode(m, rng.uniform(500, 1200), 0.002, 0.25, rng.uniform(0, 6.28), attack=0.0003)
        place(out, tap, at, g)
    out += shaped(rng, n, 300, 2500, tilt=-2) * env(n, 0.01, 0.08) * 0.04  # the scatter's hush
    return out


def trunk_creak(rng, length, voice=NEUTRAL):
    """The trunk straining: wood grinding on wood in slow grabs, a low groaning creak."""
    n = secs(length)
    p, d = voice["pitch"], voice["decay"]
    body = ((rng.uniform(180, 240) * p, 0.03 * d, 1.0), (rng.uniform(420, 520) * p, 0.02 * d, 0.6),
            (rng.uniform(780, 950) * p, 0.012 * d, 0.35))
    out = stick_slip(rng, n, rng.uniform(16, 22), rng.uniform(34, 48), body)
    out += shaped(rng, n, 150, 700) * 0.03  # the grind under it
    return out * env(n, length * 0.25, length * 0.3, hold=length * 0.3)


def fibre_tear(rng):
    """The last fibres of the hinge tearing as it goes: a fast rising crackle over a groan."""
    n = secs(1.1)
    t, times = 0.0, []
    while t < 0.95:  # the crackle thickens, then thins out as it lets go
        density = 25 + 220 * np.exp(-((t - 0.35) / 0.22) ** 2)
        t += rng.exponential(1.0 / density)
        times.append(t)
    times = np.array(times)
    gains = rng.uniform(0.2, 0.7, len(times)) * np.exp(-((times - 0.35) / 0.45) ** 2)
    out = clicks(rng, n, times, gains, 700, 5500, ring=(900, 0.01))
    body = ((rng.uniform(110, 140), 0.05, 1.0), (rng.uniform(260, 320), 0.03, 0.5))
    out += stick_slip(rng, n, 12, 28, body) * 0.35 * env(n, 0.1, 0.35, hold=0.15)
    return out


def crown_rush(rng):
    """The crown sweeping down through the air: leaves and twigs rushing, swelling as it falls
    faster, the air sound sinking as it goes."""
    n = secs(2.2)
    t = t_axis(n)
    swell = np.clip(t / 1.5, 0, 1) ** 2.2 * np.clip((2.15 - t) / 0.15, 0, 1)
    air = shaped(rng, n, 300, 2500, tilt=-1)
    leaves = shaped(rng, n, 1800, 9000)
    flutter = np.repeat(rng.uniform(0.3, 1.0, n // secs(0.02) + 1), secs(0.02))[:n]  # leaves rustling
    flutter = np.convolve(flutter, np.ones(secs(0.008)) / secs(0.008), mode="same")
    out = (air * 0.8 + leaves * flutter * 0.6) * swell
    out += clicks(rng, n, np.sort(rng.uniform(0.6, 2.0, 18)), rng.uniform(0.05, 0.18, 18), 2000, 7000)  # twigs
    return out


def land_slump(rng, voice=NEUTRAL):
    """The trunk landing: a heavy wooden thud, the crown crashing into the ground round it, and
    a bounce or two."""
    n = secs(1.0)
    out = np.zeros(n)
    for at, gain in ((0.0, 1.0), (rng.uniform(0.16, 0.2), 0.45), (rng.uniform(0.3, 0.36), 0.2)):
        m = secs(0.5)
        hit = sum(mode(m, f * voice["pitch"] * rng.uniform(0.95, 1.05), d * voice["decay"], a,
                       rng.uniform(0, 6.28), glide=0.1, attack=0.002)
                  for f, d, a in ((84, 0.2, 1.0), (131, 0.14, 0.8), (205, 0.09, 0.6), (318, 0.05, 0.4)))
        hit += shaped(rng, m, 80, 900, tilt=-3) * env(m, 0.001, 0.035) * 0.8
        place(out, hit, at, gain)
    crash = shaped(rng, n, 700, 6000, tilt=-2) * env(n, 0.015, 0.16)  # leaves and twigs smashing
    out += crash * 0.12
    out += clicks(rng, n, np.sort(rng.uniform(0.0, 0.45, 12)), rng.uniform(0.03, 0.1, 12), 1500, 5000)
    return out


def land_boom(rng):
    """The ground taking the weight: a deep thump under everything, rolling off through the
    woods for seconds."""
    n = secs(1.2)
    out = mode(n, 52, 0.32, 1.0, glide=0.25) + mode(n, 78, 0.2, 0.5, glide=0.2)
    out += shaped(rng, n, 30, 220) * env(n, 0.002, 0.12) * 0.5
    return bloom(rng, out, 3.2, 0.5, ((52 * 0.75, 1.0), (78 * 0.8, 0.5)), low_t=2.8, dry=0.8)


SOUNDS = [  # (layer, how many, build)
    ("chop_thunk", 4, chop_thunk),
    ("chop_bite", 4, chop_bite),
    ("clean_crack", 3, clean_crack),
    ("chip_scatter", 3, chip_scatter),
    ("trunk_creak", 3, lambda rng: trunk_creak(rng, rng.uniform(0.6, 1.0))),
    ("fibre_tear", 2, fibre_tear),
    ("crown_rush", 2, crown_rush),
    ("land_slump", 2, land_slump),
    ("land_boom", 1, land_boom),
    ("chop_bloom", 4, chop_bloom),
]
VOICED = [  # (layer, how many, build(rng, voice)): baked again per species into sfx/<species>/
    ("chop_thunk", 4, chop_thunk),
    ("trunk_creak", 3, lambda rng, voice:trunk_creak(rng, rng.uniform(0.6, 1.0), voice)),
    ("land_slump", 2, land_slump),
    ("chop_bloom", 3, chop_bloom),
]
# The stacks (audio/woodcutting/<stack>.tres) that play voiced layers: each species gets its own
# copy, audio/woodcutting/<species>/<stack>.tres, with its voiced layers swapped in.
VOICED_STACKS = ("axe_hit", "trunk_creak", "tree_land")


# --- finishing --------------------------------------------------------------------------------

def loudness(clip, window=0.05):
    n = min(secs(window), len(clip))
    return np.sqrt(np.convolve(clip * clip, np.ones(n) / n, mode="valid")).max()


def finish(clip):
    """Fades, then the same loudness as every other clip, peaks bent softly under 0 dB."""
    clip = clip - clip.mean()
    fade_in, fade_out = min(secs(0.001), len(clip) // 4), min(secs(0.03), len(clip) // 3)
    clip[:fade_in] *= np.linspace(0, 1, fade_in)
    clip[len(clip) - fade_out:] *= np.linspace(1, 0, fade_out)
    clip *= 10 ** (LOUDNESS / 20) / max(loudness(clip), 1e-9)
    knee, ceiling = 10 ** (-6 / 20), 10 ** (-1 / 20)
    over = np.abs(clip) > knee
    clip[over] = np.sign(clip[over]) * (knee + (ceiling - knee) * np.tanh((np.abs(clip[over]) - knee) / (ceiling - knee)))
    return clip


def write_wav(path, clip):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(clip, -1, 1) * 32767).astype("<i2").tobytes())


def write_randomizer(layer, count, folder=""):
    sfx = "res://audio/woodcutting/sfx/" + (folder + "/" if folder else "")
    lines = ['[gd_resource type="AudioStreamRandomizer" format=3]', ""]
    lines += [f'[ext_resource type="AudioStream" path="{sfx}{layer}_{i + 1:02d}.wav" id="{i + 1}"]'
              for i in range(count)]
    lines += ["", "[resource]", "playback_mode = 0", "random_pitch = 1.0", "random_volume_offset_db = 1.0",
              f"streams_count = {count}"]
    for i in range(count):
        lines += [f'stream_{i}/stream = ExtResource("{i + 1}")', f"stream_{i}/weight = 1.0"]
    with open(os.path.join(OUT, folder, layer + ".tres"), "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    layers = {name for name, _, _ in SOUNDS}
    for old in os.listdir(OUT):  # this script's layers only, so fewer variants leave none behind
        if old.endswith(".wav") and old.rsplit("_", 1)[0] in layers:
            os.remove(os.path.join(OUT, old))
    rng = np.random.default_rng(7)
    for name, count, build in SOUNDS:
        for i in range(count):
            clip = finish(build(rng).astype(np.float64))
            path = os.path.join(OUT, f"{name}_{i + 1:02d}.wav")
            write_wav(path, clip)
            print(f"{name}_{i + 1:02d}.wav  {len(clip) / RATE:4.2f}s")
        write_randomizer(name, count)
    for k, (species, voice) in enumerate(VOICES.items()):
        voiced(species, voice, np.random.default_rng(100 + k))


def voiced(species, voice, rng):
    """One species' voiced layers (sfx/<species>/) and its own copies of the stacks that play them."""
    folder = os.path.join(OUT, species)
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):
        if old.endswith(".wav"):
            os.remove(os.path.join(folder, old))
    for name, count, build in VOICED:
        for i in range(count):
            write_wav(os.path.join(folder, f"{name}_{i + 1:02d}.wav"), finish(build(rng, voice).astype(np.float64)))
        write_randomizer(name, count, species)
        print(f"{species}/{name} x{count}")
    stacks = os.path.join(OUT, "..", species)
    os.makedirs(stacks, exist_ok=True)
    for stack in VOICED_STACKS:
        with open(os.path.join(OUT, "..", stack + ".tres"), encoding="utf-8") as f:
            text = f.read()
        for name, _, _ in VOICED:
            text = text.replace(f"res://audio/woodcutting/sfx/{name}.tres", f"res://audio/woodcutting/sfx/{species}/{name}.tres")
        with open(os.path.join(stacks, stack + ".tres"), "w", newline="\n") as f:
            f.write(text)


if __name__ == "__main__":
    main()
