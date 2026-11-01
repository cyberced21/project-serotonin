extends Node
## The waves on the water (plans/water.md, phase 3): a few Gerstner waves (rolling waves whose
## crests sharpen and whose water moves in little circles) running with the shared wind. The water
## shader draws the same sum (shaders/water.gdshader, `gerstner`) on the same clock (the global
## shader uniform water_time, set here every frame), so what floats on the water (you swimming,
## the float) rides exactly the surface you see. Keep WAVES in step with the shader's.
## Each body of water scales them (WaterBody.wave_scale): the lake's chop, a pond's ripple.

## [angle off the wind (rad), wavelength (m), height (m, at scale 1)]
const WAVES := [
	[0.0, 7.0, 0.05],
	[0.5, 4.3, 0.035],
	[-0.6, 2.9, 0.022],
	[1.1, 1.9, 0.012],
]
## How sharp the crests are (0 = plain sine swell, 1 = just short of curling over).
const STEEPNESS := 0.5
## Slower than real deep water: a cosy lap, not a gale.
const PACE := 0.7
## The clock wraps after this long (s), so it stays precise in a float.
const WRAP := 10000.0
const G := 9.8

var time := 0.0
var wind := Vector2(0.8, 0.6)


func _ready() -> void:
	var w: Variant = ProjectSettings.get_setting("shader_globals/wind_direction", {})
	if w is Dictionary and (w as Dictionary).get("value") is Vector2:
		wind = ((w as Dictionary)["value"] as Vector2).normalized()


func _process(delta: float) -> void:
	time = fmod(time + delta, WRAP)
	RenderingServer.global_shader_parameter_set(&"water_time", time)


## How far the waves lift the surface at `p` (world XZ) right now, at `scale` (m, + = up).
## (Read at the point itself, not where the circling water carries it: close enough for these.)
func height(p: Vector2, scale: float) -> float:
	if scale == 0.0:
		return 0.0
	var y := 0.0
	for w in WAVES:
		var dir := wind.rotated(w[0])
		var k := TAU / float(w[1])
		y += float(w[2]) * sin(k * (dir.dot(p) - sqrt(G / k) * PACE * time))
	return y * scale
