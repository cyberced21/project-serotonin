class_name NewWorldScreen
extends PanelContainer
## Making a world: its name, seed (typed or rerolled), size, resources, water, terrain and a kind
## per biome (or Random), with a map of it on the right that redraws a moment after anything
## changes. The map comes from the same generator at PREVIEW_PIXELS across, on a worker thread:
## the layout is exact, the detail coarser. Create, or Create and play.

signal closed
signal created(id: String, play: bool)

## Pixels across the preview map, whatever the world's size.
const PREVIEW_PIXELS := 128
## Seconds after the last change before the map redraws.
const PREVIEW_DELAY := 0.35
const BIOMES: Array[StringName] = [&"clearing", &"hearthvale", &"pinewood", &"goldmeadow", &"stillwater",
		&"quarry", &"frostpeak"]
const ADJECTIVES := ["Mossy", "Amber", "Quiet", "Windy", "Golden", "Misty", "Old", "Green", "Silver",
		"Hidden", "Sunny", "Far", "Low", "High", "Red", "Still", "Bright", "Cold"]
const NOUNS := ["Hollow", "Vale", "Reach", "Downs", "Glen", "Fells", "Meadows", "Brook", "Heath",
		"Moor", "Dale", "Ridge", "Weald", "Marches", "Combe", "Hills"]

var _name: LineEdit
var _seed: LineEdit
var _choices: Dictionary[String, Dictionary] = {}  # setting -> {value: Button}
var _values := {"size": &"normal", "resources": &"normal", "water": &"normal", "terrain": &"normal"}
var _kind_pickers: Dictionary[StringName, OptionButton] = {}
var _map: TextureRect
var _map_note: Label
var _about: Label
var _thread: Thread
var _dirty := false
var _wait := 0.0


func _init() -> void:
	add_theme_stylebox_override("panel", MenuUI.box(MenuUI.BG, 22.0, MenuUI.BORDER))
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	outer.add_child(MenuUI.title("New World", 30))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 10)
	scroll.add_child(form)

	_name = MenuUI.line_edit("World name")
	form.add_child(_row("Name", _name))
	var seed_row := HBoxContainer.new()
	_seed = MenuUI.line_edit("Seed")
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.text_changed.connect(func(_t: String) -> void: _changed())
	seed_row.add_child(_seed)
	seed_row.add_child(MenuUI.button("Reroll", _reroll, 16))
	form.add_child(_row("Seed", seed_row))
	form.add_child(_row("Size", _choice("size", WorldSettings.SIZES, ["Small", "Normal", "Large"])))
	form.add_child(_row("Resources", _choice("resources", WorldSettings.RESOURCES, ["Lean", "Normal", "Rich"])))
	form.add_child(_row("Water", _choice("water", WorldSettings.WATER, ["Dry", "Normal", "Wet"])))
	form.add_child(_row("Terrain", _choice("terrain", WorldSettings.TERRAIN, ["Gentle", "Normal", "Rugged"])))
	form.add_child(MenuUI.spacer(4))
	form.add_child(MenuUI.label("Biomes", 18, MenuUI.ACCENT))
	for biome in BIOMES:
		var o := OptionButton.new()
		o.add_theme_font_size_override("font_size", 16)
		o.add_item("Random")
		for k in ProcgenMap.KINDS[biome]:
			o.add_item(k[1])
		o.item_selected.connect(func(_i: int) -> void: _changed())
		_kind_pickers[biome] = o
		form.add_child(_row(String(Biome.MOODS[biome].display_name).trim_prefix("The "), o))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuUI.box(Color(0, 0, 0, 0.35), 4.0, MenuUI.BORDER, 6))
	right.add_child(frame)
	_map = TextureRect.new()
	_map.custom_minimum_size = Vector2(280, 280)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.add_child(_map)
	_map_note = MenuUI.label("", 13, MenuUI.DIM)
	_map_note.custom_minimum_size = Vector2(300, 0)
	_map_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_map_note)
	_about = MenuUI.label("", 13)
	_about.custom_minimum_size = Vector2(300, 0)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_about)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var play := MenuUI.button("Create and play", _create.bind(true), 18)
	play.custom_minimum_size = Vector2(190, 0)
	buttons.add_child(play)
	buttons.add_child(MenuUI.button("Create", _create.bind(false), 18))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	buttons.add_child(MenuUI.button("Cancel", func() -> void: closed.emit(), 16))
	outer.add_child(buttons)


## A fresh form: a made-up name, a random seed, everything normal and Random.
func reset() -> void:
	_name.text = "%s %s" % [ADJECTIVES.pick_random(), NOUNS.pick_random()]
	_seed.text = str(ProcgenMap.random_seed())
	for key in _values:
		_set_choice(key, &"normal")
	for biome in _kind_pickers:
		_kind_pickers[biome].select(0)
	_changed()


func settings() -> Dictionary:
	var text := _seed.text.strip_edges()
	var s := WorldSettings.defaults()
	# a typed word works as a seed too
	s["seed"] = text.to_int() if text.is_valid_int() else (hash(text) & 0x7fffffff if text != "" else 1)
	for key in _values:
		s[key] = _values[key]
	var kinds := {}
	for biome in _kind_pickers:
		var i := _kind_pickers[biome].selected
		if i > 0:
			kinds[biome] = ProcgenMap.KINDS[biome][i - 1][0]
	s["kinds"] = kinds
	return WorldSettings.normalized(s)


func _process(delta: float) -> void:
	if not visible:
		return
	if _thread and not _thread.is_alive():
		var map: ProcgenMap = _thread.wait_to_finish()
		_thread = null
		_show_map(map)
	if _dirty:
		_wait -= delta
		if _wait <= 0.0 and _thread == null:
			_dirty = false
			_start_preview()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		closed.emit()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _thread:
		_thread.wait_to_finish()


func _changed() -> void:
	_dirty = true
	_wait = PREVIEW_DELAY
	_map_note.text = "Drawing the map…"


func _start_preview() -> void:
	var s := settings()
	var mpp := float(WorldSettings.SIZE_METRES[s["size"]]) / PREVIEW_PIXELS
	_thread = Thread.new()
	_thread.start(func() -> ProcgenMap:
		var map := ProcgenMap.new(s["seed"], s, mpp)
		map.generate()
		return map)


func _show_map(map: ProcgenMap) -> void:
	_map.texture = ImageTexture.create_from_image(map.preview_image())
	if _dirty:
		return  # something changed meanwhile: another map is on its way
	_map_note.text = "%d × %d m. Crosses: biomes; squares: ruins, camps and rare spots." % [map.metres, map.metres]
	var lines := PackedStringArray()
	for biome in BIOMES:
		if not map.kinds.has(biome):
			continue
		var picked := _kind_pickers[biome].selected > 0
		lines.append("%s: %s%s" % [String(Biome.MOODS[biome].display_name).trim_prefix("The "), map.kind_name(biome),
				"" if picked else " (rolled)"])
	_about.text = "\n".join(lines) + "\nRich in %s, lean on %s" % [Items.display_name(map.rich), Items.display_name(map.lean)]


func _reroll() -> void:
	_seed.text = str(ProcgenMap.random_seed())
	_changed()


func _create(play: bool) -> void:
	var world_name := _name.text.strip_edges()
	if world_name.is_empty():
		world_name = "World %d" % settings()["seed"]
	created.emit(Worlds.create(world_name, settings()), play)


# --- widgets ----------------------------------------------------------------------------------

func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := MenuUI.label(text, 17)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


## Three buttons, one lit: a setting's choices.
func _choice(key: String, values: Array[StringName], labels: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_choices[key] = {}
	for k in values.size():
		var v := values[k]
		var b := MenuUI.button(labels[k], func() -> void:
			_set_choice(key, v)
			_changed(), 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_choices[key][v] = b
		row.add_child(b)
	return row


func _set_choice(key: String, v: StringName) -> void:
	_values[key] = v
	for value in _choices[key]:
		var b: Button = _choices[key][value]
		if value == v:
			b.add_theme_stylebox_override("normal", MenuUI.box(MenuUI.BUTTON_HOVER, 8.0, MenuUI.ACCENT, 7))
			b.add_theme_color_override("font_color", MenuUI.ACCENT)
		else:
			b.add_theme_stylebox_override("normal", MenuUI.box(MenuUI.BUTTON, 8.0, Color.TRANSPARENT, 7))
			b.remove_theme_color_override("font_color")
