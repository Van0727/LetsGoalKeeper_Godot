# 战斗节拍时钟：以音频播放头为唯一时间基准，提供可测试的拍点位置与出牌准确度判定。
class_name RhythmClock
extends Node

signal beat_reached(beat_index: int, bar_index: int)

enum JudgementGrade {
	PERFECT,
	GOOD,
	MISS,
}

@export var music: AudioStream
@export_range(20.0, 300.0, 0.1) var bpm := 100.0
@export_range(0.0, 60.0, 0.001) var first_beat_offset := 0.0
@export_range(1, 16, 1) var beats_per_bar := 4
@export_range(1.0, 500.0, 1.0) var perfect_window_ms := 60.0
@export_range(1.0, 500.0, 1.0) var good_window_ms := 140.0
# 正值会把判定时间向后移动，供后续设置页补偿设备与玩家的稳定输入偏移。
@export_range(-500.0, 500.0, 1.0) var calibration_offset_ms := 0.0

var _audio_player: AudioStreamPlayer
var _last_emitted_beat := -1
var _last_music_time := 0.0


# 运行时创建播放器，避免节拍算法依赖场景结构；测试可以不播放音乐而直接调用 judge_at。
func _ready() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "MusicPlayer"
	add_child(_audio_player)


# 每帧只检测是否跨过新拍点；信号供表现层使用，实际判定始终直接查询音频时间。
func _process(_delta: float) -> void:
	if not is_music_playing():
		return
	var music_time := get_music_time()
	# 循环回到音频开头时重新允许发送拍点序号，避免第二轮音乐没有 UI 脉冲。
	if music_time + 0.05 < _last_music_time:
		_last_emitted_beat = -1
	_last_music_time = music_time
	var beat_index := get_current_beat_index(music_time)
	if beat_index < 0 or beat_index == _last_emitted_beat:
		return
	_last_emitted_beat = beat_index
	beat_reached.emit(beat_index, floori(beat_index / float(maxi(beats_per_bar, 1))))


# 从头循环播放配置音乐；复制流资源，避免修改预载资源本身的循环属性。
func start_music() -> bool:
	if music == null or _audio_player == null:
		return false
	var runtime_stream := music.duplicate() as AudioStream
	var mp3_stream := runtime_stream as AudioStreamMP3
	if mp3_stream != null:
		mp3_stream.loop = true
	_audio_player.stream = runtime_stream
	_last_emitted_beat = -1
	_last_music_time = 0.0
	_audio_player.play()
	return true


# 战斗结束时停止音乐并清理拍点状态，下一场战斗从第一拍重新开始。
func stop_music() -> void:
	if _audio_player != null:
		_audio_player.stop()
	_last_emitted_beat = -1
	_last_music_time = 0.0


# 暴露播放状态供界面与测试确认，不泄漏内部播放器引用。
func is_music_playing() -> bool:
	return _audio_player != null and _audio_player.playing


# 组合 Godot 音频播放头、混音间隔和输出延迟，降低帧率与音频缓冲造成的判定漂移。
func get_music_time() -> float:
	if not is_music_playing():
		return 0.0
	var compensated_time := (
		_audio_player.get_playback_position()
		+ AudioServer.get_time_since_last_mix()
		- AudioServer.get_output_latency()
		+ calibration_offset_ms / 1000.0
	)
	return maxf(compensated_time, 0.0)


# 在真实松手回调中即时采样播放头，返回本次出牌可长期扩展的结构化节奏上下文。
func judge_now() -> Dictionary:
	return judge_at(get_music_time())


# 纯逻辑判定接口：寻找最近四分音符拍点，并同时接受等距离的提前与延后输入。
func judge_at(music_time: float) -> Dictionary:
	var beat_duration := get_beat_duration()
	var relative_time := music_time - first_beat_offset
	var beat_index := maxi(roundi(relative_time / beat_duration), 0)
	var target_time := first_beat_offset + beat_index * beat_duration
	var signed_error_ms := (music_time - target_time) * 1000.0
	var absolute_error_ms := absf(signed_error_ms)
	var grade := JudgementGrade.MISS
	var multiplier := 0.5
	if absolute_error_ms <= perfect_window_ms:
		grade = JudgementGrade.PERFECT
		multiplier = 1.0
	elif absolute_error_ms <= good_window_ms:
		grade = JudgementGrade.GOOD
		multiplier = 1.0
	return {
		"grade": grade,
		"grade_name": get_grade_name(grade),
		"error_ms": signed_error_ms,
		"absolute_error_ms": absolute_error_ms,
		"effect_multiplier": multiplier,
		"beat_index": beat_index,
		"bar_index": floori(beat_index / float(maxi(beats_per_bar, 1))),
	}


# 返回单拍秒数；导出范围已经阻止零 BPM，这里仍保留下限以保护运行时脚本赋值。
func get_beat_duration() -> float:
	return 60.0 / maxf(bpm, 1.0)


# 返回当前已经进入的拍点序号；首拍之前返回 -1，避免提前触发第一个 UI 脉冲。
func get_current_beat_index(music_time: float = -1.0) -> int:
	var active_time := get_music_time() if music_time < 0.0 else music_time
	var relative_time := active_time - first_beat_offset
	if relative_time < 0.0:
		return -1
	return floori(relative_time / get_beat_duration())


# 返回 0～1 的拍内进度，供视觉环读取；进度只用于提示，不参与准确度判定。
func get_beat_progress(music_time: float = -1.0) -> float:
	var active_time := get_music_time() if music_time < 0.0 else music_time
	var relative_time := active_time - first_beat_offset
	if relative_time < 0.0:
		return clampf(active_time / maxf(first_beat_offset, 0.001), 0.0, 1.0)
	return fposmod(relative_time, get_beat_duration()) / get_beat_duration()


# 统一等级文字，避免战斗界面复制枚举到中文显示的映射。
func get_grade_name(grade: int) -> String:
	match grade:
		JudgementGrade.PERFECT:
			return "Perfect"
		JudgementGrade.GOOD:
			return "Good"
		_:
			return "Miss"
