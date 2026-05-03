extends CanvasLayer
## Story dialogue and cutscene handler.
## Dialogue data lives in res://data/dialogue/<scene_id>.json
## Format: array of { speaker, portrait, text, choices? }

signal dialogue_finished(scene_id: String)

@onready var panel:         PanelContainer = $Panel
@onready var speaker_label: Label          = $Panel/VBox/SpeakerLabel
@onready var text_label:    RichTextLabel  = $Panel/VBox/TextLabel
@onready var next_btn:      Button         = $Panel/VBox/NextBtn
@onready var choices_box:   VBoxContainer  = $Panel/VBox/ChoicesBox
@onready var portrait_rect: TextureRect    = $Panel/Portrait

var _scene_id:    String = ""
var _lines:       Array  = []
var _index:       int    = 0
var _typing:      bool   = false
var _full_text:   String = ""
var _tween:       Tween  = null

func _ready() -> void:
	panel.visible = false
	next_btn.pressed.connect(_on_next)
	EventBus.cutscene_started.connect(play_scene)

# ─────────────────────────────────────────────────────────────────────────────
# Play a scene by ID
# ─────────────────────────────────────────────────────────────────────────────

func play_scene(scene_id: String) -> void:
	_scene_id = scene_id
	var path   = "res://data/dialogue/%s.json" % scene_id
	if not FileAccess.file_exists(path):
		push_warning("DialogueSystem: no file for scene %s" % scene_id)
		dialogue_finished.emit(scene_id)
		return
	_lines  = JSON.parse_string(FileAccess.get_file_as_string(path))
	_index  = 0
	panel.visible = true
	_show_line()

func _show_line() -> void:
	if _index >= _lines.size():
		_finish()
		return
	var line = _lines[_index]
	speaker_label.text = line.get("speaker", "")
	_full_text         = line.get("text", "")
	text_label.text    = ""

	# Build choices if present
	for child in choices_box.get_children():
		child.queue_free()
	var choices = line.get("choices", [])
	next_btn.visible    = choices.is_empty()
	choices_box.visible = not choices.is_empty()
	for choice in choices:
		var btn = Button.new()
		btn.text = choice.get("text", "...")
		btn.pressed.connect(_on_choice.bind(choice.get("next_index", _index + 1)))
		choices_box.add_child(btn)

	# Typewriter effect
	_typing = true
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_visible_chars, 0, _full_text.length(), _full_text.length() * 0.03)
	_tween.tween_callback(func(): _typing = false)

func _set_visible_chars(n: int) -> void:
	text_label.text = _full_text.left(n)

# ─────────────────────────────────────────────────────────────────────────────
# Input
# ─────────────────────────────────────────────────────────────────────────────

func _on_next() -> void:
	if _typing:
		# Skip typewriter
		if _tween: _tween.kill()
		text_label.text = _full_text
		_typing = false
	else:
		_index += 1
		_show_line()

func _on_choice(next_index: int) -> void:
	_index = next_index
	_show_line()

func _input(event: InputEvent) -> void:
	if not panel.visible: return
	if event is InputEventScreenTouch and event.pressed:
		_on_next()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_next()

# ─────────────────────────────────────────────────────────────────────────────

func _finish() -> void:
	panel.visible = false
	EventBus.cutscene_ended.emit(_scene_id)
	dialogue_finished.emit(_scene_id)
