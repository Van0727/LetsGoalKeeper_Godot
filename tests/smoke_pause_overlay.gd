# 暂停冒烟测试：验证冻结/恢复、确认边界，以及异步重复确认和节点离树后的回调。
extends SceneTree

const PAUSE_SCENE := preload("res://scenes/pause_overlay.tscn")

var _failed := false

# 可控切曲服务用于精确覆盖等待期间的重复点击与离树，不依赖实际音频时长。
class DeferredBgm extends Node:
	signal completed
	var calls := 0
	func transition_to_main_bgm() -> void:
		calls += 1
		await completed


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

	var real_bgm := root.get_node("BgmService")
	# 替身期间暂停真实服务的场景监听，避免测试离树服务响应新场景信号。
	var bgm_scene_callback := Callable(real_bgm, "_on_scene_changed")
	scene_changed.disconnect(bgm_scene_callback)
	root.remove_child(real_bgm)
	var fake_bgm := DeferredBgm.new()
	fake_bgm.name = "BgmService"
	root.add_child(fake_bgm)
	var waiting_overlay := PAUSE_SCENE.instantiate()
	root.add_child(waiting_overlay)
	waiting_overlay.open_pause()
	waiting_overlay.request_confirmation(waiting_overlay.ConfirmAction.MAIN_MENU)
	waiting_overlay._on_confirm_pressed()
	waiting_overlay._on_confirm_pressed()
	waiting_overlay.cancel_confirmation()
	waiting_overlay.close_pause()
	_assert_equal(fake_bgm.calls, 1, "重复确认只启动一次切曲")
	_assert_true(paused, "切曲期间不能继续或取消暂停")
	root.remove_child(waiting_overlay)
	fake_bgm.completed.emit()
	waiting_overlay.open_pause()
	waiting_overlay.close_pause()
	waiting_overlay._on_confirm_pressed()
	waiting_overlay.set_external_modal_open(false)
	_assert_true(paused, "离树回调不改写其他场景的暂停状态")
	waiting_overlay.free()
	paused = false

	# 正常确认真实加载主菜单，验证切场景移除旧节点后仍能安全解除暂停。
	var old_scene := Node.new()
	root.add_child(old_scene)
	current_scene = old_scene
	var returning_overlay := PAUSE_SCENE.instantiate()
	old_scene.add_child(returning_overlay)
	returning_overlay.open_pause()
	returning_overlay.request_confirmation(returning_overlay.ConfirmAction.MAIN_MENU)
	returning_overlay._on_confirm_pressed()
	fake_bgm.completed.emit()
	await process_frame
	await process_frame
	_assert_true(not paused, "正常返回主菜单解除暂停")
	_assert_true(current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn", "正常返回真实主菜单")
	fake_bgm.free()
	root.add_child(real_bgm)
	scene_changed.connect(bgm_scene_callback)

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
