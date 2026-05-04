class_name Unit
extends Node2D
## A single combatant on the battlefield.
## Instantiated from save data or enemy definitions; never holds scene references.

# -- Identity ------------------------------------------------------------------
var unit_id:   String = ""
var unit_name: String = "Unknown"
var class_id:  String = "soldier"
var is_player: bool   = true
var controller: String = "player"   # "player" | "ai" | "pvp_remote"

# -- Level / job ---------------------------------------------------------------
var level:      int = 1
var exp:        int = 0
var job_level:  int = 1
var job_exp:    int = 0
var unlocked_skills: Array = []
var equipped: Dictionary = {
	"active":   [],   # up to 4 skill IDs
	"reaction": "",
	"supports": [],   # up to 2
	"movement": ""
}

# -- Base stats (from class data + growth) -------------------------------------
var base_hp:   int = 80
var base_mp:   int = 40
var base_atk:  int = 10
var base_matk: int = 8
var base_def:  int = 5
var base_mdef: int = 4
var base_spd:  int = 5
var base_move: int = 4
var base_jump: int = 3

# -- Current stats (base + equipment + buffs) ----------------------------------
var max_hp:  int = 80
var max_mp:  int = 40
var hp:      int = 80
var mp:      int = 40
var atk:     int = 10
var matk:    int = 8
var def:     int = 5
var mdef:    int = 4
var spd:     int = 5
var move:    int = 4
var jump:    int = 3
var crit:    int = 0
var eva:     int = 0

# -- Equipment -----------------------------------------------------------------
var equipment: Dictionary = { "weapon": "", "armor": "", "accessory": "" }

# -- Battle state --------------------------------------------------------------
var grid_pos:   Vector2i = Vector2i.ZERO
var facing:     String   = "south"
var has_moved:  bool     = false
var has_acted:  bool     = false
var is_ko:      bool     = false
var momentum:   int      = 0   # 0-100; at 100 a Surge action becomes available

# -- Status effects ------------------------------------------------------------
# { status_id: { duration: int, stacks: int, data: dict } }
var statuses: Dictionary = {}

# -- Stat modifiers from buffs (additive, cleared each battle) -----------------
var _stat_mods: Dictionary = {}

# -----------------------------------------------------------------------------
# Initialisation
# -----------------------------------------------------------------------------

func init_from_class(cid: String, lv: int = 1) -> void:
	class_id = cid
	level    = lv
	var cd   = DataManager.get_class_data(cid)
	if cd.is_empty():
		push_error("Unit.init_from_class: unknown class %s" % cid)
		return
	var base = cd.get("base_stats", {})
	base_hp   = base.get("hp",   80)
	base_mp   = base.get("mp",   40)
	base_atk  = base.get("atk",  10)
	base_matk = base.get("matk",  8)
	base_def  = base.get("def",   5)
	base_mdef = base.get("mdef",  4)
	base_spd  = base.get("spd",   5)
	base_move = base.get("move",  4)
	base_jump = base.get("jump",  3)
	recalculate_stats()
	hp = max_hp
	mp = max_mp

# -----------------------------------------------------------------------------
# Stat calculation
# -----------------------------------------------------------------------------

func recalculate_stats() -> void:
	max_hp  = base_hp
	max_mp  = base_mp
	atk     = base_atk
	matk    = base_matk
	def     = base_def
	mdef    = base_mdef
	spd     = base_spd
	move    = base_move
	jump    = base_jump
	crit    = 0
	eva     = 0
	_apply_equipment_stats()
	_apply_stat_mods()

func _apply_equipment_stats() -> void:
	for slot in equipment:
		var item_id = equipment[slot]
		if item_id == "":
			continue
		var item = DataManager.get_item(item_id)
		if item.is_empty():
			continue
		var s = item.get("stats", {})
		max_hp  += s.get("hp",   0)
		max_mp  += s.get("mp",   0)
		atk     += s.get("atk",  0)
		matk    += s.get("matk", 0)
		def     += s.get("def",  0)
		mdef    += s.get("mdef", 0)
		spd     += s.get("spd",  0)
		move    += s.get("move", 0)
		jump    += s.get("jump", 0)
		crit    += s.get("crit", 0)
		eva     += s.get("eva",  0)

func _apply_stat_mods() -> void:
	for stat in _stat_mods:
		match stat:
			"atk":   atk   += _stat_mods[stat]
			"matk":  matk  += _stat_mods[stat]
			"def":   def   += _stat_mods[stat]
			"mdef":  mdef  += _stat_mods[stat]
			"spd":   spd   += _stat_mods[stat]
			"move":  move  += _stat_mods[stat]
			"jump":  jump  += _stat_mods[stat]

func apply_stat_mod(stat: String, value: int, _duration: int = -1) -> void:
	_stat_mods[stat] = _stat_mods.get(stat, 0) + value
	recalculate_stats()
	EventBus.unit_stat_changed.emit(self, stat, 0, value)

# -----------------------------------------------------------------------------
# HP / MP
# -----------------------------------------------------------------------------

func take_damage(amount: int, element: String = "none", source: Node = null) -> int:
	var actual = max(1, amount)
	hp = max(0, hp - actual)
	EventBus.unit_damaged.emit(self, actual, element, source)
	if hp == 0:
		_on_ko()
	return actual

func heal(amount: int) -> int:
	if is_ko:
		return 0
	var actual = min(amount, max_hp - hp)
	hp += actual
	EventBus.unit_healed.emit(self, actual)
	return actual

func restore_mp(amount: int) -> int:
	var actual = min(amount, max_mp - mp)
	mp += actual
	EventBus.unit_mp_changed.emit(self, actual)
	return actual

func drain_mp(amount: int) -> int:
	var actual = min(amount, mp)
	mp -= actual
	EventBus.unit_mp_changed.emit(self, -actual)
	return actual

func _on_ko() -> void:
	is_ko = true
	statuses.clear()
	EventBus.unit_ko.emit(self)

func revive(hp_percent: float = 0.5) -> void:
	is_ko = false
	hp = max(1, int(max_hp * hp_percent))
	EventBus.unit_revived.emit(self)

# -----------------------------------------------------------------------------
# Status effects
# -----------------------------------------------------------------------------

func apply_status(status_id: String, duration: int) -> void:
	statuses[status_id] = { "duration": duration, "stacks": 1 }
	EventBus.unit_status_applied.emit(self, status_id)

func remove_status(status_id: String) -> void:
	if statuses.erase(status_id):
		EventBus.unit_status_removed.emit(self, status_id)

func has_status(status_id: String) -> bool:
	return statuses.has(status_id)

func tick_statuses() -> void:
	var to_remove: Array = []
	for sid in statuses:
		var s = statuses[sid]
		_apply_status_tick(sid)
		s["duration"] -= 1
		if s["duration"] <= 0:
			to_remove.append(sid)
	for sid in to_remove:
		remove_status(sid)

func _apply_status_tick(sid: String) -> void:
	match sid:
		"poison":  take_damage(max(1, max_hp / 12), "none", null)
		"regen":   heal(max(1, max_hp / 8))
		"burn":    take_damage(8, "fire", null)
		_:         pass   # non-dot statuses handled by action resolver

# -----------------------------------------------------------------------------
# Skill access
# -----------------------------------------------------------------------------

func can_use_skill(skill_id: String) -> bool:
	if is_ko or has_acted:
		return false
	if skill_id not in equipped.get("active", []):
		return false
	var sk = DataManager.get_skill(skill_id)
	return mp >= sk.get("mp_cost", 0) and not has_status("silence")

func get_active_skills() -> Array:
	return equipped.get("active", [])

func unlock_skill(skill_id: String) -> void:
	if skill_id not in unlocked_skills:
		unlocked_skills.append(skill_id)
		EventBus.skill_unlocked.emit(self, skill_id)

# -----------------------------------------------------------------------------
# Serialization
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"unit_id": unit_id, "unit_name": unit_name, "class_id": class_id,
		"level": level, "exp": exp, "job_level": job_level, "job_exp": job_exp,
		"base_hp": base_hp, "base_mp": base_mp,
		"base_atk": base_atk, "base_matk": base_matk,
		"base_def": base_def, "base_mdef": base_mdef,
		"base_spd": base_spd, "base_move": base_move, "base_jump": base_jump,
		"hp": hp, "mp": mp,
		"equipment": equipment,
		"unlocked_skills": unlocked_skills,
		"equipped": equipped
	}

static func from_save_data(data: Dictionary) -> Unit:
	var u = Unit.new()
	u.unit_id        = data.get("unit_id", "")
	u.unit_name      = data.get("unit_name", "Recruit")
	u.class_id       = data.get("class_id", "soldier")
	u.level          = data.get("level", 1)
	u.exp            = data.get("exp", 0)
	u.job_level      = data.get("job_level", 1)
	u.job_exp        = data.get("job_exp", 0)
	u.base_hp        = data.get("base_hp", 80)
	u.base_mp        = data.get("base_mp", 40)
	u.base_atk       = data.get("base_atk", 10)
	u.base_matk      = data.get("base_matk", 8)
	u.base_def       = data.get("base_def", 5)
	u.base_mdef      = data.get("base_mdef", 4)
	u.base_spd       = data.get("base_spd", 5)
	u.base_move      = data.get("base_move", 4)
	u.base_jump      = data.get("base_jump", 3)
	u.equipment      = data.get("equipment", { "weapon": "", "armor": "", "accessory": "" })
	u.unlocked_skills = data.get("unlocked_skills", [])
	u.equipped       = data.get("equipped", { "active": [], "reaction": "", "supports": [], "movement": "" })
	u.recalculate_stats()
	u.hp = data.get("hp", u.max_hp)
	u.mp = data.get("mp", u.max_mp)
	return u
