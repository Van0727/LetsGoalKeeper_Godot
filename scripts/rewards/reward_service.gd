# 奖励服务：按战斗级别生成确定性且不重复的卡牌、战利品候选，并解析稳定卡牌ID。
class_name RewardService
extends RefCounted

const COMMON_CARD_IDS: Array[String] = [
	"card_straight_shot", "card_banana_shot", "card_lob_shot", "card_barrage_shot",
	"card_attack_and_defend", "card_explosion_ball", "card_run_up", "card_weakness",
	"card_bloodthirsty_ball", "card_spiked_ball", "card_rugby_ball", "card_gloves",
	"card_sports_drink", "card_towel",
	"card_pitch_up", "card_pitch_down", "card_pitch_reset",
	"card_banana_left", "card_banana_right",
]
const BOSS_CARD_IDS: Array[String] = [
	"card_energy_shot", "card_shot_group", "card_double_banana_shot",
]
# 普通奖励目录也是 GM 完整清单的来源；新增奖励在这里登记后无需另写界面入口。
const NORMAL_ITEMS: Array[Resource] = [
	preload("res://data/items/item_golden_boot.tres"),
	preload("res://data/items/item_lob_badge.tres"),
	preload("res://data/items/item_banana_scarf.tres"),
	preload("res://data/items/item_golden_left_foot.tres"),
	preload("res://data/items/item_golden_right_foot.tres"),
	preload("res://data/items/item_banana.tres"),
	preload("res://data/items/item_gorilla_doll.tres"),
	preload("res://data/items/item_free_kick_master_license.tres"),
	preload("res://data/items/item_wishing_bracelet.tres"),
	preload("res://data/items/item_parrot_feather.tres"),
	preload("res://data/items/item_national_flip_flops.tres"),
	preload("res://data/items/item_hercules_cup.tres"),
	preload("res://data/items/item_lumberjack_axe.tres"),
	preload("res://data/items/item_nude_license.tres"),
	preload("res://data/items/item_chunghwa_cigarettes.tres"),
	preload("res://data/items/item_rotating_drums.tres"),
	preload("res://data/items/item_drum_isolation_screen.tres"),
	preload("res://data/items/item_racing_drumsticks.tres"),
	preload("res://data/items/item_rhythm_game_trophy.tres"),
	preload("res://data/items/item_double_bass_pedal.tres"),
	preload("res://data/items/item_in_ear_monitor.tres"),
	preload("res://data/items/item_big_drum_mallet.tres"),
	preload("res://data/items/item_spiked_drum_mallet.tres"),
	preload("res://data/items/item_blindfold.tres"),
	preload("res://data/items/item_blank_score.tres"),
	preload("res://data/items/item_rest_score.tres"),
	preload("res://data/items/item_tattoo_sticker.tres"),
	preload("res://data/items/item_bar_dice.tres"),
]
const BOSS_ITEMS: Array[Resource] = [
	preload("res://data/items/item_number_7.tres"),
	preload("res://data/items/item_number_10.tres"),
	preload("res://data/items/item_corner_flag_disabled.tres"),
]


# GM 清单读取普通与 Boss 的完整登记表，包含禁用占位物；不使用三选一抽样结果。
func get_all_items() -> Array[Resource]:
	var result: Array[Resource] = NORMAL_ITEMS.duplicate()
	result.append_array(BOSS_ITEMS)
	return result


# 根据稳定ID加载卡牌；无效ID输出明确错误并返回空值。
func get_card_by_id(card_id: String) -> Resource:
	var path := "res://data/cards/%s.tres" % card_id
	if not ResourceLoader.exists(path):
		push_error("找不到卡牌ID：%s" % card_id)
		_record_missing_resource("card", card_id)
		return null
	return load(path)


# 根据奖励池中的稳定 ID 返回战利品定义；旧存档遇到已下架 ID 时安全忽略并记录诊断。
func get_item_by_id(item_id: String) -> Resource:
	for item in get_all_items():
		if item.item_id == item_id:
			return item
	push_error("找不到战利品ID：%s" % item_id)
	_record_missing_resource("item", item_id)
	return null


# 批量解析本局已拥有战利品，保持获得顺序，以便多个同阶段效果得到稳定结算顺序。
func get_items_by_ids(item_ids: Array[String]) -> Array[Resource]:
	var result: Array[Resource] = []
	for item_id in item_ids:
		var item := get_item_by_id(item_id)
		if item != null:
			result.append(item)
	return result


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
