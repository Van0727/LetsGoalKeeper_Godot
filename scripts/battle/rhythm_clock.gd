# 战斗节拍时钟：以音频播放头为唯一时间基准，提供可测试的拍点位置与出牌准确度判定。
# BGM 文件统一存放在 sound/bgm，并以“名称_bpm数值”标记速度，例如 bg_basicDrum2_bpm100.mp3；运行时优先读取该值。
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
# 首拍偏移对齐曲目实际起音，不是设备校准；基础鼓点经离线解码测得约 25ms，由战斗场景配置。
# 判定、音符移动、缩放和光圈统一使用此值，禁止只平移 UI 导致视觉与判定不一致。
@export_range(0.0, 60.0, 0.001) var first_beat_offset := 0.0
@export_range(1, 16, 1) var beats_per_bar := 4
# 节奏细分使用全音符分母表达：4 为四分音符、8 为八分音符，奖励品据此判断“1/8和更快”。
@export_range(1, 64, 1) var rhythm_subdivision := 4
@export_range(1.0, 500.0, 1.0) var perfect_window_ms := 60.0
@export_range(1.0, 500.0, 1.0) var good_window_ms := 140.0
# 正值会把判定时间向后移动，供后续设置页补偿设备与玩家的稳定输入偏移。
@export_range(-500.0, 500.0, 1.0) var calibration_offset_ms := 0.0

var _audio_player: AudioStreamPlayer
var _uses_external_player := false
var _last_emitted_beat := -1
var _last_music_time := 0.0
var _last_raw_music_time := 0.0
var _music_loop_offset := 0.0


# 运行时创建播放器并固定接入 Music 总线，避免节拍算法依赖场景结构，
# 同时保证设置页的音乐音量只影响背景音乐；测试仍可不播放音乐而直接调用 judge_at。
func _ready() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "MusicPlayer"
	_audio_player.bus = "Music"
	add_child(_audio_player)
	_sync_bpm_from_music_name()


# 常驻 BGM 服务接管战斗曲时绑定其播放头；独立测试仍沿用本地播放器。
func start_music_with_player(player: AudioStreamPlayer) -> bool:
	if player == null or music == null:
		return false
	_audio_player = player
	_uses_external_player = true
	_sync_bpm_from_music_name()
	_last_emitted_beat = -1
	_last_music_time = 0.0
	_last_raw_music_time = 0.0
	_music_loop_offset = 0.0
	return _audio_player.playing


# 每帧只检测是否跨过新拍点；信号供表现层使用，实际判定始终直接查询音频时间。
func _process(_delta: float) -> void:
	if not is_music_playing():
		return
	var music_time := get_music_time()
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
	if _uses_external_player:
		return start_music_with_player(_audio_player)
	# 每次换曲后重新读取文件名，保证卡牌拍数始终跟随当前 BGM，而不是旧场景中的手填数值。
	_sync_bpm_from_music_name()
	var runtime_stream := music.duplicate() as AudioStream
	var mp3_stream := runtime_stream as AudioStreamMP3
	if mp3_stream != null:
		mp3_stream.loop = true
	_audio_player.stream = runtime_stream
	_last_emitted_beat = -1
	_last_music_time = 0.0
	_last_raw_music_time = 0.0
	_music_loop_offset = 0.0
	_audio_player.play()
	return true


# 战斗结束时停止音乐并清理拍点状态，下一场战斗从第一拍重新开始。
func stop_music() -> void:
	if _audio_player != null and not _uses_external_player:
		_audio_player.stop()
	_last_emitted_beat = -1
	_last_music_time = 0.0
	_last_raw_music_time = 0.0
	_music_loop_offset = 0.0


# 暴露播放状态供界面与测试确认，不泄漏内部播放器引用。
func is_music_playing() -> bool:
	return _audio_player != null and _audio_player.playing


# 组合 Godot 音频播放头、混音间隔和输出延迟，并把循环后的归零位置扩展为连续时间轴。
# 飞球跨越 BGM 循环边界时仍能抵达未来目标拍点，不会因播放头回绕而卡住。
func get_music_time() -> float:
	if not is_music_playing():
		return 0.0
	var raw_music_time := maxf((
		_audio_player.get_playback_position()
		+ AudioServer.get_time_since_last_mix()
		- AudioServer.get_output_latency()
		+ calibration_offset_ms / 1000.0
	), 0.0)
	var stream_length := music.get_length() if music != null else 0.0
	if did_playback_wrap(_last_raw_music_time, raw_music_time, stream_length):
		# MP3 的资源长度可能包含编码填充；每轮只累计整数拍时长，防止循环次数越多拍点越漂。
		var quantized_loop_duration := get_quantized_loop_duration(stream_length, bpm)
		_music_loop_offset += (
			quantized_loop_duration
			if quantized_loop_duration > 0.0
			else maxf(stream_length, _last_raw_music_time)
		)
	_last_raw_music_time = raw_music_time
	# 官方音频同步建议丢弃线程抖动产生的倒退值；保持单调时间可防止QTE音符瞬间回弹。
	var continuous_time := _music_loop_offset + raw_music_time
	_last_music_time = maxf(continuous_time, _last_music_time)
	return _last_music_time


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
		# 同时保留输入采样时间和最近拍点，攻击表现据此补偿延迟帧并锁定未来命中拍点。
		"music_time": music_time,
		"target_time": target_time,
		"beat_index": beat_index,
		"bar_index": floori(beat_index / float(maxi(beats_per_bar, 1))),
		"beat_in_bar": posmod(beat_index, maxi(beats_per_bar, 1)),
		"subdivision": rhythm_subdivision,
	}


# 返回单拍秒数；导出范围已经阻止零 BPM，这里仍保留下限以保护运行时脚本赋值。
func get_beat_duration() -> float:
	return 60.0 / maxf(bpm, 1.0)


# 所有卡牌表现统一通过这里把拍数换算为秒，避免飞行和多段间隔各自维护 BPM 公式。
func beats_to_seconds(beat_count: float) -> float:
	return maxf(beat_count, 0.0) * get_beat_duration()


# 返回严格晚于采样时刻的下一个整数拍，供QTE等玩法把整组事件锚定到真实BGM拍点。
func get_next_beat_time(music_time: float = -1.0) -> float:
	var active_time := get_music_time() if music_time < 0.0 else music_time
	var beat_duration := get_beat_duration()
	var relative_time := active_time - first_beat_offset
	var next_beat_index := floori(relative_time / beat_duration) + 1
	return first_beat_offset + maxi(next_beat_index, 0) * beat_duration


# 只有明确跨越大半首歌，或上一采样位于曲尾且新采样位于曲首，才视为真实循环。
static func did_playback_wrap(previous_time: float, current_time: float, stream_length: float) -> bool:
	if stream_length <= 0.0 or current_time >= previous_time:
		return false
	return (
		(previous_time >= stream_length * 0.75 and current_time <= stream_length * 0.25)
		or previous_time - current_time > stream_length * 0.5
	)


# 把一轮音频长度吸附到最接近的整数拍，避免 MP3 尾部填充被逐轮累计到节拍时间轴。
static func get_quantized_loop_duration(stream_length: float, music_bpm: float) -> float:
	if stream_length <= 0.0 or music_bpm <= 0.0:
		return 0.0
	var beat_duration := 60.0 / music_bpm
	var beat_count := maxi(roundi(stream_length / beat_duration), 1)
	return beat_count * beat_duration


# 从资源文件名末尾的“_bpm数值”读取速度；未遵守命名约定时保留导出的后备 BPM。
func _sync_bpm_from_music_name() -> bool:
	if music == null:
		return false
	var detected_bpm := get_bpm_from_music_path(music.resource_path)
	if detected_bpm <= 0.0:
		push_warning("BGM 文件名未包含有效 BPM，继续使用配置值 %.1f：%s" % [bpm, music.resource_path])
		return false
	bpm = detected_bpm
	return true


# 纯函数供测试验证命名契约；支持整数或小数 BPM，且不依赖音频资源是否完成导入。
static func get_bpm_from_music_path(path: String) -> float:
	var pattern := RegEx.new()
	if pattern.compile("(?i)_bpm([0-9]+(?:\\.[0-9]+)?)(?:\\.[^.]+)?$") != OK:
		return -1.0
	var matched := pattern.search(path.get_file())
	if matched == null:
		return -1.0
	return float(matched.get_string(1))


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
