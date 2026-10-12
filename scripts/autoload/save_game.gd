extends Node
## Saves registered systems to user://save.json. A system calls SaveGame.register(key, self)
## and implements to_dict() -> Dictionary and from_dict(d: Dictionary). Registering applies
## any saved data immediately, so it doesn't matter when a system registers (autoload or scene).
## Saves on quit, when asked (e.g. level-up), and every AUTOSAVE_INTERVAL if something changed.

const PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const VERSION := 1
const AUTOSAVE_INTERVAL := 30.0

var _data: Dictionary = {}                  # key -> last saved/loaded dict
var _systems: Dictionary[String, Object] = {}
var _dirty := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_INTERVAL
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if _dirty:
			save())
	add_child(timer)


func register(key: StringName, system: Object) -> void:
	_systems[String(key)] = system
	if _data.has(String(key)):
		system.from_dict(_data[String(key)])


func mark_dirty() -> void:
	_dirty = true


func save() -> void:
	for key in _systems:
		var system := _systems[key]
		if is_instance_valid(system):
			_data[key] = system.to_dict()  # freed systems keep their last saved data
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: can't write %s (%s)" % [TMP_PATH, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({"version": VERSION, "data": _data}, "\t"))
	f.close()
	# write-then-rename so a crash mid-write can't corrupt the existing save
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	var err := DirAccess.rename_absolute(TMP_PATH, PATH)
	if err != OK:
		push_warning("SaveGame: can't move save into place (%s)" % error_string(err))
		return
	_dirty = false


## Debug: wipe the save, reset every system to defaults and reload the scene.
func reset() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	_data.clear()
	for key in _systems:
		if is_instance_valid(_systems[key]):
			_systems[key].from_dict({})
	_dirty = false
	get_tree().reload_current_scene()


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary and parsed.get("data") is Dictionary):
		push_warning("SaveGame: %s is corrupt, starting fresh" % PATH)
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
