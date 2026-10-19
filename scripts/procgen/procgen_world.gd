class_name ProcgenWorld
extends Node3D
## The root of scenes/procgen.tscn: on load it builds a ProcgenMap from `world_seed`, hands it to
## the Terrain3D child, and only then lets the player move, behind a "Generating…" overlay.
## Each seed saves to its own file (save_path()), with its own character, so nothing here touches
## the main world's save. Enter with ProcgenWorld.enter(), leave with ProcgenWorld.leave(): the
## debug menu's Procgen tab, or `--procgen [--seed=N]` on the command line.

const SCENE := "res://scenes/procgen.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const Player := preload("res://scripts/player.gd")
const WATER_SHADER := preload("res://shaders/water_lowpoly.gdshader")
const PERCH := preload("res://data/fish/perch.tres")
const TROUT := preload("res://data/fish/trout.tres")
const PIKE := preload("res://data/fish/pike.tres")
const CHAR := preload("res://data/fish/char.tres")
## Schools per water body, as in the hand-built ponds and lake.
const POND_SCHOOLS: Array[FishSpecies] = [PERCH, PERCH, TROUT, PIKE]
const LAKE_SCHOOLS: Array[FishSpecies] = [TROUT, TROUT, PERCH, CHAR, CHAR]

## The seed the scene builds next time it loads (enter() sets it).
static var world_seed := 1

var map: ProcgenMap

@onready var _terrain := $Terrain3D as Terrain3D
@onready var _player := $Player as Player


static func save_path(s: int) -> String:
	return "user://procgen_%d.json" % s


## Switches to seed `s`'s save and (re)loads the procgen scene.
static func enter(tree: SceneTree, s: int) -> void:
	world_seed = s
	SaveGame.use_file(save_path(s))
	tree.change_scene_to_file(SCENE)


## Back to the hand-built world and its save.
static func leave(tree: SceneTree) -> void:
	SaveGame.use_file(SaveGame.MAIN_PATH)
	tree.change_scene_to_file(MAIN_SCENE)


static func random_seed() -> int:
	return randi_range(1, 999_999)


func _ready() -> void:
	add_to_group("procgen_world")
	Biome.locator = func(_p: Vector3) -> StringName: return &""  # until the map exists
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var overlay := _overlay()
	# let the overlay draw before the generator holds up the frame
	await get_tree().process_frame
	await get_tree().process_frame
	var started := Time.get_ticks_msec()
	map = ProcgenMap.new(world_seed)
	map.generate()
	_build_terrain()
	_build_water()
	Biome.locator = func(p: Vector3) -> StringName: return map.biome_at(Vector2(p.x, p.z))
	if not map.quarry.is_empty():
		Biome.quarry_rim_height = map.quarry["rim_height"]
		Biome.quarry_depth = map.quarry["depth"]
	for biome in map.kinds:
		Biome.kind_names[biome] = map.kind_name(biome)
	print("Procgen: seed %d generated in %d ms" % [world_seed, Time.get_ticks_msec() - started])
	_place_player()
	ProcgenPopulation.populate(self, map)
	await get_tree().process_frame  # the spawners and the scenery fill in at the end of that frame
	print("Procgen: seed %d ready in %d ms" % [world_seed, Time.get_ticks_msec() - started])
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	overlay.queue_free()


func _exit_tree() -> void:
	Biome.locator = Callable()
	Biome.reset_quarry()


## A WaterBody per basin the map carved, built like the hand-made ponds in main.tscn: a box volume,
## the water surface, reeds and lily pads (PondDressing) and fish (FishPond).
func _build_water() -> void:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	for i in map.waters.size():
		var w: Dictionary = map.waters[i]
		var r: float = w["radius"]
		var lake: bool = w["lake"]
		var size := 2.0 * r + 8.0  # the box covers the shallows round the ragged shore too
		var body := WaterBody.new()
		body.name = w["name"]
		body.position = Vector3(w["center"].x, 0.0, w["center"].y)
		body.collision_layer = 0
		body.collision_mask = 0
		body.surface_height = ProcgenMap.WATER_LEVEL
		var volume := CollisionShape3D.new()
		volume.name = "Volume"
		volume.position.y = -1.0
		var box := BoxShape3D.new()
		box.size = Vector3(size, 3.0, size)
		volume.shape = box
		body.add_child(volume)
		var dressing := PondDressing.new()
		dressing.name = "Dressing"
		dressing.seed = map.sub_seed(StringName("dressing_%d" % i))
		var area := r * r / 81.0  # relative to the hand-built clearing pond (radius 9)
		dressing.reed_clumps = roundi(9 * area)
		dressing.lily_pads = roundi(14 * area)
		dressing.stones = roundi(12 * sqrt(area))
		body.add_child(dressing)
		var fish := FishPond.new()
		fish.name = "Fish"
		fish.schools = LAKE_SCHOOLS if lake else POND_SCHOOLS
		body.add_child(fish)
		var surface := MeshInstance3D.new()
		surface.name = "Surface"
		surface.position.y = ProcgenMap.WATER_LEVEL
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var plane := PlaneMesh.new()
		plane.material = material
		plane.size = Vector2(size, size)
		plane.subdivide_width = int(size) - 1
		plane.subdivide_depth = int(size) - 1
		surface.mesh = plane
		body.add_child(surface)
		add_child(body)


func _build_terrain() -> void:
	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = map.height_image()
	_terrain.data.import_images(images, ProcgenMap.ORIGIN, 0.0, 1.0)
	for y in ProcgenMap.SIZE:
		for x in ProcgenMap.SIZE:
			var id := map.ids[y * ProcgenMap.SIZE + x]
			if id != WorldMap.TEX_DEFAULT:
				var w := ProcgenMap.world(x, y)
				_terrain.data.set_control_base_id(Vector3(w.x, 0, w.y), id)
	_terrain.data.update_maps(Terrain3DRegion.TYPE_CONTROL)  # painting at runtime only reaches the GPU here


## A fresh character starts in the hub; a saved one where they left off, but never under the ground.
func _place_player() -> void:
	var p := _player
	if not SaveGame.has(&"player"):
		var at := map.hub
		p.teleport(Vector3(at.x, map.height_at(at) + 0.1, at.y), Vector3(at.x, 0, at.y - 10.0))
		return
	var pos := p.global_position
	var ground := map.height_at(Vector2(pos.x, pos.z))
	if pos.y < ground:
		p.teleport(Vector3(pos.x, ground + 0.1, pos.z))


func _overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 20
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.075, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.text = "Generating…\nseed %d" % world_seed
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color("ffd27a"))
	layer.add_child(label)
	add_child(layer)
	return layer
