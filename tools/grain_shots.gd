extends SceneTree
## Screenshots of grain looks (shaders/grain.gdshader) over a fresh Hearthvale: a meadow and the
## cobbled street in the morning, the street at dusk. Each look in LOOKS is shot from every view;
## a look with grain_speed gets FRAMES shots with a new noise pattern each, to play as motion.
##   godot --path . --audio-driver Dummy --screen 1 --resolution 1280x720 -s res://tools/grain_shots.gd -- --save-root=user://grain_shots [--looks=off,dots] [--out=C:/some/folder]
## Saves <look>_<view>[_<frame>].jpg to docs/images/grain/ (or --out). With --game: the game's own
## GrainOverlay instead, an axe in hand, as game_on.jpg and game_off.jpg.

const FRAMES := 4

const VIEWS := [
	# name, hour, eye, look-at
	["meadow", 10.5, Vector3(60, 0, 80), Vector3(46, 0.2, 66)],
	["street", 10.5, Vector3(96, 2.2, 134), Vector3(96, 0.01, 129)],
	["dusk", 19.5, Vector3(96, 2.2, 134), Vector3(96, 0.01, 129)],
]

const LOOKS := {
	"off": {},
	# a fixed dot pattern between colour steps, picture kept sharp
	"dots": {&"levels": 20.0, &"dither": 1.0},
	# film grain, new every frame, mostly in the shadows
	"film": {&"grain": 0.07, &"grain_size": 1.5, &"grain_speed": 24.0, &"shadow_weight": 0.7},
	# halfway: 2x pixels, steps with dots, a little still grain
	"soft_chunky": {&"pixel_size": 2.0, &"levels": 24.0, &"dither": 1.0, &"grain": 0.03, &"shadow_weight": 0.5},
	# like the Reddit game: 3x pixels, few steps with dots
	"chunky": {&"pixel_size": 3.0, &"levels": 14.0, &"dither": 1.0},
}

var player: CharacterBody3D
var terrain: Terrain3D
var day_night: Node
var day: GDScript
var out := "res://docs/images/grain"
var mat: ShaderMaterial
var game := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var looks: Array = LOOKS.keys()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--looks="):
			looks = Array(arg.trim_prefix("--looks=").split(","))
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--game":
			game = true
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
	player.set_physics_process(false)

	if game:  # the game's own GrainOverlay, an axe in hand, grain on then off
		player.call("equip_now", &"axe")
		var own := player.get_node("Grain") as CanvasLayer
		var vm := player.get_node("Viewmodel") as CanvasLayer
		_set_hour(10.5)
		_view(VIEWS[1][2], VIEWS[1][3])
		await _wait(3.0)
		for on in [true, false]:
			root.get_node("Settings").call("set_value", "display", "grain", on)
			await _shot("game_%s" % ("on" if on else "off"), [own, vm])
		quit()
		return

	var layer := CanvasLayer.new()
	layer.name = "GrainLayer"
	layer.layer = 50
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/grain.gdshader")
	rect.material = mat
	layer.add_child(rect)
	root.add_child(layer)

	var hour := -1.0
	for v in VIEWS:
		if v[1] != hour:
			hour = v[1]
			_set_hour(hour)
			await _wait(2.0)
		_view(v[2], v[3])
		await _wait(1.5)
		for look in looks:
			_apply(LOOKS[look])
			var frames := FRAMES if float(LOOKS[look].get(&"grain_speed", 0.0)) > 0.0 else 1
			for f in frames:
				mat.set_shader_parameter(&"grain_speed", 0.0)
				mat.set_shader_parameter(&"seed", float(f * 7 + 1))
				var name := "%s_%s" % [look, v[0]]
				if frames > 1:
					name += "_%d" % f
				await _shot(name, [layer])
	quit()


func _apply(look: Dictionary) -> void:
	var base := {&"pixel_size": 1.0, &"levels": 0.0, &"dither": 0.0, &"grain": 0.0, &"grain_size": 1.0,
			&"grain_speed": 0.0, &"seed": 0.0, &"shadow_weight": 0.0, &"colour_grain": false}
	for key in base:
		mat.set_shader_parameter(key, look.get(key, base[key]))


func _set_hour(h: float) -> void:
	day_night.set("time", day.call("time_at", h))
	day_night.set("frozen", true)


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


func _shot(name: String, keep: Array) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible and not keep.has(layer):
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	await process_frame
	root.get_texture().get_image().save_jpg("%s/%s.jpg" % [out, name], 0.95)
	print("SHOT ", name)
	for layer in hidden:
		layer.visible = true


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
