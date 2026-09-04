# 阶段 7 地图状态冒烟测试：验证确定性生成、连线可达性、三态流转与快照恢复。
extends SceneTree

const MAP_GENERATOR := preload("res://scripts/map/map_generator.gd")
const MAP_STATE := preload("res://scripts/map/map_state.gd")
const MAP_CONFIG := preload("res://data/maps/map_chapter_1.tres")

var _failed := false


# 延迟执行以等待场景树初始化。
func _initialize() -> void:
	call_deferred("_run")


# 顺序执行阶段 7 地图核心验收。
func _run() -> void:
	_test_config_shape()
	_test_deterministic_generation()
	_test_connectivity()
	_test_room_state_transitions()
	_test_snapshot_restore()
	_test_enemy_cache()

	if _failed:
		quit(1)
		return
	print("smoke_map_state: PASS")
	quit()


# 验证第 1 章地图配置合法，层结构为三层且范围与首版规则一致。
func _test_config_shape() -> void:
	_assert_true(MAP_CONFIG.is_valid(), "第1章地图配置长度一致")
	_assert_equal(MAP_CONFIG.layer_min_rooms, [2, 2, 1], "每层最少房间数")
	_assert_equal(MAP_CONFIG.layer_max_rooms, [3, 3, 1], "每层最多房间数")
	_assert_equal(MAP_CONFIG.rest_count_by_layer, [0, 1, 0], "第2层固定1个休息房")


# 相同 seed 与配置必须生成完全一致的地图结构和房型。
func _test_deterministic_generation() -> void:
	var first := _generate(777)
	var second := _generate(777)
	_assert_equal(first.to_dict(), second.to_dict(), "固定 seed 地图完全一致")


# 首层全普通且可进；第2层固定1个休息房、其余普通/精英；Boss 层单房间；其余层锁定。
func _test_connectivity() -> void:
	var state := _generate(42)
	_assert_equal(state.layer_count, 3, "地图层数")
	_assert_in_range(state.rooms_on_layer(1).size(), 2, 3, "第1层房间数")
	_assert_in_range(state.rooms_on_layer(2).size(), 2, 3, "第2层房间数")
	_assert_equal(state.rooms_on_layer(3).size(), 1, "第3层房间数")
	_assert_equal(state.rooms_on_layer(3)[0].type, MAP_STATE.RoomType.BOSS, "最后一层是Boss房")

	var rest_count := 0
	for room in state.rooms_on_layer(2):
		if room.type == MAP_STATE.RoomType.REST:
			rest_count += 1
		else:
			_assert_true(
				room.type == MAP_STATE.RoomType.NORMAL or room.type == MAP_STATE.RoomType.ELITE,
				"第2层非休息房为普通或精英"
			)
	_assert_equal(rest_count, 1, "第2层固定一个休息房")

	for room in state.rooms_on_layer(1):
		_assert_equal(room.type, MAP_STATE.RoomType.NORMAL, "第1层全部普通")
		_assert_equal(room.state, MAP_STATE.RoomState.ATTAINABLE, "第1层初始可进")
	for room in state.rooms_on_layer(2):
		_assert_equal(room.state, MAP_STATE.RoomState.LOCKED, "第2层初始锁定")
	for room in state.rooms_on_layer(3):
		_assert_equal(room.state, MAP_STATE.RoomState.LOCKED, "Boss层初始锁定")

	# 相邻层全连通：任何上层房间都指向下一层全部房间，保证任意路线可走到 Boss。
	for layer in range(1, state.layer_count):
		var current_rooms := state.rooms_on_layer(layer)
		var next_count := state.rooms_on_layer(layer + 1).size()
		for room in current_rooms:
			_assert_equal(room.connections.size(), next_count, "第%d层房间连到下一层全部房间" % layer)
	_assert_equal(state.rooms_on_layer(3)[0].connections.size(), 0, "Boss房没有向下的连线")


# 进入可进房间后：同层其余路线锁定、下一层解锁；非法进入保持原状。
func _test_room_state_transitions() -> void:
	var state := _generate(123)
	var layer1 := state.rooms_on_layer(1)
	var layer2 := state.rooms_on_layer(2)
	var first_room: Dictionary = layer1[0]
	var locked_sibling: Dictionary = layer1[1]
	var rest_room: Dictionary = layer2[0]

	var entered: Dictionary = state.enter_room(first_room.id)
	_assert_true(not entered.is_empty(), "合法进入第1层房间")
	_assert_equal(entered.state, MAP_STATE.RoomState.VISITED, "进入后房间已完成")
	_assert_equal(state.current_room_id, first_room.id, "当前房间记录")
	_assert_equal(locked_sibling.state, MAP_STATE.RoomState.LOCKED, "同层其余房间被锁定")
	_assert_equal(rest_room.state, MAP_STATE.RoomState.ATTAINABLE, "下一层房间解锁")
	_assert_equal(state.get_attainable_rooms().size(), layer2.size(), "下一层全部可进")
	_assert_true(not state.boss_visited(), "Boss未进入前不算完成")

	var illegal: Dictionary = state.enter_room(locked_sibling.id)
	_assert_true(illegal.is_empty(), "锁定房间拒绝进入")
	var duplicate: Dictionary = state.enter_room(first_room.id)
	_assert_true(duplicate.is_empty(), "已访问房间拒绝重复进入")

	# 进入第2层任意房间（含休息房）后 Boss 房解锁，再进入 Boss 判定完成。
	var picked: Dictionary = state.enter_room(rest_room.id)
	_assert_true(not picked.is_empty(), "可进入休息房")
	var boss_room: Dictionary = state.rooms_on_layer(3)[0]
	_assert_equal(boss_room.state, MAP_STATE.RoomState.ATTAINABLE, "进入第2层后Boss解锁")
	state.enter_room(boss_room.id)
	_assert_true(state.boss_visited(), "进入Boss房后本局完成")


# 快照导出后恢复的新实例必须与导出源完全一致（模拟退出继续不重新随机）。
func _test_snapshot_restore() -> void:
	var original := _generate(999)
	original.enter_room(original.rooms_on_layer(1)[0].id)
	var restored := MAP_STATE.new()
	restored.from_dict(original.to_dict())
	_assert_equal(restored.to_dict(), original.to_dict(), "快照恢复后地图一致")
	var boss_room: Dictionary = restored.rooms_on_layer(3)[0]
	restored.enter_room(restored.rooms_on_layer(2)[0].id)
	_assert_equal(boss_room.state, MAP_STATE.RoomState.ATTAINABLE, "恢复后的地图可继续流转")


# 敌人ID缓存写入与读取必须可往返，保证同房间重进同敌人。
func _test_enemy_cache() -> void:
	var state := _generate(5)
	var room: Dictionary = state.rooms_on_layer(1)[0]
	_assert_equal(state.get_enemy_id(room.id), "", "未选择敌人时为空")
	state.set_enemy_id(room.id, "enemy_turtle")
	_assert_equal(state.get_enemy_id(room.id), "enemy_turtle", "敌人缓存往返一致")


# 使用指定 seed 生成一张地图的公共入口。
func _generate(seed_value: int) -> MapState:
	var generator = MAP_GENERATOR.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return generator.generate(MAP_CONFIG, rng)


# 通用相等断言。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用范围断言（闭区间）。
func _assert_in_range(actual: int, minimum: int, maximum: int, label: String) -> void:
	if actual >= minimum and actual <= maximum:
		return
	_failed = true
	push_error("%s：期望在 %d~%d，实际 %d" % [label, minimum, maximum, actual])


# 通用布尔断言。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
