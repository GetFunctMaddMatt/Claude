class_name CameraController
extends Camera2D
## Battle camera: pan by dragging, pinch-to-zoom, snap-to-unit helper.
## Clamps to grid bounds so you can't pan into empty void.

@export var min_zoom:   float = 0.4
@export var max_zoom:   float = 2.0
@export var pan_speed:  float = 1.0   # drag multiplier

var _grid_size:      Vector2  = Vector2.ZERO
var _dragging:       bool     = false
var _drag_start:     Vector2  = Vector2.ZERO
var _cam_start:      Vector2  = Vector2.ZERO
var _pinch_start_dist: float  = 0.0
var _pinch_start_zoom: float  = 1.0
var _touch_points:   Dictionary = {}   # finger_id -> position

func _ready() -> void:
	zoom = Vector2(1.0, 1.0)

func set_grid_bounds(grid_pixel_size: Vector2) -> void:
	_grid_size = grid_pixel_size

func _input(event: InputEvent) -> void:
	# ── Touch (mobile) ────────────────────────────────────────────────────────
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
		else:
			_touch_points.erase(event.index)
			_dragging = false

	if event is InputEventScreenDrag:
		_touch_points[event.index] = event.position
		if _touch_points.size() == 1:
			_handle_pan(event.relative)
		elif _touch_points.size() == 2:
			_handle_pinch()

	# ── Mouse (desktop / editor testing) ─────────────────────────────────────
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			if _dragging:
				_drag_start = event.position
				_cam_start  = position
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(0.1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-0.1)

	if event is InputEventMouseMotion and _dragging:
		var delta = event.position - _drag_start
		position  = _cam_start - delta / zoom.x
		_clamp_position()

# ─────────────────────────────────────────────────────────────────────────────
# Pan / zoom helpers
# ─────────────────────────────────────────────────────────────────────────────

func _handle_pan(relative: Vector2) -> void:
	position -= relative / zoom.x * pan_speed
	_clamp_position()

func _handle_pinch() -> void:
	var pts   = _touch_points.values()
	var dist  = pts[0].distance_to(pts[1])
	if _pinch_start_dist == 0.0:
		_pinch_start_dist = dist
		_pinch_start_zoom = zoom.x
		return
	var new_z = clampf(_pinch_start_zoom * (dist / _pinch_start_dist), min_zoom, max_zoom)
	zoom = Vector2(new_z, new_z)
	_clamp_position()

func _zoom_by(delta: float) -> void:
	var new_z = clampf(zoom.x + delta, min_zoom, max_zoom)
	zoom = Vector2(new_z, new_z)
	_clamp_position()

func _clamp_position() -> void:
	if _grid_size == Vector2.ZERO: return
	var vp     = get_viewport_rect().size / zoom.x
	var half   = vp * 0.5
	position.x = clampf(position.x, half.x, maxf(_grid_size.x - half.x, half.x))
	position.y = clampf(position.y, half.y, maxf(_grid_size.y - half.y, half.y))

# ─────────────────────────────────────────────────────────────────────────────
# Snap to unit (call after turn starts)
# ─────────────────────────────────────────────────────────────────────────────

func snap_to(world_pos: Vector2, animated: bool = true) -> void:
	if animated:
		var tween = create_tween()
		tween.tween_property(self, "position", world_pos, 0.25).set_trans(Tween.TRANS_QUAD)
	else:
		position = world_pos
	_clamp_position()
