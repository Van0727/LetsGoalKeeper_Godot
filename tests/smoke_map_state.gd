# 阶段 7 地图状态冒烟测试：验证确定性稀疏连线、进入/完成两阶段流转与快照恢复。
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
	_test_rest_usage_persistence()
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

	# 稀疏连线必须同时保证每个上层房间有出边、每个下层房间有入边。
	for layer in range(1, state.layer_count):
		var current_rooms := state.rooms_on_layer(layer)
		var next_rooms := state.rooms_on_layer(layer + 1)
		var edge_count := 0
		for room in current_rooms:
			_assert_true(room.connections.size() >= 1, "第%d层每个房间至少一条出边" % layer)
			edge_count += room.connections.size()
		for next_room in next_rooms:
			var incoming := 0
			for room in current_rooms:
				if next_room.id in room.connections:
					incoming += 1
			_assert_true(incoming >= 1, "第%d层每个房间至少一条入边" % (layer + 1))
		if current_rooms.size() > 1 and next_rooms.size() > 1:
			_assert_true(edge_count < current_rooms.size() * next_rooms.size(), "相邻多房间层保持稀疏而非全连接")
	_assert_equal(state.rooms_on_layer(3)[0].connections.size(), 0, "Boss房没有向下的连线")


# 开始房间不推进路线；只有完成后才锁定同层、解锁连线，非法切换保持原状。
func _test_room_state_transitions() -> void:
	var state := _generate(123)
	var layer1 := state.rooms_on_layer(1)
	var layer2 := state.rooms_on_layer(2)
	var first_room: Dictionary = layer1[0]
	var locked_sibling: Dictionary = layer1[1]
	var next_room: Dictionary = state.room_by_id(first_room.connections[0])

	var entered: Dictionary = state.begin_room(first_room.id)
	_assert_true(not entered.is_empty(), "合法进入第1层房间")
	_assert_equal(entered.state, MAP_STATE.RoomState.ATTAINABLE, "进入后尚未完成房间")
	_assert_equal(state.current_room_id, first_room.id, "当前房间记录")
	_assert_equal(locked_sibling.state, MAP_STATE.RoomState.ATTAINABLE, "完成前同层选择不被永久锁定")
	_assert_equal(next_room.state, MAP_STATE.RoomState.LOCKED, "完成前下一层保持锁定")
	_assert_true(not state.boss_visited(), "Boss未进入前不算完成")
	_assert_true(state.cancel_current_room(), "失败或退出时可取消进行中房间")
	_assert_equal(first_room.state, MAP_STATE.RoomState.ATTAINABLE, "取消后当前房间仍可重新挑战")
	_assert_equal(next_room.state, MAP_STATE.RoomState.LOCKED, "取消后下一层仍保持锁定")
	state.begin_room(first_room.id)

	var switched: Dictionary = state.begin_room(locked_sibling.id)
	_assert_true(switched.is_empty(), "已有进行中房间时拒绝切换路线")
	var completed: Dictionary = state.complete_current_room()
	_assert_equal(completed.state, MAP_STATE.RoomState.VISITED, "完成后房间标记已访问")
	_assert_equal(state.current_room_id, "", "完成后清除进行中房间")
	_assert_equal(locked_sibling.state, MAP_STATE.RoomState.LOCKED, "完成后同层其余房间被锁定")
	_assert_equal(next_room.state, MAP_STATE.RoomState.ATTAINABLE, "完成后真实连线房间解锁")

	var illegal: Dictionary = state.begin_room(locked_sibling.id)
	_assert_true(illegal.is_empty(), "锁定房间拒绝进入")
	var duplicate: Dictionary = state.begin_room(first_room.id)
	_assert_true(duplicate.is_empty(), "已访问房间拒绝重复进入")

	# 完成第2层房间后 Boss 解锁；仅开始 Boss 不能判定完成。
	var picked: Dictionary = state.begin_room(next_room.id)
	_assert_true(not picked.is_empty(), "可进入已解锁的第2层房间")
	state.complete_current_room()
	var boss_room: Dictionary = state.rooms_on_layer(3)[0]
	_assert_equal(boss_room.state, MAP_STATE.RoomState.ATTAINABLE, "完成第2层后Boss解锁")
	state.begin_room(boss_room.id)
	_assert_true(not state.boss_visited(), "Boss开战但未胜利时不算完成")
	state.complete_current_room()
	_assert_true(state.boss_visited(), "Boss结算完成后本章完成")


# 休息机会属于房间运行数据，快照恢复后仍保持已使用，且不能二次消费。
func _test_rest_usage_persistence() -> void:
	var state := _generate(321)
	var rest_room: Dictionary = {}
	for room in state.rooms_on_layer(2):
		if room.type == MAP_STATE.RoomType.REST:
			rest_room = room
			break
	_assert_true(not rest_room.is_empty(), "地图包含休息房")
	var source_room: Dictionary = {}
	for room in state.rooms_on_layer(1):
		if rest_room.id in room.connections:
			source_room = room
			break
	_assert_true(not source_room.is_empty(), "休息房至少有一条入边")
	state.begin_room(source_room.id)
	state.complete_current_room()
	_assert_equal(rest_room.state, MAP_STATE.RoomState.ATTAINABLE, "完成上层后休息房可进入")
	state.begin_room(rest_room.id)
	_assert_true(state.mark_current_rest_used(), "首次使用休息房")
	_assert_true(not state.mark_current_rest_used(), "同一休息房拒绝二次使用")
	var restored := MAP_STATE.new()
	restored.from_dict(state.to_dict())
	_assert_true(restored.room_by_id(rest_room.id).get("rest_used", false), "快照保存休息房使用状态")
	_assert_true(not restored.mark_current_rest_used(), "快照恢复后仍拒绝重复使用休息房")


# 快照导出后恢复的新实例必须与导出源完全一致（模拟退出继续不重新随机）。
func _test_snapshot_restore() -> void:
	var original := _generate(999)
	original.begin_room(original.rooms_on_layer(1)[0].id)
	original.complete_current_room()
	var restored := MAP_STATE.new()
	restored.from_dict(original.to_dict())
	_assert_equal(restored.to_dict(), original.to_dict(), "快照恢复后地图一致")
	var boss_room: Dictionary = restored.rooms_on_layer(3)[0]
	var reachable: Dictionary = restored.get_attainable_rooms()[0]
	restored.begin_room(reachable.id)
	restored.complete_current_room()
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
