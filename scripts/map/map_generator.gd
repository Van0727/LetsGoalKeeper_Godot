# 地图生成器：按章节固定配置和注入随机数生成三层房间与连线，纯逻辑不依赖界面。
class_name MapGenerator
extends RefCounted

const MAP_STATE := preload("res://scripts/map/map_state.gd")


# 按章节加载对应地图配置；缺失时输出明确错误并返回空值。
func load_config_for_chapter(chapter: int) -> Resource:
	var path := "res://data/maps/map_chapter_%d.tres" % chapter
	if not ResourceLoader.exists(path):
		push_error("找不到第%d章的地图配置：%s" % [chapter, path])
		return null
	return load(path)


# 生成一张新地图：层数与房间数来自配置，连线保持稀疏并保证上下层每个房间都参与路线。
func generate(config: Resource, rng: RandomNumberGenerator) -> MapState:
	if config == null or not config.is_valid():
		return null
	var state := MAP_STATE.new()
	state.layer_count = config.layer_min_rooms.size()

	# 先按层确定房型，再登记全部房间，最后统一连线，保证同 seed 下结构完全可复现。
	for layer in range(1, state.layer_count + 1):
		var layer_index := layer - 1
		var count := rng.randi_range(config.layer_min_rooms[layer_index], config.layer_max_rooms[layer_index])
		var types := _plan_layer_types(config, layer, count, rng)
		for index in range(count):
			var room := {
				"id": "%d-%d" % [layer, index],
				"layer": layer,
				"index": index,
				"type": types[index],
				"state": MAP_STATE.RoomState.LOCKED,
				"connections": [],
				"enemy_id": "",
				"rest_used": false,
			}
			if layer == 1:
				room.state = MAP_STATE.RoomState.ATTAINABLE
			state.add_room(room)

	# 先给每个上层房间至少一条随机出边，再补齐没有入边的下层房间；避免全连接让路线选择失去意义。
	for layer in range(1, state.layer_count):
		var current_rooms := state.rooms_on_layer(layer)
		var next_rooms := state.rooms_on_layer(layer + 1)
		for room in current_rooms:
			var target: Dictionary = next_rooms[rng.randi_range(0, next_rooms.size() - 1)]
			room.connections.append(target.id)
		for next_room in next_rooms:
			if _has_incoming_connection(current_rooms, next_room.id):
				continue
			var source: Dictionary = current_rooms[rng.randi_range(0, current_rooms.size() - 1)]
			if next_room.id not in source.connections:
				source.connections.append(next_room.id)
	return state


# 判断下一层房间是否已被任一上层房间连接，用于补齐不可达节点。
func _has_incoming_connection(current_rooms: Array[Dictionary], target_id: String) -> bool:
	for room in current_rooms:
		if target_id in room.connections:
			return true
	return false


# 规划某一层的房型序列；休息房插在随机位置，其余战斗房按层权重掷精英。
func _plan_layer_types(config: Resource, layer: int, count: int, rng: RandomNumberGenerator) -> Array:
	var layer_index := layer - 1
	var types: Array = []
	for _index in range(count):
		types.append(MAP_STATE.RoomType.NORMAL)

	var is_last_layer: bool = layer == config.layer_min_rooms.size()
	if is_last_layer:
		# 最后一层固定全部为 Boss（首版配置只有1个）。
		for slot in range(types.size()):
			types[slot] = MAP_STATE.RoomType.BOSS
		return types

	# 固定休息房数量不得超过房间总数，配置错误时以明确日志提示并截断。
	var rest_count := clampi(config.rest_count_by_layer[layer_index], 0, count)
	for _rest_index in range(rest_count):
		var rest_slot := rng.randi_range(0, count - 1)
		while types[rest_slot] != MAP_STATE.RoomType.NORMAL:
			rest_slot = (rest_slot + 1) % count
		types[rest_slot] = MAP_STATE.RoomType.REST

	# 剩余槽位才是战斗房，按本层精英概率掷点；第1层概率为0则全部普通。
	var elite_chance: float = clampf(config.elite_chance_by_layer[layer_index], 0.0, 1.0)
	for slot in range(types.size()):
		if types[slot] != MAP_STATE.RoomType.NORMAL:
			continue
		if rng.randf() < elite_chance:
			types[slot] = MAP_STATE.RoomType.ELITE
	return types
