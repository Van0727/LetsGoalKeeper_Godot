# BGM 音调冒烟测试：覆盖半音累计、升降抵消、原调恢复与新战斗重置。
extends SceneTree

const BGM_SERVICE_SCRIPT := preload("res://autoload/bgm_service.gd")
const TEST_MUSIC := preload("res://sound/bgm/bg_basicDrum2_bpm100.mp3")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service = BGM_SERVICE_SCRIPT.new()
	root.add_child(service)
	var player: AudioStreamPlayer = service.start_battle_bgm(TEST_MUSIC)
	_assert_equal(service.get_battle_pitch_semitones(), 0, "新战斗从原调开始")
	_assert_approx(player.pitch_scale, 1.0, "原调采样率倍率")
	service.shift_battle_pitch(1)
	_assert_equal(service.get_battle_pitch_semitones(), 1, "升调累计一个半音")
	_assert_approx(player.pitch_scale, pow(2.0, 1.0 / 12.0), "升调使用十二平均律")
	service.shift_battle_pitch(-1)
	_assert_equal(service.get_battle_pitch_semitones(), 0, "升降调互相抵消")
	service.shift_battle_pitch(-2)
	service.reset_battle_pitch()
	_assert_equal(service.get_battle_pitch_semitones(), 0, "原调清空累计半音")
	_assert_approx(player.pitch_scale, 1.0, "原调恢复采样率倍率")
	service.shift_battle_pitch(3)
	service.start_battle_bgm(TEST_MUSIC)
	_assert_equal(service.get_battle_pitch_semitones(), 0, "新战斗不会继承旧音调")
	service.free()
	if _failed:
		quit(1)
		return
	print("smoke_bgm_pitch: PASS")
	quit()


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		return
	_failed = true
	push_error("%s：期望 %.6f，实际 %.6f" % [label, expected, actual])
