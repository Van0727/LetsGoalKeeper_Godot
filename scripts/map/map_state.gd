# 单局地图运行时状态：保存房间节点、连线、三态流转和当前房间，不包含任何 UI。
class_name MapState
extends RefCounted

# 房型：普通/精英/Boss 与遭遇池 Tier 数字一一对应，休息房不进入战斗。
enum RoomType {
	NORMAL,
	ELITE,
	BOSS,
	REST,
}

# 房间三态：初始锁定，只有当前层可进，进入后本房已完成且同层其余路线被锁。
enum RoomState {
	LOCKED,
	ATTAINABLE,
	VISITED,
}

var layer_count := 0
# 每项保存房间运行数据：id、layer、index、type、state、connections、enemy_id。
var rooms: Array[Dictionary] = []
# 当前所在房间 ID；新一局开始前为空字符串。
var current_room_id := ""

var _id_map := {}


# 清空并重建一个空地图，供新局生成前重置。
func clear() -> void:
	layer_count = 0
	rooms.clear()
	current_room_id = ""
	_id_map.clear()


# 按本层房间顺序返回房间列表（浅拷贝，房间本身仍是共享字典）。
func rooms_on_layer(layer: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room in rooms:
		if room.layer == layer:
			result.append(room)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.index < b.index)
	return result


# 返回当前可进入的所有房间，供界面高亮和测试使用。
func get_attainable_rooms() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room in rooms:
		if room.state == RoomState.ATTAINABLE:
			result.append(room)
	return result


# 按稳定 ID 返回房间字典；不存在时返回空字典。
func room_by_id(room_id: String) -> Dictionary:
	return _id_map.get(room_id, {})


# Boss 已进入即代表本局路线走完，此后不允许再生成新的可进房间。
func boss_visited() -> bool:
	for room in rooms:
		if room.type == RoomType.BOSS and room.state == RoomState.VISITED:
			return true
	return false


# 生成器使用的内部入口：把房间登记进状态，不负责状态流转。
func add_room(room: Dictionary) -> void:
	rooms.append(room)
	_id_map[room.id] = room


# 进入一个可进房间：标记完成、锁定同层其余路线，并解锁其连线的下一层房间。
# 非法进入（锁定/已访问/不存在）不改动状态并返回空字典。
func enter_room(room_id: String) -> Dictionary:
	var room := room_by_id(room_id)
	if room.is_empty() or room.state != RoomState.ATTAINABLE:
		return {}
	room.state = RoomState.VISITED
	current_room_id = room_id
	for sibling in rooms_on_layer(room.layer):
		if sibling.id != room_id and sibling.state == RoomState.ATTAINABLE:
			sibling.state = RoomState.LOCKED
	for next_id in room.connections:
		var next_room := room_by_id(next_id)
		if not next_room.is_empty() and next_room.state == RoomState.LOCKED:
			next_room.state = RoomState.ATTAINABLE
	return room


# 记录该房间选定的敌人稳定 ID（进入战斗时确定，重进同一场不重新随机）。
func set_enemy_id(room_id: String, enemy_id: String) -> void:
	var room := room_by_id(room_id)
	if not room.is_empty():
		room.enemy_id = enemy_id


# 房间缓存可复现敌人；未选择过返回空字符串。
func get_enemy_id(room_id: String) -> String:
	var room := room_by_id(room_id)
	if room.is_empty():
		return ""
	return room.get("enemy_id", "")


# 导出纯数据快照，用于“退出后继续不重新随机”的恢复与后续存档。
func to_dict() -> Dictionary:
	return {
		"layer_count": layer_count,
		"current_room_id": current_room_id,
		"rooms": rooms.duplicate(true),
	}


# 用快照整体恢复地图状态；调用方负责保证数据来自同一版本结构。
func from_dict(data: Dictionary) -> void:
	clear()
	layer_count = data.get("layer_count", 0)
	current_room_id = data.get("current_room_id", "")
	for room in data.get("rooms", []):
		add_room(room.duplicate(true))
