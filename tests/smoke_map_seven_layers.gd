# 七层地图规则验收：三章多种子、休息位置与数量、全图可达、七次推进、失败配置和旧快照兼容。
extends SceneTree

const GENERATOR := preload("res://scripts/map/map_generator.gd")
const STATE := preload("res://scripts/map/map_state.gd")
const EXPECTED := [1,2,1,2,1,2,1]
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func generate(config: Resource, seed_value: int) -> RefCounted:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return GENERATOR.new().generate(config, rng)

func _run() -> void:
	var rest_layers_seen: Dictionary = {}
	var rest_counts_seen: Dictionary = {}
	for chapter in range(1,4):
		var config: Resource = load("res://data/maps/map_chapter_%d.tres" % chapter)
		check(config.is_valid(), "章节地图配置应合法")
		for seed_value in range(256):
			var state = generate(config,seed_value)
			check(state != null and state.layer_count == 7 and state.rooms.size() == 10, "地图应为七层10房间，底部单小怪")
			check(state.to_dict() == generate(config,seed_value).to_dict(), "同种子房型和路线必须复现")
			var rest_count := 0
			var last_rest_layer := -2
			var reachable: Dictionary = {}
			for layer in range(1,8):
				var rooms: Array = state.rooms_on_layer(layer)
				check(rooms.size() == EXPECTED[layer-1], "每层数量应为1212121")
				for room in rooms:
					if layer == 1:
						check(room.type == STATE.RoomType.NORMAL and room.state == STATE.RoomState.ATTAINABLE, "第一层必须普通且可进")
						reachable[room.id] = true
					else:
						check(reachable.has(room.id), "所有分支节点必须可从首层到达")
					if room.type == STATE.RoomType.REST:
						check(layer >= 3 and layer <= 6, "休息只允许在3~6层")
						check(layer > last_rest_layer + 1, "同层或相邻层不能再次出现休息房")
						last_rest_layer = layer
						rest_count += 1
						rest_layers_seen[layer] = true
					if layer == 7:
						check(room.type == STATE.RoomType.BOSS and room.connections.is_empty(), "最终层应为单Boss终点")
					else:
						check(not room.connections.is_empty(), "每个非Boss节点都有后续路线")
					var unique: Dictionary = {}
					for id in room.connections:
						check(not unique.has(id), "不能生成重复连线")
						unique[id] = true
						check(state.room_by_id(id).layer == layer+1, "连线只指向下一层")
						reachable[id] = true
				check(state.rooms_on_layer(layer).filter(func(room: Dictionary) -> bool: return room.type == STATE.RoomType.BOSS).size() == (1 if layer == 7 else 0), "Boss只能在终层")
			check(rest_count <= 2, "整张地图最多两休息房")
			rest_counts_seen[rest_count] = true
			# 开始不推进，完成才解锁；任取一条真实路线恰好完成七次后通关。
			for step in range(1,8):
				var next: Dictionary = state.get_attainable_rooms()[0]
				check(next.layer == step, "必须依次推进七层")
				state.begin_room(next.id)
				check(not state.boss_visited(), "开始房间不能提前判定通关")
				state.complete_current_room()
				check(state.boss_visited() == (step == 7), "第七次结算才通关")
			check(state.get_attainable_rooms().is_empty(), "七次完成后没有额外推进")
	check(rest_layers_seen.size() == 4, "休息房应可出现在3/4/5/6任意候选层")
	check(rest_counts_seen.has(0) and rest_counts_seen.has(1) and rest_counts_seen.has(2), "覆盖零、一、两个休息房边界")
	_test_invalid_configs()
	_test_legacy_snapshot()
	print("smoke_map_seven_layers: %s (3 chapters x 256 seeds)" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

# 错误配置应在生成前拒绝，不能交付部分地图；失败日志为测试预期。
func _test_invalid_configs() -> void:
	check(generate(null,1) == null, "空配置应拒绝")
	for mode in range(6):
		var config: Resource = load("res://data/maps/map_chapter_1.tres").duplicate()
		match mode:
			0: config.eligible_rest_layers.assign([2])
			1: config.eligible_rest_layers.assign([3,3])
			2: config.max_random_rest_rooms = 3
			3: config.rest_count_by_layer[3] = 1
			4: config.elite_chance_by_layer[0] = 1.0
			5: config.layer_max_rooms.pop_back()
		check(generate(config,1) == null, "非法地图配置必须拒绝")

# 旧三层快照原样恢复，不依据新配置重生成，休息使用和对手缓存仍保留。
func _test_legacy_snapshot() -> void:
	var config: Resource = load("res://data/maps/map_chapter_1.tres").duplicate()
	config.layer_min_rooms.assign([2,2,1])
	config.layer_max_rooms.assign([2,2,1])
	config.elite_chance_by_layer.assign([0.0,0.5,0.0])
	config.rest_count_by_layer.assign([0,1,0])
	config.max_random_rest_rooms = 0
	config.eligible_rest_layers.clear()
	var original = generate(config,42)
	original.set_enemy_id(original.rooms[0].id,"enemy_turtle")
	original.begin_room(original.rooms[0].id)
	for room in original.rooms:
		if room.type == STATE.RoomType.REST:
			room.rest_used = true
	var restored := STATE.new()
	restored.from_dict(original.to_dict())
	check(restored.layer_count == 3 and restored.to_dict() == original.to_dict(), "旧三层快照不得被七层配置改写")
	# 通过完整本局恢复接口和JSON往返再次验证，防止仅测MapState掩盖加载时重生成问题。
	var run_script := load("res://autoload/run_state.gd")
	var source = run_script.new()
	var loaded = run_script.new()
	source.start_new_run(42)
	source.map_state = original
	var payload: Dictionary = JSON.parse_string(JSON.stringify(source.to_dict()))
	check(loaded.from_dict(payload), "旧本局JSON应可恢复")
	check(loaded.map_state.layer_count == 3 and loaded.map_state.to_dict() == original.to_dict(), "完整存档恢复应保留三层、进行中房间、缓存与休息使用")
	source.free()
	loaded.free()
