extends SceneTree
## Headless checks for the layered notch (plans/logging.md) on each tree's own trunk: a plain chop
## takes the layers off one by one and reaches the fall depth on the tree's last cut; a clean cut
## finishes a layer; stability falls as the wood goes (not the bark); the notch saves and loads, an
## older save's depth too; the trunk still splits.
##   godot --headless --path . -s res://tools/test_logging.gd -- --save-root=user://tmp
## (No game class names: an -s script compiles before the autoloads exist.)

const TREES := [  # model, bark thickness, max hits
	["res://models/tree.glb", 0.03, 15],
	["res://models/birch.glb", 0.015, 15],
	["res://models/oak.glb", 0.045, 20],
	["res://models/pine.glb", 0.035, 25],
]
const BAND := Vector2(0.6, 1.4)
const FALL := 0.65

var _fails := 0
var _carve_script: GDScript = load("res://scripts/trunk_carve.gd")


func _initialize() -> void:
	for t in TREES:
		_test_tree(t[0], t[1], t[2])
	print("test_logging: %s" % ("all passed" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL: ", what)


func _trunk_mesh(path: String) -> ArrayMesh:
	var model: Node = (load(path) as PackedScene).instantiate()
	var trunk := model.find_child("Body_Trunk", true, false) as MeshInstance3D
	var mesh := trunk.mesh as ArrayMesh if trunk else null
	model.free()
	return mesh


func _test_tree(path: String, bark: float, max_hits: int) -> void:
	var name := path.get_file().get_basename()
	var mesh := _trunk_mesh(path)
	_check(mesh != null, "%s: has a Body_Trunk mesh" % name)
	if mesh == null:
		return
	var dir := Vector3(1, 0, 0.3).normalized()
	var carve: RefCounted = _carve_script.new(mesh, BAND, bark, FALL, max_hits)
	var layers: int = _carve_script.LAYERS.size()

	# a plain chop: the layers come off one at a time, out to in, the last on the last cut
	var popped := PackedInt32Array()
	var last_pop := -1
	var stab := PackedFloat32Array([carve.stability()])
	var dents := 0
	for i in max_hits:
		var before: float = carve.depth_toward(dir)
		var off: PackedInt32Array = carve.hit(1.0, dir, 1.0)
		popped.append_array(off)
		if not off.is_empty():
			last_pop = i
		elif carve.depth_toward(dir) > before:
			dents += 1
		stab.append(carve.stability())
	_check(popped.size() == layers, "%s: a plain chop takes all %d layers off (%d)" % [name, layers, popped.size()])
	for k in popped.size():
		_check(popped[k] == k, "%s: layers come off out to in (%s)" % [name, popped])
	_check(last_pop == max_hits - 1, "%s: the last layer comes off on the last cut (%d)" % [name, last_pop + 1])
	_check(popped.size() > 0 and popped[0] == 0, "%s: the first hit takes the outer bark" % name)
	_check(dents > 0, "%s: hits between layers still dent the notch" % name)
	var r: float = carve.radius_at(carve.ring, dir)
	var deep: float = carve.depth_toward(dir)
	_check(absf(deep - r * FALL) < r * 0.08, "%s: a plain chop ends %.0f%% deep (%.0f%%)" % [name, FALL * 100, deep / r * 100])
	var falling := true
	for i in range(1, stab.size()):
		falling = falling and stab[i] <= stab[i - 1] + 0.0001
	_check(falling, "%s: stability only falls as you chop" % name)
	_check(stab[stab.size() - 1] < 0.85, "%s: the chopped trunk has lost a good share of its wood (%.2f)" % [name, stab[stab.size() - 1]])
	_check(stab[2] > 0.97, "%s: stripping the bark costs no stability (%.3f)" % [name, stab[2]])
	var plain: PackedFloat32Array = carve.plain_chop(1.0, dir, max_hits)
	_check(absf(plain[max_hits] - stab[max_hits]) < 0.001, "%s: plain_chop() matches a real chop" % name)

	# the notch's faces show the layers' colours
	var uvs := {}
	var arrays: Array = (carve.carved() as ArrayMesh).surface_get_arrays(0)
	for uv in arrays[Mesh.ARRAY_TEX_UV]:
		uvs[uv] = true
	_check(uvs.has(Vector2(0.6875, 0.3125)), "%s: the heartwood's colour shows in a deep notch" % name)

	# a clean cut finishes the layer it's in
	var fresh: RefCounted = _carve_script.new(mesh, BAND, bark, FALL, max_hits)
	fresh.hit(1.0, dir, 1.0)
	fresh.hit(1.0, dir, 1.0)
	fresh.hit(1.0, dir, 1.0)
	var at: int = fresh.layer_toward(dir)
	var off: PackedInt32Array = fresh.hit(1.0, dir, 1.0, true)
	_check(off.size() >= 1 and fresh.layer_toward(dir) >= at + 1, "%s: a clean cut takes a layer off (%s)" % [name, off])

	# save and load: the same notch; an older save (depth only) comes back about as deep
	var saved: Dictionary = JSON.parse_string(JSON.stringify(carve.to_dict()))
	var loaded: RefCounted = _carve_script.new(mesh, BAND, bark, FALL, max_hits)
	loaded.from_dict(saved)
	_check(absf(loaded.depth_toward(dir) - deep) < 0.002 and absf(loaded.stability() - carve.stability()) < 0.002,
		"%s: the notch saves and loads" % name)
	saved.erase("work")
	var old: RefCounted = _carve_script.new(mesh, BAND, bark, FALL, max_hits)
	old.from_dict(saved)
	_check(absf(old.depth_toward(dir) - deep) < 0.01, "%s: an older save's notch comes back (%.3f vs %.3f)" % [name, old.depth_toward(dir), deep])

	# the trunk still splits at the notch
	var parts: Dictionary = carve.split()
	_check((parts["stump"] as ArrayMesh).get_surface_count() > 0 and (parts["log"] as ArrayMesh).get_surface_count() > 0,
		"%s: the trunk splits into stump and log" % name)
	print("  %s: stability by cut %s" % [name, Array(stab).map(func(v: float) -> String: return "%.2f" % v)])
