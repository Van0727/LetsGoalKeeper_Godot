# 诊断服务：在内存中收集有界结构化事件，并仅在玩家主动操作时导出脱敏 JSON 日志。
extends Node

const EXPORT_VERSION := 1
const MAX_ENTRIES := 500
const MAX_MESSAGE_LENGTH := 500
const MAX_EXPORT_BYTES := 262144
const DEFAULT_EXPORT_DIRECTORY := "user://diagnostics"
const SENSITIVE_KEY_PARTS := ["account", "email", "password", "token", "secret", "path", "user"]

var entries: Array[Dictionary] = []
var last_error := ""


# 启动事件只记录引擎与项目版本，不采集设备名、账户、绝对路径或其他身份信息。
func _ready() -> void:
	record("app", "started", {
		"engine_version": Engine.get_version_info().get("string", "unknown"),
		"project_version": ProjectSettings.get_setting("application/config/version", "development"),
	})


# 统一结构化记录入口；字段递归脱敏且字符串截断，容量溢出时淘汰最旧事件。
func record(category: String, event_name: String, fields: Dictionary = {}) -> void:
	entries.append({
		"timestamp": Time.get_datetime_string_from_system(true),
		"category": _safe_text(category),
		"event": _safe_text(event_name),
		"fields": _sanitize_dictionary(fields),
	})
	while entries.size() > MAX_ENTRIES:
		entries.pop_front()


# 用户主动导出时创建目录并写入 JSON；测试可传精确路径隔离真实诊断目录。
func export_logs(output_path := "") -> String:
	var target_path: String = output_path
	if target_path.is_empty():
		var absolute_directory := ProjectSettings.globalize_path(DEFAULT_EXPORT_DIRECTORY)
		var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
		if directory_error != OK:
			last_error = "无法创建诊断目录：%s" % error_string(directory_error)
			return ""
		target_path = "%s/diagnostics_%s.json" % [
			DEFAULT_EXPORT_DIRECTORY,
			Time.get_datetime_string_from_system().replace(":", "-"),
		]

	var export_entries: Array = entries.duplicate(true)
	var content := _build_export_json(export_entries)
	while content.to_utf8_buffer().size() > MAX_EXPORT_BYTES and export_entries.size() > 1:
		export_entries.pop_front()
		content = _build_export_json(export_entries)
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入诊断日志：%s" % FileAccess.get_open_error()
		return ""
	file.store_string(content)
	file.close()
	last_error = ""
	return target_path


func clear() -> void:
	entries.clear()


func _build_export_json(export_entries: Array) -> String:
	return JSON.stringify({
		"diagnostics_version": EXPORT_VERSION,
		"generated_at": Time.get_datetime_string_from_system(true),
		"entries": export_entries,
	}, "  ")


func _sanitize_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		var safe_key := str(key)
		if _is_sensitive_key(safe_key):
			continue
		result[safe_key] = _sanitize_value(source[key])
	return result


func _sanitize_value(value: Variant) -> Variant:
	if value is Dictionary:
		return _sanitize_dictionary(value)
	if value is Array:
		var result: Array = []
		for entry in value:
			result.append(_sanitize_value(entry))
		return result
	if value is String or value is StringName:
		return _safe_text(str(value))
	if value is bool or value is int or value is float or value == null:
		return value
	return _safe_text(str(value))


func _is_sensitive_key(key: String) -> bool:
	var lower := key.to_lower()
	for part in SENSITIVE_KEY_PARTS:
		if part in lower:
			return true
	return false


func _safe_text(value: String) -> String:
	var cleaned := value.replace("user://", "[user-data]/")
	if cleaned.length() > MAX_MESSAGE_LENGTH:
		cleaned = cleaned.left(MAX_MESSAGE_LENGTH)
	return cleaned
