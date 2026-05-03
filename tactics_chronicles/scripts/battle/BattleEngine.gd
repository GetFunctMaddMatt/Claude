class_name BattleEngine
extends Node
## Orchestrates a complete battle: map load → deploy → player/AI turns → victory/defeat.
## Attach to the Battle scene. Holds refs to BattleGrid, TurnManager, ActionResolver.

enum State { IDLE, DEPLOY, PLAYER_TURN, AI_TURN, ANIMATING, VICTORY, DEFEAT }

@export var grid:            BattleGrid
@export var turn_manager:    TurnManager
@export var action_resolver: ActionResolver

var player_units: Array = []
var enemy_units:  Array = []
var map_data:     Dictionary = {}
var state:        State = State.IDLE

# ─────────────────────────────────────────────────────────────────────────────
# Battle start
# ─────────────────────────────────────────────────────────────────────────────

func start_battle(map_id: String) -> void:
	map_data = DataManager.get_map(map_id)
	if map_data.is_empty():
		push_error("BattleEngine: map not found: %s" % map_id)
		return

	grid.load_map(map_data)
	_spawn_player_units()
	_spawn_enemy_units()

	turn_manager.initialize(player_units + enemy_units)
	_connect_signals()

	_set_state(State.DEPLOY)
	EventBus.battle_started.emit(map_id)

func confirm_deployment() -> void:
	if state != State.DEPLOY: return
	_next_turn()

# ─────────────────────────────────────────────────────────────────────────────
# Player actions (called by BattleHUD)
# ─────────────────────────────────────────────────────────────────────────────

func player_move(unit: Unit, destination: Vector2i) -> void:
	if state != State.PLAYER_TURN: return
	if unit != turn_manager.current_unit: return
	if unit.has_moved: return

	var path = grid.get_path(unit.grid_pos, destination, unit)
	if path.is_empty(): return

	_set_state(State.ANIMATING)
	grid.move_unit(unit, path)
	unit.has_moved = true
	_set_state(State.PLAYER_TURN)
	_check_turn_done(unit)

func player_skill(unit: Unit, skill_id: String, target_pos: Vector2i) -> void:
	if state != State.PLAYER_TURN: return
	if unit != turn_manager.current_unit: return
	if not unit.can_use_skill(skill_id): return

	var sk     = DataManager.get_skill(skill_id)
	unit.mp   -= sk.get("mp_cost", 0)

	_set_state(State.ANIMATING)
	var results = action_resolver.resolve_skill(unit, skill_id, target_pos, grid)
	_apply_results(results)
	unit.has_acted = true
	EventBus.skill_used.emit(unit, skill_id, target_pos)
	EventBus.skill_resolved.emit(results)
	_set_state(State.PLAYER_TURN)
	_check_turn_done(unit)

func player_item(unit: Unit, item_id: String, target_pos: Vector2i) -> void:
	if state != State.PLAYER_TURN: return
	if not GameState.remove_item(item_id): return
	_use_item(unit, item_id, target_pos)
	unit.has_acted = true
	_check_turn_done(unit)

func player_end_turn(_unit: Unit) -> void:
	if state != State.PLAYER_TURN: return
	_end_current_turn()

# ─────────────────────────────────────────────────────────────────────────────
# AI turn
# ─────────────────────────────────────────────────────────────────────────────

func _run_ai_turn(unit: Unit) -> void:
	_set_state(State.AI_TURN)
	# Simple AI: move toward nearest player unit, attack with best skill
	var nearest = _nearest_player_unit(unit)
	if nearest == null:
		_end_current_turn()
		return

	# Move toward nearest player unit if not in range
	var in_range = _unit_in_attack_range(unit, nearest)
	if not unit.has_moved and not in_range:
		var dest = _best_move_toward(unit, nearest.grid_pos)
		if dest != unit.grid_pos:
			var path = grid.get_path(unit.grid_pos, dest, unit)
			grid.move_unit(unit, path)
			unit.has_moved = true

	# Attack
	var best_skill = _pick_best_ai_skill(unit, nearest)
	if best_skill != "" and not unit.has_acted:
		var sk = DataManager.get_skill(best_skill)
		unit.mp -= sk.get("mp_cost", 0)
		var results = action_resolver.resolve_skill(unit, best_skill, nearest.grid_pos, grid)
		_apply_results(results)
		unit.has_acted = true
		EventBus.skill_used.emit(unit, best_skill, nearest.grid_pos)

	_end_current_turn()

func _nearest_player_unit(unit: Unit) -> Unit:
	var best: Unit  = null
	var best_d: int = 9999
	for pu in player_units:
		if pu.is_ko: continue
		var d = (pu.grid_pos - unit.grid_pos).length()
		if d < best_d:
			best_d = d
			best = pu
	return best

func _best_move_toward(unit: Unit, target: Vector2i) -> Vector2i:
	var tiles = grid.get_movement_tiles(unit)
	if tiles.is_empty(): return unit.grid_pos
	tiles.sort_custom(func(a: Vector2i, b: Vector2i):
		return (a - target).length_squared() < (b - target).length_squared()
	)
	return tiles[0]

func _unit_in_attack_range(unit: Unit, target: Unit) -> bool:
	for sk_id in unit.get_active_skills():
		var sk = DataManager.get_skill(sk_id)
		if sk.is_empty(): continue
		if (unit.grid_pos - target.grid_pos).length() <= sk.get("range", 1):
			return true
	return false

func _pick_best_ai_skill(unit: Unit, target: Unit) -> String:
	var best_id = ""
	var best_pow = -1.0
	for sk_id in unit.get_active_skills():
		var sk = DataManager.get_skill(sk_id)
		if sk.is_empty(): continue
		if unit.mp < sk.get("mp_cost", 0): continue
		var rng = sk.get("range", 1)
		if (unit.grid_pos - target.grid_pos).length() > rng: continue
		var pow = float(sk.get("power", 0.0))
		if pow > best_pow:
			best_pow = pow
			best_id  = sk_id
	return best_id

# ─────────────────────────────────────────────────────────────────────────────
# Result application
# ─────────────────────────────────────────────────────────────────────────────

func _apply_results(results: Array) -> void:
	for r in results:
		var target: Unit = r["unit"]
		if r["miss"]:
			continue
		if r.get("revived", false):
			target.revive(0.5)
		if r["damage"] > 0:
			target.take_damage(r["damage"], r["element"])
		if r["healing"] > 0:
			target.heal(r["healing"])
		if r["mp_drain"] > 0:
			target.drain_mp(r["mp_drain"])
		for sm in r["stat_mods"]:
			target.apply_stat_mod(sm["stat"], sm["value"], sm.get("duration", -1))
		for sa in r["statuses_applied"]:
			target.apply_status(sa["id"], sa["duration"])
		for sr in r["statuses_removed"]:
			target.remove_status(sr)
		if target.is_ko:
			_on_unit_ko(target)

func _use_item(unit: Unit, item_id: String, target_pos: Vector2i) -> void:
	var item   = DataManager.get_item(item_id)
	var effect = item.get("use_effect", null)
	if effect == null: return
	var target = grid.get_unit_at(target_pos)
	if target == null: target = unit
	match effect.get("type", ""):
		"heal_hp":         target.heal(effect.get("value", 0))
		"heal_mp":         target.restore_mp(effect.get("value", 0))
		"heal_hp_mp":
			target.heal(int(target.max_hp * float(effect.get("hp_percent", 1.0))))
			target.restore_mp(int(target.max_mp * float(effect.get("mp_percent", 1.0))))
		"revive":          target.revive(effect.get("hp_percent", 0.5))
		"cure_status":     target.remove_status(effect.get("status", ""))
		"cure_all_status": target.statuses.clear()
		"damage":
			var results = action_resolver.resolve_skill(unit, "", target_pos, grid)
			_apply_results(results)

# ─────────────────────────────────────────────────────────────────────────────
# Turn management
# ─────────────────────────────────────────────────────────────────────────────

func _next_turn() -> void:
	var unit = turn_manager.start_next_turn()
	if unit == null:
		_check_victory()
		return
	if unit.is_player:
		_set_state(State.PLAYER_TURN)
	else:
		_run_ai_turn(unit)

func _end_current_turn() -> void:
	turn_manager.end_current_turn()
	_check_victory()
	if state not in [State.VICTORY, State.DEFEAT]:
		_next_turn()

func _check_turn_done(unit: Unit) -> void:
	if unit.has_moved and unit.has_acted:
		_end_current_turn()

# ─────────────────────────────────────────────────────────────────────────────
# Win / loss
# ─────────────────────────────────────────────────────────────────────────────

func _check_victory() -> void:
	var win  = map_data.get("win_condition",  "defeat_all")
	var lose = map_data.get("lose_condition", "party_wiped")
	var all_enemies_ko  = enemy_units.all(func(u: Unit):  return u.is_ko)
	var all_players_ko  = player_units.all(func(u: Unit): return u.is_ko)
	if lose == "party_wiped"  and all_players_ko:
		_set_state(State.DEFEAT)
		EventBus.battle_ended.emit("defeat")
	elif win == "defeat_all"  and all_enemies_ko:
		_set_state(State.VICTORY)
		EventBus.battle_ended.emit("victory")

func _on_unit_ko(unit: Unit) -> void:
	turn_manager.on_unit_ko(unit)
	_check_victory()

# ─────────────────────────────────────────────────────────────────────────────
# Spawning
# ─────────────────────────────────────────────────────────────────────────────

func _spawn_player_units() -> void:
	var zones = map_data.get("deployment_zones", [])
	player_units.clear()
	for i in GameState.party.size():
		var unit = Unit.from_save_data(GameState.party[i])
		unit.is_player  = true
		unit.controller = "player"
		add_child(unit)
		var pos = Vector2i(zones[i][0], zones[i][1]) if i < zones.size() else Vector2i(0, i)
		grid.place_unit(unit, pos)
		player_units.append(unit)

func _spawn_enemy_units() -> void:
	enemy_units.clear()
	for edef in map_data.get("enemy_squads", []):
		var unit = Unit.new()
		unit.init_from_class(edef.get("job", "soldier"), edef.get("level", 1))
		unit.unit_name  = edef.get("name", "Enemy")
		unit.is_player  = false
		unit.controller = "ai"
		add_child(unit)
		var p = edef.get("pos", [0, 0])
		grid.place_unit(unit, Vector2i(p[0], p[1]))
		enemy_units.append(unit)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _set_state(s: State) -> void:
	state = s
	EventBus.battle_state_changed.emit(State.keys()[s])

func _connect_signals() -> void:
	EventBus.unit_ko.connect(_on_unit_ko)
