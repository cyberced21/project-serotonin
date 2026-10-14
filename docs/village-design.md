# Village — design decisions

Agreed and built 2026-10-13. A second area of the map: a village whose buildings you upgrade with gathered
resources, changing their look. Upgrades are visual for now; mechanics hook in later.

## Buildings

- **One house per skill**, each with a dedicated villager tied to that skill, plus a **town hall** with the **mayor**.
- **3 tiers each**; every building starts at tier 1 (lived-in but run-down).

| Building | Villager | Tier looks (1 → 2 → 3) |
|---|---|---|
| Town hall | mayor | (to design) |
| Woodcutter's lodge | woodcutter | lean-to → log cabin → cabin + porch, chimney, woodpile |
| Smithy | smith | fire pit + anvil → stone forge with roof → full smithy, chimney smoke, bellows |
| Fisher's hut | fisher | drying rack + tent → stilt shack by the water → shack + dock + nets |

- **Town hall caps the houses:** a house can't exceed the town hall's tier. The town hall costs a mix of everything.

## Costs (placeholders, tune in the `.tres`)

| | T1 → T2 | T2 → T3 |
|---|---|---|
| Town hall | 20 logs, 10 ore, 5 perch | 50 logs, 30 ore, 10 trout |
| Woodcutter | 25 logs | 60 logs, 10 ore |
| Smithy | 20 ore, 10 logs | 50 ore, 20 logs |
| Fisher | 10 perch, 10 logs | 8 trout, 3 pike, 25 logs |

Pike gate the fisher's tier 3, and pike live only in the original pond.

## Data and code

- `BuildingDef` Resource in `data/buildings/*.tres` (like `FishSpecies`):
  - id, display name, villager name, model
  - tiers: name, cost dict, flavour lines, and an empty `effects` array for later
  - (villager work spots ended up as `Spots/Work1..3` markers in each building scene, not in the data, so they can be moved in the editor)
- `Village` autoload:
  - stores `{building_id: tier}`, registered with `SaveGame` as `"village"`, keyed by **stable id**, not scene path
  - enforces the town-hall cap
  - emits `tier_changed(id, tier)`, the hook for future mechanics
- Buildings are views: they read their tier on load and animate when it changes.
- `Inventory.spend(cost) -> bool`: atomic check-then-remove.

## Upgrade moment

Instant, staged, about 2 s, with no build timer and no cutscene:

1. Old-tier pieces squash and drop into dust, with a light shake.
2. New-tier pieces pop in bottom-up with springy overshoot and a rising-pitch hammer "tok" per piece.
3. Settle bounce, particle burst, a popup with the tier name, and the villager does a cheer hop.

Each building is one `.glb` with objects named `T1_*`, `T2_*`, `T3_*`.

## Villagers

- **Models:** low-poly "toy" villagers from the Blender script and palette. Separate parts (body, head, arms, hat/prop), no rig.
- **Procedural animation:** idle bob, head tracking the player, a work loop.
- **Behaviour:**
  - 2–3 hand-placed spots each (door, work station, bench), walked in straight lines; no navmesh, no schedule
  - the work spot can change per tier (for example, the fisher moves from shore to dock)
  - they stop and face you when you come near

## Interaction

- **Contextual E:**
  - on a villager within about 3 m, E talks instead of swinging
  - left mouse never swings at villagers
  - a ghost outline and a "E — Talk to <name> (<role>)" prompt show what you can talk to
- **A single panel** (frees the mouse; Esc or walking away closes it):
  - name and a tier-based flavour line, plus a hint when the town hall caps them
  - next tier's name and costs as icon *have/need* in red or green
  - an Upgrade button, disabled until you can afford it and the cap allows it

## Map

- A separate valley about 100 m from the clearing, about 35–40 m radius, carved in `tools/generate_test_terrain.gd` (safe: the terrain has never been hand-sculpted).
- A dirt path from the clearing.
- The town hall sits on a central square. Houses face what they relate to: water, treeline, rocky hills.
- **A village pond:** smaller and shallower, **perch and trout only**.
- A few trees and rocks near the village.

## Build order

1. Terrain: valley, path, pond basin; regenerate; set up the pond in `main.tscn`.
2. Village core: autoload, `BuildingDef`, save, cap, `Inventory.spend()`, a debug tier key, greybox tiers.
3. Building models (4 × 3 tiers) + staged pop-in + sounds.
4. Villagers: models, idle, head tracking, work loops, walking, per-tier spots.
5. Interaction: contextual E, outline and prompt, upgrade panel.
6. Dressing: pond fish and reeds, nearby nodes, props, README and TODO.

## As built

- **Saving:** tiers are saved under the `village` key in `user://save.json`.
- **Debug keys:** F7 gives 50 of every item. F8 upgrades every building one tier for free, then wraps back to tier 1.
- **Upgrade watching:** during an upgrade, the villager hurries to its door spot and watches, then cheers when the building finishes.
- **Collision:** villagers are on physics layer 7. The player bumps into them and the crosshair stops on them, but you can't mantle onto them.
- **The path:** the path, square and lanes are painted as terrain texture id 1 in the control map. The terrain shader colours them, and footsteps on them sound like dirt.

## Parked

- Upgrade effects (mechanics)
- Villager rig and schedules
- More villagers / village growth
- New resource tiers (iron, oak) for costs
