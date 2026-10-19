extends CanvasLayer
## Debug menu, debug builds only. F1 opens it (frees the mouse); F1, Esc or clicking outside closes it.
## Tabs:
##   Items     add or clear any item
##   Skills    set levels, add XP
##   Village   put any building at any tier (free, ignores the town hall's cap), current perks
##   World     time of day, time scale, pause, regrow every node, restock every pond
##   Teleport  to each building, biome landmark, pond and kind of resource node (the nearest one)
##   Player    fly mode, a live readout (can stay pinned on screen), save / wipe the save
##   Procgen   a scratch generated world by seed, or a new random one, and back to the main menu
##   Graphics  Low / Medium / High presets and each costly effect on its own (GraphicsSettings)
## The old F6–F10 keys still work. Toggles that stay on (fly, pause, time scale) show as a tag at
## the top of the screen while the menu is closed.

const WIDTH := 460.0
const BG := Color(0.09, 0.075, 0.06, 0.94)
const BORDER := Color("8a6142")
const ACCENT := Color("ffd27a")
const GOOD := Color("9be27a")
const WARN := Color("ff8a7a")
const DIM := Color(1, 1, 1, 0.6)
const BUTTON := Color("5f4029")
const BUTTON_HOVER := Color("734f33")
const WORLD_MASK := 1
const Player := preload("res://scripts/player.gd")
const TIME_SCALES: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]
const TIMES_OF_DAY := {"Dawn": 0.15, "Midday": 0.5, "Dusk": 0.85, "Night": 0.0}

var _panel: PanelContainer
var _tabs: TabContainer
var _readout: Label
var _tag: Label
var _pinned: Label
var _item_labels: Dictionary[StringName, Label] = {}
var _skill_labels: Dictionary[StringName, Label] = {}
var _village_box: VBoxContainer
var _perks: Label
var _time_slider: HSlider
var _time_label: Label
var _dragging_time := false
var _scale_buttons: Dictionary[float, Button] = {}
var _pause: CheckBox
var _teleport_box: VBoxContainer
var _fly: CheckBox
var _pin: CheckBox
var _reset_button: Button
var _reset_armed := false
var _procgen_status: Label
var _seed_edit: LineEdit
var _gfx_preset: Label
var _gfx_checks: Dictionary[StringName, CheckBox] = {}
var _gfx_sliders: Dictionary[StringName, HSlider] = {}
var _gfx_msaa: Dictionary[int, Button] = {}


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false
	Inventory.changed.connect(func(_i: StringName, _c: int) -> void: _refresh_items())
	Skills.xp_gained.connect(func(_s: StringName, _a: int, _t: int) -> void: _refresh_skills())
	Village.tier_changed.connect(func(_id: StringName, _t: int) -> void: _refresh_village())


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	var upgrade := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	if upgrade:
		upgrade.close()
	_rebuild_village()  # buildings register when the scene loads, after this autoload
	_rebuild_teleports()
	_refresh_items()
	_refresh_skills()
	_disarm_reset()
	_refresh_procgen()
	_fly.set_pressed_no_signal(_player() != null and _player().debug_fly)
	_pause.set_pressed_no_signal(get_tree().paused)
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not is_open():
		return
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_menu"):
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		close()  # clicked outside the panel: the player took the mouse back
	var text := _readout_text()
	if is_open():
		_readout.text = text
		if not _dragging_time:
			_time_slider.set_value_no_signal(DayNight.time)
		_time_label.text = DayNight.clock_text()
	_pinned.visible = _pin.button_pressed and not is_open()
	if _pinned.visible:
		_pinned.text = text
	var tags: PackedStringArray = []
	var p := _player()
	if p and p.debug_fly:
		tags.append("FLY")
	if get_tree().paused:
		tags.append("PAUSED")
	if not is_equal_approx(Engine.time_scale, 1.0):
		tags.append("TIME ×%s" % Engine.time_scale)
	_tag.text = "  ·  ".join(tags)
	_tag.visible = not tags.is_empty() and not is_open()


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


# --- actions ----------------------------------------------------------------------------------

func _give_all(amount: int) -> void:
	for item in Items.DEFS:
		Inventory.add(item, amount)


func _clear_items() -> void:
	for item in Inventory.items.keys():
		Inventory.set_count(item, 0)


func _set_all_skills(lvl: int) -> void:
	for s in Skills.SKILLS:
		Skills.set_level(s, lvl)


func _set_all_tiers(top: bool) -> void:
	# the town hall first going up, last going down, so the cottages build or vanish in order
	var ids := Village.building_ids()
	if not top:
		ids.reverse()
	for id in ids:
		Village.set_tier(id, Village.get_def(id).max_tier() if top else 1)


func _set_time_scale(s: float) -> void:
	Engine.time_scale = s
	for k in _scale_buttons:
		_scale_buttons[k].modulate = ACCENT if is_equal_approx(k, s) else Color.WHITE


func _regrow_all() -> void:
	for n in get_tree().get_nodes_in_group("gatherable"):
		(n as ResourceNode).respawn_now()


func _restock_all() -> void:
	for pond in get_tree().get_nodes_in_group("fish_pond"):
		(pond as FishPond).restock_now()


func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_reset_button.text = "Really wipe the save? Click again"
		_reset_button.modulate = WARN
		return
	_disarm_reset()
	close()
	get_tree().paused = false
	Engine.time_scale = 1.0
	SaveGame.reset()


func _procgen_world() -> ProcgenWorld:
	return get_tree().get_first_node_in_group("procgen_world") as ProcgenWorld


func _enter_procgen(s: int) -> void:
	close()
	get_tree().paused = false
	Engine.time_scale = 1.0
	Worlds.play_scratch(s)


func _enter_typed_seed() -> void:
	var text := _seed_edit.text.strip_edges()
	_enter_procgen(text.to_int() if text.is_valid_int() else ProcgenMap.random_seed())


func _leave_procgen() -> void:
	close()
	get_tree().paused = false
	Engine.time_scale = 1.0
	Worlds.leave()


func _refresh_procgen() -> void:
	var world := _procgen_world()
	if world == null or world.map == null:
		_procgen_status.text = "In %s" % Worlds.current_meta.get("name", "no world")
		return
	var map := world.map
	var kinds: PackedStringArray = []
	for biome in map.kinds:
		kinds.append(map.kind_name(biome))
	_procgen_status.text = "In %s, seed %d\n%s\nRich in %s, lean on %s" % [Worlds.current_meta.get("name", "?"), world.world_seed,
			", ".join(kinds), Items.display_name(map.rich), Items.display_name(map.lean)]
	if _seed_edit.text.is_empty():
		_seed_edit.text = str(world.world_seed)


func _disarm_reset() -> void:
	_reset_armed = false
	if _reset_button:
		_reset_button.text = "Wipe save and restart"
		_reset_button.modulate = Color.WHITE


## The ground under (or over) `at`, so teleports land on the terrain, not in it.
func _ground(at: Vector3) -> Vector3:
	var p := _player()
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 80.0, at + Vector3.DOWN * 80.0, WORLD_MASK)
	if p:
		q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q) if p else {}
	return (hit["position"] as Vector3) + Vector3.UP * 0.1 if hit else at


func _teleport(to: Vector3, look: Vector3) -> void:
	var p := _player()
	if p == null:
		return
	p.teleport(_ground(to), look)
	close()


func _teleport_to_building(b: Building) -> void:
	var front := b.global_transform * Vector3(0, 0, b.footprint_radius() + 4.0)
	_teleport(front, b.global_position)


func _teleport_near_node(item: StringName) -> void:
	var p := _player()
	var best: ResourceNode
	for n in get_tree().get_nodes_in_group("gatherable"):
		var r := n as ResourceNode
		if r.item == item and (best == null or p.global_position.distance_to(r.global_position)
				< p.global_position.distance_to(best.global_position)):
			best = r
	if best == null:
		return
	var away := p.global_position - best.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	_teleport(best.global_position + away * 2.6, best.global_position)


# --- readout ----------------------------------------------------------------------------------

func _readout_text() -> String:
	var p := _player()
	var lines := ["FPS %d" % Engine.get_frames_per_second()]
	if p:
		var pos := p.global_position
		var flat := Vector2(p.velocity.x, p.velocity.z).length()
		lines.append("pos %.1f, %.1f, %.1f" % [pos.x, pos.y, pos.z])
		lines.append("speed %.1f m/s  ·  %s%s" % [flat, Player.State.keys()[p._state].capitalize(),
				"  ·  on floor" if p.is_on_floor() else ""])
	lines.append("%s  ·  %s  ·  %s" % [DayNight.clock_text(), DayNight.part_of_day(),
			String(Biome.current) if Biome.current != &"" else "no biome"])
	return "\n".join(lines)


# --- refresh ----------------------------------------------------------------------------------

func _refresh_items() -> void:
	for item in _item_labels:
		_item_labels[item].text = "%s  %d" % [Items.display_name(item), Inventory.count(item)]


func _refresh_skills() -> void:
	for s in _skill_labels:
		var lvl := Skills.level(s)
		_skill_labels[s].text = "%s  %d  (%d XP)" % [Skills.display_name(s), lvl, Skills.xp.get(s, 0)]


func _refresh_village() -> void:
	if _village_box == null:
		return
	for row in _village_box.get_children():
		if row.has_meta("building"):
			var id: StringName = row.get_meta("building")
			var def := Village.get_def(id)
			var t := Village.tier(id)
			var label := row.get_child(0) as Label
			label.text = "%s  T%d  %s" % [def.display_name, t, def.get_tier(t).name]
			for b in row.get_children().slice(1):
				(b as Button).modulate = ACCENT if int(b.get_meta("tier")) == t else Color.WHITE
	var stats: Dictionary[StringName, bool] = {}
	for id in Village.building_ids():
		for tier in Village.get_def(id).tiers:
			for e in tier.effects:
				stats[e.stat] = true
	var lines: PackedStringArray = []
	for stat in stats:
		var v := Village.stat(stat)
		if v != 0.0:
			lines.append("%s  %s" % [stat, v])
	_perks.text = "Perks now:\n" + ("\n".join(lines) if not lines.is_empty() else "(none)")


func _rebuild_village() -> void:
	for c in _village_box.get_children():
		c.queue_free()
	for id in Village.building_ids():
		var def := Village.get_def(id)
		var row := HBoxContainer.new()
		row.set_meta("building", id)
		var label := _label(15)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		for t in range(1, def.max_tier() + 1):
			var b := _button("T%d" % t, Village.set_tier.bind(id, t), false)
			b.set_meta("tier", t)
			row.add_child(b)
		_village_box.add_child(row)
	_refresh_village()


func _rebuild_teleports() -> void:
	for c in _teleport_box.get_children():
		c.queue_free()
	_teleport_box.add_child(_heading("Buildings"))
	var grid := _grid(2)
	for b in get_tree().get_nodes_in_group("building"):
		var building := b as Building
		grid.add_child(_button(building.def.display_name, _teleport_to_building.bind(building)))
	_teleport_box.add_child(grid)

	_teleport_box.add_child(_heading("Biomes"))
	grid = _grid(3)
	var world := _procgen_world()
	if world:
		for site in (world.map.sites if world.map else []):
			var mood: BiomeMood = Biome.MOODS[site["biome"]]
			var at := Vector3(site["pos"].x, 0, site["pos"].y)
			var b := _button(mood.display_name.trim_prefix("The "), _teleport.bind(at, at + Vector3.FORWARD))
			b.tooltip_text = "Tier %d" % site["tier"]
			grid.add_child(b)
	else:
		for place in WorldMap.LANDMARKS:
			var spot: Array = WorldMap.LANDMARKS[place]
			grid.add_child(_button(place, _teleport.bind(spot[0], spot[1])))
	_teleport_box.add_child(grid)

	var landmarks := get_tree().get_nodes_in_group("landmark")
	if not landmarks.is_empty():  # a procgen world's ruins, camps and rare spots
		_teleport_box.add_child(_heading("Landmarks"))
		grid = _grid(2)
		for l in landmarks:
			var at := (l as Node3D).global_position + Vector3(0, 0, 10).rotated(Vector3.UP, (l as Node3D).rotation.y)
			grid.add_child(_button(l.get_meta("landmark"), _teleport.bind(at, (l as Node3D).global_position)))
		_teleport_box.add_child(grid)

	_teleport_box.add_child(_heading("Water"))
	grid = _grid(3)
	for w in get_tree().get_nodes_in_group("water"):
		var water := w as Node3D
		var label := String(water.name).capitalize()
		if String(water.name).begins_with("Stretch"):  # a procgen river: one button, its first stretch
			if water.name != &"Stretch1":
				continue
			label = String(water.get_parent().name).capitalize()
		grid.add_child(_button(label, _teleport.bind(water.global_position, water.global_position + Vector3.FORWARD)))
	_teleport_box.add_child(grid)

	_teleport_box.add_child(_heading("Nearest resource node"))
	grid = _grid(3)
	var seen: Dictionary[StringName, ResourceNode] = {}
	for n in get_tree().get_nodes_in_group("gatherable"):
		var r := n as ResourceNode
		if not seen.has(r.item) or r.required_level < seen[r.item].required_level:
			seen[r.item] = r
	var items := seen.keys()
	items.sort_custom(func(a: StringName, b: StringName) -> bool: return Items.order(a) < Items.order(b))
	for item in items:
		var r := seen[item]
		var b := _button(Items.display_name(item), _teleport_near_node.bind(item))
		b.tooltip_text = "%s %d" % [Skills.display_name(r.skill), r.required_level]
		grid.add_child(b)
	_teleport_box.add_child(grid)


# --- layout -----------------------------------------------------------------------------------

func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 16
	_panel.offset_right = 16 + WIDTH
	_panel.offset_top = 16
	_panel.offset_bottom = -16
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := _label(22)
	title.text = "Debug"
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)
	_readout = _label(14)
	_readout.modulate = DIM
	box.add_child(_readout)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_focus_mode = Control.FOCUS_NONE
	box.add_child(_tabs)
	_tabs.add_child(_scroll("Items", _build_items()))
	_tabs.add_child(_scroll("Skills", _build_skills()))
	_tabs.add_child(_scroll("Village", _build_village()))
	_tabs.add_child(_scroll("World", _build_world()))
	_teleport_box = VBoxContainer.new()
	_tabs.add_child(_scroll("Teleport", _teleport_box))
	_tabs.add_child(_scroll("Player", _build_player()))
	_tabs.add_child(_scroll("Procgen", _build_procgen()))
	_tabs.add_child(_scroll("Graphics", _build_graphics()))

	var hint := _label(13)
	hint.text = "F1 / Esc  close"
	hint.modulate = DIM
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)

	_tag = _label(16)
	_tag.add_theme_color_override("font_color", ACCENT)
	_tag.anchor_left = 0.5
	_tag.anchor_right = 0.5
	_tag.offset_top = 10
	_tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.visible = false
	add_child(_tag)

	_pinned = _label(14)
	_pinned.anchor_left = 1.0
	_pinned.anchor_right = 1.0
	_pinned.anchor_top = 1.0
	_pinned.anchor_bottom = 1.0
	_pinned.offset_right = -16
	_pinned.offset_bottom = -16
	_pinned.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pinned.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_pinned.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pinned.visible = false
	add_child(_pinned)


func _build_items() -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_child(_button("All +10", _give_all.bind(10)))
	row.add_child(_button("All +50", _give_all.bind(50)))
	row.add_child(_button("Clear all", _clear_items))
	box.add_child(row)
	box.add_child(HSeparator.new())
	for item in Items.DEFS:
		var line := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = Items.icon(item)
		icon.custom_minimum_size = Vector2(26, 26)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		line.add_child(icon)
		var label := _label(15)
		label.custom_minimum_size = Vector2(170, 0)
		line.add_child(label)
		_item_labels[item] = label
		line.add_child(_button("+1", Inventory.add.bind(item, 1)))
		line.add_child(_button("+10", Inventory.add.bind(item, 10)))
		line.add_child(_button("0", Inventory.set_count.bind(item, 0)))
		box.add_child(line)
	return box


func _build_skills() -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_child(_button("All level 1", _set_all_skills.bind(1)))
	row.add_child(_button("All level 30", _set_all_skills.bind(30)))
	row.add_child(_button("All max", _set_all_skills.bind(Skills.MAX_LEVEL)))
	box.add_child(row)
	box.add_child(HSeparator.new())
	for s in Skills.SKILLS:
		var label := _label(16)
		label.add_theme_color_override("font_color", Skills.color(s))
		box.add_child(label)
		_skill_labels[s] = label
		var line := HBoxContainer.new()
		line.add_child(_button("−5", func() -> void: Skills.set_level(s, Skills.level(s) - 5)))
		line.add_child(_button("−1", func() -> void: Skills.set_level(s, Skills.level(s) - 1)))
		line.add_child(_button("+1", func() -> void: Skills.set_level(s, Skills.level(s) + 1)))
		line.add_child(_button("+5", func() -> void: Skills.set_level(s, Skills.level(s) + 5)))
		line.add_child(_button("+500 XP", func() -> void: Skills.add_xp(s, 500)))
		box.add_child(line)
	return box


func _build_village() -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_child(_button("All tier 1", _set_all_tiers.bind(false)))
	row.add_child(_button("All max", _set_all_tiers.bind(true)))
	box.add_child(row)
	var note := _label(13)
	note.text = "Free, and ignores the town hall's cap."
	note.modulate = DIM
	box.add_child(note)
	box.add_child(HSeparator.new())
	_village_box = VBoxContainer.new()
	box.add_child(_village_box)
	box.add_child(HSeparator.new())
	_perks = _label(14)
	_perks.add_theme_color_override("font_color", GOOD)
	box.add_child(_perks)
	return box


func _build_world() -> Control:
	var box := VBoxContainer.new()
	box.add_child(_heading("Time of day"))
	_time_label = _label(16)
	box.add_child(_time_label)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 1.0
	_time_slider.step = 0.001
	_time_slider.focus_mode = Control.FOCUS_NONE
	_time_slider.value_changed.connect(func(v: float) -> void: DayNight.time = fposmod(v, 1.0))
	_time_slider.drag_started.connect(func() -> void: _dragging_time = true)
	_time_slider.drag_ended.connect(func(_changed: bool) -> void: _dragging_time = false)
	box.add_child(_time_slider)
	var row := HBoxContainer.new()
	for name in TIMES_OF_DAY:
		row.add_child(_button(name, func() -> void: DayNight.time = TIMES_OF_DAY[name]))
	box.add_child(row)

	box.add_child(_heading("Time scale"))
	row = HBoxContainer.new()
	for s in TIME_SCALES:
		var b := _button("×%s" % s, _set_time_scale.bind(s))
		_scale_buttons[s] = b
		row.add_child(b)
	box.add_child(row)
	_set_time_scale(1.0)
	_pause = _check("Pause the world", func(on: bool) -> void: get_tree().paused = on)
	box.add_child(_pause)

	box.add_child(_heading("Reset the world"))
	row = HBoxContainer.new()
	row.add_child(_button("Regrow every node", _regrow_all))
	row.add_child(_button("Restock every pond", _restock_all))
	box.add_child(row)
	return box


func _build_player() -> Control:
	var box := VBoxContainer.new()
	_fly = _check("Fly (noclip): Space up, Ctrl down, Shift fast", func(on: bool) -> void:
		var p := _player()
		if p:
			p.debug_fly = on)
	box.add_child(_fly)
	_pin = _check("Keep the readout on screen", func(_on: bool) -> void: pass)
	box.add_child(_pin)
	box.add_child(_heading("Save"))
	var row := HBoxContainer.new()
	row.add_child(_button("Save now", SaveGame.save))
	_reset_button = _button("Wipe save and restart", _on_reset_pressed)
	row.add_child(_reset_button)
	box.add_child(row)
	var keys := _label(13)
	keys.text = "Keys: F6 skip time  ·  F7 +50 items  ·  F8 village tiers\nF9 +500 XP (last skill)  ·  F10 wipe save"
	keys.modulate = DIM
	box.add_child(keys)
	return box


func _build_procgen() -> Control:
	var box := VBoxContainer.new()
	_procgen_status = _label(16)
	box.add_child(_procgen_status)
	box.add_child(_heading("Generated world"))
	var row := HBoxContainer.new()
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "seed"
	_seed_edit.custom_minimum_size = Vector2(120, 0)
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _enter_typed_seed())
	row.add_child(_seed_edit)
	row.add_child(_button("Enter this seed", _enter_typed_seed))
	box.add_child(row)
	box.add_child(_button("New seed (random)", func() -> void: _enter_procgen(ProcgenMap.random_seed())))
	box.add_child(_button("Back to the main menu", _leave_procgen))
	var note := _label(13)
	note.text = "Seeds entered here go into a scratch world (worlds/_scratch), wiped each time.
Your own worlds are never touched."
	note.modulate = DIM
	box.add_child(note)
	return box


func _build_graphics() -> Control:
	var box := VBoxContainer.new()
	_gfx_preset = _label(16)
	box.add_child(_gfx_preset)
	var row := HBoxContainer.new()
	for p in GraphicsSettings.PRESET_ORDER:
		row.add_child(_button(String(p).capitalize(), GraphicsSettings.apply_preset.bind(p)))
	box.add_child(row)

	box.add_child(_heading("Effects"))
	var checks := {
		&"ssao": "Ambient occlusion (SSAO): contact shadows in corners",
		&"ssil": "Bounced light (SSIL)",
		&"volumetric_fog": "Volumetric fog and light shafts",
		&"glow": "Bloom (glow round bright things)",
		&"fxaa": "FXAA (cheap edge smoothing)",
		&"light_shadows": "Lamps cast shadows",
	}
	for key in checks:
		var c := _check(checks[key], func(on: bool) -> void: GraphicsSettings.set_value(key, on))
		_gfx_checks[key] = c
		box.add_child(c)

	box.add_child(_heading("Anti-aliasing (MSAA)"))
	row = HBoxContainer.new()
	for n in [0, 2, 4]:
		var b := _button("Off" if n == 0 else "%d×" % n, func() -> void: GraphicsSettings.set_value(&"msaa", n))
		_gfx_msaa[n] = b
		row.add_child(b)
	box.add_child(row)

	var sliders := {
		&"shadow_distance": ["Shadow distance (m)", 30.0, 200.0, 10.0],
		&"grass_density": ["Grass density", 0.0, 1.0, 0.05],
		&"foliage_distance": ["Grass and foliage draw distance", 0.3, 1.0, 0.05],
	}
	for key in sliders:
		var spec: Array = sliders[key]
		box.add_child(_heading(spec[0]))
		var s := HSlider.new()
		s.min_value = spec[1]
		s.max_value = spec[2]
		s.step = spec[3]
		s.focus_mode = Control.FOCUS_NONE
		s.drag_ended.connect(func(_c: bool) -> void: GraphicsSettings.set_value(key, s.value))
		_gfx_sliders[key] = s
		box.add_child(s)

	var note := _label(13)
	note.text = "Saved to user://settings.cfg, not the game save."
	note.modulate = DIM
	box.add_child(note)
	GraphicsSettings.changed.connect(_refresh_graphics)
	_refresh_graphics()
	return box


func _refresh_graphics() -> void:
	_gfx_preset.text = "Preset: %s" % String(GraphicsSettings.preset).capitalize()
	for key in _gfx_checks:
		_gfx_checks[key].set_pressed_no_signal(bool(GraphicsSettings.get_value(key)))
	for key in _gfx_sliders:
		_gfx_sliders[key].set_value_no_signal(float(GraphicsSettings.get_value(key)))
	var msaa := int(GraphicsSettings.get_value(&"msaa"))
	for n in _gfx_msaa:
		_gfx_msaa[n].modulate = ACCENT if n == msaa else Color.WHITE


func _scroll(title: String, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if content is BoxContainer:
		content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)
	return scroll


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


func _heading(text: String) -> Label:
	var label := _label(16)
	label.text = text
	label.add_theme_color_override("font_color", ACCENT)
	return label


func _button(text: String, on_press: Callable, expand := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		b.custom_minimum_size = Vector2(46, 0)
	var normal := StyleBoxFlat.new()
	normal.bg_color = BUTTON
	normal.set_corner_radius_all(5)
	normal.set_content_margin_all(5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BUTTON_HOVER
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", normal)
	b.pressed.connect(on_press)
	return b


func _check(text: String, on_toggle: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 15)
	c.toggled.connect(on_toggle)
	return c


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label
