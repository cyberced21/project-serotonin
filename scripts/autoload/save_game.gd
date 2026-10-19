extends Node
## Saves registered systems to the file of the world being played (Worlds.play() points `path` at
## it with use_file()). With no world (the menu) `path` is "" and nothing is saved.
## A system calls SaveGame.register(key, self) and implements to_dict() -> Dictionary and from_dict(d: Dictionary). Registering applies
## any saved data immediately, so it doesn't matter when a system registers (autoload or scene).
## Saves on quit, when asked (e.g. level-up), and every AUTOSAVE_INTERVAL if something changed.

signal saved

const VERSION := 1
const AUTOSAVE_INTERVAL := 30.0

## The file being saved to: the current world's save.json, or "" for none.
var path := ""
var _data: Dictionary = {}                  # key -> last saved/loaded dict
var _systems: Dictionary[String, Object] = {}
var _dirty := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if _dirty:
			save())
	add_child(timer)


## `legacy_key`: an older key the same system used to save under; its data moves to `key`.
func register(key: StringName, system: Object, legacy_key: StringName = &"") -> void:
	var k := String(key)
	var old: Object = _systems.get(k)
	if old != system and is_instance_valid(old) and (not old is Node or (old as Node).is_inside_tree()):
		push_warning("SaveGame: '%s' is registered twice; give one of them a different save id" % k)
	_systems[k] = system
	var lk := String(legacy_key)
	if not lk.is_empty() and not _data.has(k) and _data.has(lk):
		_data[k] = _data[lk]
		_data.erase(lk)
		_dirty = true
	if _data.has(k):
		system.from_dict(_data[k])


## Whether the current file has saved data for `key`.
func has(key: StringName) -> bool:
	return _data.has(String(key))


## Saves to the current file, then switches to `new_path` ("" for none): the systems that live on
## (autoloads) take that file's data, or their defaults if it has none. Systems in the current scene
## are let go: call this just before changing scenes.
func use_file(new_path: String) -> void:
	if new_path == path:
		return
	save()
	var scene := get_tree().current_scene
	for key in _systems.keys():
		var system := _systems[key]
		if not is_instance_valid(system) or (scene and system is Node
				and (system == scene or scene.is_ancestor_of(system))):
			_systems.erase(key)
	path = new_path
	_data.clear()
	_load()
	for key in _systems:
		_systems[key].from_dict(_data.get(key, {}))
	_dirty = false


func mark_dirty() -> void:
	_dirty = true


func save() -> void:
	if path.is_empty():
		return
	for key in _systems:
		var system := _systems[key]
		if is_instance_valid(system):
			_data[key] = system.to_dict()  # freed systems keep their last saved data
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: can't write %s (%s)" % [tmp_path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({"version": VERSION, "data": _data}, "\t"))
	f.close()
	# write-then-rename so a crash mid-write can't corrupt the existing save
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_warning("SaveGame: can't move save into place (%s)" % error_string(err))
		return
	_dirty = false
	saved.emit()


## Debug: wipe the save, reset every system to defaults and reload the scene.
func reset() -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_data.clear()
	for key in _systems:
		if is_instance_valid(_systems[key]):
			_systems[key].from_dict({})
	_dirty = false
	get_tree().reload_current_scene()


func _load() -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary and parsed.get("data") is Dictionary):
		push_warning("SaveGame: %s is corrupt, starting fresh" % path)
		return
	if int(parsed.get("version", 0)) > VERSION:
		push_warning("SaveGame: save is from a newer version (%s)" % parsed.get("version"))
	_data = parsed["data"]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("debug_reset_save"):
		reset()
