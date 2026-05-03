extends CanvasLayer
## Queued toast notifications — small banners that auto-dismiss.
## Also listens to EventBus and auto-displays relevant events.

const SHOW_DURATION: float = 2.2
const FADE_DURATION: float = 0.3

@onready var banner: PanelContainer = $Banner
@onready var label:  Label          = $Banner/Label

var _queue: Array   = []
var _busy:  bool    = false

func _ready() -> void:
	banner.visible = false
	EventBus.notification_requested.connect(_enqueue)
	EventBus.unit_ko.connect(func(u: Unit): _enqueue("%s was defeated!" % u.unit_name, Color(0.9, 0.3, 0.3)))
	EventBus.unit_status_applied.connect(func(u: Unit, sid: String):
		_enqueue("%s → %s" % [u.unit_name, sid.capitalize()], Color(0.8, 0.6, 1.0)))
	EventBus.job_level_up.connect(func(u: Unit, _cid, lv: int):
		_enqueue("%s reached Job Lv %d!" % [u.unit_name, lv], Color(1.0, 0.9, 0.2)))
	EventBus.gil_changed.connect(func(total: int, delta: int):
		if delta > 0: _enqueue("+%d Gil" % delta, Color(0.9, 0.8, 0.3)))

func _enqueue(text: String, color: Color = Color.WHITE) -> void:
	_queue.append({ "text": text, "color": color })
	if not _busy:
		_show_next()

func _show_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var entry = _queue.pop_front()
	label.text     = entry["text"]
	label.modulate = entry["color"]
	banner.modulate.a = 0.0
	banner.visible    = true

	var tw = create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, FADE_DURATION)
	tw.tween_interval(SHOW_DURATION)
	tw.tween_property(banner, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func():
		banner.visible = false
		_show_next()
	)
