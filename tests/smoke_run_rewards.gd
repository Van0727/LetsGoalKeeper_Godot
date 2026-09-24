# 本局与奖励冒烟测试：验证固定基础牌库、单局奖励库存、重置及跨战斗成长。
extends SceneTree

const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const ITEM_DEFINITION := preload("res://scripts/items/item_definition.gd")
const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")
const GOLDEN_BOOT := preload("res://data/items/item_golden_boot.tres")
const NUMBER_7 := preload("res://data/items/item_number_7.tres")
const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")

var _failed := false
var _run_state = RUN_STATE_SCRIPT.new()


# 延迟执行以确保 RunState 自动加载节点完成初始化。
func _initialize() -> void:
	call_deferred("_run")


# 覆盖阶段 6 的核心跨场景数据契约。
func _run() -> void:
	var service := REWARD_SERVICE.new()
	_run_state.start_new_run(301)
	_assert_equal(_run_state.deck_card_ids, ["card_straight_shot", "card_straight_shot", "card_straight_shot", "card_gloves", "card_gloves", "card_sports_drink"], "新游戏使用指定六张基础牌库")
	_assert_equal(_run_state.card_reward_stock.get("card_straight_shot"), 0, "开局专属射门不进入奖励池")
	_assert_equal(_run_state.owned_item_ids.size(), 0, "新游戏清空战利品")
	_assert_equal(service.get_item_by_id(4011), GOLDEN_BOOT, "数字 ID 可查找金靴")
	_assert_equal(service.get_item_by_id(4029).item_id, "item_energy_core", "数字 ID 可查找新增能量核心")
	_assert_equal(service.get_item_by_id(9999), null, "无效数字 ID 安全返回空值")
	var energy_core := ITEM_DEFINITION.new()
	energy_core.id = 4029
	energy_core.item_id = "item_energy_core"
	energy_core.run_max_energy_bonus = 1
	_assert_true(_run_state.add_item(energy_core), "获得能量核心")
	_assert_equal(_run_state.run_max_energy_bonus, 1, "能量核心在本次游戏历程永久提高能量上限")
	var energy_battle = BATTLE_CONTROLLER.new()
	root.add_child(energy_battle)
	energy_battle.setup(300, TURTLE, {}, [], _run_state.run_max_energy_bonus)
	_assert_equal(energy_battle.player.max_energy, 4, "后续战斗继承游戏历程能量上限")
	energy_battle.free()

	var first_rng := RandomNumberGenerator.new()
	var second_rng := RandomNumberGenerator.new()
	first_rng.seed = 88
	second_rng.seed = 88
	var first_cards := service.generate_card_choices(false, first_rng, _run_state.card_reward_stock)
	var second_cards := service.generate_card_choices(false, second_rng, _run_state.card_reward_stock)
	_assert_equal(first_cards.size(), 3, "普通战斗生成三张卡牌")
	_assert_equal(_definition_ids(first_cards, "card_id"), _definition_ids(second_cards, "card_id"), "相同seed奖励一致")
	var exhausted_stock: Dictionary = _run_state.card_reward_stock.duplicate(true)
	for card_id in exhausted_stock:
		exhausted_stock[card_id] = 0
	var exhausted_rng := RandomNumberGenerator.new()
	_assert_true(service.generate_card_choices(false, exhausted_rng, exhausted_stock).is_empty(), "全部库存为0时奖励池安全返回空候选")
	_assert_true("card_pitch_up" in service.COMMON_CARD_IDS, "禁用牌仍保留稳定目录键")
	# 临时禁用只影响新奖励；稳定ID仍可读取，保证已有旧存档不会因下架卡牌损坏。
	var disabled_card: Resource = STRAIGHT_SHOT.duplicate(true)
	disabled_card.enabled = false
	_assert_true(not service._is_card_available(disabled_card), "实装状态0的卡牌不进入正常奖励")
	_assert_equal(service.get_card_by_id("card_straight_shot"), STRAIGHT_SHOT, "开局专属牌仍可按稳定ID读取")
	var selected_card_id: String = first_cards[0].card_id
	_run_state.card_reward_stock[selected_card_id] = 2
	_assert_true(_run_state.claim_reward_card(selected_card_id), "确认奖励后卡牌加入本局牌库")
	_assert_equal(_run_state.card_reward_stock[selected_card_id], 1, "库存2领取一次后减为1")
	_assert_true(_run_state.claim_reward_card(selected_card_id), "库存仍大于0时允许再次领取")
	_assert_equal(_run_state.card_reward_stock[selected_card_id], 0, "第二次领取后库存归零")
	_assert_true(not _run_state.claim_reward_card(selected_card_id), "库存归零后不能重复领取")
	var post_claim_rng := RandomNumberGenerator.new()
	post_claim_rng.seed = 88
	_assert_true(selected_card_id not in _definition_ids(service.generate_card_choices(false, post_claim_rng, _run_state.card_reward_stock), "card_id"), "库存归零的卡牌不再进入候选")
	_assert_equal(_run_state.deck_card_ids.size(), 8, "两次有效领取各增加一张卡")

	_assert_true(_run_state.add_item(GOLDEN_BOOT), "首次获得金靴")
	_assert_true(4011 in _run_state.owned_item_ids, "本局仅保存金靴数字 ID")
	_assert_true(not _run_state.add_item(GOLDEN_BOOT), "已拥有战利品不能重复获得")
	_assert_true(_run_state.add_item(NUMBER_7), "获得直球专属战利品")
	_assert_equal(_run_state.damage_modifiers.all, 1, "所有射门加成汇总")
	_assert_equal(_run_state.damage_modifiers.straight, 1, "直球加成汇总")
	_assert_true(_run_state.remove_item(NUMBER_7), "GM 可移除已拥有直球战利品")
	_assert_equal(_run_state.damage_modifiers.straight, 0, "移除后撤销旧式射门加成")
	_assert_true(not _run_state.remove_item(NUMBER_7), "重复移除不能影响其他本局数据")
	_assert_true(_run_state.add_item(NUMBER_7), "移除后可以重新勾选获得")
	_assert_equal(_run_state.damage_modifiers.straight, 1, "重新获得后只加成一次")

	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(302, TURTLE, _run_state.damage_modifiers)
	battle.player_attack(0)
	battle.play_card(STRAIGHT_SHOT)
	_assert_equal(battle.enemy.health, 42, "下一战直球获得两点战利品加成")
	_run_state.record_battle_health(73)
	_run_state.complete_reward()
	_assert_equal(_run_state.player_hp, 73, "战后生命跨房间保留")
	_assert_equal(_run_state.battles_won, 1, "完成奖励后推进胜场")
	battle.free()

	_run_state.start_new_run(303)
	_assert_equal(_run_state.deck_card_ids.size(), 6, "再次新游戏恢复六张基础牌库")
	_assert_equal(_run_state.card_reward_stock[selected_card_id], 1, "再次新游戏恢复配表奖励库存")
	_assert_equal(_run_state.damage_modifiers.all, 0, "再次新游戏清除伤害加成")
	_assert_equal(_run_state.run_max_energy_bonus, 0, "再次新游戏清除游戏历程能量上限加成")
	_assert_equal(_run_state.player_hp, 100, "再次新游戏恢复生命")
	_run_state.free()

	if _failed:
		quit(1)
		return
	print("smoke_run_rewards: PASS")
	quit()


# 提取 Resource 的稳定ID数组，供确定性奖励比较。
func _definition_ids(definitions: Array[Resource], property_name: String) -> Array:
	var ids: Array = []
	for definition in definitions:
		ids.append(definition.get(property_name))
	return ids


# 通用相等断言。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
