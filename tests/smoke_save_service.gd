# 阶段 9 存档冒烟测试：覆盖完整往返、地图恢复、损坏降级和新游戏覆盖旧档。
extends SceneTree

const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const SAVE_SERVICE_SCRIPT := preload("res://autoload/save_service.gd")

var _failed := false
var _path := "res://tests/.smoke_run_save_%d.json" % OS.get_process_id()


# 延迟运行以避开项目 Autoload 初始化，并使用独立路径避免污染正式存档。
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_cleanup()
	_test_round_trip_and_map_restore()
	_test_v1_item_id_migration()
	_test_corrupt_save_fallback()
	_test_new_run_overwrites_old_save()
	_cleanup()
	if _failed:
		quit(1)
		return
	print("smoke_save_service: PASS")
	quit()


# 完整成长字段和正在进行的地图房间必须从 JSON 恢复为等价快照。
func _test_round_trip_and_map_restore() -> void:
	var source = RUN_STATE_SCRIPT.new()
	var restored = RUN_STATE_SCRIPT.new()
	var service = SAVE_SERVICE_SCRIPT.new()
	service.save_path = _path
	source.start_new_run(9191)
	source.chapter = 2
	source.player_hp = 63
	source.max_hp = 110
	source.deck_card_ids.append("card_banana_shot")
	source.owned_item_ids.append(4011)
	source.damage_modifiers.straight = 4
	source.battles_won = 5
	var room: Dictionary = source.map_state.get_attainable_rooms()[0]
	source.map_state.begin_room(room.id)
	source.map_state.set_enemy_id(room.id, "enemy_turtle")
	source.resume_point = source.ResumePoint.BATTLE
	_assert_true(service.save_game(source), "完整本局可写入")
	_assert_true(service.load_game(restored), "完整本局可读回")
	_assert_equal(restored.to_dict(), source.to_dict(), "存档往返保持所有字段")
	_assert_equal(restored.map_state.current_room_id, room.id, "恢复当前地图房间")
	_assert_equal(restored.map_state.get_enemy_id(room.id), "enemy_turtle", "恢复房间敌人缓存")
	source.free()
	restored.free()
	service.free()


# v1 英文战利品键迁移为数字 ID；未知、重复和非字符串值不得污染新契约。
func _test_v1_item_id_migration() -> void:
	var legacy_state = RUN_STATE_SCRIPT.new()
	legacy_state.start_new_run(717)
	var payload := {
		"save_version": 1,
		"run_state": legacy_state.to_dict(),
	}
	payload.run_state["owned_item_ids"] = ["item_golden_boot", "missing_legacy_item", "item_golden_boot", 5001]
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	var restored = RUN_STATE_SCRIPT.new()
	var service = SAVE_SERVICE_SCRIPT.new()
	service.save_path = _path
	_assert_true(service.load_game(restored), "v1 英文战利品存档可迁移")
	_assert_equal(restored.owned_item_ids, [4011], "旧键映射、排重并忽略无效值")
	legacy_state.free()
	restored.free()
	service.free()


# 非法 JSON 必须返回失败且不覆盖调用方当前内存状态。
func _test_corrupt_save_fallback() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{ definitely-not-json")
	file.close()
	var state = RUN_STATE_SCRIPT.new()
	state.start_new_run(313)
	var before: Dictionary = state.to_dict()
	var service = SAVE_SERVICE_SCRIPT.new()
	service.save_path = _path
	_assert_true(not service.load_game(state), "损坏 JSON 安全降级")
	_assert_equal(state.to_dict(), before, "损坏存档不污染内存本局")
	state.free()
	service.free()


# 写入新游戏后旧局成长和地图必须被正式文件整体替换。
func _test_new_run_overwrites_old_save() -> void:
	var state = RUN_STATE_SCRIPT.new()
	var restored = RUN_STATE_SCRIPT.new()
	var service = SAVE_SERVICE_SCRIPT.new()
	service.save_path = _path
	state.start_new_run(11)
	state.battles_won = 8
	state.owned_item_ids.append(5002)
	_assert_true(service.save_game(state), "旧局可保存")
	state.start_new_run(22)
	_assert_true(service.save_game(state), "新游戏覆盖旧档")
	_assert_true(service.load_game(restored), "覆盖后的新档可读取")
	_assert_equal(restored.seed, 22, "新档 seed 生效")
	_assert_equal(restored.battles_won, 0, "旧胜场已清空")
	_assert_true(restored.owned_item_ids.is_empty(), "旧战利品已清空")
	state.free()
	restored.free()
	service.free()


# 仅清理本测试进程派生的三个精确文件。
func _cleanup() -> void:
	for path in [_path, _path + ".tmp", _path + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


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
