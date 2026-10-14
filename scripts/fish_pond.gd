class_name FishPond
extends Node3D
## Stocks the WaterBody it sits under with schools of fish, and respawns a school that has been
## fished out. Put this as a child of a WaterBody and list one species entry per school.
## Anything that makes noise in water calls FishPond.disturb(tree, pos, loudness).

## One school per entry (repeat a species for several schools of it).
@export var schools: Array[FishSpecies] = []
## Seconds before a fully fished-out school is replaced by a new one.
@export var restock_time := 60.0

var water: WaterBody
var _restock: Array[float] = []  # pending restock timers, one per wiped-out school


func _ready() -> void:
	water = get_parent() as WaterBody
	assert(water, "FishPond must be a child of a WaterBody")
	_stock.call_deferred()


func _stock() -> void:
	for s in schools:
		_add_school(s)


func _add_school(species: FishSpecies) -> void:
	var school := FishSchool.new()
	school.name = "%sSchool" % String(species.id).capitalize()
	add_child(school)
	# lurkers hide by a reed clump at the edge of the shallows; schools start in open water
	var at := _lurk_spot() if species.lurker else random_point(water, maxf(0.5, species.min_depth + 0.1))
	if at == Vector3.INF:
		at = water.global_position
	school.setup(species, water, at)
	if species.lurker:
		school.set_lurk_spot(at)


func _process(delta: float) -> void:
	for school in get_children():
		var s := school as FishSchool
		if s and s.fish.is_empty() and s.target_size > 0:
			s.target_size = 0  # mark as handled
			_restock.append(restock_time)
			s.set_meta("species", s.species)
	for i in range(_restock.size() - 1, -1, -1):
		_restock[i] -= delta
		if _restock[i] <= 0.0:
			_restock.remove_at(i)
			for school in get_children():
				var s := school as FishSchool
				if s and s.target_size == 0 and s.has_meta("species"):
					var species: FishSpecies = s.get_meta("species")
					s.queue_free()
					_add_school(species)
					break


## Just off a reed clump, toward open water, where it's deep enough to swim (pike cover).
func _lurk_spot() -> Vector3:
	var dressing := water.get_node_or_null("Dressing") as PondDressing
	if dressing and not dressing.reed_spots.is_empty():
		var spot: Vector3 = dressing.reed_spots.pick_random()
		var to_center := water.global_position - spot
		to_center.y = 0.0
		for i in 12:  # step out from the reeds until the water is deep enough
			if water.depth_here(spot) >= 0.4:
				spot.y = water.surface_height - water.depth_here(spot) * 0.5
				return spot
			spot += to_center.normalized() * 0.25
	return random_point(water, 0.35, 0.6)


## Wakes up any school near a noise. loudness: ~0.15 crouch step, 0.6 walk, 1 sprint, 2 strike.
static func disturb(tree: SceneTree, pos: Vector3, loudness: float) -> void:
	for school in tree.get_nodes_in_group("fish_school"):
		(school as FishSchool).disturb(pos, loudness)


## A random point on the water's volume where it's between min_depth and max_depth deep,
## at mid-depth. Vector3.INF if none found.
static func random_point(w: WaterBody, min_depth: float, max_depth := INF) -> Vector3:
	var box := w.get_node("Volume") as CollisionShape3D
	var half := (box.shape as BoxShape3D).size / 2.0
	for i in 60:
		var local := Vector3(randf_range(-half.x, half.x), 0.0, randf_range(-half.z, half.z))
		var p := box.global_transform * local
		var d := w.depth_here(p)
		if d >= min_depth and d <= max_depth:
			p.y = w.surface_height - d * 0.5
			return p
	return Vector3.INF
