extends Node
## Display, audio and controls settings, saved to user://settings.cfg beside GraphicsSettings'
## section (so they hold across worlds and wipes). Applied live; the player reads the controls
## each frame. The Settings screen (scripts/menu/settings_screen.gd) edits them.
##   display   window mode, resolution, upscaling, VSync, frame cap. The resolution is the
##             window's size when windowed; borderless and fullscreen fill the screen and draw the
##             3D view at the resolution, scaled up (bilinear or FSR), the menus and text staying
##             sharp at the screen's own.
##   audio     volume per bus: Master, Effects, Ambience, Movement, Music (0..1)
##   controls  mouse sensitivity (× the player's own), invert Y, field of view, camera motion
##             (how much of the camera kicks, shakes and speed widening to keep, 0..1)

signal changed

const PATH := GraphicsSettings.PATH
const WINDOW_MODES: Array[StringName] = [&"windowed", &"borderless", &"fullscreen"]
## Resolutions offered (16:9), up to the screen's; the screen's own is always offered too.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900),
		Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160)]
const UPSCALERS: Array[StringName] = [&"bilinear", &"fsr"]
const FPS_CAPS: Array[int] = [0, 30, 60, 120, 144, 240]
const BUSES: Array[StringName] = [&"Master", &"Effects", &"Ambience", &"Movement", &"Music"]
const DEFAULTS := {
	"display": {"window_mode": &"windowed", "resolution": Vector2i(1280, 720), "upscaling": &"fsr",
			"vsync": true, "max_fps": 0},
	"audio": {"Master": 1.0, "Effects": 1.0, "Ambience": 1.0, "Movement": 1.0, "Music": 1.0},
	"controls": {"sensitivity": 1.0, "invert_y": false, "fov": 75.0, "camera_motion": 1.0},
}

## False: changes aren't written to settings.cfg (tools).
var persist := true
var _values := DEFAULTS.duplicate(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_apply_display()
	_apply_audio()
	get_tree().root.size_changed.connect(_apply_render_scale)


func get_value(section: String, key: String) -> Variant:
	return _values[section].get(key, DEFAULTS[section][key])


func set_value(section: String, key: String, value: Variant) -> void:
	_values[section][key] = value
	match section:
		"display":
			_apply_display()
		"audio":
			_apply_audio()
	_save()
	changed.emit()


## Back to the defaults, one section.
func reset_section(section: String) -> void:
	_values[section] = DEFAULTS[section].duplicate(true)
	_apply_display()
	_apply_audio()
	_save()
	changed.emit()


# --- read by the game --------------------------------------------------------------------------

func sensitivity() -> float:
	return float(get_value("controls", "sensitivity"))


func invert_y() -> bool:
	return bool(get_value("controls", "invert_y"))


func fov() -> float:
	return float(get_value("controls", "fov"))


## 0..1: how much of the camera kicks, shakes and speed widening to keep.
func camera_motion() -> float:
	return float(get_value("controls", "camera_motion"))


## The resolutions this screen can show (up to its size, and its own size).
func resolutions() -> Array[Vector2i]:
	var screen := _screen_size()
	var out: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	if not out.has(screen):
		out.append(screen)
	return out


## The 3D view's resolution now: the window's size times the render scale.
func render_size() -> Vector2i:
	var root := get_tree().root
	return Vector2i(Vector2(root.size) * root.scaling_3d_scale)


func _screen_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(1920, 1080)
	return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())


# --- applying ---------------------------------------------------------------------------------

func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Engine.max_fps = int(get_value("display", "max_fps"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_value("display", "vsync")
			else DisplayServer.VSYNC_DISABLED)
	if Engine.is_embedded_in_editor():  # the editor's Game tab owns that window
		_apply_render_scale()
		return
	var mode: StringName = get_value("display", "window_mode")
	match mode:
		&"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		&"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size: Vector2i = get_value("display", "resolution")
			var screen := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen)
			size = size.min(usable.size)
			if DisplayServer.window_get_size() != size:
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
	_apply_render_scale()


## Borderless and fullscreen: the 3D view at the chosen resolution, scaled up to the window.
## Windowed: the window already is that size, so 1:1.
func _apply_render_scale() -> void:
	var root := get_tree().root
	var scale := 1.0
	if get_value("display", "window_mode") != &"windowed" and root.size.y > 0:
		var res: Vector2i = get_value("display", "resolution")
		scale = clampf(float(res.y) / root.size.y, 0.25, 1.0)
	root.scaling_3d_scale = scale
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if get_value("display", "upscaling") == &"fsr" 			and scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR


func _apply_audio() -> void:
	for bus in BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var v := clampf(float(get_value("audio", bus)), 0.0, 1.0)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			var v: Variant = cfg.get_value(section, key, DEFAULTS[section][key])
			if typeof(v) == typeof(DEFAULTS[section][key]) or (v is float and DEFAULTS[section][key] is int):
				_values[section][key] = v


func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # keep the other sections (graphics)
	for section in _values:
		for key in _values[section]:
			cfg.set_value(section, key, _values[section][key])
	cfg.save(PATH)
