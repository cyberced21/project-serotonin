extends Node
## Reverb per place (plans/cozy-sound.md, phase 10): the world's sounds -- gathering (SFX, with
## Debris under it) and footsteps (Movement) -- ring a little differently by where you stand:
## barely at all in the open meadows, soft and close under the pines, a long slap off the far
## shore at Stillwater, a late echo off the mountain at Frostpeak, and hard stone at the quarry.
## Interface sounds, pickups and fishing (the Effects bus) stay dry, as do ambience (already
## recorded in its place) and music. Indoor reverb waits for interiors.
## Each bus gets one AudioEffectReverb ahead of its other effects; its settings ease to the
## place's over BLEND seconds, and go dry in the menus.

## Per place: room size, damping (how dull the tail), wet (how much of it you hear), predelay
## (ms: how far off the first reflection), hipass (keeps the low end out of the tail).
## &"" is the open hills between biomes.
const PLACES := {
	&"": {"room": 0.35, "damp": 0.7, "wet": 0.05, "pre": 20.0, "hipass": 0.2},
	&"clearing": {"room": 0.35, "damp": 0.7, "wet": 0.06, "pre": 20.0, "hipass": 0.2},
	&"hearthvale": {"room": 0.4, "damp": 0.6, "wet": 0.08, "pre": 25.0, "hipass": 0.2},  # walls to bounce off
	&"goldmeadow": {"room": 0.3, "damp": 0.75, "wet": 0.04, "pre": 20.0, "hipass": 0.2},
	&"pinewood": {"room": 0.5, "damp": 0.65, "wet": 0.13, "pre": 15.0, "hipass": 0.25},
	&"stillwater": {"room": 0.6, "damp": 0.4, "wet": 0.1, "pre": 70.0, "hipass": 0.3},
	&"frostpeak": {"room": 0.75, "damp": 0.45, "wet": 0.12, "pre": 130.0, "hipass": 0.3},
	&"quarry": {"room": 0.75, "damp": 0.3, "wet": 0.2, "pre": 35.0, "hipass": 0.2},
}
const BUSES: Array[StringName] = [&"SFX", &"Movement"]
## Footsteps sit close to you: a little less of the room on them.
const MOVEMENT_WET := 0.7
## Seconds to settle into a new place.
const BLEND := 2.5

var _reverbs: Array[AudioEffectReverb] = []
## Set by tools (tools/record_sfx_chain.gd) to keep a place's reverb on with no player about.
var hold := false
var _now := {"room": 0.0, "damp": 0.5, "wet": 0.0, "pre": 20.0, "hipass": 0.2}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in BUSES:
		var r := AudioEffectReverb.new()
		r.resource_name = "PlaceReverb"
		r.dry = 1.0
		r.wet = 0.0
		r.spread = 0.8
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), r, 0)
		_reverbs.append(r)


## The settings for where the player stands now (dry in the menus).
static func target() -> Dictionary:
	var player := (Engine.get_main_loop() as SceneTree).get_first_node_in_group("player")
	if player == null:
		return {"room": 0.0, "damp": 0.5, "wet": 0.0, "pre": 20.0, "hipass": 0.2}
	return PLACES.get(Biome.current, PLACES[&""])


func _process(delta: float) -> void:
	if hold:
		return
	var want := target()
	var k := 1.0 - exp(-delta * 3.0 / BLEND)
	for key in _now:
		_now[key] = lerpf(_now[key], want[key], k)
	_apply()


## Jumps straight to a place's reverb and holds it there (for tools).
func hold_place(place: StringName) -> void:
	hold = true
	_now = PLACES[place].duplicate()
	_apply()


func _apply() -> void:
	for i in _reverbs.size():
		var r := _reverbs[i]
		r.room_size = _now["room"]
		r.damping = _now["damp"]
		r.predelay_msec = _now["pre"]
		r.hipass = _now["hipass"]
		r.wet = _now["wet"] * (MOVEMENT_WET if BUSES[i] == &"Movement" else 1.0)
