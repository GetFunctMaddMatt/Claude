class_name BattleEngine
extends Node
## Orchestrates a complete battle: map load -> deploy -> player/AI turns -> victory/defeat.
## Attach to the Battle scene. Holds refs to BattleGrid, TurnManager, ActionResolver.

enum State { IDLE, DEPLOY, PLAYER_TURN, AI_TURN, ANIMATING, VICTORY, DEFEAT }

@export var grid:            BattleGrid
@export var turn_manager:    TurnManager
@export var action_resolver: ActionResolver
@export var ai_controller:   AIController
@export var input_handler:   InputHandler
@export var grid_renderer:   GridRenderer
@export var camera:          CameraController
@export var hud:             BattleHUD
@export var job_system:      JobSystem
@export var post_battle:     PostBattleScreen

var player_units:  Array = []
var enemy_units:   Array = []
var _enemy_modes:  Dictionary = {}   # Unit -> ai_mode string
var map_data:      Dictionary = {}
var state:         State = State.IDLE

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func _ready() -> void:
	var map_id = GameState.pending_map_id
	if map_id.is_empty():
		map_id = "map_001_crossroads"   # dev fallback -- lets you run Battle.tscn standalone
	start_battle(map_id)

# -----------------------------------------------------------------------------
# Battle start
# -----------------------------------------------------------------------------

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
	_wire_subsystems()

	_set_state(State.DEPLOY)
	EventBus.battle_started.emit(map_id)

func confirm_deployment() -> void:
	if state != State.DEPLOY: return
	_next_turn()

# -----------------------------------------------------------------------------
# Player actions (called by BattleHUD)
# -----------------------------------------------------------------------------

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
	_spawn_floating_results(results)
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

# -----------------------------------------------------------------------------
# AI turn
# -----------------------------------------------------------------------------

func _run_ai_turn(unit: Unit) -> void:
	_set_state(State.AI_TURN)
	var mode = _enemy_modes.get(unit, "aggressive")
	if ai_controller:
		ai_controller.run(unit, mode, self)
		_end_current_turn()
		return
	# Fallback if ai_controller not wired
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

# -----------------------------------------------------------------------------
# Result application
# -----------------------------------------------------------------------------

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

func _spawn_floating_results(results: Array) -> void:
	if grid_renderer == null: return
	for r in results:
		var target: Unit = r["unit"]
		var world_pos = grid_renderer.grid_to_screen_center(target.grid_pos)
		if r.get("miss", false):
			FloatingText.miss(grid_renderer, world_pos)
		else:
			if r["damage"] > 0:
				FloatingText.damage(grid_renderer, world_pos,
					r["damage"], r["element"], r.get("crit", false))
			if r["healing"] > 0:
				FloatingText.heal(grid_renderer, world_pos, r["healing"])
			for sa in r.get("statuses_applied", []):
				FloatingText.status(grid_renderer, world_pos, sa["id"])
			if r.get("ko", false):
				FloatingText.ko(grid_renderer, world_pos)

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

# -----------------------------------------------------------------------------
# Turn management
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Win / loss
# -----------------------------------------------------------------------------

func _check_victory() -> void:
	var win  = map_data.get("win_condition",  "defeat_all")
	var lose = map_data.get("lose_condition", "party_wiped")
	var all_enemies_ko  = enemy_units.all(func(u: Unit):  return u.is_ko)
	var all_players_ko  = player_units.all(func(u: Unit): return u.is_ko)
	if lose == "party_wiped" and all_players_ko:
		_set_state(State.DEFEAT)
		EventBus.battle_ended.emit("defeat")
		if post_battle:
			post_battle.show_results(false, {}, [], func(): get_tree().change_scene_to_file("res://scenes/Overworld.tscn"))
	elif win == "defeat_all" and all_enemies_ko:
		_set_state(State.VICTORY)
		EventBus.battle_ended.emit("victory")
		_handle_victory()

func _on_unit_ko(unit: Unit) -> void:
	turn_manager.on_unit_ko(unit)
	_check_victory()

# -----------------------------------------------------------------------------
# Spawning
# -----------------------------------------------------------------------------

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
		_enemy_modes[unit] = edef.get("ai", "aggressive")
		enemy_units.append(unit)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _handle_victory() -> void:
	var rewards = map_data.get("rewards", {})
	GameState.add_gil(rewards.get("gil", 0))
	for iid in rewards.get("items", []):
		GameState.add_item(iid)
	var unit_results: Array = []
	if job_system:
		unit_results = job_system.award_battle_rewards(player_units, map_data)
	GameState.mark_battle_complete(map_data.get("id", ""))
	SaveManager.autosave()
	if post_battle:
		post_battle.show_results(true, rewards, unit_results,
			func(): get_tree().change_scene_to_file("res://scenes/Overworld.tscn"))

func _set_state(s: State) -> void:
	state = s
	EventBus.battle_state_changed.emit(State.keys()[s])

func _wire_subsystems() -> void:
	if input_handler:
		input_handler.battle_engine = self
		input_handler.grid_renderer = grid_renderer
		input_handler.hud           = hud
	if grid_renderer:
		grid_renderer.grid = grid
		grid_renderer.queue_redraw()
	if camera and grid_renderer:
		camera.set_grid_bounds(grid_renderer.total_size())
	if hud:
		hud.battle_engine = self
	EventBus.turn_started.connect(func(u: Unit):
		if camera and grid_renderer:
			camera.snap_to(grid_renderer.grid_to_screen_center(u.grid_pos)))

func _connect_signals() -> void:
	EventBus.unit_ko.connect(_on_unit_ko)
