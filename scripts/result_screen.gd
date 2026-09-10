# 本局结算界面：根据 RunState 展示通关或失败结果，并提供重开与返回主菜单入口。
extends Control

const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")

@onready var title_label: Label = %TitleLabel
@onready var detail_label: Label = %DetailLabel
@onready var summary_label: Label = %SummaryLabel
@onready var new_run_button: Button = $Margin/Layout/NewRunButton

var run_state: Node
var _is_scene_transitioning := false


# 正式流程读取全局本局状态；独立场景验收时创建局部失败状态，避免空引用。
func _ready() -> void:
	run_state = get_node_or_null("/root/RunState")
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
		run_state.mark_run_failed()
	refresh_ui()


# 通关与失败共享统计布局，但使用清楚不同的标题、说明和主题色。
func refresh_ui() -> void:
	var completed: bool = run_state.run_status == run_state.RunStatus.COMPLETED
	title_label.text = "三章通关！" if completed else "本局结束"
	detail_label.text = (
		"你击败了第三章 Boss，完成了本次守门挑战。"
		if completed
		else "球门失守了，但下一局会从完整的初始状态重新开始。"
	)
	title_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.84, 0.28) if completed else Color(1.0, 0.46, 0.4)
	)
	summary_label.text = "到达第 %d 章\n战斗胜利 %d 场\n牌库 %d 张　战利品 %d 件" % [
		run_state.chapter,
		run_state.battles_won,
		run_state.deck_card_ids.size(),
		run_state.owned_item_ids.size(),
	]


# 从结算页重开必须彻底覆盖上一局数据，再进入第一章新地图。
func _on_new_run_pressed() -> void:
	if _is_scene_transitioning:
		return
	_is_scene_transitioning = true
	new_run_button.disabled = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	run_state.start_new_run(rng.randi())
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null:
		save_service.save_game(run_state)
	# 新局地图在主曲恢复后才加载，维持所有地图入口一致的音频过场。
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		await bgm_service.transition_to_main_bgm()
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 返回主菜单时保留刚结束的摘要状态，直到玩家主动开始下一局。
func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# 结算页没有可恢复的临时操作，移动端返回键等同返回主菜单。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_main_menu_pressed()
