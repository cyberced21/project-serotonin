class_name MarketStall
extends Prop
## The market stall in the square (plans/market.md), a village project: a striped awning over a
## counter of goods, the stallkeeper behind it. Look at it and press E to barter (MarketPanel).

const KEEPER := preload("res://models/village/villager_stallkeeper.glb")
const MODEL := preload("res://models/village/props/market_stall.glb")


func _init() -> void:
	model = MODEL
	snap_to_ground = true


func _ready() -> void:
	super()
	add_to_group("market_stall")
	var keeper := KEEPER.instantiate() as Node3D
	keeper.name = "Keeper"
	add_child(keeper)
	keeper.position = Vector3(0.3, 0.0, -0.75)  # behind the counter, facing the square
	for m in keeper.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = PaletteMaterial.for_mesh((m as MeshInstance3D).mesh)


## Shown under the crosshair (player.gd treats anything with interact() like a villager).
func prompt() -> String:
	var trader := get_tree().get_first_node_in_group("trader")
	return "E  Trade at the market" + ("  (the trader's in: better rates)" if trader and trader.call("is_in") else "")


func interact() -> void:
	MarketPanel.open_for(self)


func set_highlighted(on: bool) -> void:
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).set_instance_shader_parameter("highlight", 1.0 if on else 0.0)
