class_name Home
extends Building
## Your home (plans/home.md): a Building with no villager, upgraded from its plans (HomePlans, E
## on the board or the table: the usual upgrade panel). It starts as a tent on the village's west
## rim, facing the sunsets. Tiers: Tent, Cabin (and more to come).
## Its markers: Plans (the upgrade board), Bed (E to sleep: SleepSpot), DogBed (where the dog
## sleeps the night), Wake (where you stand up in the morning).
## Sleeping: the tent's bedroll only after midnight, a real bed from dusk, never by day. The screen
## fades, the world skips honestly to first light (the clock jumps; whatever regrows on a timer
## moves on by the same time; the villagers' day carries on from the clock), the game saves, and
## you wake by the bed with the dog there.

signal slept(full_night: bool)

## You wake at first light.
const WAKE_HOUR := 6.0
## A bed (tier 2 up) from dusk; before that only the small hours (the tent's bedroll).
const BED_FROM := 20.0
const BEDROLL_FROM := 24.0
## In bed by then, it's a full night's sleep (well rested, plans/home.md).
const FULL_NIGHT_BY := 25.0
const FADE_OUT := 1.4
const FADE_IN := 1.8

var sleeping := false


func _ready() -> void:
	super()
	add_to_group("home")


func _use_mark(t: int, m: Marker3D) -> void:
	match String(m.name).get_slice(".", 0):
		"Plans":
			_tiers[t].add_child(HomePlans.make(m.transform, self))
		"Bed":
			_tiers[t].add_child(SleepSpot.make(m.transform, self))
		_:
			super(t, m)


## A lamp left lit for you after dark, till midnight or till you turn in (no villager to put it out).
func _windows_on() -> bool:
	return DayNight.is_night() and VillagerDay.evening_hours(DayNight.time) < 24.0 and not sleeping


## Whether you can turn in now: a bed from dusk, the bedroll after midnight, never by day.
func can_sleep() -> bool:
	var h := VillagerDay.evening_hours(DayNight.time)
	if h >= 24.0 + WAKE_HOUR - 0.25 or h < 12.0:
		return false  # day (and the last moments before first light)
	return h >= (BED_FROM if tier_shown >= 2 else BEDROLL_FROM)


## What the bed says when you can't sleep yet.
func not_yet() -> String:
	if not DayNight.is_night() and VillagerDay.evening_hours(DayNight.time) < 20.0:
		return "Not tired yet"
	return "The bedroll's for the small hours. Not before midnight." if tier_shown < 2 else "Not tired yet"


## Turn in: fade out, skip to first light, wake by the bed.
func sleep() -> void:
	if sleeping or not can_sleep():
		return
	sleeping = true
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.has_method("set_cutscene"):
		player.call("set_cutscene", true)
	var fade := _fade()
	await fade.create_tween().tween_property(fade.get_child(0), "modulate:a", 1.0, FADE_OUT).finished
	var went_at := VillagerDay.evening_hours(DayNight.time)
	skip_to_morning()
	_wake_up(player)
	slept.emit(went_at <= FULL_NIGHT_BY)
	SaveGame.save()
	await get_tree().create_timer(0.6).timeout
	await fade.create_tween().tween_property(fade.get_child(0), "modulate:a", 0.0, FADE_IN).finished
	fade.queue_free()
	if player and player.has_method("set_cutscene"):
		player.call("set_cutscene", false)
	sleeping = false


## The night passes: the clock jumps to first light, and whatever regrows on a timer moves on by
## the same time (ResourceNode.fast_forward).
func skip_to_morning() -> void:
	var morning := VillagerDay.time_at(WAKE_HOUR)
	var seconds := fposmod(morning - DayNight.time, 1.0) * DayNight.DAY_LENGTH
	DayNight.time = morning
	for n in get_tree().get_nodes_in_group("gatherable"):
		if n.has_method("fast_forward"):
			n.call("fast_forward", seconds)


## Standing up by the bed, the dog beside you.
func _wake_up(player: Node3D) -> void:
	var wake := mark("Wake")
	var at := wake.global_position if wake else global_position
	var ahead := wake.global_basis.z if wake else Vector3.BACK  # (a marker faces its +Z)
	if player and player.has_method("teleport"):
		player.call("teleport", at, at + Vector3(ahead.x, 0.0, ahead.z) * 3.0 + Vector3.UP * 1.5)
	var dog := get_tree().get_first_node_in_group("dog") as Node3D
	if dog:
		var side := Vector3(ahead.z, 0.0, -ahead.x).normalized()
		dog.global_position = at + side * 0.9
		dog.reset_physics_interpolation()


func _fade() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 90
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.02, 0.04)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	return layer
