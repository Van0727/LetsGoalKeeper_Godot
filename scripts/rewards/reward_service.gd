# 奖励服务：卡牌仍按英文稳定 ID；战利品只按 CSV 数字 ID 参与运行时查询和排重。
class_name RewardService
extends RefCounted

const COMMON_CARD_IDS: Array[String] = [
	"card_straight_shot", "card_banana_shot", "card_lob_shot", "card_barrage_shot",
	"card_attack_and_defend", "card_explosion_ball", "card_run_up", "card_weakness",
	"card_bloodthirsty_ball", "card_spiked_ball", "card_rugby_ball", "card_gloves",
	"card_sports_drink", "card_towel",
	"card_pitch_up", "card_pitch_down", "card_pitch_reset",
	"card_banana_left", "card_banana_right",
	"card_outside_curve", "card_samba_duet", "card_spinning_hat_trick",
	"card_cutback_triangle", "card_rainbow_dribble", "card_agile_switch",
	"card_chain_feint", "card_carnival_beat", "card_mexican_wave",
	"card_double_kick_combo", "card_rapid_fill", "card_shield_bash",
	"card_mallet_warmup", "card_tempo_acceleration", "card_pressure_buildup",
	"card_aftershock_armor", "card_shed_armor", "card_closing_stance",
	"card_cymbal_block", "card_reinforced_post", "card_layered_defense",
	"card_perfect_block",
]
const BOSS_CARD_IDS: Array[String] = [
	"card_energy_shot", "card_shot_group", "card_double_banana_shot",
	"card_carnival_finale",
	"card_gate_breaker",
]
const ITEM_CATALOG := preload("res://data/items/item_catalog.tres")


# GM 清单读取配表生成的完整战利品目录，包含禁用占位物；不使用三选一抽样结果。
func get_all_items() -> Array[Resource]:
	return ITEM_CATALOG.items.duplicate()


# GM 卡牌清单与奖励池共用同一稳定 ID 目录，保证新增可获得卡牌后无需额外维护调试入口。
func get_all_cards() -> Array[Resource]:
	var result: Array[Resource] = []
	var all_ids: Array[String] = COMMON_CARD_IDS.duplicate()
	all_ids.append_array(BOSS_CARD_IDS)
	for card_id in all_ids:
		var card := get_card_by_id(card_id)
		if card != null:
			result.append(card)
	return result


# 根据稳定ID加载卡牌；无效ID输出明确错误并返回空值。
func get_card_by_id(card_id: String) -> Resource:
	var path := "res://data/cards/%s.tres" % card_id
	if not ResourceLoader.exists(path):
		push_error("找不到卡牌ID：%s" % card_id)
		_record_missing_resource("card", card_id)
		return null
	return load(path)


# 根据唯一数字 ID 返回战利品定义；无效值安全忽略并记录诊断。
func get_item_by_id(item_id: int) -> Resource:
	for item in get_all_items():
		if item.id == item_id:
			return item
	push_error("找不到战利品ID：%s" % item_id)
	_record_missing_resource("item", item_id)
	return null


# 批量解析本局已拥有战利品，保持获得顺序，以便多个同阶段效果得到稳定结算顺序。
func get_items_by_ids(item_ids: Array[int]) -> Array[Resource]:
	var result: Array[Resource] = []
	for item_id in item_ids:
		var item := get_item_by_id(item_id)
		if item != null:
			result.append(item)
	return result


# 缺失固定定义同时写入结构化诊断，便于外部测试包定位坏 ID。
func _record_missing_resource(resource_type: String, resource_id: Variant) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var diagnostics := tree.root.get_node_or_null("DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("resource", "missing", {
			"resource_type": resource_type,
			"resource_id": resource_id,
		})


# 英文键只服务 v1 旧存档迁移，不供战斗、奖励或 GM 运行时调用。
func get_item_id_by_legacy_key(legacy_key: String) -> int:
	for item in get_all_items():
		if item.item_id == legacy_key:
			return item.id
	return 0


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
		owned_item_ids: Array[int],
		rng: RandomNumberGenerator
) -> Array[Resource]:
	var candidates: Array[Resource] = []
	var expected_rarity := 1 if is_boss else 0
	for item in get_all_items():
		if item.rarity == expected_rarity and item.enabled and item.id not in owned_item_ids:
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
