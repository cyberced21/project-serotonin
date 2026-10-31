extends SceneTree
## Dumps the village from above, as JSON: every building's pieces per tier (flat boxes), the
## villagers' spots, props, decorations (all projects done), path lamps, trees and rocks near the
## square, the roads, and (if there is one) the walking graph. tools/plot_village.py draws it.
##   godot --headless --path . -s res://tools/village_layout.gd -- --save-root=user://tool_worlds --out=<file.json>
## (No game class names: an -s script compiles before the autoloads exist.)

const CENTER := Vector2(100, 40)
const RADIUS := 48.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://village_layout.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	root.get_node("Worlds").call("play_fresh")
	await process_frame
	while get_first_node_in_group("player") == null:
		await process_frame
	for i in 5:
		await process_frame
	var projects := root.get_node("Projects")
	for p in projects.call("all"):
		projects.call("set_done", p["id"], true)
	for i in 5:
		await process_frame

	var d := {"buildings": [], "spots": [], "boxes": [], "roads": {}, "graph": {}}
	for b in get_nodes_in_group("building"):
		var e := {"id": String(b.get("def").get("id")), "at": _xz(b.global_position), "tiers": {}}
		for t in range(0, 4):
			var tier := b.get_node_or_null("Tier%d" % t) as Node3D
			if tier:
				e["tiers"][str(t)] = _boxes(tier)
		d["buildings"].append(e)
		var spots := b.get_node_or_null("Spots")
		if spots:
			for m in spots.get_children():
				d["spots"].append({"b": e["id"], "name": String(m.name), "at": _xz(m.global_position),
					"face": _xz(m.global_basis.z)})
	var main := current_scene
	for path in ["Village/Props", "Village/Green", "Village/Decor", "PathLamps", "Trader", "DogHome"]:
		var n := main.get_node_or_null(path) as Node3D
		if n:
			for box in _boxes(n):
				box["tag"] = path
				d["boxes"].append(box)
	var nodes := main.get_node_or_null("Nodes")
	if nodes:
		for n in nodes.get_children():
			if n is Node3D and _near((n as Node3D).global_position):
				d["boxes"].append({"tag": "node", "at": _xz((n as Node3D).global_position), "name": String(n.name)})
	var roads: Dictionary = load("res://scripts/world_roads.gd").LINES
	for k in roads:
		var pts := []
		for p: Vector2 in roads[k]:
			if p.distance_to(CENTER) < RADIUS + 10.0:
				pts.append([p.x, p.y])
		if not pts.is_empty():
			d["roads"][String(k)] = pts
	var graph := get_first_node_in_group("village_paths")
	if graph:
		d["graph"] = graph.call("dump")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	print("village_layout: wrote %s" % ProjectSettings.globalize_path(out))
	quit(0)


func _near(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(CENTER) < RADIUS


func _xz(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.z, 0.01)]


## Flat boxes (x0, z0, x1, z1, top) of every mesh under `n` near the square.
func _boxes(n: Node) -> Array:
	var out := []
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not _near(mi.global_position):
			continue
		var box := mi.global_transform * mi.get_aabb()
		out.append({"r": [snappedf(box.position.x, 0.01), snappedf(box.position.z, 0.01),
			snappedf(box.end.x, 0.01), snappedf(box.end.z, 0.01)], "top": snappedf(box.end.y, 0.01),
			"name": String(mi.name)})
	return out
