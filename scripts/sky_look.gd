class_name SkyLook
extends Resource
## Every colour and number the sky is tuned with: palettes for each time of day, the sun, exposure
## and bloom, fog and mist. One file, data/sky_look.tres. DayNightSky reads it every frame, so the
## debug menu's Sky tab can change it live and save it back (see plans/mood-pass.md).

const PATH := "res://data/sky_look.tres"

static var _active: SkyLook

@export_group("Day")
@export var day_top := Color(0.36, 0.47, 0.62)
@export var day_horizon := Color(0.66, 0.74, 0.78)
## The sun's colour high in the sky (near the horizon it takes the sunrise / sunset light).
@export var noon_light := Color(1.0, 0.95, 0.86)
## The sun's energy at noon, and when low.
@export_range(0.0, 2.0, 0.01) var noon_energy := 0.82
@export_range(0.0, 2.0, 0.01) var low_energy := 0.55
## Ambient (sky) light by day: higher lifts the shadows (softer, less contrast).
@export_range(0.0, 2.0, 0.01) var day_ambient := 1.15
## How dark the sun's shadows get by day (1 = full).
@export_range(0.0, 1.0, 0.01) var shadow_strength := 0.85
## The grade by day, away from sunrise and sunset: a faint warm tint.
@export var noon_grade_dark := Color(1.02, 1.0, 0.97)
@export var noon_grade_bright := Color(1.03, 1.0, 0.94)

@export_group("Twilight")
## How far the sunrise / sunset colours reach into the day and into the night (fractions of a day;
## a day is 20 minutes). The colour is strong for about half of each.
@export_range(0.01, 0.4, 0.005) var twilight_day_side := 0.12
@export_range(0.01, 0.4, 0.005) var twilight_night_side := 0.18
## How far the sky's top and horizon go to the twilight palette at its peak.
@export_range(0.0, 1.0, 0.01) var twilight_top := 0.7
@export_range(0.0, 1.0, 0.01) var twilight_horizon := 0.85
## After sunset / before sunrise: how much of the twilight's warm light stays on the world.
@export_range(0.0, 1.0, 0.01) var afterglow := 0.6

@export_group("Sunrise")
## Golden and fresh: yellow-orange horizon under a clean pale-blue top.
@export var sunrise_top := Color(0.42, 0.56, 0.74)
@export var sunrise_horizon := Color(1.0, 0.78, 0.42)
## The light on the world, and the clouds' lit side.
@export var sunrise_light := Color(1.0, 0.8, 0.5)
@export var sunrise_clouds := Color(1.0, 0.86, 0.6)
## The grade: a tint for the darks and one for the brights.
@export var sunrise_grade_dark := Color(0.95, 0.97, 1.05)
@export var sunrise_grade_bright := Color(1.06, 1.0, 0.86)

@export_group("Sunset")
## Clearly pink: rose horizon under a lilac top.
@export var sunset_top := Color(0.42, 0.33, 0.58)
@export var sunset_horizon := Color(1.0, 0.55, 0.58)
@export var sunset_light := Color(1.0, 0.62, 0.6)
@export var sunset_clouds := Color(1.0, 0.55, 0.72)
@export var sunset_grade_dark := Color(0.98, 0.88, 1.06)
@export var sunset_grade_bright := Color(1.08, 0.93, 0.92)

@export_group("Night")
## Moonlit and readable: paths and silhouettes show without a lantern; lamps are warm pools.
@export var night_top := Color(0.05, 0.08, 0.17)
@export var night_horizon := Color(0.15, 0.2, 0.32)
@export var moon_light := Color(0.66, 0.74, 1.0)
@export_range(0.0, 1.0, 0.01) var moon_energy := 0.36
@export_range(0.0, 2.0, 0.01) var night_ambient := 0.45
## Sky brightness at night (the background's energy).
@export_range(0.0, 1.0, 0.01) var night_sky := 0.6
@export var night_grade_dark := Color(0.84, 0.92, 1.14)
@export var night_grade_bright := Color(0.92, 0.98, 1.08)

@export_group("Sun")
## The disc's angular radius (radians) and brightness.
@export_range(0.005, 0.1, 0.001) var sun_size := 0.03
@export_range(0.0, 4.0, 0.05) var sun_brightness := 1.6
## The tight halo round the disc: how bright, and how fast it falls off (higher = tighter).
@export_range(0.0, 1.0, 0.01) var sun_halo := 0.12
@export_range(2.0, 30.0, 0.5) var sun_halo_falloff := 14.0
## The wide warm glow round the sun: always, and extra when it's low.
@export_range(0.0, 0.5, 0.01) var sun_glow := 0.04
@export_range(0.0, 0.5, 0.01) var sun_glow_low := 0.22

@export_group("Exposure")
@export_range(0.5, 2.0, 0.01) var exposure := 0.95
## Bloom: how bright something must be to glow (lamps are about 2), and how strongly it does.
@export_range(0.0, 4.0, 0.05) var glow_threshold := 1.2
@export_range(0.0, 2.0, 0.01) var glow_intensity := 0.45

@export_group("Fog")
## Distance haze: clear up to fog_begin metres, thickening to fog_haze (0..1, how much of a far
## thing it hides) at fog_end; fog_curve > 1 keeps the middle distance clearer.
@export_range(0.0, 500.0, 5.0) var fog_begin := 140.0
@export_range(50.0, 2000.0, 10.0) var fog_end := 650.0
@export_range(0.0, 1.0, 0.01) var fog_haze := 0.7
@export_range(0.2, 4.0, 0.05) var fog_curve := 1.2
## How much the haze takes the sky's colour behind it (aerial perspective) rather than a flat tint.
@export_range(0.0, 1.0, 0.01) var fog_aerial := 0.6
## Biomes' extra fog and mist go no higher than this many times the base.
@export_range(1.0, 3.0, 0.05) var biome_cap := 1.2

@export_group("Mist")
## Volumetric mist in the air everywhere, and how many times thicker at the morning peak and at night.
@export_range(0.0, 0.03, 0.0005) var mist_density := 0.003
@export_range(0.0, 5.0, 0.05) var morning_mist := 0.4
@export_range(0.0, 2.0, 0.05) var night_mist := 0.0
## Morning mist lying low over ponds, lakes and rivers (each WaterBody's Mist volume): density at
## its peak, when that is (DayNight time) and how long either side it lasts (fractions of a day).
@export_range(0.0, 0.5, 0.005) var water_mist := 0.12
@export_range(0.0, 0.5, 0.005) var mist_peak := 0.19
@export_range(0.01, 0.3, 0.005) var mist_width := 0.1
## Light shafts through the mist (times the sun's).
@export_range(0.0, 2.0, 0.05) var shafts := 0.5


## The look in use: data/sky_look.tres, loaded once (the Sky tab edits this same object).
static func active() -> SkyLook:
	if _active == null:
		_active = load(PATH) as SkyLook
		if _active == null:
			_active = SkyLook.new()
	return _active


## Reloads the look from disk, dropping unsaved edits.
static func revert() -> void:
	_active = ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as SkyLook


## Saves the look in use back to data/sky_look.tres (only works running from the project).
static func save_active() -> Error:
	return ResourceSaver.save(active(), PATH)
