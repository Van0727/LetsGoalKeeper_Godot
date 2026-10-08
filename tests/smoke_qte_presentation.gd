# 聚光主动技界面验收：真实战斗场景下覆盖三类配色、可编辑目标与点击映射、进度、失败入口及可选截图。
extends SceneTree

class FixedClock extends Node:
	var now := 0.0
	var perfect_window_ms := 75.0
	var good_window_ms := 150.0
	func get_music_time() -> float: return now
	func get_beat_duration() -> float: return 0.6
	func get_next_beat_time(_time: float) -> float: return 0.6
	func get_playback_rate() -> float: return 1.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# 1.5倍非整数窗口缩放验收：同时检查像素导数随实际屏幕分辨率调整。
	var scaled := "--scaled" in OS.get_cmdline_user_args()
	var capture_suffix := "_scaled" if scaled else ""
	root.size = Vector2i(540, 960) if scaled else Vector2i(360, 640)
	var battle = load("res://scenes/battle.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	battle.run_state.start_new_run(8108)
	battle.start_new_battle(load("res://data/enemies/chapter_one/enemy_street_chicken.tres"))
	await process_frame
	var clock := FixedClock.new()
	root.add_child(clock)
	var popup = battle.qte_popup
	var completions: Array[int] = [0]
	popup.qte_finished.connect(func(_result: Dictionary) -> void: completions[0] += 1)
	assert(not popup.start_qte(null))
	assert(not popup.start_qte(clock, 1, 278.0, 99))
	for kind in [0, 1, 2]:
		var prior_feedback: bool = battle.rhythm_feedback.visible
		var prior_waveform: bool = battle.rhythm_waveform.visible
		assert(popup.start_qte(clock, 12, 278.0, kind))
		assert(not battle.rhythm_feedback.visible and not battle.rhythm_waveform.visible)
		assert(not popup.start_qte(clock))
		popup.set_process(false)
		popup.set_skill_title(["超级攻击", "超级防御", "超级技能"][kind])
		clock.now = float(popup._notes[0].target_time) - 0.2
		popup._refresh_visual_nodes()
		assert(popup._layout.get_node("Progress").text == "0 / 4")
		# 连续橙→蓝→绿复用同一弹窗，检查全轨全音符无上一类型颜色残留。
		var type_color: Color = popup.TYPE_COLORS[kind]
		for lane in range(3):
			assert(popup._beam_views[lane].modulate == type_color)
			assert(popup._lane_views[lane].modulate == type_color)
			assert(popup._lane_views[lane].material.shader == popup._edge_material.shader)
			assert(popup._target_views[lane].modulate == type_color.lightened(0.65))
			assert(popup._halo_views[lane].modulate == Color(type_color, 0.4))
			assert(popup._core_views[lane].modulate == type_color)
		for ray in popup._ray_views:
			assert(ray.modulate == Color(type_color.lightened(0.2), 0.9))
		for note_index in range(4):
			assert(popup._note_views[note_index].visible)
			assert(popup._note_views[note_index].modulate == type_color.lightened(0.65))
			assert(popup._note_core_views[note_index].modulate == type_color)
		for edge in popup._beam_edge_views:
			assert(edge.size.x == 2.0 and edge.modulate == Color(type_color, 0.78))
		assert(popup._beam_views[0].size.x == 56.0)
		# 所有光束越过屏幕顶部，材质分别控制渐隐和圆环抗锯齿。
		assert(popup._beam_views[0].position.y < 0.0)
		assert(popup._beam_views[0].material.shader == popup._beam_material.shader)
		assert(popup._target_views[0].material == popup._ring_material)
		assert(popup._baseline.modulate == type_color)
		assert(popup._baseline.material == popup._core_material)
		assert(popup._progress_style.border_color == type_color.lightened(0.2))
		# 远端左右内收、判定线精确落点，音符按距离改变大小。
		assert(popup._get_perspective_x(0, 0.0) > popup._get_lane_x(popup._get_play_area(), 0))
		assert(popup._get_perspective_x(2, 0.0) < popup._get_lane_x(popup._get_play_area(), 2))
		assert(is_equal_approx(popup._get_perspective_x(0, popup._target_line_y), popup._get_lane_x(popup._get_play_area(), 0)))
		assert(popup._note_views[0].size.x > popup._note_views[3].size.x)
		# 移动编辑标记后，目标与输入坐标同步；归位后再捕获正式布局。
		var marker: Control = popup._target_markers[0]
		var previous := marker.position
		marker.position.x += 8.0
		popup._refresh_visual_nodes()
		var center: Vector2 = popup._target_views[0].get_rect().get_center()
		assert(popup._lane_at_pointer(center) == 0)
		assert(is_equal_approx(center.x, marker.get_rect().get_center().x))
		marker.position = previous
		popup._show_judgement("Great")
		assert(popup._judgement_label.text == "GREAT")
		if "--capture" in OS.get_cmdline_user_args():
			await process_frame
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png("res://output/qte_spotlight_%d%s.png" % [kind, capture_suffix]) == OK)
		var note: Dictionary = popup._notes[0]
		var judged_time := float(note.target_time) - 0.05
		assert(popup.judge_lane(int(note.lane), judged_time) == "Great")
		var effect: Node2D = popup._last_hit_effect
		assert(effect.get_parent() == battle and not effect.missed)
		var expected_y := lerpf(popup._get_play_area().position.y, popup._target_line_y, 1.0 - 0.05 / 1.2)
		assert(is_equal_approx(effect.global_position.y, expected_y))
		assert(effect.effect_color == type_color)
		assert(is_equal_approx(effect.global_position.x, popup._get_perspective_x(int(note.lane), expected_y)))
		effect._process(0.06)
		effect.set_process(false)
		if "--capture" in OS.get_cmdline_user_args():
			await process_frame
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png("res://output/qte_hit_%d%s.png" % [kind, capture_suffix]) == OK)
		effect.free()
		assert(popup._layout.get_node("Progress").text == "1 / 4")
		popup._show_judgement("Good")
		assert(popup._judgement_label.modulate.g > popup._judgement_label.modulate.r)
		popup._show_judgement("Miss")
		assert(popup._judgement_label.modulate.r > popup._judgement_label.modulate.g)
		# 其余音符含Good与Miss，最后一音必须立即关闭并发出一次结果，独立特效仍可见。
		var second: Dictionary = popup._notes[1]
		assert(popup.judge_lane(int(second.lane), float(second.target_time) + 0.1) == "Good")
		popup._apply_judgement(popup._notes[2], "Miss", float(popup._notes[2].target_time) + 0.16)
		assert(popup._last_hit_effect.missed)
		var last: Dictionary = popup._notes[3]
		assert(popup.judge_lane(int(last.lane), float(last.target_time)) == "Great")
		assert(not popup.visible and completions[0] == kind + 1)
		var final_effect: Node2D = popup._last_hit_effect
		assert(final_effect.is_visible_in_tree())
		final_effect._process(0.06)
		final_effect.set_process(false)
		if kind == 0 and "--capture" in OS.get_cmdline_user_args():
			await process_frame
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png("res://output/qte_last_hit%s.png" % capture_suffix) == OK)
		final_effect._process(0.4)
		await process_frame
		assert(not is_instance_valid(final_effect))
		for child in battle.get_children():
			if child.get_script() == popup.HIT_EFFECT:
				child.free()
		assert(battle.rhythm_feedback.visible == prior_feedback)
		assert(battle.rhythm_waveform.visible == prior_waveform)
	battle.free()
	clock.free()
	await process_frame
	print("smoke_qte_presentation: PASS | types=3 | layout/input/progress/failure")
	quit()
