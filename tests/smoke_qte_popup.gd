# 主动技QTE冒烟测试：验证半拍目标、变调后的现实判定窗口、输入锁和延迟结算。
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
	# QTE 与普通出牌共用逐曲校准后的播放头，正负校准在同一首曲上应产生相反时间移动。
	await create_timer(0.2).timeout
	battle.rhythm_clock.set_calibration_offset_ms(40.0)
	var positive_time: float = battle.rhythm_clock.get_music_time()
	battle.rhythm_clock.set_calibration_offset_ms(-40.0)
	var negative_time: float = battle.rhythm_clock.get_music_time()
	_assert_true(absf((positive_time - negative_time) - 0.08) < 0.02, "正负40ms校准在播放头中形成约80ms差异")
	battle.rhythm_clock.set_calibration_offset_ms(0.0)

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
	_assert_true(battle.qte_popup._rhythm_clock == battle.rhythm_clock, "QTE复用已校准的战斗播放头")
	_assert_equal(battle.qte_popup._notes.size(), 4, "QTE固定生成四个音符")
	_assert_equal(battle.qte_popup.TRAVEL_BEATS, 2.0, "音符下落时长缩短到两拍即速度提升1.5倍")
	var note_interval: float = (
		float(battle.qte_popup._notes[1].target_time) - float(battle.qte_popup._notes[0].target_time)
	)
	_assert_true(
		absf(note_interval - battle.rhythm_clock.get_beat_duration() * 0.5) < 0.0001,
		"相邻音符保持半拍间隔"
	)
	var first_target_beat: float = (
		(float(battle.qte_popup._notes[0].target_time) - battle.rhythm_clock.first_beat_offset)
		/ battle.rhythm_clock.get_beat_duration()
	)
	_assert_true(
		absf(first_target_beat - roundf(first_target_beat)) < 0.0001,
		"QTE首个目标严格落在BGM整数拍点"
	)
	var first_spawn_time: float = (
		float(battle.qte_popup._notes[0].target_time)
		- battle.rhythm_clock.get_beat_duration() * battle.qte_popup.TRAVEL_BEATS
	)
	var first_spawn_beat: float = (
		(first_spawn_time - battle.rhythm_clock.first_beat_offset)
		/ battle.rhythm_clock.get_beat_duration()
	)
	_assert_true(
		absf(first_spawn_beat - roundf(first_spawn_beat)) < 0.0001,
		"首个音符仍在下一个整数拍进场"
	)
	for note in battle.qte_popup._notes:
		var target_beat: float = (
			(float(note.target_time) - battle.rhythm_clock.first_beat_offset)
			/ battle.rhythm_clock.get_beat_duration()
		)
		_assert_true(absf(target_beat * 2.0 - roundf(target_beat * 2.0)) < 0.0001, "所有QTE音符目标均对齐半拍网格")
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
	for note_index in range(1, battle.qte_popup._notes.size()):
		var previous_lane := int(battle.qte_popup._notes[note_index - 1].lane)
		var current_lane := int(battle.qte_popup._notes[note_index].lane)
		_assert_true(abs(current_lane - previous_lane) <= 1, "相邻音符不会跨过中间轨道")
	_assert_true(
		not (
			battle.qte_popup._notes[0].lane == battle.qte_popup._notes[1].lane
			and battle.qte_popup._notes[1].lane == battle.qte_popup._notes[2].lane
			and battle.qte_popup._notes[2].lane == battle.qte_popup._notes[3].lane
		),
		"四个音符不会全部落在同一轨道"
	)
	# 多组固定种子覆盖随机边界，避免单次序列恰好未出现左右端互跳而漏检。
	for sequence_seed in range(64):
		battle.qte_popup._rng.seed = sequence_seed + 1
		var lane_sequence: PackedInt32Array = battle.qte_popup._generate_lane_sequence()
		for note_index in range(1, lane_sequence.size()):
			_assert_true(
				absi(lane_sequence[note_index] - lane_sequence[note_index - 1]) <= 1,
				"任意随机种子的相邻音符轨道差不超过一格"
			)
		_assert_true(
			not (
				lane_sequence[0] == lane_sequence[1]
				and lane_sequence[1] == lane_sequence[2]
				and lane_sequence[2] == lane_sequence[3]
			),
			"任意随机种子都不会生成四连同轨"
		)

	# 升降调时窗口使用现实毫秒，与普通出牌一致；超时分支使用相同换算。
	var first_note: Dictionary = battle.qte_popup._notes[0]
	var second_note: Dictionary = battle.qte_popup._notes[1]
	var third_note: Dictionary = battle.qte_popup._notes[2]
	battle.rhythm_clock._audio_player.pitch_scale = 2.0
	_assert_true(absf(battle.qte_popup._get_source_window_seconds(0.14) - 0.28) < 0.0001, "二倍速下140ms窗口对应280ms音源时间")
	_assert_equal(
		battle.qte_popup.judge_lane(int(first_note.lane), float(first_note.target_time) + 0.10),
		"Perfect",
		"二倍速下音源晚100ms仍为现实50ms的Perfect"
	)
	battle.rhythm_clock._audio_player.pitch_scale = 0.5
	_assert_true(absf(battle.qte_popup._get_source_window_seconds(0.14) - 0.07) < 0.0001, "半速下140ms窗口对应70ms音源时间")
	_assert_equal(
		battle.qte_popup.judge_lane(int(second_note.lane), float(second_note.target_time) + 0.05),
		"Good",
		"半速下音源晚50ms对应现实100ms的Good"
	)
	battle.rhythm_clock._audio_player.pitch_scale = 2.0
	third_note.target_time = (
		battle.rhythm_clock.get_music_time() - battle.qte_popup._get_source_window_seconds(battle.qte_popup._good_window_seconds) - 0.01
	)
	battle.qte_popup._process(0.0)
	_assert_true(bool(third_note.judged) and third_note.grade == "Miss", "二倍速下越过现实Good窗口自动补记Miss")
	battle.rhythm_clock._audio_player.pitch_scale = 1.0
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
