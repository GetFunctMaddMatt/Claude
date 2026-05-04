extends Node
## Loads all JSON data at startup and exposes typed accessors.
## Nothing reads files at runtime except get_map() which lazy-loads.

var classes:       Dictionary = {}
var skills:        Dictionary = {}
var prebuilds:     Dictionary = {}
var items:         Dictionary = {}
var terrain_types: Dictionary = {}
var campaign:      Dictionary = {}
var _map_cache:    Dictionary = {}

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	var c = _load_json("res://data/classes.json")
	classes = c.get("classes", {})

	var s = _load_json("res://data/skills.json")
	skills   = s.get("skills", {})
	prebuilds = s.get("prebuilds", {})

	items         = _load_json("res://data/items.json").get("items", {})
	terrain_types = _load_json("res://data/terrain_types.json").get("terrain_types", {})
	campaign      = _load_json("res://data/campaign.json")

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DataManager: missing file %s" % path)
		return {}
	var text = FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("DataManager: JSON parse error in %s" % path)
		return {}
	return parsed

# -- Accessors -----------------------------------------------------------------

func get_class_data(class_id: String) -> Dictionary:
	return classes.get(class_id, {})

func get_skill(skill_id: String) -> Dictionary:
	return skills.get(skill_id, {})

func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})

func get_terrain(terrain_id: String) -> Dictionary:
	return terrain_types.get(terrain_id, {})

func get_map(map_id: String) -> Dictionary:
	if _map_cache.has(map_id):
		return _map_cache[map_id]
	var data = _load_json("res://data/maps/%s.json" % map_id)
	_map_cache[map_id] = data
	return data

func get_prebuilds_for_class(class_id: String) -> Dictionary:
	return prebuilds.get(class_id, {})

func get_chapter(chapter_id: String) -> Dictionary:
	for ch in campaign.get("chapters", []):
		if ch.get("id") == chapter_id:
			return ch
	return {}

func get_skills_for_class(class_id: String) -> Array:
	var result: Array = []
	for skill_id in skills:
		var sk = skills[skill_id]
		if sk.get("class_id") == class_id:
			result.append(skill_id)
	return result

func get_skills_unlocked_at(class_id: String, job_level: int) -> Array:
	var result: Array = []
	for skill_id in get_skills_for_class(class_id):
		if skills[skill_id].get("unlock_level", 1) <= job_level:
			result.append(skill_id)
	return result
