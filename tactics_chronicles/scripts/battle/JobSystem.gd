class_name JobSystem
extends Node
## Handles experience, levelling, job progression, and skill unlocks.
## Called by BattleEngine after a victory.

# EXP needed to reach the next level: level * BASE_EXP_PER_LEVEL
const BASE_EXP_PER_LEVEL: int = 100
# JP awarded per battle (scales with enemy level)
const BASE_JP_PER_BATTLE: int = 40
# JP needed for each job level: job_level * BASE_JP_PER_JOB_LEVEL
const BASE_JP_PER_JOB_LEVEL: int = 60

signal level_up(unit: Unit, new_level: int)
signal job_level_up(unit: Unit, class_id: String, new_level: int)
signal skill_unlocked(unit: Unit, skill_id: String)

# -----------------------------------------------------------------------------
# Called after each victory
# -----------------------------------------------------------------------------

func award_battle_rewards(player_units: Array, map_data: Dictionary) -> Array:
	var rewards  = map_data.get("rewards", {})
	var base_exp = rewards.get("exp", 80)
	var base_jp  = BASE_JP_PER_BATTLE
	var results: Array = []   # [{unit, exp_gained, jp_gained, levelled_up, skills_unlocked}]

	for unit in player_units:
		if unit.is_ko: continue
		var r = _award_unit(unit, base_exp, base_jp)
		results.append(r)
		# Persist to GameState party array
		_sync_to_save(unit)

	return results

func _award_unit(unit: Unit, exp: int, jp: int) -> Dictionary:
	var result = {
		"unit":             unit,
		"exp_gained":       exp,
		"jp_gained":        jp,
		"levelled_up":      false,
		"job_levelled_up":  false,
		"skills_unlocked":  []
	}

	# -- Character EXP --------------------------------------------------------
	unit.exp += exp
	var threshold = unit.level * BASE_EXP_PER_LEVEL
	if unit.exp >= threshold:
		unit.exp -= threshold
		unit.level += 1
		_apply_stat_growth(unit)
		result["levelled_up"] = true
		emit_signal("level_up", unit, unit.level)
		EventBus.job_level_up.emit(unit, unit.class_id, unit.job_level)
		FloatingText.level_up(get_tree().root, Vector2.ZERO)  # pos set by HUD

	# -- Job EXP ---------------------------------------------------------------
	unit.job_exp += jp
	var jp_threshold = unit.job_level * BASE_JP_PER_JOB_LEVEL
	if unit.job_exp >= jp_threshold:
		unit.job_exp -= jp_threshold
		unit.job_level += 1
		result["job_levelled_up"] = true
		emit_signal("job_level_up", unit, unit.class_id, unit.job_level)

		# Unlock skills available at new job level
		var new_skills = _check_skill_unlocks(unit)
		result["skills_unlocked"] = new_skills

	return result

# -----------------------------------------------------------------------------
# Stat growth
# -----------------------------------------------------------------------------

func _apply_stat_growth(unit: Unit) -> void:
	var cd     = DataManager.get_class_data(unit.class_id)
	var growth = cd.get("stat_growth", {})
	# Growth values are per-level increments
	unit.base_hp   += growth.get("hp",   4)
	unit.base_mp   += growth.get("mp",   2)
	unit.base_atk  += growth.get("atk",  1)
	unit.base_matk += growth.get("matk", 1)
	unit.base_def  += growth.get("def",  1)
	unit.base_mdef += growth.get("mdef", 1)
	unit.base_spd  += growth.get("spd",  0)
	# Heal from level up
	unit.recalculate_stats()
	unit.hp = unit.max_hp
	unit.mp = unit.max_mp

# -----------------------------------------------------------------------------
# Skill unlocks
# -----------------------------------------------------------------------------

func _check_skill_unlocks(unit: Unit) -> Array:
	var newly_unlocked: Array = []
	var available = DataManager.get_skills_unlocked_at(unit.class_id, unit.job_level)
	for sk_id in available:
		if sk_id not in unit.unlocked_skills:
			unit.unlock_skill(sk_id)
			newly_unlocked.append(sk_id)
			emit_signal("skill_unlocked", unit, sk_id)
	return newly_unlocked

func get_all_unlocked(unit: Unit) -> Array:
	return unit.unlocked_skills.duplicate()

func get_available_to_unlock(unit: Unit) -> Array:
	return DataManager.get_skills_unlocked_at(unit.class_id, unit.job_level)

# -----------------------------------------------------------------------------
# Progress query helpers (used by PartyScreen)
# -----------------------------------------------------------------------------

func exp_to_next_level(unit: Unit) -> int:
	return unit.level * BASE_EXP_PER_LEVEL - unit.exp

func jp_to_next_job_level(unit: Unit) -> int:
	return unit.job_level * BASE_JP_PER_JOB_LEVEL - unit.job_exp

func exp_percent(unit: Unit) -> float:
	var needed = unit.level * BASE_EXP_PER_LEVEL
	return float(unit.exp) / float(needed)

func jp_percent(unit: Unit) -> float:
	var needed = unit.job_level * BASE_JP_PER_JOB_LEVEL
	return float(unit.job_exp) / float(needed)

# -----------------------------------------------------------------------------
# Sync back to GameState party array
# -----------------------------------------------------------------------------

func _sync_to_save(unit: Unit) -> void:
	for i in GameState.party.size():
		if GameState.party[i].get("unit_id") == unit.unit_id:
			GameState.party[i] = unit.serialize()
			break
