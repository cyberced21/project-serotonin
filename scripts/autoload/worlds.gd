extends Node
## The player's worlds: one folder each under `root` (user://worlds/ unless `--save-root=<dir>`):
##   <id>/world.json   name, kind, created, last played, playtime
##   <id>/save.json    what SaveGame writes while the world is played
##   <id>/thumb.png    a screenshot, taken on Save & Quit
## "classic" is Hearthvale (scenes/main.tscn), the one world: always there, never deleted, only
## reset. Generated worlds are gone (plans/world.md); starting up deletes their old folders.
## Starting up, the old flat save (user://save.json) moves into the classic world's folder.
##
## Command line (after `--`), skipping the menu:
##   --classic                  Hearthvale
##   --world=<id>               any world by its folder name
##   --save-root=<dir>          keep every world under <dir> instead (tests: never the real saves)
## A `-s` tool script without --save-root gets TOOLS_ROOT, so it can never touch (or migrate) the
## player's worlds by accident.

signal list_changed

const DEFAULT_ROOT := "user://worlds"
const TOOLS_ROOT := "user://tool_worlds"
const CLASSIC := "classic"
const META_VERSION := 1
const CLASSIC_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
## Where the old flat save was (save.json).
const OLD_SAVES := "user://"

var root := DEFAULT_ROOT
## The world being played ("" in the menu), and its meta.
var current := ""
var current_meta: Dictionary = {}
## True when the command line names a world: the menu skips its backdrop (it'd be gone next frame).
var skip_menu := false
var _session_start := 0  # ticks (ms) when playtime was last banked


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var engine_args := OS.get_cmdline_args()
	if engine_args.has("-s") or engine_args.has("--script"):
		root = TOOLS_ROOT
	for arg in args:
		if arg.begins_with("--save-root="):
			root = arg.trim_prefix("--save-root=")
	DirAccess.make_dir_recursive_absolute(_abs(root))
	if root == DEFAULT_ROOT:
		migrate(OLD_SAVES)
	_ensure_classic()
	_remove_generated()
	SaveGame.saved.connect(_on_saved)
	for arg in args:
		if arg == "--classic" or arg.begins_with("--world="):
			skip_menu = true
	_start_from_cmdline.call_deferred(args)


# --- queries ----------------------------------------------------------------------------------

## Every world's meta, the most recently played first; classic is always among them.
func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in DirAccess.get_directories_at(_abs(root)):
		var m := meta(id)
		if not m.is_empty() and m.get("kind") != "generated":  # (in case one's left mid-startup)
			out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("last_played", 0)) > float(b.get("last_played", 0)))
	return out


## The world most recently played, or "" if none ever was (a first launch).
func last_played() -> String:
	for m in list():
		if float(m.get("last_played", 0)) > 0.0:
			return m["id"]
	return ""


func meta(id: String) -> Dictionary:
	var path := folder(id).path_join("world.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("Worlds: %s is corrupt" % path)
		return {}
	var m: Dictionary = parsed
	m["id"] = id  # the folder is the truth, whatever the file says
	return m


func exists(id: String) -> bool:
	return FileAccess.file_exists(folder(id).path_join("world.json"))


func folder(id: String) -> String:
	return root.path_join(id)


func save_path(id: String) -> String:
	return folder(id).path_join("save.json")


func thumb_path(id: String) -> String:
	return folder(id).path_join("thumb.png")


func has_save(id: String) -> bool:
	return FileAccess.file_exists(save_path(id))


# --- changes ----------------------------------------------------------------------------------

func rename(id: String, world_name: String) -> void:
	var m := meta(id)
	if m.is_empty() or world_name.strip_edges().is_empty():
		return
	m["name"] = world_name.strip_edges()
	_write_meta(id, m)
	if id == current:
		current_meta = m
	list_changed.emit()


func delete(id: String) -> void:
	if id == CLASSIC or id == current or not exists(id):
		return
	_remove_tree(_abs(folder(id)))
	list_changed.emit()


## Wipes a world's progress (its save and picture), keeping its name and settings.
func reset(id: String) -> void:
	if id == current:
		return
	for path in [save_path(id), thumb_path(id)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(_abs(path))
	var m := meta(id)
	if not m.is_empty():
		m["playtime"] = 0.0
		m["last_played"] = 0.0
		_write_meta(id, m)
	list_changed.emit()


# --- playing ----------------------------------------------------------------------------------

## Loads world `id`: switches SaveGame to its file and changes to its scene.
func play(id: String) -> void:
	var m := meta(id)
	if m.is_empty():
		push_warning("Worlds: no world '%s'" % id)
		return
	_bank_playtime()
	get_tree().paused = false
	Engine.time_scale = 1.0
	current = id
	current_meta = m
	m["last_played"] = Time.get_unix_time_from_system()
	_write_meta(id, m)
	SaveGame.use_file(save_path(id))
	_session_start = Time.get_ticks_msec()
	get_tree().change_scene_to_file(CLASSIC_SCENE)


## Hearthvale from the start (its save wiped), then play it: for tools and benches, which run
## under their own root (TOOLS_ROOT or --save-root), never the player's worlds.
func play_fresh() -> void:
	if current == CLASSIC:
		SaveGame.use_file("")  # let go of its file before it's wiped
		current = ""
	reset(CLASSIC)
	play(CLASSIC)


## Saves, lets go of the world and changes to `scene` (the main menu by default).
func leave(scene := MENU_SCENE) -> void:
	if current.is_empty():
		get_tree().change_scene_to_file(scene)
		return
	SaveGame.save()
	_bank_playtime()
	SaveGame.use_file("")
	current = ""
	current_meta = {}
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(scene)


## The current world's meta gets the playtime since it was last banked.
func _bank_playtime() -> void:
	if current.is_empty() or not exists(current):
		return
	var now := Time.get_ticks_msec()
	var m := meta(current)
	m["playtime"] = float(m.get("playtime", 0.0)) + (now - _session_start) / 1000.0
	m["last_played"] = Time.get_unix_time_from_system()
	_session_start = now
	_write_meta(current, m)
	current_meta = m


func _on_saved() -> void:
	_bank_playtime()


## `-- --classic`, `--world=<id>`: straight into a world.
func _start_from_cmdline(args: PackedStringArray) -> void:
	for arg in args:
		if arg.begins_with("--world="):
			play(arg.trim_prefix("--world="))
			return
	if args.has("--classic"):
		play(CLASSIC)


# --- files ------------------------------------------------------------------------------------

func _write_meta(id: String, m: Dictionary) -> void:
	var data := m.duplicate()
	data.erase("id")
	var f := FileAccess.open(folder(id).path_join("world.json"), FileAccess.WRITE)
	if f == null:
		push_warning("Worlds: can't write %s's meta (%s)" % [id, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "\t"))


func _ensure_classic() -> void:
	if exists(CLASSIC):
		var m := meta(CLASSIC)
		if m.get("name") == "Hearthvale (classic)":  # from when there were generated worlds too
			m["name"] = "Hearthvale"
			_write_meta(CLASSIC, m)
		return
	DirAccess.make_dir_recursive_absolute(_abs(folder(CLASSIC)))
	var now := Time.get_unix_time_from_system()
	_write_meta(CLASSIC, {"version": META_VERSION, "name": "Hearthvale", "kind": "classic",
			"created": now, "last_played": 0.0, "playtime": 0.0})


## Deletes the worlds made by the old generator: only Hearthvale is played now.
func _remove_generated() -> void:
	for id in DirAccess.get_directories_at(_abs(root)):
		if meta(id).get("kind") == "generated" and id != current:
			_remove_tree(_abs(folder(id)))
			print("Worlds: deleted the generated world %s" % id)


## The old flat save in `from` (save.json) becomes the classic world's.
func migrate(from: String) -> void:
	var old_main := from.path_join("save.json")
	if FileAccess.file_exists(old_main) and not has_save(CLASSIC):
		_ensure_classic()
		var err := DirAccess.rename_absolute(_abs(old_main), _abs(save_path(CLASSIC)))
		if err == OK:
			var m := meta(CLASSIC)
			m["last_played"] = FileAccess.get_modified_time(_abs(save_path(CLASSIC)))
			_write_meta(CLASSIC, m)
			print("Worlds: moved the old save into the classic world")
		else:
			push_warning("Worlds: can't move the old save (%s)" % error_string(err))


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func _remove_tree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
