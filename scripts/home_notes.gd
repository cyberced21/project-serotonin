class_name HomeNotes
extends RefCounted
## The notes the villagers leave on your desk (plans/home.md, from the Cottage up): some mornings
## after a night in your own bed, one of them has been by. A thank-you for something you built, a
## gentle hint at what the village could do next, or a little gift. write() picks one.

## Each villager's little gift: what, how many, and how they put it.
const GIFTS := {
	&"woodcutter": [&"wood", 8, "A few logs I had spare. Dry ones, for your fire."],
	&"fisher": [&"perch", 2, "Two perch from this morning. The big one nearly had me in."],
	&"baker_cottage": [&"wheat", 6, "Some wheat from the last sack. And a crust for your dog, he's had it already."],
	&"smithy": [&"iron", 2, "Iron left over from a job. Too good to throw on the scrap pile."],
	&"prospector_cottage": [&"coal", 4, "A bit of coal. Burns cleaner than wood on a cold night."],
	&"town_hall": [&"gold", 1, "A small thank-you from the village. Don't tell the others it's gold."],
}


## A note from someone in the village: {"from": name, "text": ..., "gift": {item: count}}, or {}
## if there's nobody to write one yet.
static func write(tree: SceneTree) -> Dictionary:
	var folk := []
	for b in tree.get_nodes_in_group("building"):
		var def: BuildingDef = b.get("def")
		if b.get_node_or_null("Villager") and b.call("is_unlocked") and def.villager_name != "":
			folk.append(def)
	if folk.is_empty():
		return {}
	var def: BuildingDef = folk.pick_random()
	var kinds := ["gift", "hint", "thanks"]
	kinds.shuffle()
	for kind in kinds:
		var note := _note(kind, def, tree)
		if not note.is_empty():
			note["from"] = def.villager_name
			return note
	return {}


static func _note(kind: String, def: BuildingDef, _tree: SceneTree) -> Dictionary:
	match kind:
		"gift":
			if GIFTS.has(def.id):
				var g: Array = GIFTS[def.id]
				return {"text": g[2], "gift": {g[0]: g[1]}}
		"thanks":
			var built := []
			for p in Projects.all():
				if p["done"]:
					built.append(p)
			if not built.is_empty():
				var p: Dictionary = built.pick_random()
				return {"text": "Thank you for %s. I walk past it every day and it still makes me smile." % String(p["title"]).to_lower(),
						"gift": {}}
		"hint":
			var next := Village.next_tier(def.id)
			if next and not Village.is_capped(def.id):
				return {"text": "I've been dreaming about %s. If you've a few things to spare one day, come and see me." % _a(next.name),
						"gift": {}}
	return {}


## "a Log Cabin", "an Assay Office".
static func _a(thing: String) -> String:
	return ("an " if "AEIOU".contains(thing.left(1)) else "a ") + thing
