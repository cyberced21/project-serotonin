extends SceneTree
## Loads every SoundLayers stack under audio/ and checks each layer's stream loads and isn't
## empty, so a renamed clip or a typo in a .tres shows up without playing:
##     godot --headless --path . -s res://tools/check_sound_stacks.gd

var _bad := 0
var _stacks := 0

func _init() -> void:
	_walk("res://audio")
	print("%d stacks checked, %d problems" % [_stacks, _bad])
	quit(1 if _bad else 0)

func _walk(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		var res := load(dir.path_join(file))
		if res == null:
			_bad += 1
			printerr("%s: doesn't load" % dir.path_join(file))
		elif res is SoundLayers:
			_stacks += 1
			for layer in (res as SoundLayers).layers:
				if layer == null or layer.stream == null:
					_bad += 1
					printerr("%s: a layer has no stream" % dir.path_join(file))
				elif layer.stream is AudioStreamRandomizer:
					var r := layer.stream as AudioStreamRandomizer
					for i in r.streams_count:
						if r.get_stream(i) == null:
							_bad += 1
							printerr("%s: %s clip %d missing" % [dir.path_join(file), layer.resource_name, i])
