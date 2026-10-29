class_name MineLayout
## The mine's three levels, drawn by hand on a grid (plans/mine.md). Each cell is CELL metres
## square; one row of a map is a row of cells along +Z, one character a cell along +X:
##   #  solid rock, never dug
##   .  tunnel, hidden in the rock until you dig into it
##   C  a chamber (a tunnel cell that's part of a room: lamps hang from the roof, no frames)
##   E  the way in from the quarry (open from the start)
##   L  the lift shaft (dug into on level 1; where the lift stops on the levels below)
##   R  a rail stop, where the minecart comes in
##   X  a collapse: rubble you can see but not get past until the supports go in
##   F  flooded: water to the roof until the pump drains it
##   S  the underground stream (level 2)
##   K  the crystal caverns (level 3)

const CELL := 4.0
## How high a tunnel is (m): one ore wall panel.
const HEIGHT := 4.0

const LEVELS := [
	{
		"title": "Level 1",
		"map": [
			"#########",
			"#CC..L.##",
			"#CC.##.##",
			"###.#R..#",
			"#X...E#.#",
			"#.###.#.#",
			"#..##...#",
			"#########",
		],
		"richness": 0,  # copper and coal, a little iron (OreWall.RICHNESS)
		"stone_tier": 0,  # any pick
		"rock": Vector2(0.5625, 0.0625),  # stone.4: earthy grey
	},
	{
		"title": "Level 2",
		"map": [
			"#########",
			"###SSS###",
			"####F####",
			"#..CCC..#",
			"#.#.L.R.#",
			"#.#####.#",
			"#...C...#",
			"#########",
		],
		"richness": 4,  # iron, then gold
		"stone_tier": 1,  # rusty rock: a copper pick
		"rock": Vector2(0.4375, 0.0625),  # stone.3, warmed by the light
	},
	{
		"title": "Level 3",
		"map": [
			"#########",
			"#KKK..KK#",
			"#KKK#.KK#",
			"#.#..L#.#",
			"#.##R##.#",
			"#.......#",
			"#########",
		],
		"richness": 7,  # gold and crystal
		"stone_tier": 2,  # deep rock: an iron pick
		"rock": Vector2(0.3125, 0.0625),  # stone.2: dark
	},
]

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## The character at cell `c` of level `n` ('#' outside the map).
static func at(n: int, c: Vector2i) -> String:
	var rows: Array = LEVELS[n]["map"]
	if c.y < 0 or c.y >= rows.size() or c.x < 0 or c.x >= (rows[c.y] as String).length():
		return "#"
	return (rows[c.y] as String)[c.x]


static func is_cell(n: int, c: Vector2i) -> bool:
	return at(n, c) != "#"


## Every cell of level n that's a given kind (one of the map's characters).
static func cells_of(n: int, kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rows: Array = LEVELS[n]["map"]
	for y in rows.size():
		for x in (rows[y] as String).length():
			if (rows[y] as String)[x] == kind:
				out.append(Vector2i(x, y))
	return out


## All the cells of level n.
static func cells(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rows: Array = LEVELS[n]["map"]
	for y in rows.size():
		for x in (rows[y] as String).length():
			if (rows[y] as String)[x] != "#":
				out.append(Vector2i(x, y))
	return out


static func size(n: int) -> Vector2i:
	var rows: Array = LEVELS[n]["map"]
	return Vector2i((rows[0] as String).length(), rows.size())
