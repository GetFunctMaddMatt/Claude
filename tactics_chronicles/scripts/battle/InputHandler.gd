class_name InputHandler
extends Node
## Translates touch/mouse input into battle actions.
## State machine decouples UI concerns from BattleEngine logic.

enum InputState {
	IDLE,            # nothing selected
	UNIT_SELECTED,   # player unit selected, waiting for move or skill choice
	AWAITING_MOVE,   # move range shown, waiting for destination tap
	SKILL_TARGETING, # skill selected, waiting for target tap
	LOCKED           # animation playing, no input
}

var battle_engine:  BattleEngine  = null
var grid_renderer:  GridRenderer  = null
var hud:            BattleHUD     = null

var state:           InputState = InputState.IDLE
var selected_unit:   Unit       = null
var selected_skill:  String     = ""
var _move_tiles:     Array      = []

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.battle_state_changed.connect(_on_battle_state_changed)

func _input(event: InputEvent) -> void:
	if state == InputState.LOCKED: return
	if battle_engine == null or grid_renderer == null: return

	var tap_pos: Vector2 = Vector2.ZERO
	var is_tap  = false

	if event is InputEventScreenTouch and event.pressed:
		tap_pos = event.position;  is_tap = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap_pos = event.position;  is_tap = true

	if not is_tap: return

	var grid_pos = grid_renderer.screen_to_grid(tap_pos)
	if not battle_engine.grid.is_in_bounds(grid_pos): return

	EventBus.tile_hovered.emit(grid_pos)   # for hover highlight during tap
	_handle_tap(grid_pos)

func _handle_tap(pos: Vector2i) -> void:
	match state:
		InputState.IDLE:         _tap_idle(pos)
		InputState.UNIT_SELECTED: _tap_unit_selected(pos)
		InputState.AWAITING_MOVE: _tap_awaiting_move(pos)
		InputState.SKILL_TARGETING: _tap_skill_targeting(pos)

# ─────────────────────────────────────────────────────────────────────────────
# State handlers
# ─────────────────────────────────────────────────────────────────────────────

func _tap_idle(pos: Vector2i) -> void:
	var unit = battle_engine.grid.get_unit_at(pos)
	if unit == null or not unit.is_player: return
	if not battle_engine.turn_manager.is_player_turn(): return
	if unit != battle_engine.turn_manager.current_unit: return
	_select_unit(unit)

func _tap_unit_selected(pos: Vector2i) -> void:
	var unit = battle_engine.grid.get_unit_at(pos)
	# Tap same unit — deselect
	if unit == selected_unit:
		_deselect()
		return
	# Tap another friendly — switch selection
	if unit != null and unit.is_player:
		_select_unit(unit)
		return
	# Tap empty/enemy tile — attempt move if unit hasn't moved yet
	if not selected_unit.has_moved and pos in _move_tiles:
		_set_state(InputState.AWAITING_MOVE)
		_confirm_move(pos)
	elif unit != null and not unit.is_player:
		# Tap enemy with no skill selected — try first available attack skill
		var atk_skill = _find_attack_skill_for(selected_unit, pos)
		if atk_skill != "":
			battle_engine.player_skill(selected_unit, atk_skill, pos)
			_check_done_or_deselect()

func _tap_awaiting_move(pos: Vector2i) -> void:
	if pos in _move_tiles:
		_confirm_move(pos)
	else:
		_set_state(InputState.UNIT_SELECTED)

func _tap_skill_targeting(pos: Vector2i) -> void:
	var valid_targets = battle_engine.grid.get_tiles_in_pattern(
		selected_unit.grid_pos,
		DataManager.get_skill(selected_skill).get("target_pattern", "single"),
		DataManager.get_skill(selected_skill).get("range", 1),
		DataManager.get_skill(selected_skill).get("aoe_radius", 0),
		selected_unit.facing
	)
	if pos in valid_targets:
		battle_engine.player_skill(selected_unit, selected_skill, pos)
		EventBus.skill_range_updated.emit([])
		selected_skill = ""
		_check_done_or_deselect()
	else:
		# Cancel skill targeting, return to unit selected
		EventBus.skill_range_updated.emit([])
		selected_skill = ""
		_set_state(InputState.UNIT_SELECTED)

# ─────────────────────────────────────────────────────────────────────────────
# Actions
# ─────────────────────────────────────────────────────────────────────────────

func _select_unit(unit: Unit) -> void:
	selected_unit = unit
	_move_tiles = battle_engine.grid.get_movement_tiles(unit) if not unit.has_moved else []
	EventBus.move_range_updated.emit(_move_tiles)
	EventBus.tile_selected.emit(unit.grid_pos)
	_set_state(InputState.UNIT_SELECTED)

func _deselect() -> void:
	selected_unit  = null
	selected_skill = ""
	_move_tiles    = []
	EventBus.move_range_updated.emit([])
	EventBus.skill_range_updated.emit([])
	EventBus.tile_selected.emit(Vector2i(-1, -1))
	_set_state(InputState.IDLE)

func _confirm_move(pos: Vector2i) -> void:
	battle_engine.player_move(selected_unit, pos)
	_move_tiles = []
	EventBus.move_range_updated.emit([])
	EventBus.tile_selected.emit(selected_unit.grid_pos)
	_set_state(InputState.UNIT_SELECTED)

func begin_skill_targeting(skill_id: String) -> void:
	if selected_unit == null: return
	if not selected_unit.can_use_skill(skill_id): return
	selected_skill = skill_id
	var sk      = DataManager.get_skill(skill_id)
	var targets = battle_engine.grid.get_tiles_in_pattern(
		selected_unit.grid_pos, sk.get("target_pattern", "single"),
		sk.get("range", 1), sk.get("aoe_radius", 0), selected_unit.facing)
	EventBus.skill_range_updated.emit(targets)
	_set_state(InputState.SKILL_TARGETING)

func _check_done_or_deselect() -> void:
	if selected_unit == null: return
	if selected_unit.has_moved and selected_unit.has_acted:
		_deselect()
	else:
		# Refresh move tiles if unit just acted but hasn't moved
		if not selected_unit.has_moved:
			_move_tiles = battle_engine.grid.get_movement_tiles(selected_unit)
			EventBus.move_range_updated.emit(_move_tiles)
		_set_state(InputState.UNIT_SELECTED)

func _find_attack_skill_for(unit: Unit, target_pos: Vector2i) -> String:
	for sk_id in unit.get_active_skills():
		var sk = DataManager.get_skill(sk_id)
		if sk.get("target_alignment", "") not in ["enemy", "any"]: continue
		if sk.get("damage_type", "none") == "none": continue
		var rng = sk.get("range", 1)
		if (unit.grid_pos - target_pos).length() <= rng:
			return sk_id
	return ""

# ─────────────────────────────────────────────────────────────────────────────
# Event handlers
# ─────────────────────────────────────────────────────────────────────────────

func _on_turn_started(unit: Unit) -> void:
	if unit.is_player:
		_deselect()
		_set_state(InputState.IDLE)
	else:
		_set_state(InputState.LOCKED)

func _on_battle_state_changed(s: String) -> void:
	if s in ["ANIMATING", "AI_TURN", "VICTORY", "DEFEAT"]:
		_set_state(InputState.LOCKED)
	elif s == "PLAYER_TURN":
		if state == InputState.LOCKED:
			_set_state(InputState.IDLE)

func _set_state(s: InputState) -> void:
	state = s
