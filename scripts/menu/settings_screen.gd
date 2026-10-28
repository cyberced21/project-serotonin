class_name SettingsScreen
extends PanelContainer
## Settings, in four tabs, all applied as they change: Graphics (GraphicsSettings: presets and each
## costly effect), Display, Audio and Controls (Settings). Saved to user://settings.cfg.

signal closed

const GFX_CHECKS := {
	&"ssao": "Ambient occlusion: contact shadows in corners",
	&"ssil": "Bounced light",
	&"volumetric_fog": "Volumetric fog and light shafts",
	&"glow": "Bloom round bright things",
	&"fxaa": "FXAA edge smoothing (cheap)",
	&"light_shadows": "Lamps cast shadows",
}
## key: [label, min, max, step, shown as a percentage]
const GFX_SLIDERS := {
	&"shadow_distance": ["Shadow distance", 30.0, 200.0, 10.0, false],
	&"grass_density": ["Grass density", 0.0, 1.0, 0.05, true],
	&"foliage_distance": ["Grass and foliage draw distance", 0.3, 1.0, 0.05, true],
}
const BUS_NAMES := {&"Master": "Master", &"Effects": "Effects", &"Ambience": "Ambience",
		&"Movement": "Footsteps and movement", &"Music": "Music"}

var _tabs: TabContainer
var _refreshers: Array[Callable] = []
var _refreshing := false


func _init() -> void:
	add_theme_stylebox_override("panel", MenuUI.box(MenuUI.BG, 20.0, MenuUI.BORDER))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(MenuUI.title("Settings", 30))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 17)
	_tabs.add_theme_stylebox_override("panel", MenuUI.box(Color(0, 0, 0, 0.2), 14.0, Color.TRANSPARENT, 6))
	box.add_child(_tabs)
	_tabs.add_child(_page("Graphics", _graphics()))
	_tabs.add_child(_page("Display", _display()))
	_tabs.add_child(_page("Audio", _audio()))
	_tabs.add_child(_page("Controls", _controls()))
	var row := HBoxContainer.new()
	row.add_child(MenuUI.button("Reset this tab", _reset_tab, 16))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var back := MenuUI.button("Back", func() -> void: closed.emit(), 16)
	back.custom_minimum_size = Vector2(110, 0)
	row.add_child(back)
	box.add_child(row)


func _ready() -> void:
	GraphicsSettings.changed.connect(refresh)
	Settings.changed.connect(refresh)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()


## Every control back in step with the settings (they can change from the debug menu too).
func refresh() -> void:
	_refreshing = true
	for r in _refreshers:
		r.call()
	_refreshing = false


func _reset_tab() -> void:
	match _tabs.current_tab:
		0:
			GraphicsSettings.apply_preset(GraphicsSettings.DEFAULT_PRESET)
		1:
			Settings.reset_section("display")
		2:
			Settings.reset_section("audio")
		3:
			Settings.reset_section("controls")


# --- tabs -------------------------------------------------------------------------------------

func _graphics() -> Control:
	var box := _column()
	var preset := MenuUI.label("", 17, MenuUI.ACCENT)
	box.add_child(preset)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for p in GraphicsSettings.PRESET_ORDER:
		row.add_child(MenuUI.button(String(p).capitalize(), GraphicsSettings.apply_preset.bind(p), 16))
	box.add_child(row)
	_refreshers.append(func() -> void:
		preset.text = "Preset: %s" % String(GraphicsSettings.preset).capitalize())
	for key in GFX_CHECKS:
		var c := _check(GFX_CHECKS[key], func(on: bool) -> void: GraphicsSettings.set_value(key, on))
		box.add_child(c)
		_refreshers.append(func() -> void: c.set_pressed_no_signal(bool(GraphicsSettings.get_value(key))))
	var msaa := _choice(["Off", "2×", "4×"], func(i: int) -> void:
		GraphicsSettings.set_value(&"msaa", [0, 2, 4][i]))
	box.add_child(_row("Anti-aliasing (MSAA)", msaa))
	_refreshers.append(func() -> void:
		msaa.select(maxi([0, 2, 4].find(int(GraphicsSettings.get_value(&"msaa"))), 0)))
	for key in GFX_SLIDERS:
		var spec: Array = GFX_SLIDERS[key]
		var s := _slider(spec[1], spec[2], spec[3], spec[4], func(v: float) -> void:
			GraphicsSettings.set_value(key, v), true)
		box.add_child(_row(spec[0], s))
		_refreshers.append(func() -> void: _set_slider(s, float(GraphicsSettings.get_value(key))))
	return box


func _display() -> Control:
	var box := _column()
	var mode := _choice(["Windowed", "Borderless", "Fullscreen"], func(i: int) -> void:
		Settings.set_value("display", "window_mode", Settings.WINDOW_MODES[i]))
	box.add_child(_row("Window", mode))
	var res := _choice([], func(i: int) -> void:
		Settings.set_value("display", "resolution", Settings.resolutions()[i]))
	box.add_child(_row("Resolution", res))
	var upscale := _choice(["Bilinear (soft)", "FSR 1.0 (sharper)"], func(i: int) -> void:
		Settings.set_value("display", "upscaling", Settings.UPSCALERS[i]))
	box.add_child(_row("Upscaling", upscale))
	var note := MenuUI.label("", 14, MenuUI.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var vsync := _check("VSync (no tearing; caps the frame rate to the screen)", func(on: bool) -> void:
		Settings.set_value("display", "vsync", on))
	box.add_child(vsync)
	var caps: Array = Settings.FPS_CAPS.map(func(f: int) -> String: return "No cap" if f == 0 else "%d" % f)
	var fps := _choice(caps, func(i: int) -> void: Settings.set_value("display", "max_fps", Settings.FPS_CAPS[i]))
	box.add_child(_row("Frame rate cap", fps))
	_refreshers.append(func() -> void:
		var m: StringName = Settings.get_value("display", "window_mode")
		mode.select(maxi(Settings.WINDOW_MODES.find(m), 0))
		var options := Settings.resolutions()
		res.clear()
		for r in options:
			res.add_item("%d × %d" % [r.x, r.y])
		var current: Vector2i = Settings.get_value("display", "resolution")
		var pick := options.find(current)
		if pick < 0:  # not offered on this screen: the nearest that is
			pick = 0
			for k in options.size():
				if absi(options[k].y - current.y) < absi(options[pick].y - current.y):
					pick = k
		res.select(pick)
		upscale.select(maxi(Settings.UPSCALERS.find(Settings.get_value("display", "upscaling")), 0))
		var scaled := m != &"windowed" and Settings.render_size().y < get_tree().root.size.y if is_inside_tree() else false
		upscale.disabled = not scaled
		if m == &"windowed":
			note.text = "Windowed: the resolution is the window's size."
		else:
			note.text = "The 3D view is drawn at the resolution and scaled up to the screen; menus and text stay sharp. Lower it for more frames."
		vsync.set_pressed_no_signal(bool(Settings.get_value("display", "vsync")))
		fps.select(maxi(Settings.FPS_CAPS.find(int(Settings.get_value("display", "max_fps"))), 0)))
	return box


func _audio() -> Control:
	var box := _column()
	for bus in Settings.BUSES:
		var s := _slider(0.0, 1.0, 0.05, true, func(v: float) -> void:
			Settings.set_value("audio", String(bus), v))
		box.add_child(_row(BUS_NAMES[bus], s))
		_refreshers.append(func() -> void: _set_slider(s, float(Settings.get_value("audio", String(bus)))))
	return box


func _controls() -> Control:
	var box := _column()
	var sens := _slider(0.2, 3.0, 0.05, false, func(v: float) -> void:
		Settings.set_value("controls", "sensitivity", v))
	box.add_child(_row("Mouse sensitivity", sens))
	var invert := _check("Invert mouse Y", func(on: bool) -> void: Settings.set_value("controls", "invert_y", on))
	box.add_child(invert)
	var fov := _slider(60.0, 100.0, 1.0, false, func(v: float) -> void: Settings.set_value("controls", "fov", v))
	box.add_child(_row("Field of view", fov))
	var motion := _slider(0.0, 1.0, 0.05, true, func(v: float) -> void:
		Settings.set_value("controls", "camera_motion", v))
	box.add_child(_row("Camera motion", motion))
	var note := MenuUI.label("How much the camera kicks and shakes on hits, and widens at speed. Lower it if that's too much.", 14, MenuUI.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	_refreshers.append(func() -> void:
		_set_slider(sens, Settings.sensitivity())
		invert.set_pressed_no_signal(Settings.invert_y())
		_set_slider(fov, Settings.fov())
		_set_slider(motion, Settings.camera_motion()))
	return box


# --- widgets ----------------------------------------------------------------------------------

func _page(title: String, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	return box


func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := MenuUI.label(text, 17)
	l.custom_minimum_size = Vector2(250, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _check(text: String, on_toggle: Callable) -> CheckBox:
	var c := MenuUI.check_box(text)
	c.toggled.connect(func(on: bool) -> void:
		if not _refreshing:
			on_toggle.call(on))
	return c


func _choice(items: Array, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 16)
	for it in items:
		o.add_item(it)
	o.item_selected.connect(func(i: int) -> void:
		if not _refreshing:
			on_pick.call(i))
	return o


## A slider with its value beside it. `on_release`: only apply when the drag ends (costly ones).
func _slider(lo: float, hi: float, step: float, percent: bool, on_change: Callable, on_release := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value := MenuUI.label("", 16, MenuUI.ACCENT)
	value.custom_minimum_size = Vector2(56, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var show := func(v: float) -> void:
		value.text = "%d%%" % roundi(v * 100.0) if percent else ("%d" % roundi(v) if step >= 1.0 else "%.2f" % v)
	s.value_changed.connect(func(v: float) -> void:
		show.call(v)
		if not _refreshing and not on_release:
			on_change.call(v))
	if on_release:
		s.drag_ended.connect(func(changed: bool) -> void:
			if changed:
				on_change.call(s.value))
	row.add_child(s)
	row.add_child(value)
	row.set_meta("slider", s)
	return row


func _set_slider(row: HBoxContainer, v: float) -> void:
	(row.get_meta("slider") as HSlider).value = v
