extends SceneTree
## Checks the town designer (plans/town-designer.md) where the game sees it:
##   - every building type in the catalog has its model
##   - an added building (an anchor with a `type`) is made under Village where its anchor says,
##     turned to its yaw, with its door a Spots/Door marker; applying twice makes it once
##   - one not placed is kept out; one of an unknown type is skipped
##   - a plot: its edge leaves its gate open, its garden's things are inside it, the same each time
##   - Hearthvale's work yards, read from its layout, are the ones WorkYards has written down
##   - the market: its size and the green's spots from the green's anchor (the lamps, the pond, the
##     noticeboard), the baskets and bunting following the lamps
##   godot --headless --path . -s res://tools/test_town.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

const Anchors := preload("res://scripts/layout_anchors.gd")
const Plots := preload("res://scripts/town_plots.gd")
const Yards := preload("res://scripts/work_yards.gd")
const WorldMapC := preload("res://scripts/world_map.gd")
const Decor := preload("res://scripts/village_decor.gd")
## Trade (WorkYards' key) -> its building's anchor.
const YARD_ANCHORS := {&"smithy": "smithy", &"woodcutter": "woodcutter", &"fisher": "fisher", &"prospector_cottage": "prospector",
	&"baker_cottage": "baker", &"town_hall": "town_hall", &"tavern": "tavern"}
const TMP := "user://tmp/test_town_layout.json"
const EPS := 0.01

var failures := PackedStringArray()


func _initialize() -> void:
	_catalog()
	_added()
	_plots()
	_yards()
	if failures.is_empty():
		print("test_town: PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL " + f)
		print("test_town: %d FAILED" % failures.size())
		quit(1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func _catalog() -> void:
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout/catalog.json"))
	_check(c.has("buildings") and c["buildings"].size() >= 6, "the catalog lists buildings to add")
	for k in c.get("buildings", {}):
		var t: Dictionary = c["buildings"][k]
		_check(ResourceLoader.exists(String(t["model"])), "building type %s's model %s exists" % [k, t["model"]])
		_check((t["box"] as Array).size() == 4 and float(t.get("pad", 0)) > 0.0, "building type %s has a box and a pad" % k)


## A layout like Hearthvale's with three added buildings: a cottage, a barn not placed, a nonsense type.
func _layout() -> String:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout/hearthvale.json"))
	layout["anchors"].append({"id": "cottage_t1", "type": "cottage", "at": [150.0, 160.0], "yaw": 90.0, "pad": 7, "area": "village"})
	layout["anchors"].append({"id": "barn_t1", "type": "barn", "at": [170.0, 170.0], "yaw": 0.0, "placed": false})
	layout["anchors"].append({"id": "odd_t1", "type": "no_such_thing", "at": [180.0, 170.0]})
	for a in layout["anchors"]:
		if a["id"] == "green":
			a["market"] = {"length": 60.0, "half_width": 10.0}
			a["spots"] = {"Lamp1": [-20.0, -4.0, 90.0], "VillagePond": [-4.0, 8.0], "noticeboard": [-10.0, -6.0, 45.0]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tmp"))
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify(layout))
	f.close()
	return TMP


func _added() -> void:
	Anchors.use_file(_layout())
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	Anchors.apply(main)
	var n := main.get_node_or_null("Village/cottage_t1") as Node3D
	_check(n != null, "the added cottage is made under Village")
	if n:
		_check(Vector2(n.position.x, n.position.z).distance_to(Vector2(150, 160)) < EPS, "it stands at its anchor (%s)" % n.position)
		var yaw := rad_to_deg(atan2(n.basis.z.x, n.basis.z.z))
		_check(absf(wrapf(yaw - 90.0, -180.0, 180.0)) < 0.05, "it's turned to its yaw (%.2f)" % yaw)
		_check(n.get("model") != null and n.get("doors_open") == false, "it has its model, its doors shut")
		var door := n.call("door_point") as Node3D
		_check(door != null, "it has a door for the walkways")
		if door:
			var p := n.transform * door.position  # (its door: 4.6 m in front, and in front is +X when turned 90°)
			_check(Vector2(p.x, p.z).distance_to(Vector2(154.6, 160)) < 0.05, "its door is at its front (%s)" % p)
		_check(String(n.get_meta(&"display_name", "")) == "Cottage", "it's called by its type's name")
		_check(n.is_in_group("fixture"), "it's a fixture (its door is found before it's ready)")
	var count := main.get_node("Village").get_child_count()
	Anchors.apply(main)
	_check(main.get_node("Village").get_child_count() == count, "applying twice makes it once")
	var barn := main.get_node_or_null("Village/barn_t1") as Node3D
	_check(barn != null and not barn.visible and barn.has_meta(&"kept_out"), "a building not placed is kept out")
	_check(main.get_node_or_null("Village/odd_t1") == null, "a building of no known type isn't made")
	_check(Anchors.find(&"cottage_t1").get("node", "") == "Village/cottage_t1", "its anchor names the node made for it")
	var g := main.get_node("Village/Green") as Node3D
	var lamp := g.get_node("Lamp1") as Node3D
	_check(Vector2(lamp.position.x, lamp.position.z).distance_to(Vector2(-20, -4)) < EPS, "the green's lamp stands where its spot says (%s)" % lamp.position)
	_check(absf(rad_to_deg(atan2(lamp.basis.z.x, lamp.basis.z.z)) - 90.0) < 0.05, "and faces the way it says")
	var pond := g.get_node("VillagePond") as Node3D
	_check(Vector2(pond.position.x, pond.position.z).distance_to(Vector2(-4, 8)) < EPS, "the village pond moved with its spot")
	_check(g.get_node("Lamp2").position.x == 16.5, "a lamp without a spot stays put")
	_check(is_equal_approx(WorldMapC.market_length(), 60.0) and is_equal_approx(WorldMapC.market_widest(), 10.0), "the market's size is the green's")
	_check(is_equal_approx(WorldMapC.market_half_width(0.0), 10.0) and WorldMapC.market_half_width(29.0) > 0.0 and WorldMapC.market_half_width(31.0) == 0.0, "the lens follows its size")
	var nb: Array = Decor.spot("noticeboard", Decor.NOTICEBOARD)
	_check(nb[0] == Vector2(-10, -6) and is_equal_approx(nb[1], deg_to_rad(45.0)), "the noticeboard goes to its spot (%s)" % [nb])
	_check(Decor.spot("well/0", [Vector2(3, -9.5), -0.306])[0] == Vector2(3, -9.5), "a decoration without a spot stays where it was")
	_check(Decor.lamp(0) == Vector2(-20, -4) and Decor.lamp(1) == Decor.LAMPS[1], "the baskets and bunting follow the lamps")
	main.free()
	Anchors.use_file("res://data/layout/hearthvale.json")


func _plots() -> void:
	var plot := {"id": "plot_t", "points": [[0, 0], [20, 0], [20, 12], [0, 12]], "edge": "hedge", "gate": [0, 3.0], "seed": 7}
	var runs := Plots.edge_runs(plot)
	_check(runs.size() == 1, "a gated plot's edge is one run")
	if runs.size() == 1:
		var r: PackedVector2Array = runs[0]
		_check(r[0].distance_to(Vector2(11.5, 0)) < 0.01 and r[-1].distance_to(Vector2(8.5, 0)) < 0.01, "its gate is a 3 m gap in the middle of edge 0 (%s .. %s)" % [r[-1], r[0]])
		_check(r.size() == 6, "the run goes round every corner (%d points)" % r.size())
	var open := plot.duplicate()
	open.erase("gate")
	var loop: PackedVector2Array = Plots.edge_runs(open)[0]
	_check(loop.size() == 5 and loop[0] == loop[-1], "without a gate the edge closes on itself")
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/layout/catalog.json"))
	for g in c.get("gardens", {}):
		var garden: Dictionary = c["gardens"][g]
		var spots := Plots.fill_spots(plot, garden)
		_check(not spots.is_empty(), "garden %s puts something in a 20 x 12 m plot" % g)
		var poly := PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 12), Vector2(0, 12)])
		for s in spots:
			_check(c["props"].has(s[0]) or c["fixtures"].has(s[0]), "garden %s's %s is in the catalog" % [g, s[0]])
			_check(Geometry2D.is_point_in_polygon(s[1], poly), "garden %s's %s is inside the plot (%s)" % [g, s[0], s[1]])
		_check(str(Plots.fill_spots(plot, garden)) == str(spots), "garden %s comes out the same for the same seed" % g)
	_check(Plots.inside_grid(plot, 2.0).size() == 60, "the keep-clear grid covers it (%d spots)" % Plots.inside_grid(plot, 2.0).size())


func _yards() -> void:
	for trade in Yards.YARDS:
		var a: Dictionary = Anchors.find(StringName(YARD_ANCHORS.get(trade, "")))
		_check(a.has("yard"), "%s's anchor has its yard" % trade)
		if not a.has("yard"):
			continue
		var got: Dictionary = Yards.from_layout(a["yard"])
		var want: Dictionary = Yards.YARDS[trade]
		for part in ["props", "stations"]:
			_check(got[part].size() == want[part].size(), "%s's yard has its %d %s" % [trade, want[part].size(), part])
			for i in mini(got[part].size(), want[part].size()):
				var g: Array = got[part][i]
				var w: Array = want[part][i]
				var gv: Vector3 = g[1] if part == "props" else g[0]
				var wv: Vector3 = w[1] if part == "props" else w[0]
				var gf: float = g[2] if part == "props" else g[1]
				var wf: float = w[2] if part == "props" else w[1]
				_check(gv.distance_to(wv) < 0.01 and absf(wrapf(gf - wf, -PI, PI)) < 0.001, "%s's %s %d is where WorkYards has it (%s %.3f, wants %s %.3f)" % [trade, part, i, gv, gf, wv, wf])
				_check(str(g[0] if part == "props" else g[2]) == str(w[0] if part == "props" else w[2]), "%s's %s %d is the same thing" % [trade, part, i])
