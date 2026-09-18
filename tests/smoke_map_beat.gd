# 地图节拍验收：可选节点整体放大、锁定静止、重复节拍、暂停恢复与刷新清理。
extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(360, 640)
	var bgm = root.get_node("BgmService")
	bgm.set_process(false)
	root.get_node("RunState").start_new_run(777)
	var screen = load("res://scenes/map_screen.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	var active
	var locked
	for button in screen.room_buttons.values():
		if button.disabled:
			locked = button
		else:
			active = button
	bgm.main_beat_reached.emit(0)
	check(active._pulse_tween != null, "音乐节拍必须触发可选节点")
	check(locked._pulse_tween == null and locked.scale == Vector2.ONE, "锁定节点保持静止")
	active._pulse_tween.pause()
	active._pulse_tween.custom_step(0.16)
	check(is_equal_approx(active.scale.x, screen.selectable_pulse_scale), "峰值必须使用可调倍率")
	check(active.title_label.get_global_transform().get_scale().is_equal_approx(active.scale), "名字随节点整体放大")
	check(active.pivot_offset.is_equal_approx(active.node_center()), "以圆盘中心缩放")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/map-beat-peak.png")
	active._pulse_tween.custom_step(0.34)
	check(active.scale.is_equal_approx(Vector2.ONE), "每拍结束恢复原尺寸")
	bgm.main_beat_reached.emit(1)
	var previous: Tween = active._pulse_tween
	bgm.main_beat_reached.emit(2)
	check(not previous.is_valid(), "重复节拍应终止上一动画")
	paused = true
	var frozen: Vector2 = active.scale
	bgm.main_beat_reached.emit(3)
	await create_timer(0.05, true).timeout
	check(active.scale.is_equal_approx(frozen), "暂停时动画与节拍均冻结")
	paused = false
	active.stop_pulse()
	check(active.scale == Vector2.ONE and active._pulse_tween == null, "过场清理恢复原尺寸")
	screen.refresh_ui()
	await process_frame
	check(not is_instance_valid(active), "刷新应释放旧节点和动画")
	root.get_node("RunState").map_state = null
	bgm.main_beat_reached.emit(4)
	screen.queue_free()
	await process_frame
	bgm.main_beat_reached.emit(5)
	print("MAP BEAT SMOKE: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
