class_name GridRenderer
extends Node2D
## Draws the battle grid as colored placeholder tiles.
## Art pass: swap _draw() tile rects for a TileMap with real sprites.
## All terrain colors come from terrain_types.json so adding a terrain = no code change.

const TILE_W:  int = 64
const TILE_H:  int = 48    # shorter height gives subtle depth illusion

# Overlay alpha values
const ALPHA_MOVE:   float = 0.35
const ALPHA_SKILL:  float = 0.30
const ALPHA_HOVER:  float = 0.50
const ALPHA_SELECT: float = 0.70

var grid: BattleGrid = null

# Highlight state
var move_tiles:    Array    = []
var skill_tiles:   Array    = []
var hovered_tile:  Vector2i = Vector2i(-1, -1)
var selected_tile: Vector2i = Vector2i(-1, -1)

# Cached terrain colors (hex string → Color)
var _terrain_colors: Dictionary = {}

func _ready() -> void:
	_cache_terrain_colors()
	EventBus.move_range_updated.connect(func(tiles):  move_tiles  = tiles; queue_redraw())
	EventBus.skill_range_updated.connect(func(tiles): skill_tiles = tiles; queue_redraw())
	EventBus.tile_hovered.connect(func(p):   hovered_tile  = p; queue_redraw())
	EventBus.tile_selected.connect(func(p):  selected_tile = p; queue_redraw())
	EventBus.unit_moved.connect(func(_u, _f, _t): queue_redraw())

func _cache_terrain_colors() -> void:
	var types = DataManager.terrain_types
	for tid in types:
		var hex = types[tid].get("color", "888888")
		_terrain_colors[tid] = Color("#" + hex)

# ─────────────────────────────────────────────────────────────────────────────
# Drawing
# ─────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if grid == null: return
	for y in grid.height:
		for x in grid.width:
			_draw_tile(Vector2i(x, y))
	_draw_overlays()
	_draw_units()
	_draw_objects()

func _draw_tile(pos: Vector2i) -> void:
	var tile   = grid.get_tile(pos)
	if tile.is_empty(): return
	var t_id   = tile.get("t", "grass")
	var h      = tile.get("h", 0)
	var base_c = _terrain_colors.get(t_id, Color(0.4, 0.5, 0.4))
	# Height brightens the tile slightly
	var c      = base_c.lightened(clampf(h * 0.07, 0.0, 0.35))
	var rect   = _tile_rect(pos)
	draw_rect(rect, c)
	# Grid line
	draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)
	# Height label (small, top-right corner)
	if h != 0:
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 12, 12),
			str(h), HORIZONTAL_ALIGNMENT_RIGHT, -1, 9, Color(1, 1, 1, 0.6))

func _draw_overlays() -> void:
	for p in move_tiles:
		draw_rect(_tile_rect(p), Color(0.2, 0.5, 1.0, ALPHA_MOVE))
	for p in skill_tiles:
		draw_rect(_tile_rect(p), Color(1.0, 0.2, 0.2, ALPHA_SKILL))
	if hovered_tile != Vector2i(-1, -1):
		draw_rect(_tile_rect(hovered_tile), Color(1.0, 1.0, 0.3, ALPHA_HOVER), false, 2.0)
	if selected_tile != Vector2i(-1, -1):
		draw_rect(_tile_rect(selected_tile), Color(1.0, 1.0, 1.0, ALPHA_SELECT), false, 2.5)

func _draw_units() -> void:
	if grid == null: return
	for pos in grid.units_on_grid:
		var unit: Unit = grid.units_on_grid[pos]
		_draw_unit(unit, pos)

func _draw_unit(unit: Unit, pos: Vector2i) -> void:
	var rect   = _tile_rect(pos)
	var inset  = rect.grow(-8)
	var color  = Color(0.2, 0.4, 1.0) if unit.is_player else Color(0.9, 0.2, 0.2)
	if unit.is_ko: color = color.darkened(0.5)
	if unit.has_status("invisible"): color.a = 0.35

	draw_rect(inset, color)
	draw_rect(inset, Color(1, 1, 1, 0.8), false, 1.5)

	# Name initial
	var initial = unit.unit_name.left(1).to_upper()
	draw_string(ThemeDB.fallback_font, inset.position + Vector2(inset.size.x * 0.3, inset.size.y * 0.65),
		initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

	# HP bar
	var hp_pct  = float(unit.hp) / float(unit.max_hp)
	var bar_bg  = Rect2(rect.position + Vector2(2, rect.size.y - 7), Vector2(rect.size.x - 4, 5))
	var bar_fg  = Rect2(bar_bg.position, Vector2(bar_bg.size.x * hp_pct, 5))
	draw_rect(bar_bg, Color(0.2, 0.2, 0.2))
	draw_rect(bar_fg, Color(0.1, 0.9, 0.1) if hp_pct > 0.5 else Color(1.0, 0.5, 0.0) if hp_pct > 0.25 else Color(0.9, 0.1, 0.1))

	# Status icons (tiny colored dots)
	var sx = 0
	for sid in unit.statuses.keys().slice(0, 4):
		var sd = DataManager._load_json("res://data/status_effects.json").get("status_effects", {}).get(sid, {})
		var sc = Color("#" + sd.get("color", "888888"))
		draw_circle(rect.position + Vector2(4 + sx * 8, 4), 3, sc)
		sx += 1

	# Momentum pip (small yellow bar below unit)
	if unit.is_player:
		var mom = 0.0
		# pulled from TurnManager if available
		var tm = get_tree().get_first_node_in_group("turn_manager")
		if tm: mom = float(tm.get_momentum(unit)) / 100.0
		if mom > 0:
			var mb = Rect2(rect.position + Vector2(2, rect.size.y - 13), Vector2((rect.size.x - 4) * mom, 4))
			draw_rect(mb, Color(1.0, 0.9, 0.1, 0.8))

func _draw_objects() -> void:
	if grid == null: return
	for pos in grid.objects_on_grid:
		var obj  = grid.objects_on_grid[pos]
		var rect = _tile_rect(pos)
		match obj.get("type", ""):
			"chest":
				draw_rect(rect.grow(-14), Color(0.8, 0.6, 0.1))
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(16, 30), "C",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
			"barrel", "crate":
				draw_rect(rect.grow(-16), Color(0.5, 0.35, 0.1))
			"trap":
				draw_circle(rect.get_center(), 6, Color(0.8, 0.2, 0.8, 0.5))

# ─────────────────────────────────────────────────────────────────────────────
# Coordinate helpers
# ─────────────────────────────────────────────────────────────────────────────

func _tile_rect(pos: Vector2i) -> Rect2:
	return Rect2(pos.x * TILE_W, pos.y * TILE_H, TILE_W, TILE_H)

func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	var local = to_local(screen_pos)
	return Vector2i(int(local.x / TILE_W), int(local.y / TILE_H))

func grid_to_screen_center(pos: Vector2i) -> Vector2:
	return to_global(Vector2(pos.x * TILE_W + TILE_W * 0.5, pos.y * TILE_H + TILE_H * 0.5))

func total_size() -> Vector2:
	if grid == null: return Vector2.ZERO
	return Vector2(grid.width * TILE_W, grid.height * TILE_H)
