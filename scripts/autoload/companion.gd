extends Node
## Your dog (plans/dog.md), per world: whether you have one yet, and his breed, coat and name.
## The dog in the world is a Dog node (scripts/dog.gd) that DogHome puts in the scene.

signal adopted
## His collar changed (a special from the trader, plans/market.md).
signal collar_changed

const BREEDS: Array[StringName] = [&"terrier", &"shepherd", &"fluffy"]
## Coats per breed (models/dogs/dog_<breed>_<coat>.glb), the first one the stray's.
const COATS := {
	&"terrier": [&"wheaten", &"grey", &"black_tan"],
	&"shepherd": [&"saddle", &"brown", &"cream"],
	&"fluffy": [&"tricolour", &"golden", &"white"],
}
const BREED_NAMES := {&"terrier": "terrier", &"shepherd": "shepherd mutt", &"fluffy": "big fluffy dog"}
const COAT_NAMES := {
	&"wheaten": "Wheaten", &"grey": "Grey", &"black_tan": "Black and tan",
	&"saddle": "Black saddle", &"brown": "Brown", &"cream": "Cream",
	&"tricolour": "Tricolour", &"golden": "Golden", &"white": "White",
}
## Suggested names, one picked at random for the naming box.
const NAMES := ["Biscuit", "Pip", "Bramble", "Maple", "Juniper", "Tuck", "Hazel", "Rufus", "Clover", "Moss"]

var has_dog := false
var breed: StringName = &""
var coat: StringName = &""
var dog_name := ""
## The collar he wears (a Trader special id, e.g. &"collar_red"), or &"" for none.
var collar: StringName = &""
const COLLARS := {&"collar_red": Color(0.62, 0.17, 0.12), &"collar_blue": Color(0.24, 0.5, 0.77), &"collar_green": Color(0.3, 0.52, 0.3)}


func _ready() -> void:
	SaveGame.register(&"dog", self)


static func model_path(b: StringName, c: StringName) -> String:
	return "res://models/dogs/dog_%s_%s.glb" % [b, c]


func adopt(b: StringName, c: StringName, n: String) -> void:
	has_dog = true
	breed = b
	coat = c
	dog_name = n.strip_edges() if not n.strip_edges().is_empty() else NAMES[0]
	SaveGame.mark_dirty()
	adopted.emit()


func set_collar(id: StringName) -> void:
	collar = id
	SaveGame.mark_dirty()
	collar_changed.emit()


func to_dict() -> Dictionary:
	return {"has": has_dog, "breed": String(breed), "coat": String(coat), "name": dog_name, "collar": String(collar)}


func from_dict(d: Dictionary) -> void:
	has_dog = bool(d.get("has", false))
	breed = StringName(d.get("breed", ""))
	coat = StringName(d.get("coat", ""))
	dog_name = String(d.get("name", ""))
	collar = StringName(d.get("collar", ""))
	if has_dog and (not COATS.has(breed) or not (COATS[breed] as Array).has(coat)):
		has_dog = false  # a breed or coat that's gone: meet a new one
