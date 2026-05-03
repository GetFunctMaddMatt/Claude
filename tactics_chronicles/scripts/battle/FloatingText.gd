class_name FloatingText
extends Node2D
## Spawns floating labels for damage, healing, misses, and status names.
## Call FloatingText.spawn() statically — no scene required.

const FONT_SIZE_NORMAL: int = 18
const FONT_SIZE_LARGE:  int = 26   # crits, KO
const RISE_HEIGHT:      float = 64.0
const DURATION:         float = 0.9

# ─────────────────────────────────────────────────────────────────────────────
# Static factory — attach to any node that owns a canvas layer
# ─────────────────────────────────────────────────────────────────────────────

static func spawn(parent: Node, world_pos: Vector2, text: String,
		color: Color, large: bool = false) -> void:
	var lbl            = Label.new()
	lbl.text           = text
	lbl.position       = world_pos - Vector2(20, 20)
	lbl.modulate       = color
	lbl.z_index        = 100
	lbl.add_theme_font_size_override("font_size",
		FONT_SIZE_LARGE if large else FONT_SIZE_NORMAL)
	parent.add_child(lbl)

	var tw = lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - RISE_HEIGHT, DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, DURATION) \
		.set_delay(DURATION * 0.4)
	tw.chain().tween_callback(lbl.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Convenience helpers — call these from BattleEngine or GridRenderer
# ─────────────────────────────────────────────────────────────────────────────

static func damage(parent: Node, world_pos: Vector2,
		amount: int, element: String, is_crit: bool) -> void:
	var color = _element_color(element)
	var text  = "-%d%s" % [amount, " CRIT!" if is_crit else ""]
	spawn(parent, world_pos, text, color, is_crit)

static func heal(parent: Node, world_pos: Vector2, amount: int) -> void:
	spawn(parent, world_pos, "+%d" % amount, Color(0.2, 1.0, 0.4))

static func miss(parent: Node, world_pos: Vector2) -> void:
	spawn(parent, world_pos, "MISS", Color(0.8, 0.8, 0.8))

static func status(parent: Node, world_pos: Vector2, status_id: String) -> void:
	spawn(parent, world_pos, status_id.capitalize(), Color(0.9, 0.7, 1.0))

static func ko(parent: Node, world_pos: Vector2) -> void:
	spawn(parent, world_pos, "KO!", Color(1.0, 0.2, 0.2), true)

static func level_up(parent: Node, world_pos: Vector2) -> void:
	spawn(parent, world_pos, "LEVEL UP!", Color(1.0, 0.95, 0.2), true)

# ─────────────────────────────────────────────────────────────────────────────

static func _element_color(element: String) -> Color:
	match element:
		"fire":      return Color(1.0, 0.45, 0.1)
		"ice":       return Color(0.5, 0.85, 1.0)
		"lightning": return Color(1.0, 0.95, 0.2)
		"water":     return Color(0.2, 0.6, 1.0)
		"earth":     return Color(0.7, 0.5, 0.2)
		"wind":      return Color(0.5, 1.0, 0.5)
		"holy":      return Color(1.0, 1.0, 0.6)
		"dark":      return Color(0.6, 0.2, 0.8)
		_:           return Color(1.0, 0.95, 0.8)
