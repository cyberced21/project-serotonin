class_name MarketPanel
extends CanvasLayer
## Bartering at the market stall (plans/market.md), in the noticeboard's wood-and-parchment look.
## Left: what you can get (every tradeable good). Pick one, and the right lists what you could give
## for it, cheapest first, with what you have: click one to trade (one at a time). While the trader
## is in town the rates are kinder (Market.TRADER_RATE), and her specials show at the bottom.
## Frees the mouse while open; closes on E, Esc, clicking off it, or walking away.

const CLOSE_DISTANCE := 5.0
## Goods changing hands (audio/trader/SOURCES.md).
const TRADE_SOUND := preload("res://audio/trader/trade.wav")
const TRADE_DB := -10.0

var stall: Node3D
var _closed_msec := -100000
var _shade: ColorRect
var _wants: GridContainer
var _offers: VBoxContainer
var _title: Label
var _hint: Label
var _specials: Control
var _want: StringName = &"iron"


static func open_for(s: Node3D) -> void:
	var tree := s.get_tree()
	var panel := tree.get_first_node_in_group("market_panel") as MarketPanel
	if panel == null:
		panel = MarketPanel.new()
		tree.current_scene.add_child(panel)
	panel.open(s)


func _ready() -> void:
	add_to_group("market_panel")
	add_to_group("modal_panel")
	layer = 3
	_build()
	_shade.visible = false
	Inventory.changed.connect(func(_i: StringName, _c: int) -> void: _refresh())


func is_open() -> bool:
	return stall != null


func just_closed() -> bool:
	return Time.get_ticks_msec() - _closed_msec < 250


func open(s: Node3D) -> void:
	stall = s
	_refresh()
	_shade.visible = true
	_shade.modulate.a = 0.0
	create_tween().tween_property(_shade, "modulate:a", 1.0, 0.2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play_ui(&"open")


func close() -> void:
	if stall == null:
		return
	stall = null
	_closed_msec = Time.get_ticks_msec()
	_shade.visible = false
	Sfx.play_ui(&"close")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Picks what you want (the left column).
func want(item: StringName) -> void:
	_want = item
	_refresh()


func trader_in() -> bool:
	var t := get_tree().get_first_node_in_group("trader")
	return t != null and t.call("is_in")


func _input(event: InputEvent) -> void:
	if stall == null:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if stall == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(stall) or (player and player.global_position.distance_to(stall.global_position) > CLOSE_DISTANCE):
		close()


func _refresh() -> void:
	if _wants == null:
		return
	for c in _wants.get_children():
		c.queue_free()
	for f in Market.FAMILIES:
		for item: StringName in Market.FAMILIES[f]:
			var b := Button.new()
			b.toggle_mode = true
			b.button_pressed = item == _want
			b.icon = Items.icon(item)
			b.expand_icon = true
			b.custom_minimum_size = Vector2(52, 52)
			b.tooltip_text = "%s (you have %d)" % [Items.display_name(item), Inventory.count(item)]
			b.pressed.connect(want.bind(item))
			_wants.add_child(b)
	_title.text = "Get one %s" % Items.display_name(_want).to_lower()
	_hint.text = "The trader's in town: kinder rates today." if trader_in() else "Swaps within a family (logs, ore, crops, fish) are cheaper."
	for c in _offers.get_children():
		c.queue_free()
	var offers: Array = []
	for item: StringName in Market.VALUES:
		if item != _want:
			offers.append([item, Market.price(item, _want, trader_in())])
	offers.sort_custom(func(a: Array, b: Array) -> bool:
		var ha := Inventory.count(a[0]) >= int(a[1])
		var hb := Inventory.count(b[0]) >= int(b[1])
		return ha and not hb or (ha == hb and float(Market.VALUES[a[0]]) * a[1] < float(Market.VALUES[b[0]]) * b[1]))
	for o in offers:
		var item: StringName = o[0]
		var n: int = o[1]
		var have := Inventory.count(item)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = Items.icon(item)
		b.expand_icon = false
		b.text = "  Give %d %s   (you have %d)" % [n, Items.display_name(item), have]
		b.disabled = have < n
		b.add_theme_font_override("font", MapView.map_font(false))
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func() -> void:
			if Market.trade(item, _want, trader_in()):
				Sfx.play(TRADE_SOUND, randf_range(0.95, 1.05), TRADE_DB))
		_offers.add_child(b)
	var trader := get_tree().get_first_node_in_group("trader")
	for c in _specials.get_children():
		c.queue_free()
	if trader and trader.call("is_in"):
		trader.call("fill_specials", _specials)


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.5)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	add_child(_shade)
	var frame := PanelContainer.new()
	var wood := StyleBoxFlat.new()
	wood.bg_color = NoticeboardPanel.WOOD
	wood.border_color = NoticeboardPanel.BRONZE
	wood.set_border_width_all(3)
	wood.set_corner_radius_all(6)
	wood.set_content_margin_all(14)
	wood.shadow_color = Color(0, 0, 0, 0.6)
	wood.shadow_size = 18
	frame.add_theme_stylebox_override("panel", wood)
	MenuUI.place(frame, Rect2(0.12, 0.08, 0.76, 0.84))
	_shade.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	frame.add_child(box)
	box.add_child(_label("The market stall", 30, NoticeboardPanel.GOLD, true))
	_hint = _label("", 16, Color(NoticeboardPanel.GOLD, 0.75))
	box.add_child(_hint)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	box.add_child(cols)
	var left := VBoxContainer.new()
	left.add_child(_label("What you'd like", 20, NoticeboardPanel.GOLD, true))
	_wants = GridContainer.new()
	_wants.columns = 6
	left.add_child(_wants)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = _label("", 20, NoticeboardPanel.GOLD, true)
	right.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_offers = VBoxContainer.new()
	_offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_offers)
	cols.add_child(right)
	_specials = VBoxContainer.new()
	box.add_child(_specials)


func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", MapView.map_font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
