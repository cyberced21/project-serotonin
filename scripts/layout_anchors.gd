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
## An anchor with a `type` (plans/town-designer.md) is a building the town designer added: no node in
## main.tscn, so apply() makes one under Village (a Fixture of the catalog's `buildings` model, named
## by its id, its door a Spots/Door marker), and it's handled like any other from there on.
## Main's scene is Hearthvale's: playing another map (plans/map-maker.md), this first points the
## terrain at that map's land and swaps the baked layout for that map's (use_map()).

## The layout file read: the map's, unless a tool points it at another (use_file()).
static var layout_path := Maps.layout()
static var _anchors: Array = []
static var _loaded := false
static var _catalog := {}
const CATALOG := "res://data/layout/catalog.json"
const FIXTURE := "res://scripts/fixture.gd"


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
		for a in _anchors:  # (an added building's node: made by apply())
			if a.has("type") and not a.has("node"):
				a["node"] = "Village/" + String(a["id"])
	return _anchors


## Where spot `name` is on the green (plans/town-designer.md, phase 7): the green anchor's `spots`
## ({name: [x, z, facing degrees]}) if it has it, else `fallback` ([offset, facing radians]), as
## [offset, facing radians] in the green's frame. (VillageDecor's decorations ask through spot().)
static func green_spot(name: String, fallback: Array) -> Array:
	var s: Variant = find(&"green").get("spots", {}).get(name)
	if s is Array and (s as Array).size() >= 2:
		return [Vector2(float(s[0]), float(s[1])), deg_to_rad(float(s[2])) if (s as Array).size() > 2 else float(fallback[1])]
	return fallback


## The catalog's building type `type` (plans/town-designer.md): {label, model, pad, box, door}, or {}.
static func building_type(type: String) -> Dictionary:
	if _catalog.is_empty():
		var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		_catalog = c if c is Dictionary else {"buildings": {}}
	return _catalog.get("buildings", {}).get(type, {})


## Makes the buildings the town designer added (anchors with a `type`) under main's Village, each
## once: a Fixture of its type's model, shut, its door a Spots/Door marker in its own frame.
static func make_added(main: Node) -> void:
	var village := main.get_node_or_null("Village")
	if village == null:
		return
	for a in anchors():
		if not a.has("type") or village.has_node(String(a["id"])):
			continue
		var t := building_type(String(a["type"]))
		if t.is_empty() or not ResourceLoader.exists(String(t.get("model", ""))):
			push_warning("LayoutAnchors: no building type %s for anchor %s" % [a["type"], a["id"]])
			continue
		var f := (load(FIXTURE) as GDScript).new() as Node3D
		f.name = String(a["id"])
		f.set("model", load(String(t["model"])))
		f.set("doors_open", false)
		f.add_to_group("fixture")  # (now: the walkways look for doors before its _ready)
		f.set_meta(&"display_name", String(a.get("name", t.get("label", a["id"]))))
		var door: Variant = t.get("door")
		if door is Array:
			var spots := Node3D.new()
			spots.name = "Spots"
			f.add_child(spots)
			var m := Marker3D.new()
			m.name = "Door"
			m.position = Vector3(float(door[0]), 0.0, float(door[1]))
			spots.add_child(m)
		village.add_child(f)


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


## Stands anchored node `n`'s children named in its anchor's `spots` ({name: [x, z, facing degrees]},
## the town designer's: the green's benches, lamps, crates, pond and the villagers' spots on it)
## where they say, in `n`'s own frame, keeping their height, tilt and scale. (Names that aren't
## children, the decorations VillageDecor makes, are its to read.)
static func _place_spots(n: Node3D, spots: Variant) -> void:
	if not spots is Dictionary:
		return
	for key in spots:
		var c := n.get_node_or_null(NodePath(String(key))) as Node3D
		var s: Array = spots[key]
		if c == null or s.size() < 2:
			continue
		var t := c.transform
		if s.size() > 2:
			var turn := deg_to_rad(float(s[2])) - atan2(t.basis.z.x, t.basis.z.z)
			t.basis = Basis(Vector3.UP, turn) * t.basis
		t.origin = Vector3(float(s[0]), t.origin.y, float(s[1]))
		c.transform = t


## Moves and turns each anchored node under `main` to its anchor, keeping its height, tilt and
## scale, then stands the areas' own things (apply_areas). An anchor the map hasn't placed
## (`placed: false`, or, on another map than Hearthvale, one it hasn't at all) is kept out.
## Returns how many it placed (a missing node is warned about and skipped).
static func apply(main: Node) -> int:
	make_added(main)
	var placed := 0
	var have := {}
	for a in anchors():
		have[a["id"]] = true
		var n := main.get_node_or_null(NodePath(String(a["node"]))) as Node3D
		if n == null:
			push_warning("LayoutAnchors: no node %s for anchor %s" % [a["node"], a["id"]])
			continue
		if not a.get("placed", true):
			keep_out(n)
			continue
		var t := n.transform
		var turn := deg_to_rad(float(a.get("yaw", 0.0))) - atan2(t.basis.z.x, t.basis.z.z)
		t.basis = Basis(Vector3.UP, turn) * t.basis
		t.origin = Vector3(float(a["at"][0]), t.origin.y, float(a["at"][1]))
		n.transform = t
		_place_spots(n, a.get("spots", {}))
		placed += 1
	if Maps.current() != Maps.DEFAULT:  # (Hearthvale's anchored things this map hasn't got)
		for a in Maps.read_layout(Maps.path("layout", Maps.DEFAULT)).get("anchors", []):
			var n := main.get_node_or_null(NodePath(String(a["node"]))) as Node3D
			if n and not have.has(a["id"]):
				keep_out(n)
	apply_areas(main)
	return placed


## What the map's areas carry in main.tscn (plans/map-maker.md): things built for an area where it
## is in Hearthvale (its home), moved and turned with it. Without the area they're kept out.
const AREA_NODES := {&"clearing": ["Ruins"], &"quarry": ["Quarry/Props"], &"goldmeadow": ["Goldmeadow/Props"]}
const AREA_OUT := {&"clearing": ["Ruins"], &"quarry": ["Quarry"], &"goldmeadow": ["Goldmeadow"]}
## Life's animals, critters and sounds go with the area nearest where they are in Hearthvale (within
## this, m; else the village's: its farmland).
const LIFE_REACH := 160.0


## Moves main's things for each area (AREA_NODES, Life's, the player's first spawn: the village's)
## with it, or keeps them out without it (AREA_OUT); the landslide and the trader need the road east.
## Nothing moves in Hearthvale (its areas are at their homes).
static func apply_areas(main: Node) -> void:
	for type in AREA_OUT:
		if not WorldMap.has_area(type):
			for path in AREA_OUT[type]:
				var n := main.get_node_or_null(NodePath(path))
				if n:
					keep_out(n)
	for type in AREA_NODES:
		if WorldMap.has_area(type):
			for path in AREA_NODES[type]:
				var n := main.get_node_or_null(NodePath(path)) as Node3D
				if n:
					_move(n, area_frame(type))
	if WorldMap.road(&"east_road").is_empty() and Maps.current() != Maps.DEFAULT:
		for path in ["Landslide", "Trader"]:
			var n := main.get_node_or_null(NodePath(path))
			if n:
				keep_out(n)
	for group in ["Life/Animals", "Life/Critters", "Life/Sounds"]:
		var holder := main.get_node_or_null(group)
		for n in (holder.get_children() if holder else []):
			if n is Node3D:
				_carry_life(n as Node3D)
	var player := main.get_node_or_null("Player") as Node3D
	if player and Maps.current() != Maps.DEFAULT:  # (a fresh world starts by the green, or the map's middle)
		if WorldMap.has_area(&"village"):
			_move(player, area_frame(&"village"))
		else:
			var mid := Maps.origin() + Vector2(Maps.size()) / 2.0
			player.position = Vector3(mid.x, 0.1, mid.y)


static func _carry_life(n: Node3D) -> void:
	var p := Vector2(n.position.x, n.position.z)
	var by: StringName = &"village"
	var near := LIFE_REACH
	for type in WorldMap.AREAS:
		var d := p.distance_to(WorldMap.AREAS[type]["home"])
		if type != &"village" and d < near:
			near = d
			by = type
	if not WorldMap.has_area(by):
		keep_out(n)
	else:
		_move(n, area_frame(by))


## Area `type`'s move from its home: a turn by its yaw about its home, then over to where it is.
static func area_frame(type: StringName) -> Transform3D:
	var home: Vector2 = WorldMap.AREAS[type]["home"]
	var at := WorldMap.area_at(type)
	var yaw := WorldMap.area_yaw(type)
	if at == home and yaw == 0.0:
		return Transform3D.IDENTITY
	var turn := Basis(Vector3.UP, yaw)
	var h := Vector3(home.x, 0, home.y)
	return Transform3D(turn, Vector3(at.x, 0, at.y) - turn * h)


## Moves `n` by `frame` once (applying twice changes nothing).
static func _move(n: Node3D, frame: Transform3D) -> void:
	if frame != Transform3D.IDENTITY and not n.has_meta(&"area_moved"):
		n.transform = frame * n.transform
		n.set_meta(&"area_moved", true)


## Keeps `n` out of the game (a building or a place the map hasn't, an area's things without it):
## hidden, not processed, nothing to bump into, well under the world.
static func keep_out(n: Node) -> void:
	if n.has_meta(&"kept_out"):
		return
	n.process_mode = Node.PROCESS_MODE_DISABLED
	if n is Node3D:
		(n as Node3D).visible = false
		(n as Node3D).position.y -= 5000.0
	n.set_meta(&"kept_out", true)
