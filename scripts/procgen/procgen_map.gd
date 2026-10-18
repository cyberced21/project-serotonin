class_name ProcgenMap
extends RefCounted
## Builds a 512 × 512 m world from a seed, as arrays: height per pixel (metres) and terrain texture
## id per pixel (WorldMap.TEX_*). Pure data, no nodes, so it runs headless and can be previewed as
## an image. ProcgenWorld hands the result to Terrain3D.
##
## Layout: a flat hub at the origin where you spawn, rolling ground rising out of it, and a
## mountain rim along the edge so you never reach the end of the world.

const SIZE := 512                       # pixels = metres (vertex spacing 1)
const ORIGIN := Vector3(-256, 0, -256)  # world position of pixel (0, 0); on Terrain3D's region grid
const HUB_CENTER := Vector2.ZERO
const HUB_RADIUS := 28.0
## Metres over which the ground rises out of the hub.
const HUB_RAMP := 45.0
## Rolling ground: the hills' height (m) and how wide they are (noise frequency, per metre).
const HILL_HEIGHT := 20.0
const HILL_FREQUENCY := 0.009
const BUMP_HEIGHT := 1.2
## The rim starts this far from the centre (a rounded square, warped) and is RIM_HEIGHT tall at the edge.
const RIM_START := 172.0
const RIM_HEIGHT := 62.0
const RIM_WARP := 22.0

var seed := 0
var heights := PackedFloat32Array()
var ids := PackedByteArray()

var _hills := FastNoiseLite.new()
var _bumps := FastNoiseLite.new()
var _rim_warp := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()


func _init(world_seed: int) -> void:
	seed = world_seed
	_hills.seed = sub_seed(&"hills")
	_hills.frequency = HILL_FREQUENCY
	_hills.fractal_octaves = 4
	_bumps.seed = sub_seed(&"bumps")
	_bumps.frequency = 0.07
	_rim_warp.seed = sub_seed(&"rim_warp")
	_rim_warp.frequency = 0.012
	_ridges.seed = sub_seed(&"ridges")
	_ridges.frequency = 0.02
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 3


## A seed for one part of the generator, so tuning one part doesn't reshuffle the others.
func sub_seed(part: StringName) -> int:
	return hash([seed, part]) & 0x7fffffff


func generate() -> void:
	heights.resize(SIZE * SIZE)
	ids.resize(SIZE * SIZE)
	ids.fill(WorldMap.TEX_DEFAULT)
	for y in SIZE:
		for x in SIZE:
			heights[y * SIZE + x] = _height(world(x, y))


static func world(x: int, y: int) -> Vector2:
	return Vector2(x + ORIGIN.x, y + ORIGIN.z)


## The generated height under a world XZ position (bilinear between pixels).
func height_at(w: Vector2) -> float:
	var p := w - Vector2(ORIGIN.x, ORIGIN.z)
	var x0 := clampi(floori(p.x), 0, SIZE - 2)
	var y0 := clampi(floori(p.y), 0, SIZE - 2)
	var fx := clampf(p.x - x0, 0.0, 1.0)
	var fy := clampf(p.y - y0, 0.0, 1.0)
	var top := lerpf(heights[y0 * SIZE + x0], heights[y0 * SIZE + x0 + 1], fx)
	var bottom := lerpf(heights[(y0 + 1) * SIZE + x0], heights[(y0 + 1) * SIZE + x0 + 1], fx)
	return lerpf(top, bottom, fy)


func height_image() -> Image:
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, heights.to_byte_array())


func _height(w: Vector2) -> float:
	var d := w.distance_to(HUB_CENTER)
	var out := smoothstep(HUB_RADIUS, HUB_RADIUS + HUB_RAMP, d)
	var hills := (_hills.get_noise_2dv(w) * 0.5 + 0.5) * HILL_HEIGHT + _bumps.get_noise_2dv(w) * BUMP_HEIGHT
	var h := hills * out
	# the rim: distance from the centre in a rounded square (a superellipse, so the corners don't
	# crease), bent so it doesn't run in straight lines
	var r := pow(pow(absf(w.x), 4.0) + pow(absf(w.y), 4.0), 0.25) + _rim_warp.get_noise_2dv(w) * RIM_WARP
	var rim := smoothstep(RIM_START, SIZE * 0.5 + 8.0, r)
	h += rim * rim * RIM_HEIGHT + rim * (_ridges.get_noise_2dv(w) * 0.5 + 0.5) * RIM_HEIGHT * 0.35
	return h


## A top-down picture of the map: height as shaded colour bands, for checking a seed at a glance.
func write_preview(path: String) -> Error:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			var h := heights[y * SIZE + x]
			var c: Color
			if h > 38.0:
				c = Color(0.92, 0.94, 0.96)
			elif h > 18.0:
				c = Color(0.47, 0.46, 0.45)
			else:
				c = Color(0.36, 0.55, 0.30).lerp(Color(0.52, 0.42, 0.30), h / 18.0)
			if ids[y * SIZE + x] == WorldMap.TEX_PATH:
				c = Color(0.63, 0.52, 0.40)
			# light from the north-west, so slopes read
			var east := heights[y * SIZE + mini(x + 1, SIZE - 1)] - h
			var south := heights[mini(y + 1, SIZE - 1) * SIZE + x] - h
			var light := clampf(1.0 - (east + south) * 0.25, 0.6, 1.3)
			img.set_pixel(x, y, c * light)
	var hub := Vector2i(int(HUB_CENTER.x - ORIGIN.x), int(HUB_CENTER.y - ORIGIN.z))
	for i in range(-3, 4):
		img.set_pixelv(hub + Vector2i(i, 0), Color.RED)
		img.set_pixelv(hub + Vector2i(0, i), Color.RED)
	return img.save_png(path)
