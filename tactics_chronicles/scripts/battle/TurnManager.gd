class_name TurnManager
extends Node
## Manages turn order (speed-sorted), round counting, and the Momentum / Surge system.
##
## Momentum: each unit builds Momentum every turn equal to their SPD.
## At 100 Momentum a Surge prompt appears -- spend it for a bonus action or ability upgrade.
## This is PvP-safe: momentum is per-unit, deterministic, and synced easily.

var all_units:    Array = []
var turn_queue:   Array = []
var current_unit: Unit  = null
var round_number: int   = 0

# momentum[unit] = int 0-100
var _momentum: Dictionary = {}

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

func initialize(units: Array) -> void:
	all_units = units.duplicate()
	_momentum.clear()
	for u in all_units:
		_momentum[u] = 0
	_build_queue()

func _build_queue() -> void:
	turn_queue = all_units.filter(func(u: Unit): return not u.is_ko)
	# Speed desc; ties: player units first (feels fair)
	turn_queue.sort_custom(func(a: Unit, b: Unit):
		if a.spd != b.spd: return a.spd > b.spd
		return int(a.is_player) > int(b.is_player)
	)
	EventBus.turn_order_updated.emit(turn_queue.duplicate())

# -----------------------------------------------------------------------------
# Turn flow
# -----------------------------------------------------------------------------

func start_next_turn() -> Unit:
	if turn_queue.is_empty():
		_build_queue()
		round_number += 1
	if turn_queue.is_empty():
		return null   # all units KO -- battle engine will catch this

	current_unit = turn_queue.pop_front()
	current_unit.has_moved = false
	current_unit.has_acted = false
	current_unit.tick_statuses()

	# Skip silently if unit is KO or stunned/stopped
	if current_unit.is_ko or current_unit.has_status("stop"):
		return start_next_turn()

	if current_unit.has_status("berserk"):
		# Berserk: auto-attack nearest enemy, skip player input
		pass  # BattleEngine handles this after signal

	EventBus.turn_started.emit(current_unit)
	return current_unit

func end_current_turn() -> void:
	if current_unit == null: return
	_tick_momentum(current_unit)
	EventBus.turn_ended.emit(current_unit)
	current_unit = null

# -----------------------------------------------------------------------------
# Momentum / Surge
# -----------------------------------------------------------------------------

func _tick_momentum(unit: Unit) -> void:
	var prev = _momentum.get(unit, 0)
	var next = mini(prev + unit.spd, 100)
	_momentum[unit] = next
	EventBus.momentum_changed.emit(unit, next)

func get_momentum(unit: Unit) -> int:
	return _momentum.get(unit, 0)

func consume_surge(unit: Unit) -> bool:
	if _momentum.get(unit, 0) < 100:
		return false
	_momentum[unit] = 0
	EventBus.momentum_changed.emit(unit, 0)
	return true

func has_surge(unit: Unit) -> bool:
	return _momentum.get(unit, 0) >= 100

# -----------------------------------------------------------------------------
# Unit removal (KO or retreat)
# -----------------------------------------------------------------------------

func on_unit_ko(unit: Unit) -> void:
	turn_queue.erase(unit)
	all_units.erase(unit)
	_momentum.erase(unit)
	if current_unit == unit:
		end_current_turn()
		start_next_turn()

# -----------------------------------------------------------------------------
# HUD helpers
# -----------------------------------------------------------------------------

func get_turn_preview(count: int = 6) -> Array:
	var preview = []
	if current_unit:
		preview.append(current_unit)
	for u in turn_queue:
		if preview.size() >= count: break
		preview.append(u)
	return preview

func is_player_turn() -> bool:
	return current_unit != null and current_unit.is_player
