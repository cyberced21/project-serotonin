extends Node
## Graphics quality: Low / Medium / High presets, or any mix of the single settings below, saved
## to user://settings.cfg (not the game save, so it holds across worlds and wipes).
## Applied to every WorldEnvironment and sun (DirectionalLight3D) as they enter the tree, and to
## the root viewport. The *look* (fog colours, glow strength, grading) lives in
## materials/world_environment.tres and the biome moods; this only turns costly parts on or off.
## Other systems read the values (the grass ring reads grass_density) and listen to `changed`.
## Debug menu: Graphics tab.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "graphics"
const PRESETS := {
	&"low": {
		&"msaa": 0, &"fxaa": true, &"ssao": false, &"ssil": false, &"glow": true,
		&"volumetric_fog": false, &"shadow_distance": 50.0, &"shadow_splits": 2,
		&"shadow_size": 2048, &"soft_shadows": 1, &"grass_density": 0.35, &"foliage_distance": 0.6, &"light_shadows": false,
	},
	&"medium": {
		&"msaa": 2, &"fxaa": false, &"ssao": true, &"ssil": false, &"glow": true,
		&"volumetric_fog": true, &"shadow_distance": 90.0, &"shadow_splits": 4,
		&"shadow_size": 4096, &"soft_shadows": 2, &"grass_density": 0.65, &"foliage_distance": 0.8, &"light_shadows": false,
	},
	&"high": {
		&"msaa": 4, &"fxaa": false, &"ssao": true, &"ssil": true, &"glow": true,
		&"volumetric_fog": true, &"shadow_distance": 140.0, &"shadow_splits": 4,
		&"shadow_size": 4096, &"soft_shadows": 3, &"grass_density": 1.0, &"foliage_distance": 1.0, &"light_shadows": true,
	},
}
const PRESET_ORDER: Array[StringName] = [&"low", &"medium", &"high"]
const DEFAULT_PRESET := &"high"

## &"low", &"medium", &"high", or &"custom" once a single setting is changed.
var preset: StringName = DEFAULT_PRESET
var values: Dictionary = PRESETS[DEFAULT_PRESET].duplicate()
## False: changes aren't written to settings.cfg (tools/graphics_tour.gd).
var persist := true


func _ready() -> void:
	_load()
	get_tree().node_added.connect(_on_node_added)
	_apply_globals()
	for n in get_tree().root.find_children("*", "", true, false):
		_on_node_added(n)


## A setting's current value.
func get_value(key: StringName) -> Variant:
	return values.get(key, PRESETS[DEFAULT_PRESET][key])


func apply_preset(name: StringName) -> void:
	if not PRESETS.has(name):
		push_warning("GraphicsSettings: no preset %s" % name)
		return
	preset = name
	values = PRESETS[name].duplicate()
	_apply_all()


## Changes one setting; the preset becomes &"custom" unless the values still match one.
func set_value(key: StringName, value: Variant) -> void:
	values[key] = value
	preset = &"custom"
	for p in PRESET_ORDER:
		if PRESETS[p] == values:
			preset = p
	_apply_all()


func _apply_all() -> void:
	_apply_globals()
	for n in get_tree().root.find_children("*", "", true, false):
		_apply_to(n)
	_save()
	changed.emit()


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment or n is DirectionalLight3D or n is OmniLight3D:
		_apply_to.call_deferred(n)


func _apply_globals() -> void:
	var vp := get_tree().root
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X,
			8: Viewport.MSAA_8X}.get(int(get_value(&"msaa")), Viewport.MSAA_DISABLED)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if get_value(&"fxaa") else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(int(get_value(&"shadow_size")), true)
	var soft := int(get_value(&"soft_shadows")) as RenderingServer.ShadowQuality
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)


func _apply_to(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n is WorldEnvironment and (n as WorldEnvironment).environment:
		var env := (n as WorldEnvironment).environment
		env.ssao_enabled = get_value(&"ssao")
		env.ssil_enabled = get_value(&"ssil")
		env.glow_enabled = get_value(&"glow")
		env.volumetric_fog_enabled = get_value(&"volumetric_fog")
	elif n is DirectionalLight3D:
		var sun := n as DirectionalLight3D
		sun.directional_shadow_max_distance = get_value(&"shadow_distance")
		sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
				if int(get_value(&"shadow_splits")) >= 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
		sun.directional_shadow_blend_splits = int(get_value(&"shadow_splits")) >= 4
	elif n is OmniLight3D and n.is_in_group("night_light"):  # lamps and lanterns
		(n as OmniLight3D).shadow_enabled = get_value(&"light_shadows")


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var p := StringName(cfg.get_value(SECTION, "preset", String(DEFAULT_PRESET)))
	values = PRESETS[p if PRESETS.has(p) else DEFAULT_PRESET].duplicate()
	for key in values.keys():
		values[key] = cfg.get_value(SECTION, String(key), values[key])
	preset = p
	if p == &"custom" or not PRESETS.has(p):
		preset = &"custom"
		for name in PRESET_ORDER:
			if PRESETS[name] == values:
				preset = name


func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "preset", String(preset))
	for key in values:
		cfg.set_value(SECTION, String(key), values[key])
	cfg.save(PATH)
