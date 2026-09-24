# 全局背景音乐服务：在场景切换期间保留非战斗 BGM，并负责进入战斗前的切曲音效顺序。
extends Node

signal main_beat_reached(beat_index: int)
signal game_win_audio_finished

const MAIN_BGM := preload("res://sound/bgm/bg_main_bpm110.mp3")
const CHANGE_BGM_SFX := preload("res://sound/sounds/changeBgm.mp3")
const BACK_MAP_SFX := preload("res://sound/sounds/backmap.mp3")
const GAME_WIN_SFX := preload("res://sound/sounds/gamewin.mp3")
const BATTLE_SCENE_PATH := "res://scenes/battle.tscn"
const MAIN_BGM_BPM := 110.0
const BATTLE_BGM_SILENT_DB := -80.0
const BATTLE_BGM_FADE_IN_SECONDS := 0.45

var _main_player: AudioStreamPlayer
var _battle_player: AudioStreamPlayer
var _transition_player: AudioStreamPlayer
var _game_win_player: AudioStreamPlayer
var _battle_transition_ready := false
var _last_main_beat := -1
var _last_main_music_time := 0.0
var _last_main_raw_time := 0.0
var _main_loop_offset := 0.0
var _output_latency := 0.0
var _battle_pitch_semitones := 0
var _battle_volume_tween: Tween


# 常驻播放器分别承载循环 BGM 与一次性切曲音效，避免场景销毁导致切换音效中断。
func _ready() -> void:
	# 胜利音效后的 BGM 渐显属于全局音频状态；暂停层打开时也必须继续完成恢复。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main_player = AudioStreamPlayer.new()
	_main_player.name = "MainBgmPlayer"
	# 运行时复制后开启循环，不修改预载资源，且主菜单曲能在任意非战斗界面持续播放。
	var runtime_main_bgm := MAIN_BGM.duplicate() as AudioStream
	var main_mp3_stream := runtime_main_bgm as AudioStreamMP3
	if main_mp3_stream != null:
		main_mp3_stream.loop = true
	_main_player.stream = runtime_main_bgm
	_main_player.bus = &"Music"
	_main_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_main_player)
	_battle_player = AudioStreamPlayer.new()
	_battle_player.name = "BattleBgmPlayer"
	_battle_player.bus = &"Music"
	# 战斗暂停时仍持续输出，设置覆盖层关闭后节拍时钟可从同一播放头继续判定。
	_battle_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_battle_player)
	_transition_player = AudioStreamPlayer.new()
	_transition_player.name = "ChangeBgmPlayer"
	_transition_player.stream = CHANGE_BGM_SFX
	_transition_player.bus = &"SFX"
	# 暂停菜单确认返回主菜单时仍要完整播放切曲音效，不能随玩法树暂停。
	_transition_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_transition_player)
	# 胜利音效跨越战斗、结算和奖励场景；由全局服务持有才不会被领取奖励的场景切换截断。
	_game_win_player = AudioStreamPlayer.new()
	_game_win_player.name = "GameWinAudio"
	_game_win_player.stream = GAME_WIN_SFX
	_game_win_player.bus = &"SFX"
	_game_win_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_game_win_player.finished.connect(_on_game_win_audio_finished)
	add_child(_game_win_player)
	# 输出延迟在设备运行期间通常稳定；只读取一次，避免每帧查询音频驱动。
	_output_latency = AudioServer.get_output_latency()
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed()


# 主界面表现使用真实音乐播放头触发节拍，避免普通定时器在长时间循环后逐渐漂拍。
func _process(_delta: float) -> void:
	if _main_player == null or not _main_player.playing or _main_player.stream_paused:
		return
	var raw_time := maxf(
		_main_player.get_playback_position()
		+ AudioServer.get_time_since_last_mix()
		- _output_latency,
		0.0
	)
	var stream_length := _main_player.stream.get_length() if _main_player.stream != null else 0.0
	if (
		stream_length > 0.0
		and raw_time < _last_main_raw_time
		and _last_main_raw_time >= stream_length * 0.75
		and raw_time <= stream_length * 0.25
	):
		# MP3 可能包含编码填充，以完整拍数累计循环时长可抑制多轮播放后的拍点漂移。
		var beat_duration := 60.0 / MAIN_BGM_BPM
		var beat_count := maxi(roundi(stream_length / beat_duration), 1)
		_main_loop_offset += beat_count * beat_duration
	_last_main_raw_time = raw_time
	var music_time := maxf(_main_loop_offset + raw_time, _last_main_music_time)
	_last_main_music_time = music_time
	var beat_index := floori(music_time / (60.0 / MAIN_BGM_BPM))
	if beat_index == _last_main_beat:
		return
	_last_main_beat = beat_index
	main_beat_reached.emit(beat_index)


# 所有非战斗界面共享主菜单曲；战斗胜利后的奖励页保留战斗曲，直到实际触发切曲。
func _on_scene_changed() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null or scene_root.scene_file_path == BATTLE_SCENE_PATH:
		return
	if _battle_player != null and _battle_player.playing:
		return
	play_main_bgm()


# 非战斗 BGM 始终从上次位置继续；首次进入或被战斗切换停止后则从头开始循环。
func play_main_bgm() -> void:
	if _main_player == null:
		return
	_main_player.stream_paused = false
	if not _main_player.playing:
		_reset_main_beat_clock()
		_main_player.play()


# 浏览器首次用户手势到达时重新发起播放，修复启动阶段 autoplay 被拒后播放器仍显示 playing 却无声音的问题。
func resume_after_web_user_gesture() -> void:
	if not OS.has_feature("web") or _main_player == null:
		return
	_main_player.stop()
	_reset_main_beat_clock()
	_main_player.play()


# 只有音乐真正从头播放时才清空节拍时间轴；暂停恢复必须沿用原播放位置。
func _reset_main_beat_clock() -> void:
	_last_main_beat = -1
	_last_main_music_time = 0.0
	_last_main_raw_time = 0.0
	_main_loop_offset = 0.0


# 启动常驻战斗曲并返回唯一播放头，RhythmClock 通过它保持节拍判定与实际声音一致。
func start_battle_bgm(source_music: AudioStream) -> AudioStreamPlayer:
	if _battle_player == null or source_music == null:
		return null
	var runtime_battle_bgm := source_music.duplicate() as AudioStream
	var battle_mp3_stream := runtime_battle_bgm as AudioStreamMP3
	if battle_mp3_stream != null:
		battle_mp3_stream.loop = true
	_stop_game_win_sfx()
	_battle_player.stop()
	_reset_battle_bgm_volume()
	_battle_player.stream = runtime_battle_bgm
	# 每场战斗从原调开始，避免上一场或奖励页保留的变调泄漏到新战斗。
	reset_battle_pitch()
	_battle_player.play()
	return _battle_player


# 以十二平均律累计改变战斗 BGM；AudioStreamPlayer 的 pitch_scale 会同步改变音高与速度。
func shift_battle_pitch(semitone_delta: int) -> int:
	_battle_pitch_semitones += semitone_delta
	_apply_battle_pitch()
	return _battle_pitch_semitones


# “原调”无条件回到资源的原始采样率，不依赖此前累计了多少次升降调。
func reset_battle_pitch() -> void:
	_battle_pitch_semitones = 0
	_apply_battle_pitch()


# 暴露整数半音状态，供界面提示和自动化测试核对累计规则。
func get_battle_pitch_semitones() -> int:
	return _battle_pitch_semitones


# 胜利音效开始时仅压低音量，战斗曲播放头持续运行，保证音效结束后可从原位置自然恢复。
func mute_battle_bgm_for_game_win() -> void:
	if _battle_player == null:
		return
	_reset_battle_bgm_volume()
	_battle_player.volume_db = BATTLE_BGM_SILENT_DB


# 胜利音效完成后从静音渐显；切场景或新战斗会由重置方法取消旧 Tween。
func fade_in_battle_bgm_after_game_win() -> void:
	if _battle_player == null or not _battle_player.playing or _battle_player.stream_paused:
		return
	_reset_battle_bgm_volume(false)
	_battle_player.volume_db = BATTLE_BGM_SILENT_DB
	_battle_volume_tween = create_tween()
	_battle_volume_tween.tween_property(_battle_player, "volume_db", 0.0, BATTLE_BGM_FADE_IN_SECONDS)


# 胜利音效开始时压低但不停播战斗曲；播放器属于常驻服务，奖励界面切换不影响其自然结束。
func play_game_win_sfx() -> void:
	if _game_win_player == null:
		return
	mute_battle_bgm_for_game_win()
	_game_win_player.play()


# 高优先级切曲（尤其返回地图）可中断胜利音效；同时恢复音量，防止旧静音状态泄漏给后续流程。
func _stop_game_win_sfx() -> void:
	if _game_win_player != null and _game_win_player.playing:
		_game_win_player.stop()
	_reset_battle_bgm_volume()


# 只在音效自然播完且战斗曲仍在运行时渐显；被地图切换中断时不会错误恢复旧 BGM。
func _on_game_win_audio_finished() -> void:
	game_win_audio_finished.emit()
	fade_in_battle_bgm_after_game_win()


# 新战斗、明确停曲与音量渐显前均复位，防止旧胜利协程遗留静音或 Tween。
func _reset_battle_bgm_volume(restore_volume := true) -> void:
	if _battle_volume_tween != null and _battle_volume_tween.is_valid():
		_battle_volume_tween.kill()
	_battle_volume_tween = null
	if restore_volume and _battle_player != null:
		_battle_player.volume_db = 0.0


# 把累计半音数转换成采样率倍率；每增加十二个半音恰好升高一个八度。
func _apply_battle_pitch() -> void:
	if _battle_player != null:
		_battle_player.pitch_scale = pow(2.0, _battle_pitch_semitones / 12.0)


# 关卡点击后在原场景内完成切曲，调用方只能在音效结束后再加载战斗场景。
func prepare_battle_transition() -> void:
	if _main_player != null and _main_player.playing:
		_main_player.stream_paused = true
	if _battle_player != null and _battle_player.playing:
		_battle_player.stream_paused = true
	await _play_transition_sfx()
	_stop_main_bgm()
	_stop_battle_bgm()
	_battle_transition_ready = true


# 战斗场景消费预先完成的过场；直接打开战斗场景时仍补做一次完整过场。
func consume_battle_transition() -> void:
	if not _battle_transition_ready:
		await prepare_battle_transition()
	_battle_transition_ready = false


# 返回地图时同样保留当前界面，等切曲音效结束、主菜单曲恢复后才允许调用方切场景。
func transition_to_main_bgm() -> void:
	_stop_game_win_sfx()
	if _main_player != null and _main_player.playing:
		_main_player.stream_paused = true
	if _battle_player != null and _battle_player.playing:
		_battle_player.stream_paused = true
	await _play_transition_sfx()
	_stop_main_bgm()
	_stop_battle_bgm()
	play_main_bgm()


# 战斗胜利的奖励结算完成后，返回地图音效优先中断仍在播放的胜利音效，再恢复地图主曲。
func transition_after_victory_to_main_bgm() -> void:
	_stop_game_win_sfx()
	if _main_player != null and _main_player.playing:
		_main_player.stream_paused = true
	if _battle_player != null and _battle_player.playing:
		_battle_player.stream_paused = true
	await _play_transition_sfx(BACK_MAP_SFX)
	_stop_main_bgm()
	_stop_battle_bgm()
	play_main_bgm()


# 切曲音效独占一个播放器；资源异常时直接完成，避免界面永久等待。
func _play_transition_sfx(sound_effect: AudioStream = CHANGE_BGM_SFX) -> void:
	if _transition_player == null or sound_effect == null:
		return
	if _transition_player.stream != sound_effect:
		_transition_player.stream = sound_effect
	_transition_player.play()
	await _transition_player.finished


# 切曲音效结束后才停止被暂停的旧曲，避免其在后续场景切换时意外恢复。
func _stop_main_bgm() -> void:
	if _main_player != null:
		_main_player.stop()
		_main_player.stream_paused = false


# 仅在明确切换到其他 BGM 时停止战斗曲；胜利进入奖励页时不调用此方法。
func _stop_battle_bgm() -> void:
	if _battle_player != null:
		_reset_battle_bgm_volume()
		_battle_player.stop()
		_battle_player.stream_paused = false
