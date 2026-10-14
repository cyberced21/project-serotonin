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

- [x] **Weak points:** a glowing diamond on one chunk. A swing aimed at it counts an extra hit, gives double XP and a "Weak spot!" burst, then the spot moves (`ResourceNode` *Weak point* group).
- [x] **True tool sinking:** during the bite, a world copy of the tool sticks with its edge buried in the node. The held fist stays on screen holding the handle (`player.gd` `_stick_in_world`).
- [x] **Clean respawn ghost:** one silhouette outline via the stencil buffer (`ResourceNode.ghost_silhouette`, on by default).
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

- [x] **Real-model pickups:** drops show the item's model (`Items.model`), tumbling on a fitted box, spinning in as they're collected.
- [x] **Block hands:** a blocky fist and sleeve cuff are part of each tool model (`block_hand()` in `make_models.py`).
- [x] **Replace greybox leftovers:** the parkour blocks are low-poly ruins (`ruins()` in `make_models.py`) with exactly the old collision boxes. Chips are wedge shards and bursts are spinning diamond flecks.
- [x] **Scenery:** grass, flowers, bushes and boulders are scattered by `SceneryScatter` (layers in `main.tscn`, models in `make_models.py` `scenery()`).
- [x] **Blender guide:** [blender-guide.md](blender-guide.md), remodelling the rock by hand.
- [ ] **Sculpt / paint the terrain** in the Terrain3D editor (note: re-running `tools/generate_test_terrain.gd` overwrites it).

## Audio

- [ ] **Real recordings** to replace the synthesized placeholders: footsteps (all surfaces + water), slide scrape, mantle, splash, spear hit (`audio/footsteps/`, `audio/movement/`, `audio/fishing/` — swap the `.wav`s, the `.tres` randomizers stay).

## World & tech

- [x] **Day / night:** a 20-minute day (`DayNight` autoload) lit by the `Sky` node. Lamps and windows glow after dark, villagers go home at night, and fish are calmer at dawn and dusk.
- [x] **Stars and moon:** `shaders/sky.gdshader` draws the gradient, a sun disc by day, a moon disc and twinkling stars at night.
- [x] **Terrain collision range:** Terrain3D now builds collision for the whole map up front (`collision_mode` Full/Game, ~0.1 s at 512 m). Revisit if the world gets much bigger.
- [x] **Saved node keys:** every placed node has a `save_id`. Saves keyed by the old scene path carry over automatically.
