class_name QuarryDressing
extends Node3D
## Greystone as a working quarry (plans/mine.md): the CC0 pack pieces (models/mine/) set out on
## its levels, a puddle on the floor ringed with stones. Each piece is placed by level and angle
## round the pit, on the free arc of its level (the haul road's ramps spiral down the other side:
## tools/generate_test_terrain.gd), and stands on the ground.

const MINE := "res://models/mine/%s.glb"
## Pieces painted from our palette (rubberduck's); the rest keep their own painted materials.
const PALETTE_PIECES: Array[String] = ["frame_square", "frame_braced", "frame_arched", "post_cap",
	"post_crossbraced", "post_brackets", "gate_posts", "planks", "boardwalk", "lamp_hanging",
	"lamp_hanging_plain", "chest", "boulder_small", "rubble_pile", "stalactite", "stalactite_cluster"]
const WATER := preload("res://shaders/water.gdshader")
const STONE := preload("res://models/scenery/shore_stone.glb")
## Where each level's props stand, as a distance from the pit's middle: just in from the level's
## inner edge, clear of the ramp that runs along its outer wall.
const RIM := 60.0
const LEVEL := [48.0, 38.0, 28.0, 17.5]
const FLOOR := 9.0

## [model, distance, angle (degrees round the pit, from +X toward +Z), turn (degrees), collide,
##  optional (along the level, up) in metres: a hanging lamp at the end of its post's arm]
const PIECES := [
	# the rim: a lamp post at the road's top, the yard's crates and barrels
	["post_cap", RIM, -18.0, 0.0, true], ["lamp_hanging", RIM, -18.0, 0.0, false, Vector2(1.15, 2.42)],
	["crate", RIM + 1.5, -8.0, 15.0, true], ["crate", RIM + 1.4, -6.5, -10.0, true],
	["barrel", RIM + 2.2, -4.0, 0.0, true], ["barrel", RIM + 1.0, -2.5, 0.0, true],
	["tub", RIM - 1.0, 4.0, 0.0, true], ["chain_coil", RIM, 8.0, 30.0, false],
	["rope", RIM + 1.0, 9.5, 0.0, false],
	# level 1: a stretch of rail with a cart on it, tools against a crate
	["rail", LEVEL[0], 40.0, 0.0, false], ["rail", LEVEL[0], 42.4, 0.0, false],
	["rail", LEVEL[0], 44.8, 0.0, false], ["cart_low", LEVEL[0], 42.4, 90.0, true],
	["crate", LEVEL[0], 52.0, 20.0, true], ["pickaxe", LEVEL[0] + 0.6, 53.0, 70.0, false],
	["shovel", LEVEL[0] - 0.4, 54.0, 10.0, false], ["lamp_hanging_plain", LEVEL[0], 60.0, 0.0, false, Vector2(1.15, 2.42)],
	["post_cap", LEVEL[0], 60.0, 0.0, true],
	["barrel", LEVEL[0], 150.0, 0.0, true], ["bucket", LEVEL[0] + 0.8, 151.5, 0.0, false],
	# level 2: the sorting place
	["tub", LEVEL[1], 20.0, 0.0, true], ["jar", LEVEL[1] + 0.9, 22.0, 0.0, true],
	["basin", LEVEL[1], 25.0, 0.0, true], ["hammer", LEVEL[1], 25.0, 40.0, false],
	["cart_tall", LEVEL[1], 95.0, 70.0, true], ["rubble_pile", LEVEL[1] + 1.5, 98.0, 0.0, false],
	["post_crossbraced", LEVEL[1], 110.0, 0.0, true], ["lamp_hanging", LEVEL[1], 110.0, 0.0, false, Vector2(0.95, 2.6)],
	# level 3: a cleared ledge, a fallen chest of tools, the stone pillars of an old crane
	["pillar_half", LEVEL[2], 0.0, 0.0, true], ["pillar_half", LEVEL[2], 6.0, 0.0, true],
	["chest", LEVEL[2] - 0.5, 3.0, 90.0, true], ["pickaxe_bronze", LEVEL[2] + 0.7, 9.0, 40.0, false],
	["rock_a", LEVEL[2], 30.0, 0.0, true], ["rock_b", LEVEL[2] + 1.2, 33.0, 60.0, true],
	# level 4: the gate down to the floor, a lamp
	["gate_posts", LEVEL[3], 205.0, 0.0, true], ["lamp_hanging_plain", LEVEL[3], 212.0, 0.0, false, Vector2(0.85, 2.0)],
	["post_brackets", LEVEL[3], 212.0, 0.0, true], ["rubble_pile", LEVEL[3], 225.0, 0.0, false],
	# the floor: crates by the mine mouth, a boardwalk to the puddle
	["crate", 11.5, 122.0, 10.0, true], ["barrel", 11.0, 117.0, 0.0, true],
	["torch", 12.5, 150.0, 0.0, false], ["boardwalk", FLOOR - 2.5, 200.0, 20.0, false],
]
## The puddle on the floor: distance, angle, radius.
const PUDDLE := Vector3(FLOOR, 200.0, 2.2)

var _terrain: Terrain3D


func _ready() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	for p in PIECES:
		_place(p[0], p[1], p[2], p[3], p[4], p[5] if p.size() > 5 else Vector2.ZERO)
	_puddle()


func _at(dist: float, angle_deg: float) -> Vector3:
	var a := deg_to_rad(angle_deg)
	var c := WorldMap.QUARRY_CENTER
	var p := Vector3(c.x + cos(a) * dist, 0.0, c.y + sin(a) * dist)
	p.y = _height(p)
	return p


func _height(p: Vector3) -> float:
	var h: float = _terrain.data.get_height(p) if _terrain and _terrain.data else NAN
	return 0.0 if is_nan(h) else h


func _place(model: String, dist: float, angle_deg: float, turn: float, collide: bool, offset: Vector2) -> Prop:
	var prop := Prop.new()
	prop.name = model.to_pascal_case()
	prop.model = load(MINE % model)
	prop.collide = collide
	prop.own_materials = model not in PALETTE_PIECES
	var at := _at(dist, angle_deg)
	var a := deg_to_rad(angle_deg)
	at += Vector3(sin(a), 0.0, -cos(a)) * offset.x + Vector3.UP * offset.y
	prop.position = at - global_position
	# its front (-Z) toward the pit's middle, its X along the level; then the piece's own turn
	prop.rotation.y = PI / 2.0 - deg_to_rad(angle_deg) + deg_to_rad(turn)
	add_child(prop)
	return prop


func _puddle() -> void:
	var at := _at(PUDDLE.x, PUDDLE.y)
	var water := MeshInstance3D.new()
	water.name = "Puddle"
	var disc := CylinderMesh.new()
	disc.top_radius = PUDDLE.z
	disc.bottom_radius = PUDDLE.z
	disc.height = 0.02
	disc.radial_segments = 24
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	disc.material = mat
	water.mesh = disc
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = at - global_position + Vector3(0, 0.06, 0)
	add_child(water)
	for i in 9:  # stones round its edge
		var a := TAU * i / 9.0 + 0.3
		var stone := STONE.instantiate() as Node3D
		var r := PUDDLE.z + 0.15
		var p := at + Vector3(cos(a) * r, 0.0, sin(a) * r)
		p.y = _height(p) - 0.05
		stone.position = p - global_position
		stone.rotation.y = a * 2.3
		stone.scale = Vector3.ONE * (0.6 + 0.35 * fmod(i * 0.618, 1.0))
		add_child(stone)
		for m in stone.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = PaletteMaterial.for_mesh((m as MeshInstance3D).mesh)
