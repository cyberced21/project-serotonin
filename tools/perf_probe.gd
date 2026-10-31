extends SceneTree
## Performance probe (plans/crumbs.md, phase 7): stands at busy spots of a fresh Hearthvale and
## measures the frame there: frame time (mean and 95th percentile), CPU vs GPU time, draw calls,
## and primitives, and physics time. With --experiments, it measures each
## spot again with one suspect switched off at a time, to see what each costs.
##
##   godot --path . --screen 1 --resolution 1920x1080 --audio-driver Dummy -s res://tools/perf_probe.gd -- --save-root=user://tmp
##
## Options (after `--`):
##   --only=a,b       only these spots
##   --experiments    also measure with each suspect off (shadows, fixtures, orchard, far
##                    geometry, critters and animals, SSIL, SSAO, volumetric fog, grass)
##   --try=a,b        only these experiments
##   --seconds=S      how long to measure each (default 3)
## The game is played on a throwaway save. Windowed: ask before running it (the user may be gaming).

## [name, stand at, look at, time of day]
const SPOTS := [
	["village", Vector3(128, 0, 140), Vector3(141, 0, 128), 0.45],
	["village_dusk", Vector3(98, 0, 82), Vector3(126, 0, 104), 0.86],
	["square", Vector3(114, 0, 124), Vector3(70, 0, 94), 0.45],
	["clearing", Vector3(50, 0, 80), Vector3(46, 0, 50), 0.42],
	["quarry", Vector3(-65, 0, 62), Vector3(-118, 0, 88), 0.45],
	["pinewood", Vector3(140.5, 0, -80.5), Vector3(115, 0, -110.5), 0.38],
	["overlook", Vector3(209, 0, 146), Vector3(120, 0, 120), 0.45],
]
const EXPERIMENTS := ["no_shadows", "no_lamp_shadows", "no_sun_shadows", "no_buildings", "no_trees", "no_fixtures", "no_orchard", "no_far", "no_life", "no_ssil", "no_ssao", "no_fog", "no_grass"]

var only: PackedStringArray = []
var experiments := false
var seconds := 3.0
var tries: PackedStringArray = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		elif arg == "--experiments":
			experiments = true
		elif arg.begins_with("--try="):
			tries = arg.trim_prefix("--try=").split(",")
			experiments = true
		elif arg.begins_with("--seconds="):
			seconds = arg.trim_prefix("--seconds=").to_float()
	_run.call_deferred()


func _run() -> void:
	root.get_node("SaveGame").set("path", "user://perf_probe_save.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://perf_probe_save.json"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  # real frame rates
	Engine.max_fps = 0
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null:
		await process_frame
	await _wait(2.0)
	var gfx := root.get_node_or_null("GraphicsSettings")
	if gfx:
		gfx.set("persist", false)  # never write the player's settings.cfg
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var day_night := root.get_node("DayNight")
	day_night.set("frozen", true)
	var p := get_first_node_in_group("player") as Node3D
	print("PROBE %-14s %-12s %7s %7s %7s %7s %6s %7s %9s %6s" % ["spot", "variant", "fps", "ms", "p95", "gpu", "cpu", "draws", "prims", "phys"])
	for s in SPOTS:
		if not only.is_empty() and not only.has(s[0]):
			continue
		day_night.set("time", s[3])
		_go(p, s[1], s[2])
		await _wait(0.5)
		_go(p, s[1], s[2])
		await _wait(3.0)  # (past the biome card, and things settling)
		await _measure(s[0], "base")
		if experiments:
			for e in EXPERIMENTS:
				if not tries.is_empty() and not tries.has(e):
					continue
				var undo := _switch_off(e, p.global_position)
				await _wait(0.5)
				await _measure(s[0], e)
				for u: Callable in undo:
					u.call()
				await _wait(0.3)
	quit()


## Measures `seconds` of frames and prints one line.
func _measure(spot: String, variant: String) -> void:
	var times := PackedFloat32Array()
	var gpu := 0.0
	var cpu := 0.0
	var draws := 0.0
	var prims := 0.0
	var phys := 0.0
	var vp := root.get_viewport_rid()
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(seconds * 1e6):
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var n := float(times.size())
	var sorted := times.duplicate()
	sorted.sort()
	var mean := 0.0
	for t in times:
		mean += t
	mean /= n
	print("PROBE %-14s %-12s %7.1f %7.2f %7.2f %7.2f %6.2f %7d %9d %6.2f" % [spot, variant, 1000.0 / mean, mean,
		sorted[int(n * 0.95)], gpu / n, cpu / n, roundi(draws / n), roundi(prims / n), phys / n])


## Switches a suspect off; returns how to switch it back.
func _switch_off(what: String, at: Vector3) -> Array[Callable]:
	var undo: Array[Callable] = []
	var scene := current_scene
	match what:
		"no_lamp_shadows", "no_sun_shadows":
			for l in root.find_children("*", "Light3D", true, false):
				var light := l as Light3D
				if light.shadow_enabled and ((light is DirectionalLight3D) == (what == "no_sun_shadows")):
					light.shadow_enabled = false
					undo.append(func() -> void: light.shadow_enabled = true)
		"no_buildings", "no_trees":
			for n in root.find_children("*", "Node3D", true, false):
				var sc: Script = n.get_script()
				var path := sc.resource_path if sc else ""
				var hit: bool = path.ends_with("building.gd") if what == "no_buildings" 					else (path.ends_with("resource_node.gd") and n.get("skill") == &"woodcutting")
				if hit:
					undo.append_array(_hide(n))
		"no_shadows":
			for l in root.find_children("*", "Light3D", true, false):
				var light := l as Light3D
				if light.shadow_enabled:
					light.shadow_enabled = false
					undo.append(func() -> void: light.shadow_enabled = true)
		"no_fixtures":
			undo.append_array(_hide(scene.get_node_or_null("Village/Fixtures")))
		"no_orchard":
			undo.append_array(_hide(scene.get_node_or_null("Places/Orchard")))
		"no_life":
			undo.append_array(_hide(scene.get_node_or_null("Life")))
		"no_ssil", "no_ssao", "no_fog", "no_grass":
			var gfx := root.get_node("GraphicsSettings")
			var key: StringName = {"no_ssil": &"ssil", "no_ssao": &"ssao", "no_fog": &"volumetric_fog", "no_grass": &"grass_density"}[what]
			var was: Variant = gfx.call("get_value", key)
			gfx.call("set_value", key, 0.0 if key == &"grass_density" else false)
			undo.append(func() -> void: gfx.call("set_value", key, was))
		"no_far":  # everything drawn with no distance limit, further than 60 m
			for g in root.find_children("*", "GeometryInstance3D", true, false):
				var geo := g as GeometryInstance3D
				if geo.is_visible_in_tree() and geo.visibility_range_end <= 0.0 and not geo is MultiMeshInstance3D \
						and geo.global_position.distance_to(at) > 60.0 and geo.get_aabb().size.length() < 30.0:
					geo.visible = false
					undo.append(func() -> void: geo.visible = true)
	return undo


func _hide(n: Node) -> Array[Callable]:
	if n == null or not n is Node3D or not (n as Node3D).visible:
		return []
	(n as Node3D).visible = false
	return [func() -> void: (n as Node3D).visible = true]


func _wait(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _go(p: Node3D, to: Vector3, look: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(to + Vector3.UP * 120.0, to + Vector3.DOWN * 120.0, 1)
	q.exclude = [(p as CollisionObject3D).get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		to = hit["position"] + Vector3.UP * 0.1
	p.call("teleport", to, look)
