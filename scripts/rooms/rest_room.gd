# 休息房界面：每间休息房允许治疗一次（20点），之后继续返回路线地图。
extends Control

const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const REST_HEAL_AMOUNT := 20

@onready var run_label: Label = %RunLabel
@onready var heal_button: Button = %HealButton
@onready var status_label: Label = %StatusLabel

var run_state: Node


# 绑定本局状态并刷新当前生命；独立场景测试没有 Autoload 时创建局部状态。
func _ready() -> void:
	run_state = get_node_or_null("/root/RunState")
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
	_refresh_labels()


# 治疗一次并禁用按钮；房间只进入一次，不允许第二次治疗。
func _on_heal_pressed() -> void:
	if run_state == null or heal_button.disabled:
		return
	var healed = run_state.heal_run(REST_HEAL_AMOUNT)
	heal_button.disabled = true
	if healed > 0:
		status_label.text = "已恢复 %d 点生命" % healed
	else:
		status_label.text = "生命已满，没有需要恢复的生命"
	_refresh_labels()


# 返回路线地图继续选择房间。
func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 返回主菜单放弃当前路线。
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# 刷新生命与治疗按钮提示文字。
func _refresh_labels() -> void:
	run_label.text = "生命 %d/%d" % [run_state.player_hp, run_state.max_hp]
	heal_button.text = "治疗 %d 点" % REST_HEAL_AMOUNT
