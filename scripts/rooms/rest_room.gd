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


# 治疗机会写入当前房间运行状态；重新加载场景也不能重复治疗。
func _on_heal_pressed() -> void:
	if run_state == null or heal_button.disabled:
		return
	var healed = run_state.use_current_rest(REST_HEAL_AMOUNT)
	var current_room: Dictionary = run_state.get_current_room()
	heal_button.disabled = current_room.is_empty() or current_room.get("rest_used", false)
	if healed > 0:
		status_label.text = "已恢复 %d 点生命" % healed
	else:
		status_label.text = "生命已满，没有需要恢复的生命"
	_refresh_labels()


# 继续前进时才提交休息房完成状态并解锁下一层。
func _on_continue_pressed() -> void:
	run_state.complete_current_room()
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 返回主菜单时取消尚未完成的休息房，不提前推进路线。
func _on_back_pressed() -> void:
	run_state.cancel_current_room()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# 刷新生命与治疗按钮提示文字。
func _refresh_labels() -> void:
	run_label.text = "生命 %d/%d" % [run_state.player_hp, run_state.max_hp]
	heal_button.text = "治疗 %d 点" % REST_HEAL_AMOUNT
	var current_room: Dictionary = run_state.get_current_room()
	heal_button.disabled = current_room.is_empty() or current_room.get("rest_used", false)
	if not current_room.is_empty() and current_room.get("rest_used", false):
		status_label.text = "本休息房已经使用过治疗"
