class_name PostBattleScreen
extends Control
## Shown after every battle. Displays EXP/JP gains, level-ups, skill unlocks,
## and items/gil earned. "Continue" returns to overworld.
## Standalone scene (PostBattleScreen.tscn) -- instantiated via add_child, freed via signal.

signal closed()

@onready var result_label:   Label          = $Margin/VBox/ResultLabel
@onready var gil_label:      Label          = $Margin/VBox/GilLabel
@onready var items_label:    Label          = $Margin/VBox/ItemsLabel
@onready var unit_rows:      VBoxContainer  = $Margin/VBox/UnitRows
@onready var continue_btn:   Button         = $Margin/VBox/ContinueBtn
@onready var skills_panel:   VBoxContainer  = $Margin/VBox/SkillsPanel

var _on_continue: Callable = Callable()

func _ready() -> void:
	continue_btn.pressed.connect(_on_continue_pressed)

# -----------------------------------------------------------------------------
# Open with results
# -----------------------------------------------------------------------------

func show_results(victory: bool, rewards: Dictionary,
		unit_results: Array, on_continue: Callable) -> void:
	_on_continue = on_continue

	result_label.text     = "VICTORY!" if victory else "DEFEAT"
	result_label.modulate = Color(1.0, 0.9, 0.2) if victory else Color(0.8, 0.2, 0.2)

	if victory:
		gil_label.text   = "+%d Gil" % rewards.get("gil", 0)
		_build_item_list(rewards.get("items", []))
		_build_unit_rows(unit_results)
		_build_skill_list(unit_results)
	else:
		gil_label.text   = ""
		items_label.text = "No rewards."

	EventBus.menu_opened.emit("post_battle")

func _build_item_list(items: Array) -> void:
	if items.is_empty():
		items_label.text = ""
		return
	var names: Array = []
	for iid in items:
		var item = DataManager.get_item(iid)
		names.append(item.get("name", iid))
	items_label.text = "Items: " + ", ".join(names)

func _build_unit_rows(results: Array) -> void:
	for child in unit_rows.get_children():
		child.queue_free()
	for r in results:
		var unit: Unit = r["unit"]
		var row        = HBoxContainer.new()
		var name_lbl   = Label.new()
		var exp_lbl    = Label.new()
		var lv_lbl     = Label.new()
		name_lbl.text  = unit.unit_name
		name_lbl.custom_minimum_size = Vector2(120, 0)
		exp_lbl.text   = "+%d EXP  +%d JP" % [r.get("exp_gained", 0), r.get("jp_gained", 0)]
		exp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lv_lbl.text    = "Lv%d" % unit.level
		if r.get("levelled_up", false):
			lv_lbl.text       += " ^"
			lv_lbl.modulate    = Color(1.0, 0.9, 0.2)
		row.add_child(name_lbl)
		row.add_child(exp_lbl)
		row.add_child(lv_lbl)
		unit_rows.add_child(row)

func _build_skill_list(results: Array) -> void:
	for child in skills_panel.get_children():
		child.queue_free()
	for r in results:
		for sk_id in r.get("skills_unlocked", []):
			var sk  = DataManager.get_skill(sk_id)
			var lbl = Label.new()
			lbl.text     = "%s unlocked: %s" % [r["unit"].unit_name, sk.get("name", sk_id)]
			lbl.modulate = Color(0.5, 1.0, 0.7)
			skills_panel.add_child(lbl)

# -----------------------------------------------------------------------------

func _on_continue_pressed() -> void:
	EventBus.menu_closed.emit("post_battle")
	if _on_continue.is_valid():
		_on_continue.call()
	closed.emit()
