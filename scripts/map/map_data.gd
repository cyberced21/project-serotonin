class_name MapData
extends Node
## What the maps draw (Minimap, WorldMapScreen), read from the world once it's loaded: a grid of
## samples over the terrain's regions, packed into two small textures for the parchment shader
## (shaders/map_parchment.gdshader), plus where each biome's name goes. It only asks the Terrain3D
## data, the water bodies and Biome what's where. The HUD makes one per world (group "map_data"); it samples a slice
## every frame (BUDGET_MS) so loading in doesn't hitch, and says `built` when done.
##
##   heights: RGF   R ground height (m), G water depth (m, 0 on land)
##   kinds:   RGBA8 R ground texture id (WorldMap.TEX_*), G biome (index into `biomes` + 1),
##                  B road (1 ring road, 0.5 path), A forest

signal built

## The most samples across the longer side (a normal 512 m world: 2 m a sample).
const MAX_SAMPLES := 320
## A biome patch needs this much ground (m²) for its name to be written on the map.
const LABEL_MIN_AREA := 2500.0
const BUDGET_MS := 3.0

var rect := Rect2()  # the sampled world area (XZ, metres)
var step := 2.0  # metres per sample
var heights: Image
var kinds: Image
var height_range := Vector2(0.0, 1.0)  # lowest and highest ground (m)
var biomes: Array[StringName] = []
## Where each biome's name is written: [{"text", "pos" (world XZ), "id"}].
var labels: Array[Dictionary] = []
var height_tex: ImageTexture
var kind_tex: ImageTexture
var is_built := false

var _terrain: Terrain3D
var _waters: Array = []  # [WaterBody, its XZ bounds]
var _size := Vector2i.ZERO
var _row := 0


func _ready() -> void:
	add_to_group("map_data")
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if is_built:
		set_process(false)
		return
	if _terrain == null:
		if not _world_ready():
			return
		_begin()
	var until := Time.get_ticks_usec() + int(BUDGET_MS * 1000.0)
	while _row < _size.y and Time.get_ticks_usec() < until:
		_sample_row(_row)
		_row += 1
	if _row >= _size.y:
		_finish()


## Loaded: the player's in and no loading screen is up.
func _world_ready() -> bool:
	var tree := get_tree()
	if tree.get_first_node_in_group("player") == null:
		return false
	var t := tree.get_first_node_in_group("terrain") as Terrain3D
	return t != null and t.data != null and not t.data.get_region_locations().is_empty()


func _begin() -> void:
	_terrain = get_tree().get_first_node_in_group("terrain") as Terrain3D
	var region := float(_terrain.region_size) * _terrain.vertex_spacing
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for loc: Vector2i in _terrain.data.get_region_locations():
		lo = lo.min(Vector2(loc) * region)
		hi = hi.max(Vector2(loc + Vector2i.ONE) * region)
	rect = Rect2(lo, hi - lo)
	step = maxf(ceilf(maxf(rect.size.x, rect.size.y) / MAX_SAMPLES), 1.0)
	_size = Vector2i(ceili(rect.size.x / step), ceili(rect.size.y / step))
	heights = Image.create_empty(_size.x, _size.y, false, Image.FORMAT_RGF)
	kinds = Image.create_empty(_size.x, _size.y, false, Image.FORMAT_RGBA8)
	height_range = Vector2(INF, -INF)
	for w in get_tree().get_nodes_in_group("water"):
		var box := (w.get_node("Volume") as CollisionShape3D)
		var half: Vector3 = (box.shape as BoxShape3D).size / 2.0
		var a := box.global_transform * Vector3(-half.x, 0, -half.z)
		var b := box.global_transform * Vector3(half.x, 0, half.z)
		var c := box.global_transform * Vector3(-half.x, 0, half.z)
		var d := box.global_transform * Vector3(half.x, 0, -half.z)
		var bounds := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).expand(Vector2(c.x, c.z)).expand(Vector2(d.x, d.z))
		_waters.append([w, bounds])
	_row = 0


func _sample_row(y: int) -> void:
	var data := _terrain.data
	for x in _size.x:
		var p := rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * step
		var at := Vector3(p.x, 0.0, p.y)
		var h: float = data.get_height(at)
		if is_nan(h):
			heights.set_pixel(x, y, Color(-1000.0, 0.0, 0.0))  # (no ground here: off the map)
			continue
		height_range = Vector2(minf(height_range.x, h), maxf(height_range.y, h))
		at.y = h
		var depth := 0.0
		for wb: Array in _waters:
			if (wb[1] as Rect2).has_point(p) and wb[0].contains(at):
				depth = maxf(depth, float(wb[0].surface_height) - h)
		var tex: int = data.get_control_base_id(at)
		var biome := Biome.biome_at(at)
		var bi := biomes.find(biome)
		if bi < 0 and biome != &"":
			biomes.append(biome)
			bi = biomes.size() - 1
		var road := 1.0 if tex == WorldMap.TEX_ROAD else 0.5 if tex == WorldMap.TEX_PATH else 0.0
		var forest := 1.0 if tex == WorldMap.TEX_FOREST or biome == &"pinewood" else 0.0
		heights.set_pixel(x, y, Color(h, depth, 0.0))
		kinds.set_pixel(x, y, Color(tex / 255.0, (bi + 1) / 255.0, road, forest))


func _finish() -> void:
	if height_range.x > height_range.y:
		height_range = Vector2(0.0, 1.0)
	height_tex = ImageTexture.create_from_image(heights)
	kind_tex = ImageTexture.create_from_image(kinds)
	_place_labels()
	is_built = true
	built.emit()


## One name per biome patch big enough to hold it (a biome can have several, in a large world),
## at the patch's sample nearest its middle, so the name sits inside it.
func _place_labels() -> void:
	labels.clear()
	var seen := PackedByteArray()
	seen.resize(_size.x * _size.y)
	for y in _size.y:
		for x in _size.x:
			var i := y * _size.x + x
			if seen[i] != 0:
				continue
			var b := kinds.get_pixel(x, y).g8
			seen[i] = 1
			if b == 0:
				continue
			var patch: Array[Vector2i] = []
			var todo: Array[Vector2i] = [Vector2i(x, y)]
			while not todo.is_empty():
				var c: Vector2i = todo.pop_back()
				patch.append(c)
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := c + o
					if n.x < 0 or n.y < 0 or n.x >= _size.x or n.y >= _size.y:
						continue
					var j := n.y * _size.x + n.x
					if seen[j] == 0 and kinds.get_pixel(n.x, n.y).g8 == b:
						seen[j] = 1
						todo.append(n)
			if patch.size() * step * step < LABEL_MIN_AREA:
				continue
			var mid := Vector2.ZERO
			for c in patch:
				mid += Vector2(c)
			mid /= patch.size()
			var best := patch[0]
			for c in patch:
				if Vector2(c).distance_squared_to(mid) < Vector2(best).distance_squared_to(mid):
					best = c
			var id := biomes[b - 1]
			labels.append({"text": biome_name(id), "id": id,
				"pos": rect.position + (Vector2(best) + Vector2(0.5, 0.5)) * step})


## A biome's name on the map.
static func biome_name(id: StringName) -> String:
	var mood: BiomeMood = Biome.MOODS.get(id)
	return mood.display_name if mood and mood.display_name != "" else String(id).capitalize()


## The data texture's UV for a world XZ point.
func uv_of(p: Vector2) -> Vector2:
	return (p - rect.position) / rect.size
