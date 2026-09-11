# 主菜单入口测试：验证临时遮罩层级，以及继续按钮在不同本局状态下的启用边界。
extends SceneTree

const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")

var _failed := false


# 延迟运行，确保 Autoload 与主菜单唯一名称节点完成初始化。
func _initialize() -> void:
	call_deferred("_run")


# 直接切换 RunState 状态，验证主菜单不会把已结束的本局显示成可继续。
func _run() -> void:
	root.size = Vector2i(360, 640)
	var menu := MAIN_MENU_SCENE.instantiate()
	root.add_child(menu)
	await process_frame
	var run_state: Node = root.get_node("RunState")
	var test_mask := menu.get_node("TempCompanyTestMask") as ColorRect
	_assert_true(test_mask.visible, "公司测试临时遮罩默认可见")
	_assert_true(test_mask.mouse_filter == Control.MOUSE_FILTER_STOP, "临时遮罩拦截下层界面输入")
	_assert_true(test_mask.get_index() < menu.start_button.get_index(), "开始按钮绘制在临时遮罩上方")
	_assert_true(test_mask.get_index() < menu.continue_button.get_index(), "继续按钮绘制在临时遮罩上方")

	run_state.start_new_run(7001)
	run_state.chapter = 2
	run_state.battles_won = 4
	menu.refresh_continue_availability()
	_assert_true(not menu.continue_button.disabled, "进行中的本局允许继续")

	run_state.mark_run_failed()
	menu.refresh_continue_availability()
	_assert_true(menu.continue_button.disabled, "失败本局不能继续")

	run_state.run_status = run_state.RunStatus.COMPLETED
	menu.refresh_continue_availability()
	_assert_true(menu.continue_button.disabled, "通关本局不能继续")

	if _failed:
		quit(1)
		return
	print("smoke_main_menu_status: PASS")
	quit()


# 通用布尔断言：失败时输出对应的继续按钮状态场景。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
