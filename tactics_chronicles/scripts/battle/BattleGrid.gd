class_name BattleGrid
extends Node2D
## Owns the tile map, unit placement, pathfinding, LOS, and cover calculations.

var width:  int = 0
var height: int = 0
var tiles:  Array = []              # [row][col] -> tile dict
var units_on_grid:   Dictionary = {} # Vector2i -> Unit
var objects_on_grid: Dictionary = {} # Vector2i -> object dict

# -----------------------------------------------------------------------------
# Map loading
# -----------------------------------------------------------------------------

func load_map(map_data: Dictionary) -> void:
	width  = map_data.get("width",  10)
	height = map_data.get("height", 8)
	tiles  = map_data.get("tiles",  [])
	units_on_grid.clear()
	objects_on_grid.clear()
	for obj in map_data.get("objects", []):
		var pos = Vector2i(obj["pos"][0], obj["pos"][1])
		objects_on_grid[pos] = obj

# -----------------------------------------------------------------------------
# Tile queries
# -----------------------------------------------------------------------------

func get_tile(pos: Vector2i) -> Dictionary:
	if not is_in_bounds(pos):
		return {}
	return tiles[pos.y][pos.x]

func get_height(pos: Vector2i) -> int:
	var t = get_tile(pos)
	if t.is_empty():
		return 0
	var terrain = DataManager.get_terrain(t.get("t", "grass"))
	return t.get("h", terrain.get("height_default", 0))

func get_move_cost(pos: Vector2i) -> int:
	var t = get_tile(pos)
	if t.is_empty():
		return 99
	return DataManager.get_terrain(t.get("t", "grass")).get("move_cost", 1)

func is_impassable(pos: Vector2i) -> bool:
	var t = get_tile(pos)
	if t.is_empty():
		return true
	return DataManager.get_terrain(t.get("t", "grass")).get("impassable", false)

func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func is_occupied(pos: Vector2i) -> bool:
	return units_on_grid.has(pos)

func is_walkable(pos: Vector2i, unit: Unit) -> bool:
	if not is_in_bounds(pos) or is_impassable(pos):
		return false
	if is_occupied(pos):
		return false
	var h_diff = abs(get_height(pos) - get_height(unit.grid_pos))
	return h_diff <= unit.jump

# -----------------------------------------------------------------------------
# Unit management
# -----------------------------------------------------------------------------

func place_unit(unit: Unit, pos: Vector2i) -> void:
	units_on_grid[pos] = unit
	unit.grid_pos = pos

func move_unit(unit: Unit, path: Array) -> void:
	units_on_grid.erase(unit.grid_pos)
	var prev = unit.grid_pos
	for pos in path:
		unit.grid_pos = pos
		_apply_terrain_entry(unit, pos)
	units_on_grid[unit.grid_pos] = unit
	EventBus.unit_moved.emit(unit, prev, unit.grid_pos)

func remove_unit(unit: Unit) -> void:
	units_on_grid.erase(unit.grid_pos)

func get_unit_at(pos: Vector2i) -> Unit:
	return units_on_grid.get(pos, null)

func _apply_terrain_entry(unit: Unit, pos: Vector2i) -> void:
	var t    = get_tile(pos)
	if t.is_empty(): return
	var tdef = DataManager.get_terrain(t.get("t", "grass"))
	var hazard = tdef.get("hazard", null)
	if hazard == "poison":   unit.apply_status("poison", 4)
	elif hazard == "lava":   unit.take_damage(30, "fire", null)

# -----------------------------------------------------------------------------
# Pathfinding (Dijkstra)
# -----------------------------------------------------------------------------

func get_movement_tiles(unit: Unit) -> Array:
	var budget = unit.move
	var dist:   Dictionary = { unit.grid_pos: 0 }
	var queue:  Array      = [unit.grid_pos]
	var result: Array      = []
	while not queue.is_empty():
		queue.sort_custom(func(a, b): return dist[a] < dist[b])
		var cur = queue.pop_front()
		result.append(cur)
		for nb in _neighbors(cur):
			if is_impassable(nb): continue
			var h_diff = abs(get_height(nb) - get_height(cur))
			if h_diff > unit.jump: continue
			var cost = dist[cur] + get_move_cost(nb)
			if cost <= budget and (not dist.has(nb) or dist[nb] > cost):
				dist[nb] = cost
				queue.append(nb)
	result.erase(unit.grid_pos)
	return result

func find_path(from: Vector2i, to: Vector2i, unit: Unit) -> Array:
	# A* -- returns tile positions to step through (not including 'from')
	var open:   Dictionary = { from: 0.0 }
	var came:   Dictionary = {}
	var g:      Dictionary = { from: 0.0 }
	while not open.is_empty():
		var cur = open.keys().reduce(func(a, b): return a if open[a] < open[b] else b)
		if cur == to:
			return _reconstruct_path(came, cur)
		open.erase(cur)
		for nb in _neighbors(cur):
			if is_impassable(nb): continue
			var h_diff = abs(get_height(nb) - get_height(cur))
			if h_diff > unit.jump: continue
			var ng = g[cur] + get_move_cost(nb)
			if not g.has(nb) or ng < g[nb]:
				g[nb]    = ng
				open[nb] = ng + _heuristic(nb, to)
				came[nb] = cur
	return []

func _reconstruct_path(came: Dictionary, cur: Vector2i) -> Array:
	var path = [cur]
	while came.has(cur):
		cur = came[cur]
		path.push_front(cur)
	path.pop_front()  # remove 'from'
	return path

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return float(abs(a.x - b.x) + abs(a.y - b.y))

func _neighbors(pos: Vector2i) -> Array:
	return [
		Vector2i(pos.x+1, pos.y), Vector2i(pos.x-1, pos.y),
		Vector2i(pos.x, pos.y+1), Vector2i(pos.x, pos.y-1)
	].filter(func(p): return is_in_bounds(p))

# -----------------------------------------------------------------------------
# Skill targeting -- returns affected tile positions for a pattern
# -----------------------------------------------------------------------------

func get_tiles_in_pattern(origin: Vector2i, pattern: String, skill_range: int,
		aoe_radius: int, facing: String) -> Array:
	match pattern:
		"single":           return _single_target_tiles(origin, skill_range)
		"self":             return [origin]
		"all_enemies", "all_allies": return units_on_grid.keys()
		"circle", "circle_enemy", "circle_ally":
			return _circle_tiles(origin, aoe_radius)
		"explosion_1":      return _single_target_tiles(origin, skill_range)  # explosion resolved at impact
		"explosion_2":      return _single_target_tiles(origin, skill_range)
		"line_pierce_all", "line_pierce_enemy", "line_pierce_ally":
			return _line_tiles(origin, facing, skill_range)
		"line_2":           return _line_tiles(origin, facing, 2)
		"line_3":           return _line_tiles(origin, facing, 3)
		"line_4":           return _line_tiles(origin, facing, 4)
		"cone":             return _cone_tiles(origin, facing, skill_range)
		_:                  return []

func _single_target_tiles(origin: Vector2i, rng: int) -> Array:
	var result = []
	for x in range(origin.x - rng, origin.x + rng + 1):
		for y in range(origin.y - rng, origin.y + rng + 1):
			var p = Vector2i(x, y)
			if is_in_bounds(p) and _manhattan(origin, p) <= rng:
				result.append(p)
	return result

func _circle_tiles(center: Vector2i, radius: int) -> Array:
	var result = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var p = Vector2i(x, y)
			if is_in_bounds(p) and _manhattan(center, p) <= radius:
				result.append(p)
	return result

func _line_tiles(origin: Vector2i, facing: String, length: int) -> Array:
	var dir = _facing_to_dir(facing)
	var result = []
	for i in range(1, length + 1):
		var p = origin + dir * i
		if not is_in_bounds(p): break
		result.append(p)
	return result

func _cone_tiles(origin: Vector2i, facing: String, rng: int) -> Array:
	# Simple cone: all tiles within range in a 90-degree arc ahead
	var result = []
	for p in _single_target_tiles(origin, rng):
		if p == origin: continue
		var d = p - origin
		var f = _facing_to_dir(facing)
		if d.dot(f) > 0:
			result.append(p)
	return result

func _facing_to_dir(facing: String) -> Vector2i:
	match facing:
		"north": return Vector2i(0, -1)
		"south": return Vector2i(0,  1)
		"east":  return Vector2i(1,  0)
		"west":  return Vector2i(-1, 0)
	return Vector2i(0, 1)

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

# -----------------------------------------------------------------------------
# Line of sight
# -----------------------------------------------------------------------------

func check_los(from: Vector2i, to: Vector2i) -> bool:
	var from_h = get_height(from)
	var points = _bresenham(from, to)
	for i in range(1, points.size() - 1):
		var p    = points[i]
		var t    = get_tile(p)
		if t.is_empty(): continue
		var tdef = DataManager.get_terrain(t.get("t", "grass"))
		if tdef.get("blocks_los", false) and get_height(p) >= from_h:
			return false
	return true

func _bresenham(a: Vector2i, b: Vector2i) -> Array:
	var pts = []
	var dx = abs(b.x - a.x);  var dy = abs(b.y - a.y)
	var sx = 1 if a.x < b.x else -1
	var sy = 1 if a.y < b.y else -1
	var err = dx - dy
	var x = a.x;  var y = a.y
	while true:
		pts.append(Vector2i(x, y))
		if x == b.x and y == b.y: break
		var e2 = 2 * err
		if e2 > -dy: err -= dy; x += sx
		if e2 < dx:  err += dx; y += sy
	return pts

# -----------------------------------------------------------------------------
# Height & cover helpers (used by ActionResolver)
# -----------------------------------------------------------------------------

func height_diff(attacker_pos: Vector2i, target_pos: Vector2i) -> int:
	return get_height(attacker_pos) - get_height(target_pos)

func get_cover_bonus(target_pos: Vector2i) -> int:
	var t    = get_tile(target_pos)
	if t.is_empty(): return 0
	var tdef = DataManager.get_terrain(t.get("t", "grass"))
	return tdef.get("cover", 0)

func is_concealed(pos: Vector2i) -> bool:
	var t    = get_tile(pos)
	if t.is_empty(): return false
	return DataManager.get_terrain(t.get("t", "grass")).get("conceal", false)
