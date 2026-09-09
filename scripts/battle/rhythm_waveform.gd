# 战斗中央节奏波形：用蓝青渐变竖条在每个拍点上下起峰，再缓慢衰减归零。
class_name RhythmWaveform
extends Control

const BAR_COUNT := 72
const ATTACK_SECONDS := 0.045
const RELEASE_SECONDS := 0.48
const EDGE_COLOR := Color(0.25, 0.36, 0.78, 0.72)
const CENTER_COLOR := Color(0.28, 0.92, 0.92, 0.94)

var _pulse_age := -1.0
var _visual_amplitude := 0.0
var _bar_heights := PackedFloat32Array()
var _shape_rng := RandomNumberGenerator.new()


# 控件只负责装饰性绘制，必须让鼠标和触摸穿透到卡牌交互层。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 波形使用独立随机源，不能消耗战斗控制器用于抽牌、敌人和效果结算的随机序列。
	_shape_rng.randomize()
	_generate_wave_shape()
	queue_redraw()


# 单次包络先快速起峰、再慢速归零；归零后停止重绘，下一拍到来前保持完全静止。
func _process(delta: float) -> void:
	if _pulse_age < 0.0:
		return
	_pulse_age += maxf(delta, 0.0)
	if _pulse_age <= ATTACK_SECONDS:
		var attack_progress := clampf(_pulse_age / ATTACK_SECONDS, 0.0, 1.0)
		# 三次缓出让首帧便明显扩张，同时保留极短的起峰过程而非瞬间跳变。
		_visual_amplitude = 1.0 - pow(1.0 - attack_progress, 3.0)
	else:
		var release_progress := clampf((_pulse_age - ATTACK_SECONDS) / RELEASE_SECONDS, 0.0, 1.0)
		# 二次缓出使峰值后的回落先快后慢，并在结束点严格归零。
		_visual_amplitude = pow(1.0 - release_progress, 2.0)
		if release_progress >= 1.0:
			_visual_amplitude = 0.0
			_pulse_age = -1.0
	queue_redraw()


# 新拍无条件重启包络；即使上一拍尚未完全衰减，也从零开始一次清晰的新起峰。
func pulse_beat() -> void:
	_pulse_age = 0.0
	_visual_amplitude = 0.0
	_generate_wave_shape()
	queue_redraw()


# 每根细竖条从中心线同时向上下展开；固定采样形状保证动画只改变振幅而不会随机抖动。
func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var center_y: float = size.y * 0.5
	var spacing: float = size.x / float(BAR_COUNT)
	var bar_width: float = maxf(spacing * 0.42, 1.0)
	for bar_index in range(BAR_COUNT):
		var normalized_x: float = (float(bar_index) + 0.5) / float(BAR_COUNT)
		var shape_amplitude: float = _bar_heights[bar_index] if bar_index < _bar_heights.size() else 0.0
		var half_height: float = shape_amplitude * size.y * 0.47 * _visual_amplitude
		var center_weight: float = 1.0 - absf(normalized_x * 2.0 - 1.0)
		var color := EDGE_COLOR.lerp(CENTER_COLOR, center_weight)
		# 静止时保留极淡的单像素中心痕迹；可见波形高度仍严格归零。
		color.a *= 0.18 + _visual_amplitude * 0.82
		draw_line(
			Vector2((float(bar_index) + 0.5) * spacing, center_y - half_height),
			Vector2((float(bar_index) + 0.5) * spacing, center_y + half_height),
			color,
			bar_width,
			true
		)


# 每拍生成一组新高度：主峰限定在中间区域，左右设低上限，最高点位置因此可变但不会跑到边缘。
func _generate_wave_shape() -> void:
	_bar_heights.resize(BAR_COUNT)
	var main_peak_position := _shape_rng.randf_range(0.36, 0.64)
	var main_peak_width := _shape_rng.randf_range(0.1, 0.18)
	var secondary_peak_position := _shape_rng.randf_range(0.3, 0.7)
	var secondary_peak_width := _shape_rng.randf_range(0.06, 0.13)
	var secondary_strength := _shape_rng.randf_range(0.22, 0.42)
	var detail_phase := _shape_rng.randf_range(0.0, TAU)
	var detail_frequency := _shape_rng.randf_range(5.0, 9.0)
	for bar_index in range(BAR_COUNT):
		var normalized_x := (float(bar_index) + 0.5) / float(BAR_COUNT)
		var edge_envelope := pow(sin(normalized_x * PI), 0.85)
		var main_distance := (normalized_x - main_peak_position) / main_peak_width
		var secondary_distance := (normalized_x - secondary_peak_position) / secondary_peak_width
		var main_peak := exp(-main_distance * main_distance)
		var secondary_peak := exp(-secondary_distance * secondary_distance) * secondary_strength
		var detail := 0.82 + 0.18 * absf(sin(normalized_x * TAU * detail_frequency + detail_phase))
		var height := edge_envelope * (0.16 + main_peak * 0.78 + secondary_peak) * detail
		# 两侧允许保留小峰，但整体高度不得压过中部主峰。
		if normalized_x < 0.28 or normalized_x > 0.72:
			height = minf(height, 0.48 * edge_envelope)
		_bar_heights[bar_index] = clampf(height, 0.0, 0.96)
	# 强制随机主峰对应的竖条成为全局最高点，避免细节波在数值边界上意外抢峰。
	var main_peak_index := clampi(roundi(main_peak_position * float(BAR_COUNT) - 0.5), 0, BAR_COUNT - 1)
	_bar_heights[main_peak_index] = 1.0
