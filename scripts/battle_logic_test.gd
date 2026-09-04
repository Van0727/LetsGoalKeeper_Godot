extends Control

const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const SPORTS_DRINK := preload("res://data/cards/card_sports_drink.tres")
const TOWEL := preload("res://data/cards/card_towel.tres")

@onready var controller := %BattleController
@onready var player_status: Label = %PlayerStatus
@onready var enemy_status: Label = %EnemyStatus
@onready var phase_label: Label = %PhaseLabel
@onready var battle_log: TextEdit = %BattleLog
@onready var action_buttons: GridContainer = %ActionButtons


func _ready() -> void:
	controller.log_added.connect(_on_log_added)
	controller.state_changed.connect(_refresh_status)
	controller.battle_finished.connect(_on_battle_finished)
	controller.setup()


func _on_attack_pressed() -> void:
	controller.play_card(STRAIGHT_SHOT)


func _on_guard_pressed() -> void:
	controller.play_card(GLOVES)


func _on_heal_pressed() -> void:
	controller.play_card(SPORTS_DRINK)


func _on_energy_pressed() -> void:
	controller.play_card(TOWEL)


func _on_end_turn_pressed() -> void:
	controller.end_player_turn()


func _on_reset_pressed() -> void:
	battle_log.clear()
	_set_action_buttons_disabled(false)
	controller.setup()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_log_added(message: String) -> void:
	battle_log.text += message + "\n"
	battle_log.scroll_vertical = battle_log.get_line_count()


func _refresh_status() -> void:
	player_status.text = "玩家  HP %d/%d  护盾 %d  能量 %d/%d" % [
		controller.player.health,
		controller.player.max_health,
		controller.player.shield,
		controller.player.energy,
		controller.player.max_energy,
	]
	enemy_status.text = "企鹅  HP %d/%d  护盾 %d" % [
		controller.enemy.health,
		controller.enemy.max_health,
		controller.enemy.shield,
	]
	phase_label.text = "回合 %d · %s · 意图 %d" % [
		controller.turn_number,
		controller.get_phase_text(),
		controller.enemy_intent_damage,
	]


func _on_battle_finished(_victory: bool) -> void:
	_set_action_buttons_disabled(true)


func _set_action_buttons_disabled(disabled: bool) -> void:
	for child in action_buttons.get_children():
		if child is Button:
			child.disabled = disabled
