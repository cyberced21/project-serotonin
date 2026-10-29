class_name DogHome
extends Node3D
## Puts your dog (Companion) in the world when it loads, beside you, and again the moment you
## adopt him (plans/dog.md).

var dog: Dog


func _ready() -> void:
	add_to_group("dog_home")
	Companion.adopted.connect(_spawn)
	_spawn.call_deferred()


func _spawn() -> void:
	if not Companion.has_dog or is_instance_valid(dog):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	dog = Dog.new()
	dog.name = "Dog"
	dog.setup(Companion.breed, Companion.coat, Companion.dog_name)
	add_child(dog)
	var at := player.global_position + player.global_basis.x * 1.5 if player else Vector3.ZERO
	var terrain := get_tree().get_first_node_in_group("terrain") as Terrain3D
	if terrain and terrain.data:
		var g: float = terrain.data.get_height(at)
		if not is_nan(g):
			at.y = g
	dog.global_position = at
	dog.reset_physics_interpolation()
