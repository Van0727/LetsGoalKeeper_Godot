# 战斗节奏反馈控件：横向音符穿过基准线并缩放，三层同心色带逐拍扩散，与判定共用首拍偏移。
class_name RhythmFeedback
extends Control

const GREAT_COLOR := Color(1.0, 0.79, 0.25, 1.0)
const GOOD_COLOR := Color(0.31, 0.88, 0.42, 1.0)
const MISS_COLOR := Color(1.0, 0.35, 0.34, 1.0)
const JUDGEMENT_OUTLINE_COLOR := Color(0.055, 0.07, 0.16, 0.96)
const JUDGEMENT_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const JUDGEMENT_FONT_SIZE := 64
const JUDGEMENT_OUTLINE_SIZE := 8
const JUDGEMENT_EFFECT_SECONDS := 0.42
const JUDGEMENT_WAVE_BAR_COUNT := 24
const BEAT_LINE := preload("res://assets/ui/battle/beatline.png")
const FIRST_BEAT := preload("res://assets/ui/battle/bigbeat.png")
const OTHER_BEAT := preload("res://assets/ui/battle/beat.png")
# 参考图 941×1672 映射到 360×640：首拍约 26 像素、普通拍约 16 像素，左右各显示三拍。
const FIRST_BEAT_SIZE := Vector2(26, 26)
const OTHER_BEAT_SIZE := Vector2(16, 16)
const VISIBLE_BEAT_SPAN := 6.0
const TARGET_LINE_HEIGHT := 46.0
const TARGET_LINE_COLOR := Color(1.0, 0.86, 0.46, 1.0)
const NOTE_PEAK_SCALE := 1.35
const NOTE_RISE_SECONDS := 0.06
const NOTE_FALL_SECONDS := 0.14

@onready var beat_label: Label = %BeatLabel
@onready var judgement_glow_label: Label = %JudgementGlowLabel
@onready var judgement_label: Label = %JudgementLabel

var _music_time := 0.0
var _beat_duration := 0.6
var _first_beat_offset := 0.0
var _beats_per_bar := 4
var _feedback_tween: Tween
var _judgement_glow_tween: Tween
var _circle_enabled := true
# 评级特效独立于圆圈/波形模式：两种节拍样式都能在中央看到同一套结果反馈。
var _judgement_effect_age := -1.0
var _judgement_effect_grade := ""
var _judgement_label_base_position := Vector2.ZERO


# 初始判定文字留空；图片线性过滤，绘制区域裁切只作用于音符，不裁掉独立的判定文字。
func _ready() -> void:
	judgement_label.text = ""
	# 三种判定共享大字号、描边和阴影，只切换主色与入场特效，保证辨识层级一致。
	judgement_label.add_theme_font_size_override("font_size", JUDGEMENT_FONT_SIZE)
	judgement_label.add_theme_constant_override("outline_size", JUDGEMENT_OUTLINE_SIZE)
	judgement_label.add_theme_constant_override("shadow_offset_x", 2)
	judgement_label.add_theme_constant_override("shadow_offset_y", 4)
	judgement_label.add_theme_color_override("font_outline_color", JUDGEMENT_OUTLINE_COLOR)
	judgement_label.add_theme_color_override("font_shadow_color", JUDGEMENT_SHADOW_COLOR)
	judgement_glow_label.add_theme_font_size_override("font_size", JUDGEMENT_FONT_SIZE)
	judgement_glow_label.add_theme_constant_override("outline_size", JUDGEMENT_OUTLINE_SIZE + 4)
	_judgement_label_base_position = judgement_label.position
	judgement_label.pivot_offset = judgement_label.size * 0.5
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()


# 使用音乐连续时间直接定位音符，不累计 delta；暂停时冻结，循环后沿现有时钟自然连续移动。
func set_music_timing(music_time: float, beat_duration: float, first_beat_offset: float, beats_per_bar: int) -> void:
	_music_time = music_time
	_beat_duration = beat_duration
	_first_beat_offset = first_beat_offset
	_beats_per_bar = maxi(beats_per_bar, 1)
	if _circle_enabled:
		queue_redraw()


# 保留圆圈设置枚举；关闭时隐藏整条线和音符，波形及共用判定文字仍按原流程工作。
func set_circle_enabled(enabled: bool) -> void:
	_circle_enabled = enabled
	queue_redraw()


# 拍点信号只更新小节文字，音符位置始终由连续音频时间决定，避免低帧率下漏拍后跳回。
func pulse_beat(beat_index: int, beats_per_bar: int) -> void:
	beat_label.text = "BEAT  %d/%d" % [beat_index % maxi(beats_per_bar, 1) + 1, maxi(beats_per_bar, 1)]


# 松手后只显示等级，不暴露毫秒偏差；动画只负责反馈，不推迟或更改已经完成的结算。
func show_judgement(result: Dictionary) -> void:
	var internal_grade_name: String = result.get("grade_name", "Miss")
	# 核心规则继续兼容内部Perfect键；玩家可见的三个平级结果统一为全大写文案。
	var grade_name := "MISS"
	match internal_grade_name.to_lower():
		"perfect", "great": grade_name = "GREAT"
		"good": grade_name = "GOOD"
	judgement_label.text = grade_name
	match grade_name:
		"GREAT": judgement_label.add_theme_color_override("font_color", GREAT_COLOR)
		"GOOD": judgement_label.add_theme_color_override("font_color", GOOD_COLOR)
		_: judgement_label.add_theme_color_override("font_color", MISS_COLOR)
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	if _judgement_glow_tween != null and _judgement_glow_tween.is_running():
		_judgement_glow_tween.kill()
	# 主色由字体主题控制，CanvasItem 调制只负责统一透明度，避免描边跟随主色染色。
	judgement_label.modulate = Color.WHITE
	judgement_label.position = _judgement_label_base_position
	judgement_label.scale = Vector2.ONE
	_judgement_effect_grade = grade_name
	# MISS 只保留文字和淡出，不启动任何图形或位移动画；GOOD/GREAT 才从圆心发射波形。
	_judgement_effect_age = 0.0 if grade_name != "MISS" else -1.0
	_configure_judgement_text_glow(grade_name)
	queue_redraw()
	_feedback_tween = create_tween()
	match grade_name:
		"GREAT":
			judgement_label.scale = Vector2(1.32, 1.32)
			_feedback_tween.tween_property(judgement_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"GOOD":
			judgement_label.scale = Vector2(1.16, 1.16)
			_feedback_tween.tween_property(judgement_label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_:
			pass
	_feedback_tween.parallel().tween_property(judgement_label, "modulate:a", 0.0, 0.28).set_delay(0.55)


# GOOD/GREAT 在正文外叠加一次扩张的彩色或绿色残影，形成贴附文字本体的闪光，而非替换节拍音符特效。
func _configure_judgement_text_glow(grade_name: String) -> void:
	if grade_name == "MISS":
		judgement_glow_label.hide()
		return
	judgement_glow_label.text = grade_name
	judgement_glow_label.position = _judgement_label_base_position
	judgement_glow_label.pivot_offset = judgement_glow_label.size * 0.5
	var glow_color := GOOD_COLOR if grade_name == "GOOD" else Color(0.35, 0.85, 1.0, 1.0)
	var outline_color := Color(0.08, 0.55, 0.22, 0.9) if grade_name == "GOOD" else Color(0.95, 0.22, 0.85, 0.92)
	judgement_glow_label.add_theme_color_override("font_color", glow_color)
	judgement_glow_label.add_theme_color_override("font_outline_color", outline_color)
	judgement_glow_label.modulate = Color(1.0, 1.0, 1.0, 0.92)
	judgement_glow_label.scale = Vector2.ONE
	judgement_glow_label.show()
	_judgement_glow_tween = create_tween()
	_judgement_glow_tween.set_parallel(true)
	_judgement_glow_tween.tween_property(judgement_glow_label, "scale", Vector2(1.22, 1.22), 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_judgement_glow_tween.tween_property(judgement_glow_label, "modulate:a", 0.0, 0.26).set_ease(Tween.EASE_IN)
	_judgement_glow_tween.tween_callback(judgement_glow_label.hide).set_delay(0.26)


# 特效包络只在评级出现后的短时间内重绘：GOOD/GREAT 从圆心外扩波形，MISS 不启动图形特效。
func _process(delta: float) -> void:
	if _judgement_effect_age < 0.0:
		return
	_judgement_effect_age += maxf(delta, 0.0)
	if _judgement_effect_age >= JUDGEMENT_EFFECT_SECONDS:
		_judgement_effect_age = -1.0
	queue_redraw()


# 仅生成视窗内音符；缩放围绕移动中的中心，不改变中心轨迹，大、小音符使用同一拍点包络。
func get_note_layout() -> Array[Dictionary]:
	var notes: Array[Dictionary] = []
	if size.x <= 0.0 or _beat_duration <= 0.0 or not is_finite(_beat_duration) or not is_finite(_music_time) or not is_finite(_first_beat_offset):
		return notes
	var phase := (_music_time - _first_beat_offset) / _beat_duration
	var spacing := size.x / VISIBLE_BEAT_SPAN
	var start_index := maxi(ceili(phase - VISIBLE_BEAT_SPAN * 0.5 - 1.0), 0)
	var end_index := floori(phase + VISIBLE_BEAT_SPAN * 0.5 + 1.0)
	for beat_index in range(start_index, end_index + 1):
		var is_first := posmod(beat_index, _beats_per_bar) == 0
		var base_size := FIRST_BEAT_SIZE if is_first else OTHER_BEAT_SIZE
		var note_scale := get_note_scale(beat_index)
		var note_size := base_size * note_scale
		var center := Vector2(size.x * 0.5 + (beat_index - phase) * spacing, size.y * 0.5)
		var rect := Rect2(center - note_size * 0.5, note_size)
		if rect.end.x <= 0.0 or rect.position.x >= size.x:
			continue
		notes.append({"beat_index": beat_index, "is_first": is_first, "base_size": base_size, "scale": note_scale, "rect": rect})
	return notes


# 到点时为最大尺寸，提前短促起峰、随后缓出缩回；不依赖信号或 Tween，掉帧与暂停不会漏触发或漂移。
func get_note_scale(beat_index: int) -> float:
	if beat_index < 0 or _beat_duration <= 0.0 or not is_finite(_beat_duration) or not is_finite(_music_time) or not is_finite(_first_beat_offset):
		return 1.0
	var signed_time := _music_time - (_first_beat_offset + beat_index * _beat_duration)
	var rise := minf(NOTE_RISE_SECONDS, _beat_duration * 0.2)
	var fall := minf(NOTE_FALL_SECONDS, _beat_duration * 0.3)
	var envelope := 0.0
	if signed_time < 0.0:
		envelope = smoothstep(-rise, 0.0, signed_time)
	else:
		envelope = pow(1.0 - clampf(signed_time / fall, 0.0, 1.0), 2.0)
	return lerpf(1.0, NOTE_PEAK_SCALE, envelope)


# 光圈按当前拍内进度扩张、淡出；前奏和无效拍长隐藏，暂停时音乐时间不变则效果自然冻结。
func get_pulse_visual() -> Dictionary:
	if _beat_duration <= 0.0 or not is_finite(_beat_duration) or not is_finite(_music_time) or not is_finite(_first_beat_offset) or _music_time < _first_beat_offset:
		return {"diameter": 56.0, "alpha": 0.0}
	var progress := fposmod(_music_time - _first_beat_offset, _beat_duration) / _beat_duration
	return {"diameter": lerpf(56.0, 94.0, progress), "alpha": pow(1.0 - progress, 0.9)}


# 参考图中心约 (470,741)，圈层半径约 34、54、72 源像素：以 0.48/0.75/1 比例重现三段。
# 每段内部纯色且半径边界明确，只整体改变透明度；不叠加柔光或连续径向渐变。
func get_pulse_bands() -> Array[Dictionary]:
	var bands: Array[Dictionary] = []
	var pulse := get_pulse_visual()
	if pulse.alpha <= 0.0:
		return bands
	var radius: float = pulse.diameter * 0.5
	# 提高分段底色的不透明度，减少背景穿透；仍保持外暗内亮及整圈随拍淡出的层次。
	bands.append({"inner_radius": radius * 0.75, "outer_radius": radius, "color": Color(0.86, 0.38, 0.18, 0.45 * pulse.alpha)})
	bands.append({"inner_radius": radius * 0.48, "outer_radius": radius * 0.75, "color": Color(1.0, 0.48, 0.2, 0.65 * pulse.alpha)})
	bands.append({"inner_radius": 0.0, "outer_radius": radius * 0.48, "color": Color(1.0, 0.63, 0.31, 0.78 * pulse.alpha)})
	return bands


# 背景线仅绘制一次并铺满宽度；两端音符按纹理区域裁切，不缩挤图片或影响中央拍点位置。
func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_judgement_effect()
	if not _circle_enabled:
		return
	var center := size * 0.5
	# 先绘制分段色带，再画基准线和音符；仅轮廓抗锯齿，不模糊圈层内部边界。
	for band in get_pulse_bands():
		var inner: float = band.inner_radius
		var outer: float = band.outer_radius
		if inner <= 0.0:
			draw_circle(center, outer, band.color, true, -1.0, true)
		else:
			draw_arc(center, (inner + outer) * 0.5, 0, TAU, 128, band.color, outer - inner, true)
	var line_height := size.x * BEAT_LINE.get_height() / float(BEAT_LINE.get_width())
	draw_texture_rect(BEAT_LINE, Rect2(0, (size.y - line_height) * 0.5, size.x, line_height), false)
	# 柔和外沿与亮色内芯作为固定判定基准；置于音符后方，不遮挡音符本体。
	var start := center - Vector2(0, TARGET_LINE_HEIGHT * 0.5)
	var end := center + Vector2(0, TARGET_LINE_HEIGHT * 0.5)
	draw_line(start, end, Color(1, 0.48, 0.14, 0.3), 8.0, true)
	draw_line(start, end, TARGET_LINE_COLOR, 2.5, true)
	for note in get_note_layout():
		var texture: Texture2D = FIRST_BEAT if note.is_first else OTHER_BEAT
		var rect: Rect2 = note.rect
		var clipped := rect.intersection(Rect2(Vector2.ZERO, size))
		var source_rect := Rect2((clipped.position - rect.position) / rect.size * texture.get_size(), clipped.size / rect.size * texture.get_size())
		draw_texture_rect_region(texture, clipped, source_rect)


# 评级特效仅使用基础绘制 API：GOOD 为绿色外扩波形，GREAT 为彩色外扩波形；MISS 完全不绘制。
func _draw_judgement_effect() -> void:
	if _judgement_effect_age < 0.0:
		return
	var progress := clampf(_judgement_effect_age / JUDGEMENT_EFFECT_SECONDS, 0.0, 1.0)
	var alpha := pow(1.0 - progress, 1.6)
	var center := size * 0.5
	match _judgement_effect_grade:
		"GREAT":
			var radius := lerpf(12.0, 70.0, progress)
			for ray_index in range(JUDGEMENT_WAVE_BAR_COUNT):
				var angle := float(ray_index) * TAU / float(JUDGEMENT_WAVE_BAR_COUNT)
				var direction := Vector2(cos(angle), sin(angle))
				var waveform := 0.35 + 0.65 * absf(sin(angle * 3.0 + progress * TAU * 2.0))
				var hue := fposmod(float(ray_index) / float(JUDGEMENT_WAVE_BAR_COUNT) + progress * 0.2, 1.0)
				var color := Color.from_hsv(hue, 0.8, 1.0, alpha * 0.94)
				draw_line(center + direction * radius, center + direction * (radius + 9.0 + waveform * 19.0), color, 3.0, true)
		"GOOD":
			var good_radius := lerpf(10.0, 58.0, progress)
			for ray_index in range(18):
				var angle := float(ray_index) * TAU / 18.0
				var direction := Vector2(cos(angle), sin(angle))
				var waveform := 0.45 + 0.55 * absf(sin(angle * 2.0 - progress * TAU * 1.5))
				draw_line(center + direction * good_radius, center + direction * (good_radius + 7.0 + waveform * 13.0), Color(GOOD_COLOR, alpha * 0.88), 2.6, true)
		_:
			pass
