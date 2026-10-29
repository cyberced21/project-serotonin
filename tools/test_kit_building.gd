extends SceneTree
## Checks a kit-built village building (tools/blender/kit_buildings.py, plans/home.md phase 2) as
## Building shows it: every tier has pieces; kit pieces keep their own materials and our pieces get
## the palette; there's window glass to light; you can walk in through the door but not through a
## wall; and there's a floor to stand on inside.
##   godot --headless --path . -s res://tools/test_kit_building.gd -- --save-root=user://tool_worlds
## (No game class names: an -s script compiles before the autoloads exist.)

const MODEL := "res://models/village/baker_cottage.gltf"
const DEF := "res://data/buildings/baker_cottage.tres"
## Per tier, the doorway's centre and a stretch of plain wall on the front (Godot x; front faces +z).
const FRONT := {1: {"door": 0.0, "wall_z": 4.0}, 2: {"door": -1.0, "wall_z": 5.0}, 3: {"door": -1.0, "wall_z": 5.0}}
const AT := Vector3(400, 0, 400)  # well away from the village

var _fails := 0
var _player: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_player = Node3D.new()  # stands in for the player, for "are you inside"
	_player.add_to_group("player")
	root.add_child(_player)
	var def: Resource = load(DEF).duplicate()
	def.set("model", load(MODEL))
	var b := Node3D.new()
	b.set_script(load("res://scripts/building.gd"))
	b.set("def", def)
	b.position = AT
	root.add_child(b)
	await process_frame
	for t in FRONT:
		b.call("_show_tier", t)
		for i in 3:
			await physics_frame
		_tier(b, t)
	_finish()


func _tier(b: Node3D, t: int) -> void:
	var group := b.get_node("Tier%d" % t) as Node3D
	var kit := 0
	var ours := 0
	var glass := 0
	var bad := 0
	for m in group.get_children():
		if not m is MeshInstance3D:
			continue
		var is_kit := String(m.name).substr(3).begins_with("Kit") and m.mesh.surface_get_material(0) != null
		if is_kit:
			kit += 1
			if m.material_override != null:
				bad += 1
		else:
			ours += 1
			if m.material_override == null:
				bad += 1
		if String(m.name).to_lower().contains("windowglass"):
			glass += 1
	print("tier %d: %d kit pieces, %d ours, %d window panes" % [t, kit, ours, glass])
	_check(kit > 20, "tier %d is built from the kit" % t)
	_check(bad == 0, "tier %d: kit pieces keep their materials, ours get the palette (%d wrong)" % [t, bad])
	_check(glass > 0, "tier %d has window glass to light" % t)
	var f: Dictionary = FRONT[t]
	var z: float = f["wall_z"]
	_check(_ray(b, Vector3(f["door"], 1.0, z + 2.0), Vector3(f["door"], 1.0, z - 2.0)).is_empty(),
			"tier %d: the door is open to walk through" % t)
	var wall_x: float = f["door"] + 2.0  # the next module along is a window wall: solid below the sill
	_check(not _ray(b, Vector3(wall_x, 0.5, z + 2.0), Vector3(wall_x, 0.5, z - 2.0)).is_empty(),
			"tier %d: the front wall is solid" % t)
	_check(not _ray(b, Vector3(0.5, 1.5, 0.5), Vector3(0.5, -0.5, 0.5)).is_empty(), "tier %d has a floor inside" % t)
	# the walk-in house (phase 3): a bed, seats, things to look at, a door that swings, a room
	_check(b.call("bed") != null, "tier %d has a bed" % t)
	var seats := 0
	var looks := 0
	var doors := 0
	for c in group.get_children():
		if c is Marker3D and c.is_in_group("seat") and c.get_meta(&"kind", &"") == &"home":
			seats += 1
		if c.has_method("prompt") and String(c.call("prompt")).begins_with("E  Look at"):
			looks += 1
		if c is MeshInstance3D and String(c.name).substr(3).begins_with("KitDoor1"):
			doors += 1
	_check(seats >= 2, "tier %d has seats at home (%d)" % [t, seats])
	_check(looks >= 1, "tier %d has something to look at (%d)" % [t, looks])
	_check(doors >= 1, "tier %d has a door leaf (%d)" % [t, doors])
	_player.global_position = b.to_global(Vector3(0.5, 0.2, 0.5))
	_check(b.call("has_player"), "tier %d: standing inside counts as indoors" % t)
	_player.global_position = b.to_global(Vector3(0.0, 0.2, 12.0))
	_check(not b.call("has_player"), "tier %d: outside doesn't" % t)


func _ray(b: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(b.to_global(from), b.to_global(to))
	return b.get_world_3d().direct_space_state.intersect_ray(q)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1


func _finish() -> void:
	print("%s: %d failed" % ["OK" if _fails == 0 else "FAILED", _fails])
	quit(1 if _fails else 0)
