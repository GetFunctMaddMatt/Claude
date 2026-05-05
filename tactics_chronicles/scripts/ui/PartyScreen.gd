class_name PartyScreen
extends Control
## Party management screen: equip gear, assign skills, apply prebuilds, view stats.
## Standalone scene (PartyScreen.tscn) -- instantiated via add_child, freed via signal.

signal closed()

@onready var unit_list:     ItemList      = $Margin/VBox/Body/UnitList
@onready var tab_bar:       TabBar        = $Margin/VBox/Body/Right/TabBar
@onready var stat_panel:    PanelContainer = $Margin/VBox/Body/Right/StatPanel
@onready var skill_panel:   PanelContainer = $Margin/VBox/Body/Right/SkillPanel
@onready var equip_panel:   PanelContainer = $Margin/VBox/Body/Right/EquipPanel
@onready var prebuild_menu: PanelContainer = $Margin/VBox/Body/Right/PrebuildMenu
@onready var close_btn:     Button        = $Margin/VBox/CloseBtn

var current_unit: Unit = null
var _units: Array = []

func _ready() -> void:
	tab_bar.tab_changed.connect(_on_tab_changed)
	unit_list.item_selected.connect(_on_unit_selected)
	close_btn.pressed.connect(_on_close)

func open(units: Array) -> void:
	_units = units
	_populate_unit_list()
	if units.size() > 0:
		unit_list.select(0)
		_show_unit(units[0])
	EventBus.menu_opened.emit("party")

func _on_close() -> void:
	EventBus.menu_closed.emit("party")
	closed.emit()

# -----------------------------------------------------------------------------
# Unit list
# -----------------------------------------------------------------------------

func _populate_unit_list() -> void:
	unit_list.clear()
	for u in _units:
		var name_str: String = u.unit_name if u is Unit else u.get("unit_name", "?")
		var level: int       = u.level if u is Unit else u.get("level", 1)
		var class_id: String = u.class_id if u is Unit else u.get("class_id", "?")
		unit_list.add_item("%s  Lv%d %s" % [name_str, level, class_id])

func _on_unit_selected(idx: int) -> void:
	_show_unit(_units[idx])

func _show_unit(unit) -> void:
	current_unit = unit
	_refresh_stats(unit)
	_refresh_skills(unit)
	_refresh_equip(unit)

# -----------------------------------------------------------------------------
# Stats / Skills / Equip
# -----------------------------------------------------------------------------

func _refresh_stats(_unit) -> void:
	# TODO: fill StatPanel labels from unit fields
	pass

func _refresh_skills(_unit) -> void:
	# TODO: populate SkillPanel grid; allow drag-to-slot
	pass

func _refresh_equip(_unit) -> void:
	# TODO: show equipped weapon/armor/accessory; allow swapping from inventory
	pass

func apply_prebuild(prebuild_id: String) -> void:
	if current_unit == null: return
	var pb = DataManager.get_prebuilds_for_class(current_unit.class_id).get(prebuild_id, {})
	if pb.is_empty(): return
	current_unit.equipped["active"]   = pb.get("active_skills", [])
	current_unit.equipped["reaction"] = pb.get("reaction", "")
	current_unit.equipped["supports"] = pb.get("supports", [])
	current_unit.equipped["movement"] = pb.get("movement", "")
	current_unit.recalculate_stats()
	EventBus.party_updated.emit()
	_refresh_skills(current_unit)

func equip_skill(skill_id: String, slot_type: String, slot_index: int = 0) -> void:
	if current_unit == null: return
	match slot_type:
		"active":
			var actives = current_unit.equipped["active"]
			if actives.size() <= slot_index:
				actives.resize(slot_index + 1)
			actives[slot_index] = skill_id
		"reaction":  current_unit.equipped["reaction"] = skill_id
		"movement":  current_unit.equipped["movement"] = skill_id
		"support":
			var supports = current_unit.equipped["supports"]
			if supports.size() <= slot_index:
				supports.resize(slot_index + 1)
			supports[slot_index] = skill_id
	current_unit.recalculate_stats()
	EventBus.party_updated.emit()

func equip_item(item_id: String, slot: String) -> void:
	if current_unit == null: return
	var item = DataManager.get_item(item_id)
	if item.is_empty(): return
	var allowed = item.get("allowed_classes", "all")
	if allowed != "all" and current_unit.class_id not in allowed:
		EventBus.notification_requested.emit("This class can't equip that.", Color.RED)
		return
	current_unit.equipment[slot] = item_id
	current_unit.recalculate_stats()
	EventBus.item_equipped.emit(current_unit, slot, item_id)
	_refresh_stats(current_unit)

# -----------------------------------------------------------------------------
# Tab switching
# -----------------------------------------------------------------------------

func _on_tab_changed(tab: int) -> void:
	stat_panel.visible    = (tab == 0)
	skill_panel.visible   = (tab == 1)
	equip_panel.visible   = (tab == 2)
	prebuild_menu.visible = (tab == 3)
