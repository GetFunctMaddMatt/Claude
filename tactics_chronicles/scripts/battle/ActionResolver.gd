class_name ActionResolver
extends Node
## Resolves skill use into a list of result dicts.
## Pure logic — no scene nodes, no animations. BattleEngine applies results.
##
## Result dict shape:
##   { unit, damage, healing, mp_drain, statuses_applied, statuses_removed,
##     stat_mods, revived, ko, miss, crit, element }

const HEIGHT_DMG_BONUS   = 0.15   # per tier above target
const HEIGHT_DMG_PENALTY = 0.15   # per tier below target

func resolve_skill(attacker: Unit, skill_id: String,
		target_pos: Vector2i, grid: BattleGrid) -> Array:
	var skill = DataManager.get_skill(skill_id)
	if skill.is_empty():
		return []

	var pattern   = skill.get("target_pattern", "single")
	var alignment = skill.get("target_alignment", "enemy")
	var aoe_r     = skill.get("aoe_radius", 0)

	# Resolve impact tile(s) then expand AOE if needed
	var impact_tiles: Array = []
	if pattern in ["explosion_1", "explosion_2"]:
		impact_tiles = grid.get_tiles_in_pattern(
			target_pos, "circle_enemy" if alignment == "enemy" else "circle",
			skill.get("range", 1),
			1 if pattern == "explosion_1" else 2,
			attacker.facing)
	else:
		impact_tiles = grid.get_tiles_in_pattern(
			attacker.grid_pos, pattern,
			skill.get("range", 1), aoe_r, attacker.facing)

	# Filter to relevant units
	var targets: Array = []
	for pos in impact_tiles:
		var u = grid.get_unit_at(pos)
		if u == null or u.is_ko:
			continue
		if alignment == "enemy"  and u.is_player == attacker.is_player: continue
		if alignment == "ally"   and u.is_player != attacker.is_player: continue
		if not _check_los(attacker, u, grid): continue
		targets.append(u)

	var results: Array = []
	for target in targets:
		results.append(_apply_to_unit(attacker, target, skill, grid))
	return results

# ─────────────────────────────────────────────────────────────────────────────
# Per-target resolution
# ─────────────────────────────────────────────────────────────────────────────

func _apply_to_unit(attacker: Unit, target: Unit,
		skill: Dictionary, grid: BattleGrid) -> Dictionary:
	var result = {
		"unit": target, "damage": 0, "healing": 0, "mp_drain": 0,
		"statuses_applied": [], "statuses_removed": [],
		"stat_mods": [], "revived": false, "ko": false,
		"miss": false, "crit": false,
		"element": skill.get("element", "none")
	}

	# Hit check
	if not _roll_hit(attacker, target, skill, grid):
		result["miss"] = true
		return result

	var dmg_type = skill.get("damage_type", "none")
	var power    = float(skill.get("power", 1.0))
	var element  = skill.get("element", "none")

	match dmg_type:
		"physical":
			var crit = _roll_crit(attacker)
			result["crit"] = crit
			result["damage"] = _calc_physical(attacker, target, power, grid, crit)
		"magical":
			result["damage"] = _calc_magical(attacker, target, power, element, grid)
		"mixed":
			var phys_p = skill.get("power_phys", power * 0.6)
			var mag_p  = skill.get("power_mag",  power * 0.4)
			result["damage"] = (_calc_physical(attacker, target, phys_p, grid, false)
							  + _calc_magical(attacker, target, mag_p, element, grid))
		"none":
			pass

	# Effects (status, heal, drain, stat_mod, etc.)
	for eff in skill.get("effects", []):
		_apply_effect(attacker, target, eff, result)

	return result

# ─────────────────────────────────────────────────────────────────────────────
# Damage formulas
# ─────────────────────────────────────────────────────────────────────────────

func _calc_physical(attacker: Unit, target: Unit, power: float,
		grid: BattleGrid, is_crit: bool) -> int:
	var base    = attacker.atk * power
	var hd      = grid.height_diff(attacker.grid_pos, target.grid_pos)
	var h_mult  = 1.0 + hd * HEIGHT_DMG_BONUS if hd > 0 else 1.0 + hd * HEIGHT_DMG_PENALTY
	var cover   = grid.get_cover_bonus(target.grid_pos) / 100.0
	var def_red = 1.0 - (float(target.def) / (float(target.def) + 50.0))
	var damage  = int(base * h_mult * (1.0 - cover) * def_red)
	if is_crit:
		damage = int(damage * 1.5)
	return maxi(1, damage)

func _calc_magical(attacker: Unit, target: Unit, power: float,
		element: String, grid: BattleGrid) -> int:
	var base   = attacker.matk * power
	var hd     = grid.height_diff(attacker.grid_pos, target.grid_pos)
	var h_mult = 1.0 + hd * HEIGHT_DMG_BONUS if hd > 0 else 1.0 + hd * HEIGHT_DMG_PENALTY
	var mdef_r = 1.0 - (float(target.mdef) / (float(target.mdef) + 50.0))
	var e_mult = _element_multiplier(element, target)
	return maxi(1, int(base * h_mult * mdef_r * e_mult))

func _element_multiplier(element: String, target: Unit) -> float:
	# TODO: hook into unit's elemental affinities/weaknesses from equipment
	# Undead take 2x holy; placeholder:
	if element == "holy" and target.has_status("zombie"): return 2.0
	return 1.0

# ─────────────────────────────────────────────────────────────────────────────
# Effect application
# ─────────────────────────────────────────────────────────────────────────────

func _apply_effect(attacker: Unit, target: Unit,
		eff: Dictionary, result: Dictionary) -> void:
	match eff.get("type", ""):
		"status":
			var sid      = eff.get("id", "")
			var chance   = eff.get("chance", 100)
			var duration = eff.get("duration", 3)
			if sid != "" and _roll(chance):
				result["statuses_applied"].append({ "id": sid, "duration": duration })
		"stat_mod":
			result["stat_mods"].append({
				"stat":     eff.get("stat", ""),
				"value":    eff.get("value", 0),
				"duration": eff.get("duration", -1)
			})
		"heal":
			var h = eff.get("flat", 0)
			if eff.has("percent_max"):
				h = int(target.max_hp * float(eff["percent_max"]))
			result["healing"] += h
		"drain_hp":
			var pct = float(eff.get("percent_damage", 1.0))
			result["healing"] += int(result["damage"] * pct)
		"drain_mp":
			result["mp_drain"] += eff.get("amount", 0)
		"revive":
			if target.is_ko:
				result["revived"] = true
				result["healing"] = int(target.max_hp * float(eff.get("hp_percent", 0.5)))
		"act_again":
			pass  # BattleEngine handles this flag
		"teleport_adjacent_to_target":
			pass  # BattleEngine handles repositioning
		"place_trap":
			pass  # BattleEngine places object on grid

# ─────────────────────────────────────────────────────────────────────────────
# Hit / crit rolls
# ─────────────────────────────────────────────────────────────────────────────

func _roll_hit(attacker: Unit, target: Unit,
		skill: Dictionary, grid: BattleGrid) -> bool:
	if skill.get("damage_type", "none") == "none":
		return true  # status/buff skills don't miss (status chance handled per effect)
	var base_hit = 90
	var cover    = grid.get_cover_bonus(target.grid_pos)
	var evasion  = target.eva
	var chance   = base_hit - cover - evasion
	return _roll(clamp(chance, 5, 99))

func _roll_crit(attacker: Unit) -> bool:
	return _roll(attacker.crit + 5)

func _roll(percent: int) -> bool:
	return randi() % 100 < percent

# ─────────────────────────────────────────────────────────────────────────────
# LOS
# ─────────────────────────────────────────────────────────────────────────────

func _check_los(attacker: Unit, target: Unit, grid: BattleGrid) -> bool:
	var sk = DataManager.get_skill("")  # called with actual skill in full impl
	# Melee skills skip LOS check
	return grid.check_los(attacker.grid_pos, target.grid_pos)
