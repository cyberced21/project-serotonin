class_name ProcgenLandmarks
extends RefCounted
## Builds the landmarks a ProcgenMap placed (map.landmarks), out of existing pieces:
## - ruins: the clearing's parkour blocks as a Broken Tower (two walls meeting in an L) or an Old
##   Colonnade (a row of pillars with gaps, a fallen wall), each with a pedestal of steps and
##   stacked ledges you climb to reach an ore rock on top;
## - an abandoned camp: a cart, hay, a log pile, crates, barrels and a bench round a clearing;
## - rare spots: a crystal outcrop or a gold vein out in the mountains, a ring of ancient oaks,
##   a flower meadow round a lone oak (a pike pond is just water: ProcgenWorld stocks it).
## Layouts are in metres round the landmark's middle, turned to its angle (as the village is).

const RUINS := "res://models/ruins/%s.glb"
## Each ruin piece's size: its collision box, centred on its origin (as in main.tscn's Ruins).
const RUIN_SIZES := {
	&"step_050": Vector3(1.5, 0.5, 1.5), &"step_100": Vector3(1.5, 1.0, 1.5), &"step_150": Vector3(1.5, 1.5, 1.5),
	&"ledge_120": Vector3(3.0, 1.2, 2.0), &"wall_250": Vector3(8.0, 2.5, 1.0), &"pillar": Vector3(1.0, 3.0, 1.0),
}
## The climb to the reward: steps up to two stacked ledges, the reward on top (at PEDESTAL_TOP).
## [piece, offset, height of its bottom, facing]
const PEDESTAL := [
	[&"ledge_120", Vector2(0.5, 0.5), 0.0, 0.0], [&"ledge_120", Vector2(0.5, 0.5), 1.2, 0.0],
	[&"step_150", Vector2(2.75, 0.5), 0.0, 0.0], [&"step_100", Vector2(4.25, 0.5), 0.0, 0.0],
	[&"step_050", Vector2(5.75, 0.5), 0.0, 0.0],
]
const PEDESTAL_TOP := Vector3(0.5, 2.4, 0.5)
const RUIN_LAYOUTS := {
	&"broken_tower": [
		[&"wall_250", Vector2(0, -1.5), 0.0, 0.0], [&"wall_250", Vector2(-3.5, 2.5), 0.0, 1.5708],
		[&"pillar", Vector2(3.5, 4.0), 0.0, 0.0], [&"pillar", Vector2(-1.0, 6.0), 0.0, 0.0],
	],
	&"old_colonnade": [
		[&"pillar", Vector2(-6, -3), 0.0, 0.0], [&"pillar", Vector2(-3, -3), 0.0, 0.0],
		[&"pillar", Vector2(3, -3), 0.0, 0.0], [&"pillar", Vector2(6, -3), 0.0, 0.0],
		[&"wall_250", Vector2(-2, 4), 0.0, 0.0], [&"pillar", Vector2(4.5, 4.0), 0.0, 0.0],
	],
}
## What waits on top of the ruins.
const REWARDS := ["res://scenes/gold_rock.tscn", "res://scenes/coal_rock.tscn", "res://scenes/iron_rock.tscn"]
const CAMP := [  # [model path, offset, facing]
	["res://models/field/cart.glb", Vector2(0, -3.5), 0.4],
	["res://models/road/log_pile.glb", Vector2(3.5, 1.0), 1.2],
	["res://models/field/hay_stack.glb", Vector2(-3.5, 1.5), 0.0],
	["res://models/field/hay_round.glb", Vector2(-1.5, 4.0), 0.7],
	["res://models/village/props/crates.glb", Vector2(2.8, -2.2), -0.3],
	["res://models/village/props/barrel.glb", Vector2(-3.0, -1.8), 0.0],
	["res://models/village/props/barrel.glb", Vector2(-2.3, -2.7), 1.0],
	["res://models/village/props/bench.glb", Vector2(0.5, 2.0), 0.0],
]
## Rare spots made of nodes: [scene, offset] each.
const RARE_NODES := {
	&"crystal_outcrop": [["res://scenes/crystal_rock.tscn", Vector2(-2.5, 0)], ["res://scenes/crystal_rock.tscn", Vector2(2.5, 0.8)]],
	&"gold_vein": [["res://scenes/gold_rock.tscn", Vector2(0, -3)], ["res://scenes/gold_rock.tscn", Vector2(3, 2)],
			["res://scenes/gold_rock.tscn", Vector2(-3, 2)]],
	&"ancient_oaks": [["res://scenes/oak_tree.tscn", Vector2(0, -5)], ["res://scenes/oak_tree.tscn", Vector2(5, 0)],
			["res://scenes/oak_tree.tscn", Vector2(0, 5)], ["res://scenes/oak_tree.tscn", Vector2(-5, 0)]],
	&"flower_meadow": [["res://scenes/oak_tree.tscn", Vector2.ZERO]],
}
const PROP := preload("res://scripts/prop.gd")
## How far a node's base sinks into the ground (as NodeSpawner's).
const SINK := 0.15


static func build(parent: Node3D, map: ProcgenMap) -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = map.sub_seed(&"landmark_build")
	for i in map.landmarks.size():
		var l: Dictionary = map.landmarks[i]
		var place := Node3D.new()
		place.name = "%s%d" % [String(l["kind"]).to_pascal_case(), i + 1]
		place.position = Vector3(l["pos"].x, l["height"], l["pos"].y)
		place.rotation.y = -float(l["angle"])  # a turn by +angle in the XZ plane is -angle round Y
		place.set_meta("landmark", l["name"])
		place.add_to_group("landmark")
		root.add_child(place)
		match l["type"]:
			&"ruins":
				for piece in PEDESTAL + RUIN_LAYOUTS[l["kind"]]:
					_ruin_piece(place, piece)
				_node(place, REWARDS[rng.randi_range(0, REWARDS.size() - 1)], PEDESTAL_TOP, rng.randf() * TAU,
						"landmark_%d_reward" % i)
			&"camp":
				for p in CAMP:
					_prop(place, load(p[0]), Vector3(p[1].x, 0.0, p[1].y), p[2])
			&"rare":
				var nodes: Array = RARE_NODES.get(l["kind"], [])
				for k in nodes.size():
					var off: Vector2 = nodes[k][1]
					var world: Vector2 = l["pos"] + off.rotated(l["angle"])
					var y := map.height_at(world) - float(l["height"]) - SINK
					_node(place, nodes[k][0], Vector3(off.x, y, off.y), rng.randf() * TAU, "landmark_%d_%d" % [i, k])
				if l["kind"] == &"flower_meadow":
					place.add_child(_meadow(map, l))


static func _ruin_piece(place: Node3D, piece: Array) -> void:
	var size: Vector3 = RUIN_SIZES[piece[0]]
	var prop := _prop(place, load(RUINS % piece[0]), Vector3(piece[1].x, piece[2] + size.y * 0.5, piece[1].y), piece[3])
	prop.set("collision_size", size)


static func _prop(place: Node3D, model: PackedScene, at: Vector3, facing: float) -> StaticBody3D:
	var prop := StaticBody3D.new()
	prop.set_script(PROP)
	prop.set("model", model)
	prop.position = at
	prop.rotation.y = facing
	place.add_child(prop)
	return prop


static func _node(place: Node3D, scene_path: String, at: Vector3, yaw: float, save_id: String) -> void:
	var node := (load(scene_path) as PackedScene).instantiate() as ResourceNode
	node.save_id = StringName(save_id)
	node.name = save_id
	node.position = at
	node.rotation.y = yaw
	place.add_child(node)


## Thick flowers round the meadow's oak, on whatever ground it is (not paths).
static func _meadow(map: ProcgenMap, l: Dictionary) -> SceneryScatter:
	var scatter := SceneryScatter.new()
	scatter.name = "Flowers"
	scatter.top_level = true  # its area is in world coordinates
	var at: Vector2 = l["pos"]
	scatter.area = Rect2(at - Vector2.ONE * 14.0, Vector2.ONE * 28.0)
	scatter.seed = map.sub_seed(&"meadow")
	scatter.spawn_radius = 0.0
	var layers: Array[ScatterLayer] = []
	for look in ["flowers_warm", "flowers_cool", "grass_tuft"]:
		var layer := ScatterLayer.new()
		layer.model = load("res://models/scenery/%s.glb" % look)
		layer.density = 9.0 if look != "grass_tuft" else 5.0
		layer.scale_range = Vector2(1.2, 1.8)
		layer.cluster = Vector2i(3, 7)
		layer.cluster_radius = 1.0
		layer.sway = 0.7
		layer.cast_shadow = false
		layer.visible_distance = 70.0
		var ids: Array[int] = [WorldMap.TEX_DEFAULT, WorldMap.TEX_FOREST, WorldMap.TEX_FIELD]
		layer.allowed_ids = ids
		layers.append(layer)
	scatter.layers = layers
	scatter.edge_ellipse = Vector4(at.x, at.y, 13.0, 13.0)
	return scatter
