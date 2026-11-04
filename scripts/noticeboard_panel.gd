class_name NoticeboardPanel
extends CanvasLayer
## The noticeboard up close (plans/noticeboard.md, look B), in the map's wood-and-parchment look.
## Down the left, the board's categories (Projects.categories()): how many are open in each, and a
## gold mark where there's something you can pay for now. On the cork, the chosen category: one
## paper strip per open project (what it adds, what it costs, have / need, and Pay); on Roads, one
## card per road with its lamps and its paving, each with its own Pay. Under them, a quiet line for
## what waits on the town hall, and a "Done (n)" fold you can open to see what's finished.
## Opens on the category you last looked at. Paying closes the board so you can watch it built.
## Frees the mouse while open; closes on E, Esc, clicking off the board, or walking away.

const CLOSE_DISTANCE := 4.5
const WOOD := Color(0.24, 0.15, 0.08, 0.98)
const BRONZE := Color(0.7, 0.52, 0.27)
const GOLD := Color(1.0, 0.86, 0.55)
const CORK := Color(0.52, 0.36, 0.22)
const TAB := Color(0.17, 0.11, 0.055)
const PAPER := Color(0.93, 0.86, 0.69)
const INK := Color(0.24, 0.15, 0.08)
const HAVE := Color(0.18, 0.45, 0.16)
const NEED := Color(0.62, 0.17, 0.12)
const PIN := Color(0.66, 0.2, 0.16)
const LATER := Color(0.97, 0.92, 0.82, 0.85)

## The category shown last (this session): the board opens on it again.
static var last_category: StringName = &"green"

var board: Node3D
var _closed_msec := -100000
var _shade: ColorRect
var _side: VBoxContainer
var _list: VBoxContainer
var _scroll: ScrollContainer
var _done_open := false
## What the cork shows now (for tests): project ids on strips and cards, waiting, and done.
var shown: Array[StringName] = []
var waiting: Array[StringName] = []
var finished: Array[StringName] = []


## Opens the board's panel (made the first time, in the current scene).
static func open_for(b: Node3D) -> void:
	var tree := b.get_tree()
	var panel := tree.get_first_node_in_group("noticeboard_panel") as NoticeboardPanel
	if panel == null:
		panel = NoticeboardPanel.new()
		tree.current_scene.add_child(panel)
	panel.open(b)


func _ready() -> void:
	add_to_group("noticeboard_panel")
	add_to_group("modal_panel")
	layer = 3
	_build()
	_shade.visible = false
	Inventory.changed.connect(func(_i: StringName, _c: int) -> void: _refresh())
	Projects.changed.connect(_refresh)
	Village.tier_changed.connect(func(_id: StringName, _t: int) -> void: _refresh())


func is_open() -> bool:
	return board != null


## True for a moment after closing, so the same E press doesn't reopen it.
func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


func open(b: Node3D) -> void:
	board = b
	_done_open = false
	_refresh()
	_scroll.scroll_vertical = 0
	_shade.visible = true
	_shade.modulate.a = 0.0
	create_tween().tween_property(_shade, "modulate:a", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_ui(&"open")


func close() -> void:
	if board == null:
		return
	board = null
	_closed_msec = Time.get_ticks_msec()
	_shade.visible = false
	Sfx.play_ui(&"close")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Shows category `id` (as clicking it on the left does).
func show_category(id: StringName) -> void:
	if id != last_category:
		last_category = id
		_done_open = false
		_scroll.scroll_vertical = 0
		Sfx.play_ui(&"click")
	_refresh()


func _input(event: InputEvent) -> void:
	if board == null:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if board == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(board) or (player and player.global_position.distance_to(board.global_position) > CLOSE_DISTANCE):
		close()


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.5)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())  # a click off the board: done
	add_child(_shade)
	var frame := PanelContainer.new()
	var wood := _box(WOOD, BRONZE, 3, 14)
	wood.set_corner_radius_all(6)
	wood.shadow_color = Color(0, 0, 0, 0.6)
	wood.shadow_size = 18
	frame.add_theme_stylebox_override("panel", wood)
	MenuUI.place(frame, Rect2(0.1, 0.07, 0.8, 0.86))
	_shade.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	frame.add_child(box)
	box.add_child(_label("Village noticeboard", 30, GOLD, true))
	box.add_child(_label("What the village would love. Pay for one here and a villager will build it.", 16, Color(GOLD, 0.75)))
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 0)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	# the categories, down the left (a share of the board's width)
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", _box(TAB, Color(BRONZE, 0.5), 2, 0, [2, 2, 0, 2]))
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 0.22
	split.add_child(side)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 0)
	side.add_child(_side)
	# the cork
	var cork := PanelContainer.new()
	cork.add_theme_stylebox_override("panel", _box(CORK, Color(BRONZE, 0.8), 2, 16))
	cork.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cork.size_flags_stretch_ratio = 0.78
	split.add_child(cork)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cork.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	box.add_child(_label("E / Esc close", 15, Color(GOLD, 0.6)))


func _refresh() -> void:
	if _list == null or board == null:
		return
	var cats := Projects.categories().filter(func(c: Dictionary) -> bool: return not (c["projects"] as Array).is_empty())
	if cats.is_empty():
		return
	if not cats.any(func(c: Dictionary) -> bool: return c["id"] == last_category):
		last_category = cats[0]["id"]
	for holder: Node in [_side, _list]:  # (queued: this may run from one of their buttons' signals)
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	for c in cats:
		_side.add_child(_tab(c))
		if c["id"] == last_category:
			_fill(c)


## A category's button on the left: its name, how many are open, and a mark if you can pay for one.
func _tab(c: Dictionary) -> Control:
	var on: bool = c["id"] == last_category
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.tooltip_text = "Something here you can pay for now" if _affordable(c["projects"]) else ""
	var idle := StyleBoxFlat.new()
	idle.bg_color = CORK if on else Color(TAB, 0.0)
	b.add_theme_stylebox_override("normal", idle)
	var hover := idle.duplicate() as StyleBoxFlat
	hover.bg_color = CORK if on else Color(CORK, 0.35)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var id: StringName = c["id"]
	b.pressed.connect(func() -> void: show_category(id))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -12
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var title := _label(c["name"], 18, PAPER if on else Color(PAPER, 0.7), on)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_FILL
	row.add_child(title)
	if _affordable(c["projects"]):
		var mark := _label("●", 14, GOLD)
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.size_flags_vertical = Control.SIZE_FILL
		row.add_child(mark)
	var n := _open(c["projects"]).size()
	var count := _label(str(n) if n > 0 else "", 15, Color(PAPER, 0.6))
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.size_flags_vertical = Control.SIZE_FILL
	count.custom_minimum_size = Vector2(22, 0)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count)
	for l in row.get_children():
		(l as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## The cork for one category: strips (or road cards), then what waits, then the done fold.
func _fill(c: Dictionary) -> void:
	shown.clear()
	waiting.clear()
	finished.clear()
	var projects: Array = c["projects"]
	var later: Array[Dictionary] = []
	var done: Array[Dictionary] = []
	if c["id"] == &"roads":
		for road in _by_road(projects):
			var steps: Array = road["steps"]
			if not _open(steps).is_empty():
				_list.add_child(_road_card(road))
				for p in steps:
					shown.append(p["id"])
			elif steps.all(func(p: Dictionary) -> bool: return p["done"]):
				done.append({"title": road["title"], "ids": steps.map(func(p: Dictionary) -> StringName: return p["id"])})
			else:  # (nothing open, something waiting: the road goes in the "later" line)
				later.append({"title": road["title"], "hall": steps.filter(func(p: Dictionary) -> bool: return not p["done"])
						.map(func(p: Dictionary) -> int: return int(p["hall"])).min(), "ids": steps.map(func(p: Dictionary) -> StringName: return p["id"])})
	else:
		for p in projects:
			if p["done"]:
				done.append({"title": p["title"], "ids": [p["id"]]})
			elif _locked(p):
				later.append({"title": p["title"], "hall": int(p["hall"]), "ids": [p["id"]]})
			else:
				_list.add_child(_strip(p))
				shown.append(p["id"])
	for l in later:
		waiting.append_array(l["ids"])
	for d in done:
		finished.append_array(d["ids"])
	if shown.is_empty():
		_list.add_child(_label("Nothing to pay for here just now." if not later.is_empty() else "All done here. Thank you!", 17, LATER))
	if not later.is_empty():
		var line := _label(_later_text(later), 15, LATER)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(line)
	if not done.is_empty():
		_list.add_child(_done_fold(done))


## Projects not done whose town hall tier you have.
func _open(projects: Array) -> Array:
	return projects.filter(func(p: Dictionary) -> bool: return not p["done"] and not _locked(p))


func _locked(p: Dictionary) -> bool:
	return Village.tier(Village.TOWN_HALL) < int(p["hall"])


func _affordable(projects: Array) -> bool:
	return _open(projects).any(func(p: Dictionary) -> bool: return Inventory.has_all(p["cost"]))


## Roads' projects as one entry per road, in the board's order: {title, steps} (lamps first).
func _by_road(projects: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := {}
	for p in projects:
		var road: StringName = p["on_road"]
		if not at.has(road):
			at[road] = out.size()
			out.append({"title": p["road_title"], "steps": []})
		(out[at[road]]["steps"] as Array).append(p)
	for r in out:
		(r["steps"] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["step"] == "Lamps" and b["step"] != "Lamps")
	return out


## "Later, at town hall tier 2: a well on the green, bunting. Tier 3: a fountain."
func _later_text(later: Array[Dictionary]) -> String:
	var tiers := {}
	for l in later:
		if not tiers.has(l["hall"]):
			tiers[l["hall"]] = []
		tiers[l["hall"]].append(Projects._lower_first(l["title"]))
	var keys := tiers.keys()
	keys.sort()
	var parts: Array[String] = []
	for i in keys.size():
		parts.append(("Later, at town hall tier %d: %s." if i == 0 else "Tier %d: %s.") % [keys[i], ", ".join(tiers[keys[i]])])
	return " ".join(parts)


## One open project on a paper strip: title and what it adds | cost | Pay.
func _strip(p: Dictionary) -> Control:
	var note := _paper()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	note.add_child(row)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_stretch_ratio = 0.62
	row.add_child(words)
	var head := _label(p["title"], 19, INK, true)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(head)
	var blurb := _label(p["blurb"], 15, Color(INK, 0.85))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(blurb)
	var cost := _cost(p["cost"])
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost.size_flags_stretch_ratio = 0.38
	cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cost)
	row.add_child(_pay(p))
	return note


## A road's card: its name, then a row each for its lamps and its paving.
func _road_card(road: Dictionary) -> Control:
	var note := _paper()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	note.add_child(col)
	col.add_child(_label(road["title"], 19, INK, true))
	for p in road["steps"]:
		col.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		col.add_child(row)
		var step := _label(p["step"], 16, INK, true)
		step.tooltip_text = p["blurb"]
		step.mouse_filter = Control.MOUSE_FILTER_STOP
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.size_flags_stretch_ratio = 0.3
		step.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(step)
		if p["done"]:
			var what := _label("✓  " + ("Lit" if p["step"] == "Lamps" else "Cobbled"), 15, HAVE)
			what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			what.size_flags_stretch_ratio = 0.7
			row.add_child(what)
			continue
		var cost := _cost(p["cost"])
		cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cost.size_flags_stretch_ratio = 0.7
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cost)
		if _locked(p):
			row.add_child(_label("Town hall tier %d" % p["hall"], 14, Color(INK, 0.6)))
		else:
			row.add_child(_pay(p))
	return note


func _done_fold(done: Array[Dictionary]) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text = ("▾  " if _done_open else "▸  ") + "Done (%d)" % done.size()
	head.add_theme_font_override("font", MapView.map_font(true))
	head.add_theme_font_size_override("font_size", 16)
	for s in ["font_color", "font_hover_color", "font_pressed_color"]:
		head.add_theme_color_override(s, LATER)
	head.pressed.connect(func() -> void:
		_done_open = not _done_open
		_refresh())
	col.add_child(head)
	if _done_open:
		for d in done:
			col.add_child(_label("    ✓  " + String(d["title"]), 15, LATER))
	return col


func _cost(cost: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 4)
	for item in cost:
		var need: int = cost[item]
		var have := Inventory.count(item)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var icon := TextureRect.new()
		icon.texture = Items.icon(item)
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.tooltip_text = Items.display_name(item)
		cell.add_child(icon)
		cell.add_child(_label("%d/%d" % [mini(have, need), need], 15, HAVE if have >= need else NEED))
		row.add_child(cell)
	return row


func _pay(p: Dictionary) -> Button:
	var id: StringName = p["id"]
	var pay := Button.new()
	pay.text = "Pay"
	pay.focus_mode = Control.FOCUS_NONE
	pay.disabled = not Inventory.has_all(p["cost"])
	pay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pay.custom_minimum_size = Vector2(90, 0)
	pay.pressed.connect(func() -> void:
		if Projects.pay(id):
			close())
	return pay


## A sheet of paper pinned to the cork.
func _paper() -> PanelContainer:
	var note := PanelContainer.new()
	var ps := _box(PAPER, Color(INK, 0.25), 1, 12)
	ps.content_margin_top = 14
	ps.shadow_color = Color(0, 0, 0, 0.35)
	ps.shadow_size = 4
	ps.shadow_offset = Vector2(2, 3)
	note.add_theme_stylebox_override("panel", ps)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.draw.connect(func() -> void:  # (a pin at the top middle: drawn, so the strip's layout ignores it)
		note.draw_circle(Vector2(note.size.x * 0.5, 4.0), 5.0, PIN)
		note.draw_circle(Vector2(note.size.x * 0.5 - 1.5, 2.5), 1.6, Color(1, 1, 1, 0.45)))
	return note


## A flat box: fill, border (all sides, or [left, top, right, bottom]), content margin.
func _box(fill: Color, border: Color, width: int, margin: int, sides := []) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	if sides.is_empty():
		s.set_border_width_all(width)
	else:
		s.border_width_left = sides[0]
		s.border_width_top = sides[1]
		s.border_width_right = sides[2]
		s.border_width_bottom = sides[3]
	s.set_content_margin_all(margin)
	return s


func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MapView.map_font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
