class_name MusicLibrary
extends Resource
## The game's music, by slot (data/music/library.tres): pieces for each time of day and for each
## area, plus the main menu's. The Music autoload picks from these. CC0 tracks only
## (plans/cozy-sound.md); a slot left empty is simply never picked.

@export_group("Time of day")
@export var morning: Array[AudioStream] = []
@export var day: Array[AudioStream] = []
@export var evening: Array[AudioStream] = []
@export var night: Array[AudioStream] = []
@export_group("Areas")
@export var village: Array[AudioStream] = []
@export var forest: Array[AudioStream] = []
@export var lake: Array[AudioStream] = []
@export var mine: Array[AudioStream] = []
@export_group("Menu")
@export var menu: Array[AudioStream] = []
@export_group("Later")
## Heard from the tavern at night (cozy chunk 8); not picked by the Music autoload yet.
@export var tavern: Array[AudioStream] = []
@export_group("Levels")
## Every piece plays this much louder or quieter (dB), so tracks from different sources sit
## together: keyed by the stream's resource path.
@export var trim_db: Dictionary[String, float] = {}
## Short pieces play this many times back to back (a 45 s loop would barely register), keyed
## like trim_db. Missing: once.
@export var repeats: Dictionary[String, int] = {}


## The pieces in `slot` (&"morning", &"village", ...), or none.
func pieces(slot: StringName) -> Array[AudioStream]:
	var list: Variant = get(slot)
	return list if list is Array else ([] as Array[AudioStream])
