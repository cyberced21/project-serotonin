class_name NodeTheme
extends Resource
## How the place a node grows in dresses it: moss, snow, wet, dust and a colour shift, each a
## range the node's look is drawn from (data/themes/, one per biome kind; see plans/themed-nodes.md).
## Only the dressing: what makes copper read as copper (its ore, its break, a tree's cut wood) is
## the model's and never changes.
## Nodes close together share a cluster (NodeSpawner.cluster_at): its draw sets where in each
## range they sit, and each node strays from it by `jitter`, so neighbours look like siblings.
## All of it comes from the seed and the node's position, so nothing needs saving.
## The look goes to the node shaders as two instance uniforms (node_surface.gdshaderinc):
## theme_a = (moss, snow, wet, dust) and theme_b = (hue shift, value, saturation, vein).

## The look of a node no theme dresses: the model as made.
const PLAIN_A := Vector4.ZERO
const PLAIN_B := Vector4(0.0, 1.0, 1.0, 1.0)

## The name shown in tools and the debug menu ("Pine Forest moss").
@export var title := ""
@export_group("Dressing (0..1)")
## Moss and lichen on tops and in hollows.
@export var moss := Vector2(0.0, 0.0)
## Snow on everything facing up.
@export var snow := Vector2(0.0, 0.0)
## Dark, glossy wet round the foot.
@export var wet := Vector2(0.0, 0.0)
## Pale dust over the tops (quarry, dry downs).
@export var dust := Vector2(0.0, 0.0)
@export_group("Colour")
## Hue turned by this much (in turns: 0.05 = 18 degrees), on the weathered skin only.
@export var hue := Vector2(0.0, 0.0)
## Brightness multiplied by this.
@export var value := Vector2(1.0, 1.0)
## Saturation multiplied by this.
@export var saturation := Vector2(1.0, 1.0)
## How brightly the ore glints (1 = as made). Kept near 1: the ore is the node's identity.
@export var vein := Vector2(1.0, 1.0)
@export_group("Clusters")
## How far a node strays from its cluster's draw, as a share of each range (0 = identical siblings).
@export_range(0.0, 1.0) var jitter := 0.25


## The look drawn for cluster seed `cluster`, node seed `node`, as [theme_a, theme_b].
func look(cluster: int, node: int) -> Array[Vector4]:
	var c := RandomNumberGenerator.new()
	c.seed = cluster
	var n := RandomNumberGenerator.new()
	n.seed = node
	var ranges := [moss, snow, wet, dust, hue, value, saturation, vein]
	var v: Array[float] = []
	for r: Vector2 in ranges:
		var t := clampf(c.randf() + n.randf_range(-1.0, 1.0) * jitter, 0.0, 1.0)
		v.append(lerpf(r.x, r.y, t))
	return [Vector4(v[0], v[1], v[2], v[3]), Vector4(v[4], v[5], v[6], v[7])]


## Dresses one mesh with a look from look() (or the plain one).
static func dress(g: GeometryInstance3D, a: Vector4, b: Vector4) -> void:
	g.set_instance_shader_parameter("theme_a", a)
	g.set_instance_shader_parameter("theme_b", b)
