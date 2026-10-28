extends Node
## Which biome you're in, and what that does: blends the light toward its BiomeMood (DayNightSky
## reads fog_density, fog_tint, ambient and sun_tint from here and multiplies the time of day's
## values by them, and grades the image with its mist and tints; saturation is set here),
## crossfades its ambience loop, and announces it with a title card. The first visit says "Discovered" (saved); later ones get a smaller card, at
## most once a minute per biome. You have to be in a new biome for HOLD seconds before it counts,
## so walking along a border doesn't flicker.
## Biomes are told apart by where you are (WorldMap's shapes), not by the ground under you, so
## the ring road and paths take on whichever biome they pass through.

signal changed(id: StringName)

const MOODS := {
	&"clearing": preload("res://data/biomes/clearing.tres"),
	&"hearthvale": preload("res://data/biomes/hearthvale.tres"),
	&"stillwater": preload("res://data/biomes/stillwater.tres"),
	&"pinewood": preload("res://data/biomes/pinewood.tres"),
	&"quarry": preload("res://data/biomes/quarry.tres"),
	&"goldmeadow": preload("res://data/biomes/goldmeadow.tres"),
	&"frostpeak": preload("res://data/biomes/frostpeak.tres"),
}
const FIRST_STING := preload("res://audio/level_up.wav")
const STING := preload("res://audio/pickup.tres")
const HOLD := 1.5
## Seconds for the light and the ambience to settle into a new biome.
const BLEND := 3.0
const REPEAT_COOLDOWN := 60.0
const SAMPLE_EVERY := 0.2
## Fog in the quarry thickens toward the floor: up to this many times its mood's at the bottom.
const QUARRY_DEPTH_FOG := 2.0

## Replaces WorldMap's shapes when set: func(at: Vector3) -> StringName. A procgen world sets it.
var locator := Callable()
## The quarry pit the depth fog measures from: its rim's height and how deep it goes. The
## hand-built Greystone Quarry's unless a procgen world sets its own (see reset_quarry()).
var quarry_rim_height := WorldMap.QUARRY_RIM_HEIGHT
var quarry_depth := WorldMap.QUARRY_LEVEL_DROP * WorldMap.QUARRY_WALLS.size()
## The kind of each biome in a procgen world ("Birch Grove"), shown on its card in place of the
## mood's subtitle. Empty in the hand-built world.
var kind_names: Dictionary[StringName, String] = {}
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
var _beds: Dictionary[StringName, AudioStreamPlayer] = {}
## 0..1: how loud the ambience plays (a cutscene ducks it to hush the world).
var ambience_duck := 1.0
var _card: Control
var _title: Label
var _subtitle: Label
var _card_tween: Tween


func _ready() -> void:
	SaveGame.register(&"biomes", self)
	for id in MOODS:
		var mood: BiomeMood = MOODS[id]
		if mood.ambience:
			_beds[id] = _make_bed(mood.ambience)
	_build_card()


## Back to the hand-built world: its quarry (for the depth fog), and no biome kinds.
func reset_quarry() -> void:
	quarry_rim_height = WorldMap.QUARRY_RIM_HEIGHT
	quarry_depth = WorldMap.QUARRY_LEVEL_DROP * WorldMap.QUARRY_WALLS.size()
	kind_names.clear()


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


## Which biome a world position is in, by WorldMap's shapes (first match wins), or the locator's.
func biome_at(p: Vector3) -> StringName:
	if locator.is_valid():
		return locator.call(p)
	var w := Vector2(p.x, p.z)
	if w.distance_to(WorldMap.QUARRY_CENTER) < WorldMap.QUARRY_WALLS[0] + WorldMap.QUARRY_APRON + 8.0:
		return &"quarry"
	if w.distance_to(WorldMap.PEAK_CENTER) < 45.0 or p.y > 32.0:
		return &"frostpeak"
	if w.distance_to(WorldMap.FIELD_CENTER) < WorldMap.FIELD_RADIUS + 12.0:
		return &"goldmeadow"
	if ((w - WorldMap.FOREST_CENTER) / WorldMap.FOREST_RADII).length() < 1.0:
		return &"pinewood"
	if w.distance_to(WorldMap.VILLAGE_CENTER) < 70.0:
		return &"hearthvale"
	if w.distance_to(WorldMap.LAKE_CENTER) < 55.0:
		return &"stillwater"
	if w.distance_to(WorldMap.CLEARING_CENTER) < 70.0:
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
		_show_card(MOODS[id], true, kind_names.get(id, ""))
		_last_card[id] = now
	elif now - _last_card.get(id, -INF) > REPEAT_COOLDOWN:
		_show_card(MOODS[id], false, kind_names.get(id, ""))
		_last_card[id] = now


## Eases the light and the ambience toward the current biome's.
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
	for id in _beds:
		var bed := _beds[id]
		var full := db_to_linear((MOODS[id] as BiomeMood).ambience_db) * ambience_duck
		var level := lerpf(db_to_linear(bed.volume_db), full if id == current else 0.0, k)
		bed.volume_db = linear_to_db(maxf(level, 0.0001))


func _make_bed(stream: AudioStream) -> AudioStreamPlayer:
	var wav := stream as AudioStreamWAV
	if wav:  # a seamless loop; loop it without needing import settings
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	var bed := AudioStreamPlayer.new()
	bed.bus = &"Ambience"
	bed.stream = stream
	bed.volume_db = -80.0
	add_child(bed)
	bed.play()
	return bed


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


func _show_card(mood: BiomeMood, first: bool, kind := "") -> void:
	_title.text = mood.display_name
	_title.add_theme_font_size_override("font_size", 46 if first else 34)
	var what: String = kind if kind != "" else mood.subtitle
	_subtitle.text = (what + "  ·  Discovered" if kind != "" else "Discovered") if first else what
	_subtitle.add_theme_font_size_override("font_size", 24 if first else 18)
	if first:
		Sfx.play(FIRST_STING, 0.8, -13.0)
	else:
		Sfx.play(STING, 0.6, -17.0)
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
