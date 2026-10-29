class_name Home
extends Building
## Your home (plans/home.md): a Building with no villager, upgraded from its plans (HomePlans, E
## on the board, the table or the desk: the usual upgrade panel). It starts as a tent on the
## village's west rim, facing the sunsets. Tiers: Tent, Cabin, Cottage, Homestead.
## Its markers: Plans (the upgrade board), Bed (E to sleep: SleepSpot), DogBed (where the dog
## sleeps the night), Wake (where you stand up in the morning).
## Sleeping: the tent's bedroll only after midnight, a real bed from dusk, never by day. The screen
## fades, the world skips honestly to first light (the clock jumps; whatever regrows on a timer
## moves on by the same time; the villagers' day carries on from the clock), the game saves, and
## you wake by the bed with the dog there.

## From the Cottage (tier 3): well rested after a full night in your own bed (extra XP till noon:
## Skills asks rested_bonus()), and some mornings a villager's note on the desk (HomeNotes,
## DeskNote, a small gift now and then). From the Homestead (tier 4): head home from the world
## map at dusk (head_home()). Both saved under "home".

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
## Well rested: this much extra XP, till noon.
const RESTED_BONUS := 0.15
const RESTED_TILL := 12.0
## How often a morning finds a note on the desk.
const NOTE_CHANCE := 0.6
## Head home from the map: only from the Homestead, only in the evening, from further than this.
const HEAD_HOME_FROM := 17.0
const HEAD_HOME_MIN := 30.0

## Villagers come to you (plans/home.md, from the Cabin): every few days one walks over by day
## and stays a moment; with you there they chat (and the first time they see a new tier, say so),
## without you they leave a little gift on the doorstep. From the Homestead, some evenings one of
## them sits on your porch for a while before the tavern.
const VISIT_EVERY := Vector2i(2, 3)  # days between visits
const VISIT_HOURS := Vector2(9.0, 15.0)  # when in the day they set off
const VISIT_TIME := 25.0  # seconds at your door
const VISIT_NEAR := 14.0  # you're "there" this close
const PORCH_CHANCE := 0.5
## The porch swing (an add-on): the day goes by this many times faster while you sit on it.
const SWING_SPEED := 4.0
const REACT := {
	2: "A cabin! Four walls and a roof. Look at you.",
	3: "A hearth and a desk, and that wall's begging for something to hang on it. You're one of us now.",
	4: "Two storeys and a porch! I'll need a sit-down after those stairs.",
}
const REACT_ADDON := {
	&"swing": "A porch swing! Save me a seat for the sunset.",
	&"garden": "Look at your beans coming up. My gran grew beans just like those.",
}
const HELLO := [
	"Thought I'd come and see how the place is coming along.",
	"You get the sunsets out here, don't you? Lucky.",
	"Your dog's got the right idea, lying in the sun like that.",
	"Just passing. Well, not really passing. I came to see you.",
]

## Well rested this morning (a full night in your own bed, from the Cottage).
static var rested := false

var sleeping := false
var _note: Dictionary = {}  # waiting on the desk (saved till you read it)
var _note_node: DeskNote
var _doorstep: Dictionary = {}  # a visitor's gift on the step (saved till you pick it up)
var _doorstep_node: DeskNote
var _day := 0  # mornings since the world began (counted here, for the visits)
var _next_visit := 1  # the day of the next visit
var _visit_hour := 11.0
var _porch_day := -1  # the last evening someone was asked to the porch
var _seen: Dictionary = {}  # villager (building id) -> the home's tier they last saw (and "<id>+" its add-on)
var _harvest: Dictionary = {}  # the garden's morning pickings, waiting in the crate (saved)
var _harvest_node: DeskNote
var _swinging := false


func _ready() -> void:
	super()
	add_to_group("home")
	rested = false  # (a static: not carried over from another world)
	SaveGame.register(&"home", self)
	slept.connect(_on_slept)
	upgraded.connect(func(_t: int) -> void:  # (the desk and the step move with the tier)
		_place_note()
		_place_doorstep())
	DayNight.day_broke.connect(_on_morning)
	Village.addon_changed.connect(func(id: StringName, _s: int, _a: StringName) -> void:
		if id == def.id:
			_place_harvest.call_deferred())


func to_dict() -> Dictionary:
	return {"rested": rested, "note": _note, "doorstep": _doorstep, "day": _day, "next_visit": _next_visit,
			"porch_day": _porch_day, "seen": _seen, "harvest": _harvest}


func from_dict(d: Dictionary) -> void:
	rested = bool(d.get("rested", false))
	_note = d.get("note", {})
	_doorstep = d.get("doorstep", {})
	_day = int(d.get("day", 0))
	_next_visit = int(d.get("next_visit", 1))
	_porch_day = int(d.get("porch_day", -1))
	_seen = d.get("seen", {})
	_harvest = d.get("harvest", {})
	_place_note.call_deferred()
	_place_harvest.call_deferred()
	_place_doorstep.call_deferred()


func _process(delta: float) -> void:
	super(delta)
	_swing()
	if tier_shown < 2 or sleeping:
		return
	var h := VillagerDay.hours(DayNight.time)
	if _day >= _next_visit and h >= _visit_hour and h < VISIT_HOURS.y + 1.0:
		_next_visit = _day + randi_range(VISIT_EVERY.x, VISIT_EVERY.y)
		_visit_hour = randf_range(VISIT_HOURS.x, VISIT_HOURS.y)
		send_visitor()
	if tier_shown >= 4 and _porch_day != _day and h >= VillagerDay.DUSK_FROM - 1.0 and h < VillagerDay.DUSK_FROM:
		_porch_day = _day
		if randf() < PORCH_CHANCE:
			ask_to_porch()


## The villagers who could come over now: about their day's work, not busy with anything else.
func _free_folk() -> Array[Villager]:
	var out: Array[Villager] = []
	for b in get_tree().get_nodes_in_group("building"):
		var v := b.get_node_or_null("Villager") as Villager
		if v and not b is Tavern and (b as Building).is_unlocked() and not v.busy():
			out.append(v)
	return out


## One of them walks over to see you. False if nobody's free (or there's nowhere to stand yet).
func send_visitor() -> bool:
	var spot := mark("Visit")
	var folk := _free_folk()
	if spot == null or folk.is_empty():
		return false
	folk.pick_random().visit_home(spot)
	return true


## One of them (not the keeper) spends the start of the evening on your porch (Villager, DUSK).
func ask_to_porch() -> bool:
	var folk: Array[Villager] = []
	for b in get_tree().get_nodes_in_group("building"):
		var v := b.get_node_or_null("Villager") as Villager
		if v and not b is Tavern and (b as Building).is_unlocked():
			folk.append(v)
	if folk.is_empty():
		return false
	folk.pick_random().porch_tonight = true
	return true


## A visitor got to your door: a word if you're there, else a gift on the step.
func visited(v: Villager) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var id := String(v.building.def.id)
	var here := player != null and player.global_position.distance_to(v.global_position) < VISIT_NEAR
	if here:
		var new_tier := int(_seen.get(id, 1)) < tier_shown
		var built := Village.addon(def.id, 1)
		var new_addon := built != &"" and StringName(_seen.get(id + "+", &"")) != built
		if new_tier:
			v.say(REACT.get(tier_shown, HELLO.pick_random()))
		elif new_addon:
			v.say(REACT_ADDON.get(built, HELLO.pick_random()))
		else:
			v.say(HELLO.pick_random())
		_seen[id] = tier_shown
		_seen[id + "+"] = built
	elif _doorstep.is_empty() and HomeNotes.GIFTS.has(v.building.def.id):
		var g: Array = HomeNotes.GIFTS[v.building.def.id]
		_doorstep = {"from": v.display_name(), "text": "Came by to see the place. Left you this.", "gift": {g[0]: g[1]}}
		_place_doorstep()
	SaveGame.mark_dirty()


func _place_doorstep() -> void:
	if is_instance_valid(_doorstep_node):
		_doorstep_node.queue_free()
	_doorstep_node = null
	var step := mark("Doorstep")
	if _doorstep.is_empty() or step == null:
		return
	_doorstep_node = DeskNote.make(step.position, _doorstep)
	step.get_parent().add_child(_doorstep_node)
	_doorstep_node.read.connect(func() -> void:
		_doorstep = {}
		SaveGame.mark_dirty())


## Extra XP while you're well rested (Skills.add_xp): from waking till noon.
static func rested_bonus() -> float:
	if not rested:
		return 0.0
	var h := VillagerDay.hours(DayNight.time)
	if h >= RESTED_TILL + Village.stat(&"rested_hours") or h < WAKE_HOUR - 0.5:  # (Rosa's bread oven)
		rested = false
		return 0.0
	return RESTED_BONUS


func _on_slept(full_night: bool) -> void:
	if tier_shown < 3:
		return
	if full_night:
		rested = true
		var wake := mark("Wake")
		PopupText.spawn(get_parent(), (wake.global_position if wake else global_position) + Vector3.UP * 2.0,
				"Well rested", Color("ffe08a"), 12, FADE_IN)
	if _note.is_empty() and randf() < NOTE_CHANCE:
		_note = HomeNotes.write(get_tree())
		_place_note()


## The note waiting on the desk of the tier on show (if there's one, and a desk).
func _place_note() -> void:
	if is_instance_valid(_note_node):
		_note_node.queue_free()
	_note_node = null
	var desk := mark("Desk")
	if _note.is_empty() or desk == null:
		return
	_note_node = DeskNote.make(desk.position, _note)
	desk.get_parent().add_child(_note_node)
	_note_node.read.connect(func() -> void:
		_note = {}
		SaveGame.mark_dirty())


## You can head home from the map now: the Homestead, an evening, and you're away.
func can_head_home() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var h := VillagerDay.evening_hours(DayNight.time)
	return tier_shown >= 4 and h >= HEAD_HOME_FROM and h < 24.0 and player != null \
			and player.global_position.distance_to(global_position) > HEAD_HOME_MIN


## Home for the evening: a fade, and you're on the porch, the dog beside you.
func head_home() -> void:
	if not can_head_home():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.call("set_cutscene", true)
	var fade := _fade()
	await fade.create_tween().tween_property(fade.get_child(0), "modulate:a", 1.0, FADE_OUT).finished
	var arrive := mark("Arrive")
	var at := arrive.global_position
	player.call("teleport", at, global_position + Vector3.UP * 1.5)
	var dog := get_tree().get_first_node_in_group("dog") as Node3D
	if dog:
		dog.global_position = at + arrive.global_basis.x * 0.9
		dog.reset_physics_interpolation()
	await get_tree().create_timer(0.3).timeout
	await fade.create_tween().tween_property(fade.get_child(0), "modulate:a", 0.0, FADE_IN).finished
	fade.queue_free()
	player.call("set_cutscene", false)


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


# --- the home's add-ons (plans/home.md) ------------------------------------------------------

## The garden's pickings each morning, and a new day for the visits.
func _on_morning() -> void:
	_day += 1
	if Village.addon(def.id, 1) == &"garden" and Village.slot_open(def.id, 1) and _harvest.is_empty():
		_harvest = {"from": "your garden", "text": "Beans, a few heads of wheat, and a carrot the dog has his eye on.",
				"gift": {&"wheat": 3, &"barley": 2}, "prompt": "E  Pick what's ready in the garden"}
		_place_harvest()


func _place_harvest() -> void:
	if is_instance_valid(_harvest_node):
		_harvest_node.queue_free()
	_harvest_node = null
	var crate := addon_mark("Harvest")
	if _harvest.is_empty() or crate == null:
		return
	_harvest_node = DeskNote.make(crate.position, _harvest)
	crate.get_parent().add_child(_harvest_node)
	_harvest_node.read.connect(func() -> void:
		_harvest = {}
		SaveGame.mark_dirty())


## Sitting on the porch swing: the day goes by faster (DayNight.speed) till you get up.
func _swing() -> void:
	var swing := addon_mark("PorchSeatSwing")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var on: bool = swing != null and player != null and player.get("seat") == swing
	if on != _swinging:
		_swinging = on
		DayNight.speed = SWING_SPEED if on else 1.0
