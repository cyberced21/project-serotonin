extends SceneTree
## Checks the sky's look loads and the scripts that use it compile (headless):
##   godot --headless --path . -s res://tools/test_sky_look.gd -- --save-root=user://tool_worlds


func _initialize() -> void:
	var fails := 0
	for path in ["res://scripts/sky_look.gd", "res://scripts/day_night_sky.gd", "res://scripts/autoload/debug_menu.gd", "res://scripts/autoload/day_night.gd", "res://scripts/water_body.gd"]:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			print("FAIL compile ", path)
			fails += 1
	var look := SkyLook.active()
	var numbers := 0
	var colours := 0
	for prop in look.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_EDITOR:
			if prop.type == TYPE_FLOAT:
				numbers += 1
				if (prop.hint_string as String).split(",").size() < 3:
					print("FAIL no range on ", prop.name)
					fails += 1
			elif prop.type == TYPE_COLOR:
				colours += 1
	print("sky look: %d numbers, %d colours" % [numbers, colours])
	print("PASS" if fails == 0 else "FAILED %d" % fails)
	quit(fails)
