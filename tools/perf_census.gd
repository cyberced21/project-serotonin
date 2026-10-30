extends SceneTree
## Performance census (plans/crumbs.md, phase 7): loads a fresh Hearthvale headless and counts what
## the world is made of, where the frame time can go: nodes, what runs every frame (_process /
## _physics_process, by script), lights and their shadows, meshes drawn with no distance limit,
## the meshes repeated most (candidates for a MultiMesh), particles, and how many of each near a
## few busy spots. No rendering, so no frame times: tools/perf_probe.gd measures those windowed.
##
##   godot --headless --path . -s res://tools/perf_census.gd -- --save-root=user://tmp

const SPOTS := {"village": Vector3(128, 0, 140), "quarry": Vector3(-118, 0, 88), "clearing": Vector3(50, 0, 80)}
const NEAR := 40.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.get_node("Worlds").call("play_fresh")
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 60:
		await process_frame
	var all := root.find_children("*", "", true, false)
	print("nodes: %d" % all.size())

	var processing := {}
	var physics := {}
	var lights := {"omni": 0, "spot": 0, "directional": 0, "shadowed": 0}
	var unlimited := {}
	var meshes := {}
	var particles := 0
	var kinds := {}
	for n in all:
		var key := _key(n)
		kinds[n.get_class()] = kinds.get(n.get_class(), 0) + 1
		if n.is_processing():
			processing[key] = processing.get(key, 0) + 1
		if n.is_physics_processing():
			physics[key] = physics.get(key, 0) + 1
		if n is Light3D:
			lights["omni" if n is OmniLight3D else "spot" if n is SpotLight3D else "directional"] += 1
			if (n as Light3D).shadow_enabled and (n as Light3D).visible:
				lights["shadowed"] += 1
		if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree():
			var g := n as GeometryInstance3D
			if g.visibility_range_end <= 0.0 and not (n is MultiMeshInstance3D):
				var owner_key := _owner(n)
				unlimited[owner_key] = unlimited.get(owner_key, 0) + 1
		if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).is_visible_in_tree():
			var m := (n as MeshInstance3D).mesh
			var name := m.resource_path if not m.resource_path.is_empty() else "%s:%s" % [_key(n.get_parent()), n.name]
			meshes[name] = meshes.get(name, 0) + 1
		if n is GPUParticles3D or n is CPUParticles3D:
			particles += 1
	_top("node classes", kinds, 12)
	_top("_process on (by script/class)", processing, 15)
	_top("_physics_process on", physics, 10)
	print("lights: %s" % lights)
	_top("visible geometry with no draw distance (by scene)", unlimited, 25)
	_top("meshes repeated most (separate MeshInstance3Ds)", meshes, 12)
	print("particle emitters: %d" % particles)

	for spot in SPOTS:
		var at: Vector3 = SPOTS[spot]
		var near := {}
		for n in all:
			if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
				var p := (n as Node3D).global_position
				if Vector2(p.x - at.x, p.z - at.z).length() < NEAR:
					if n is GeometryInstance3D:
						near["geometry"] = near.get("geometry", 0) + 1
					if n is Light3D:
						near["lights"] = near.get("lights", 0) + 1
					if n.is_processing() or n.is_physics_processing():
						near["processing"] = near.get("processing", 0) + 1
		print("within %d m of %s: %s" % [NEAR, spot, near])
	quit()


func _key(n: Node) -> String:
	var s: Script = n.get_script()
	return s.resource_path.get_file() if s and not s.resource_path.is_empty() else n.get_class()


## The scene (or script) the node was instanced from: its nearest ancestor that is one.
func _owner(n: Node) -> String:
	var a := n
	while a and a != root:
		if not a.scene_file_path.is_empty():
			return a.scene_file_path.get_file()
		a = a.get_parent()
	return "%s (built in code under %s)" % [n.get_class(), n.get_parent().name if n.get_parent() else "?"]


func _top(title: String, counts: Dictionary, n: int) -> void:
	var keys := counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return counts[a] > counts[b])
	print("%s:" % title)
	for k in keys.slice(0, n):
		print("  %6d  %s" % [counts[k], k])
