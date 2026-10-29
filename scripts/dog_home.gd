class_name DogHome
extends Node3D
## Puts your dog (Companion) in the world when it loads, beside you (plans/dog.md). Before you have
## one, three strays (one of each breed) nap round the clearing's pond by day; at night they're
## not there yet, so a world without a dog meets them at the next dawn. Pet one and the naming box
## (DogNamePanel) asks his name and coat; he's yours, and the other two wander off.

## Where the strays nap: round the clearing's pond, clear of the creek and the ruins.
const STRAY_SPOTS: Array[Vector2] = [Vector2(7, 14), Vector2(10, 28), Vector2(32, 23)]
## Strays come by day only: between these times of day (DayNight.time).
const STRAYS_FROM := DayNight.SUNRISE + 0.01
const STRAYS_UNTIL := DayNight.SUNSET - 0.05

var dog: Dog
var strays: Array[Dog] = []
var _meeting: Dog  # the stray whose naming box is open


func _ready() -> void:
	add_to_group("dog_home")
	Companion.adopted.connect(_spawn)  # (adopted some other way: the debug menu, a test)
	_spawn.call_deferred()


func _process(_delta: float) -> void:
	if Companion.has_dog or not strays.is_empty():
		return
	if DayNight.time > STRAYS_FROM and DayNight.time < STRAYS_UNTIL:
		_spawn_strays()


func _spawn() -> void:
	if not Companion.has_dog or is_instance_valid(dog):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	_send_off_strays(null)
	dog = Dog.new()
	dog.name = "Dog"
	dog.setup(Companion.breed, Companion.coat, Companion.dog_name)
	add_child(dog)
	dog.global_position = _on_ground(player.global_position + player.global_basis.x * 1.5 if player else Vector3.ZERO)
	dog.reset_physics_interpolation()


func _spawn_strays() -> void:
	for i in Companion.BREEDS.size():
		var b: StringName = Companion.BREEDS[i]
		var d := Dog.new()
		d.name = "Stray%d" % (i + 1)
		d.stray = true
		d.setup(b, Companion.COATS[b][0], "")
		add_child(d)
		var spot := STRAY_SPOTS[i]
		d.global_position = _on_ground(Vector3(spot.x, 0.0, spot.y))
		d.rotation.y = randf() * TAU
		d.reset_physics_interpolation()
		strays.append(d)


## You petted a stray: ask his name and coat.
func meet(stray: Dog) -> DogNamePanel:
	_meeting = stray
	var panel := DogNamePanel.open_for(stray)
	if not panel.chosen.is_connected(_on_chosen):
		panel.chosen.connect(_on_chosen)
	return panel


func _on_chosen(coat: StringName, dog_name: String) -> void:
	if is_instance_valid(_meeting):
		adopt(_meeting, coat, dog_name)
	_meeting = null


## `stray` is your dog now; the others trot off away from you.
func adopt(stray: Dog, coat: StringName, dog_name: String) -> void:
	_send_off_strays(stray)
	stray.adopt_as(coat, dog_name)
	dog = stray
	Companion.adopt(stray.breed, coat, dog_name)


func _send_off_strays(keep: Dog) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for s in strays:
		if is_instance_valid(s) and s != keep:
			var away := s.global_position - (player.global_position if player else s.global_position + Vector3.BACK)
			s.leave(away if away.length() > 0.1 else Vector3.FORWARD)
	strays.clear()


func _on_ground(at: Vector3) -> Vector3:
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain and terrain.data:
		var g: float = terrain.data.get_height(at)
		if not is_nan(g):
			at.y = g
	return at
