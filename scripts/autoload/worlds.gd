extends Node
## The player's worlds: one folder each under `root` (user://worlds/ unless `--save-root=<dir>`):
##   <id>/world.json   name, kind (classic / generated), seed and settings, generator version,
##                     created, last played, playtime
##   <id>/save.json    what SaveGame writes while the world is played
##   <id>/thumb.png    a screenshot, taken on Save & Quit
## "classic" is the hand-built world (scenes/main.tscn): always there, never deleted, only reset.
## "_scratch" is the throwaway generated world the debug menu and `--procgen` use; never listed.
## Starting up, the old flat saves (user://save.json, user://procgen_<seed>.json) move into folders.
##
## Command line (after `--`), skipping the menu:
##   --classic                  the hand-built world
##   --world=<id>               any world by its folder name
##   --procgen [--seed=N]       the scratch world, a random seed if none is given
##   --save-root=<dir>          keep every world under <dir> instead (tests: never the real saves)

signal list_changed

const DEFAULT_ROOT := "user://worlds"
const CLASSIC := "classic"
const SCRATCH := "_scratch"
const META_VERSION := 1
const CLASSIC_SCENE := "res://scenes/main.tscn"
const PROCGEN_SCENE := "res://scenes/procgen.tscn"
## Where the old flat saves were (save.json, procgen_<seed>.json).
const OLD_SAVES := "user://"

var root := DEFAULT_ROOT
## The world being played ("" in the menu), and its meta.
var current := ""
var current_meta: Dictionary = {}
var _session_start := 0  # ticks (ms) when playtime was last banked


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--save-root="):
			root = arg.trim_prefix("--save-root=")
	DirAccess.make_dir_recursive_absolute(_abs(root))
	if root == DEFAULT_ROOT:
		migrate(OLD_SAVES)
	_ensure_classic()
	SaveGame.saved.connect(_on_saved)
	_start_from_cmdline.call_deferred(args)


# --- queries ----------------------------------------------------------------------------------

## Every listed world's meta (not the scratch world), the most recently played first; classic is
## always among them.
func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in DirAccess.get_directories_at(_abs(root)):
		if id == SCRATCH:
			continue
		var m := meta(id)
		if not m.is_empty():
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


## Whether a generated world was made by an older generator, so its land may have changed.
func outdated(m: Dictionary) -> bool:
	return m.get("kind") == "generated" and int(m.get("generator", 0)) != ProcgenMap.GENERATOR_VERSION


# --- changes ----------------------------------------------------------------------------------

## A new generated world; returns its id. `settings` is a WorldSettings dictionary (seed included).
func create(world_name: String, settings: Dictionary) -> String:
	var id := _new_id()
	DirAccess.make_dir_recursive_absolute(_abs(folder(id)))
	_write_meta(id, _new_meta(world_name, settings))
	list_changed.emit()
	return id


func rename(id: String, world_name: String) -> void:
	var m := meta(id)
	if m.is_empty() or world_name.strip_edges().is_empty():
		return
	m["name"] = world_name.strip_edges()
	_write_meta(id, m)
	if id == current:
		current_meta = m
	list_changed.emit()


## A fresh world with the same seed and settings (not the classic world: there's only one).
func duplicate_world(id: String) -> String:
	var m := meta(id)
	if m.is_empty() or m.get("kind") != "generated":
		return ""
	return create("%s (copy)" % m["name"], m.get("settings", {}))


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
		m["generator"] = ProcgenMap.GENERATOR_VERSION if m.get("kind") == "generated" else 0
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
	var was_outdated := outdated(m) and has_save(id)
	m["last_played"] = Time.get_unix_time_from_system()
	if m.get("kind") == "generated":
		m["generator"] = ProcgenMap.GENERATOR_VERSION  # it's today's land from now on
	_write_meta(id, m)
	SaveGame.use_file(save_path(id))
	_session_start = Time.get_ticks_msec()
	if m.get("kind") == "generated":
		ProcgenWorld.world_name = m.get("name", "")
		ProcgenWorld.settings = m.get("settings", {})
		ProcgenWorld.regenerated = was_outdated
		get_tree().change_scene_to_file(PROCGEN_SCENE)
	else:
		get_tree().change_scene_to_file(CLASSIC_SCENE)


## A new scratch world on seed `s` (the old one wiped), then play it.
func play_scratch(s: int) -> void:
	if current == SCRATCH:
		SaveGame.use_file("")  # let go of its file before it's deleted
		current = ""
	if exists(SCRATCH):
		_remove_tree(_abs(folder(SCRATCH)))
	DirAccess.make_dir_recursive_absolute(_abs(folder(SCRATCH)))
	var settings := WorldSettings.defaults()
	settings["seed"] = s
	_write_meta(SCRATCH, _new_meta("Scratch, seed %d" % s, settings))
	play(SCRATCH)


## Saves, lets go of the world and changes to `scene` (the menu).
func leave(scene: String) -> void:
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


## `-- --classic`, `--world=<id>`, `--procgen [--seed=N]`: straight into a world.
func _start_from_cmdline(args: PackedStringArray) -> void:
	if args.has("--procgen"):
		var s := ProcgenMap.random_seed()
		for arg in args:
			if arg.begins_with("--seed="):
				s = arg.trim_prefix("--seed=").to_int()
		play_scratch(s)
		return
	for arg in args:
		if arg.begins_with("--world="):
			play(arg.trim_prefix("--world="))
			return
	# until there's a menu: booting the classic scene plays the classic world, as before (not under
	# a -s tool script, which has no scene yet and picks its own save)
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path == CLASSIC_SCENE:
		play(CLASSIC)


# --- files ------------------------------------------------------------------------------------

func _new_meta(world_name: String, settings: Dictionary) -> Dictionary:
	var now := Time.get_unix_time_from_system()
	return {
		"version": META_VERSION, "name": world_name, "kind": "generated", "settings": settings,
		"generator": ProcgenMap.GENERATOR_VERSION, "created": now, "last_played": 0.0, "playtime": 0.0,
	}


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
		return
	DirAccess.make_dir_recursive_absolute(_abs(folder(CLASSIC)))
	var now := Time.get_unix_time_from_system()
	_write_meta(CLASSIC, {"version": META_VERSION, "name": "Hearthvale (classic)", "kind": "classic",
			"created": now, "last_played": 0.0, "playtime": 0.0})


## The old flat saves in `from` into folders: save.json becomes the classic world's, and each
## procgen_<seed>.json a world of its own, "Seed <seed>" on default settings.
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
	for file in DirAccess.get_files_at(from):
		if not (file.begins_with("procgen_") and file.ends_with(".json")):
			continue
		var s := file.trim_prefix("procgen_").trim_suffix(".json")
		if not s.is_valid_int():
			continue
		var settings := WorldSettings.defaults()
		settings["seed"] = s.to_int()
		var id := create("Seed %s" % s, settings)
		var old := from.path_join(file)
		var m := meta(id)
		m["last_played"] = FileAccess.get_modified_time(_abs(old))
		_write_meta(id, m)
		DirAccess.rename_absolute(_abs(old), _abs(save_path(id)))
		print("Worlds: moved %s into world %s" % [file, id])


func _new_id() -> String:
	while true:
		var id := "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
		if not DirAccess.dir_exists_absolute(_abs(folder(id))):
			return id
	return ""


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func _remove_tree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
