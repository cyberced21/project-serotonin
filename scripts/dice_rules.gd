class_name DiceRules
extends RefCounted
## The tavern's dice game (plans/tavern.md), "Hound's Luck": press your luck with five dice, first
## to TARGET wins, played for nothing but the chalkboard.
##   Roll. Every die that scores is set aside and counts toward your turn: each 1 is 100, each 5
##   is 50, three of a kind is the face x 100 (three 1s are 1000; the three don't also count on
##   their own). Then roll the rest again, or stop and bank the turn. A roll where nothing scores
##   is a bust: the turn's points are lost. Score with all five and you get all five back.
## Villagers decide with their style (wants_roll): when they're content to stop, and how many dice
## left still tempt them to roll on regardless.

const DICE := 5
const TARGET := 2000
## The usual style, and how each villager (by building id) plays: stop once the turn's worth
## `stop` points, unless `push` or more dice are left to roll.
const STYLE := {"stop": 400, "push": 4}
const STYLES := {
	&"woodcutter": {"stop": 300, "push": 5},  # Bram plays it safe
	&"smithy": {"stop": 650, "push": 3},  # Greta pushes her luck
	&"fisher": {"stop": 350, "push": 4},
	&"town_hall": {"stop": 450, "push": 4},
	&"baker_cottage": {"stop": 400, "push": 5},
	&"prospector_cottage": {"stop": 500, "push": 3},
}
## Falling this far behind makes anyone bolder: content only with this much more.
const BEHIND := 600
const BEHIND_BOLDER := 250


## What a roll scores: {"points": int, "keep": indexes of the dice that score}. 0 points: bust.
static func score(roll: Array[int]) -> Dictionary:
	var by_face := {}
	for i in roll.size():
		if not by_face.has(roll[i]):
			by_face[roll[i]] = []
		by_face[roll[i]].append(i)
	var points := 0
	var keep: Array[int] = []
	for face in range(1, 7):
		var at: Array = by_face.get(face, [])
		if at.size() >= 3:
			points += 1000 if face == 1 else face * 100
			for j in 3:
				keep.append(at[j])
			at = at.slice(3)
		if face == 1 or face == 5:
			for i in at:
				points += 100 if face == 1 else 50
				keep.append(i)
	keep.sort()
	return {"points": points, "keep": keep}


static func style_of(id: StringName) -> Dictionary:
	return STYLES.get(id, STYLE)


## Whether someone playing `style` rolls again, with `turn` points so far this turn and `left`
## dice to roll; `mine` and `theirs` are the banked scores.
static func wants_roll(style: Dictionary, turn: int, left: int, mine: int, theirs: int) -> bool:
	if mine + turn >= TARGET:
		return false  # that's the game: stop
	var stop: int = style["stop"]
	if theirs - mine >= BEHIND:
		stop += BEHIND_BOLDER
	if theirs >= TARGET - 300 and mine + turn < theirs:
		return true  # they're about to win: nothing to lose
	return turn < stop or left >= int(style["push"])


## A random roll of `n` dice (for tests, and anywhere the dice aren't thrown for real).
static func random_roll(n: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(rng.randi_range(1, 6))
	return out
