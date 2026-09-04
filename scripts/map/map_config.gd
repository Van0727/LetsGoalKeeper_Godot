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


# 校验层配置数组长度是否一致；不一致时输出明确错误供内容排查。
func is_valid() -> bool:
	var sizes := [layer_min_rooms.size(), layer_max_rooms.size(), elite_chance_by_layer.size(), rest_count_by_layer.size()]
	if sizes.min() != sizes.max():
		push_error("第%d章地图配置的层数组长度不一致" % chapter)
		return false
	return sizes[0] > 0
