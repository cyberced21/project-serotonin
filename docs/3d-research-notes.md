# 3D conversion — research & check-later notes

Things to learn, verify or decide before/while moving Project Serotonin to first-person 3D.
Tick items off as you go. Decisions already made are listed at the bottom for reference.

---

## Modelling (Blender)

- [ ] Install Blender and learn the basics: navigation, edit mode, extrude, loop cuts, modifiers.
- [ ] Watch Imphenzia's "low poly in 10 minutes" series — it uses the exact palette-atlas workflow we picked.
- [ ] Learn UV unwrapping *for a palette atlas*: scaling a face's UVs down to a point/small area and dropping it on a colour swatch.
- [ ] Practice models, in this order: one rock, one ore vein (same rock, ore faces on a different swatch), one tree, one pickaxe, one axe.
- [ ] Learn how to split a model into **chunks** (separate objects/meshes) so rocks can shed pieces per hit.
- [ ] Model a **stump** and a **rubble** mesh for the "depleted" state.
- [ ] Learn to export **`.glb`** (not `.blend` — `.blend` import needs Blender installed on every machine).
- [ ] Check Godot's import settings for `.glb`: scale, generating collision shapes, keeping child meshes separate for chunks.
- [ ] Later: simple block hands holding the tool handle (part of the viewmodel mesh, no rig needed).

## Palette atlas texture

- [ ] Design the palette image (64×64 to 256×256): gradient ramps for bark, leaves, stone, grass, and one per ore (copper, iron, …).
- [ ] Import settings: **filter off / no mipmaps** on the palette so swatches don't bleed into each other.
- [ ] Decide: ore variants via **UV-offset swatches** or a **shader uniform** colour swap on one shared material.

## Terrain (Terrain3D)

- [ ] Confirm **Terrain3D supports Godot 4.7** (check the releases page / Asset Library before installing).
- [ ] Learn install + basic workflow: sculpting, holes, painting texture layers.
- [ ] **Style clash to solve:** Terrain3D is built for smooth, textured terrain. Research how to get a flat-shaded / low-poly look
      (low-res textures, flat colour layers, a custom shader, or faceted normals). If it can't look right, fall back to a hand-made
      ground mesh from Blender.
- [ ] Check collision works with **Jolt Physics** (the project already uses Jolt).
- [ ] Learn how to place hand-made nodes (trees/rocks) on the terrain surface, and whether Terrain3D's **instancer** is useful
      for decorative (non-gatherable) trees and rocks.
- [ ] Check performance cost — region size, LODs — for a small test area first.

## Rendering & lighting

- [ ] `WorldEnvironment`: `ProceduralSkyMaterial`, distance fog, tonemapping. Keep SSAO off to start.
- [ ] `DirectionalLight3D` sun with shadows — learn shadow distance / split settings for first-person.
- [ ] Project settings to change when converting: viewport `320×180` → native, stretch mode `viewport` → `canvas_items`,
      remove integer scaling, texture filter nearest → linear (except the palette), drop 2D pixel snapping, rescale HUD fonts.
- [ ] Outline / rim highlight shader for the targeted node (next-pass material).
- [ ] Later: optional day/night cycle.

## Viewmodel (tool on screen)

- [ ] Research the **SubViewport viewmodel** technique in Godot 4: separate camera + own FOV, layered over the main view,
      so tools never clip into trees/rocks. Check how shadows/lighting from the main scene apply to it.
- [ ] Port the windup → strike → recover tween from `player.gd` onto the tool's rotation/position.
- [ ] Impact "kick": small viewmodel push toward the camera (replaces the body squash).

## Camera, input & feel

- [ ] Mouse capture (`Input.mouse_mode = CAPTURED`), Esc to release, sensitivity setting.
- [ ] Mouse-look must use `_unhandled_input` (raw events) so it stays smooth during **hit-stop** (`Engine.time_scale = 0.02`).
- [ ] Camera shake as **rotation trauma** (pitch/roll), not position — research the "trauma²" shake approach.
- [ ] Crosshair raycast (`PhysicsRayQueryParameters3D` / `RayCast3D`), ~2–2.5 m reach, re-checked on the impact frame.

## Movement (traversal pillar)

- [ ] `CharacterBody3D` fundamentals in Godot 4: `floor_max_angle`, `floor_snap_length`, slopes and steps.
- [ ] Acceleration / friction tuning so movement isn't icy (separate ground vs. air control).
- [ ] Jump feel: coyote time, jump buffering, variable jump height.
- [ ] **Slide:** crouch while sprinting → slide, gaining speed down slopes; how to get the slope normal from Terrain3D/collision.
- [ ] **Mantle:** ledge detection with raycasts (forward chest ray + downward ray from above the ledge), then a short pull-up tween/animation.
- [ ] Check how mantling works on Terrain3D (heightmaps have no overhangs, so ledges will mostly be placed rocks/meshes).
- [ ] Motion-sickness checks: FOV setting, subtle/optional head-bob, small FOV kick when sprinting/sliding.
- [ ] Surface-aware footsteps: read Terrain3D's texture under the player, play positional 3D footsteps from the feet.
- [ ] Level design: put rare/high-level nodes on hard-to-reach ledges and outcrops.
- [ ] Later: grapple / rope; optional Agility skill or a craftable grapple for gating.

## Physics (Jolt)

- [ ] `RigidBody3D` chunk debris that fades out after a couple of seconds — collision layers so debris hits the world, not the player.
- [ ] Toppling tree as a rigid body: pivot at the base, initial push away from the player, detect when it lands (for the thud + log drops).
- [ ] Physical item drops (`RigidBody3D`) + magnet pull + auto-pull timeout.
- [ ] Check how rigid bodies behave during hit-stop (time scale 0.02).

## Audio (surround)

- [ ] `AudioStreamPlayer3D` settings: attenuation model, unit size, max distance, doppler (probably off).
- [ ] `AudioListener3D` on the camera.
- [ ] Test 5.1 / 7.1 output (Project Settings → Audio → driver channel count / speaker mode) and with headphones.
- [ ] Audio buses: reverb for the area (`Area3D` reverb bus), separate bus for UI/pickup sounds (non-positional).
- [ ] Heavy, positional thud for the tree landing.

## Future gameplay (design hooks only — not building yet)

- [ ] **Interactive gathering / weak points:** aim or hover at specific spots on a node for bonus damage/XP/effects.
      Hook: `hit()` takes a `HitInfo` (position, normal, collider), weak points are small `Area3D`s or chunk colliders.
- [ ] Save which nodes are depleted + their respawn timers (currently not saved — fine for a small test area).

---

## Decisions so far (for reference)

| # | Topic | Decision |
|---|-------|----------|
| 1 | Camera | First-person. Goals: depth, shadows, lighting, impactful surround sound. |
| 2 | Look | Clean, flat-shaded low-poly at native resolution. |
| 3 | Texturing | One shared palette atlas, one material for everything. |
| 4 | Modelling | Greybox with Godot primitives now; learn Blender on the side; export `.glb`. |
| 5 | Targeting | Crosshair raycast, hold-to-swing, re-check on impact frame, outline on hovered node, level-requirement shown on hover. |
| 6 | Viewmodel | Tool only (block hands later), rendered in a SubViewport with its own camera/FOV. |
| 7 | Depletion | Chunks pop off as fading `RigidBody3D` debris → rubble/stump. Trees topple as a rigid body. Debris doesn't affect the player. Respawn grow-in tween kept. |
| 8 | Loot | Physical drops + magnet, billboard icons for greybox, auto-pull timeout, collect at chest height, logs drop along fallen trunk. |
| 9 | World | Terrain3D heightmap terrain. |
| 10 | Movement | Expressive movement is the second pillar — it carries you between gathering spots. |
| 11 | Moves | Sprint, jump, slide, mantle first; grapple later. Light gating: rare nodes in hard-to-reach spots, no unlocks needed. No gathering while airborne/sliding; keep the swing slow-down. |
| 12 | Migration | Convert in place (game may be broken mid-way). 2D version committed and tagged `2d-prototype` in git. |
| 13 | Order | One system at a time, runnable after each step: (1) project settings + 3D main scene, (2) FP player + rotation shake, (3) gathering a rock end-to-end, (4) pickups + HUD rescale, (5) tree topple, (6) slide + mantle, (7) Terrain3D. |
| 14 | Saving nodes | Not saved for now; add depletion/respawn saving together with Terrain3D. |

## Still open

- Nothing — design tree covered. Revisit Terrain3D (4.7 support + low-poly look) before step 7.
