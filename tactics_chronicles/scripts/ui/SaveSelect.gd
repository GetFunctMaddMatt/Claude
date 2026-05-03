class_name SaveSelect
extends Control
## Save slot selection screen — used for both New Game (pick slot) and Continue (pick save).

enum Mode { NEW_GAME, LOAD }

signal slot_confirmed(slot: int)
signal cancelled()

@onready var title_label: Label        = $VBox/TitleLabel
@onready var slots_vbox:  VBoxContainer = $VBox/SlotsVBox
@onready var cancel_btn:  Button        = $VBox/CancelBtn

var _mode: Mode = Mode.LOAD

func _ready() -> void:
	cancel_btn.pressed.connect(func(): cancelled.emit(); hide())
	visible = false

func open_for_new_game() -> void:
	_mode = Mode.NEW_GAME
	title_label.text = "Select Save Slot"
	_build_slots()
	show()

func open_for_load() -> void:
	_mode = Mode.LOAD
	title_label.text = "Load Game"
	_build_slots()
	show()

func _build_slots() -> void:
	for child in slots_vbox.get_children():
		child.queue_free()

	for i in SaveManager.MAX_SLOTS:
		if i == 0:
			continue   # slot 0 = autosave, not shown to player
		var info = SaveManager.get_slot_info(i)
		var btn  = Button.new()

		if _mode == Mode.LOAD:
			if not info.get("exists", false):
				btn.disabled = true
				btn.text = "Slot %d — Empty" % i
			else:
				var ts  = info.get("timestamp", 0)
				var dt  = Time.get_datetime_string_from_unix_time(int(ts))
				btn.text = "Slot %d — %s  (%s)" % [i, info.get("chapter", "?"), dt]
		else:
			if info.get("exists", false):
				btn.text = "Slot %d — Overwrite save" % i
			else:
				btn.text = "Slot %d — Empty" % i

		btn.pressed.connect(_on_slot_pressed.bind(i))
		slots_vbox.add_child(btn)

func _on_slot_pressed(slot: int) -> void:
	slot_confirmed.emit(slot)
	hide()
