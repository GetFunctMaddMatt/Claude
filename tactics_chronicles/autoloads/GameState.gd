extends Node
## Global mutable game state. Persisted by SaveManager.
## Battle-scoped data lives in BattleEngine, not here.

# ── Persistent state ──────────────────────────────────────────────────────────
var current_chapter: String     = "ch01"
var current_node:    String     = ""

# ── Transient (not saved) ─────────────────────────────────────────────────────
var pending_map_id:  String     = ""   # set by Overworld before switching to Battle
var party:           Array      = []   # Array of unit save dicts
var gil:             int        = 500
var inventory:       Dictionary = {}   # item_id -> count
var unlocked_classes: Array     = ["soldier", "arcanist"]
var completed_battles: Array    = []
var story_flags:     Dictionary = {}

# ── Gil ───────────────────────────────────────────────────────────────────────

func add_gil(amount: int) -> void:
	gil += amount
	EventBus.gil_changed.emit(gil, amount)

func spend_gil(amount: int) -> bool:
	if gil < amount:
		return false
	gil -= amount
	EventBus.gil_changed.emit(gil, -amount)
	return true

# ── Inventory ─────────────────────────────────────────────────────────────────

func add_item(item_id: String, qty: int = 1) -> void:
	inventory[item_id] = inventory.get(item_id, 0) + qty
	EventBus.item_acquired.emit(item_id, qty)

func remove_item(item_id: String, qty: int = 1) -> bool:
	if inventory.get(item_id, 0) < qty:
		return false
	inventory[item_id] -= qty
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	return true

func item_count(item_id: String) -> int:
	return inventory.get(item_id, 0)

func has_item(item_id: String) -> bool:
	return item_count(item_id) > 0

# ── Classes ───────────────────────────────────────────────────────────────────

func unlock_class(class_id: String) -> void:
	if class_id not in unlocked_classes:
		unlocked_classes.append(class_id)

func is_class_unlocked(class_id: String) -> bool:
	return class_id in unlocked_classes

# ── Progress ──────────────────────────────────────────────────────────────────

func mark_battle_complete(map_id: String) -> void:
	if map_id not in completed_battles:
		completed_battles.append(map_id)

func is_battle_complete(map_id: String) -> bool:
	return map_id in completed_battles

func set_flag(flag: String, value = true) -> void:
	story_flags[flag] = value

func get_flag(flag: String, default = false):
	return story_flags.get(flag, default)

# ── Serialization ─────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"chapter": current_chapter,
		"node": current_node,
		"party": party,
		"gil": gil,
		"inventory": inventory,
		"unlocked_classes": unlocked_classes,
		"completed_battles": completed_battles,
		"story_flags": story_flags
	}

func from_dict(d: Dictionary) -> void:
	current_chapter  = d.get("chapter", "ch01")
	current_node     = d.get("node", "")
	party            = d.get("party", [])
	gil              = d.get("gil", 500)
	inventory        = d.get("inventory", {})
	unlocked_classes = d.get("unlocked_classes", ["soldier", "arcanist"])
	completed_battles = d.get("completed_battles", [])
	story_flags      = d.get("story_flags", {})
