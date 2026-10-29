class_name TrophyPlaque
extends StaticBody3D
## A place on your wall for a trophy (plans/trophies.md): one of the plaques (TrophySlot*) or a spot
## on the Homestead's mantel (MantelSpot*, the small ones only). Shows what's hung there with its
## brass label; E opens the trophy panel (TrophyPanel) to hang one, swap or take it down. What's
## hung is Trophies.hung[place], so it stays put as the house goes up a tier.

const MODELS := "res://models/trophies/"
const LABEL_COLOR := Color("e2c47a")
## Trophies hang a little smaller than they're modelled, so the fish boards clear their neighbours.
const SCALE := 0.8

var place := ""
var small_only := false
var _shown: Node3D
var _label: Label3D


static func make(at: Transform3D, place_name: String) -> TrophyPlaque:
	var p := TrophyPlaque.new()
	p.place = place_name
	p.small_only = place_name.begins_with("Mantel")
	p.collision_layer = LookObject.LAYER
	p.collision_mask = 0
	p.transform = at
	p.add_to_group("trophies_listener")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.55, 0.6, 0.3) if not p.small_only else Vector3(0.4, 0.45, 0.4)
	shape.shape = box
	shape.position = Vector3(0, 0.0 if not p.small_only else 0.2, 0.12)
	p.add_child(shape)
	return p


func _ready() -> void:
	trophies_changed()


func hung() -> Dictionary:
	return Trophies.hung.get(place, {})


func prompt() -> String:
	var r := hung()
	if not r.is_empty():
		return "E  %s" % Trophies.label(r)
	return "E  Hang a trophy here" if not Trophies.fitting(small_only).is_empty() \
			else ("A spot on the mantel for something small" if small_only else "An empty plaque")


func interact() -> void:
	if hung().is_empty() and Trophies.fitting(small_only).is_empty():
		return
	var panel := get_tree().get_first_node_in_group("trophy_panel") as TrophyPanel
	if panel:
		panel.open(self)


## Shows whatever's hung here now (a pop when it's new).
func trophies_changed() -> void:
	var r := hung()
	var key := "" if r.is_empty() else "%s|%s|%s" % [r.get("kind"), r.get("species"), r.get("day")]
	if _shown and _shown.get_meta(&"key", "") == key:
		return
	if _shown:
		_shown.queue_free()
		_shown = null
	if _label:
		_label.queue_free()
		_label = null
	if r.is_empty():
		return
	var scene := load(MODELS + Trophies.model(r) + ".glb") as PackedScene
	if scene == null:
		return
	_shown = scene.instantiate() as Node3D
	_shown.set_meta(&"key", key)
	add_child(_shown)
	for m in _shown.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = PaletteMaterial.for_mesh((m as MeshInstance3D).mesh)
	_shown.scale = Vector3.ONE * 0.01
	_shown.create_tween().tween_property(_shown, "scale", Vector3.ONE * SCALE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_label = Label3D.new()
	_label.text = Trophies.label(r)
	_label.pixel_size = 0.0012
	_label.font_size = 40
	_label.outline_size = 6
	_label.modulate = LABEL_COLOR
	_label.outline_modulate = Color(0.15, 0.1, 0.05, 0.8)
	_label.position = Vector3(0, -0.05 if small_only else -0.36, 0.06)
	add_child(_label)


func set_highlighted(_on: bool) -> void:
	pass
