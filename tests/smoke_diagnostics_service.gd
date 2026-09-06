# 阶段 9 诊断冒烟测试：验证容量上限、字段脱敏、主动导出和缺失资源记录。
extends SceneTree

const DIAGNOSTICS_SCRIPT := preload("res://autoload/diagnostics_service.gd")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const MAP_GENERATOR := preload("res://scripts/map/map_generator.gd")

var _failed := false
var _path := "res://tests/.smoke_diagnostics_%d.json" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_capacity_sanitizing_and_export()
	_test_missing_resource_diagnostic()
	_cleanup()
	if _failed:
		quit(1)
		return
	print("smoke_diagnostics_service: PASS")
	quit()


# 超量事件只保留最新窗口，导出内容不得包含敏感键或原始 user:// 路径。
func _test_capacity_sanitizing_and_export() -> void:
	var service = DIAGNOSTICS_SCRIPT.new()
	for index in range(service.MAX_ENTRIES + 25):
		service.record("test", "event", {
			"index": index,
			"account_token": "secret-value",
			"save_path": "user://private/save.json",
			"message": "读取 user://private/data",
		})
	_assert_equal(service.entries.size(), service.MAX_ENTRIES, "日志容量淘汰最旧事件")
	_assert_equal(service.entries[0].fields.index, 25, "容量溢出后保留最新窗口")
	_assert_true(not service.entries[0].fields.has("account_token"), "敏感账户字段已移除")
	_assert_true(not service.entries[0].fields.has("save_path"), "路径字段已移除")
	_assert_true("user://" not in service.entries[0].fields.message, "消息中的用户路径已泛化")
	_assert_equal(service.export_logs(_path), _path, "玩家指定路径可导出诊断")
	_assert_true(FileAccess.file_exists(_path), "诊断导出文件存在")
	var file := FileAccess.open(_path, FileAccess.READ)
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	_assert_true(parsed is Dictionary, "导出文件为合法 JSON")
	_assert_true(text.to_utf8_buffer().size() <= service.MAX_EXPORT_BYTES, "导出文件不超过容量上限")
	_assert_true("secret-value" not in text and "user://private" not in text, "导出内容不含敏感值")
	service.free()


# 无效卡牌 ID 应安全返回空资源，并在全局诊断中留下可定位的稳定 ID。
func _test_missing_resource_diagnostic() -> void:
	var diagnostics: Node = root.get_node("DiagnosticsService")
	diagnostics.clear()
	var rewards = REWARD_SERVICE.new()
	_assert_true(rewards.get_card_by_id("card_missing_for_test") == null, "缺失卡牌安全返回空值")
	_assert_equal(diagnostics.entries.size(), 1, "缺失资源生成一条诊断")
	_assert_equal(diagnostics.entries[0].category, "resource", "缺失资源诊断分类")
	_assert_equal(diagnostics.entries[0].fields.resource_id, "card_missing_for_test", "诊断保留稳定资源 ID")
	var generator = MAP_GENERATOR.new()
	_assert_true(generator.load_config_for_chapter(999) == null, "缺失地图配置安全返回空值")
	_assert_equal(diagnostics.entries.size(), 2, "缺失地图追加诊断")
	_assert_equal(diagnostics.entries[1].fields.resource_type, "map_config", "地图诊断标明资源类型")
	_assert_equal(diagnostics.entries[1].fields.chapter, 999, "地图诊断保留章节")


# 仅删除本测试进程生成的精确导出文件。
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
