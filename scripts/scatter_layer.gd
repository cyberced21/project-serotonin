class_name ScatterLayer
extends Resource
## One kind of scenery SceneryScatter spreads over the terrain (grass, flowers, bushes, boulders).

## A .glb with a single mesh, origin at its base (tools/blender/make_models.py, scenery()).
@export var model: PackedScene
## Average number per 100 m² of ground it's allowed on.
@export var density := 1.0
@export var scale_range := Vector2(0.8, 1.2)
## Grow in clumps: each spot gets this many (min, max), spread within cluster_radius metres.
## `density` then counts clumps, not single plants.
@export var cluster := Vector2i(1, 1)
@export var cluster_radius := 0.8
## Steepest ground it grows on: minimum terrain normal Y (1 = flat only, 0.7 = steep slopes too).
@export_range(0.0, 1.0) var min_normal_y := 0.86
## 0 = none. Sways in the breeze, more for taller parts (see shaders/sway_instanced.gdshader).
@export var sway := 0.0
## Lean with the slope instead of standing upright (boulders).
@export var align_to_slope := false
## Give each one a collision shape (boulders). Keep this for small counts.
@export var collide := false
@export var cast_shadow := true
## Hidden beyond this distance (0 = always drawn). Small things vanish early to save draw time.
@export var visible_distance := 0.0
## Extra clearance kept from nodes, buildings and props (m), on top of their own radius.
@export var clearance := 0.0
