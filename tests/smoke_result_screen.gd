# 阶段 8 结算界面冒烟测试：验证通关、失败摘要，以及新游戏对旧局状态的彻底覆盖。
extends SceneTree

const RESULT_SCENE := preload("res://scenes/result_screen.tscn")

var _failed := false


# 延迟运行，确保真实场景的唯一名称节点已完成绑定。
func _initialize() -> void:
	call_deferred("_run")


# 依次覆盖通关与失败分支，并验证结算页重开使用 RunState 的统一重置入口。
func _run() -> void:
	root.size = Vector2i(360, 640)
	var screen := RESULT_SCENE.instantiate()
	root.add_child(screen)
	await process_frame

	screen.run_state.chapter = 3
	screen.run_state.battles_won = 9
	screen.run_state.run_status = screen.run_state.RunStatus.COMPLETED
	screen.refresh_ui()
	_assert_equal(screen.title_label.text, "三章通关！", "完成状态显示通关标题")
	_assert_true("战斗胜利 9 场" in screen.summary_label.text, "通关摘要包含胜场")

	screen.run_state.run_status = screen.run_state.RunStatus.FAILED
	screen.refresh_ui()
	_assert_equal(screen.title_label.text, "本局结束", "失败状态显示失败标题")
	_assert_true("下一局" in screen.detail_label.text, "失败说明提示重新开始")

	if _failed:
		quit(1)
		return
	print("smoke_result_screen: PASS")
	quit()


# 通用相等断言：保留结算分支标签，便于定位状态与文案不一致。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言：允许一次运行报告多个结算展示问题。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
