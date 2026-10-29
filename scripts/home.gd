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
## Trophies (plans/trophies.md): days between a feather (or a shell) and the next, the shell gone
## by noon, the dog's stick a few days after he's yours (and now and then after that).
const FIND_EVERY := Vector2i(2, 3)
const SHELL_GONE := 12.0
const STICK_AFTER := 5
const STICK_AGAIN := 0.05
const STICK_NEAR := 6.0
const REACT := {
	2: "A cabin! Four walls and a roof. Look at you.",
	3: "A hearth and a desk, and that wall's begging for something to hang on it. You're one of us now.",
	4: "Two storeys and a porch! I'll need a sit-down after those stairs.",
}
const REACT_ADDON := {
	&"swing": "A porch swing! Save me a seat for the sunset.",
	&"garden": "Look at your beans coming up. My gran grew beans just like those.",
}
## What they say on a visit about a trophy on your wall they haven't seen yet (plans/trophies.md):
## per villager, per kind; anyone else, TROPHY_ANY.
const TROPHY_LINES := {
	&"fisher": {&"fish": "Is that the %s? Everyone said it was a story. Look at the size of it!"},
	&"woodcutter": {&"log": "Count those rings. Older than my grandad's grandad, that tree."},
	&"prospector_cottage": {&"geode": "Sapphire! The cleanest I've seen this side of the peak."},
	&"smithy": {&"stick": "Finest stick in the valley. I'd know, I've seen him fetch it."},
	&"baker_cottage": {&"sheaf": "A golden sheaf! My gran said they bring a good harvest."},
	&"town_hall": {&"feather": "An eagle's feather from the peak. You climbed all that way?"},
}
const TROPHY_ANY := "Well now, %s! Where did you find that?"
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
var _wall_done := false  # the mayor's note for a full wall has been left
var _framed := false  # ...read, and hung by the door
var _frame_node: Node3D
## Trophies out in the world (plans/trophies.md): the peak's feather and the lake's shell where
## they lie (kind -> [x, y, z], saved), the days the next ones come, and the dog's stick.
var _finds: Dictionary = {}
var _find_nodes: Dictionary = {}
var _next_find := {"feather": 1, "shell": 1}
var _dog_day := -1  # the first day you had your dog
var _stick_due := false


func _ready() -> void:
	super()
	add_to_group("home")
	rested = false  # (a static: not carried over from another world)
	Trophies.clear()  # (so are the trophies)
	SaveGame.register(&"home", self)
	slept.connect(_on_slept)
	add_to_group("trophies_listener")
	add_child(TrophyPanel.new())
	upgraded.connect(func(_t: int) -> void:  # (the desk and the step move with the tier)
		_place_note()
		_place_doorstep()
		_place_frame())
	DayNight.day_broke.connect(_on_morning)
	Village.addon_changed.connect(func(id: StringName, _s: int, _a: StringName) -> void:
		if id == def.id:
			_place_harvest.call_deferred())


func to_dict() -> Dictionary:
	return {"rested": rested, "note": _note, "doorstep": _doorstep, "day": _day, "next_visit": _next_visit,
			"porch_day": _porch_day, "seen": _seen, "harvest": _harvest, "trophies": Trophies.to_dict(),
			"finds": _finds, "next_find": _next_find, "dog_day": _dog_day, "stick_due": _stick_due,
			"wall_done": _wall_done, "framed": _framed}


func from_dict(d: Dictionary) -> void:
	rested = bool(d.get("rested", false))
	_note = d.get("note", {})
	_doorstep = d.get("doorstep", {})
	_day = int(d.get("day", 0))
	_next_visit = int(d.get("next_visit", 1))
	_porch_day = int(d.get("porch_day", -1))
	_seen = d.get("seen", {})
	_harvest = d.get("harvest", {})
	Trophies.from_dict(d.get("trophies", {}))
	_finds = d.get("finds", {})
	_next_find = d.get("next_find", _next_find)
	_dog_day = int(d.get("dog_day", -1))
	_stick_due = bool(d.get("stick_due", false))
	_wall_done = bool(d.get("wall_done", false))
	_framed = bool(d.get("framed", false))
	_place_frame.call_deferred()
	_place_finds.call_deferred()
	Trophies.adopt_old_logs.call_deferred()
	_place_note.call_deferred()
	_place_harvest.call_deferred()
	_place_doorstep.call_deferred()


func _process(delta: float) -> void:
	super(delta)
	_swing()
	_trophy_errands()
	if tier_shown < 2 or sleeping:
		return
	var h := VillagerDay.hours(DayNight.time)
	if _day >= _next_visit and h >= _visit_hour and h < VISIT_HOURS.y + 1.0:
		_next_visit = _day + (1 if Village.stat(&"visit_more") > 0.0 else randi_range(VISIT_EVERY.x, VISIT_EVERY.y))
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
		var trophy := _unseen_trophy(id)
		if new_tier:
			v.say(REACT.get(tier_shown, HELLO.pick_random()))
		elif new_addon:
			v.say(REACT_ADDON.get(built, HELLO.pick_random()))
		elif not trophy.is_empty():
			_seen[id + "#" + _key(trophy)] = true
			var line: String = TROPHY_LINES.get(v.building.def.id, {}).get(StringName(trophy["kind"]), TROPHY_ANY)
			v.say(line % Trophies.title(trophy).to_lower() if line.contains("%s") else line)
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
	if full_night or Village.stat(&"nap_rested") > 0.0:  # (the hearth: any sleep will do)
		rested = true
		var wake := mark("Wake")
		PopupText.spawn(get_parent(), (wake.global_position if wake else global_position) + Vector3.UP * 2.0,
				"Well rested", Color("ffe08a"), 12, FADE_IN)
	if _note.is_empty() and randf() < NOTE_CHANCE + Village.stat(&"note_more"):
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
		if _note.get("framed", false):  # (the mayor's: framed by the door)
			_framed = true
			_place_frame()
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
		var n when n.begins_with("TrophySlot") or n.begins_with("MantelSpot"):
			var p := TrophyPlaque.make(m.transform, n)
			_tiers[t].add_child(p)
			if not _looks.has(t):
				_looks[t] = []
			_looks[t].append(p)  # (its collision follows the tier's, like the look-at things)
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

## The garden's pickings each morning, a new day for the visits, and the trophies out in the
## world: a feather at the peak, a shell on the shore (every 2-3 days each).
func _on_morning() -> void:
	_day += 1
	for kind in [&"feather", &"shell"]:
		if _day >= int(_next_find.get(String(kind), 1)) and not _finds.has(String(kind)):
			var every := FIND_EVERY / 2 if kind == &"feather" and Village.stat(&"feather_more") > 0.0 else FIND_EVERY
			_next_find[String(kind)] = _day + randi_range(maxi(every.x, 1), maxi(every.y, 1))
			var at := _find_spot(kind)
			if at != Vector3.INF:
				_finds[String(kind)] = [at.x, at.y, at.z]
	if _dog_day >= 0 and not _stick_due and _day > _dog_day + STICK_AFTER and randf() < STICK_AGAIN:
		_stick_due = true  # (now and then another)
	_place_finds()
	_eel_trap()
	if Village.addon(def.id, 1) == &"garden" and Village.slot_open(def.id, 1) and _harvest.is_empty():
		_harvest = {"from": "your garden", "text": "Beans, a few heads of wheat, and a carrot the dog has his eye on.",
				"gift": {&"wheat": 3, &"barley": 2}, "prompt": "E  Pick what's ready in the garden"}
		_place_harvest()


## Ollie's eel traps (the fisher's add-on): a fish in them each morning, by his jetty.
func _eel_trap() -> void:
	if Village.stat(&"eel_trap") <= 0.0:
		return
	for b in get_tree().get_nodes_in_group("building"):
		if b.get("def") and (b.get("def") as BuildingDef).id == &"fisher" and b.has_method("addon_mark"):
			var m: Marker3D = b.call("addon_mark", "Harvest")
			if m and m.get_child_count() == 0:
				var fish: StringName = [&"perch", &"trout", &"perch", &"pike"].pick_random()
				var note := DeskNote.make(Vector3.ZERO, {"from": "the eel traps", "text": "Something in the traps this morning.",
						"gift": {fish: 1}, "prompt": "E  Take what's in the traps"})
				m.add_child(note)
				note.read.connect(note.queue_free)


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


# --- trophies out in the world (plans/trophies.md) ----------------------------------------------

## Where a feather (Frostpeak, near the summit) or a shell (on Stillwater's shore) turns up.
func _find_spot(kind: StringName) -> Vector3:
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain == null or terrain.get("data") == null:
		return Vector3.INF
	var data: Object = terrain.get("data")
	var a := randf() * TAU
	var dir := Vector2(cos(a), sin(a))
	if kind == &"feather":
		var p := WorldMap.PEAK_CENTER + dir * randf_range(8.0, 30.0)
		return Vector3(p.x, data.call("get_height", Vector3(p.x, 0, p.y)), p.y)
	for step in range(4, 120):  # out from the middle of the lake till the water's gone: the shore
		var p := WorldMap.LAKE_CENTER + dir * float(step)
		var at := Vector3(p.x, data.call("get_height", Vector3(p.x, 0, p.y)), p.y)
		if WaterBody.depth_at(get_tree(), at + Vector3.UP * 0.05) <= 0.0:
			return at + Vector3(dir.x, 0.0, dir.y) * 0.6
	return Vector3.INF


## The finds that are out, in the world (and gone once picked up).
func _place_finds() -> void:
	for kind in _finds:
		if is_instance_valid(_find_nodes.get(kind)):
			continue
		var p: Array = _finds[kind]
		var f := TrophyFind.make(Vector3(p[0], p[1], p[2]), StringName(kind))
		get_parent().add_child(f)
		_find_nodes[kind] = f
		f.picked.connect(func() -> void:
			_finds.erase(kind)
			SaveGame.mark_dirty())


## The shell's gone by noon; the dog's stick, once he's been yours a few days.
func _trophy_errands() -> void:
	if _finds.has("shell") and VillagerDay.hours(DayNight.time) >= SHELL_GONE and VillagerDay.hours(DayNight.time) < 20.0:
		_finds.erase("shell")
		if is_instance_valid(_find_nodes.get("shell")):
			_find_nodes["shell"].queue_free()
	if not Companion.has_dog:
		return
	if _dog_day < 0:
		_dog_day = _day
		_stick_due = true
	if not _stick_due or _day < _dog_day + STICK_AFTER or DayNight.is_night():
		return
	var dog := get_tree().get_first_node_in_group("dog") as Node3D
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if dog and player and dog.global_position.distance_to(player.global_position) < STICK_NEAR:
		_stick_due = false
		Trophies.found(&"stick", dog.global_position)
		PopupText.spawn(get_parent(), dog.global_position + Vector3.UP * 0.6, "He won't let go till you take it",
				Trophies.FOUND_COLOR, 8, 1.0)
		SaveGame.mark_dirty()


# --- the trophy wall (plans/trophies.md) -------------------------------------------------------

## A trophy on your wall villager `id` hasn't remarked on yet, or {}.
func _unseen_trophy(id: String) -> Dictionary:
	for place in Trophies.hung:
		var r: Dictionary = Trophies.hung[place]
		if not _seen.has(id + "#" + _key(r)):
			return r
	return {}


static func _key(r: Dictionary) -> String:
	return "%s|%s|%s" % [r.get("kind"), r.get("species"), r.get("day")]


## Every place on the wall (and the mantel) filled: the mayor leaves a framed note, once.
func trophies_changed() -> void:
	var places := 0
	var filled := 0
	for m in marks(tier_shown):
		var n := String(m.name)
		if n.begins_with("TrophySlot") or n.begins_with("MantelSpot"):
			places += 1
			if Trophies.hung.has(n):
				filled += 1
	if places > 0 and filled == places and not _wall_done:
		_wall_done = true
		_note = {"from": "Mayor Hartwell", "framed": true,
				"text": "Hearthvale's proudest wall. Frame this, and hang it by your door. From all of us."}
		_place_note()


## The mayor's note, framed by the door once you've read it.
func _place_frame() -> void:
	if is_instance_valid(_frame_node):
		_frame_node.queue_free()
	_frame_node = null
	var at := mark("NoteFrame")
	if not _framed or at == null:
		return
	var frame := Node3D.new()
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.38, 0.03)
	box.mesh = mesh
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6b4a2e")
	box.material_override = wood
	frame.add_child(box)
	var paper := MeshInstance3D.new()
	var sheet := BoxMesh.new()
	sheet.size = Vector3(0.42, 0.3, 0.035)
	paper.mesh = sheet
	var white := StandardMaterial3D.new()
	white.albedo_color = DeskNote.PAPER
	paper.material_override = white
	frame.add_child(paper)
	var words := Label3D.new()
	words.text = "Hearthvale's proudest wall\n— Mayor Hartwell"
	words.pixel_size = 0.0011
	words.font_size = 40
	words.modulate = Color("4a3524")
	words.outline_size = 0
	words.position = Vector3(0, 0, 0.02)
	frame.add_child(words)
	at.add_child(frame)
	_frame_node = frame
