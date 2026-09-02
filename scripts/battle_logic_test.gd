extends Control

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
	controller.player_attack()


func _on_guard_pressed() -> void:
	controller.player_guard()


func _on_heal_pressed() -> void:
	controller.player_heal()


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
	player_status.text = "玩家  HP %d/%d  护盾 %d" % [
		controller.player.health,
		controller.player.max_health,
		controller.player.shield,
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
