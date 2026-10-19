"""Synthesizes the mining sounds (needs numpy), in place of the clips once cut from the GDC bundle:

    python tools/synth_mining_sounds.py

Writes audio/mining/sfx/<layer>_NN.wav and <layer>.tres (an AudioStreamRandomizer picking one),
the same layers the stacks in audio/mining/ (pickaxe_hit, split, crack_tip...) have always played,
so they work unchanged. Every clip is mono, 48 kHz, faded, and brought to the same loudness, so
the stacks set the mix (see tools/synth_wood_sounds.py, whose pieces this reuses).

Each ore also gets its own voice for the layers that are the rock's own body (VOICED): the ring
after the tink, the thump, a crack running and a piece splitting. They bake into sfx/<ore>/ with
the ore's own copies of the stacks that play them (audio/mining/<ore>/), which the ore scenes use.
Copper (the plain rock) keeps the base voice.

Built from physical pieces:
- a stone body is a few low resonances that die almost at once (stone is stiff and lossy);
- the pick is steel: a few inharmonic resonances that ring on a moment (the tink);
- cracks are trains of tiny snaps, gravel and pebbles are scattered clicks with small knocks;
- air past the pick is noise whose band sweeps up and down with the swing.
"""
import os

import numpy as np

from synth_wood_sounds import RATE, bloom, clicks, env, finish, mode, place, secs, shaped, t_axis, write_wav

OUT = os.path.join(os.path.dirname(__file__), "..", "audio", "mining", "sfx")

# How each ore's stone answers next to copper's: `pitch` shifts its resonances, `decay` stretches
# how long they last, `ring` is how much it rings rather than knocks, `crumble` how much grit
# breaks off with every blow. Iron's basalt is hard and rings; coal is soft, dull and crumbly;
# gold's quartz rim rings bright; crystal chimes.
NEUTRAL = {"pitch": 1.0, "decay": 1.0, "ring": 1.0, "crumble": 1.0}
VOICES = {
    "iron": {"pitch": 1.15, "decay": 1.5, "ring": 1.6, "crumble": 0.6},
    "coal": {"pitch": 0.8, "decay": 0.6, "ring": 0.4, "crumble": 1.8},
    "gold": {"pitch": 1.1, "decay": 1.2, "ring": 1.3, "crumble": 0.8},
    "crystal": {"pitch": 1.6, "decay": 2.2, "ring": 2.2, "crumble": 0.4},
}
# The ore scenes that wear each voice.
ORE_SCENES = {"iron": "iron_rock", "coal": "coal_rock", "gold": "gold_rock", "crystal": "crystal_rock"}


def swept(rng, n, centres, width=0.6):
    """Noise whose band follows `centres` (Hz, spread evenly over the clip): each 20 ms window is
    filtered round its own centre and the windows are overlapped, so the band glides."""
    win = secs(0.02)
    hop = win // 2
    out = np.zeros(n + win)
    window = np.hanning(win)
    f = np.fft.rfftfreq(win, 1.0 / RATE)
    for k, start in enumerate(range(0, n, hop)):
        c = np.interp(start / max(n - 1, 1), np.linspace(0, 1, len(centres)), centres)
        gain = np.exp(-0.5 * (np.log2(np.maximum(f, 1.0) / c) / width) ** 2)
        seg = np.fft.irfft(np.fft.rfft(rng.standard_normal(win)) * gain, win)
        out[start:start + win] += seg * window
    out = out[:n]
    return out / (np.abs(out).max() + 1e-9)


def apart(freq, others, gap=180.0):
    """`freq` moved clear of `others` by at least `gap` Hz: two tones closer than that beat
    against each other tens of times a second, which is heard as a rough, grating buzz."""
    for o in sorted(others, key=lambda o: abs(o - freq)):
        if abs(freq - o) < gap:
            freq = o + gap if freq >= o else o - gap
    return freq


def body_decay(voice):
    """How much longer a voice lets the low body ring: a little at most. Low modes a few dozen Hz
    apart beat against each other, and drawn out past a thud that beating turns into a growl; a
    ringing ore rings in its high partials instead (stone_knock, the tink)."""
    return min(voice["decay"], 1.2)


def stone_knock(rng, n, base, voice, amp=1.0):
    """A stone body struck: a few stiff resonances above `base` Hz that die almost at once."""
    p, d, r = voice["pitch"], voice["decay"], voice["ring"]
    out = np.zeros(n)
    for ratio, decay, a in ((1.0, 0.012, 1.0), (1.73, 0.009, 0.7), (2.6, 0.007, 0.5), (3.9, 0.005, 0.35)):
        out += mode(n, base * ratio * p * rng.uniform(0.95, 1.05), decay * d * (0.6 + 0.4 * r), a,
                    rng.uniform(0, 6.28))
    return out * amp


# --- the layers -------------------------------------------------------------------------------

def hit_crack(rng):
    """The point biting into stone: a hard, bright crack, gone in a few milliseconds."""
    n = secs(0.25)
    out = shaped(rng, n, 1500, 9000, tilt=-1) * env(n, 0.0002, 0.006)
    out += stone_knock(rng, n, rng.uniform(900, 1300), NEUTRAL, 0.6)
    out += clicks(rng, n, np.sort(rng.uniform(0.002, 0.04, 8)), rng.uniform(0.05, 0.2, 8), 2500, 9000)
    return out


def hit_tink(rng, voice=NEUTRAL):
    """The steel pick ringing off the rock, and the rock's own ring under it: inharmonic, bright,
    a moment long. A ringing ore (iron, crystal) answers louder and longer."""
    n = secs(0.5)
    f = rng.uniform(1900, 2400)
    out = np.zeros(n)
    pick = []
    for ratio, decay, a in ((1.0, 0.06, 1.0), (2.76, 0.035, 0.5), (5.4, 0.02, 0.25)):  # the pick
        pick.append(f * ratio * rng.uniform(0.98, 1.02))
        out += mode(n, pick[-1], decay, a, rng.uniform(0, 6.28))
    stone = rng.uniform(1300, 1700) * voice["pitch"]
    for ratio, decay, a in ((1.0, 0.05, 0.8), (2.32, 0.03, 0.45), (4.1, 0.018, 0.25)):  # the rock
        out += mode(n, apart(stone * ratio * rng.uniform(0.97, 1.03), pick), decay * voice["decay"],
                    a * voice["ring"], rng.uniform(0, 6.28))
    out += shaped(rng, n, 3000, 10000) * env(n, 0.0001, 0.002) * 0.5
    return out


def hit_thump(rng, voice=NEUTRAL):
    """The blow going into the boulder: a short, heavy, low knock."""
    n = secs(0.3)
    out = np.zeros(n)
    for f, d, a in ((70, 0.05, 1.0), (118, 0.035, 0.7), (190, 0.022, 0.45), (300, 0.012, 0.3)):
        out += mode(n, f * voice["pitch"] * rng.uniform(0.92, 1.08), d * body_decay(voice), a, rng.uniform(0, 6.28),
                    glide=0.08)
    out += shaped(rng, n, 60, 700, tilt=-3) * env(n, 0.0008, 0.02) * 0.7
    out += shaped(rng, n, 800, 5000, tilt=-2) * env(n, 0.001, 0.03) * 0.15 * voice["crumble"]  # grit
    return out


def hit_gravel(rng):
    """Grit and chips pattering down after a blow: a trickle of small clicks, thinning out."""
    n = secs(0.6)
    count = rng.integers(14, 24)
    times = np.sort(rng.exponential(0.12, count)) + 0.005
    times = times[times < 0.55]
    out = clicks(rng, n, times, rng.uniform(0.15, 0.6, len(times)) * np.exp(-times * 3), 1800, 8000, 0.004)
    for at in times[: len(times) // 3]:  # a few bigger chips knock as they land
        place(out, stone_knock(rng, secs(0.04), rng.uniform(1400, 2400), NEUTRAL, 0.12), at)
    return out


def pull_scrape(rng):
    """The point dragged out of the rock: steel grinding on stone, catching as it goes."""
    n = secs(rng.uniform(0.18, 0.26))
    # the point catches at uneven moments: grabs at a steady rate would fuse into a buzz
    grabs = np.full(n, 0.55)
    at = 0.0
    while at < n / RATE:
        place(grabs, env(secs(0.03), 0.004, 0.008) * rng.uniform(0.3, 0.6), at)
        at += rng.uniform(0.012, 0.05)
    out = shaped(rng, n, 1200, 6000, tilt=-1) * grabs * env(n, 0.01, n / RATE / 3)
    out += clicks(rng, n, np.sort(rng.uniform(0, n / RATE * 0.8, 6)), rng.uniform(0.1, 0.3, 6), 2000, 7000)
    return out


def pull_pebbles(rng):
    """A few pebbles knocked loose as the point comes free, rolling off."""
    n = secs(0.5)
    out = np.zeros(n)
    for at in np.sort(rng.uniform(0.0, 0.35, rng.integers(3, 6))):
        pebble = stone_knock(rng, secs(0.05), rng.uniform(1500, 2800), NEUTRAL, 0.5)
        place(out, pebble + shaped(rng, len(pebble), 2000, 8000) * env(len(pebble), 0.0002, 0.003) * 0.4, at,
              rng.uniform(0.4, 1.0))
    return out


def swing_whoosh(rng):
    """The pick coming down: air rushing past it, its band rising to the fastest moment and falling."""
    n = secs(rng.uniform(0.24, 0.34))
    peak = rng.uniform(900, 1400)
    out = swept(rng, n, [300, peak * 0.6, peak, peak * 0.7, 350], width=0.7)
    t = np.linspace(0, 1, n)
    return out * np.sin(np.pi * t ** rng.uniform(0.7, 0.9)) ** 2


def windup_creak(rng):
    """Arms and sleeves as the pick is raised: a soft rustle of cloth, a little leather creak."""
    n = secs(rng.uniform(0.3, 0.42))
    t = np.linspace(0, 1, n)
    flutter = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * rng.uniform(6, 10) * t * n / RATE))
    out = shaped(rng, n, 400, 4000, tilt=-2) * flutter * np.sin(np.pi * t) ** 1.5
    for at in rng.uniform(0.05, n / RATE * 0.7, 2):  # the leather grip giving
        place(out, mode(secs(0.05), rng.uniform(350, 550), 0.012, 0.3, rng.uniform(0, 6.28)), at)
    return out


def crack_split(rng, voice=NEUTRAL):
    """A crack running through the stone: snaps coming faster as it races along, a ringing tick
    off the fresh faces."""
    length = rng.uniform(0.25, 0.45)
    n = secs(length + 0.1)
    gaps = np.geomspace(0.04, 0.006, rng.integers(10, 18))
    times = np.cumsum(gaps)
    times = times[times < length]
    ring = (rng.uniform(2200, 3200) * voice["pitch"], 0.01 * voice["decay"] * voice["ring"])
    out = clicks(rng, n, times, np.linspace(0.3, 1.0, len(times)), 1500, 9000, 0.004, ring=ring)
    out += shaped(rng, n, 2000, 8000) * env(n, length * 0.6, 0.04) * 0.08 * voice["crumble"]
    return out


def split_crunch(rng, voice=NEUTRAL):
    """A piece breaking away: a heavy, grinding crunch, the body thudding as it lets go."""
    n = secs(0.6)
    out = np.zeros(n)
    for f, d, a in ((55, 0.09, 1.0), (92, 0.06, 0.8), (150, 0.04, 0.55), (240, 0.025, 0.35)):
        out += mode(n, f * voice["pitch"] * rng.uniform(0.93, 1.07), d * body_decay(voice), a, rng.uniform(0, 6.28),
                    glide=0.12, attack=0.002)
    out += shaped(rng, n, 150, 5000, tilt=-2) * env(n, 0.002, 0.07) * 0.9 * voice["crumble"]
    out += clicks(rng, n, np.sort(rng.uniform(0.0, 0.12, 14)), rng.uniform(0.1, 0.4, 14), 1200, 7000)
    out += stone_knock(rng, n, rng.uniform(600, 900), voice, 0.4)
    return out


def split_rubble(rng):
    """The broken piece tumbling to the ground in a few knocks, and grit settling after it."""
    n = secs(1.0)
    out = np.zeros(n)
    at, gain = 0.0, 1.0
    for _ in range(rng.integers(3, 5)):
        knock = stone_knock(rng, secs(0.12), rng.uniform(260, 520), NEUTRAL)
        knock += shaped(rng, len(knock), 100, 2500, tilt=-3) * env(len(knock), 0.001, 0.02) * 0.6
        place(out, knock, at, gain)
        at += rng.uniform(0.12, 0.25)
        gain *= rng.uniform(0.45, 0.65)
    out += clicks(rng, n, np.sort(rng.uniform(0.05, 0.8, 16)), rng.uniform(0.04, 0.12, 16), 1800, 7000)
    return out


def debris_tick(rng):
    """One chip landing on stone: a tiny high tick."""
    n = secs(0.08)
    return stone_knock(rng, n, rng.uniform(2200, 3400), NEUTRAL) + \
        shaped(rng, n, 3000, 10000) * env(n, 0.0001, 0.002) * 0.6


def hit_clink(rng, voice=NEUTRAL):
    """The pick ringing out after the tink, like a hammer on an anvil: a steel bar's partials
    (1 : 2.76 : 5.40 : 8.93), the lowest one doubled a few Hz apart so the ring shimmers, the
    ore's own ring under it, then a short bright space. A ringing ore (iron, crystal) sings on;
    coal barely answers."""
    n = secs(1.3)
    f = rng.uniform(1650, 2050)
    out = np.zeros(n)
    pick = []
    for ratio, decay, a in ((1.0, 0.22, 1.0), (2.756, 0.12, 0.45), (5.404, 0.06, 0.22), (8.933, 0.03, 0.1)):
        pick.append(f * ratio * rng.uniform(0.995, 1.005))
        out += mode(n, pick[-1], decay * min(voice["ring"], 1.4), a, rng.uniform(0, 6.28))
    out += mode(n, pick[0] + rng.uniform(4, 7), 0.22, 0.35, rng.uniform(0, 6.28))  # the shimmer
    stone = rng.uniform(2300, 2800) * voice["pitch"]
    for ratio, decay, a in ((1.0, 0.09, 0.6), (2.41, 0.05, 0.3)):  # the ore's own note
        out += mode(n, apart(stone * ratio, pick), decay * voice["decay"], a * voice["ring"] ** 1.5,
                    rng.uniform(0, 6.28))
    out *= 1.0 - np.exp(-t_axis(n) / 0.0015)  # the tink layer has the strike; this is the ring
    return bloom(rng, out, 0.9, 0.5, 0.9, dry=1.0)


def hit_bloom(rng, voice=NEUTRAL):
    """The boulder booming under the blow and the rocks round about throwing it back: a deep,
    short knock (harmonic, so it doesn't growl) with a long dark tail."""
    n = secs(0.5)
    f = rng.uniform(62, 72) * voice["pitch"]
    body = np.zeros(n)
    for ratio, decay, a in ((1.0, 0.1, 1.0), (2.0, 0.06, 0.5), (3.0, 0.035, 0.25)):
        body += mode(n, f * ratio, decay * body_decay(voice), a, rng.uniform(0, 6.28), glide=0.05, attack=0.002)
    body += shaped(rng, n, 40, 600, tilt=-3) * env(n, 0.001, 0.025) * 0.6
    return bloom(rng, body, 2.0, 1.7, 0.35, dry=0.5)


SOUNDS = [  # (layer, how many, build): the layer names the stacks in audio/mining/ play
    ("hit_crack", 6, hit_crack),
    ("hit_tink", 4, hit_tink),
    ("hit_thump", 6, hit_thump),
    ("hit_gravel", 6, hit_gravel),
    ("pull_scrape", 3, pull_scrape),
    ("pull_pebbles", 3, pull_pebbles),
    ("swing_whoosh", 6, swing_whoosh),
    ("windup_creak", 3, windup_creak),
    ("crack_split", 5, crack_split),
    ("split_crunch", 3, split_crunch),
    ("split_rubble", 3, split_rubble),
    ("debris_tick", 4, debris_tick),
    ("hit_clink", 5, hit_clink),
    ("hit_bloom", 4, hit_bloom),
]
VOICED = [  # (layer, how many, build(rng, voice)): baked again per ore into sfx/<ore>/
    ("hit_tink", 4, hit_tink),
    ("hit_thump", 4, hit_thump),
    ("crack_split", 4, crack_split),
    ("split_crunch", 3, split_crunch),
    ("hit_clink", 4, hit_clink),
    ("hit_bloom", 3, hit_bloom),
]
# The stacks (audio/mining/<stack>.tres) that play voiced layers, and the scene property each is.
VOICED_STACKS = {"pickaxe_hit": "hit_layers", "crack_tip": "crack_layers", "split": "split_layers"}


def write_randomizer(layer, count, folder=""):
    sfx = "res://audio/mining/sfx/" + (folder + "/" if folder else "")
    lines = ['[gd_resource type="AudioStreamRandomizer" format=3]', ""]
    lines += [f'[ext_resource type="AudioStream" path="{sfx}{layer}_{i + 1:02d}.wav" id="{i + 1}"]'
              for i in range(count)]
    lines += ["", "[resource]", "playback_mode = 0", "random_pitch = 1.0", "random_volume_offset_db = 1.0",
              f"streams_count = {count}"]
    for i in range(count):
        lines += [f'stream_{i}/stream = ExtResource("{i + 1}")', f"stream_{i}/weight = 1.0"]
    with open(os.path.join(OUT, folder, layer + ".tres"), "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def bake(folder, layers, rng, voice=None):
    path = os.path.join(OUT, folder)
    os.makedirs(path, exist_ok=True)
    names = {name for name, _, _ in layers}
    for old in os.listdir(path):  # this layer set's clips only: fewer variants leave none behind
        if old.endswith(".wav") and old.rsplit("_", 1)[0] in names or old.endswith(".wav.import") and \
                old.rsplit("_", 1)[0] in names:
            os.remove(os.path.join(path, old))
    for name, count, build in layers:
        for i in range(count):
            clip = build(rng) if voice is None else build(rng, voice)
            write_wav(os.path.join(path, f"{name}_{i + 1:02d}.wav"), finish(clip.astype(np.float64)))
        write_randomizer(name, count, folder)
        print(f"{folder or 'sfx'}/{name} x{count}")


def voiced_stacks(ore):
    """The ore's own copies of the stacks, playing its voiced layers instead of the base ones."""
    stacks = os.path.join(OUT, "..", ore)
    os.makedirs(stacks, exist_ok=True)
    for stack in VOICED_STACKS:
        with open(os.path.join(OUT, "..", stack + ".tres"), encoding="utf-8") as f:
            text = f.read()
        for name, _, _ in VOICED:
            text = text.replace(f"res://audio/mining/sfx/{name}.tres", f"res://audio/mining/sfx/{ore}/{name}.tres")
        with open(os.path.join(stacks, stack + ".tres"), "w", newline="\n") as f:
            f.write(text)


def main():
    bake("", SOUNDS, np.random.default_rng(11))
    for k, (ore, voice) in enumerate(VOICES.items()):
        bake(ore, VOICED, np.random.default_rng(200 + k), voice)
        voiced_stacks(ore)


if __name__ == "__main__":
    main()
