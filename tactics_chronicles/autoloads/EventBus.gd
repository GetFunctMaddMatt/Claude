extends Node
## Central signal bus. All systems talk through here -- keeps everything decoupled
## and makes adding multiplayer easy (remote controller just listens to the same signals).
## @warning_ignore annotations silence the expected "unused_signal" warnings: signals
## in a bus are emitted and connected by other files, never by this one.

# -- Battle lifecycle ----------------------------------------------------------
@warning_ignore("unused_signal") signal battle_started(map_id: String)
@warning_ignore("unused_signal") signal battle_ended(result: String)         # "victory" | "defeat" | "retreat"
@warning_ignore("unused_signal") signal battle_state_changed(state: String)

# -- Deploy phase --------------------------------------------------------------
@warning_ignore("unused_signal") signal deployment_zones_shown(zones: Array) # Vector2i array; empty = hide
@warning_ignore("unused_signal") signal deploy_unit_picked(unit: Node)        # null when nothing picked
@warning_ignore("unused_signal") signal deploy_layout_changed()               # roster/bench moved -- repaint UI

# -- Turn flow -----------------------------------------------------------------
@warning_ignore("unused_signal") signal turn_started(unit: Node)
@warning_ignore("unused_signal") signal turn_ended(unit: Node)
@warning_ignore("unused_signal") signal turn_order_updated(queue: Array)
@warning_ignore("unused_signal") signal momentum_changed(unit: Node, value: int)

# -- Unit actions --------------------------------------------------------------
@warning_ignore("unused_signal") signal unit_moved(unit: Node, from: Vector2i, to: Vector2i)
@warning_ignore("unused_signal") signal unit_damaged(unit: Node, amount: int, element: String, source: Node)
@warning_ignore("unused_signal") signal unit_healed(unit: Node, amount: int)
@warning_ignore("unused_signal") signal unit_mp_changed(unit: Node, delta: int)
@warning_ignore("unused_signal") signal unit_ko(unit: Node)
@warning_ignore("unused_signal") signal unit_revived(unit: Node)
@warning_ignore("unused_signal") signal unit_status_applied(unit: Node, status_id: String)
@warning_ignore("unused_signal") signal unit_status_removed(unit: Node, status_id: String)
@warning_ignore("unused_signal") signal unit_stat_changed(unit: Node, stat: String, old_val: int, new_val: int)

# -- Skill resolution ----------------------------------------------------------
@warning_ignore("unused_signal") signal skill_used(unit: Node, skill_id: String, target_pos: Vector2i)
@warning_ignore("unused_signal") signal skill_resolved(results: Array)        # array of result dicts

# -- Grid interaction ----------------------------------------------------------
@warning_ignore("unused_signal") signal tile_hovered(pos: Vector2i)
@warning_ignore("unused_signal") signal tile_selected(pos: Vector2i)
@warning_ignore("unused_signal") signal move_range_updated(tiles: Array)
@warning_ignore("unused_signal") signal skill_range_updated(tiles: Array)

# -- Overworld -----------------------------------------------------------------
@warning_ignore("unused_signal") signal chapter_started(chapter_id: String)
@warning_ignore("unused_signal") signal node_entered(node_id: String)
@warning_ignore("unused_signal") signal cutscene_started(scene_id: String)
@warning_ignore("unused_signal") signal cutscene_ended(scene_id: String)

# -- Party / inventory ---------------------------------------------------------
@warning_ignore("unused_signal") signal party_updated()
@warning_ignore("unused_signal") signal item_acquired(item_id: String, qty: int)
@warning_ignore("unused_signal") signal item_used(item_id: String, target_unit: Node)
@warning_ignore("unused_signal") signal item_equipped(unit: Node, slot: String, item_id: String)
@warning_ignore("unused_signal") signal gil_changed(new_total: int, delta: int)
@warning_ignore("unused_signal") signal job_level_up(unit: Node, class_id: String, new_level: int)
@warning_ignore("unused_signal") signal skill_unlocked(unit: Node, skill_id: String)

# -- UI ------------------------------------------------------------------------
@warning_ignore("unused_signal") signal menu_opened(menu_name: String)
@warning_ignore("unused_signal") signal menu_closed(menu_name: String)
@warning_ignore("unused_signal") signal shop_opened(shop_data: Dictionary)
@warning_ignore("unused_signal") signal notification_requested(text: String, color: Color)
