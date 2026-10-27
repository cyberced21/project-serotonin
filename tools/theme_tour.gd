extends SceneTree
## Theme tour: generates a procgen world and, in each biome, stands by its busiest cluster of
## nodes and saves a screenshot (docs/images/themes/<label>/<n>_<biome>_<kind>.png), to see a
## place's theme on its rocks, trees and scenery together. The debug menu builds the world from
## the same command line (`--procgen --seed=N`).
##
##   godot --path . --screen 1 --resolution 1280x720 -s res://tools/theme_tour.gd -- --procgen --seed=7
##
## Options (after `--`): --label=NAME (default "tour"), --distance=M (default 9), how far from the
## cluster the camera stands.
## The world saves to its own file (user://procgen_<seed>.json), deleted at the end; the main
## save is not loaded into, but back it up anyway.

var label := "tour"
var distance := 9.0
var world_seed := 0
## How high above the ground the camera stands (m): the player's eye, under the pines' skirts.
const EYE := 1.6


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")
		elif arg.begins_with("--distance="):
			distance = arg.trim_prefix("--distance=").to_float()
		elif arg.begins_with("--seed="):
			world_seed = arg.trim_prefix("--seed=").to_int()
	_run.call_deferred()


func _run() -> void:
	var out := "res://docs/images/themes/%s" % label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var world: Node = null
	var started := Time.get_ticks_msec()
	while world == null or (world.get("_player") as Node).process_mode == Node.PROCESS_MODE_DISABLED:
		await process_frame
		world = get_first_node_in_group("procgen_world")
		if Time.get_ticks_msec() - started > 120000:
			push_error("no procgen world (pass --procgen --seed=N)")
			quit(1)
			return
	await _wait(2.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)
	root.get_node("DayNight").set("time", 0.42)
	var map: Object = world.get("map")
	var player := get_first_node_in_group("player") as Node3D
	var terrain := get_first_node_in_group("terrain") as Terrain3D
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	var nodes: Array[Node3D] = []
	for n in get_nodes_in_group("gatherable"):
		if n.get("skill") in [&"woodcutting", &"mining"]:  # (the themed ones: not the grain)
			nodes.append(n as Node3D)
	var seen := {}
	var shot := 0
	for site: Dictionary in map.get("sites"):
		var key := "%s_%s" % [site["biome"], site.get("kind", &"")]
		if seen.has(key):
			continue
		seen[key] = true
		var at: Vector2 = site["pos"]
		var best: Node3D = null
		var best_count := 0
		for n in nodes:
			var p := Vector2(n.global_position.x, n.global_position.z)
			if p.distance_to(at) > 70.0 or map.call("biome_at", p) != site["biome"]:
				continue
			var count := 0
			for m in nodes:
				if m.global_position.distance_to(n.global_position) < 14.0:
					count += 1
			if count > best_count:
				best_count = count
				best = n
		if best == null:
			print("TOUR %s: no nodes" % key)
			continue
		var focus := best.global_position + Vector3.UP * 0.8
		player.call("teleport", focus, focus + Vector3.FORWARD)  # (so the world streams in round it)
		cam.global_position = _viewpoint(terrain, focus)
		cam.look_at(focus)
		await _wait(2.5)
		for n in nodes:  # (the parked player's crosshair lights up whatever it's on)
			n.call("set_highlighted", false)
		shot += 1
		var name := "%02d_%s" % [shot, key]
		await _shot("%s/%s.png" % [out, name])
		print("TOUR %s  %d nodes round %s" % [name, best_count, best.name])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://procgen_%d.json" % world_seed))
	quit()


## Where to look at `focus` from: `distance` away at eye height (under the canopies), on the side where the ground is
## lowest and nothing solid stands in the way.
func _viewpoint(terrain: Terrain3D, focus: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_score := INF
	for k in 12:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 12.0)
		var at := focus + dir * distance
		var ground: float = terrain.data.get_height(at)
		var score := ground if not is_nan(ground) else INF
		var eye := Vector3(at.x, ground + EYE, at.z)
		var q := PhysicsRayQueryParameters3D.create(eye, focus)
		var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(focus) > 2.0:
			score += 8.0  # something solid (a trunk, the hillside) in the way
		var near := PhysicsShapeQueryParameters3D.new()
		near.shape = SphereShape3D.new()
		(near.shape as SphereShape3D).radius = 2.5
		near.transform = Transform3D(Basis.IDENTITY, eye)
		for h in root.get_world_3d().direct_space_state.intersect_shape(near, 8):
			if h["collider"] is StaticBody3D and (h["collider"] as Node).get_parent() is SceneryScatter:
				score += 8.0  # inside a tree's crown
		if score < best_score:
			best_score = score
			best = at
	best.y = terrain.data.get_height(best) + EYE
	return best


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		await process_frame


func _shot(path: String) -> void:
	var hidden: Array[CanvasLayer] = []
	for layer in root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
			layer.visible = false
			hidden.append(layer)
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(path)
	for layer in hidden:
		layer.visible = true
