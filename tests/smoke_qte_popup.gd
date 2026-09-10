# 主动技QTE冒烟测试：验证内嵌遮罩、三轨八音符、判定边界、输入锁和完成后延迟结算。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	battle.run_state.start_new_run(8108)
	battle.start_new_battle(TURTLE)
	await process_frame

	# 直接准备三点攻击连击，确认按下技能只打开弹窗，不会提前消耗连击或造成伤害。
	battle.controller.combo_state.card_type = 0
	battle.controller.combo_state.count = 3
	battle._refresh_all()
	var health_before: int = battle.controller.enemy.health
	var launched_results: Array[Variant] = []
	var committed_times: Array[float] = []
	var shake_results: Array[Variant] = []
	battle.active_skill_ball_launched.connect(
		func(hit_target: bool, end_position: Vector2) -> void:
			launched_results.append([hit_target, end_position])
	)
	battle.screen_shake_started.connect(
		func(duration: float, amplitude: float) -> void:
			shake_results.append([duration, amplitude])
	)
	battle.active_skill_effect_committed.connect(
		func(elapsed_music_seconds: float) -> void: committed_times.append(elapsed_music_seconds)
	)
	battle._on_skill_pressed()
	_assert_true(battle.qte_popup.visible, "主动技打开战斗内嵌QTE弹窗")
	_assert_equal(battle.qte_popup._notes.size(), 8, "QTE固定生成八个音符")
	_assert_equal(battle.qte_popup.TRAVEL_BEATS, 2.0, "音符下落时长缩短到两拍即速度提升1.5倍")
	var note_interval: float = (
		float(battle.qte_popup._notes[1].target_time) - float(battle.qte_popup._notes[0].target_time)
	)
	_assert_true(
		absf(note_interval - battle.rhythm_clock.get_beat_duration()) < 0.0001,
		"加速后相邻音符仍保持一拍间隔"
	)
	_assert_equal(battle.controller.combo_state.count, 3, "QTE期间不提前消耗连击")
	_assert_equal(battle.controller.enemy.health, health_before, "QTE期间不提前结算主动技")
	_assert_true(battle._input_locked, "QTE期间锁住战斗输入")
	_assert_true(not battle.pause_overlay.pause_button.visible, "QTE期间隐藏暂停入口")
	_assert_true(
		absf(battle.qte_popup._target_line_y - battle.rhythm_waveform.get_global_rect().get_center().y) < 0.1,
		"QTE判定横线与原波形中心线保持同一高度"
	)
	var play_area: Rect2 = battle.qte_popup._get_play_area()
	for lane in range(3):
		var target_position := Vector2(
			battle.qte_popup._get_lane_x(play_area, lane), battle.qte_popup._target_line_y
		)
		_assert_equal(battle.qte_popup._lane_at_pointer(target_position), lane, "鼠标点击映射到对应轨道")
	_assert_equal(battle.qte_popup._lane_at_pointer(Vector2(0, 0)), -1, "横线音符外的点击不触发判定")
	var click_audio_count := [0]
	var qte_miss_audio_count := [0]
	battle.qte_popup.click_audio_triggered.connect(func() -> void: click_audio_count[0] += 1)
	battle.qte_popup.miss_audio_triggered.connect(func() -> void: qte_miss_audio_count[0] += 1)
	battle.qte_popup._activate_lane(0)
	_assert_equal(click_audio_count[0], 1, "点击目标音符播放qteClick音效")
	_assert_equal(battle.qte_popup._target_pulse_ages[0], 0.0, "点击后启动对应目标音符脉冲")
	battle.qte_popup._process(0.04)
	_assert_true(battle.qte_popup._get_target_pulse_scale(0) > 1.0, "点击后目标音符快速放大")
	battle.qte_popup._process(0.2)
	_assert_equal(battle.qte_popup._get_target_pulse_scale(0), 1.0, "点击动画结束后恢复原尺寸")
	_assert_equal(qte_miss_audio_count[0], 1, "错误点击立即产生Miss音效反馈")
	for note in battle.qte_popup._notes:
		_assert_true(int(note.lane) >= 0 and int(note.lane) < 3, "每个音符只落在三条轨道之一")

	# 分别覆盖Perfect、Good和超时Miss；其余音符精确击中后应进入统一完成流程。
	var first_note: Dictionary = battle.qte_popup._notes[0]
	var second_note: Dictionary = battle.qte_popup._notes[1]
	var third_note: Dictionary = battle.qte_popup._notes[2]
	_assert_equal(
		battle.qte_popup.judge_lane(int(first_note.lane), float(first_note.target_time)),
		"Perfect",
		"目标拍点命中判定为Perfect"
	)
	var good_offset: float = (
		battle.qte_popup._perfect_window_seconds + battle.qte_popup._good_window_seconds
	) * 0.5
	_assert_equal(
		battle.qte_popup.judge_lane(int(second_note.lane), float(second_note.target_time) + good_offset),
		"Good",
		"Perfect窗口外且Good窗口内判定为Good"
	)
	third_note.target_time = (
		battle.rhythm_clock.get_music_time() - battle.qte_popup._good_window_seconds - 0.01
	)
	battle.qte_popup._process(0.0)
	_assert_true(bool(third_note.judged) and third_note.grade == "Miss", "越过Good窗口自动补记Miss")
	_assert_true(qte_miss_audio_count[0] >= 2, "音符超时Miss播放对应音效")
	for note_index in range(3, battle.qte_popup._notes.size() - 1):
		var note: Dictionary = battle.qte_popup._notes[note_index]
		var grade: String = battle.qte_popup.judge_lane(int(note.lane), float(note.target_time))
		_assert_equal(grade, "Perfect", "其余目标拍点命中判定为Perfect")
	var final_note: Dictionary = battle.qte_popup._notes[-1]
	_assert_equal(
		battle.qte_popup._activate_lane(int(final_note.lane), float(final_note.target_time)),
		"Perfect",
		"最后一个目标音符通过点击完成Perfect判定"
	)
	_assert_true(not battle.qte_popup.visible, "最后一拍完成时立即关闭QTE弹窗")
	_assert_equal(launched_results.size(), 1, "关闭QTE同帧发射超级足球")
	_assert_equal(click_audio_count[0], 2, "最后点击音效与同帧足球起脚音允许重叠播放")
	_assert_true(bool(launched_results[0][0]), "少于四次Miss时足球飞向敌人")
	_assert_true(battle.ball_flight.deform_pivot.scale.x > 0.9, "主动技足球明显大于普通足球")
	var beat_seconds: float = battle.rhythm_clock.get_beat_duration()
	await create_timer(beat_seconds + battle.PARTIAL_SHAKE_SECONDS + 0.25).timeout
	_assert_true(battle.controller.enemy.health < health_before, "足球飞行一拍后才结算主动技伤害")
	_assert_equal(committed_times.size(), 1, "主动技效果只提交一次")
	_assert_true(committed_times[0] + 0.001 >= beat_seconds, "主动技效果等待完整一拍音乐时间")
	_assert_equal(battle.controller.combo_state.count, 0, "QTE完成后主动技消耗连击")
	_assert_equal(shake_results.size(), 1, "命中后触发一次震屏")
	_assert_true(
		absf(float(shake_results[0][0]) - battle.PARTIAL_SHAKE_SECONDS) < 0.0001,
		"一至三次Miss触发0.2秒小幅震屏"
	)
	var perfect_shake: Vector2 = battle._get_active_skill_shake_config(0)
	_assert_true(
		absf(perfect_shake.x - battle.PERFECT_SHAKE_SECONDS) < 0.0001,
		"零Miss配置0.5秒夸张震屏"
	)
	_assert_true(perfect_shake.y > shake_results[0][1], "零Miss震屏幅度大于部分Miss")
	for _sample in range(8):
		var miss_end: Vector2 = battle._get_missed_active_skill_end_position()
		_assert_true(miss_end.x < 0.0 or miss_end.x > battle.size.x, "失败球随机终点保持在左右屏幕外")
	_assert_true(not battle._input_locked, "主动技结算后恢复战斗输入")
	_assert_true(battle.pause_overlay.pause_button.visible, "QTE关闭后恢复暂停入口")

	if _failed:
		quit(1)
		return
	print("smoke_qte_popup: PASS")
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
