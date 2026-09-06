# 阶段 9 设置冒烟测试：验证配置往返、损坏降级、数值边界和设置界面绑定。
extends SceneTree

const SETTINGS_SERVICE_SCRIPT := preload("res://autoload/settings_service.gd")
const SETTINGS_SCENE := preload("res://scenes/settings_screen.tscn")

var _failed := false
var _path := "res://tests/.smoke_settings_%d.cfg" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_round_trip_and_boundaries()
	_test_corrupt_config_fallback()
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
	_assert_equal(source.master_volume, 1.0, "主音量上限")
	_assert_equal(source.music_volume, 0.0, "音乐音量下限")
	_assert_true(source.save_settings(), "设置可保存")
	_assert_true(restored.load_settings(), "设置可读回")
	_assert_equal(restored.master_volume, 1.0, "主音量往返")
	_assert_equal(restored.music_volume, 0.0, "音乐静音往返")
	_assert_equal(restored.sfx_volume, 0.35, "音效音量往返")
	_assert_equal(restored.language, "en", "语言往返")
	_assert_equal(restored.window_mode, restored.WindowMode.FULLSCREEN, "窗口模式往返")
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
	service.free()


# 正式场景应从 Autoload 映射全部控件，保证主菜单入口打开后可以立即操作。
func _test_settings_screen() -> void:
	root.size = Vector2i(360, 640)
	var global_service: Node = root.get_node("SettingsService")
	global_service.set_audio_volumes(0.75, 0.6, 0.4)
	global_service.set_language("zh_CN")
	global_service.set_window_mode(global_service.WindowMode.WINDOWED)
	var screen := SETTINGS_SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	_assert_equal(screen.master_slider.value, 75.0, "界面显示主音量")
	_assert_equal(screen.music_slider.value, 60.0, "界面显示音乐音量")
	_assert_equal(screen.sfx_slider.value, 40.0, "界面显示音效音量")
	_assert_equal(screen.language_option.item_count, 2, "界面提供两种语言")
	_assert_equal(screen.window_option.item_count, 2, "界面提供窗口与全屏")
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
