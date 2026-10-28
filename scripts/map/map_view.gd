class_name MapView
extends Control
## A window onto the world on parchment (shaders/map_parchment.gdshader), with the ink drawn on
## top: biome names, the village's buildings, and the player as a gold arrow. North is up (−Z).
## The Minimap and the WorldMapScreen are each one of these. Shows plain paper until MapData is
## built.

const SHADER := preload("res://shaders/map_parchment.gdshader")
const INK := Color(0.28, 0.18, 0.1)
const PAPER := Color(0.92, 0.84, 0.66)
const ARROW := Color(1.0, 0.82, 0.3)

## The world point at the middle, and how many metres one pixel covers.
var center := Vector2.ZERO
var metres_per_px := 1.0
## Clip to a circle (the minimap).
var circular := false
## Burnt, darkened edges (the big map).
var vignette := 0.0
## Write the biome names, and how big.
var show_labels := true
var label_size := 22
var data: MapData

var _paper: ColorRect
var _ink: Control
var _font: SystemFont


func _init() -> void:
	clip_contents = true
	_paper = ColorRect.new()
	_paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_paper.material = mat
	add_child(_paper)
	_ink = Control.new()
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.draw.connect(_draw_ink)
	add_child(_ink)
	_font = map_font()


## The map's lettering: a book serif, as an old map would be inked.
static func map_font(bold := false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Cambria", "Times New Roman", "serif"])
	f.font_weight = 700 if bold else 400
	return f


func _process(_delta: float) -> void:
	if data == null or not is_instance_valid(data):
		data = get_tree().get_first_node_in_group("map_data") as MapData
	var mat := _paper.material as ShaderMaterial
	if data and data.is_built:
		mat.set_shader_parameter("height_tex", data.height_tex)
		mat.set_shader_parameter("kind_tex", data.kind_tex)
		mat.set_shader_parameter("kind_smooth", data.kind_tex)
		mat.set_shader_parameter("world_rect", Vector4(data.rect.position.x, data.rect.position.y, data.rect.size.x, data.rect.size.y))
		mat.set_shader_parameter("height_range", data.height_range)
	mat.set_shader_parameter("view_center", center)
	mat.set_shader_parameter("metres_per_px", metres_per_px)
	mat.set_shader_parameter("view_px", size)
	mat.set_shader_parameter("circular", circular)
	mat.set_shader_parameter("vignette", vignette)
	mat.set_shader_parameter("ink_scale", 1.0 if metres_per_px < 1.5 else 1.4)
	_ink.queue_redraw()


func world_to_px(p: Vector2) -> Vector2:
	return size / 2.0 + (p - center) / metres_per_px


func px_to_world(px: Vector2) -> Vector2:
	return center + (px - size / 2.0) * metres_per_px


func _visible_px(px: Vector2, margin: float) -> bool:
	if circular:
		return px.distance_to(size / 2.0) < minf(size.x, size.y) / 2.0 - margin
	return Rect2(Vector2.ZERO, size).grow(-margin).has_point(px)


func _draw_ink() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# the village: a little house for each building
	var house := clampf(6.0 / metres_per_px, 4.0, 9.0)
	for b in tree.get_nodes_in_group("building"):
		var n := b as Node3D
		if n == null or not n.is_visible_in_tree():
			continue
		var px := world_to_px(Vector2(n.global_position.x, n.global_position.z))
		if _visible_px(px, house):
			_draw_house(px, house)
	var player := tree.get_first_node_in_group("player") as Node3D
	var me := world_to_px(Vector2(player.global_position.x, player.global_position.z)) if player else Vector2.INF
	# the biomes' names, each moved a line up or down if it would cover another or you, else left out
	if show_labels and data and data.is_built:
		var taken: Array[Rect2] = []
		if player:
			taken.append(Rect2(me - Vector2(14, 14), Vector2(28, 28)))
		for l in data.labels:
			var px := world_to_px(l["pos"])
			if not _visible_px(px, 20.0):
				continue
			var text := _spaced(String(l["text"]).to_upper())
			var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
			for dy: float in [0.0, label_size * 1.3, -label_size * 1.3]:
				var box := Rect2(px + Vector2(-w / 2.0, dy - label_size * 0.7), Vector2(w, label_size * 1.2))
				if taken.all(func(r: Rect2) -> bool: return not r.intersects(box)):
					taken.append(box)
					_draw_label(text, px + Vector2(0, dy), label_size)
					break
	# you
	if player:
		var fwd := -player.global_basis.z
		_draw_arrow(me, atan2(fwd.x, -fwd.z), 9.0 if circular else 11.0)


## Capitals spaced out a little, as an engraver would letter a region (thin spaces between).
static func _spaced(text: String) -> String:
	return " ".join(text.split(""))


func _draw_house(at: Vector2, s: float) -> void:
	var body := Rect2(at + Vector2(-s * 0.5, -s * 0.15), Vector2(s, s * 0.65))
	_ink.draw_rect(body, PAPER)
	_ink.draw_rect(body, INK, false, 1.2)
	var roof := PackedVector2Array([at + Vector2(-s * 0.7, -s * 0.1), at + Vector2(0, -s * 0.75), at + Vector2(s * 0.7, -s * 0.1)])
	_ink.draw_colored_polygon(roof, INK)


## A name in ink (already spaced: _spaced), with a haze of paper round it so it reads over any ground.
func _draw_label(text: String, at: Vector2, font_size: int) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := at - Vector2(w / 2.0, -font_size * 0.35)
	_ink.draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(PAPER, 0.8))
	_ink.draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)


## The player: a gold arrowhead pointing the way you face (`angle`: 0 = north, clockwise).
func _draw_arrow(at: Vector2, angle: float, s: float) -> void:
	var pts := PackedVector2Array([Vector2(0, -s), Vector2(s * 0.7, s * 0.8), Vector2(0, s * 0.35), Vector2(-s * 0.7, s * 0.8)])
	var t := Transform2D(angle, at)
	for i in pts.size():
		pts[i] = t * pts[i]
	_ink.draw_colored_polygon(pts, ARROW)
	pts.append(pts[0])
	_ink.draw_polyline(pts, INK, 1.6, true)
