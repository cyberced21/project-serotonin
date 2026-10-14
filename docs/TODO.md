# TODO — parked for later

Everything we decided to come back to, in one place. Tick items off (`- [x]`) as they're done.
Design background for most of these is in [3d-research-notes.md](3d-research-notes.md).

## Fishing

- [ ] **Pike as a predator** — a pike that hunts: it stalks a perch school and its lunge scatters them (decided in fishing design, F6).
- [ ] **Swimming** — surface swimming in deep water (float, paddle, can't strike well while swimming); maybe diving with a breath meter after that (F2).
- [ ] **Faster regrouping** — scattered schools drift back together slowly (~1 m spread after 8 s); tune cohesion in `scripts/fish_school.gd`.
- [ ] **Skittishness tuning** — play-test `scare_radius`, `nerve`, `calm_down` per species in `data/fish/*.tres`.
- [ ] **Save fish?** — ponds currently start full on every load (deliberate); revisit if it feels exploitable.
- [ ] **More water** — a stream feeding the pond, more ponds / a lake with deeper-water species.

## Gathering

- [ ] **Weak points / interactive gathering** — aim at or hover over specific spots on a node for bonus damage / XP / effects. `HitInfo` already carries the hit point, normal and collider; weak points can be chunk colliders or small `Area3D`s.
- [ ] **True tool sinking** — during the bite, swap the viewmodel tool for a world-space copy stuck in the node so it really sinks into the geometry (currently faked with motion + notch decal).
- [ ] **Clean respawn ghost** — option for a single silhouette outline instead of one outline per piece.
- [x] **Iron and oak:** `iron_rock.tscn` (Mining 15) and `oak_tree.tscn` (Woodcutting 15), used in the village's tier-3 costs.
- [ ] **More node types** — gold / coal veins, more tree species (`rock()` / `tree()` in the Blender script take parameters; inherit `rock.tscn` / `tree.tscn`).

## Village

Design notes are in [village-design.md](village-design.md).

- [x] **Upgrade effects:** tiers give perks (`TierEffect`, summed by `Village.stat`). Smithy: chance of a double hit. Lodge: extra logs. Fisher: calmer fish, then bonus fish. Town hall: an XP bonus.
- [ ] **Villager rig and schedules:** real skeletal animation, a day plan, and wandering the whole valley instead of only 2–3 spots.
- [ ] **More villagers / a growing village:** new houses and villagers unlocked by the town hall.
- [ ] **Sitting:** villagers stand at the benches; give them a sit pose.
- [x] **Talk ray occlusion:** a villager behind a pole still counts if their head, chest or hips is in plain sight (`player.gd` `_villager_behind_clutter`).
- [ ] **Interiors:** buildings are solid shells. Could have doors you walk through.

## Movement

- [ ] **Grapple / rope** — for chasms and cliff-face nodes.
- [ ] **Agility skill or craftable grapple** — optional movement gating for rare nodes.
- [ ] **Slide / mantle tuning** — play-test speeds and heights (Player inspector: *Crouch / slide*, *Mantle*).

## Art & models

- [ ] **Real-model pickups** — drops as tiny models instead of icon billboards.
- [ ] **Block hands** on the viewmodel tools (part of the tool mesh, no rig).
- [ ] **Replace greybox leftovers** — the parkour blocks and the box-shaped chip / burst particles. (The hidden greybox meshes in `rock.tscn` / `tree.tscn` are gone.)
- [x] **Scenery:** grass, flowers, bushes and boulders are scattered by `SceneryScatter` (layers in `main.tscn`, models in `make_models.py` `scenery()`).
- [ ] **Blender guide** — a step-by-step for remodelling the rock by hand, to learn modelling.
- [ ] **Sculpt / paint the terrain** in the Terrain3D editor (note: re-running `tools/generate_test_terrain.gd` overwrites it).

## Audio

- [ ] **Real recordings** to replace the synthesized placeholders: footsteps (all surfaces + water), slide scrape, mantle, splash, spear hit (`audio/footsteps/`, `audio/movement/`, `audio/fishing/` — swap the `.wav`s, the `.tres` randomizers stay).

## World & tech

- [ ] **Day / night cycle** (optional).
- [ ] **Terrain collision range** — Terrain3D only builds collision within 64 m of the camera; anything left further away (debris, drops) can fall through. Fine for now; revisit with bigger worlds.
- [x] **Saved node keys:** every placed node has a `save_id`. Saves keyed by the old scene path carry over automatically.
