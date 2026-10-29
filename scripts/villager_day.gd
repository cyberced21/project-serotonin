class_name VillagerDay
extends RefCounted
## A villager's day (plans/tavern.md): one shape for everyone, staggered so they don't move as a
## herd, with a quirk or two each. Times are hours on DayNight's wall clock (sunrise 06:00,
## sunset 20:00; a night is about 6 minutes, an hour of day about one).
##   SLEEP      home, indoors (they still come to the door if you knock)
##   BREAKFAST  at Rosa's bakery terrace once it's built (plans/tavern.md P4), else pottering at home
##   WORK       at their work spots
##   DUSK       out on the square: a bench, their own spot, a stroll
##   TAVERN     at the tavern once it's open (P5); without one they go home at dark
## Villager asks part() every tick and acts on a change.

enum Part { SLEEP, BREAKFAST, WORK, DUSK, TAVERN }

## The shared day, in clock hours.
const WAKE := 6.0
const BREAKFAST_END := 7.75
const DUSK_FROM := 18.6
const DARK := 20.3
## Bedtime after the tavern, in hours past 24 (24.5 = half past midnight).
const BED := 24.4
## Bedtime after an evening at home (no tavern, or skipping it), and how long the lights stay on
## after coming in late.
const HOME_BED := 22.6
const LIGHTS_AWAKE := 0.35
## Each villager (by their building's id): their offsets from the shared day, in hours, and
## quirks. Keys: wake, breakfast_from (until then they work: dawn fishing), dusk (work ends),
## tavern (how long after dark they get there), bed, and:
##   serves         Rosa: at breakfast she's serving on her terrace, not sitting down
##   strolls        at dusk: a slow round of the square instead of a seat
##   skips_tavern   some nights (this share of them) straight home at dark instead
##   lingers        last out of the tavern
##   plays          plays the fiddle on the tavern's stage, once it has one (Tavern)
const PEOPLE := {
	&"town_hall": {"wake": 0.3, "dusk": -0.2, "tavern": 0.3, "bed": -0.3, "strolls": true},
	&"woodcutter": {"wake": 0.1, "dusk": 0.2, "tavern": 0.1, "bed": 0.5, "lingers": true},
	&"smithy": {"wake": 0.25, "dusk": 0.4, "tavern": 0.2, "bed": 0.1, "skips_tavern": 0.4},
	&"fisher": {"wake": -1.0, "breakfast_from": 7.0, "dusk": -0.1, "tavern": 0.0, "bed": 0.3, "plays": true},
	&"baker_cottage": {"wake": -0.6, "dusk": -0.3, "tavern": 0.4, "bed": -0.6, "serves": true},
	&"prospector_cottage": {"wake": 0.4, "dusk": 0.1, "tavern": 0.25, "bed": 0.0},
	# Maud keeps the tavern: up late, at it till dusk getting ready, there before anyone, last to bed
	&"tavern": {"wake": 1.5, "dusk": 1.5, "tavern": -0.3, "bed": 0.6},
}


## Clock hours (0..24) at DayNight time `t` (the same clock as DayNight.clock_text()).
static func hours(t: float) -> float:
	if t >= DayNight.SUNRISE and t <= DayNight.SUNSET:
		return 6.0 + (t - DayNight.SUNRISE) / (DayNight.SUNSET - DayNight.SUNRISE) * 14.0
	var night := fmod(t - DayNight.SUNSET + 1.0, 1.0) / (1.0 - (DayNight.SUNSET - DayNight.SUNRISE))
	return fmod(20.0 + night * 10.0, 24.0)


## DayNight time at clock hour `h` (0..24): hours()'s inverse.
static func time_at(h: float) -> float:
	h = fposmod(h, 24.0)
	if h >= 6.0 and h <= 20.0:
		return DayNight.SUNRISE + (h - 6.0) / 14.0 * (DayNight.SUNSET - DayNight.SUNRISE)
	var night := fposmod(h - 20.0, 24.0) / 10.0
	return fposmod(DayNight.SUNSET + night * (1.0 - (DayNight.SUNSET - DayNight.SUNRISE)), 1.0)


## Clock hours with the small hours after midnight counted on from 24 (00:30 is 24.5), so an
## evening reads in order.
static func evening_hours(t: float) -> float:
	var h := hours(t)
	return h + 24.0 if h < 12.0 else h


## When villager `id`, home at evening hour `came_in` (evening_hours), puts the lights out.
static func lights_out(id: StringName, came_in: float) -> float:
	return maxf(came_in + LIGHTS_AWAKE, HOME_BED + float(person(id).get("bed", 0.0)))


static func person(id: StringName) -> Dictionary:
	return PEOPLE.get(id, {})


static func has_quirk(id: StringName, quirk: String) -> bool:
	if quirk == "plays" and id == &"woodcutter" and Village.stat(&"tavern_stage") > 0.0:
		return true  # (Bram brings his whistle once there's room on the stage for two)
	return person(id).has(quirk)


## What villager `id` is doing at clock hour `h`. `tavern_open`: there's a tavern to go to;
## `skip_tonight`: they're giving it a miss tonight.
static func part(id: StringName, h: float, tavern_open: bool, skip_tonight := false) -> Part:
	var p := person(id)
	var wake := WAKE + float(p.get("wake", 0.0))
	var breakfast_from := float(p.get("breakfast_from", wake))
	var dusk := DUSK_FROM + float(p.get("dusk", 0.0))
	var tavern_from := DARK + float(p.get("tavern", 0.0))
	var bed := BED + float(p.get("bed", 0.0))
	var out_late := tavern_open and not skip_tonight
	if h < 12.0:
		if out_late and h + 24.0 < bed:
			return Part.TAVERN
		if h < wake:
			return Part.SLEEP
		if h < breakfast_from:
			return Part.WORK
		if h < BREAKFAST_END:
			return Part.BREAKFAST
		return Part.WORK
	if h < dusk:
		return Part.WORK
	if h < DARK:
		return Part.DUSK
	if not out_late:
		return Part.SLEEP
	if h < tavern_from:
		return Part.DUSK
	return Part.TAVERN if h < bed else Part.SLEEP
