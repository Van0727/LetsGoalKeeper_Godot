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

# 房间三态：初始锁定，当前层可进；内容结算完成后本房已访问且同层其余路线被锁。
enum RoomState {
	LOCKED,
	ATTAINABLE,
	VISITED,
}

var layer_count := 0
# 每项保存房间运行数据：id、layer、index、type、state、connections、enemy_id、rest_used。
var rooms: Array[Dictionary] = []
# 当前正在结算的房间 ID；只有完成战斗奖励或休息结算后才会清空并推进路线。
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


# Boss 房完成结算才代表本章路线走完；仅开始 Boss 战不会提前判定通关。
func boss_visited() -> bool:
	for room in rooms:
		if room.type == RoomType.BOSS and room.state == RoomState.VISITED:
			return true
	return false


# 生成器使用的内部入口：把房间登记进状态，不负责状态流转。
func add_room(room: Dictionary) -> void:
	rooms.append(room)
	_id_map[room.id] = room


# 开始一个可进房间：仅记录进行中房间，不提前修改三态或解锁后续路线。
# 已有房间正在结算时拒绝切换，避免从战斗/休息流程中途改走另一条路线。
func begin_room(room_id: String) -> Dictionary:
	if not current_room_id.is_empty():
		return {}
	var room := room_by_id(room_id)
	if room.is_empty() or room.state != RoomState.ATTAINABLE:
		return {}
	current_room_id = room_id
	return room


# 完成当前房间：提交已访问状态、锁定同层其他选择并解锁真实连线指向的下一层。
# 该接口只能由战斗奖励全部领取或休息房结算调用，失败和中途退出不得调用。
func complete_current_room() -> Dictionary:
	if current_room_id.is_empty():
		return {}
	var room := room_by_id(current_room_id)
	if room.is_empty() or room.state != RoomState.ATTAINABLE:
		return {}
	room.state = RoomState.VISITED
	for sibling in rooms_on_layer(room.layer):
		if sibling.id != room.id and sibling.state == RoomState.ATTAINABLE:
			sibling.state = RoomState.LOCKED
	for next_id in room.connections:
		var next_room := room_by_id(next_id)
		if not next_room.is_empty() and next_room.state == RoomState.LOCKED:
			next_room.state = RoomState.ATTAINABLE
	current_room_id = ""
	return room


# 取消尚未完成的房间，不改变任何房间三态；用于放弃战斗或结束失败的本局。
func cancel_current_room() -> bool:
	if current_room_id.is_empty():
		return false
	current_room_id = ""
	return true


# 消耗当前休息房的唯一治疗机会；返回 false 表示房型错误、没有进行中房间或已经使用。
func mark_current_rest_used() -> bool:
	var room := room_by_id(current_room_id)
	if room.is_empty() or room.type != RoomType.REST or room.get("rest_used", false):
		return false
	room.rest_used = true
	return true


# 缓存数字怪物ID的十进制字符串，保留原存档字段类型；旧英文值由怪物目录迁移。
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


# 用快照整体恢复地图状态；对缺失字段使用默认值并忽略非字典房间，兼容残缺旧档。
func from_dict(data: Dictionary) -> void:
	clear()
	layer_count = maxi(int(data.get("layer_count", 0)), 0)
	current_room_id = str(data.get("current_room_id", ""))
	var saved_rooms: Variant = data.get("rooms", [])
	if saved_rooms is not Array:
		saved_rooms = []
	for room in saved_rooms:
		if room is Dictionary and room.has("id"):
			# JSON 数字统一恢复为整数，并补齐房间运行字段，避免浮点反序列化影响状态比较。
			var restored_room := {
				"id": str(room.get("id", "")),
				"layer": int(room.get("layer", 0)),
				"index": int(room.get("index", 0)),
				"type": int(room.get("type", RoomType.NORMAL)),
				"state": int(room.get("state", RoomState.LOCKED)),
				"connections": room.get("connections", []).duplicate() if room.get("connections", []) is Array else [],
				"enemy_id": str(room.get("enemy_id", "")),
				"rest_used": bool(room.get("rest_used", false)),
			}
			if not restored_room.id.is_empty():
				add_room(restored_room)
	if not current_room_id.is_empty() and room_by_id(current_room_id).is_empty():
		current_room_id = ""
