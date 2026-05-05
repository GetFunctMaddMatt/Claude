class_name SaveSelect
extends Control
## Standalone save slot selection screen.
## Instantiate via MainMenu, mode set externally before adding to tree.

enum Mode { NEW_GAME, LOAD }

signal slot_confirmed(slot: int)
signal cancelled()

var mode: Mode = Mode.LOAD

@onready var title_label: Label         = $Center/VBox/TitleLabel
@onready var slots_vbox:  VBoxContainer = $Center/VBox/SlotsVBox
@onready var cancel_btn:  Button        = $Center/VBox/CancelBtn

func _ready() -> void:
	cancel_btn.pressed.connect(_on_cancel)
	title_label.text = "Select Save Slot" if mode == Mode.NEW_GAME else "Load Game"
	_build_slots()

func _on_cancel() -> void:
	cancelled.emit()

func _build_slots() -> void:
	for child in slots_vbox.get_children():
		child.queue_free()

	for i in SaveManager.MAX_SLOTS:
		if i == 0:
			continue   # slot 0 = autosave, hidden from player
		var info = SaveManager.get_slot_info(i)
		var btn  = Button.new()
		btn.custom_minimum_size = Vector2(320, 56)

		if mode == Mode.LOAD:
			if not info.get("exists", false):
				btn.disabled = true
				btn.text = "Slot %d -- Empty" % i
			else:
				var ts = info.get("timestamp", 0)
				var dt = Time.get_datetime_string_from_unix_time(int(ts))
				btn.text = "Slot %d -- %s  (%s)" % [i, info.get("chapter", "?"), dt]
		else:
			if info.get("exists", false):
				btn.text = "Slot %d -- Overwrite save" % i
			else:
				btn.text = "Slot %d -- New game" % i

		btn.pressed.connect(_on_slot_pressed.bind(i))
		slots_vbox.add_child(btn)

func _on_slot_pressed(slot: int) -> void:
	slot_confirmed.emit(slot)
