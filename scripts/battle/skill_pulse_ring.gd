# 连击技能节拍环：仅在技能可释放时围绕按钮绘制短促波条，并由真实音乐拍点驱动。
class_name SkillPulseRing
extends Control

const BAR_COUNT := 16
const ATTACK_SECONDS := 0.05
const RELEASE_SECONDS := 0.34
const BASE_COLOR := Color(1.0, 0.72, 0.22, 0.3)
const PEAK_COLOR := Color(1.0, 0.39, 0.08, 0.96)

var _ready_to_activate := false
var _pulse_age := -1.0
var _visual_amplitude := 0.0


# 波形环是纯表现层，不能遮挡按钮点击；初始隐藏以免未攒满连击时制造错误提示。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()


# 可释放状态由战斗界面统一结算；失效时立即停止重绘和缩放关联的视觉残影。
func set_skill_ready(is_ready: bool) -> void:
	_ready_to_activate = is_ready
	visible = is_ready
	if not is_ready:
		_pulse_age = -1.0
		_visual_amplitude = 0.0
	queue_redraw()


# 每个真实拍点重新起峰，按钮未激活时不产生任何装饰性动画。
func pulse_beat() -> void:
	if not _ready_to_activate:
		return
	_pulse_age = 0.0
	_visual_amplitude = 0.0
	queue_redraw()


# 包络与中央节奏波形一致：短促放大后自然回落，归零时停止逐帧重绘。
func _process(delta: float) -> void:
	if _pulse_age < 0.0:
		return
	_pulse_age += maxf(delta, 0.0)
	if _pulse_age <= ATTACK_SECONDS:
		var attack_progress := clampf(_pulse_age / ATTACK_SECONDS, 0.0, 1.0)
		_visual_amplitude = 1.0 - pow(1.0 - attack_progress, 3.0)
	else:
		var release_progress := clampf((_pulse_age - ATTACK_SECONDS) / RELEASE_SECONDS, 0.0, 1.0)
		_visual_amplitude = pow(1.0 - release_progress, 2.0)
		if release_progress >= 1.0:
			_visual_amplitude = 0.0
			_pulse_age = -1.0
	queue_redraw()


# 以环形短条模拟卡牌上方波形，峰值时外扩更长；尺寸由场景节点决定，方便在编辑器单独调整。
func _draw() -> void:
	if not _ready_to_activate or size.x <= 1.0 or size.y <= 1.0:
		return
	var center := size * 0.5
	var base_radius := minf(size.x, size.y) * 0.33
	for bar_index in range(BAR_COUNT):
		var normalized_index := float(bar_index) / float(BAR_COUNT)
		var angle := normalized_index * TAU - PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var wave_detail := 0.5 + 0.5 * sin(angle * 3.0 + 0.8)
		var bar_length := 2.0 + (4.0 + wave_detail * 7.0) * _visual_amplitude
		var color := BASE_COLOR.lerp(PEAK_COLOR, _visual_amplitude)
		draw_line(
			center + direction * base_radius,
			center + direction * (base_radius + bar_length),
			color,
			1.6 + _visual_amplitude,
			true
		)
