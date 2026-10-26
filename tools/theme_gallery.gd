extends SceneTree
## Theme gallery: lines nodes up in the main world, a row per theme (data/themes/), and saves a
## screenshot, to judge how each place dresses them. Within a row, the first half share a cluster
## (siblings), the rest are each their own cluster.
##
##   godot --path . --screen 1 --resolution 1600x900 -s res://tools/theme_gallery.gd -- --nodes=rock
##
## Options (after `--`):
##   --nodes=A,B    the node scenes (scenes/<name>.tscn), each `--copies` times along a row
##   --themes=A,B   the themes, a row each; "plain" = no theme (default: plain and every theme)
##   --copies=N     of each node per row (default 4)
##   --gap=M        between nodes (default 3.2)
##   --view=DEG     how steeply the camera looks down (default 28)
##   --looks        each node in all its looks instead (the model, then the variants), grouped by
##                  shape family: 0 4 8 | 1 5 | 2 6 | 3 7
##   --hit=N        strike every node N times first, to show the fresh insides against the dressing
##   --label=NAME   file name under docs/images/themes/ (default "gallery")
## The game is played on a throwaway save, so the real one is never touched.

var nodes: PackedStringArray = ["rock"]
var themes: PackedStringArray = []
var copies := 4
var gap := 3.2
var view := 28.0
var hits := 0
var looks := false
## --looks: the model (0) and its variants, family by family (NodeSpawner.FAMILIES).
const LOOK_ORDER: Array[int] = [0, 4, 8, 1, 5, 2, 6, 3, 7]
var label := "gallery"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"nodes": nodes = v.split(",")
			"themes": themes = v.split(",")
			"copies": copies = v.to_int()
			"gap": gap = v.to_float()
			"view": view = v.to_float()
			"hit": hits = v.to_int()
			"looks": looks = true
			"label": label = v
	if looks:
		copies = LOOK_ORDER.size()
	if themes.is_empty():
		themes = ["plain"]
		for f in DirAccess.get_files_at("res://data/themes"):
			if f.ends_with(".tres"):
				themes.append(f.get_basename())
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", "user://theme_gallery_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://theme_gallery_save.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/images/themes"))
	change_scene_to_file("res://scenes/main.tscn")
	await _wait(2.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	root.get_node("DayNight").set("time", 0.42)
	root.get_node("Skills").call("set_level", &"mining", 50)
	root.get_node("Skills").call("set_level", &"woodcutting", 50)
	root.get_node("Tools").call("set_tier", &"pickaxe", 3)
	root.get_node("Tools").call("set_tier", &"axe", 3)
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	var player := get_first_node_in_group("player") as Node3D
	var cols := nodes.size() * copies
	var width := (cols - 1) * gap
	var depth := (themes.size() - 1) * gap * 1.4
	print("GALLERY %d themes x %d nodes" % [themes.size(), cols])
	var centre := _open_ground(terrain, player.global_position, maxf(width, depth) * 0.5 + 4.0)
	print("GALLERY at %s" % centre.snapped(Vector3.ONE * 0.1))
	_clear_round(centre, maxf(width, depth) * 0.5 + 6.0)
	var made: Array[Node3D] = []
	for r in themes.size():
		var theme: NodeTheme = null if themes[r] == "plain" else load("res://data/themes/%s.tres" % themes[r])
		for c in cols:
			var scene: PackedScene = load("res://scenes/%s.tscn" % nodes[c / copies])
			var node := scene.instantiate() as Node3D
			node.set("save_id", StringName("gallery_%d_%d" % [r, c]))
			var i := c % copies
			if looks and LOOK_ORDER[i] > 0:
				node.set("model", load("res://models/variants/%s_v%d.glb" % [_model_name(node), LOOK_ORDER[i]]))
			if theme:
				var look := theme.look(hash(["sib", r] if i < copies / 2 else ["own", r, c]), hash([r, c]))
				node.set("look", look)
			var at := centre + Vector3(c * gap - width * 0.5, 0.0, r * gap * 1.4 - depth * 0.5)
			at.y = terrain.data.get_height(at) - 0.1
			node.position = at
			node.rotation.y = hash([c, r]) % 628 / 100.0
			current_scene.add_child(node)
			made.append(node)
		print("ROW %d %s  %s" % [r, themes[r], theme.title if theme else "as made"])
	player.call("teleport", centre + Vector3(0, 0, depth * 0.5 + 30.0), centre)
	await _wait(1.0)
	for k in hits:
		for node in made:
			var from := node.global_position + Vector3(0, 1.2, 2.5)
			var q := PhysicsRayQueryParameters3D.create(from, node.global_position + Vector3(0, 0.6, 0))
			var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and node.call("is_available"):
				node.call("hit", HitInfo.new(hit["position"], hit["normal"], hit["collider"], from))
				node.call("set_highlighted", false)
		await _wait(0.7)
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	var span := maxf(width, depth * 1.6) + gap * 2.0
	var back := span * 0.55 / tan(deg_to_rad(cam.fov * 0.5)) * 0.5
	var tilt := deg_to_rad(view)
	cam.global_position = centre + Vector3(0, sin(tilt) * back + 0.8, depth * 0.5 + cos(tilt) * back)
	cam.look_at(centre + Vector3(0, 0.6, depth * 0.1))
	cam.current = true
	await _wait(2.5)
	await _shot("res://docs/images/themes/%s.png" % label)
	print("SAVED docs/images/themes/%s.png" % label)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://theme_gallery_save.json"))
	quit()


## The file name of the model a node scene wears (models/<name>.glb).
func _model_name(node: Node) -> String:
	return (node.get("model") as PackedScene).resource_path.get_file().get_basename()


## The flattest open spot near `from` with room for a gallery of radius `r`.
func _open_ground(terrain: Terrain3D, from: Vector3, r: float) -> Vector3:
	var best := from
	var best_score := INF
	for ring in range(1, 8):
		for k in 12:
			var p := from + Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 12.0) * ring * 12.0
			var hs: Array[float] = []
			for o in [Vector3.ZERO, Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
				var h: float = terrain.data.get_height(p + o)
				hs.append(h if not is_nan(h) else -100.0)
			var score: float = hs.max() - hs.min()
			if hs.min() > 0.2 and score < best_score:
				best_score = score
				best = p
	best.y = terrain.data.get_height(best)
	return best


## Hides what stands round `centre`, so the gallery has the ground to itself.
func _clear_round(centre: Vector3, r: float) -> void:
	for group in ["gatherable", "prop", "building"]:
		for n in get_nodes_in_group(group):
			var g := (n as Node3D).global_position
			if Vector2(g.x - centre.x, g.z - centre.z).length() < r:
				(n as Node3D).visible = false
				if n is CollisionObject3D:
					(n as CollisionObject3D).collision_layer = 0
	for s in current_scene.find_children("*", "SceneryScatter", true, false):
		(s as Node3D).visible = false


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await process_frame


func _shot(path: String) -> void:
	for layer in root.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(path)
