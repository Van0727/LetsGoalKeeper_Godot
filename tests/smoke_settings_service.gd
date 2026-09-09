# 设置功能冒烟测试：验证配置往返、损坏降级、数值边界、音频总线应用和设置界面绑定。
extends SceneTree

const SETTINGS_SERVICE_SCRIPT := preload("res://autoload/settings_service.gd")
const SETTINGS_SCENE := preload("res://scenes/settings_screen.tscn")
const BALL_FLIGHT_SCENE := preload("res://scenes/ball_flight.tscn")
const RHYTHM_CLOCK_SCRIPT := preload("res://scripts/battle/rhythm_clock.gd")

var _failed := false
var _path := "res://tests/.smoke_settings_%d.cfg" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_round_trip_and_boundaries()
	_test_legacy_config_defaults_to_waveform()
	_test_corrupt_config_fallback()
	await _test_audio_bus_routing()
	await _test_settings_screen()
	_cleanup()
	if _failed:
		quit(1)
		return
	print("smoke_settings_service: PASS")
	quit()


# 越界音量必须收敛到 0～1，合法语言与全屏枚举必须完整往返。
func _test_round_trip_and_boundaries() -> void:
	var source = SETTINGS_SERVICE_SCRIPT.new()
	var restored = SETTINGS_SERVICE_SCRIPT.new()
	source.settings_path = _path
	restored.settings_path = _path
	source.set_audio_volumes(1.4, -0.2, 0.35)
	source.set_language("en")
	source.set_window_mode(source.WindowMode.FULLSCREEN)
	source.set_metronome_style(source.MetronomeStyle.CIRCLE)
	_assert_equal(source.master_volume, 1.0, "主音量上限")
	_assert_equal(source.music_volume, 0.0, "音乐音量下限")
	_assert_true(source.save_settings(), "设置可保存")
	_assert_true(restored.load_settings(), "设置可读回")
	_assert_equal(restored.master_volume, 1.0, "主音量往返")
	_assert_equal(restored.music_volume, 0.0, "音乐静音往返")
	_assert_equal(restored.sfx_volume, 0.35, "音效音量往返")
	_assert_equal(restored.language, "en", "语言往返")
	_assert_equal(restored.window_mode, restored.WindowMode.FULLSCREEN, "窗口模式往返")
	_assert_equal(restored.metronome_style, restored.MetronomeStyle.CIRCLE, "节拍器样式往返")
	restored.settings_return_scene = "res://scenes/battle.tscn"
	_assert_equal(
		restored.take_settings_return_scene("res://scenes/main_menu.tscn"),
		"res://scenes/battle.tscn",
		"暂停设置返回原场景"
	)
	_assert_equal(
		restored.take_settings_return_scene("res://scenes/main_menu.tscn"),
		"res://scenes/main_menu.tscn",
		"来源路径只消费一次"
	)
	source.free()
	restored.free()


# 版本号相同但尚未包含节拍器字段的旧配置必须继续可读，并自动采用新的波形默认值。
func _test_legacy_config_defaults_to_waveform() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "settings_version", 1)
	config.set_value("general", "language", "en")
	_assert_equal(config.save(_path), OK, "旧版设置样本可写入")
	var service = SETTINGS_SERVICE_SCRIPT.new()
	service.settings_path = _path
	_assert_true(service.load_settings(), "缺少节拍器字段的旧配置仍可读取")
	_assert_equal(service.metronome_style, service.MetronomeStyle.WAVEFORM, "旧配置默认使用波形")
	service.free()


# 无法解析的配置不得保留旧内存值，必须恢复到可启动的默认设置。
func _test_corrupt_config_fallback() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("[broken\nnot-a-config")
	file.close()
	var service = SETTINGS_SERVICE_SCRIPT.new()
	service.settings_path = _path
	service.master_volume = 0.1
	service.language = "en"
	_assert_true(not service.load_settings(), "损坏配置安全降级")
	_assert_equal(service.master_volume, 1.0, "损坏配置恢复默认音量")
	_assert_equal(service.language, "zh_CN", "损坏配置恢复默认语言")
	_assert_equal(service.metronome_style, service.MetronomeStyle.WAVEFORM, "损坏配置恢复默认波形")
	service.free()


# 音乐与战斗音效必须进入各自总线，否则设置页只能调节主音量，两个分类滑块不会产生实际效果。
func _test_audio_bus_routing() -> void:
	var rhythm_clock = RHYTHM_CLOCK_SCRIPT.new()
	root.add_child(rhythm_clock)
	var ball_flight = BALL_FLIGHT_SCENE.instantiate()
	root.add_child(ball_flight)
	await process_frame
	_assert_equal(rhythm_clock._audio_player.bus, &"Music", "战斗音乐进入 Music 总线")
	_assert_equal(ball_flight.kick_audio.bus, &"SFX", "踢球音效进入 SFX 总线")
	_assert_equal(ball_flight.hit_audio.bus, &"SFX", "命中音效进入 SFX 总线")
	rhythm_clock.free()
	ball_flight.free()


# 正式场景应从 Autoload 映射全部控件，保证主菜单入口打开后可以立即操作。
func _test_settings_screen() -> void:
	root.size = Vector2i(360, 640)
	var global_service: Node = root.get_node("SettingsService")
	# 设置页会即时保存；测试改用进程专属路径，禁止覆盖玩家真实 user://settings.cfg。
	global_service.settings_path = _path
	global_service.set_audio_volumes(0.75, 0.6, 0.4)
	global_service.set_language("zh_CN")
	global_service.set_window_mode(global_service.WindowMode.WINDOWED)
	global_service.set_metronome_style(global_service.MetronomeStyle.WAVEFORM)
	var screen := SETTINGS_SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	_assert_equal(screen.master_slider.value, 75.0, "界面显示主音量")
	_assert_equal(screen.music_slider.value, 60.0, "界面显示音乐音量")
	_assert_equal(screen.sfx_slider.value, 40.0, "界面显示音效音量")
	_assert_equal(screen.language_option.item_count, 2, "界面提供两种语言")
	_assert_equal(screen.window_option.item_count, 2, "界面提供窗口与全屏")
	_assert_true(screen.waveform_metronome_check.button_pressed, "设置界面默认选择波形")
	_assert_true(not screen.circle_metronome_check.button_pressed, "圆圈与波形选项保持互斥")
	screen.circle_metronome_check.button_pressed = true
	screen._on_circle_metronome_pressed()
	_assert_equal(global_service.metronome_style, global_service.MetronomeStyle.CIRCLE, "圆圈选项即时写入设置")
	_assert_true(not screen.waveform_metronome_check.button_pressed, "选择圆圈后自动取消波形")
	screen.free()


# 仅删除本测试进程的精确配置文件。
func _cleanup() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
