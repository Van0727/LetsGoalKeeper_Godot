extends Control

const CARD_DRAG_TEST_SCENE := preload("res://scenes/card_drag_test.tscn")
const CHARACTER_FEEDBACK_TEST_SCENE := preload("res://scenes/character_feedback_test.tscn")
const BATTLE_LOGIC_TEST_SCENE := preload("res://scenes/battle_logic_test.tscn")
const DECK_LOGIC_TEST_SCENE := preload("res://scenes/deck_logic_test.tscn")

@onready var status_label: Label = %StatusLabel


func _on_start_button_pressed() -> void:
	status_label.text = "正在进入牌堆逻辑测试……"
	get_tree().change_scene_to_packed(DECK_LOGIC_TEST_SCENE)


func _on_battle_logic_button_pressed() -> void:
	status_label.text = "正在进入战斗逻辑测试……"
	get_tree().change_scene_to_packed(BATTLE_LOGIC_TEST_SCENE)


func _on_character_feedback_button_pressed() -> void:
	status_label.text = "正在进入角色反馈测试……"
	get_tree().change_scene_to_packed(CHARACTER_FEEDBACK_TEST_SCENE)


func _on_card_drag_button_pressed() -> void:
	status_label.text = "正在进入卡牌拖拽测试……"
	get_tree().change_scene_to_packed(CARD_DRAG_TEST_SCENE)
