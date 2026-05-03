extends Node
## Central signal bus. All systems talk through here — keeps everything decoupled
## and makes PvP easy (remote controller just listens to the same signals).

# ── Battle lifecycle ──────────────────────────────────────────────────────────
signal battle_started(map_id: String)
signal battle_ended(result: String)          # "victory" | "defeat" | "retreat"
signal battle_state_changed(state: String)

# ── Turn flow ─────────────────────────────────────────────────────────────────
signal turn_started(unit: Node)
signal turn_ended(unit: Node)
signal turn_order_updated(queue: Array)
signal momentum_changed(unit: Node, value: int)

# ── Unit actions ──────────────────────────────────────────────────────────────
signal unit_moved(unit: Node, from: Vector2i, to: Vector2i)
signal unit_damaged(unit: Node, amount: int, element: String, source: Node)
signal unit_healed(unit: Node, amount: int)
signal unit_mp_changed(unit: Node, delta: int)
signal unit_ko(unit: Node)
signal unit_revived(unit: Node)
signal unit_status_applied(unit: Node, status_id: String)
signal unit_status_removed(unit: Node, status_id: String)
signal unit_stat_changed(unit: Node, stat: String, old_val: int, new_val: int)

# ── Skill resolution ──────────────────────────────────────────────────────────
signal skill_used(unit: Node, skill_id: String, target_pos: Vector2i)
signal skill_resolved(results: Array)        # array of result dicts

# ── Grid interaction ──────────────────────────────────────────────────────────
signal tile_hovered(pos: Vector2i)
signal tile_selected(pos: Vector2i)
signal move_range_updated(tiles: Array)
signal skill_range_updated(tiles: Array)

# ── Overworld ─────────────────────────────────────────────────────────────────
signal chapter_started(chapter_id: String)
signal node_entered(node_id: String)
signal cutscene_started(scene_id: String)
signal cutscene_ended(scene_id: String)

# ── Party / inventory ─────────────────────────────────────────────────────────
signal party_updated()
signal item_acquired(item_id: String, qty: int)
signal item_used(item_id: String, target_unit: Node)
signal item_equipped(unit: Node, slot: String, item_id: String)
signal gil_changed(new_total: int, delta: int)
signal job_level_up(unit: Node, class_id: String, new_level: int)
signal skill_unlocked(unit: Node, skill_id: String)

# ── UI ────────────────────────────────────────────────────────────────────────
signal menu_opened(menu_name: String)
signal menu_closed(menu_name: String)
signal shop_opened(shop_data: Dictionary)
signal notification_requested(text: String, color: Color)
