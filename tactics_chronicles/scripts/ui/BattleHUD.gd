class_name BattleHUD
extends CanvasLayer
## Renders the in-battle UI: unit stats panel, skill menu, turn order bar,
## tile highlight overlay, and action log. Talks to BattleEngine via method calls;
## listens to EventBus for updates.

@onready var turn_bar:       HBoxContainer = $TurnBar
@onready var unit_panel:     Control       = $UnitPanel
@onready var skill_menu:     Control       = $SkillMenu
@onready var action_log:     RichTextLabel = $ActionLog
@onready var end_turn_btn:   Button        = $EndTurnBtn
@onready var momentum_bar:   ProgressBar   = $MomentumBar
@onready var surge_btn:      Button        = $SurgeBtn

var battle_engine: BattleEngine
var selected_unit: Unit = null

func _ready() -> void:
	_connect_signals()
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	surge_btn.pressed.connect(_on_surge_pressed)
	_hide_menus()

# ─────────────────────────────────────────────────────────────────────────────
# Signal handlers
# ─────────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.turn_order_updated.connect(_refresh_turn_bar)
	EventBus.unit_damaged.connect(_on_unit_damaged)
	EventBus.unit_healed.connect(_on_unit_healed)
	EventBus.unit_ko.connect(_on_unit_ko)
	EventBus.unit_status_applied.connect(_on_status_changed)
	EventBus.unit_status_removed.connect(_on_status_changed)
	EventBus.momentum_changed.connect(_on_momentum_changed)
	EventBus.tile_hovered.connect(_on_tile_hovered)
	EventBus.tile_selected.connect(_on_tile_selected)

func _on_turn_started(unit: Unit) -> void:
	selected_unit = unit
	_refresh_unit_panel(unit)
	_refresh_skill_menu(unit)
	end_turn_btn.visible  = unit.is_player
	surge_btn.visible     = unit.is_player and battle_engine.turn_manager.has_surge(unit)
	_log("[color=yellow]%s's turn[/color]" % unit.unit_name)

func _on_turn_ended(_unit: Unit) -> void:
	_hide_menus()

func _refresh_turn_bar(queue: Array) -> void:
	# TODO: populate turn_bar children with unit portraits/icons in order
	pass

func _on_unit_damaged(unit: Unit, amount: int, element: String, _src) -> void:
	_log("[color=red]%s took %d %s damage[/color]" % [unit.unit_name, amount, element])
	_refresh_unit_panel_if_selected(unit)

func _on_unit_healed(unit: Unit, amount: int) -> void:
	_log("[color=green]%s healed %d HP[/color]" % [unit.unit_name, amount])
	_refresh_unit_panel_if_selected(unit)

func _on_unit_ko(unit: Unit) -> void:
	_log("[color=gray]%s was defeated.[/color]" % unit.unit_name)

func _on_status_changed(unit: Unit, _sid: String) -> void:
	_refresh_unit_panel_if_selected(unit)

func _on_momentum_changed(unit: Unit, value: int) -> void:
	if unit == selected_unit:
		momentum_bar.value = value
		surge_btn.visible  = value >= 100 and unit.is_player

func _on_tile_hovered(pos: Vector2i) -> void:
	var u = battle_engine.grid.get_unit_at(pos) if battle_engine else null
	if u:
		_refresh_unit_panel(u)

func _on_tile_selected(pos: Vector2i) -> void:
	# TODO: pass selection to BattleEngine depending on current input state
	pass

# ─────────────────────────────────────────────────────────────────────────────
# Panel refresh
# ─────────────────────────────────────────────────────────────────────────────

func _refresh_unit_panel(unit: Unit) -> void:
	# TODO: fill in labels/bars from unit stats
	# unit_panel/NameLabel.text = unit.unit_name
	# unit_panel/HPBar.value    = unit.hp  etc.
	pass

func _refresh_unit_panel_if_selected(unit: Unit) -> void:
	if unit == selected_unit:
		_refresh_unit_panel(unit)

func _refresh_skill_menu(unit: Unit) -> void:
	# TODO: populate skill buttons from unit.get_active_skills()
	pass

# ─────────────────────────────────────────────────────────────────────────────
# Buttons
# ─────────────────────────────────────────────────────────────────────────────

func _on_end_turn_pressed() -> void:
	if battle_engine and battle_engine.turn_manager.is_player_turn():
		battle_engine.player_end_turn(battle_engine.turn_manager.current_unit)

func _on_surge_pressed() -> void:
	# Show surge action menu
	EventBus.menu_opened.emit("surge")

func _hide_menus() -> void:
	skill_menu.visible = false

# ─────────────────────────────────────────────────────────────────────────────
# Action log
# ─────────────────────────────────────────────────────────────────────────────

func _log(text: String) -> void:
	action_log.append_text(text + "\n")
	action_log.scroll_to_line(action_log.get_line_count() - 1)
