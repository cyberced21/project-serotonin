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
- [ ] **More node types** — iron / gold / coal veins, other tree species (same Blender script + `ResourceNode.model`).

## Village

Design notes are in [village-design.md](village-design.md).

- [ ] **Upgrade effects:** give tiers a mechanical payoff, such as better tools from the smithy or selling fish to the fisher. Fill `BuildingTier.effects` (`data/buildings/*.tres`), or listen to `Village.tier_changed`.
- [ ] **Villager rig and schedules:** real skeletal animation, a day plan, and wandering the whole valley instead of only 2–3 spots.
- [ ] **More villagers / a growing village:** new houses and villagers unlocked by the town hall.
- [ ] **Sitting:** villagers stand at the benches; give them a sit pose.
- [ ] **Talk ray occlusion:** thin pieces (the tier-1 smithy's tarp poles) can block the crosshair from reaching a villager behind them. Consider no collision on thin props, or a wider talk shape.
- [ ] **Interiors:** buildings are solid shells. Could have doors you walk through.

## Movement

- [ ] **Grapple / rope** — for chasms and cliff-face nodes.
- [ ] **Agility skill or craftable grapple** — optional movement gating for rare nodes.
- [ ] **Slide / mantle tuning** — play-test speeds and heights (Player inspector: *Crouch / slide*, *Mantle*).

## Art & models

- [ ] **Real-model pickups** — drops as tiny models instead of icon billboards.
- [ ] **Block hands** on the viewmodel tools (part of the tool mesh, no rig).
- [ ] **Replace greybox leftovers** — the parkour blocks, the old greybox meshes still inside `scenes/rock.tscn` / `scenes/tree.tscn` (hidden by the models), and the box-shaped chip / burst particles.
- [ ] **Scenery** — bushes, grass tufts, boulders scattered over the terrain.
- [ ] **Blender guide** — a step-by-step for remodelling the rock by hand, to learn modelling.
- [ ] **Sculpt / paint the terrain** in the Terrain3D editor (note: re-running `tools/generate_test_terrain.gd` overwrites it).

## Audio

- [ ] **Real recordings** to replace the synthesized placeholders: footsteps (all surfaces + water), slide scrape, mantle, splash, spear hit (`audio/footsteps/`, `audio/movement/`, `audio/fishing/` — swap the `.wav`s, the `.tres` randomizers stay).

## World & tech

- [ ] **Day / night cycle** (optional).
- [ ] **Terrain collision range** — Terrain3D only builds collision within 64 m of the camera; anything left further away (debris, drops) can fall through. Fine for now; revisit with bigger worlds.
- [ ] **Saved node keys** — depleted-node state is saved by scene path, so renaming / moving a node in the editor resets it.
