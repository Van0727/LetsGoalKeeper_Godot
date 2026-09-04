# 战斗逻辑人工测试场景：通过按钮执行已迁移卡牌并展示完整结算日志。
extends Control

const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const BANANA_SHOT := preload("res://data/cards/card_banana_shot.tres")
const LOB_SHOT := preload("res://data/cards/card_lob_shot.tres")
const BARRAGE_SHOT := preload("res://data/cards/card_barrage_shot.tres")
const ATTACK_AND_DEFEND := preload("res://data/cards/card_attack_and_defend.tres")
const EXPLOSION_BALL := preload("res://data/cards/card_explosion_ball.tres")
const ENERGY_SHOT := preload("res://data/cards/card_energy_shot.tres")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const SPORTS_DRINK := preload("res://data/cards/card_sports_drink.tres")
const TOWEL := preload("res://data/cards/card_towel.tres")

@onready var controller := %BattleController
@onready var player_status: Label = %PlayerStatus
@onready var enemy_status: Label = %EnemyStatus
@onready var phase_label: Label = %PhaseLabel
@onready var battle_log: TextEdit = %BattleLog
@onready var action_buttons: GridContainer = %ActionButtons


# 连接控制器信号并创建一场固定种子的测试战斗。
func _ready() -> void:
	controller.log_added.connect(_on_log_added)
	controller.state_changed.connect(_refresh_status)
	controller.battle_finished.connect(_on_battle_finished)
	controller.setup()


# 以下按钮回调分别打出对应卡牌，统一复用 BattleController 的费用和效果流程。
func _on_attack_pressed() -> void:
	controller.play_card(STRAIGHT_SHOT)


func _on_banana_pressed() -> void:
	controller.play_card(BANANA_SHOT)


func _on_lob_pressed() -> void:
	controller.play_card(LOB_SHOT)


func _on_barrage_pressed() -> void:
	controller.play_card(BARRAGE_SHOT)


func _on_attack_and_defend_pressed() -> void:
	controller.play_card(ATTACK_AND_DEFEND)


func _on_explosion_ball_pressed() -> void:
	controller.play_card(EXPLOSION_BALL)


func _on_energy_shot_pressed() -> void:
	controller.play_card(ENERGY_SHOT)


func _on_guard_pressed() -> void:
	controller.play_card(GLOVES)


func _on_heal_pressed() -> void:
	controller.play_card(SPORTS_DRINK)


func _on_energy_pressed() -> void:
	controller.play_card(TOWEL)


# 结束当前玩家回合并触发敌人行动。
func _on_end_turn_pressed() -> void:
	controller.end_player_turn()


# 清空日志并重新初始化战斗。
func _on_reset_pressed() -> void:
	battle_log.clear()
	_set_action_buttons_disabled(false)
	controller.setup()


# 返回迁移测试版主菜单。
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# 追加战斗日志并保持视图滚动到底部。
func _on_log_added(message: String) -> void:
	battle_log.text += message + "\n"
	battle_log.scroll_vertical = battle_log.get_line_count()


# 根据控制器运行状态刷新双方数值、阶段和敌人意图。
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


# 战斗结束后锁定所有行动按钮，防止重复结算。
func _on_battle_finished(_victory: bool) -> void:
	_set_action_buttons_disabled(true)


# 批量切换行动区按钮的可用状态。
func _set_action_buttons_disabled(disabled: bool) -> void:
	for child in action_buttons.get_children():
		if child is Button:
			child.disabled = disabled
