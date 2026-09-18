# 章节地图固定定义：描述章节显示主题、每层房间数量和房型权重，不保存本局地图节点状态。
class_name MapConfig
extends Resource

@export var chapter := 1
# 章节名称与占位配色让尚无正式美术的三章仍可清楚区分；后续替换背景资源时保持同一数据入口。
@export var chapter_name := "第一章"
@export var map_background_color := Color(0.04, 0.11, 0.16, 1.0)
@export var battle_background_color := Color(0.04, 0.09, 0.12, 1.0)
# 每层最少房间数，数组下标从第1层开始；最后一层固定为单房间 Boss。
@export var layer_min_rooms: Array[int] = []
# 每层最多房间数，与 layer_min_rooms 一一对应。
@export var layer_max_rooms: Array[int] = []
# 每层战斗房成为精英房的概率（0~1），休息房与 Boss 房不参与掷点。
@export var elite_chance_by_layer: Array[float] = []
# 兼容旧地图配置的固定休息房数量；随机模式要求全部为零，避免两种来源叠加。
@export var rest_count_by_layer: Array[int] = []
# 新地图从允许层中随机选择0～上限个休息房，每层最多一个且相邻层不能同时出现。
@export_range(0, 2, 1) var max_random_rest_rooms := 0
@export var eligible_rest_layers: Array[int] = []


# 校验层配置结构和逐层数值，防止空层、反向随机范围或多个 Boss 进入运行时。
func is_valid() -> bool:
	var sizes := [layer_min_rooms.size(), layer_max_rooms.size(), elite_chance_by_layer.size(), rest_count_by_layer.size()]
	if sizes.min() != sizes.max():
		push_error("第%d章地图配置的层数组长度不一致" % chapter)
		return false
	if chapter < 1 or sizes[0] == 0:
		push_error("地图章节必须大于0且至少配置一层")
		return false
	if chapter_name.strip_edges().is_empty():
		push_error("第%d章缺少章节显示名称" % chapter)
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
	if max_random_rest_rooms < 0 or max_random_rest_rooms > 2:
		push_error("随机休息房上限必须在0~2之间")
		return false
	if elite_chance_by_layer[0] != 0.0 or rest_count_by_layer[0] != 0:
		push_error("地图第一层必须全部为普通小怪")
		return false
	var seen: Array[int] = []
	for layer in eligible_rest_layers:
		if layer < 3 or layer > 6 or layer >= sizes[0] or layer in seen:
			push_error("随机休息房候选层必须在3~6、位于Boss前且无重复")
			return false
		seen.append(layer)
	if max_random_rest_rooms > 0:
		if eligible_rest_layers.is_empty() or rest_count_by_layer.any(func(value: int) -> bool: return value != 0):
			push_error("随机休息房模式必须提供候选层，且不能配置固定休息房")
			return false
	return true
