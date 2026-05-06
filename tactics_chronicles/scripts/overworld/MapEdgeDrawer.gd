extends Control
## Draws connection lines between campaign nodes on the overworld map.
## Added as a child of NodeMap by Overworld._build_node_map() so it renders
## behind the buttons. Call setup() to supply edge data, then queue_redraw().

var _edges: Array = []  # Array of {from: Vector2, to: Vector2, complete: bool}

func setup(edge_list: Array) -> void:
	_edges = edge_list
	queue_redraw()

func _draw() -> void:
	for edge in _edges:
		var color = Color(0.3, 0.8, 0.3, 0.75) if edge.get("complete", false) \
				else Color(0.55, 0.55, 0.55, 0.55)
		draw_line(edge["from"], edge["to"], color, 2.5, true)
		# Arrow head -- small filled triangle at the destination end
		var dir   = (edge["to"] - edge["from"]).normalized()
		var perp  = Vector2(-dir.y, dir.x)
		var tip   = edge["to"]
		var left  = tip - dir * 10.0 + perp * 5.0
		var right = tip - dir * 10.0 - perp * 5.0
		draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
