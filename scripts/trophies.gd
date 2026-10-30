class_name Trophies
extends RefCounted
## Trophies for your wall (plans/trophies.md): rare finds you carry home and hang yourself. Each
## is a record, not a stack of items, so it keeps its own label: what it is, where you found it,
## on which day (and a fish's species). Keepsakes only: no perks, never sold.
## The ones you carry and the ones hung (by plaque) live here, saved with your home (Home).
## Found: rolled when a node breaks (ResourceNode._break: roll()), a Huge fish landed (fish()),
## the peak's feather and the lake's shell picked up (TrophyFind), the dog's stick (Home).

## The kinds: name, how it reads on a label.
const KINDS := {
	&"log": "Trophy log",
	&"fish": "Huge fish",
	&"geode": "Geode",
	&"sheaf": "Golden sheaf",
	&"feather": "Peak feather",
	&"shell": "Lake shell",
	&"stick": "The dog's stick",
	&"fossil": "Fossil",
	&"flower": "Haven flower",
}
## The small ones (they fit the Homestead's mantel as well as the wall).
const SMALL: Array[StringName] = [&"geode", &"feather", &"shell", &"fossil", &"flower"]
## Chance per node broken (plans/trophies.md): a tree felled, an ore vein from iron up, a harvest.
const LOG_CHANCE := 1.0 / 150.0
const GEODE_CHANCE := 1.0 / 120.0
const SHEAF_CHANCE := 1.0 / 200.0
const GEODE_ORES: Array[StringName] = [&"iron", &"gold", &"crystal"]
const FOUND_COLOR := Color("ffd27a")

## Records you're carrying ({kind, species, where, day}), and the hung ones by place
## ("TrophySlot1".., "MantelSpot1"..).
static var carried: Array[Dictionary] = []
static var hung: Dictionary = {}


static func clear() -> void:
	carried.clear()
	hung.clear()


static func to_dict() -> Dictionary:
	return {"carried": carried.duplicate(true), "hung": hung.duplicate(true)}


static func from_dict(d: Dictionary) -> void:
	clear()
	for r in d.get("carried", []):
		carried.append(r)
	var h: Dictionary = d.get("hung", {})
	for k in h:
		hung[k] = h[k]


## A new trophy in your pack: a popup and a chime where it was found.
static func found(kind: StringName, at: Vector3, species := &"") -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var r := {"kind": String(kind), "species": String(species), "where": _place_name(at), "day": _today(tree)}
	carried.append(r)
	if tree and tree.current_scene:
		PopupText.spawn(tree.current_scene, at + Vector3.UP * 1.2, "A trophy! %s" % title(r), FOUND_COLOR, 12)
		PopupText.spawn(tree.current_scene, at + Vector3.UP * 0.9, "Take it home for your wall", FOUND_COLOR, 8, 0.5)
		Music.play_cue(&"discovery")
	SaveGame.mark_dirty()
	_changed()
	return r


## What it is: "Trophy log", "Huge pike".
static func title(r: Dictionary) -> String:
	if r.get("kind") == "fish" and String(r.get("species", "")) != "":
		return "Huge %s" % Items.display_name(StringName(r["species"])).to_lower()
	return KINDS.get(StringName(r.get("kind", "")), "A trophy")


## Its brass label: "Huge pike, Stillwater, day 12".
static func label(r: Dictionary) -> String:
	var parts := PackedStringArray([title(r)])
	if String(r.get("where", "")) != "":
		parts.append(r["where"])
	parts.append("day %d" % int(r.get("day", 0)))
	return ", ".join(parts)


## A node broke (ResourceNode._break): maybe a trophy with it.
static func roll(node: ResourceNode) -> void:
	var kind := &""
	if node.skill == &"woodcutting" and randf() < LOG_CHANCE:
		kind = &"log"
	elif node.skill == &"mining" and node.item in GEODE_ORES and randf() < GEODE_CHANCE:
		kind = &"geode"
	elif node.skill == &"farming" and randf() < SHEAF_CHANCE:
		kind = &"sheaf"
	if kind != &"":
		found(kind, node.global_position)


## A fish landed (rod or spear): a Huge one is a trophy too (the fish still goes in your pack).
static func fish(item: StringName, count: int, at: Vector3) -> void:
	if count >= 3:  # (FishSize.count: Huge counts 3)
		found(&"fish", at, item)


## The looks picked on the trophy page (2026-10-29): models/trophies/<kind>_<look>.glb, the fish
## one per species (fish_<look>_<species>.glb).
const LOOKS := {&"log": "b", &"fish": "a", &"geode": "b", &"sheaf": "b", &"feather": "a", &"shell": "b", &"stick": "b", &"fossil": "a", &"flower": "a"}


## Its model's name in models/trophies/.
static func model(r: Dictionary) -> String:
	var kind := StringName(r.get("kind", ""))
	if kind == &"fish":
		return "fish_%s_%s" % [LOOKS[kind], r.get("species", "pike")]
	return "%s_%s" % [kind, LOOKS.get(kind, "a")]


## The trophies you're carrying that fit a place (the mantel takes only the small ones).
static func fitting(small_only: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in carried:
		if not small_only or StringName(r.get("kind", "")) in SMALL:
			out.append(r)
	return out


## Hang `r` at `place` ({} to clear it).
static func hang(place: String, r: Dictionary) -> void:
	if r.is_empty():
		hung.erase(place)
	else:
		hung[place] = r
	SaveGame.mark_dirty()
	_changed()


## Take `r` out of your pack (to hang it).
static func take(r: Dictionary) -> void:
	carried.erase(r)
	_changed()


static func give_back(r: Dictionary) -> void:
	carried.append(r)
	_changed()


## Old trophy logs (items, from before trophies were records) become records.
static func adopt_old_logs() -> void:
	var n := Inventory.count(&"trophy_log")
	if n <= 0:
		return
	Inventory.set_count(&"trophy_log", 0)
	for i in n:
		carried.append({"kind": "log", "species": "", "where": "", "day": 0})
	_changed()


static func _changed() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		for n in tree.get_nodes_in_group("trophies_listener"):
			n.call("trophies_changed")


static func _today(tree: SceneTree) -> int:
	var home := tree.get_first_node_in_group("home") if tree else null
	return int(home.get("_day")) + 1 if home else 1


static func _place_name(at: Vector3) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var d := tree.get_first_node_in_group("map_data") as MapData if tree else null
	if d and d.is_built:  # (as the world map names the place under the mouse)
		var uv := d.uv_of(Vector2(at.x, at.z))
		if uv.x >= 0.0 and uv.y >= 0.0 and uv.x < 1.0 and uv.y < 1.0:
			var b := d.kinds.get_pixelv(Vector2i(uv * Vector2(d.kinds.get_size()))).g8
			if b > 0 and b <= d.biomes.size():
				return MapData.biome_name(d.biomes[b - 1])
	return MapData.biome_name(Biome.current) if Biome.current != &"" else ""
