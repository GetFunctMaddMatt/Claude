extends Node2D
## Overworld map screen: chapters as node graphs.
## Player taps a node to advance (battle, shop, camp, story).

const PARTY_SCREEN_SCENE  = preload("res://scenes/PartyScreen.tscn")
const SHOP_SCREEN_SCENE   = preload("res://scenes/ShopScreen.tscn")
const MAP_EDGE_DRAWER_SCR = preload("res://scripts/overworld/MapEdgeDrawer.gd")

const BTN_SIZE := Vector2(160.0, 48.0)

@onready var node_map:      Control = $UI/Root/NodeMap
@onready var chapter_label: Label   = $UI/Root/TopBar/ChapterLabel
@onready var party_btn:     Button  = $UI/Root/TopBar/PartyBtn
@onready var save_btn:      Button  = $UI/Root/TopBar/SaveBtn

var _chapter_data: Dictionary = {}
var _current_node: String     = ""

func _ready() -> void:
	party_btn.pressed.connect(_open_party)
	save_btn.pressed.connect(_save_game)
	_load_chapter(GameState.current_chapter)

func _load_chapter(chapter_id: String) -> void:
	_chapter_data = DataManager.get_chapter(chapter_id)
	chapter_label.text = _chapter_data.get("name", chapter_id)
	_current_node = GameState.current_node if not GameState.current_node.is_empty() \
			else _chapter_data.get("starting_node", "")
	_build_node_map()
	EventBus.chapter_started.emit(chapter_id)

# -----------------------------------------------------------------------------
# Map building
# -----------------------------------------------------------------------------

func _build_node_map() -> void:
	for child in node_map.get_children():
		child.queue_free()

	var nodes: Array = _chapter_data.get("nodes", [])
	var by_id: Dictionary = {}
	for nd in nodes:
		by_id[nd["id"]] = nd

	_add_edge_drawer(nodes, by_id)

	for nd in nodes:
		_create_map_node(nd)

func _add_edge_drawer(nodes: Array, by_id: Dictionary) -> void:
	var half  := BTN_SIZE * 0.5
	var edges: Array = []
	for nd in nodes:
		var raw_from: Array = nd.get("map_pos", [0, 0])
		var from_center := Vector2(raw_from[0], raw_from[1]) + half
		for next_id in nd.get("unlock_next", []):
			if not by_id.has(next_id): continue
			var raw_to: Array = by_id[next_id].get("map_pos", [0, 0])
			var to_center := Vector2(raw_to[0], raw_to[1]) + half
			edges.append({
				"from":     from_center,
				"to":       to_center,
				"complete": _is_node_complete(nd)
			})
	var drawer := Control.new()
	drawer.set_script(MAP_EDGE_DRAWER_SCR)
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node_map.add_child(drawer)
	drawer.setup(edges)

func _create_map_node(node_def: Dictionary) -> void:
	var btn:      Button  = Button.new()
	var raw_pos:  Array   = node_def.get("map_pos", [0, 0])
	var type:     String  = node_def.get("type", "")
	var complete: bool    = _is_node_complete(node_def)
	var reachable: bool   = _is_node_reachable(node_def["id"])

	btn.text               = node_def.get("label", node_def["id"])
	btn.custom_minimum_size = BTN_SIZE
	btn.position           = Vector2(raw_pos[0], raw_pos[1])

	match type:
		"battle": btn.modulate = Color(1.0, 0.55, 0.55)
		"shop":   btn.modulate = Color(0.55, 1.0, 0.65)
		"camp":   btn.modulate = Color(0.55, 0.80, 1.0)
		"story":  btn.modulate = Color(1.0, 0.90, 0.40)

	# Battle nodes are locked out once won; shop/camp/story stay re-enterable.
	var locked: bool = (type == "battle" and complete) or not reachable
	btn.disabled = locked
	if type == "battle" and complete:
		btn.modulate = btn.modulate.darkened(0.45)

	btn.pressed.connect(_on_node_pressed.bind(node_def["id"]))
	node_map.add_child(btn)

# -----------------------------------------------------------------------------
# Reachability -- proper directed-graph traversal
# -----------------------------------------------------------------------------

func _is_node_reachable(node_id: String) -> bool:
	# Collect all predecessor nodes (those that list node_id in unlock_next).
	var predecessors: Array = []
	for nd in _chapter_data.get("nodes", []):
		if node_id in nd.get("unlock_next", []):
			predecessors.append(nd)
	# Root nodes (nothing points at them) are always reachable.
	if predecessors.is_empty():
		return true
	# Otherwise at least one predecessor must be complete.
	for pred in predecessors:
		if _is_node_complete(pred):
			return true
	return false

func _is_node_complete(node_def: Dictionary) -> bool:
	# Each node type has its own definition of "done".
	# Battle: the map must have been WON (completed_battles tracks map IDs).
	# All others: the player must have entered the node (visited_nodes tracks node IDs).
	match node_def.get("type", ""):
		"battle": return GameState.is_battle_complete(node_def.get("map_id", ""))
		_:        return GameState.is_node_visited(node_def["id"])

# -----------------------------------------------------------------------------
# Node interaction
# -----------------------------------------------------------------------------

func _on_node_pressed(node_id: String) -> void:
	_current_node = node_id
	GameState.current_node = node_id
	# Mark visited immediately so successors unlock and save state is correct.
	GameState.mark_node_visited(node_id)

	var node_def: Dictionary = {}
	for nd in _chapter_data.get("nodes", []):
		if nd["id"] == node_id:
			node_def = nd
			break
	if node_def.is_empty():
		return

	match node_def.get("type", ""):
		"battle": _enter_battle(node_def["map_id"])
		"shop":   _enter_shop(node_def)
		"camp":   _enter_camp()
		"story":  _play_story(node_def.get("scene_id", ""))

func _enter_battle(map_id: String) -> void:
	GameState.pending_map_id = map_id
	GameState.current_node   = _current_node
	SaveManager.autosave()
	get_tree().change_scene_to_file("res://scenes/Battle.tscn")

func _enter_shop(node_def: Dictionary) -> void:
	var canvas := SHOP_SCREEN_SCENE.instantiate()
	var screen: ShopScreen = canvas.get_node("Root")
	screen.closed.connect(func(): canvas.queue_free(); _build_node_map())
	add_child(canvas)
	screen.open(node_def)

func _enter_camp() -> void:
	_open_party()

func _play_story(_scene_id: String) -> void:
	# TODO: trigger cutscene/dialogue system
	EventBus.cutscene_started.emit(_scene_id)

# -----------------------------------------------------------------------------
# UI actions
# -----------------------------------------------------------------------------

func _open_party() -> void:
	var canvas := PARTY_SCREEN_SCENE.instantiate()
	var screen: PartyScreen = canvas.get_node("Root")
	screen.closed.connect(func(): canvas.queue_free())
	add_child(canvas)
	screen.open(GameState.party)

func _save_game() -> void:
	SaveManager.save(1)
	EventBus.notification_requested.emit("Game saved.", Color.GREEN)
