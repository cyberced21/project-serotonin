class_name LayoutAnchors
extends Node
## Stands the village's buildings, its fixtures and the places where the map editor put them
## (plans/map-editor-places.md): the map's layout's "anchors" (Maps.layout()), one per thing, each
## {id, node, at: [x, z], yaw} (`node` a path from Main, `yaw` in degrees). The first child of Main:
## it moves them in _enter_tree, before anything under them is ready, so every script sees where
## they stand. Height is left alone (things settle onto the ground themselves). Scripts that build
## main.tscn without adding it to the tree (the terrain generator) call apply() themselves.
## Anchored nodes' parents (Village, Village/Fixtures, Places) stand unturned at the origin, so
## `at` is both their place in the parent and on the map.
## Main's scene is Hearthvale's: playing another map (plans/map-maker.md), this first points the
## terrain at that map's land and swaps the baked layout for that map's (use_map()).

## The layout file read: the map's, unless a tool points it at another (use_file()).
static var layout_path := Maps.layout()
static var _anchors: Array = []
static var _loaded := false


func _enter_tree() -> void:
	use_map(get_parent())
	apply(get_parent())


## Puts the current map (Maps.current()) under `main` in place of Hearthvale: its terrain and its
## baked layout (main's Layout node keeps its name, its children the map's). Nothing for Hearthvale.
## (Main is still entering the tree: its children aren't, so they can be changed.)
static func use_map(main: Node) -> void:
	if Maps.current() == Maps.DEFAULT:
		return
	var terrain := main.get_node_or_null("Terrain3D")
	if terrain != null:
		terrain.set("data_directory", Maps.path("terrain"))
	var holder := main.get_node_or_null("Layout")
	if holder == null:
		return
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()
	var scene_path := Maps.path("scene")
	if not ResourceLoader.exists(scene_path):
		push_warning("LayoutAnchors: map %s isn't baked yet (no %s)" % [Maps.current(), scene_path])
		return
	var baked := (load(scene_path) as PackedScene).instantiate()
	for child in baked.get_children():
		baked.remove_child(child)
		holder.add_child(child)
	baked.free()


## Reads the anchors from `path` instead (the terrain generator's --layout, for a test).
static func use_file(path: String) -> void:
	layout_path = path
	_loaded = false
	_anchors = []


## The layout's anchors (read once).
static func anchors() -> Array:
	if not _loaded:
		_loaded = true
		var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path)) if FileAccess.file_exists(layout_path) else null
		if layout is Dictionary:
			_anchors = layout.get("anchors", [])
	return _anchors


## The anchor `id`, or {} if there's none.
static func find(id: StringName) -> Dictionary:
	for a in anchors():
		if StringName(a["id"]) == id:
			return a
	return {}


## Where anchor `id` stands on the map, or `fallback` without one.
static func at(id: StringName, fallback: Vector2) -> Vector2:
	var a := find(id)
	return Vector2(float(a["at"][0]), float(a["at"][1])) if not a.is_empty() else fallback


## Anchor `id`'s turn about the vertical (radians), or 0.
static func yaw(id: StringName) -> float:
	var a := find(id)
	return deg_to_rad(float(a.get("yaw", 0.0))) if not a.is_empty() else 0.0


## Moves and turns each anchored node under `main` to its anchor, keeping its height, tilt and
## scale. Returns how many it placed (a missing node is warned about and skipped).
static func apply(main: Node) -> int:
	var placed := 0
	for a in anchors():
		var n := main.get_node_or_null(NodePath(String(a["node"]))) as Node3D
		if n == null:
			push_warning("LayoutAnchors: no node %s for anchor %s" % [a["node"], a["id"]])
			continue
		var t := n.transform
		var turn := deg_to_rad(float(a.get("yaw", 0.0))) - atan2(t.basis.z.x, t.basis.z.z)
		t.basis = Basis(Vector3.UP, turn) * t.basis
		t.origin = Vector3(float(a["at"][0]), t.origin.y, float(a["at"][1]))
		n.transform = t
		placed += 1
	return placed
