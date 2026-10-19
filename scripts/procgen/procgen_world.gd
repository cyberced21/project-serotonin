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
const WATER_SHADER := preload("res://shaders/water.gdshader")
const PERCH := preload("res://data/fish/perch.tres")
const TROUT := preload("res://data/fish/trout.tres")
const PIKE := preload("res://data/fish/pike.tres")
const CHAR := preload("res://data/fish/char.tres")
## Schools per water body, as in the hand-built ponds and lake.
const POND_SCHOOLS: Array[FishSpecies] = [PERCH, PERCH, TROUT, PIKE]
const LAKE_SCHOOLS: Array[FishSpecies] = [TROUT, TROUT, PERCH, CHAR, CHAR]
const PIKE_SCHOOLS: Array[FishSpecies] = [PIKE, PIKE, PIKE]
const PROP := preload("res://scripts/prop.gd")

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
	_build_rivers()
	_build_village()
	ProcgenLandmarks.build(self, map)
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
## Each river's water: one surface following its bends (a strip, the water shader works from world
## position), and a WaterBody every RIVER_SEGMENT metres along it, its box turned along the river,
## so wading, splashes and footsteps work in it like in a pond.
const RIVER_SEGMENT := 10


func _build_rivers() -> void:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	for r in map.rivers.size():
		var pts: PackedVector2Array = map.rivers[r]["points"]
		var widths: PackedFloat32Array = map.rivers[r]["widths"]
		var river := Node3D.new()
		river.name = "River%d" % (r + 1)
		add_child(river)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y := ProcgenMap.WATER_LEVEL
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			var na := _across(pts, k) * (widths[k] + 2.0)
			var nb := _across(pts, k + 1) * (widths[k + 1] + 2.0)
			var al := Vector3(a.x - na.x, y, a.y - na.y)
			var ar := Vector3(a.x + na.x, y, a.y + na.y)
			var bl := Vector3(b.x - nb.x, y, b.y - nb.y)
			var br := Vector3(b.x + nb.x, y, b.y + nb.y)
			for v in [al, bl, ar, ar, bl, br]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
		var surface := MeshInstance3D.new()
		surface.name = "Surface"
		surface.mesh = st.commit()
		surface.material_override = material
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		river.add_child(surface)
		for k in range(0, pts.size() - 1, RIVER_SEGMENT):
			var a := pts[k]
			var b := pts[mini(k + RIVER_SEGMENT, pts.size() - 1)]
			var body := WaterBody.new()
			body.name = "Stretch%d" % (k / RIVER_SEGMENT + 1)
			body.position = Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
			body.rotation.y = atan2(b.x - a.x, b.y - a.y)  # its box's length (Z) along the river
			body.collision_layer = 0
			body.collision_mask = 0
			body.surface_height = y
			var volume := CollisionShape3D.new()
			volume.name = "Volume"
			volume.position.y = -1.0
			var box := BoxShape3D.new()
			box.size = Vector3(widths[k] * 2.0 + 6.0, 3.0, a.distance_to(b) + 2.0)
			volume.shape = box
			body.add_child(volume)
			river.add_child(body)


## The unit vector across the river at point k (to its right, looking downstream).
static func _across(pts: PackedVector2Array, k: int) -> Vector2:
	var along := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
	return Vector2(-along.y, along.x)


## Hearthvale's buildings (each with its villager) and props, where the map laid them out. Their
## tiers are the Village autoload's, saved with this seed like everything else.
func _build_village() -> void:
	if map.village.is_empty():
		return
	var root := Node3D.new()
	root.name = "Village"
	add_child(root)
	var y: float = map.village["height"]
	for b in map.village["buildings"]:
		var building := (load("res://scenes/village/%s.tscn" % b[0]) as PackedScene).instantiate() as Node3D
		building.position = Vector3(b[1].x, y, b[1].y)
		building.rotation.y = b[2]
		root.add_child(building)
	for p in map.village["props"]:
		var prop := StaticBody3D.new()
		prop.set_script(PROP)
		prop.set("model", load("res://models/village/props/%s.glb" % p[0]))
		prop.position = Vector3(p[1].x, y, p[1].y)
		prop.rotation.y = p[2]
		root.add_child(prop)


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
		if w.get("schools") == &"pike":  # a rare spot: nothing but pike
			fish.schools = PIKE_SCHOOLS
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
