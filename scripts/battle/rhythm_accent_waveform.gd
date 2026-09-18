# 卡牌上方装饰波形：暖橙分段柱随音乐拍点起伏；只负责绘制，不读取音频振幅或参与判定与随机结算。
extends Control

const BAR_COUNT := 43
const SEGMENT_HEIGHT := 2.0
const SEGMENT_GAP := 1.0
var _music_time := 0.0
var _beat_duration := 0.6
var _first_beat_offset := 0.0

# 鼠标与触摸穿透，暂停遵循战斗场景；既不截获拖牌，也不改变原波形模式脚本。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# 表现直接读取连续音乐时间，避免切回圆圈时重启动画或暂停后相位漂移。
func set_music_timing(music_time: float, beat_duration: float, first_beat_offset: float) -> void:
	_music_time = music_time
	_beat_duration = beat_duration
	_first_beat_offset = first_beat_offset
	if visible:
		queue_redraw()

# 中部较高、两侧逐渐衰减；确定性变化不消耗正式随机流，前奏与非法时钟安全返回空波形。
func get_bar_heights() -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	if _beat_duration <= 0.0 or not is_finite(_beat_duration) or not is_finite(_music_time) or not is_finite(_first_beat_offset) or _music_time < _first_beat_offset:
		return heights
	var phase := (_music_time - _first_beat_offset) / _beat_duration
	var progress := fposmod(phase, 1.0)
	var amplitude := 0.3 + 0.7 * pow(1.0 - progress, 1.5)
	for index in range(BAR_COUNT):
		var x := (index + 0.5) / BAR_COUNT
		var envelope := pow(sin(x * PI), 1.4)
		var detail := 0.35 + 0.65 * absf(sin(index * 1.7 + phase * 2.0))
		var height := envelope * detail * amplitude
		if index == BAR_COUNT / 2:
			height = amplitude
		heights.append(height)
	return heights

# 分段竖柱从统一底边向上生长，暖橙到金黄按高度过渡，完整限制在卡牌上方专用区域。
func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var heights := get_bar_heights()
	var step := size.x / BAR_COUNT
	var bar_width := maxf(step - 2.0, 1.0)
	for index in range(heights.size()):
		var height := heights[index] * size.y
		var segment_count := floori(height / (SEGMENT_HEIGHT + SEGMENT_GAP))
		for segment in range(segment_count):
			var y := size.y - SEGMENT_HEIGHT - segment * (SEGMENT_HEIGHT + SEGMENT_GAP)
			var color := Color(1, 0.28, 0.1, 0.45).lerp(Color(1, 0.8, 0.28, 0.95), segment / maxf(size.y / 3.0, 1.0))
			draw_rect(Rect2(index * step + 1.0, y, bar_width, SEGMENT_HEIGHT), color)
