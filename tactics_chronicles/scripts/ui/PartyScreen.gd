class_name PartyScreen
extends Control
## Party management screen: equip gear, assign skills, apply prebuilds, view stats.

@onready var unit_list:     ItemList  = $UnitList
@onready var stat_panel:    Control   = $StatPanel
@onready var skill_panel:   Control   = $SkillPanel
@onready var equip_panel:   Control   = $EquipPanel
@onready var prebuild_menu: Control   = $PrebuildMenu
@onready var tab_bar:       TabBar    = $TabBar

var current_unit: Unit = null
var _units: Array = []

func _ready() -> void:
	tab_bar.tab_changed.connect(_on_tab_changed)
	unit_list.item_selected.connect(_on_unit_selected)

func open(units: Array) -> void:
	_units = units
	_populate_unit_list()
	if units.size() > 0:
		unit_list.select(0)
		_show_unit(units[0])
	visible = true
	EventBus.menu_opened.emit("party")

func close() -> void:
	visible = false
	EventBus.menu_closed.emit("party")

# -----------------------------------------------------------------------------
# Unit list
# -----------------------------------------------------------------------------

func _populate_unit_list() -> void:
	unit_list.clear()
	for u in _units:
		unit_list.add_item("%s  Lv%d %s" % [u.unit_name, u.level, u.class_id])

func _on_unit_selected(idx: int) -> void:
	_show_unit(_units[idx])

func _show_unit(unit: Unit) -> void:
	current_unit = unit
	_refresh_stats(unit)
	_refresh_skills(unit)
	_refresh_equip(unit)

# -----------------------------------------------------------------------------
# Stats tab
# -----------------------------------------------------------------------------

func _refresh_stats(unit: Unit) -> void:
	# TODO: fill StatPanel labels from unit fields
	pass

# -----------------------------------------------------------------------------
# Skills tab
# -----------------------------------------------------------------------------

func _refresh_skills(unit: Unit) -> void:
	# Show all unlocked skills; highlight equipped ones; allow drag-to-slot
	# TODO: populate SkillPanel grid
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

# -----------------------------------------------------------------------------
# Equipment tab
# -----------------------------------------------------------------------------

func _refresh_equip(unit: Unit) -> void:
	# TODO: show equipped weapon/armor/accessory; allow swapping from inventory
	pass

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
	stat_panel.visible   = (tab == 0)
	skill_panel.visible  = (tab == 1)
	equip_panel.visible  = (tab == 2)
	prebuild_menu.visible = (tab == 3)
