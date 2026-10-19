extends SceneTree
## Writes a top-down picture of generated worlds without opening the game:
##   godot --headless --path . -s res://tools/procgen_preview.gd -- --seed=42 [--seed=7 ...] [--out=dir]
## One PNG per seed, <out>/procgen_<seed>.png (default out: the project folder). Prints how long
## each took to generate.


func _initialize() -> void:
	var seeds: Array[int] = []
	var out := "."
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seeds.append(arg.trim_prefix("--seed=").to_int())
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if seeds.is_empty():
		seeds.append(1)
	for s in seeds:
		var started := Time.get_ticks_msec()
		var map := ProcgenMap.new(s)
		map.generate()
		var ms := Time.get_ticks_msec() - started
		var path := out.path_join("procgen_%d.png" % s)
		var err := map.write_preview(path)
		var kinds: PackedStringArray = []
		for b in map.kinds:
			kinds.append(map.kind_name(b))
		var marks: PackedStringArray = []
		for l in map.landmarks:
			marks.append(l["name"])
		print("seed %d: %d ms, %d trails, %d waters, %d rivers, %s; %s; %s %s" % [s, ms, map.trails.size(), map.waters.size(), map.rivers.size(), ", ".join(marks),
				", ".join(kinds), path,
				"" if err == OK else error_string(err)])
	quit()
