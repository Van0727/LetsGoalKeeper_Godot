# 卡牌三表迁移测试：验证唯一卡牌 ID、模板复用、步骤外键与失败前不写资源。
extends SceneTree

const IMPORTER := preload("res://scripts/cards/card_csv_importer.gd")

var _failed := false
var _output_directory := "res://tests/smoke_card_csv_migration_%d" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var importer = IMPORTER.new()
	var bad_cards := {}
	var ids := {}
	var errors: Array[String] = []
	var card_row := PackedStringArray(["1001", "射门", "测试", "1", "1", "1", "1", "0.5", "0.5", "2", "3|6", "1|1", "0|0", "100|100", "100|100", "0|0", "card_test", "测试流派", "1", "1"])
	importer._parse_card_row(card_row, 4, bad_cards, ids, errors)
	importer._parse_card_row(card_row, 5, bad_cards, ids, errors)
	_assert_true(not errors.is_empty(), "重复卡牌 ID 被拒绝")
	var templates := {2: {"name": "测试", "steps": []}}
	var effect_row := PackedStringArray(["9999", "1", "1", "2", "仅供策划查看"])
	errors.clear()
	importer._parse_step_row(effect_row, 4, templates, errors)
	_assert_true(not errors.is_empty(), "孤立步骤外键被拒绝")
	effect_row[0] = "2"
	effect_row[2] = "不是整数"
	errors.clear()
	importer._parse_step_row(effect_row, 4, templates, errors)
	_assert_true(not errors.is_empty(), "错误字段类型被拒绝")
	errors.clear()
	importer._parse_effect_row(PackedStringArray(["2", "重复模板", "仅供策划查看"]), 4, templates, errors)
	_assert_true(not errors.is_empty(), "重复效果模板 ID 被拒绝")
	var reused_row := card_row.duplicate()
	reused_row[0] = "1020"
	reused_row[16] = "card_reused_test"
	errors.clear()
	importer._parse_card_row(reused_row, 6, bad_cards, ids, errors)
	_assert_true(errors.is_empty(), "新卡仅用主表一行引用相同效果模板")
	_assert_equal(bad_cards["card_test"].effect_id, bad_cards["card_reused_test"].effect_id, "两张卡复用同一个效果 ID")
	var disabled_row := reused_row.duplicate()
	disabled_row[0] = "1022"
	disabled_row[16] = "card_disabled_test"
	disabled_row[18] = "0"
	errors.clear()
	importer._parse_card_row(disabled_row, 7, bad_cards, ids, errors)
	_assert_true(errors.is_empty() and not bad_cards["card_disabled_test"].enabled, "实装状态0合法并写入禁用状态")
	var invalid_enabled_row := reused_row.duplicate()
	invalid_enabled_row[0] = "1023"
	invalid_enabled_row[16] = "card_invalid_enabled_test"
	invalid_enabled_row[18] = "2"
	errors.clear()
	importer._parse_card_row(invalid_enabled_row, 8, bad_cards, ids, errors)
	_assert_true(not errors.is_empty(), "卡牌实装状态只能为0或1")
	var invalid_stock_row := reused_row.duplicate()
	invalid_stock_row[0] = "1024"
	invalid_stock_row[16] = "card_invalid_stock_test"
	invalid_stock_row[19] = "256"
	errors.clear()
	importer._parse_card_row(invalid_stock_row, 9, bad_cards, ids, errors)
	_assert_true(not errors.is_empty(), "卡牌奖励库存必须在uint8范围内")
	var mismatched_row := reused_row.duplicate()
	mismatched_row[0] = "1021"
	mismatched_row[11] = "1"
	mismatched_row[16] = "card_mismatched_test"
	errors.clear()
	importer._parse_card_row(mismatched_row, 10, bad_cards, ids, errors)
	_assert_true(not errors.is_empty(), "多步骤卡牌的参数组数不一致时被拒绝")
	_assert_true(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_output_directory)), "失败校验未创建输出目录")
	var missing_template_result: Dictionary = importer.import_cards("res://tables/cards.csv", _output_directory, "res://tables/effects_missing_for_test.csv")
	_assert_true(not missing_template_result.ok, "缺失效果模板表时导入失败")
	_assert_true(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_output_directory)), "缺失模板时不创建输出目录")
	var result: Dictionary = importer.import_cards("res://tables/cards.csv", _output_directory)
	_assert_true(result.ok, "双表可以导入")
	if result.ok:
		_assert_equal(result.card_count, 46, "主表共46张唯一卡牌")
		_assert_equal(result.effect_count, 50, "子表共50条效果")
		var multi = load("%s/card_attack_and_defend.tres" % _output_directory)
		_assert_equal(multi.effects.size(), 2, "同一卡牌组装两个有序效果")
		_assert_equal(multi.effects[0].effect_type, 0, "先造成伤害")
		_assert_equal(multi.effects[1].effect_type, 1, "后获得护盾")
	_cleanup()
	if _failed:
		quit(1)
		return
	print("smoke_card_csv_migration: PASS")
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
