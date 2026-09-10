# 全局背景音乐服务：在场景切换期间保留非战斗 BGM，并负责进入战斗前的切曲音效顺序。
extends Node

const MAIN_BGM := preload("res://sound/bgm/bg_main_bpm110.mp3")
const CHANGE_BGM_SFX := preload("res://sound/sounds/changeBgm.mp3")
const WIN_SFX := preload("res://sound/sounds/win.mp3")
const BATTLE_SCENE_PATH := "res://scenes/battle.tscn"

var _main_player: AudioStreamPlayer
var _battle_player: AudioStreamPlayer
var _transition_player: AudioStreamPlayer
var _battle_transition_ready := false


# 常驻播放器分别承载循环 BGM 与一次性切曲音效，避免场景销毁导致切换音效中断。
func _ready() -> void:
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
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed()


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
		_main_player.play()


# 启动常驻战斗曲并返回唯一播放头，RhythmClock 通过它保持节拍判定与实际声音一致。
func start_battle_bgm(source_music: AudioStream) -> AudioStreamPlayer:
	if _battle_player == null or source_music == null:
		return null
	var runtime_battle_bgm := source_music.duplicate() as AudioStream
	var battle_mp3_stream := runtime_battle_bgm as AudioStreamMP3
	if battle_mp3_stream != null:
		battle_mp3_stream.loop = true
	_battle_player.stop()
	_battle_player.stream = runtime_battle_bgm
	_battle_player.play()
	return _battle_player


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
	if _main_player != null and _main_player.playing:
		_main_player.stream_paused = true
	if _battle_player != null and _battle_player.playing:
		_battle_player.stream_paused = true
	await _play_transition_sfx()
	_stop_main_bgm()
	_stop_battle_bgm()
	play_main_bgm()


# 战斗胜利的奖励结算完成后使用专属胜利音效，再恢复地图主曲；其余切曲仍保留 changeBgm。
func transition_after_victory_to_main_bgm() -> void:
	if _main_player != null and _main_player.playing:
		_main_player.stream_paused = true
	if _battle_player != null and _battle_player.playing:
		_battle_player.stream_paused = true
	await _play_transition_sfx(WIN_SFX)
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
		_battle_player.stop()
		_battle_player.stream_paused = false
