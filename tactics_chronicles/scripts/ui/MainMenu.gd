extends Control
## Main menu: New Game, Continue, Settings, Quit.
## Sub-screens (SaveSelect) are instantiated as needed and removed via queue_free.

const SAVE_SELECT_SCENE = preload("res://scenes/SaveSelect.tscn")

@onready var new_game_btn:  Button  = $Center/VBox/NewGameBtn
@onready var continue_btn:  Button  = $Center/VBox/ContinueBtn
@onready var settings_btn:  Button  = $Center/VBox/SettingsBtn
@onready var quit_btn:      Button  = $Center/VBox/QuitBtn

func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)
	_check_saves()

func _check_saves() -> void:
	continue_btn.disabled = true
	for i in SaveManager.MAX_SLOTS:
		if SaveManager.slot_exists(i):
			continue_btn.disabled = false
			break

# -- Sub-screens ---------------------------------------------------------------

func _open_save_select(mode: int, on_confirm: Callable) -> void:
	var canvas = SAVE_SELECT_SCENE.instantiate()
	var ss: SaveSelect = canvas.get_node("Root")
	ss.mode = mode
	ss.slot_confirmed.connect(func(slot):
		canvas.queue_free()
		on_confirm.call(slot))
	ss.cancelled.connect(func(): canvas.queue_free())
	add_child(canvas)

# -- Buttons -------------------------------------------------------------------

func _on_new_game() -> void:
	_open_save_select(SaveSelect.Mode.NEW_GAME, _start_new_game)

func _on_continue() -> void:
	_open_save_select(SaveSelect.Mode.LOAD, _load_game)

func _on_settings() -> void:
	EventBus.menu_opened.emit("settings")

func _on_quit() -> void:
	get_tree().quit()

# -- Game start ----------------------------------------------------------------

func _start_new_game(slot: int) -> void:
	_init_new_game_state()
	SaveManager.save(slot)
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _load_game(slot: int) -> void:
	if SaveManager.load_save(slot):
		get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _init_new_game_state() -> void:
	GameState.current_chapter   = "ch01"
	GameState.current_node      = "node_ch01_01"
	GameState.party             = _create_starter_party()
	GameState.gil               = 500
	GameState.inventory         = { "potion": 3, "ether": 1 }
	GameState.unlocked_classes  = ["soldier", "arcanist"]
	GameState.completed_battles = []
	GameState.story_flags       = {}

func _create_starter_party() -> Array:
	var warrior = {
		"unit_id": "pc_01", "unit_name": "Aric",
		"class_id": "soldier", "level": 1,
		"base_hp": 90, "base_mp": 30, "base_atk": 12, "base_matk": 6,
		"base_def": 7, "base_mdef": 4, "base_spd": 5, "base_move": 4, "base_jump": 3,
		"equipment": { "weapon": "iron_sword", "armor": "iron_plate", "accessory": "" },
		"unlocked_skills": ["dual_strike", "war_cry", "guard", "hp_up"],
		"equipped": {
			"active":   ["dual_strike", "war_cry"],
			"reaction": "guard", "supports": ["hp_up"], "movement": ""
		},
		"exp": 0, "job_level": 1, "job_exp": 0, "hp": 90, "mp": 30
	}
	var mage = {
		"unit_id": "pc_02", "unit_name": "Lyra",
		"class_id": "arcanist", "level": 1,
		"base_hp": 60, "base_mp": 60, "base_atk": 5, "base_matk": 14,
		"base_def": 3, "base_mdef": 7, "base_spd": 6, "base_move": 4, "base_jump": 3,
		"equipment": { "weapon": "pine_rod", "armor": "linen_robe", "accessory": "" },
		"unlocked_skills": ["arcane_bolt", "cantrip", "mana_veil", "mp_up"],
		"equipped": {
			"active":   ["arcane_bolt", "cantrip"],
			"reaction": "mana_veil", "supports": ["mp_up"], "movement": ""
		},
		"exp": 0, "job_level": 1, "job_exp": 0, "hp": 60, "mp": 60
	}
	return [warrior, mage]
