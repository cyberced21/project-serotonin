class_name Maps
extends RefCounted
## The maps (plans/map-maker.md): data/maps.json lists them and names the one the game plays
## (`active`). Each map is a layout the map editor draws and the files made from it: its terrain,
## its baked layout scene, its roads as laid, and what the editor reads back. Hearthvale keeps the
## paths it always had; a new map's files are under data/maps/<id>/ (the editor's pictures of it
## under tools/map_editor/maps/<id>/, which Godot doesn't import).
## A tool run with `-- --map=<id>` works on that map instead of the active one, and so does
## everything it reads through here (LayoutAnchors, LayoutWater, WorldMap...).

const REGISTRY := "res://data/maps.json"
const DEFAULT := &"hearthvale"
## Hearthvale's files, where they were before there were other maps.
const HEARTHVALE := {
	"layout": "res://data/layout/hearthvale.json",
	"baked": "res://data/layout/baked.json",
	"applied": "res://data/layout/terrain_applied.json",
	"scene": "res://scenes/layout.tscn",
	"terrain": "res://terrain_data",
	"roads": "res://scripts/world_roads.gd",
	"editor": "res://tools/map_editor/",
}

static var _registry: Dictionary = {}
static var _current: StringName = &""


## The map being played or worked on: `--map=<id>` on the command line, else the registry's active one.
static func current() -> StringName:
	if _current == &"":
		_current = active()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--map="):
				_current = StringName(arg.trim_prefix("--map="))
	return _current


## Works on map `id` from now on (a tool or a test).
static func use(id: StringName) -> void:
	_current = id


## The map the game plays (data/maps.json's `active`).
static func active() -> StringName:
	return StringName(registry().get("active", DEFAULT))


## data/maps.json (read once): {active, maps: [{id, name}]}.
static func registry() -> Dictionary:
	if _registry.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY)) if FileAccess.file_exists(REGISTRY) else null
		_registry = d if d is Dictionary else {"active": String(DEFAULT), "maps": [{"id": String(DEFAULT), "name": "Hearthvale"}]}
	return _registry


## Every map's id.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for m in registry().get("maps", []):
		out.append(StringName(m["id"]))
	return out


## Map `id`'s file `what` (layout, baked, applied, scene, terrain, roads, editor).
static func path(what: String, id: StringName = &"") -> String:
	if id == &"":
		id = current()
	if id == DEFAULT:
		return HEARTHVALE[what]
	var dir := "res://data/maps/%s/" % id
	match what:
		"layout": return dir + "layout.json"
		"baked": return dir + "baked.json"
		"applied": return dir + "terrain_applied.json"
		"scene": return dir + "layout.tscn"
		"terrain": return dir + "terrain"
		"roads": return dir + "roads.gd"
		"editor": return "res://tools/map_editor/maps/%s/" % id
	return ""


## The current map's layout file.
static func layout() -> String:
	return path("layout")


## The current map's layout, parsed ({} if it can't be read).
static func read_layout(file: String = "") -> Dictionary:
	if file == "":
		file = layout()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(file)) if FileAccess.file_exists(file) else null
	return d if d is Dictionary else {}
