class_name MineLevel
extends Node3D
## One level of the mine (plans/mine.md), built from its map (MineLayout) and which cells are
## open (Mine). Each open cell is a 4 m stretch of tunnel: rough rock floor, roof and walls. Where
## an open cell meets a hidden one there's a dig face: an ore wall panel (OreWall) in the tunnel's
## end, with the rock round its alcove; dig a couple of layers in and the rest gives way, and the
## cell behind opens. Some walls into solid rock carry a seam instead: a panel you dig a little way
## into for its ore, spent, then grown back a while later. Shored levels get timber frames and
## lamps (cells dug since the last dawn wait for the morning: the prospector puts them in
## overnight); the rest is dark but for your lantern.
## Level space: x and z in metres from the map's corner (cell (x, y) spans x*4..x*4+4 and
## y*4..y*4+4), y up from the floor.

signal opened_cell(cell: Vector2i)

const CELL := MineLayout.CELL
const HEIGHT := MineLayout.HEIGHT
const PANEL_SCENE := preload("res://scenes/ore_wall.tscn")
const ROCK_MATERIAL := preload("res://materials/node_rock.tres")
## Layers a dig face gives way after, and how far into a seam you can dig before it's spent.
const GIVE_WAY := 2
const SEAM_LAYERS := 4
## Seconds a spent seam takes to grow back (rock_regrow shortens it).
const SEAM_REGROW := 900.0
## Every this-many walls into solid rock (by a hash), a seam.
const SEAM_EVERY := 3
const ROUGH := 0.13
const GRID := 0.5
const FLOOR_UV := Vector2(0.3125, 0.5625)  # terrain.dirt
const LAMP_COLOR := Color(1.0, 0.72, 0.44)
## The lamp room's chalk marks on a dig face: what's behind it.
const HINTS := {"C": "a chamber", "L": "the old shaft", "R": "a rail stop", "X": "loose roof!", "F": "water",
	"S": "the stream", "K": "crystal", ".": "more tunnel"}

const FRAME := preload("res://models/mine/frame_square.glb")
const LAMP := preload("res://models/mine/lamp_hanging.glb")
const LAMP_PLAIN := preload("res://models/mine/lamp_hanging_plain.glb")
const RUBBLE := preload("res://models/mine/rubble_pile.glb")
const BOULDER := preload("res://models/mine/boulder_small.glb")
const PLANKS := preload("res://models/mine/planks.glb")
const POSTS := preload("res://models/mine/post_crossbraced.glb")
const DOOR := preload("res://models/mine/door.glb")
const STALACTITE := preload("res://models/mine/stalactite.glb")
const STALACTITES := preload("res://models/mine/stalactite_cluster.glb")
const PUMP_POST := preload("res://models/mine/post.glb")
const PUMP_BUCKET := preload("res://models/mine/bucket.glb")
const CHAIN := preload("res://models/mine/chain.glb")
const BOARDWALK := preload("res://models/mine/boardwalk.glb")
const STREAM_SOUNDS: Array[AudioStream] = [preload("res://audio/mine/stream_1.mp3"), preload("res://audio/mine/stream_2.mp3")]
const PUMP_SOUNDS: Array[AudioStream] = [preload("res://audio/mine/pump_1.mp3"), preload("res://audio/mine/pump_2.mp3")]
const CRYSTAL_SOUND := preload("res://audio/mine/crystal.mp3")
const ROCKFALL: Array[AudioStream] = [preload("res://audio/mine/rockfall_1.wav"), preload("res://audio/mine/rockfall_2.wav")]
const PALETTE_PIECES := ["frame_square", "lamp_hanging", "lamp_hanging_plain", "rubble_pile", "boulder_small",
	"planks", "post_crossbraced", "stalactite", "stalactite_cluster", "chest", "boardwalk", "post_cap", "gate_posts"]

var n := 0
var mine: Node  # Mine
var _rock: Node3D
var _dress: Node3D
var _panels: Dictionary[String, OreWall] = {}
var _noise := FastNoiseLite.new()
var _st: SurfaceTool
var _body: StaticBody3D


func _ready() -> void:
	_noise.seed = 4100 + n
	_noise.frequency = 0.7


## Level space -> the middle of a cell, on the floor.
static func centre(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func kind(c: Vector2i) -> String:
	return MineLayout.at(n, c)


## Rebuilds the rock and dressing from which cells are open; keeps the panels that still stand
## (their digging carries on), adds new ones, takes away those whose cell behind is open now.
func refresh() -> void:
	if _rock:
		_rock.free()
	if _dress:
		_dress.free()
	_rock = Node3D.new()
	_rock.name = "Rock"
	add_child(_rock)
	_dress = Node3D.new()
	_dress.name = "Dressing"
	add_child(_dress)
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body = StaticBody3D.new()
	_body.name = "Body"
	_rock.add_child(_body)
	var want: Dictionary[String, Array] = {}  # panel id -> [cell, dir index, seam]
	var rock_uv: Vector2 = MineLayout.LEVELS[n]["rock"]
	for c in MineLayout.cells(n):
		if not mine.is_open(n, c):
			continue
		var o := centre(c)
		_quad(o + Vector3(-CELL / 2, 0, CELL / 2), Vector3(CELL, 0, 0), Vector3(0, 0, -CELL), FLOOR_UV, 0)
		_quad(o + Vector3(-CELL / 2, HEIGHT, -CELL / 2), Vector3(CELL, 0, 0), Vector3(0, 0, CELL), rock_uv, 1)
		_box(o + Vector3(0, -0.25, 0), Basis.IDENTITY, Vector3(CELL, 0.5, CELL))
		_box(o + Vector3(0, HEIGHT + 0.25, 0), Basis.IDENTITY, Vector3(CELL, 0.5, CELL))
		if not mine.is_passable(n, c):  # an obstacle: plain rock round it till it's cleared
			for d in MineLayout.DIRS:
				if not mine.is_open(n, c + d):
					_wall(c, d, rock_uv)
			continue
		for i in MineLayout.DIRS.size():
			var d := MineLayout.DIRS[i]
			var nb := c + d
			if MineLayout.is_cell(n, nb):
				if mine.is_open(n, nb):
					continue  # open to the next cell (or an obstacle in it)
				want["mine%d_%d_%d_%d" % [n, c.x, c.y, i]] = [c, i, false]
				_alcove(c, d, CELL, rock_uv)
			elif hash([n, c, i]) % SEAM_EVERY == 0:
				want["mine%d_%d_%d_%d" % [n, c.x, c.y, i]] = [c, i, true]
				_alcove(c, d, SEAM_LAYERS * OreWall.LAYER_DEPTH + 0.02, rock_uv)
			else:
				_wall(c, d, rock_uv)
	_st.index()
	_st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "RockMesh"
	mesh.mesh = _st.commit()
	mesh.material_override = ROCK_MATERIAL
	_rock.add_child(mesh)
	_st = null
	for id in _panels.keys():
		if not want.has(id):
			remove_child(_panels[id])  # (out of the tree now: a new one may take its save id at once)
			_panels[id].queue_free()
			_panels.erase(id)
	for id in want:
		if not _panels.has(id):
			_panels[id] = _make_panel(id, want[id][0], want[id][1], want[id][2])
	_dress_cells()


# --- the rock ----------------------------------------------------------------------------------

## The wall of cell c toward d: its plane's middle on the floor, and the axis along it (so that
## along x UP is the wall's facing, back into the cell).
func _wall_frame(c: Vector2i, d: Vector2i) -> Array:
	var d3 := Vector3(d.x, 0, d.y)
	return [centre(c) + d3 * CELL / 2, d3.cross(Vector3.UP), d3]


func _wall(c: Vector2i, d: Vector2i, uv: Vector2) -> void:
	var f := _wall_frame(c, d)
	var o: Vector3 = f[0]
	var u: Vector3 = f[1]
	var d3: Vector3 = f[2]
	_quad(o - u * CELL / 2, u * CELL, Vector3.UP * HEIGHT, uv, 2)
	_box(o + d3 * 0.25 + Vector3.UP * HEIGHT / 2, Basis(u, Vector3.UP, d3), Vector3(CELL, HEIGHT, 0.5))


## A panel's hole in the wall toward d: pillars either side of it, and the alcove it digs back
## into (sides, floor, roof and the bedrock at `depth`), so a dug panel shows rock, not a void.
func _alcove(c: Vector2i, d: Vector2i, depth: float, uv: Vector2) -> void:
	var f := _wall_frame(c, d)
	var o: Vector3 = f[0]
	var u: Vector3 = f[1]
	var d3: Vector3 = f[2]
	var w := OreWall.WIDTH / 2
	var side := CELL / 2 - w
	var basis := Basis(u, Vector3.UP, d3)
	for s: float in [-1.0, 1.0]:  # the pillars' faces in the tunnel
		var a := o + u * (s * (w + side * 0.5) - side * 0.5)
		_quad(a, u * side, Vector3.UP * HEIGHT, uv, 2)
		_box(o + u * s * (w + side / 2) + d3 * depth / 2 + Vector3.UP * HEIGHT / 2, basis, Vector3(side, HEIGHT, depth))
	_quad(o - u * w, d3 * depth, Vector3.UP * HEIGHT, uv, 3)  # left side, facing in
	_quad(o + u * w + d3 * depth, -d3 * depth, Vector3.UP * HEIGHT, uv, 3)  # right side
	_quad(o - u * w, u * OreWall.WIDTH, d3 * depth, FLOOR_UV, 0)  # floor
	_quad(o - u * w + Vector3.UP * HEIGHT, d3 * depth, u * OreWall.WIDTH, uv, 1)  # roof
	_quad(o + d3 * depth - u * w, u * OreWall.WIDTH, Vector3.UP * HEIGHT, MineLayout.LEVELS[2]["rock"], 2)  # bedrock
	_box(o + d3 * depth / 2 + Vector3.DOWN * 0.25, basis, Vector3(OreWall.WIDTH, 0.5, depth))
	_box(o + d3 * depth / 2 + Vector3.UP * (HEIGHT + 0.25), basis, Vector3(OreWall.WIDTH, 0.5, depth))
	_box(o + d3 * (depth + 0.25) + Vector3.UP * HEIGHT / 2, basis, Vector3(OreWall.WIDTH, HEIGHT, 0.5))


## A quad from corner `a` along `u` and `v` (its face toward u x v), gridded and wandered by the
## level's one smooth field, so neighbouring quads wander alike and meet.
func _quad(a: Vector3, u: Vector3, v: Vector3, uv: Vector2, which: int) -> void:
	var nu := maxi(ceili(u.length() / GRID), 1)
	var nv := maxi(ceili(v.length() / GRID), 1)
	var grid := []
	for j in nv + 1:
		var row := []
		for i in nu + 1:
			row.append(_wander(a + u * (float(i) / nu) + v * (float(j) / nv)))
		grid.append(row)
	_st.set_smooth_group(which)
	for j in nv:
		for i in nu:
			var p00: Vector3 = grid[j][i]
			var p10: Vector3 = grid[j][i + 1]
			var p11: Vector3 = grid[j + 1][i + 1]
			var p01: Vector3 = grid[j + 1][i]
			for p in [p00, p11, p10, p00, p01, p11]:  # (clockwise seen from the front: Godot's front)
				_st.set_uv(uv)
				_st.set_color(_shade(p, which))
				_st.add_vertex(p)


func _wander(p: Vector3) -> Vector3:
	var amount := ROUGH if p.y > 0.05 else ROUGH * 0.3  # (the floor stays walkable)
	return p + Vector3(_noise.get_noise_3dv(p), _noise.get_noise_3dv(p + Vector3(31, 0, 0)) * 0.5,
		_noise.get_noise_3dv(p + Vector3(0, 0, 57))) * amount


## The shade the rock shader multiplies in: roofs darker, the foot of the walls darker, mottled.
func _shade(p: Vector3, which: int) -> Color:
	var s := 0.8 + 0.15 * _noise.get_noise_3dv(p * 2.1)
	if which == 1:
		s *= 0.7
	elif which == 0:
		s *= 0.85
	else:
		s *= lerpf(0.72, 1.0, clampf(p.y / 1.4, 0.0, 1.0))
	return Color(s, s, s, 1.0)


func _box(at: Vector3, basis: Basis, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = Transform3D(basis, at)
	_body.add_child(shape)


# --- panels ------------------------------------------------------------------------------------

func _make_panel(id: String, c: Vector2i, i: int, seam: bool) -> OreWall:
	var f := _wall_frame(c, MineLayout.DIRS[i])
	var u: Vector3 = f[1]
	var d3: Vector3 = f[2]
	var p := PANEL_SCENE.instantiate() as OreWall
	p.name = "Panel_%d_%d_%d" % [c.x, c.y, i]
	var h := hash(id)
	p.template = h % OreWall.TEMPLATES
	p.vein_seed = h % 100000
	p.save_id = StringName(id)
	p.richness_base = int(MineLayout.LEVELS[n]["richness"]) + (1 if seam else 0)
	p.stone_tier = int(MineLayout.LEVELS[n]["stone_tier"])
	if seam:
		p.spent_at = SEAM_LAYERS
		p.regrow_time = SEAM_REGROW * (1.0 - Village.stat(&"mine_regrow"))  # (the prospector's ore cart)
	else:
		p.give_way_at = mine.give_way_layers()
	p.transform = Transform3D(Basis(u, Vector3.UP, -d3), f[0])  # face into the cell, digging away from it
	add_child(p)
	if not seam:
		p.gave_way.connect(_on_gave_way.bind(c + MineLayout.DIRS[i], p))
		var first: bool = n == 0 and mine.open_count(0) == 1  # (just the way in: show where to dig)
		if Village.stat(&"mine_hint") > 0.0 or first:  # the lamp room: a chalk mark says what's behind
			var hint := Label3D.new()
			hint.text = "dig here" if first and Village.stat(&"mine_hint") <= 0.0 else HINTS.get(kind(c + MineLayout.DIRS[i]), "more tunnel")
			hint.pixel_size = 0.004
			hint.font_size = 36
			hint.modulate = Color(0.92, 0.9, 0.82, 0.85)
			hint.outline_size = 6
			hint.position = Vector3(0, HEIGHT * 0.78, 0.05)
			p.add_child(hint)
	return p


func _on_gave_way(cell: Vector2i, panel: OreWall) -> void:
	var at := panel.global_transform * Vector3(0, HEIGHT * 0.45, -0.6)
	PopupText.spawn(self, at, "Broke through!", panel.ore_color, 13)
	var fall := AudioStreamPlayer3D.new()
	fall.stream = ROCKFALL.pick_random()
	fall.bus = &"Effects"
	fall.volume_db = -4.0
	add_child(fall)
	fall.global_position = at
	fall.play()
	fall.finished.connect(fall.queue_free)
	Juice.shake(0.35)
	mine.on_broke_through(n, cell, at)
	opened_cell.emit(cell)


## Debug and tests: the panel at the end of cell c toward direction index i, if there is one.
func panel_at(c: Vector2i, i: int) -> OreWall:
	return _panels.get("mine%d_%d_%d_%d" % [n, c.x, c.y, i])


func panels() -> Array[OreWall]:
	var out: Array[OreWall] = []
	out.assign(_panels.values())
	return out


# --- frames, lamps and what's lying about --------------------------------------------------------

func _dress_cells() -> void:
	var shored: bool = mine.is_shored(n)
	for c in MineLayout.cells(n):
		if not mine.is_open(n, c):
			continue
		var k := kind(c)
		var o := centre(c)
		var h := hash([n, c])
		match k:
			"X":
				_collapse(c, o)
			"F":
				_flood(c, o)
			"S":
				_stream(c, o)
			"K":
				_crystals(c, o, h)
		if k == "X" or k == "F":
			continue
		if shored and not mine.is_fresh(n, c):
			var across := _corridor_axis(c)
			if across != Vector3.ZERO and (c.x + c.y) % 2 == 0 and k not in ["C", "K", "S"]:
				_prop("frame_square", FRAME, o, across)
				_lamp(o + Vector3.UP * 2.98, LAMP)
			elif k in ["E", "L", "R"] or (k in ["C", "K"] and (c.x * 3 + c.y) % 2 == 0):
				_lamp(o + Vector3.UP * (HEIGHT - 0.02), LAMP_PLAIN)
		if k in ["C", "."] and h % 5 == 0:  # a heap of spoil against a wall
			_prop("rubble_pile", RUBBLE, o + Vector3((h % 3 - 1) * 1.2, 0, ((h / 3) % 3 - 1) * 1.2), Vector3.FORWARD.rotated(Vector3.UP, h % 7))
		if n == 2 and h % 2 == 0:  # the deep level's roof drips stone
			_prop("stalactite", STALACTITE, o + Vector3((h % 5 - 2) * 0.6, HEIGHT, ((h / 5) % 5 - 2) * 0.6), Vector3.FORWARD)


## For a cell with open cells straight through on one axis only: that axis turned across the
## tunnel (the way a frame faces); else zero.
func _corridor_axis(c: Vector2i) -> Vector3:
	var ew: bool = mine.is_open(n, c + Vector2i(1, 0)) or mine.is_open(n, c + Vector2i(-1, 0))
	var ns: bool = mine.is_open(n, c + Vector2i(0, 1)) or mine.is_open(n, c + Vector2i(0, -1))
	if ew and not ns:
		return Vector3.RIGHT  # tunnel along x: the frame's plane across it
	if ns and not ew:
		return Vector3.BACK
	return Vector3.ZERO


## A piece of the pack (models/mine/), its front (-Z) along `facing`.
func _prop(name_: String, model: PackedScene, at: Vector3, facing: Vector3, collide := false) -> Prop:
	var p := Prop.new()
	p.model = model
	p.own_materials = name_ not in PALETTE_PIECES
	p.collide = collide
	p.position = at
	if facing != Vector3.ZERO:
		p.rotation.y = atan2(-facing.x, -facing.z)
	_dress.add_child(p)
	return p


## A lamp hanging from the roof, lit for good (it's always night down here).
func _lamp(at: Vector3, model: PackedScene) -> void:
	_prop("lamp_hanging", model, at, Vector3.FORWARD)
	var light := OmniLight3D.new()
	light.light_color = LAMP_COLOR
	light.light_energy = 2.0
	light.omni_range = 8.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = at + Vector3.DOWN * 0.45
	light.add_to_group("mine_lamp")
	_dress.add_child(light)


func _collapse(c: Vector2i, o: Vector3) -> void:
	if mine.is_passable(n, c):  # shored: timber props, a little rubble left at the sides
		for s in [-1.0, 1.0]:
			_prop("post_crossbraced", POSTS, o + Vector3(s * 1.4, 0, 0), Vector3.FORWARD)
		_prop("rubble_pile", RUBBLE, o + Vector3(-1.3, 0, 1.3), Vector3.LEFT)
		return
	for i in 7:
		var a := i * 2.4
		_prop("rubble_pile", RUBBLE, o + Vector3(cos(a), 0.0, sin(a)) * (0.4 + i * 0.2), Vector3.FORWARD.rotated(Vector3.UP, a)).scale = Vector3.ONE * 2.2
	for i in 5:
		var b := _prop("boulder_small", BOULDER, o + Vector3((i % 3 - 1) * 1.0, 0.6 + i * 0.35, (i / 3 - 0.5) * 1.2), Vector3.FORWARD.rotated(Vector3.UP, i))
		b.scale = Vector3.ONE * 4.5
	_prop("planks", PLANKS, o + Vector3(0.3, 1.0, 0.2), Vector3.RIGHT).rotation.z = 0.7
	_blocker(c, o, "A roof fall. It'll need timber supports before you can get past (the noticeboard).")


func _flood(c: Vector2i, o: Vector3) -> void:
	var drained: bool = mine.is_passable(n, c)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL, CELL)
	plane.material = _cave_water()
	water.mesh = plane
	water.position = o + Vector3.UP * (0.05 if drained else HEIGHT - 0.4)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dress.add_child(water)
	if drained:
		_bed(PUMP_SOUNDS[hash(c) % 2], o + Vector3.UP, -8.0)
	if drained:  # the pump that did it: a post, a bucket at its spout, the chain up the shaft
		_prop("post", PUMP_POST, o + Vector3(1.4, 0, -1.4), Vector3.FORWARD)
		_prop("bucket", PUMP_BUCKET, o + Vector3(1.1, 0, -1.0), Vector3.LEFT)
		_prop("chain", CHAIN, o + Vector3(1.4, HEIGHT, -1.4), Vector3.FORWARD)
	else:
		_blocker(c, o, "Flooded to the roof. A pump would drain it (the noticeboard).")


## A box filling an obstacle's cell, with something to say when you look at it.
func _blocker(c: Vector2i, o: Vector3, text: String) -> void:
	var s := MineSpot.make(Vector3(CELL, HEIGHT, CELL), func() -> String: return text)
	s.collision_layer |= 1  # (and solid)
	s.position = o
	_dress.add_child(s)
	mine.saw_obstacle(n, kind(c))


func _stream(_c: Vector2i, o: Vector3) -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CELL, 1.1)
	plane.material = _cave_water()
	water.mesh = plane
	water.position = o + Vector3(0, 0.04, 0.9)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.add_to_group("mine_stream")
	_dress.add_child(water)
	_bed(STREAM_SOUNDS[hash(o) % 2], o + Vector3(0, 0.3, 0.9), -6.0)
	for i in 4:
		_prop("boulder_small", BOULDER, o + Vector3(-1.5 + i, 0.0, 0.25 + (i % 2) * 1.3), Vector3.FORWARD.rotated(Vector3.UP, i)).scale = Vector3.ONE * 2.0


## The crystal caverns: clusters of softly glowing crystal and their light; stalactites.
func _crystals(c: Vector2i, o: Vector3, h: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.48, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.4, 1.0)
	mat.emission_energy_multiplier = 1.4
	mat.roughness = 0.2
	for k in 3:
		var at := o + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6))
		if (Vector2(at.x, at.z) - Vector2(o.x, o.z)).length() < 0.9:
			continue  # (keep the middle clear to walk)
		for j in rng.randi_range(3, 6):
			var shard := MeshInstance3D.new()
			var prism := CylinderMesh.new()
			prism.radial_segments = 6
			prism.rings = 1
			var len_ := rng.randf_range(0.35, 1.1)
			prism.top_radius = 0.0
			prism.bottom_radius = rng.randf_range(0.06, 0.13)
			prism.height = len_
			prism.material = mat
			shard.mesh = prism
			var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
			shard.transform = Transform3D(tilt, at + tilt.y * len_ * 0.5)
			shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_dress.add_child(shard)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.7, 0.55, 1.0)
	glow.light_energy = 0.9
	glow.omni_range = 5.0
	glow.position = o + Vector3.UP * 0.8
	glow.add_to_group("mine_lamp")
	_dress.add_child(glow)
	if h % 2 == 0:
		_bed(CRYSTAL_SOUND, o + Vector3.UP, -14.0)
	if h % 3 == 0:
		_prop("stalactite_cluster", STALACTITES, o + Vector3(rng.randf_range(-1, 1), HEIGHT, rng.randf_range(-1, 1)), Vector3.FORWARD)


## A looped sound heard near one spot (the stream, the pump, the crystals' hum), in the dressing.
## Water down here: dark, glossy, catching the lamps.
static func _cave_water() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.11, 0.13)
	m.metallic = 0.4
	m.roughness = 0.08
	return m


func _bed(stream: AudioStream, at: Vector3, trim_db: float) -> void:
	var bed := LoopBed.new()
	bed.stream = stream
	bed.trim_db = trim_db
	bed.positional = true
	bed.unit_size = 4.0
	bed.max_distance = 16.0
	bed.level = 1.0
	bed.position = at
	_dress.add_child(bed)


## Something placed in a cell by the mine (the way out, the lift, the rail stop): parented to this
## level's dressing so a refresh rebuilds it; the mine re-adds its own after each refresh.
func dressing() -> Node3D:
	return _dress
