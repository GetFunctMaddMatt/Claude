class_name AIController
extends Node
## Behaviour modes for enemy AI. BattleEngine calls run(unit) each AI turn.
## Each mode is a self-contained function -- add new ones without touching BattleEngine.

## Registered modes -- map string key (from map JSON) to Callable
var _modes: Dictionary = {}

func _ready() -> void:
	_modes = {
		"aggressive":   _run_aggressive,
		"ranged_hold":  _run_ranged_hold,
		"flanker":      _run_flanker,
		"defensive":    _run_defensive,
		"hold_bridge":  _run_hold_bridge,
		"passive":      _run_passive
	}

# -----------------------------------------------------------------------------
# Entry point -- called by BattleEngine
# -----------------------------------------------------------------------------

func run(unit: Unit, mode: String, engine: BattleEngine) -> void:
	var fn: Callable = _modes.get(mode, _run_aggressive)
	fn.call(unit, engine)

# -----------------------------------------------------------------------------
# Behaviour modes
# -----------------------------------------------------------------------------

## Aggressive: close distance, use highest-power skill
func _run_aggressive(unit: Unit, engine: BattleEngine) -> void:
	var target = _nearest_player(unit, engine)
	if target == null: return
	if not unit.has_moved:
		_move_toward(unit, target.grid_pos, engine)
	_attack_best(unit, target, engine)

## Ranged: stay at preferred range (3-5 tiles), retreat if enemy is too close
func _run_ranged_hold(unit: Unit, engine: BattleEngine) -> void:
	var target = _nearest_player(unit, engine)
	if target == null: return
	var dist = _manhattan(unit.grid_pos, target.grid_pos)
	if not unit.has_moved:
		if dist < 3:
			_move_away_from(unit, target.grid_pos, engine)
		elif dist > 5:
			_move_toward(unit, target.grid_pos, engine)
	_attack_best(unit, target, engine)

## Flanker: tries to position behind/beside the target before attacking
func _run_flanker(unit: Unit, engine: BattleEngine) -> void:
	var target = _nearest_player(unit, engine)
	if target == null: return
	if not unit.has_moved:
		var flank_pos = _find_flank_position(unit, target, engine)
		if flank_pos != unit.grid_pos:
			_move_to(unit, flank_pos, engine)
		else:
			_move_toward(unit, target.grid_pos, engine)
	_attack_best(unit, target, engine)

## Defensive: hold position, only attacks if target enters range
func _run_defensive(unit: Unit, engine: BattleEngine) -> void:
	var target = _nearest_player(unit, engine)
	if target == null: return
	# Only move if we have a skill that reaches the target
	if _best_skill_for(unit, target, engine) != "":
		_attack_best(unit, target, engine)
	# Minimal movement -- step back if threatened
	if not unit.has_moved and _manhattan(unit.grid_pos, target.grid_pos) <= 1:
		_move_away_from(unit, target.grid_pos, engine)

## Hold bridge: guard a specific area (tiles near unit's spawn), attack anyone adjacent
func _run_hold_bridge(unit: Unit, engine: BattleEngine) -> void:
	var target = _nearest_player(unit, engine)
	if target == null: return
	# Only attack -- don't chase (hold the chokepoint)
	_attack_best(unit, target, engine)

## Passive: does nothing (used for summoned wards, scripted NPCs)
func _run_passive(_unit: Unit, _engine: BattleEngine) -> void:
	pass

# -----------------------------------------------------------------------------
# Shared helpers
# -----------------------------------------------------------------------------

func _nearest_player(unit: Unit, engine: BattleEngine) -> Unit:
	var best: Unit  = null
	var best_d: int = 9999
	for pu in engine.player_units:
		if pu.is_ko: continue
		var d = _manhattan(unit.grid_pos, pu.grid_pos)
		if d < best_d:
			best_d = d
			best   = pu
	return best

func _move_toward(unit: Unit, target: Vector2i, engine: BattleEngine) -> void:
	var tiles = engine.grid.get_movement_tiles(unit)
	if tiles.is_empty(): return
	tiles.sort_custom(func(a: Vector2i, b: Vector2i):
		return _manhattan(a, target) < _manhattan(b, target))
	_move_to(unit, tiles[0], engine)

func _move_away_from(unit: Unit, threat: Vector2i, engine: BattleEngine) -> void:
	var tiles = engine.grid.get_movement_tiles(unit)
	if tiles.is_empty(): return
	tiles.sort_custom(func(a: Vector2i, b: Vector2i):
		return _manhattan(a, threat) > _manhattan(b, threat))
	_move_to(unit, tiles[0], engine)

func _move_to(unit: Unit, dest: Vector2i, engine: BattleEngine) -> void:
	if dest == unit.grid_pos: return
	var path = engine.grid.find_path(unit.grid_pos, dest, unit)
	if path.is_empty(): return
	engine.grid.move_unit(unit, path)
	unit.has_moved = true

func _attack_best(unit: Unit, target: Unit, engine: BattleEngine) -> void:
	if unit.has_acted: return
	var sk_id = _best_skill_for(unit, target, engine)
	if sk_id == "": return
	var sk = DataManager.get_skill(sk_id)
	unit.mp -= sk.get("mp_cost", 0)
	var results = engine.action_resolver.resolve_skill(unit, sk_id, target.grid_pos, engine.grid)
	engine._apply_results(results)
	unit.has_acted = true
	EventBus.skill_used.emit(unit, sk_id, target.grid_pos)
	EventBus.skill_resolved.emit(results)

func _best_skill_for(unit: Unit, target: Unit, engine: BattleEngine) -> String:
	var best_id  = ""
	var best_pow = -1.0
	for sk_id in unit.get_active_skills():
		var sk = DataManager.get_skill(sk_id)
		if sk.is_empty(): continue
		if sk.get("category", "active") != "active": continue
		if sk.get("target_alignment", "enemy") not in ["enemy", "any"]: continue
		if unit.mp < sk.get("mp_cost", 0): continue
		var rng = sk.get("range", 1)
		if _manhattan(unit.grid_pos, target.grid_pos) > rng: continue
		if not engine.grid.check_los(unit.grid_pos, target.grid_pos): continue
		var pow = float(sk.get("power", 0.5))
		if pow > best_pow:
			best_pow = pow
			best_id  = sk_id
	return best_id

func _find_flank_position(unit: Unit, target: Unit, engine: BattleEngine) -> Vector2i:
	# Try to find a tile adjacent to the target that is not in front of it
	var tiles     = engine.grid.get_movement_tiles(unit)
	var adj       = engine.grid._neighbors(target.grid_pos)
	var flanks    = tiles.filter(func(p): return p in adj and p != target.grid_pos)
	if flanks.is_empty(): return unit.grid_pos
	# Prefer tiles not directly facing the target's facing direction
	flanks.sort_custom(func(a: Vector2i, b: Vector2i):
		return _manhattan(a, unit.grid_pos) < _manhattan(b, unit.grid_pos))
	return flanks[0]

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
