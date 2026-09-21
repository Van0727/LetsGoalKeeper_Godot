# 卡牌 CSV 导入冒烟测试：验证真实策划表可生成资源，并确认多段伤害与百分比倍率会进入战斗结算。
extends SceneTree

const CARD_CSV_IMPORTER_SCRIPT := preload("res://scripts/cards/card_csv_importer.gd")
const COMBATANT_STATE := preload("res://scripts/battle/combatant_state.gd")
const EFFECT_RESOLVER := preload("res://scripts/battle/effect_resolver.gd")

var _failed := false
var _output_directory := "res://tests/smoke_card_csv_import_%d" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var importer := CARD_CSV_IMPORTER_SCRIPT.new()
	_test_attack_delay_float_validation(importer)
	var missing_result: Dictionary = importer.import_cards("res://tables/cards_missing_for_test.csv", _output_directory)
	_assert_true(not missing_result.ok, "缺失 CSV 明确失败且不会生成资源")
	_assert_true(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_output_directory)), "校验失败前不创建输出目录")
	var result: Dictionary = importer.import_cards("res://tables/cards.csv", _output_directory)
	_assert_true(result.ok, "真实卡牌 CSV 可完成导入")
	_assert_equal(result.card_count, 46, "CSV 导入46张卡牌")
	_assert_equal(result.effect_count, 50, "CSV 导入50条效果")
	if result.ok:
		_test_imported_values_affect_battle()
	_cleanup()
	if _failed:
		quit(1)
		return
	print("smoke_card_csv_importer: PASS")
	quit()


# 攻击延迟与攻击间隔共用浮点边界：验证小数和上限可用，负数与非数字会被拒绝。
func _test_attack_delay_float_validation(importer: RefCounted) -> void:
	var valid_errors: Array[String] = []
	_assert_equal(importer._parse_float("0.0625", 0.0, 16.0, "攻击延迟拍数", 4, valid_errors), 0.0625, "攻击延迟支持十六分之一拍")
	_assert_equal(importer._parse_float("16", 0.0, 16.0, "攻击延迟拍数", 4, valid_errors), 16.0, "攻击延迟兼容整数并接受上限")
	_assert_true(valid_errors.is_empty(), "合法攻击延迟不会产生校验错误")
	var negative_errors: Array[String] = []
	_assert_true(importer._parse_float("-0.0001", 0.0, 16.0, "攻击延迟拍数", 4, negative_errors) < 0.0, "负攻击延迟被拒绝")
	_assert_equal(negative_errors.size(), 1, "负攻击延迟产生一条明确错误")
	var invalid_errors: Array[String] = []
	_assert_true(importer._parse_float("一拍", 0.0, 16.0, "攻击延迟拍数", 4, invalid_errors) < 0.0, "非数字攻击延迟被拒绝")
	_assert_equal(invalid_errors.size(), 1, "非数字攻击延迟产生一条明确错误")


# 一组射门和助跑分别覆盖多段攻击、节拍间隔与百分比倍率的实际结算路径。
func _test_imported_values_affect_battle() -> void:
	var group = load("%s/card_shot_group.tres" % _output_directory)
	var run_up = load("%s/card_run_up.tres" % _output_directory)
	var samba_duet = load("%s/card_samba_duet.tres" % _output_directory)
	_assert_equal(group.effects[0].hits, 4, "CSV 的一组射门按数值列导入4段")
	_assert_equal(group.multi_hit_interval_beats, 0.25, "CSV 的攻击间隔写入资源")
	_assert_equal(run_up.effects[0].multiplier, 1.5, "CSV 百分比倍率150转换为1.5")
	_assert_equal(samba_duet.id, 1013, "数字ID写入卡牌资源")
	_assert_equal(samba_duet.archetype_hint, "桑巴精灵·左右香蕉", "流派倾向写入资源但不参与结算")
	_assert_true(samba_duet.enabled, "实装状态写入卡牌资源")
	var source = COMBATANT_STATE.new("导入测试球员", 20, 3)
	var target = COMBATANT_STATE.new("导入测试目标", 30)
	var resolver = EFFECT_RESOLVER.new()
	resolver.resolve_card(run_up, source, target)
	var events: Array[Dictionary] = resolver.resolve_card(group, source, target)
	_assert_equal(events.size(), 4, "导入后的多段攻击生成4段事件")
	_assert_equal(target.health, 18, "助跑倍率使4段各2点伤害变为各3点")


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
