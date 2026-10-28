class_name Minimap
extends Control
## The round map in the top-right corner, as on an old MMO's HUD: the parchment map round you
## (MapView, north up, you the gold arrow in the middle), a bronze ring with an N on it, the name
## of the place you're in above it and the time of day below. Built by the HUD.

## The map's width on screen, as a share of the window's height (so it scales with the window).
const SCREEN_SHARE := 0.27
const METRES_ACROSS := 110.0
const BRONZE := Color(0.62, 0.45, 0.22)
const BRONZE_LIGHT := Color(0.86, 0.68, 0.38)
const BRONZE_DARK := Color(0.25, 0.16, 0.07)

var view: MapView
var _ring: Control  # drawn over the map's edge
var _zone: Label
var _clock: Label
var _font: SystemFont


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = MapView.map_font(true)
	view = MapView.new()
	view.circular = true
	view.show_labels = false
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_ring = Control.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_zone = _label(17)
	add_child(_zone)
	_clock = _label(15)
	add_child(_clock)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.03))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Sized from the window: the map, the zone name over it, the clock under it.
func _layout() -> void:
	var win := get_viewport_rect().size
	var d := roundf(clampf(win.y * SCREEN_SHARE, 150.0, 300.0))
	var zone_h := 24.0
	var top := zone_h + 14.0  # (room for the N plaque under the zone's name)
	size = Vector2(d + 16.0, d + top + 30.0)
	position = Vector2(win.x - size.x - 14.0, 10.0)
	_zone.position = Vector2(0, 0)
	_zone.size = Vector2(size.x, zone_h)
	view.position = Vector2(8.0, top)
	view.size = Vector2(d, d)
	_clock.position = Vector2(0, top + d + 8.0)
	_clock.size = Vector2(size.x, 22.0)
	_ring.queue_redraw()


func _process(_delta: float) -> void:
	# out of the way while a villager's panel is up (it takes the right of the screen)
	var panel := get_tree().get_first_node_in_group("upgrade_panel") as UpgradePanel
	visible = not (panel and panel.is_open())
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		view.center = Vector2(player.global_position.x, player.global_position.z)
	view.metres_per_px = METRES_ACROSS / maxf(view.size.x, 1.0)
	var here := MapData.biome_name(Biome.current) if Biome.current != &"" else "The Wilds"
	if _zone.text != here:
		_zone.text = here
	var t := "%s  %s" % [DayNight.part_of_day(), DayNight.clock_text()]
	if _clock.text != t:
		_clock.text = t


## The ring: bronze, lit on its upper left, with an N plaque at the top.
func _draw_ring() -> void:
	var c := view.position + view.size / 2.0
	var r := view.size.x / 2.0
	_ring.draw_arc(c, r + 3.0, 0.0, TAU, 96, BRONZE_DARK, 9.0, true)
	_ring.draw_arc(c, r + 3.0, 0.0, TAU, 96, BRONZE, 6.0, true)
	_ring.draw_arc(c, r + 4.0, PI * 0.9, PI * 1.6, 48, BRONZE_LIGHT, 2.0, true)
	_ring.draw_arc(c, r, 0.0, TAU, 96, BRONZE_DARK, 1.5, true)
	var n := c + Vector2(0, -r - 3.0)
	_ring.draw_circle(n, 10.0, BRONZE_DARK)
	_ring.draw_circle(n, 8.5, BRONZE)
	var w := _font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_ring.draw_string(_font, n + Vector2(-w / 2.0, 4.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.92, 0.7))
