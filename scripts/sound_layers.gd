class_name SoundLayers
extends Resource
## A sound built from several layers played together (a pickaxe hit = metal tink + stone crack +
## low thump + a gravel trickle a moment later). Each layer is randomized on its own, so repeats
## don't sound identical. Make one as a .tres (audio/mining/), add SoundLayer entries, and play it
## with Sfx.play_at() (in the world) or Sfx.play_layers() (on the player).

@export var layers: Array[SoundLayer] = []
## Audio bus every layer plays on (see default_bus_layout.tres).
@export var bus: StringName = &"SFX"
## Positional only: distance (m) at which it's at full volume, and beyond which it's silent.
@export var unit_size := 4.0
@export var max_distance := 50.0
