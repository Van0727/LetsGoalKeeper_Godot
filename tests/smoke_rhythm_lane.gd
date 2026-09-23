# 横向圆圈模式验收：覆盖三段同心色带、曲目起音偏移、中心缩放、暂停及时间边界。
extends SceneTree

const BATTLE := preload("res://scenes/battle.tscn")
var _failed := false

func _initialize() -> void:
	call_deferred("_run")

# 使用真实战斗 UI，但关闭音频时间自动刷新，以注入确定性时刻检验方向与边界，不写正式设置或存档。
func _run() -> void:
	root.size = Vector2i(360, 640)
	var settings: Node = root.get_node("SettingsService")
	settings.set_metronome_style(settings.MetronomeStyle.CIRCLE)
	root.get_node("RunState").start_new_run(7302)
	var battle: Control = BATTLE.instantiate()
	root.add_child(battle)
	var deadline := Time.get_ticks_msec() + 3000
	while battle._battle_generation <= 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	_assert(battle._battle_generation > 0 and battle.hand_layer.get_child_count() > 0, "真实战斗初始化完成且生成手牌")
	battle.set_process(false)
	var lane: RhythmFeedback = battle.rhythm_feedback
	# 判定反馈公开接口统一输出玩家可见的大写等级；内部旧Perfect键也只能显示GREAT。
	lane.show_judgement({"grade_name": "Miss", "error_ms": 83.0})
	_assert(lane.judgement_label.text == "MISS", "Miss判定只显示全大写等级，不显示毫秒")
	_assert(lane._judgement_effect_age < 0.0, "MISS不启动图形评级特效")
	_assert(not lane.judgement_glow_label.visible, "MISS不显示文字闪光残影")
	var miss_color := lane.judgement_label.get_theme_color("font_color")
	var shared_font_size := lane.judgement_label.get_theme_font_size("font_size")
	var shared_outline_size := lane.judgement_label.get_theme_constant("outline_size")
	lane.show_judgement({"grade_name": "Good", "error_ms": -83.0})
	_assert(lane.judgement_label.text == "GOOD", "Good判定只显示全大写等级，不显示毫秒")
	_assert(lane._judgement_effect_grade == "GOOD" and lane._judgement_effect_age == 0.0, "GOOD启动绿色外扩波形特效")
	_assert(lane.judgement_glow_label.visible, "GOOD显示绿色文字闪光残影")
	var good_color := lane.judgement_label.get_theme_color("font_color")
	lane.show_judgement({"grade_name": "Perfect", "error_ms": 0.0})
	_assert(lane.judgement_label.text == "GREAT", "内部Perfect判定对玩家只显示全大写GREAT")
	var great_color := lane.judgement_label.get_theme_color("font_color")
	_assert(miss_color.r > miss_color.g and miss_color.r > miss_color.b, "MISS使用红色主色")
	_assert(good_color.g > good_color.r and good_color.g > good_color.b, "GOOD使用绿色主色")
	_assert(great_color.r > 0.9 and great_color.g > 0.6 and great_color.b < 0.4, "GREAT使用金色主色")
	_assert(shared_font_size == lane.judgement_label.get_theme_font_size("font_size"), "三种判定共用同一字号")
	_assert(shared_font_size >= 64, "评级文字提升至两倍大字号")
	_assert(shared_outline_size >= 8 and shared_outline_size == lane.judgement_label.get_theme_constant("outline_size"), "三种判定共用更粗描边")
	_assert(lane._judgement_effect_grade == "GREAT" and lane._judgement_effect_age == 0.0, "GREAT触发彩色外扩波形特效")
	_assert(lane.judgement_glow_label.visible, "GREAT显示彩色文字闪光残影")
	await _capture("great_judgement", battle)
	_assert(is_equal_approx(battle.rhythm_clock.first_beat_offset, 0.025), "基础鼓点对齐实际起音的25ms偏移")
	_assert(lane._circle_enabled and not battle.rhythm_waveform.visible, "圆圈显示横向节奏条并隐藏波形")
	_assert(battle.get_node_or_null("RhythmLaneArt") == null, "节奏模式不再加载旧背景图片")
	lane.set_music_timing(2.4, 0.6, 0.0, 4)
	var accent: Control = battle.rhythm_accent_waveform
	_assert(accent.visible and accent.mouse_filter == Control.MOUSE_FILTER_IGNORE, "圆圈模式显示装饰波形且不截获输入")
	_assert(accent.get_global_rect().end.y <= battle.hand_layer.get_global_rect().position.y, "装饰波形位于手牌上方")
	_assert(is_equal_approx(lane.get_global_rect().get_center().x, 180.0), "基准线与节奏条位于屏幕中心")
	var initial_pulse := lane.get_pulse_visual()
	var initial_bands := lane.get_pulse_bands()
	_assert(initial_bands.size() == 3, "扩散圈使用参考图的三段同心色带")
	_assert(is_equal_approx(initial_bands[0].inner_radius, initial_bands[1].outer_radius), "外圈与中圈边界相接")
	_assert(is_equal_approx(initial_bands[1].inner_radius, initial_bands[2].outer_radius), "中圈与内圈边界相接")
	_assert(initial_bands[0].color.a < initial_bands[1].color.a and initial_bands[1].color.a < initial_bands[2].color.a, "圈层从内到外亮度递减")
	lane.set_music_timing(2.6, 0.6, 0.0, 4)
	var expanded_pulse := lane.get_pulse_visual()
	_assert(lane.get_pulse_bands()[0].outer_radius > initial_bands[0].outer_radius, "分段圈层同步向外扩张")
	_assert(expanded_pulse.diameter > initial_pulse.diameter and expanded_pulse.alpha < initial_pulse.alpha, "拍内光圈向外扩散并淡出")
	lane.set_music_timing(3.0, 0.6, 0.0, 4)
	_assert(is_equal_approx(lane.get_pulse_visual().diameter, initial_pulse.diameter), "下一拍光圈重新从中心扩散")
	accent.set_music_timing(2.4, 0.6, 0.0)
	var first_heights: PackedFloat32Array = accent.get_bar_heights()
	accent.set_music_timing(2.6, 0.6, 0.0)
	_assert(first_heights != accent.get_bar_heights(), "装饰柱随音乐拍内进度变化")
	var frozen_heights: PackedFloat32Array = accent.get_bar_heights()
	accent.set_music_timing(2.6, 0.6, 0.0)
	_assert(frozen_heights == accent.get_bar_heights(), "暂停时间不变时装饰波形冻结")
	accent.set_music_timing(0.0, 0.0, 0.0)
	_assert(accent.get_bar_heights().is_empty(), "装饰波形非法拍长安全回退")
	accent.set_music_timing(0.0, 0.6, 1.0)
	_assert(accent.get_bar_heights().is_empty(), "前奏不生成装饰拍点")
	lane.set_music_timing(2.4, 0.6, 0.0, 4)
	var first := _note(lane, 4)
	_assert(first.is_first and first.base_size == Vector2(26, 26), "每小节首拍使用大音符")
	_assert(is_equal_approx(first.scale, 1.35), "大音符在中心达到缩放峰值")
	_assert(is_equal_approx(first.rect.get_center().x, lane.size.x * 0.5), "目标拍恰好位于中央")
	_assert(not _note(lane, 5).is_first and _note(lane, 5).rect.size == Vector2(16, 16), "其他拍使用普通音符")
	# 普通拍也必须放大；校准后的最近拍判定时间与视觉中心完全一致，缩回时轨迹继续向左。
	var clock: RhythmClock = battle.rhythm_clock
	var aligned_target: float = clock.first_beat_offset + 5 * clock.get_beat_duration()
	var result: Dictionary = clock.judge_at(aligned_target)
	lane.set_music_timing(result.target_time, clock.get_beat_duration(), clock.first_beat_offset, clock.beats_per_bar)
	_assert(is_equal_approx(_note(lane, 5).scale, 1.35), "普通音符到点同样放大")
	_assert(is_equal_approx(_note(lane, 5).rect.get_center().x, lane.size.x * 0.5), "校准后的判定拍点和UI中心一致")
	await _capture("normal_beat_peak", battle)
	lane.set_music_timing(aligned_target + 0.07, 0.6, clock.first_beat_offset, 4)
	_assert(_note(lane, 5).scale > 1.0 and _note(lane, 5).scale < 1.35, "到点后普通音符缩回")
	_assert(_note(lane, 5).rect.get_center().x < lane.size.x * 0.5, "缩放不影响向左移动的中心轨迹")
	lane.set_music_timing(aligned_target + 0.2, 0.6, clock.first_beat_offset, 4)
	_assert(is_equal_approx(_note(lane, 5).scale, 1.0), "跳帧后按音乐时间恢复原尺寸")
	lane.set_music_timing(aligned_target - 0.03, 0.6, clock.first_beat_offset, 4)
	_assert(_note(lane, 5).scale > 1.0 and _note(lane, 5).scale < 1.35, "到点前短促起峰")
	lane.set_music_timing(2.4, 0.6, 0.0, 4)
	var before_x: float = _note(lane, 5).rect.get_center().x
	lane.set_music_timing(2.55, 0.6, 0.0, 4)
	_assert(_note(lane, 5).rect.get_center().x < before_x, "音乐时间前进时音符从右向左")
	var paused_layout := lane.get_note_layout()
	lane.set_music_timing(2.55, 0.6, 0.0, 4)
	_assert(lane.get_note_layout() == paused_layout, "暂停期间同一音频时间保持位置不变")
	lane.set_music_timing(120.0, 0.6, 0.0, 4)
	var loop_x: float = _note(lane, 201).rect.get_center().x
	lane.set_music_timing(120.1, 0.6, 0.0, 4)
	_assert(_note(lane, 201).rect.get_center().x < loop_x, "跨循环的连续时间保持移动方向")
	lane.set_music_timing(0.0, 0.6, 1.0, 4)
	for note in lane.get_note_layout():
		_assert(note.beat_index >= 0 and note.rect.get_center().x > lane.size.x * 0.5, "前奏仅显示将来的真实音符")
	lane.set_music_timing(0.0, 0.0, 0.0, 4)
	_assert(lane.get_note_layout().is_empty(), "无效拍长安全隐藏音符")
	_assert(lane.get_pulse_bands().is_empty(), "无效时钟不绘制分段色带")
	lane.set_music_timing(0.0, 0.6, 0.0, 0)
	_assert(_note(lane, 0).is_first, "无效小节拍数安全归一化")
	lane.set_music_timing(2.4, 0.6, 0.0, 4)
	accent.set_music_timing(2.4, 0.6, 0.0)
	await _capture("circle", battle)
	lane.set_music_timing(2.6, 0.6, 0.0, 4)
	accent.set_music_timing(2.6, 0.6, 0.0)
	await _capture("expanding", battle)
	settings.set_metronome_style(settings.MetronomeStyle.WAVEFORM)
	_assert(not lane._circle_enabled and battle.rhythm_waveform.visible, "切换波形隐藏横向音符")
	_assert(not accent.visible, "原波形模式隐藏新增装饰波形")
	_assert(battle.get_node_or_null("RhythmLaneArt") == null, "波形使用透明背景，不再恢复旧图片")
	_assert(battle.rhythm_waveform.CENTER_LINE_WIDTH > 0.0, "透明波形保留独立横向基准线")
	battle.rhythm_waveform.pulse_beat()
	battle.rhythm_waveform._process(0.045)
	battle.rhythm_waveform.set_process(false)
	await _capture("waveform", battle)
	settings.set_metronome_style(settings.MetronomeStyle.CIRCLE)
	_assert(lane._circle_enabled and not battle.rhythm_waveform.visible, "切回圆圈即时恢复")
	battle.free()
	print("smoke_rhythm_lane: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

# 根据正式拍号查找可见音符，失败时记录诊断并返回可继续断言的空占位。
func _note(lane: RhythmFeedback, index: int) -> Dictionary:
	for note in lane.get_note_layout():
		if note.beat_index == index:
			return note
	_assert(false, "缺少预期音符 %d" % index)
	return {"is_first": false, "rect": Rect2()}

func _assert(value: bool, label: String) -> void:
	if not value:
		_failed = true
		push_error(label)

# 仅在显式传入 --capture 的真实渲染模式读取视口，避免无头环境访问空渲染纹理。
func _capture(stage: String, battle: Control) -> void:
	if not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	_assert(battle.get_viewport().get_texture().get_image().save_png("res://output/rhythm_%s.png" % stage) == OK, "截图保存")
