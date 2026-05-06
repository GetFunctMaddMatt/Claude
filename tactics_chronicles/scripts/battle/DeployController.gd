class_name DeployController
extends Node
## Owns the pre-battle deploy phase.
##
## Pattern: tap-source / tap-target.
##   1. Player taps a unit in the roster panel OR a unit on the grid -> "picks up" the unit.
##   2. Deployment zones highlight; player taps a zone -> swap with whoever is there.
##   3. "Begin Battle" button calls confirm(); BattleEngine transitions DEPLOY -> player turn.
##
## Sub-states (per the FFT-style nested-state pattern):
##   NONE          : nothing picked, zones still highlighted, can pick a unit
##   UNIT_SELECTED : a unit is in hand, waiting for a zone tap (or pick another unit to swap intent)
##
## A unit can be in one of three places: a deployment slot (slots[i]), the bench, or "absent"
## while it's the picked unit being moved. Slots and bench are kept in sync; on confirm,
## the BattleGrid is rebuilt from slots and benched units are removed from player_units.

enum SubState { NONE, UNIT_SELECTED }

signal deployment_confirmed()

var battle_engine: BattleEngine = null

var sub_state:     SubState = SubState.NONE
var picked_unit:   Unit     = null
var slots:         Array    = []   # parallel to zones; entry is Unit or null
var bench:         Array    = []   # units beyond zone capacity

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func start(player_units: Array) -> void:
	var zones = battle_engine.grid.deployment_zones
	slots.clear()
	bench.clear()
	for i in zones.size():
		if i < player_units.size():
			slots.append(player_units[i])
		else:
			slots.append(null)
	for i in range(zones.size(), player_units.size()):
		bench.append(player_units[i])
	_sync_grid()
	EventBus.deployment_zones_shown.emit(zones)
	EventBus.deploy_layout_changed.emit()

func shutdown() -> void:
	picked_unit = null
	sub_state = SubState.NONE
	EventBus.deployment_zones_shown.emit([])
	EventBus.deploy_unit_picked.emit(null)

# -----------------------------------------------------------------------------
# Selection / placement
# -----------------------------------------------------------------------------

func pick_unit(unit: Unit) -> void:
	if unit == null: return
	if not (unit in slots or unit in bench): return
	picked_unit = unit
	sub_state = SubState.UNIT_SELECTED
	EventBus.deploy_unit_picked.emit(unit)

func cancel_pick() -> void:
	picked_unit = null
	sub_state = SubState.NONE
	EventBus.deploy_unit_picked.emit(null)

func tap_tile(pos: Vector2i) -> void:
	# Tapping a unit on the grid picks it up (regardless of sub-state).
	var on_tile := battle_engine.grid.get_unit_at(pos)
	if on_tile != null and on_tile.is_player and on_tile != picked_unit:
		pick_unit(on_tile)
		return
	if sub_state != SubState.UNIT_SELECTED:
		return
	var zones := battle_engine.grid.deployment_zones
	var zone_idx := zones.find(pos)
	if zone_idx < 0:
		return  # tapped a non-zone tile -- ignore
	_place_in_slot(zone_idx, picked_unit)
	picked_unit = null
	sub_state = SubState.NONE
	EventBus.deploy_unit_picked.emit(null)
	_sync_grid()
	EventBus.deploy_layout_changed.emit()

func bench_picked() -> void:
	if picked_unit == null: return
	# Move from slot to bench (no-op if already benched).
	var prev_slot := slots.find(picked_unit)
	if prev_slot >= 0:
		slots[prev_slot] = null
		bench.append(picked_unit)
	picked_unit = null
	sub_state = SubState.NONE
	EventBus.deploy_unit_picked.emit(null)
	_sync_grid()
	EventBus.deploy_layout_changed.emit()

# -----------------------------------------------------------------------------
# Confirm
# -----------------------------------------------------------------------------

func confirm() -> void:
	# Drop benched units from the active player_units roster -- they sit out this battle.
	var active: Array = slots.filter(func(u): return u != null)
	for u in bench:
		if u.get_parent() != null:
			u.get_parent().remove_child(u)
		u.queue_free()
	battle_engine.player_units = active
	_sync_grid()
	shutdown()
	deployment_confirmed.emit()

# -----------------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------------

func _place_in_slot(zone_idx: int, unit: Unit) -> void:
	var prev_slot := slots.find(unit)
	var was_benched := unit in bench
	var displaced: Unit = slots[zone_idx]

	if prev_slot >= 0:
		slots[prev_slot] = displaced  # swap into the now-empty old slot
	elif was_benched:
		bench.erase(unit)
		if displaced != null:
			bench.append(displaced)   # displaced goes to bench
	slots[zone_idx] = unit

func _sync_grid() -> void:
	var grid: BattleGrid = battle_engine.grid
	# Strip every player-owned tile, regardless of stale entries from the
	# initial spawn (place_unit doesn't clear old tiles).
	for pos in grid.units_on_grid.keys():
		var u: Unit = grid.units_on_grid[pos]
		if u != null and u.is_player:
			grid.units_on_grid.erase(pos)
	var zones := grid.deployment_zones
	for i in slots.size():
		if slots[i] != null:
			grid.place_unit(slots[i], zones[i])
