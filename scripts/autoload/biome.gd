extends Node
## Which biome you're in, and what that does: blends the light toward its BiomeMood (DayNightSky
## reads fog_density, fog_tint, ambient and sun_tint from here and multiplies the time of day's
## values by them, and grades the image with its mist and tints; saturation is set here),
## and announces it with a title card (its ambience bed is played by the Ambience autoload). The first visit says "Discovered" (saved); later ones get a smaller card, at
## most once a minute per biome. You have to be in a new biome for HOLD seconds before it counts,
## so walking along a border doesn't flicker.
## Biomes are told apart by where you are (WorldMap's shapes), not by the ground under you, so
## the roads and paths take on whichever biome they pass through.

signal changed(id: StringName)

const MOODS := {
	&"clearing": preload("res://data/biomes/clearing.tres"),
	&"hearthvale": preload("res://data/biomes/hearthvale.tres"),
	&"stillwater": preload("res://data/biomes/stillwater.tres"),
	&"pinewood": preload("res://data/biomes/pinewood.tres"),
	&"quarry": preload("res://data/biomes/quarry.tres"),
	&"goldmeadow": preload("res://data/biomes/goldmeadow.tres"),
	&"frostpeak": preload("res://data/biomes/frostpeak.tres"),
	&"mine": preload("res://data/biomes/mine.tres"),
}
## Anywhere below this height is the mine (plans/mine.md): its levels are built far under the
## quarry (Mine.LEVEL_Y).
const MINE_BELOW := -25.0
const HOLD := 1.5
## Seconds for the light to settle into a new biome.
const BLEND := 3.0
const REPEAT_COOLDOWN := 60.0
const SAMPLE_EVERY := 0.2
## Fog in the quarry thickens toward the floor: up to this many times its mood's at the bottom.
const QUARRY_DEPTH_FOG := 2.0

## The quarry pit the depth fog measures from: its rim's height and how deep it goes.
var quarry_rim_height := WorldMap.QUARRY_RIM_HEIGHT
var quarry_depth := WorldMap.QUARRY_LEVEL_DROP * WorldMap.QUARRY_WALLS.size()
## The biome you're in (&"" between them, in the wild hills: plain light, no card).
var current: StringName = &""
var discovered: Dictionary[StringName, bool] = {}
# the blended mood, read by DayNightSky
var fog_density := 1.0
var fog_tint := Color.WHITE
var ambient := 1.0
var sun_tint := Color.WHITE
var saturation := 1.0
var mist := 1.0
var shadow_tint := Color.WHITE
var highlight_tint := Color.WHITE

var _candidate: StringName = &""
var _candidate_time := 0.0
var _sample := 0.0
var _last_card: Dictionary[StringName, float] = {}
## 0..1: how loud the ambience plays (a cutscene ducks it to hush the world; Ambience reads it).
var ambience_duck := 1.0
var _card: Control
var _title: Label
var _subtitle: Label
var _card_tween: Tween


func _ready() -> void:
	SaveGame.register(&"biomes", self)
	_build_card()


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	_sample -= delta
	if _sample <= 0.0:
		_sample = SAMPLE_EVERY
		var here := biome_at(player.global_position)
		if here != _candidate:
			_candidate = here
			_candidate_time = 0.0
	_candidate_time += delta
	if _candidate != current and _candidate_time >= HOLD:
		_enter(_candidate)
	_blend(delta, player.global_position)


## Which biome a world position is in, by WorldMap's shapes (first match wins).
func biome_at(p: Vector3) -> StringName:
	if p.y < MINE_BELOW:
		return &"mine"
	var w := Vector2(p.x, p.z)
	if w.distance_to(WorldMap.QUARRY_CENTER) < WorldMap.QUARRY_WALLS[0] + WorldMap.QUARRY_APRON + 8.0:
		return &"quarry"
	if w.distance_to(WorldMap.PEAK_CENTER) < 55.0:  # (not by height: the rim hills climb as high)
		return &"frostpeak"
	var q := WorldMap.biome_warp(w)  # (the shapes the ground is painted by)
	if q.distance_to(WorldMap.FIELD_CENTER) < WorldMap.FIELD_RADIUS + 12.0:
		return &"goldmeadow"
	if ((q - WorldMap.FOREST_CENTER) / WorldMap.FOREST_RADII).length() < 1.0:
		return &"pinewood"
	if w.distance_to(WorldMap.VILLAGE_CENTER) < WorldMap.VILLAGE_RADIUS + 10.0:
		return &"hearthvale"
	if w.distance_to(WorldMap.LAKE_CENTER) < 55.0:
		return &"stillwater"
	if w.distance_to(WorldMap.CLEARING_CENTER) < 40.0:
		return &"clearing"
	return &""


func _enter(id: StringName) -> void:
	current = id
	changed.emit(id)
	if id == &"":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not discovered.has(id):
		discovered[id] = true
		SaveGame.mark_dirty()
		_show_card(MOODS[id], true)
		_last_card[id] = now
	elif now - _last_card.get(id, -INF) > REPEAT_COOLDOWN:
		_show_card(MOODS[id], false)
		_last_card[id] = now


## Straight into the biome at `at` with its light already settled (after a fade: into the mine
## and back out), the card shown as usual.
func settle(at: Vector3) -> void:
	_candidate = biome_at(at)
	_candidate_time = HOLD
	if _candidate != current:
		_enter(_candidate)
	for i in 40:
		_blend(1.0, at)


## Eases the light toward the current biome's.
func _blend(delta: float, at: Vector3) -> void:
	var target: BiomeMood = MOODS.get(current)
	var k := 1.0 - exp(-delta * 3.0 / BLEND)  # most of the way there in BLEND seconds
	var density := target.fog_density if target else 1.0
	if current == &"quarry":  # thicker toward the floor
		var depth := clampf((quarry_rim_height - at.y) / quarry_depth, 0.0, 1.0)
		density *= lerpf(1.0, QUARRY_DEPTH_FOG, depth)
	fog_density = lerpf(fog_density, density, k)
	fog_tint = fog_tint.lerp(target.fog_tint if target else Color.WHITE, k)
	ambient = lerpf(ambient, target.ambient if target else 1.0, k)
	sun_tint = sun_tint.lerp(target.sun_tint if target else Color.WHITE, k)
	saturation = lerpf(saturation, target.saturation if target else 1.0, k)
	mist = lerpf(mist, target.mist if target else 1.0, k)
	shadow_tint = shadow_tint.lerp(target.shadow_tint if target else Color.WHITE, k)
	highlight_tint = highlight_tint.lerp(target.highlight_tint if target else Color.WHITE, k)
	var world := get_viewport().find_world_3d()
	var env := world.environment if world else null
	if env:
		env.adjustment_enabled = true
		env.adjustment_saturation = saturation


# --- the card -----------------------------------------------------------------------------------

func _build_card() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_card = VBoxContainer.new()
	_card.anchor_right = 1.0
	_card.anchor_top = 0.18
	_card.anchor_bottom = 0.18
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	layer.add_child(_card)
	_title = _label(56)
	_subtitle = _label(22)
	_subtitle.modulate = Color(1, 1, 1, 0.8)


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(label)
	return label


## Takes the title card off screen now (a cutscene starting).
func hide_card() -> void:
	if _card_tween:
		_card_tween.kill()
	_card.modulate.a = 0.0


func _show_card(mood: BiomeMood, first: bool) -> void:
	_title.text = mood.display_name
	_title.add_theme_font_size_override("font_size", 46 if first else 34)
	_subtitle.text = "Discovered" if first else mood.subtitle
	_subtitle.add_theme_font_size_override("font_size", 24 if first else 18)
	if first:
		Music.play_cue(&"discovery")
	else:
		Music.play_cue(&"return")
	if _card_tween:
		_card_tween.kill()
	_card.modulate.a = 0.0
	_card_tween = create_tween()
	_card_tween.tween_property(_card, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)
	_card_tween.tween_interval(2.5 if first else 1.6)
	_card_tween.tween_property(_card, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE)


# --- saving -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"discovered": discovered.keys().map(func(id: StringName) -> String: return String(id))}


func from_dict(d: Dictionary) -> void:
	discovered.clear()
	for id in d.get("discovered", []):
		discovered[StringName(id)] = true
