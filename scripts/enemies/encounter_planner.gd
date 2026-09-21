# 地图怪物规划器：使用确定性回溯为全图分配敌人，同行与相邻层真实连线不得出现同一怪物。
class_name EncounterPlanner
extends RefCounted


# 返回 room_id -> 敌人资源的完整方案；无解时返回空字典，由界面或战斗入口执行安全降级。
# 已有的有效缓存视为固定选择，避免旧存档重进时重掷已见过的怪物。
static func plan(map_state: RefCounted, pool: Resource, catalog: Resource, run_seed: int) -> Dictionary:
	if map_state == null or pool == null:
		return {}
	var rooms: Array[Dictionary] = []
	for layer in range(1, map_state.layer_count + 1):
		for room in map_state.rooms_on_layer(layer):
			if room.type != 3: # MapState.RoomType.REST，避免该纯逻辑工具强依赖脚本常量。
				rooms.append(room)
	var candidates_by_room := {}
	for room in rooms:
		var cached_id := str(room.get("enemy_id", ""))
		if not cached_id.is_empty():
			var cached_enemy: Resource = catalog.resolve_cached_id(cached_id) if catalog != null else null
			if cached_enemy != null:
				candidates_by_room[room.id] = [cached_enemy]
				continue
		var raw_candidates: Array[Resource] = pool.get_planning_candidates(room.type)
		var candidates: Array[Resource] = []
		for candidate in raw_candidates:
			# 旧章节资源的数字ID为0，规划前必须通过目录白名单转为正式ID，否则所有旧怪物会被误判为同一只。
			var normalized: Resource = candidate
			if candidate.id <= 0 and catalog != null:
				normalized = catalog.resolve_cached_id(candidate.enemy_id)
			if normalized != null:
				candidates.append(normalized)
		_shuffle_tier_groups(candidates, run_seed, room)
		candidates_by_room[room.id] = candidates
	var result := {}
	return result if _assign_room(0, rooms, candidates_by_room, map_state, result) else {}


# 按稳定房间顺序回溯；直到后续房间也可分配时才确认当前选择。
static func _assign_room(index: int, rooms: Array[Dictionary], candidates_by_room: Dictionary, map_state: RefCounted, result: Dictionary) -> bool:
	if index >= rooms.size():
		return true
	var room: Dictionary = rooms[index]
	for enemy: Resource in candidates_by_room.get(room.id, []):
		if _conflicts(room, enemy, map_state, result):
			continue
		result[room.id] = enemy
		if _assign_room(index + 1, rooms, candidates_by_room, map_state, result):
			return true
		result.erase(room.id)
	return false


# 约束只比较已分配节点：同行全部互斥，相邻行仅真实连线的房间互斥。
static func _conflicts(room: Dictionary, enemy: Resource, map_state: RefCounted, result: Dictionary) -> bool:
	for other_id in result:
		var other_enemy: Resource = result[other_id]
		if other_enemy.id != enemy.id:
			continue
		var other: Dictionary = map_state.room_by_id(other_id)
		if other.layer == room.layer:
			return true
		if absi(other.layer - room.layer) == 1 and (room.id in other.connections or other.id in room.connections):
			return true
	return false


# 每个房间使用独立派生 seed；只在同一优先级组内洗牌，始终先尝试房型匹配的怪物。
static func _shuffle_tier_groups(candidates: Array[Resource], run_seed: int, room: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, room.layer, room.index, 1701])
	var preferred_count := 0
	while preferred_count < candidates.size() and candidates[preferred_count].tier == room.type:
		preferred_count += 1
	_shuffle_range(candidates, 0, preferred_count, rng)
	_shuffle_range(candidates, preferred_count, candidates.size(), rng)


# Fisher-Yates 只处理半开区间，避免备选怪物被洗到房型首选之前。
static func _shuffle_range(candidates: Array[Resource], begin: int, end: int, rng: RandomNumberGenerator) -> void:
	for index in range(end - 1, begin, -1):
		var swap_index := rng.randi_range(begin, index)
		var temporary := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temporary
