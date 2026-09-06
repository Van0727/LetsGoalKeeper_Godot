# 奖励服务：按战斗级别生成确定性且不重复的卡牌、战利品候选，并解析稳定卡牌ID。
class_name RewardService
extends RefCounted

const COMMON_CARD_IDS: Array[String] = [
	"card_straight_shot", "card_banana_shot", "card_lob_shot", "card_barrage_shot",
	"card_attack_and_defend", "card_explosion_ball", "card_run_up", "card_weakness",
	"card_bloodthirsty_ball", "card_spiked_ball", "card_rugby_ball", "card_gloves",
	"card_sports_drink", "card_towel",
]
const BOSS_CARD_IDS: Array[String] = [
	"card_energy_shot", "card_shot_group", "card_double_banana_shot",
]
const NORMAL_ITEMS: Array[Resource] = [
	preload("res://data/items/item_golden_boot.tres"),
	preload("res://data/items/item_lob_badge.tres"),
	preload("res://data/items/item_banana_scarf.tres"),
]
const BOSS_ITEMS: Array[Resource] = [
	preload("res://data/items/item_number_7.tres"),
	preload("res://data/items/item_number_10.tres"),
	preload("res://data/items/item_corner_flag_disabled.tres"),
]


# 根据稳定ID加载卡牌；无效ID输出明确错误并返回空值。
func get_card_by_id(card_id: String) -> Resource:
	var path := "res://data/cards/%s.tres" % card_id
	if not ResourceLoader.exists(path):
		push_error("找不到卡牌ID：%s" % card_id)
		_record_missing_resource("card", card_id)
		return null
	return load(path)


# 缺失固定定义同时写入结构化诊断，便于外部测试包定位坏 ID。
func _record_missing_resource(resource_type: String, resource_id: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var diagnostics := tree.root.get_node_or_null("DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("resource", "missing", {
			"resource_type": resource_type,
			"resource_id": resource_id,
		})


# 生成最多三张互不重复的卡牌，Boss战只使用Boss卡池。
func generate_card_choices(is_boss: bool, rng: RandomNumberGenerator) -> Array[Resource]:
	var ids: Array[String] = BOSS_CARD_IDS.duplicate() if is_boss else COMMON_CARD_IDS.duplicate()
	_shuffle(ids, rng)
	var choices: Array[Resource] = []
	for index in range(mini(3, ids.size())):
		var card := get_card_by_id(ids[index])
		if card != null:
			choices.append(card)
	return choices


# 排除已拥有及禁用战利品后生成最多三个选项；不足时不复制占位奖励。
func generate_item_choices(
		is_boss: bool,
		owned_item_ids: Array[String],
		rng: RandomNumberGenerator
) -> Array[Resource]:
	var source: Array[Resource] = BOSS_ITEMS if is_boss else NORMAL_ITEMS
	var candidates: Array[Resource] = []
	for item in source:
		if item.enabled and item.item_id not in owned_item_ids:
			candidates.append(item)
	_shuffle(candidates, rng)
	candidates.resize(mini(3, candidates.size()))
	return candidates


# 使用注入随机数执行原地洗牌，确保相同本局seed和房间进度得到相同奖励。
func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temporary
