class_name BiomeMood
extends Resource
## How a biome looks, sounds and announces itself (data/biomes/*.tres). The Biome autoload blends
## between them as you move, and DayNightSky multiplies the time of day's light by the blend, so
## night still falls in the forest.

@export var display_name := ""
## Under the name on the card you get when you arrive (the first time it says "Discovered").
@export var subtitle := ""
@export_group("Light")
## Fog density, times the scene's own.
@export var fog_density := 1.0
## Multiplies the fog's colour (above 1 is fine: brighter).
@export var fog_tint := Color.WHITE
## Multiplies the ambient light's energy.
@export var ambient := 1.0
## Multiplies the sun's (and the moon's) colour.
@export var sun_tint := Color.WHITE
## Colour saturation of the whole image (1 = as is).
@export var saturation := 1.0
## Volumetric mist (light shafts, haze in the air), times the scene's own.
@export var mist := 1.0
@export_group("Grade")
## Colour grading: tints the darks (shadow_tint) and the brights (highlight_tint) of the whole
## image, white = as is. Blended with the time of day's grade (see ColorGrade).
@export var shadow_tint := Color.WHITE
@export var highlight_tint := Color.WHITE
@export_group("Sound")
## The bed played here by day (Ambience loops it without a seam and crossfades it in and out).
@export var ambience: AudioStream
@export var ambience_db := -14.0
## Weather rather than wildlife (wind on the peak, the quarry's hollow air): plays at night too,
## under the night bed, instead of giving way to it.
@export var ambience_always := false
