extends Node
## Village projects (plans/projects.md): things you pay for to make the village prettier, pinned
## on the noticeboard by the green. Two kinds:
##   spots: decorations with set places round the green (benches, flower boxes, a well,
##     bunting, a fountain) and the mended footbridge; done ones are saved here, per world;
##   road lamps: one per road stretch not lit from the start (the Lamps autoload keeps which are
##     lit, so that's where a road project's "done" lives).
## A project opens with the town hall's tier (`hall`) and costs gathered goods. Some wait for
## something first (a SPOTS entry's sixth field, `needs`): another project done (so the doghouse
## grows in steps, plans/dog.md), &"dog" for having a dog, or &"slide" for the landslide's boulders
## all broken (plans/market.md); until then they aren't on the board.

## Paid for (not ticked off in the debug menu): VillageDecor builds it in view.
signal completed(id: StringName)
signal changed

## The decorations, in the board's order: [id, title, what it adds, cost, town hall tier, needs].
const SPOTS := [
	[&"benches", "Benches round the green", "Two more benches on the green: somewhere to sit when the lamps come on.", {&"wood": 10}, 1],
	[&"flower_boxes", "Flower boxes", "Planters full of flowers round the green.", {&"birch": 8, &"wheat": 6}, 1],
	[&"well", "A well on the green", "A stone well with a bucket on a rope. Someone will always be drawing water.", {&"ore": 20, &"wood": 15}, 2],
	[&"bunting", "Bunting", "Strings of little flags between the green's lamps.", {&"birch": 10, &"barley": 8}, 2],
	[&"fountain", "A fountain", "A little fountain on the green, splashing away.", {&"iron": 30, &"gold": 10, &"oak": 20}, 3],
	[&"footbridge", "Mend the footbridge", "Planks across the water, so you stop wading.", {&"oak": 30, &"iron": 10}, 3],
	[&"terrace", "A terrace at the bakery", "Tables and stools under a striped awning outside Rosa's bakery: breakfast in the morning sun.", {&"wood": 15, &"birch": 8, &"wheat": 6}, 2],
	[&"kennel", "A kennel for your dog", "A little wooden house by your door: somewhere of his own to sleep at night.", {&"wood": 15}, 1, &"dog"],
	[&"kennel_paint", "Paint it and hang his name", "Cream walls, a red roof and a sign over the door with his name on it.", {&"birch": 10, &"wheat": 6, &"barley": 4}, 1, &"kennel"],
	[&"market", "A market stall", "A stall on the green with a striped awning, where you can swap what you have plenty of for what you need.", {&"wood": 20, &"birch": 10, &"wheat": 8}, 1],
	# the village's fixtures (plans/world-pass.md, phase 5): Fixture shows each one put right
	[&"mend_granary", "Mend the granary", "Straighten the old granary on its stones and patch its walls, so the grain keeps dry.", {&"wood": 15, &"oak": 8, &"ore": 6}, 1],
	[&"restore_barn", "Restore the old barn", "New planks and doors for the barn by the farm yard, and hay stacked to the rafters.", {&"wood": 30, &"pine": 15, &"wheat": 10}, 2],
	[&"open_cottage", "Open up an empty cottage", "Air out the shuttered cottage north of the green, light a fire and hang flower boxes: ready for a newcomer.", {&"wood": 20, &"birch": 10, &"iron": 4}, 2],
	# the new places (phase 7)
	[&"mill_wheel", "Mend the mill wheel", "New paddles for the watermill's wheel below the village, so it turns again and the miller can grind.", {&"oak": 20, &"iron": 10, &"wood": 15}, 2],
	[&"orchard_wall", "Mend the orchard wall", "Lay the fallen stones of the orchard's wall back up, so the sheep stay out of the apples.", {&"ore": 25, &"wood": 8}, 1],
	[&"retaining_wall", "Shore up the road east", "A timber wall to hold the slope back, so the landslide's road stays open and traders can come over the pass. Dig out the boulders first.", {&"wood": 25, &"pine": 15, &"iron": 6}, 2, &"slide"],
	[&"kennel_porch", "A bowl, a blanket and a porch", "A deck out front with a rail, a water bowl and a checked blanket to flop on.", {&"oak": 12, &"iron": 4}, 2, &"kennel_paint"],
	# the mine under the quarry (plans/mine.md): "mine:" needs are the Mine's (a shaft dug into,
	# an obstacle seen)
	[&"mine_shoring", "Shore up the old mine", "Timber frames and lamps at the boarded mouth on the quarry floor, so you can go in and dig.", {&"wood": 25, &"pine": 10, &"ore": 10}, 1],
	[&"mine_supports", "Prop up the roof fall", "Timber supports under the fallen roof on the mine's first level, and the rubble cleared, so you can get past.", {&"wood": 30, &"pine": 15}, 1, &"mine:collapse"],
	[&"mine_lift", "A lift down the shaft", "A winch, a rope and a wooden cage in the shaft you dug into, down to the mine's second level.", {&"wood": 40, &"iron": 15, &"coal": 10}, 2, &"mine:shaft"],
	[&"mine_shoring_2", "Shore up the second level", "Frames and lamps all through the mine's second level.", {&"pine": 25, &"wood": 15, &"iron": 10}, 2, &"mine_lift"],
	[&"mine_pump", "A pump for the flooded tunnel", "A hand pump and a pipe up the shaft to drain the flooded tunnel on the second level.", {&"iron": 25, &"wood": 20, &"ore": 15}, 2, &"mine:flood"],
	[&"mine_lift_3", "Lengthen the lift", "More rope and a deeper shaft: the lift goes down to the third level.", {&"iron": 30, &"gold": 10, &"pine": 20}, 3, &"mine_pump"],
	[&"mine_shoring_3", "Shore up the third level", "Frames and lamps through the deep level, among the crystals.", {&"pine": 30, &"iron": 12, &"gold": 6}, 3, &"mine_lift_3"],
	[&"mine_rails", "Rails and a minecart", "Rails from the mine's way in down to the deepest level the lift reaches, and a cart to ride them.", {&"iron": 40, &"wood": 30, &"coal": 15}, 2, &"mine_lift"],
]
## Road lamps: a stretch near the village (one that keeps within NEAR_VILLAGE m of the green on
## average: PathLamps) is cheaper and opens at once; the far roads wait for the town hall's second tier.
const NEAR_VILLAGE := 140.0
const ROAD_NEAR := {&"wood": 10, &"ore": 5, &"coal": 3}
const ROAD_FAR := {&"wood": 15, &"iron": 8, &"coal": 5}
const ROAD_PREFIX := "lamps:"

var _done: Dictionary[StringName, bool] = {}
## Whether this world has somewhere for the footbridge (set by VillageDecor): if not, it isn't
## on the board.
var footbridge_here := false


func _ready() -> void:
	SaveGame.register(&"projects", self)
	Lamps.changed.connect(changed.emit)
	Companion.adopted.connect(changed.emit)  # (the kennel goes up on the board)


## Every project of this world, in the board's order: {id, title, blurb, cost, hall, done, road}
## (road: the stretch id, or &"" for a decoration).
func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in SPOTS:
		if s[0] == &"footbridge" and not footbridge_here:
			continue
		if s.size() > 5 and not _needs_met(s[5]):
			continue
		out.append({"id": s[0], "title": s[1], "blurb": s[2], "cost": _cost(s[0], s[3]), "hall": s[4],
				"done": _done.has(s[0]), "road": &""})
	for s in Lamps.stretches:
		if s["id"] in Lamps.DEFAULT_LIT:
			continue
		var near := float(s.get("closest", INF)) < NEAR_VILLAGE
		out.append({"id": StringName(ROAD_PREFIX + String(s["id"])), "title": "Lamps along " + _lower_first(s["title"]),
				"blurb": "Lamp posts all along it, lit at dusk.", "cost": _cost(&"", ROAD_NEAR if near else ROAD_FAR),
				"hall": 1 if near else 2, "done": Lamps.is_lit(s["id"]), "road": s["id"]})
	return out


func _needs_met(need: StringName) -> bool:
	if String(need).begins_with("mine:"):
		var mine := get_tree().get_first_node_in_group("mine")
		return mine != null and mine.call("need_met", need)
	if need == &"dog":
		return Companion.has_dog
	if need == &"slide":  # every boulder of the landslide broken
		var slide := get_tree().get_first_node_in_group("landslide")
		return slide != null and slide.call("cleared")
	return _done.has(need)


## What a project costs now: less with the town hall's notice-board lamp (project_discount), and
## the mine's timber less again with the woodcutter's timber slide (mine_timber). Never below 1.
func _cost(id: StringName, base: Dictionary) -> Dictionary:
	var off := Village.stat(&"project_discount")
	var timber := Village.stat(&"mine_timber") if String(id).begins_with("mine_") else 0.0
	var out := {}
	for item: StringName in base:
		var k := 1.0 - off - (timber if item in [&"wood", &"pine", &"oak", &"birch"] else 0.0)
		out[item] = maxi(roundi(base[item] * k), 1)
	return out


static func _lower_first(t: String) -> String:
	return t.left(1).to_lower() + t.substr(1)


func get_project(id: StringName) -> Dictionary:
	for p in all():
		if p["id"] == id:
			return p
	return {}


func is_done(id: StringName) -> bool:
	if String(id).begins_with(ROAD_PREFIX):
		return Lamps.is_lit(StringName(String(id).trim_prefix(ROAD_PREFIX)))
	return _done.has(id)


## The town hall isn't high enough yet.
func is_locked(id: StringName) -> bool:
	var p := get_project(id)
	return p.is_empty() or Village.tier(Village.TOWN_HALL) < int(p["hall"])


func can_pay(id: StringName) -> bool:
	var p := get_project(id)
	return not p.is_empty() and not p["done"] and not is_locked(id) and Inventory.has_all(p["cost"])


## Pays for `id` and has it built. False (and nothing spent) if it isn't open or affordable.
func pay(id: StringName) -> bool:
	if not can_pay(id) or not Inventory.spend(get_project(id)["cost"]):
		return false
	_finish(id, true, true)
	SaveGame.save()  # progress worth keeping right away
	return true


## Debug: done or not, for free.
func set_done(id: StringName, on: bool) -> void:
	if on != is_done(id):
		_finish(id, on)


func _finish(id: StringName, on: bool, paid := false) -> void:
	if String(id).begins_with(ROAD_PREFIX):
		Lamps.set_lit(StringName(String(id).trim_prefix(ROAD_PREFIX)), on)
	elif on:
		_done[id] = true
	else:
		_done.erase(id)
	SaveGame.mark_dirty()
	if paid:
		completed.emit(id)
	changed.emit()


func to_dict() -> Dictionary:
	var ids: Array[String] = []
	for id in _done:
		ids.append(String(id))
	return {"done": ids}


func from_dict(d: Dictionary) -> void:
	_done.clear()
	for id in d.get("done", []):
		_done[StringName(id)] = true
	changed.emit()
