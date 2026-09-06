# 全局设置服务：独立保存音量、语言和窗口模式，并负责把经过校验的值即时应用到引擎。
extends Node

signal settings_changed

const SETTINGS_VERSION := 1
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const SUPPORTED_LOCALES := ["zh_CN", "en"]

enum WindowMode {
	WINDOWED,
	FULLSCREEN,
}

# 测试可覆盖配置路径，正式运行使用独立于本局存档的 user://settings.cfg。
var settings_path := DEFAULT_SETTINGS_PATH
var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 0.8
var language := "zh_CN"
var window_mode := WindowMode.WINDOWED
var last_error := ""
# 暂停菜单进入设置时暂存来源场景；该字段不写配置，应用重启后自然清空。
var settings_return_scene := ""


# 设置页消费一次来源路径后立即清空，避免下次从主菜单打开时错误返回旧场景。
func take_settings_return_scene(default_path: String) -> String:
	var result := settings_return_scene if not settings_return_scene.is_empty() else default_path
	settings_return_scene = ""
	return result


# 启动时先建立音频总线，再加载并应用配置；损坏配置会回退默认值而不阻止游戏启动。
func _ready() -> void:
	_ensure_audio_buses()
	load_settings()
	apply_settings()


# 读取版本化配置；字段缺失或越界时逐项使用默认值并归一化。
func load_settings() -> bool:
	_reset_defaults()
	if not FileAccess.file_exists(settings_path):
		last_error = ""
		return false
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error != OK:
		last_error = "设置文件损坏：%s" % error_string(error)
		return false
	if int(config.get_value("meta", "settings_version", 0)) != SETTINGS_VERSION:
		last_error = "设置版本不兼容"
		return false
	master_volume = _normalize_volume(config.get_value("audio", "master_volume", master_volume))
	music_volume = _normalize_volume(config.get_value("audio", "music_volume", music_volume))
	sfx_volume = _normalize_volume(config.get_value("audio", "sfx_volume", sfx_volume))
	language = _normalize_language(config.get_value("general", "language", language))
	window_mode = _normalize_window_mode(config.get_value("display", "window_mode", window_mode))
	last_error = ""
	return true


# 保存独立配置文件；调用方修改设置后统一经此入口持久化。
func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value("meta", "settings_version", SETTINGS_VERSION)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("general", "language", language)
	config.set_value("display", "window_mode", window_mode)
	var error := config.save(settings_path)
	if error != OK:
		last_error = "无法保存设置：%s" % error_string(error)
		return false
	last_error = ""
	_record_diagnostic("saved", {"language": language, "window_mode": window_mode})
	return true


# 音量入口统一限制到 0～1，并立即同步三个引擎总线。
func set_audio_volumes(master: float, music: float, sfx: float) -> void:
	master_volume = _normalize_volume(master)
	music_volume = _normalize_volume(music)
	sfx_volume = _normalize_volume(sfx)
	_apply_audio()
	settings_changed.emit()


# 语言只接受首版支持列表；翻译资源可后续加入而无需改变设置契约。
func set_language(locale: String) -> void:
	language = _normalize_language(locale)
	TranslationServer.set_locale(language)
	settings_changed.emit()


# 窗口模式使用稳定枚举持久化；无显示设备的测试环境只更新状态，不调用窗口 API。
func set_window_mode(mode: int) -> void:
	window_mode = _normalize_window_mode(mode)
	_apply_window_mode()
	settings_changed.emit()


# 将当前内存配置完整应用，供启动加载和设置界面恢复默认值复用。
func apply_settings() -> void:
	_ensure_audio_buses()
	_apply_audio()
	TranslationServer.set_locale(language)
	_apply_window_mode()


func _reset_defaults() -> void:
	master_volume = 1.0
	music_volume = 0.8
	sfx_volume = 0.8
	language = "zh_CN"
	window_mode = WindowMode.WINDOWED


func _normalize_volume(value: Variant) -> float:
	if value is not float and value is not int:
		return 1.0
	return clampf(float(value), 0.0, 1.0)


func _normalize_language(value: Variant) -> String:
	var locale := str(value)
	return locale if locale in SUPPORTED_LOCALES else "zh_CN"


func _normalize_window_mode(value: Variant) -> int:
	var mode := int(value)
	return mode if mode in [WindowMode.WINDOWED, WindowMode.FULLSCREEN] else WindowMode.WINDOWED


# Music 与 SFX 挂到 Master 下，当前及后续播放器可直接选择对应总线。
func _ensure_audio_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, BUS_MASTER)


func _apply_audio() -> void:
	_set_bus_volume(BUS_MASTER, master_volume)
	_set_bus_volume(BUS_MUSIC, music_volume)
	_set_bus_volume(BUS_SFX, sfx_volume)


# 0 音量显式静音；其他值转为分贝，避免 linear_to_db(0) 的无穷值进入总线。
func _set_bus_volume(bus_name: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))


func _apply_window_mode() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		return
	var engine_mode := (
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if window_mode == WindowMode.FULLSCREEN
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(engine_mode)


# 设置日志不包含配置文件路径，仅记录可公开的选项值。
func _record_diagnostic(event_name: String, fields: Dictionary) -> void:
	if not is_inside_tree():
		return
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("settings", event_name, fields)
