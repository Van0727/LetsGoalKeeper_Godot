# 迁移测试版主菜单：开始或继续内存中的本局，并保留各模块回归测试入口。
extends Control

const CARD_DRAG_TEST_SCENE := preload("res://scenes/card_drag_test.tscn")
const CHARACTER_FEEDBACK_TEST_SCENE := preload("res://scenes/character_feedback_test.tscn")
const BATTLE_LOGIC_TEST_SCENE := preload("res://scenes/battle_logic_test.tscn")
const DECK_LOGIC_TEST_SCENE := preload("res://scenes/deck_logic_test.tscn")

@onready var status_label: Label = %StatusLabel
@onready var continue_button: Button = %ContinueButton


# 主菜单每次进入都根据本局状态刷新提示；阶段 9 接入存档后仍复用同一入口。
func _ready() -> void:
	refresh_run_status()


# 进行中的本局允许继续，失败与通关状态只保留结果提示并要求开始新游戏。
func refresh_run_status() -> void:
	var run_state := get_node("/root/RunState")
	continue_button.disabled = run_state.run_status != run_state.RunStatus.ACTIVE or run_state.map_state == null
	match run_state.run_status:
		run_state.RunStatus.ACTIVE:
			status_label.text = "进行中：第 %d 章，已胜 %d 场" % [run_state.chapter, run_state.battles_won]
		run_state.RunStatus.FAILED:
			status_label.text = "上一局已失败，可以开始新的挑战"
		run_state.RunStatus.COMPLETED:
			status_label.text = "三章已通关，可以开始新的挑战"
		_:
			status_label.text = "准备开始新的守门挑战"


# 开始新游戏：使用随机种子彻底重置本局并进入第 1 章路线地图。
func _on_start_button_pressed() -> void:
	status_label.text = "正在开始新的一局……"
	var run_state := get_node("/root/RunState")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	run_state.start_new_run(rng.randi())
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 阶段 8 先继续当前进程内的 RunState；跨进程恢复由阶段 9 存档负责。
func _on_continue_button_pressed() -> void:
	var run_state := get_node("/root/RunState")
	if run_state.run_status != run_state.RunStatus.ACTIVE or run_state.map_state == null:
		refresh_run_status()
		return
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
