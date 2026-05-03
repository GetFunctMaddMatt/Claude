extends Node
## Handles save/load for up to MAX_SLOTS save files.

const MAX_SLOTS  = 3
const SAVE_DIR   = "user://saves/"
const SAVE_FILE  = SAVE_DIR + "slot_%d.json"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# ── Save ──────────────────────────────────────────────────────────────────────

func save(slot: int) -> void:
	assert(slot >= 0 and slot < MAX_SLOTS)
	var data = GameState.to_dict()
	data["timestamp"] = Time.get_unix_time_from_system()
	var file = FileAccess.open(SAVE_FILE % slot, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))

# ── Load ──────────────────────────────────────────────────────────────────────

func load_save(slot: int) -> bool:
	var path = SAVE_FILE % slot
	if not FileAccess.file_exists(path):
		return false
	var text   = FileAccess.get_file_as_string(path)
	var data   = JSON.parse_string(text)
	if data == null:
		push_error("SaveManager: corrupt save in slot %d" % slot)
		return false
	GameState.from_dict(data)
	return true

# ── Slot info (for save-select screen) ───────────────────────────────────────

func get_slot_info(slot: int) -> Dictionary:
	var path = SAVE_FILE % slot
	if not FileAccess.file_exists(path):
		return { "exists": false }
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data == null:
		return { "exists": false }
	return {
		"exists":    true,
		"chapter":   data.get("chapter", "ch01"),
		"timestamp": data.get("timestamp", 0),
		"playtime":  data.get("playtime", 0)
	}

func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(SAVE_FILE % slot)

func delete_slot(slot: int) -> void:
	DirAccess.remove_absolute(SAVE_FILE % slot)

# ── Auto-save ─────────────────────────────────────────────────────────────────

func autosave() -> void:
	save(0)   # slot 0 is always the autosave
