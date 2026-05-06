extends Node2D
## Overworld map screen: chapters as node graphs.
## Player taps a node to advance (battle, shop, camp, story).

const PARTY_SCREEN_SCENE  = preload("res://scenes/PartyScreen.tscn")
const SHOP_SCREEN_SCENE   = preload("res://scenes/ShopScreen.tscn")
const MAP_EDGE_DRAWER_SCR = preload("res://scripts/overworld/MapEdgeDrawer.gd")

@onready var node_map:       Control = $UI/Root/NodeMap
@onready var chapter_label:  Label   = $UI/Root/TopBar/ChapterLabel
@onready var party_btn:      Button  = $UI/Root/TopBar/PartyBtn
@onready var save_btn:       Button  = $UI/Root/TopBar/SaveBtn

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
	for child in node_map.get_children():
		child.queue_free()

	# Index node defs by id for edge building.
	var by_id: Dictionary = {}
	for nd in _chapter_data.get("nodes", []):
		by_id[nd["id"]] = nd

	# Draw edges first so they sit behind buttons.
	var btn_size := Vector2(160.0, 48.0)
	var half     := btn_size * 0.5
	var edges:   Array = []
	for nd in _chapter_data.get("nodes", []):
		var raw_from = nd.get("map_pos", [0, 0])
		var from_center = Vector2(raw_from[0], raw_from[1]) + half
		var from_complete = GameState.is_battle_complete(nd.get("map_id", ""))
		for next_id in nd.get("unlock_next", []):
			if not by_id.has(next_id): continue
			var raw_to = by_id[next_id].get("map_pos", [0, 0])
			var to_center = Vector2(raw_to[0], raw_to[1]) + half
			edges.append({ "from": from_center, "to": to_center,
					"complete": from_complete })

	var drawer := Control.new()
	drawer.set_script(MAP_EDGE_DRAWER_SCR)
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node_map.add_child(drawer)
	drawer.setup(edges)

	# Add positioned buttons on top.
	for nd in _chapter_data.get("nodes", []):
		_create_map_node(nd)

func _create_map_node(node_def: Dictionary) -> void:
	var btn  := Button.new()
	var pos  := node_def.get("map_pos", [0, 0])
	var type := node_def.get("type", "")

	btn.text = node_def.get("label", node_def["id"])
	btn.custom_minimum_size = Vector2(160, 48)
	btn.position = Vector2(pos[0], pos[1])

	# Color-code by node type so the player can read the map at a glance.
	match type:
		"battle": btn.modulate = Color(1.0, 0.55, 0.55)   # red tint
		"shop":   btn.modulate = Color(0.55, 1.0, 0.65)   # green tint
		"camp":   btn.modulate = Color(0.55, 0.80, 1.0)   # blue tint
		"story":  btn.modulate = Color(1.0, 0.90, 0.40)   # gold tint

	var complete   := GameState.is_battle_complete(node_def.get("map_id", ""))
	var reachable  := _is_node_reachable(node_def["id"])
	btn.disabled = complete or not reachable
	if complete:
		btn.modulate = btn.modulate.darkened(0.45)

	btn.pressed.connect(_on_node_pressed.bind(node_def["id"]))
	node_map.add_child(btn)

func _is_node_reachable(node_id: String) -> bool:
	if node_id == _current_node:
		return true
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
	var canvas = SHOP_SCREEN_SCENE.instantiate()
	var screen: ShopScreen = canvas.get_node("Root")
	screen.closed.connect(func(): canvas.queue_free())
	add_child(canvas)
	screen.open(node_def)

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
	var canvas = PARTY_SCREEN_SCENE.instantiate()
	var screen: PartyScreen = canvas.get_node("Root")
	screen.closed.connect(func(): canvas.queue_free())
	add_child(canvas)
	screen.open(GameState.party)

func _save_game() -> void:
	SaveManager.save(1)   # slot 1 = manual save
	EventBus.notification_requested.emit("Game saved.", Color.GREEN)
