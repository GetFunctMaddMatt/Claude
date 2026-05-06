class_name DeployPanel
extends Control
## Pre-battle deploy UI. Renders party roster split into "On Map" and "Bench"
## sections; tap a row to pick that unit (the on-grid InputHandler does the
## same when the player taps the unit's tile). Begin Battle confirms.

signal unit_picked(unit: Unit)
signal bench_requested()
signal begin_pressed()

@onready var deployed_list: VBoxContainer = $LeftPanel/Margin/VBox/DeployedList
@onready var bench_list:    VBoxContainer = $LeftPanel/Margin/VBox/BenchList
@onready var bench_btn:     Button        = $LeftPanel/Margin/VBox/BenchBtn
@onready var begin_btn:     Button        = $LeftPanel/Margin/VBox/BeginBtn

var _picked:     Unit             = null
var _controller: DeployController = null

func _ready() -> void:
	begin_btn.pressed.connect(_on_begin_pressed)
	bench_btn.pressed.connect(_on_bench_pressed)
	EventBus.deploy_layout_changed.connect(refresh)
	EventBus.deploy_unit_picked.connect(_on_picked_changed)

func bind(controller: DeployController) -> void:
	# Called by BattleEngine after the panel is added; controller is the
	# source of truth for slots/bench, panel just renders from it.
	_controller = controller
	refresh()

# -----------------------------------------------------------------------------
# Render
# -----------------------------------------------------------------------------

func refresh() -> void:
	if _controller == null: return
	_rebuild(deployed_list, _controller.slots.filter(func(u): return u != null))
	_rebuild(bench_list, _controller.bench)

func _rebuild(container: VBoxContainer, units: Array) -> void:
	for child in container.get_children():
		child.queue_free()
	if units.is_empty():
		var lbl = Label.new()
		lbl.text = "  (none)"
		lbl.modulate = Color(1, 1, 1, 0.4)
		container.add_child(lbl)
		return
	for u in units:
		container.add_child(_make_row(u))

func _make_row(unit: Unit) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(0, 44)
	btn.text = "%s  Lv%d %s" % [unit.unit_name, unit.level, unit.class_id]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.toggle_mode = true
	btn.button_pressed = (unit == _picked)
	btn.pressed.connect(func(): unit_picked.emit(unit))
	return btn

# -----------------------------------------------------------------------------
# Picked-state changes
# -----------------------------------------------------------------------------

func _on_picked_changed(unit) -> void:
	_picked = unit
	bench_btn.disabled = (unit == null)
	refresh()

# -----------------------------------------------------------------------------
# Buttons
# -----------------------------------------------------------------------------

func _on_begin_pressed() -> void:
	begin_pressed.emit()

func _on_bench_pressed() -> void:
	bench_requested.emit()
