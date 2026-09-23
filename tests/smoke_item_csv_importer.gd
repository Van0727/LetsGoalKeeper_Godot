# 战利品 CSV 导入冒烟测试：覆盖真实全量配置、效果顺序、目录生成及缺表失败不创建输出目录。
extends SceneTree

const TABLE_IMPORTER := preload("res://scripts/cards/card_csv_importer.gd")

var _failed := false
var _output_directory := "res://tests/smoke_item_csv_import_%d" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var importer := TABLE_IMPORTER.new()
	var missing := importer.import_items("res://tables/items_missing_for_test.csv", "res://tables/item_effects.csv", _output_directory)
	_assert_true(not missing.ok, "缺失战利品主表明确失败")
	_assert_true(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_output_directory)), "校验失败前不创建战利品输出目录")
	var result := importer.import_items("res://tables/items.csv", "res://tables/item_effects.csv", _output_directory, "%s/item_catalog.tres" % _output_directory)
	_assert_true(result.ok, "真实战利品配表可完成导入")
	if result.ok:
		_assert_equal(result.item_count, 36, "战利品主表共36件")
		_assert_equal(result.effect_count, 30, "战利品效果表共30条")
		var license := load("%s/item_free_kick_master_license.tres" % _output_directory)
		_assert_true(license.icon != null, "已配置战利品图片写入生成资源")
		_assert_equal(license.icon.resource_path, "res://assets/ui/items/item_free_kick_master_license.png", "生成资源保留配表图片路径")
		_assert_equal(license.effects.size(), 2, "多效果战利品保持效果数量")
		_assert_equal(license.effects[0].operation, 6, "战利品效果顺序保持连续计数在前")
		_assert_equal(license.effects[1].operation, 7, "战利品效果顺序保持读计数加伤在后")
		var energy_core := load("%s/item_energy_core.tres" % _output_directory)
		_assert_true(energy_core.icon == null, "未配置图片的战利品保持空纹理以触发界面回退")
		_assert_equal(energy_core.id, 4029, "能量核心使用正式数字ID")
		_assert_equal(energy_core.run_max_energy_bonus, 1, "能量核心写入游戏历程能量上限加成")
		var charger := load("%s/item_three_phase_charger.tres" % _output_directory)
		_assert_equal(charger.effects[0].turn_interval, 3, "三相充能器回读每三回合触发条件")
		var catalog := load("%s/item_catalog.tres" % _output_directory)
		_assert_equal(catalog.items.size(), 36, "战利品目录收录全部正常和禁用配置")
		_cleanup()
	if _failed:
		quit(1)
		return
	print("smoke_item_csv_importer: PASS")
	quit()


func _cleanup() -> void:
	var directory := DirAccess.open(_output_directory)
	if directory == null:
		return
	for file_name in directory.get_files():
		directory.remove(file_name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_output_directory))


func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])
