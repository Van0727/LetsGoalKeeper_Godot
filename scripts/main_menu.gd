# 迁移测试版主菜单：集中导航到当前已完成的各个功能测试场景。
extends Control

const CARD_DRAG_TEST_SCENE := preload("res://scenes/card_drag_test.tscn")
const CHARACTER_FEEDBACK_TEST_SCENE := preload("res://scenes/character_feedback_test.tscn")
const BATTLE_LOGIC_TEST_SCENE := preload("res://scenes/battle_logic_test.tscn")
const DECK_LOGIC_TEST_SCENE := preload("res://scenes/deck_logic_test.tscn")

@onready var status_label: Label = %StatusLabel


# 开始新游戏：使用随机种子彻底重置本局并进入第 1 章路线地图。
func _on_start_button_pressed() -> void:
	status_label.text = "正在开始新的一局……"
	var run_state := get_node("/root/RunState")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	run_state.start_new_run(rng.randi())
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 保留阶段 2 的牌堆逻辑测试入口，方便后续回归抽弃牌规则。
func _on_deck_logic_button_pressed() -> void:
	status_label.text = "正在进入牌堆逻辑测试……"
	get_tree().change_scene_to_packed(DECK_LOGIC_TEST_SCENE)


# 进入战斗结算与卡牌效果测试。
func _on_battle_logic_button_pressed() -> void:
	status_label.text = "正在进入战斗逻辑测试……"
	get_tree().change_scene_to_packed(BATTLE_LOGIC_TEST_SCENE)


# 进入角色受击、治疗和护盾反馈测试。
func _on_character_feedback_button_pressed() -> void:
	status_label.text = "正在进入角色反馈测试……"
	get_tree().change_scene_to_packed(CHARACTER_FEEDBACK_TEST_SCENE)


# 进入鼠标与触摸统一拖拽测试。
func _on_card_drag_button_pressed() -> void:
	status_label.text = "正在进入卡牌拖拽测试……"
	get_tree().change_scene_to_packed(CARD_DRAG_TEST_SCENE)
