# 章节地图固定定义：只描述每层房间数量和房型权重，不保存本局地图节点状态。
class_name MapConfig
extends Resource

@export var chapter := 1
# 每层最少房间数，数组下标从第1层开始；最后一层固定为单房间 Boss。
@export var layer_min_rooms: Array[int] = []
# 每层最多房间数，与 layer_min_rooms 一一对应。
@export var layer_max_rooms: Array[int] = []
# 每层战斗房成为精英房的概率（0~1），休息房与 Boss 房不参与掷点。
@export var elite_chance_by_layer: Array[float] = []
# 每层固定插入的休息房数量（本局首版：第2层固定1个）。
@export var rest_count_by_layer: Array[int] = []


# 校验层配置结构和逐层数值，防止空层、反向随机范围或多个 Boss 进入运行时。
func is_valid() -> bool:
	var sizes := [layer_min_rooms.size(), layer_max_rooms.size(), elite_chance_by_layer.size(), rest_count_by_layer.size()]
	if sizes.min() != sizes.max():
		push_error("第%d章地图配置的层数组长度不一致" % chapter)
		return false
	if chapter < 1 or sizes[0] == 0:
		push_error("地图章节必须大于0且至少配置一层")
		return false

	for layer_index in range(sizes[0]):
		var minimum := layer_min_rooms[layer_index]
		var maximum := layer_max_rooms[layer_index]
		var rest_count := rest_count_by_layer[layer_index]
		var elite_chance := elite_chance_by_layer[layer_index]
		if minimum < 1 or maximum < minimum:
			push_error("第%d章第%d层房间范围非法：%d~%d" % [chapter, layer_index + 1, minimum, maximum])
			return false
		if rest_count < 0 or rest_count > minimum:
			push_error("第%d章第%d层休息房数量超过该层最少房间数" % [chapter, layer_index + 1])
			return false
		if elite_chance < 0.0 or elite_chance > 1.0:
			push_error("第%d章第%d层精英概率必须在0~1之间" % [chapter, layer_index + 1])
			return false

	var last_index: int = sizes[0] - 1
	if layer_min_rooms[last_index] != 1 or layer_max_rooms[last_index] != 1:
		push_error("第%d章最后一层必须固定为单个Boss房" % chapter)
		return false
	if rest_count_by_layer[last_index] != 0:
		push_error("第%d章Boss层不能配置休息房" % chapter)
		return false
	return true
