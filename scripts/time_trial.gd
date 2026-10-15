class_name TimeTrial
extends Node
## A timed lap of the ring road. Run through the gate and the clock starts; pass the checkpoint
## arches in order (the next one's pennants light up), then back through the gate to finish. Each
## arch shows your split against your best lap's. Stray far off the road, or go too long without
## a checkpoint, and the run quietly ends.
## Beat a medal time and its banner hangs on the gate for good. Best lap, its splits and the
## medals are saved.
## A child of RoadCourse, which says where things are along the road.

const CHIME := preload("res://audio/pickup.tres")
const FANFARE := preload("res://audio/level_up.wav")
const PLAYER_LAYER := 1 << 1
const MEDALS := ["", "Bronze", "Silver", "Gold"]
const MEDAL_COLORS := [Color.WHITE, Color("e88a2c"), Color("c9d0d8"), Color("f2cf4a")]
const AHEAD := Color("8fe388")
const BEHIND := Color("ff8a7a")

## Metres from the gate to each checkpoint arch, in order.
@export var checkpoints: Array[float] = [105.0, 214.0, 330.0, 455.0, 565.0, 680.0, 775.0, 905.0]
@export_group("Medal times (s)")
@export var bronze := 170.0
@export var silver := 125.0
@export var gold := 95.0
@export_group("Giving up")
## The run ends if you're this far from the road...
@export var off_road := 40.0
## ...or this long without reaching the next checkpoint.
@export var checkpoint_timeout := 40.0

var best_lap := 0.0
var best_splits: Array[float] = []
var medals := 0  # 0 none, 1 bronze, 2 silver, 3 gold

var _course: RoadCourse
var _gate: Prop
var _arches: Array[Prop] = []
var _running := false
var _start_us := 0
var _last_cp_us := 0
var _next := 0  # index of the next checkpoint; checkpoints.size() means the gate (finish)
var _splits: Array[float] = []
var _watch := 0.0
var _hud: CanvasLayer
var _clock: Label
var _info: Label
var _message: Label
var _message_tween: Tween


func _ready() -> void:
	_course = get_parent() as RoadCourse
	if not _course.is_node_ready():
		await _course.ready  # children are ready first; the road isn't measured yet
	_gate = _course.place(&"gate", 0.0)
	_add_trigger(0.0, -1)
	for i in checkpoints.size():
		_arches.append(_course.place(&"checkpoint", checkpoints[i]))
		_add_trigger(checkpoints[i], i)
	_build_hud()
	SaveGame.register(&"time_trial", self)
	_show_banners()
	_light_next()


func _process(delta: float) -> void:
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.006)
	if _running and _next < _arches.size():
		_set_glow(_arches[_next], pulse)
	if not _running:
		return
	_clock.text = _format(_now())
	_watch -= delta
	if _watch <= 0.0:  # a few times a second is plenty for giving up
		_watch = 0.25
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and _course.locate(player.global_position).y > off_road:
			_stop("Off the road: run abandoned")
		elif (Time.get_ticks_usec() - _last_cp_us) / 1e6 > checkpoint_timeout:
			_stop("Too slow to the next checkpoint: run abandoned")


## The gate (index -1) or checkpoint `i` was run through.
func _crossed(i: int) -> void:
	if i == -1:
		if _running and _next == checkpoints.size():
			_finish()
		else:
			_begin()  # a fresh start (or a restart, if you came back to the gate)
		return
	if not _running or i != _next:
		return  # out of order: doesn't count
	var t := _now()
	_splits.append(t)
	_next += 1
	_last_cp_us = Time.get_ticks_usec()
	Sfx.play(CHIME, 1.15 + 0.04 * i)
	_info.text = "Checkpoint %d / %d" % [_next, checkpoints.size()]
	if best_splits.size() > i:
		var d := t - best_splits[i]
		_say("%s%.2f s" % ["+" if d >= 0.0 else "-", absf(d)], BEHIND if d >= 0.0 else AHEAD, 2.0)
	_light_next()


func _begin() -> void:
	_running = true
	_start_us = Time.get_ticks_usec()
	_last_cp_us = _start_us
	_next = 0
	_splits.clear()
	_clock.visible = true
	_info.visible = true
	_info.text = "Checkpoint 0 / %d" % checkpoints.size()
	Sfx.play(CHIME, 0.9)
	_say("Go!", Color.WHITE, 1.0)
	_light_next()


func _finish() -> void:
	var t := _now()
	_running = false
	_light_next()
	var lines := ["Lap  %s" % _format(t)]
	if best_lap <= 0.0 or t < best_lap:
		lines.append("New best!" if best_lap > 0.0 else "First lap!")
		best_lap = t
		best_splits = _splits.duplicate()
	var earned := 3 if t <= gold else (2 if t <= silver else (1 if t <= bronze else 0))
	var color := Color.WHITE
	if earned > medals:
		medals = earned
		lines.append("%s medal! Its banner hangs on the gate." % MEDALS[earned])
		color = MEDAL_COLORS[earned]
		_show_banners(true)
	Sfx.play(FANFARE)
	SaveGame.mark_dirty()
	_clock.text = _format(t)
	_say("\n".join(lines), color, 5.0)
	_hide_clock_later()


func _stop(why: String) -> void:
	_running = false
	_light_next()
	_say(why, Color(1, 1, 1, 0.8), 2.5)
	_hide_clock_later()


func _now() -> float:
	return (Time.get_ticks_usec() - _start_us) / 1e6


func _hide_clock_later() -> void:
	await get_tree().create_timer(5.0).timeout
	if not _running:
		_clock.visible = false
		_info.visible = false


# --- the course ---------------------------------------------------------------------------------

func _add_trigger(at: float, index: int) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = PLAYER_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 6.0, 1.5)
	shape.shape = box
	shape.position = Vector3.UP * 2.5
	area.add_child(shape)
	area.transform = _course.frame_at(at)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body.is_in_group("player"):
			_crossed(index))
	_course.add_child(area)


## Only the next arch's pennants are lit, while a run is on.
func _light_next() -> void:
	for i in _arches.size():
		_set_glow(_arches[i], 0.8 if _running and i == _next else 0.0)


func _set_glow(arch: Prop, glow: float) -> void:
	var flags := arch.find_child("Flags", true, false) as GeometryInstance3D
	if flags:
		flags.set_instance_shader_parameter("glow", glow)


## The gate's banners for the medals won; `fresh` pops the newest one in.
func _show_banners(fresh := false) -> void:
	for i in 3:
		var banner := _gate.find_child(["BannerBronze", "BannerSilver", "BannerGold"][i], true, false) as Node3D
		if banner == null:
			continue
		banner.visible = medals > i
		if fresh and i == medals - 1:
			banner.scale = Vector3(1, 0.05, 1)
			banner.create_tween().tween_property(banner, "scale", Vector3.ONE, 0.6) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- hud ----------------------------------------------------------------------------------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_clock = _label(44, 70.0)
	_info = _label(20, 124.0)
	_message = _label(30, 156.0)
	_clock.visible = false
	_info.visible = false
	_message.modulate.a = 0.0


func _label(font_size: int, top: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.offset_top = top
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(label)
	return label


func _say(text: String, color: Color, hold: float) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	if _message_tween:
		_message_tween.kill()
	_message.modulate.a = 1.0
	_message_tween = create_tween()
	_message_tween.tween_interval(hold)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.5)


static func _format(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


# --- saving -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"best_lap": best_lap, "best_splits": best_splits, "medals": medals}


func from_dict(d: Dictionary) -> void:
	best_lap = float(d.get("best_lap", 0.0))
	best_splits.clear()
	for s in d.get("best_splits", []):
		best_splits.append(float(s))
	medals = int(d.get("medals", 0))
	if _gate:
		_show_banners()
