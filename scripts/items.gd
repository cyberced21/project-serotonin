class_name Items
## Every item in the game: id -> display name. Icons are found by id at art/icons/<id>.png,
## rendered from the models by tools/blender/render_icons.py (+ tools/outline_icons.py).
## To add an item: add a row here and an entry in render_icons.py's ICONS.

const DEFS := {
	&"wood": {"name": "Logs"},
	&"birch": {"name": "Birch logs"},
	&"oak": {"name": "Oak logs"},
	&"pine": {"name": "Pine logs"},
	&"ore": {"name": "Copper ore"},
	&"iron": {"name": "Iron ore"},
	&"coal": {"name": "Coal"},
	&"gold": {"name": "Gold ore"},
	&"perch": {"name": "Perch"},
	&"trout": {"name": "Trout"},
	&"pike": {"name": "Pike"},
}

static var _icons: Dictionary[StringName, Texture2D] = {}


static func display_name(id: StringName) -> String:
	return DEFS.get(id, {}).get("name", String(id).capitalize())


static func icon(id: StringName) -> Texture2D:
	if not _icons.has(id):
		var path := "res://art/icons/%s.png" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


static var _models: Dictionary[StringName, PackedScene] = {}

## The item's little 3D model for drops: models/items/<id>.glb, or models/fish/<id>.glb for
## fish. Null if there's none (the drop shows the icon instead).
static func model(id: StringName) -> PackedScene:
	if not _models.has(id):
		_models[id] = null
		for path in ["res://models/items/%s.glb" % id, "res://models/fish/%s.glb" % id]:
			if ResourceLoader.exists(path):
				_models[id] = load(path)
				break
	return _models[id]


## Sort key, so the HUD lists items in a stable order (the order of DEFS).
static func order(id: StringName) -> int:
	var i := DEFS.keys().find(id)
	return i if i >= 0 else DEFS.size()
