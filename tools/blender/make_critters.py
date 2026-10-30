"""Small wild things the picks had no model for (plans/world-pass.md, phase 8): a rabbit and a red
squirrel, low-poly in the palette, made to hop in code (Animal), facing +Y here (-Z... see below).

    blender -b -P tools/blender/make_critters.py -- models art/palette.json

Writes models/animals/rabbit_ours.glb and squirrel_ours.glb. Each faces -Y in Blender, which is +Z
in Godot (as the picked animals do), standing on its origin.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_models import blob, export, prism, reset  # noqa: E402
import make_village as mv  # noqa: E402

FUR = ("neutral.4", "neutral.3", "neutral.5")
RED = ("accent.2", "accent.1", "accent.2")


def rabbit():
    reset()
    k = mv.Kit("", 701)
    k.add("Body", blob(0.13, k.rng, squash=(0.85, 1.25, 0.9)), FUR, (0, 0.03, 0.13))
    k.add("Haunch", blob(0.1, k.rng, squash=(1.0, 1.0, 0.9)), FUR, (0, 0.1, 0.1))
    k.add("Head", blob(0.075, k.rng, squash=(0.9, 1.1, 0.95)), FUR, (0, -0.13, 0.22))
    for s in (-1, 1):
        k.box("Ear", (0.03, 0.02, 0.13), (s * 0.03, -0.11, 0.33), FUR, rot=(0.25, s * 0.2, 0))
        k.box("Eye", (0.012, 0.012, 0.012), (s * 0.045, -0.18, 0.24), "neutral.0")
        k.box("Foot", (0.035, 0.09, 0.03), (s * 0.06, 0.06, 0.015), FUR)
    k.add("Tail", blob(0.035, k.rng), ("neutral.7", "neutral.7", "neutral.6"), (0, 0.19, 0.14))
    export(os.path.join("animals", "rabbit_ours"))


def squirrel():
    reset()
    k = mv.Kit("", 702)
    k.add("Body", blob(0.08, k.rng, squash=(0.8, 1.3, 0.9)), RED, (0, 0.0, 0.1))
    k.add("Head", blob(0.05, k.rng), RED, (0, -0.1, 0.17))
    for s in (-1, 1):
        k.box("Ear", (0.015, 0.012, 0.04), (s * 0.025, -0.1, 0.23), RED)
        k.box("Eye", (0.01, 0.01, 0.01), (s * 0.03, -0.14, 0.18), "neutral.0")
    for i in range(4):  # the bushy tail, curling up over its back
        a = i * 0.45
        k.add("Tail", blob(0.06 - i * 0.006, k.rng), RED, (0, 0.11 + math.sin(a) * 0.06, 0.1 + i * 0.07))
    k.add("Belly", blob(0.05, k.rng, squash=(0.7, 1.0, 0.8)), ("neutral.7", "neutral.6", "neutral.6"), (0, -0.04, 0.09))
    export(os.path.join("animals", "squirrel_ours"))


if __name__ == "__main__":
    rabbit()
    squirrel()
