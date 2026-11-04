extends SceneTree
## Screenshots of the ground (plans/ground-depth.md) in a fresh Hearthvale, mid-morning: a meadow,
## a hillside, the forest floor, the snowy peak, a packed road beside a dirt path, the cobbled
## street. Each look in LOOKS (sets of terrain shader parameters) is shot from every view, so
## candidate looks can be compared side by side; "game" is the shader's own defaults.
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/ground_shots.gd -- --save-root=user://ground_shots [--looks=game,before] [--out=C:/some/folder]
## Saves <look>_<view>.jpg to docs/images/ground/ (or --out). (No game class names: an -s script
## compiles before the autoloads.)

const SPEED := 10.0

const VIEWS := [
	["meadow", Vector3(60, 0, 80), Vector3(46, 0.2, 66)],
	["hillside", Vector3(124, 0, -6), Vector3(128, 0, 128)],
	["forest", Vector3(128, 2.0, -20), Vector3(128, 0, -60)],
	["peak", Vector3(0, 0, 0), Vector3(0, 0, 0)],  # placed by the highest ground (see _run)
	["roads", Vector3(0, 0, 0), Vector3(0, 0, 0)],  # placed along the village road (see _run)
	["cobbles", Vector3(96, 2.2, 134), Vector3(96, 0.01, 129)],
	["air", Vector3(128, 70, 230), Vector3(130, 0, 140)],
]

## Parameter sets. "before" switches the new depth off and restores the old palette.
const LOOKS := {
	"game": {},
	"before": {
		&"normal_strength": 0.0, &"crevice_strength": 0.0, &"coarse_strength": 0.0,
		&"hollow_strength": 0.0, &"second_strength": 0.0, &"slope_breakup": 0.0, &"rock_band_strength": 0.0,
		&"snow_wander": 0.0, &"snow_cling": 0.0, &"saturation": 1.0,
		&"lush_tint": Color(1, 1, 1), &"dry_tint": Color(1, 1, 1),
		&"grass_color": Color(0.36, 0.55, 0.30), &"grass_color_2": Color(0.42, 0.60, 0.31),
		&"dirt_color": Color(0.52, 0.42, 0.30), &"rock_color": Color(0.47, 0.46, 0.45),
		&"snow_color": Color(0.92, 0.94, 0.96), &"path_color": Color(0.63, 0.52, 0.40),
		&"forest_color": Color(0.23, 0.39, 0.22), &"forest_color_2": Color(0.27, 0.43, 0.24),
		&"needle_color": Color(0.42, 0.33, 0.22),
		&"field_color": Color(0.50, 0.62, 0.29), &"field_color_2": Color(0.56, 0.66, 0.31),
		&"shadow_tint": Color(0.70, 0.76, 0.86),
	},
	# A: richer, still natural: deeper greens, warm tips, cool blue-green shade, red-brown dirt.
	"a_rich": {
		&"grass_color": Color(0.29, 0.55, 0.21), &"grass_color_2": Color(0.40, 0.63, 0.23),
		&"dirt_color": Color(0.52, 0.39, 0.27), &"rock_color": Color(0.50, 0.48, 0.46),
		&"snow_color": Color(0.95, 0.97, 1.0), &"path_color": Color(0.66, 0.50, 0.34),
		&"forest_color": Color(0.17, 0.37, 0.18), &"forest_color_2": Color(0.23, 0.43, 0.20),
		&"needle_color": Color(0.48, 0.32, 0.19),
		&"field_color": Color(0.49, 0.66, 0.24), &"field_color_2": Color(0.58, 0.70, 0.26),
		&"shadow_tint": Color(0.62, 0.72, 0.90), &"saturation": 1.1,
	},
	# B: golden storybook: sunnier yellow-greens, strong dry patches, warm orange dirt, bolder bumps.
	"b_golden": {
		&"grass_color": Color(0.36, 0.58, 0.19), &"grass_color_2": Color(0.50, 0.67, 0.21),
		&"dirt_color": Color(0.56, 0.41, 0.26), &"rock_color": Color(0.53, 0.50, 0.46),
		&"snow_color": Color(0.97, 0.96, 0.95), &"path_color": Color(0.70, 0.53, 0.33),
		&"forest_color": Color(0.21, 0.39, 0.16), &"forest_color_2": Color(0.29, 0.46, 0.18),
		&"needle_color": Color(0.53, 0.35, 0.18),
		&"field_color": Color(0.56, 0.68, 0.22), &"field_color_2": Color(0.64, 0.72, 0.24),
		&"shadow_tint": Color(0.66, 0.70, 0.88), &"saturation": 1.15,
		&"dry_tint": Color(1.16, 1.06, 0.74), &"normal_strength": 1.3, &"crevice_strength": 0.6,
	},
	# C: cool and lush: blue-green grass, deep shade, darker earth, softer bumps.
	"c_lush": {
		&"grass_color": Color(0.25, 0.53, 0.26), &"grass_color_2": Color(0.33, 0.60, 0.28),
		&"dirt_color": Color(0.46, 0.36, 0.27), &"rock_color": Color(0.46, 0.47, 0.48),
		&"snow_color": Color(0.93, 0.96, 1.0), &"path_color": Color(0.60, 0.48, 0.36),
		&"forest_color": Color(0.15, 0.35, 0.21), &"forest_color_2": Color(0.20, 0.41, 0.24),
		&"needle_color": Color(0.42, 0.31, 0.21),
		&"field_color": Color(0.45, 0.63, 0.28), &"field_color_2": Color(0.52, 0.67, 0.30),
		&"shadow_tint": Color(0.55, 0.70, 0.95), &"crevice_tint": Color(0.32, 0.42, 0.66),
		&"lush_tint": Color(0.88, 1.04, 1.0), &"saturation": 1.05, &"normal_strength": 0.8,
	},
}

var player: CharacterBody3D
var terrain: Terrain3D
var day_night: Node
var day: GDScript
var out := "res://docs/images/ground"
var defaults := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var looks: Array = LOOKS.keys()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--looks="):
			looks = Array(arg.trim_prefix("--looks=").split(","))
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	for autoload in ["GraphicsSettings", "Settings"]:
		root.get_node(autoload).set("persist", false)  # never write the player's settings.cfg
	day = load("res://scripts/villager_day.gd")
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	await _wait(2.0)
	player = get_first_node_in_group("player") as CharacterBody3D
	terrain = get_first_node_in_group("terrain") as Terrain3D
	day_night = root.get_node("DayNight")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var roads := root.get_node("Roads")
	roads.call("set_level", &"village_road", 1)
	roads.call("set_level", &"main_street", 2)
	player.set_physics_process(false)
	await _run_to(10.5, 9.0)
	await _wait(2.0)

	# the roads view: along the packed village road where a dirt path leaves it
	var road := _road(&"village_road")
	var a := road[road.size() / 3]
	var b := road[mini(road.size() / 3 + 6, road.size() - 1)]
	var side := (b - a).normalized()
	side = Vector2(-side.y, side.x)
	var views := VIEWS.duplicate(true)
	views[4] = ["roads", Vector3(a.x, 0, a.y) + Vector3(side.x, 0, side.y) * 5.0 + Vector3(0, 2.0, 0),
			Vector3(b.x, 0.01, b.y)]

	# the peak view: from partway down the highest ground, looking up at its top
	var top := Vector3.ZERO
	for x in range(-480, 480, 8):
		for z in range(-480, 480, 8):
			var p := Vector3(x, 0, z)
			if _h(p) > top.y:
				top = Vector3(x, _h(p), z)
	var down := (Vector3(128, 0, 128) - Vector3(top.x, 0, top.z)).normalized()
	views[3] = ["peak", Vector3(top.x, 0, top.z) + down * 55.0 + Vector3(0, 4.0, 0), Vector3(top.x, -6.0, top.z)]

	var mat: Terrain3DMaterial = terrain.material
	for look in looks:
		for key in LOOKS[look]:
			if not defaults.has(key):
				var d: Variant = mat.get_shader_param(key)
				if d == null:
					d = RenderingServer.shader_get_parameter_default(load("res://shaders/terrain.gdshader").get_rid(), key)
				defaults[key] = d
	for look in looks:
		for key in defaults:
			mat.set_shader_param(key, defaults[key])
		for key in LOOKS[look]:
			mat.set_shader_param(key, LOOKS[look][key])  # (a Color, so it's taken as sRGB)
		var grass := get_first_node_in_group("grass_field")
		if grass == null:
			grass = root.find_child("GrassField", true, false)
		if grass:
			grass.call("_setup")  # blades take the look's colours
		for v in views:
			_view(v[1], v[2])
			await _shot("%s_%s" % [look, v[0]])
	quit()


func _road(id: StringName) -> PackedVector2Array:
	for r in load("res://scripts/world_map.gd").roads():
		if r["id"] == id:
			return r["pts"]
	return PackedVector2Array()


func _run_to(h: float, from := -1.0) -> void:
	if from >= 0.0:
		day_night.set("time", day.call("time_at", from))
	day_night.set("frozen", false)
	Engine.time_scale = SPEED
	var target: float = day.call("time_at", h)
	var guard := 0
	while absf(wrapf(float(day_night.get("time")) - target, -0.5, 0.5)) > 0.002 and guard < 60 * 300:
		await process_frame
		guard += 1
	Engine.time_scale = 1.0
	day_night.set("frozen", true)
	await _wait(0.5)


func _view(at: Vector3, look: Vector3) -> void:
	at.y = _h(at) + maxf(at.y, 0.0)
	player.global_position = at
	var d := look - at
	player.rotation.y = atan2(-d.x, -d.z)
	var target_y := _h(look) + look.y
	var pitch := atan2(target_y - (at.y + 1.6), Vector2(d.x, d.z).length())
	player.set("_pitch", pitch)
	(player.get("head") as Node3D).rotation.x = pitch
	player.call("reset_physics_interpolation")


func _h(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _shot(name: String) -> void:
	await _wait(1.5)
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_jpg("%s/%s.jpg" % [out, name], 0.85)
	print("SHOT ", name)
	for layer in hidden:
		layer.visible = true


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
