# 主菜单：开始新局或从持久化安全节点继续，并保留各模块回归测试入口。
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
	continue_button.disabled = (
		run_state.is_placeholder_run
		or run_state.run_status != run_state.RunStatus.ACTIVE
		or run_state.map_state == null
	)
	if run_state.is_placeholder_run:
		status_label.text = "准备开始新的守门挑战"
		return
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
	_record_diagnostic("new_run", {"seed": run_state.seed})
	_save_run()
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 继续按钮再次从磁盘恢复，确保入口不依赖当前进程中可能过期的临时状态。
func _on_continue_button_pressed() -> void:
	var run_state := get_node("/root/RunState")
	var save_service := get_node_or_null("/root/SaveService")
	if save_service == null or not save_service.load_game(run_state):
		refresh_run_status()
		return
	if run_state.run_status != run_state.RunStatus.ACTIVE or run_state.map_state == null:
		refresh_run_status()
		return
	# 安全节点决定恢复目标：胜利后直接领奖，已进入的房间回到对应内容，其他情况回地图。
	match run_state.resume_point:
		run_state.ResumePoint.BATTLE:
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
		run_state.ResumePoint.REWARD:
			get_tree().change_scene_to_file("res://scenes/reward_screen.tscn")
		run_state.ResumePoint.REST:
			get_tree().change_scene_to_file("res://scenes/rest_room.tscn")
		_:
			get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 新游戏建立完整地图后立即覆盖旧档，保证强制关闭也不会回到上一局。
func _save_run() -> void:
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null:
		save_service.save_game(get_node("/root/RunState"))


# 设置使用独立场景和独立配置，不改变当前本局或存档安全节点。
func _on_settings_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings_screen.tscn")


# 诊断文件只在玩家点击后生成，并把可提交给开发者的虚拟路径显示在主菜单。
func _on_export_diagnostics_pressed() -> void:
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics == null:
		status_label.text = "诊断服务不可用"
		return
	var exported_path: String = diagnostics.export_logs()
	status_label.text = (
		"诊断日志已导出：%s" % exported_path
		if not exported_path.is_empty()
		else "导出失败：%s" % diagnostics.last_error
	)


func _record_diagnostic(event_name: String, fields: Dictionary) -> void:
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("run", event_name, fields)


# 主菜单没有未提交进度，移动端返回键可直接退出；玩法场景则由暂停层二次确认。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


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
