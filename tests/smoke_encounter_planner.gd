# 地图怪物规划验收：覆盖同行去重、连线去重、固定 seed 可复现与候选不足的失败路径。
extends SceneTree

const MAP_STATE := preload("res://scripts/map/map_state.gd")
const PLANNER := preload("res://scripts/enemies/encounter_planner.gd")
const POOL := preload("res://data/encounters/chapter_1.tres")
const CATALOG := preload("res://data/enemies/enemy_catalog.tres")
const ENCOUNTER_POOL := preload("res://scripts/enemies/encounter_pool.gd")
const MAP_GENERATOR := preload("res://scripts/map/map_generator.gd")
var _failed := false


func _initialize() -> void:
	var state := _make_state()
	var first := PLANNER.plan(state, POOL, CATALOG, 20260921)
	var second := PLANNER.plan(state, POOL, CATALOG, 20260921)
	_check(first.size() == 7, "全部战斗房都应获得怪物")
	_check(_ids(first) == _ids(second), "固定seed的全图方案必须可复现")
	_check_constraints(state, first)
	_test_published_chapters()

	# 三个同行房间只给两种普通怪，必须明确返回无解，不得死循环或产出部分方案。
	var short_pool := ENCOUNTER_POOL.new()
	short_pool.chapter = 1
	short_pool.enemies.assign(POOL.get_candidates(0).slice(0, 2))
	_check(PLANNER.plan(state, short_pool, CATALOG, 20260921).is_empty(), "候选不足时应安全报告无解")
	print("smoke_encounter_planner: %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


# 对每章多个地图 seed 验证正式房型和遭遇池的组合确实有解，避免只在人工夹具中成功。
func _test_published_chapters() -> void:
	for chapter in range(1, 4):
		var config: Resource = load("res://data/maps/map_chapter_%d.tres" % chapter)
		var pool: Resource = load("res://data/encounters/chapter_%d.tres" % chapter)
		for seed_value in range(20):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value + chapter * 10000
			var state: RefCounted = MAP_GENERATOR.new().generate(config, rng)
			var plan: Dictionary = PLANNER.plan(state, pool, CATALOG, seed_value)
			_check(not plan.is_empty(), "第%d章 seed %d 的正式地图应存在合法遇敌方案" % [chapter, seed_value])
			if not plan.is_empty():
				_check_constraints(state, plan)


# 两行普通房间各三个并交叉连线，最后连接单Boss，制造需要回溯也能求解的真实约束图。
func _make_state() -> RefCounted:
	var state := MAP_STATE.new()
	state.layer_count = 3
	for layer in range(1, 4):
		var count := 1 if layer == 3 else 3
		for index in range(count):
			state.add_room({
				"id": "%d-%d" % [layer, index],
				"layer": layer,
				"index": index,
				"type": 2 if layer == 3 else 0,
				"state": 0,
				"connections": [],
				"enemy_id": "",
				"rest_used": false,
			})
	state.room_by_id("1-0").connections.assign(["2-0", "2-1"])
	state.room_by_id("1-1").connections.assign(["2-1", "2-2"])
	state.room_by_id("1-2").connections.assign(["2-0", "2-2"])
	for room in state.rooms_on_layer(2):
		room.connections.append("3-0")
	return state


# 将规划结果压成稳定数字ID字典，避免用资源对象地址比较可复现性。
func _ids(plan: Dictionary) -> Dictionary:
	var result := {}
	for room_id in plan:
		result[room_id] = plan[room_id].id
	return result


# 同行检查全部房间，跨行检查每一条真实连线，两类规则分别失败时能直接定位。
func _check_constraints(state: RefCounted, plan: Dictionary) -> void:
	for layer in range(1, state.layer_count + 1):
		var seen := {}
		for room in state.rooms_on_layer(layer):
			if not plan.has(room.id):
				continue
			var enemy_id: int = plan[room.id].id
			_check(not seen.has(enemy_id), "第%d行不得出现重复怪物" % layer)
			seen[enemy_id] = true
	for room in state.rooms:
		if not plan.has(room.id):
			continue
		for target_id in room.connections:
			if plan.has(target_id):
				_check(plan[room.id].id != plan[target_id].id, "%s与%s的连线不得出现重复怪物" % [room.id, target_id])


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)
