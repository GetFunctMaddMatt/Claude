extends Node2D
## Overworld map screen: chapters as node graphs.
## Player taps a node to advance (battle, shop, camp, story).

@onready var node_map:       Control = $NodeMap
@onready var chapter_label:  Label   = $UI/ChapterLabel
@onready var party_btn:      Button  = $UI/PartyBtn
@onready var save_btn:       Button  = $UI/SaveBtn

var _chapter_data: Dictionary = {}
var _current_node: String     = ""

func _ready() -> void:
	party_btn.pressed.connect(_open_party)
	save_btn.pressed.connect(_save_game)
	EventBus.battle_ended.connect(_on_battle_ended)
	_load_chapter(GameState.current_chapter)

func _load_chapter(chapter_id: String) -> void:
	_chapter_data = DataManager.get_chapter(chapter_id)
	chapter_label.text = _chapter_data.get("name", chapter_id)
	_current_node = _chapter_data.get("starting_node", "") if GameState.current_node.is_empty() \
		else GameState.current_node
	_build_node_map()
	EventBus.chapter_started.emit(chapter_id)

func _build_node_map() -> void:
	# TODO: Instantiate node buttons from _chapter_data["nodes"]
	# Each node shows as a dot on the map; edges show connections.
	# Completed nodes are greyed out; current node is highlighted.
	for child in node_map.get_children():
		child.queue_free()
	for node_def in _chapter_data.get("nodes", []):
		_create_map_node(node_def)

func _create_map_node(node_def: Dictionary) -> void:
	var btn = Button.new()
	btn.text = node_def.get("label", node_def["id"])
	# TODO: position from node_def["map_pos"]
	btn.pressed.connect(_on_node_pressed.bind(node_def["id"]))
	var complete = GameState.is_battle_complete(node_def.get("map_id", ""))
	btn.disabled = complete or not _is_node_reachable(node_def["id"])
	node_map.add_child(btn)

func _is_node_reachable(node_id: String) -> bool:
	if node_id == _current_node:
		return true
	# Check if any completed predecessor unlocks this node
	for nd in _chapter_data.get("nodes", []):
		if node_id in nd.get("unlock_next", []):
			var prereq_map = nd.get("map_id", "")
			if prereq_map == "" or GameState.is_battle_complete(prereq_map):
				return true
	return false

func _on_node_pressed(node_id: String) -> void:
	_current_node = node_id
	GameState.current_node = node_id
	var node_def: Dictionary = {}
	for nd in _chapter_data.get("nodes", []):
		if nd["id"] == node_id:
			node_def = nd
			break
	if node_def.is_empty(): return

	match node_def.get("type", ""):
		"battle":
			_enter_battle(node_def["map_id"])
		"shop":
			_enter_shop(node_def)
		"camp":
			_enter_camp()
		"story":
			_play_story(node_def.get("scene_id", ""))

func _enter_battle(map_id: String) -> void:
	GameState.pending_map_id = map_id
	GameState.current_node   = _current_node
	SaveManager.autosave()
	get_tree().change_scene_to_file("res://scenes/Battle.tscn")

func _enter_shop(node_def: Dictionary) -> void:
	# TODO: open ShopScreen overlay with node_def shop data
	EventBus.shop_opened.emit(node_def)

func _enter_camp() -> void:
	_open_party()

func _play_story(_scene_id: String) -> void:
	# TODO: trigger cutscene/dialogue system
	EventBus.cutscene_started.emit(_scene_id)

# -----------------------------------------------------------------------------
# Battle result
# -----------------------------------------------------------------------------

func _on_battle_ended(result: String) -> void:
	if result == "victory":
		GameState.mark_battle_complete(_current_node)
		_build_node_map()
		SaveManager.autosave()
	elif result == "defeat":
		# Return to overworld; player keeps progress but loses battle rewards
		pass

# -----------------------------------------------------------------------------
# Buttons
# -----------------------------------------------------------------------------

func _open_party() -> void:
	EventBus.menu_opened.emit("party")
	# TODO: show PartyScreen overlay

func _save_game() -> void:
	SaveManager.save(1)   # slot 1 = manual save
	EventBus.notification_requested.emit("Game saved.", Color.GREEN)
