class_name WorkYards
extends RefCounted
## Each worker's yard (plans/village-street.md, phase 5): the things they work at and the stations
## they move between by day, so they stay at their trade instead of wandering off to the green.
## Everything is in the building's own frame (+Z its front, toward the street), so it goes where the
## building goes. Building._ready builds its yard under a "Yard" node; Building.stations() lists
## the stations open at its tier, and Villager._pick_spot() walks between them during work hours.
##   props:    [model (models/village/yard/<name>.glb), offset (y: height, for the jetty), facing
##             (radians, a +Y turn: its front, +Z, that way), solid]
##   stations: [where they stand (y: the floor's height, for the jetty), facing, motion
##             (a Villager.Work name), the building tier that opens it]
## The forge is ours, painted from the palette; the rest keep their own materials.

const YARDS := {
	# the smith's yard, east of the smithy: forge, anvil, quench bucket, grindstone, the iron crate
	&"smithy": {
		"props": [[&"forge", Vector3(12.0, 0, -5.6), 0.0, true], [&"anvil_log", Vector3(10.8, 0, -0.8), PI / 2.0, true],
			[&"quench_bucket", Vector3(8.6, 0, -3.4), 0.0, false], [&"whetstone", Vector3(13.4, 0, 0.2), 0.0, true],
			[&"metal_crate", Vector3(8.4, 0, -6.6), 0.3, true]],
		"stations": [[Vector3(12.0, 0, -4.1), PI, &"STOKE", 1], [Vector3(10.8, 0, 0.4), PI, &"HAMMER", 1],
			[Vector3(8.6, 0, -2.2), PI, &"DUNK", 2], [Vector3(13.4, 0, 1.4), PI, &"GRIND", 3]],
	},
	# the woodcutter's yard, east of the lodge: chopping log, woodpile, saw bench
	&"woodcutter": {
		"props": [[&"chopping_log", Vector3(10.6, 0, -0.6), PI / 2.0, true], [&"woodpile", Vector3(12.6, 0, -4.6), 0.0, true],
			[&"workbench", Vector3(8.6, 0, -4.0), PI / 2.0, true], [&"axe", Vector3(11.9, 0, 0.7), 0.4, false]],
		"stations": [[Vector3(10.6, 0, 0.6), PI, &"CHOP", 1], [Vector3(12.6, 0, -2.8), PI, &"TEND", 1],
			[Vector3(9.8, 0, -4.0), -PI / 2.0, &"SAW", 2]],
	},
	# the fisher's jetty, 20 m west on the creek: the deck out over the water, a gutting table and the
	# drying rack on the bank (the hut faces the street, so west is its +X)
	&"fisher": {
		"props": [[&"jetty_deck", Vector3(23.2, 0, -2.4), PI / 2.0, true], [&"gutting_table", Vector3(18.4, 0, 1.1), 0.0, true],
			[&"fish_rack", Vector3(18.9, 0, -5.9), 0.0, true]],
		"stations": [[Vector3(24.8, 0.41, -2.4), PI / 2.0, &"FISH", 1], [Vector3(17.0, 0, 1.1), PI / 2.0, &"SORT", 1],
			[Vector3(18.9, 0, -4.95), PI, &"TEND", 2]],
	},
	# the prospector's sorting yard, between her cottage and the ore store
	&"prospector_cottage": {
		"props": [[&"workbench", Vector3(-12.3, 0, -1.6), 0.0, true], [&"stone_heap", Vector3(-15.0, 0, -3.6), 0.4, true],
			[&"tub", Vector3(-9.6, 0, -3.4), 0.0, true]],
		"stations": [[Vector3(-12.3, 0, -0.2), PI, &"SORT", 1], [Vector3(-15.0, 0, -2.3), PI, &"TEND", 1],
			[Vector3(-9.6, 0, -2.6), PI, &"DUNK", 2]],
	},
	# Rosa's yard, beside the bakery on the market place: the dough table, the flour, the oven's wood
	&"baker_cottage": {
		"props": [[&"table_large", Vector3(-11.0, 0, -2.4), 0.0, true], [&"flour_sack", Vector3(-13.4, 0, 0.6), 0.6, false],
			[&"firewood", Vector3(-8.3, 0, -3.6), 0.5, true]],
		"stations": [[Vector3(-11.0, 0, -0.9), PI, &"KNEAD", 1], [Vector3(-13.4, 0, 1.7), PI, &"TEND", 1],
			[Vector3(-8.3, 0, -2.8), PI, &"TEND", 2]],
	},
	# the mayor: on the town hall's steps, at the noticeboard, out on the market place
	&"town_hall": {
		"props": [],
		"stations": [[Vector3(0.8, 0, 9.8), 0.0, &"ORATE", 1], [Vector3(-12.6, 0, 22.9), PI, &"TEND", 1],
			[Vector3(4.0, 0, 14.5), 0.0, &"ORATE", 2]],
	},
	# Maud, out front of the tavern by day: a table to wipe, the step to sweep
	&"tavern": {
		"props": [[&"table_large", Vector3(4.6, 0, 8.6), 0.0, true]],
		"stations": [[Vector3(4.6, 0, 9.9), PI, &"WIPE", 1], [Vector3(-1.0, 0, 6.4), 0.0, &"SWEEP", 1]],
	},
}
## Models kept in the palette (ours) rather than their own materials.
const PALETTE_MODELS := [&"forge"]


## Builds building `b`'s yard (props and stations) under a "Yard" node, if it has one.
static func build(b: Node3D, id: StringName) -> void:
	if not YARDS.has(id) or b.has_node("Yard"):
		return
	var yard := Node3D.new()
	yard.name = "Yard"
	b.add_child(yard)
	for p in YARDS[id]["props"]:
		var prop := Prop.new()
		prop.name = String(p[0]).to_pascal_case()
		prop.model = load("res://models/village/yard/%s.glb" % p[0])
		prop.own_materials = not PALETTE_MODELS.has(p[0])
		prop.collide = p[3]
		prop.snap_to_ground = (p[1] as Vector3).y == 0.0 and p[0] != &"jetty_deck"  # (the jetty stands level over the water)
		prop.transform = Transform3D(Basis(Vector3.UP, p[2]), p[1])
		yard.add_child(prop)
	var i := 0
	for s in YARDS[id]["stations"]:
		i += 1
		var m := Marker3D.new()
		m.name = "Station%d" % i
		m.transform = Transform3D(Basis(Vector3.UP, s[1]), s[0])
		m.set_meta(&"motion", s[2])
		m.set_meta(&"tier", s[3])
		m.add_to_group("station")
		yard.add_child(m)
