# 阶段 9 暂停冒烟测试：验证冻结/恢复、返回键切换，以及菜单和退出的确认边界。
extends SceneTree

const PAUSE_SCENE := preload("res://scenes/pause_overlay.tscn")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var overlay := PAUSE_SCENE.instantiate()
	root.add_child(overlay)
	await process_frame
	_assert_true(not paused, "初始场景未暂停")
	_assert_true(overlay.pause_button.visible, "初始显示暂停入口")

	overlay.open_pause()
	_assert_true(paused, "打开菜单冻结 SceneTree")
	_assert_true(overlay.pause_panel.visible, "打开后显示暂停菜单")
	overlay.request_confirmation(overlay.ConfirmAction.MAIN_MENU)
	_assert_equal(overlay.pending_action, overlay.ConfirmAction.MAIN_MENU, "返回主菜单进入确认态")
	_assert_true(overlay.confirm_panel.visible, "返回主菜单显示确认框")
	overlay.cancel_confirmation()
	_assert_equal(overlay.pending_action, overlay.ConfirmAction.NONE, "取消后清除待执行操作")
	_assert_true(paused and overlay.pause_panel.visible, "取消确认后保持暂停")

	overlay.request_confirmation(overlay.ConfirmAction.QUIT_GAME)
	_assert_equal(overlay.pending_action, overlay.ConfirmAction.QUIT_GAME, "退出游戏进入确认态")
	var back_event := InputEventAction.new()
	back_event.action = "ui_cancel"
	back_event.pressed = true
	overlay._unhandled_input(back_event)
	_assert_equal(overlay.pending_action, overlay.ConfirmAction.NONE, "确认框按返回键只取消操作")
	overlay._unhandled_input(back_event)
	_assert_true(not paused, "暂停菜单按返回键恢复游戏")
	overlay._unhandled_input(back_event)
	_assert_true(paused, "游戏中按返回键打开暂停菜单")
	overlay.close_pause()
	_assert_true(not paused, "继续游戏解除冻结")
	overlay.free()

	if _failed:
		quit(1)
		return
	print("smoke_pause_overlay: PASS")
	quit()


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
