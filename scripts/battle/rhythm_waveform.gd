# 战斗中央节奏波形：每个拍点快速向上下起峰，再缓慢衰减归零，强化鼓点但不参与判定。
class_name RhythmWaveform
extends Control

const SAMPLE_COUNT := 56
const ATTACK_SECONDS := 0.045
const RELEASE_SECONDS := 0.48
const LAYER_COLORS := [
	Color(1.0, 0.08, 0.88, 0.72),
	Color(0.33, 0.78, 1.0, 0.58),
	Color(0.78, 0.42, 1.0, 0.38),
]

var _pulse_age := -1.0
var _visual_amplitude := 0.0


# 控件只负责装饰性绘制，必须让鼠标和触摸穿透到卡牌交互层。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	queue_redraw()


# 三层曲面采用不同相位与上下比例，形成粉、蓝、紫相互穿插的镜像波形。
func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var center_y: float = size.y * 0.5
	for layer_index in range(LAYER_COLORS.size() - 1, -1, -1):
		_draw_wave_layer(layer_index, center_y, _visual_amplitude)
	var glow_alpha: float = 0.18 + _visual_amplitude * 0.4
	draw_line(
		Vector2(0.0, center_y),
		Vector2(size.x, center_y),
		Color(1.0, 0.86, 1.0, glow_alpha),
		1.0 + _visual_amplitude * 2.0,
		true
	)


# 每层由上、下两条采样曲线闭合；振幅为零时曲面严格收束到中央水平线。
func _draw_wave_layer(layer_index: int, center_y: float, pulse_amplitude: float) -> void:
	var points := PackedVector2Array()
	var phase: float = float(layer_index) * 1.73
	var layer_scale: float = [1.0, 0.72, 0.52][layer_index]
	for sample_index in range(SAMPLE_COUNT + 1):
		var normalized_x: float = float(sample_index) / float(SAMPLE_COUNT)
		var amplitude: float = _sample_amplitude(normalized_x, phase)
		points.append(Vector2(
			normalized_x * size.x,
			center_y - amplitude * size.y * 0.42 * layer_scale * pulse_amplitude
		))
	for sample_index in range(SAMPLE_COUNT, -1, -1):
		var normalized_x: float = float(sample_index) / float(SAMPLE_COUNT)
		var amplitude: float = _sample_amplitude(normalized_x, phase + 0.86)
		points.append(Vector2(
			normalized_x * size.x,
			center_y + amplitude * size.y * 0.34 * layer_scale * pulse_amplitude
		))
	var color: Color = LAYER_COLORS[layer_index]
	color.a = minf(color.a + pulse_amplitude * 0.16, 0.92)
	draw_colored_polygon(points, color)


# 平滑包络叠加低频和高频谐波，避免随机数导致逐帧跳变，同时保留不规则音乐波峰。
func _sample_amplitude(normalized_x: float, phase: float) -> float:
	var envelope: float = pow(sin(clampf(normalized_x, 0.0, 1.0) * PI), 1.35)
	var primary: float = absf(sin(normalized_x * TAU * 2.35 + phase))
	var detail: float = absf(sin(normalized_x * TAU * 5.2 - phase * 0.7))
	return envelope * (0.28 + primary * 0.57 + detail * 0.15)
