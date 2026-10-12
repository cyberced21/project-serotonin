extends SceneTree
## Generates the starter terrain into res://terrain_data. Run headless from the project folder:
##   godot --headless --path . -s res://tools/generate_test_terrain.gd
## WARNING: overwrites any sculpting you've done in res://terrain_data.
##
## Layout: a flat clearing around the gathering area (where the trees, rocks and greybox
## blocks sit, all at height 0), hills rising outside it, a dip with a pond bed, and one tall
## peak in a corner so every colour band of the low-poly shader shows up.

const SIZE := 512                       # heightmap pixels = metres (vertex spacing 1); 2x2 regions
const ORIGIN := Vector3(-256, 0, -256)  # world position of pixel (0, 0) — must sit on the region grid
const CLEARING_CENTER := Vector2(0, -4)
const CLEARING_RADIUS := 28.0
const HILL_RAMP := 40.0                 # metres over which the hills rise out of the clearing
const DATA_DIR := "res://terrain_data"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var terrain := Terrain3D.new()
	root.add_child(terrain)
	await process_frame

	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var bumps := FastNoiseLite.new()
	bumps.seed = 21
	bumps.frequency = 0.06

	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RF)
	for y in SIZE:
		for x in SIZE:
			var w := Vector2(x + ORIGIN.x, y + ORIGIN.z)
			img.set_pixel(x, y, Color(_height(w, noise, bumps), 0, 0))

	var images: Array[Image] = []
	images.resize(Terrain3DRegion.TYPE_MAX)
	images[Terrain3DRegion.TYPE_HEIGHT] = img
	terrain.data.import_images(images, ORIGIN, 0.0, 1.0)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	terrain.data.save_directory(DATA_DIR)
	print("Saved terrain to ", DATA_DIR)
	quit()


func _height(w: Vector2, noise: FastNoiseLite, bumps: FastNoiseLite) -> float:
	var d := w.distance_to(CLEARING_CENTER)
	# 0 inside the clearing, easing up to 1 over HILL_RAMP metres
	var outside := smoothstep(CLEARING_RADIUS, CLEARING_RADIUS + HILL_RAMP, d)
	var hills := (noise.get_noise_2dv(w) * 0.5 + 0.5) * 18.0 + 4.0
	var h := outside * hills
	h += outside * bumps.get_noise_2dv(w) * 1.5          # small lumps, not in the clearing
	h = lerpf(h, -4.0, _bump(w, Vector2(42, 34), 16.0))  # pond dip (sand below -2 m)
	h += _bump(w, Vector2(-92, -92), 30.0) * 38.0        # the snowy peak
	return h


## 1 at `center`, smoothly 0 at `radius`.
func _bump(w: Vector2, center: Vector2, radius: float) -> float:
	return 1.0 - smoothstep(0.0, radius, w.distance_to(center))
