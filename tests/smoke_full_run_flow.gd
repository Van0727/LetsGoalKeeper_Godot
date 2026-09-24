# 阶段 8 完整流程冒烟测试：从新游戏走过三章路线、战斗、奖励与最终通关，并验证失败重置边界。
extends SceneTree

const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const MAP_STATE := preload("res://scripts/map/map_state.gd")
const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")

var _failed := false
var _run_state = RUN_STATE_SCRIPT.new()
var _reward_service := REWARD_SERVICE.new()


# 延迟执行，让 Resource 与脚本类完成初始化后再模拟完整本局。
func _initialize() -> void:
	call_deferred("_run")


# 每章选择一条合法路线；战斗用核心 GM 胜利入口缩短测试，但奖励与章节推进走正式接口。
func _run() -> void:
	_run_state.start_new_run(8808)
	var combat_count := 0
	while _run_state.run_status == _run_state.RunStatus.ACTIVE:
		var chapter_before: int = _run_state.chapter
		var available: Array[Dictionary] = _run_state.map_state.get_attainable_rooms()
		_assert_true(not available.is_empty(), "进行中的本局始终存在可进入房间")
		if available.is_empty():
			break
		var room: Dictionary = _run_state.map_state.begin_room(available[0].id)
		_assert_true(not room.is_empty(), "只能进入当前可达房间")
		if room.type == MAP_STATE.RoomType.REST:
			_run_state.use_current_rest(20)
			_run_state.complete_current_room()
			continue

		combat_count += 1
		var enemy: Resource = _pick_enemy(room, combat_count)
		var battle = BATTLE_CONTROLLER.new()
		root.add_child(battle)
		var victory := {"value": false}
		battle.battle_finished.connect(func(won: bool) -> void: victory.value = won)
		battle.setup(_run_state.seed + combat_count, enemy, _run_state.damage_modifiers)
		_assert_true(battle.debug_force_victory(), "路线战斗可通过统一胜利出口结束")
		_assert_true(victory.value, "战斗核心广播胜利结果")
		_run_state.record_battle_health(battle.player.health)
		battle.free()

		var is_boss: bool = room.type == MAP_STATE.RoomType.BOSS
		_run_state.pending_reward_is_boss = is_boss
		_take_rewards(is_boss, combat_count)
		var flow_result: int = _run_state.complete_reward_and_advance()
		if not is_boss:
			_assert_equal(flow_result, _run_state.RewardFlowResult.MAP_CONTINUES, "普通房奖励后继续本章")
		elif chapter_before < _run_state.FINAL_CHAPTER:
			_assert_equal(flow_result, _run_state.RewardFlowResult.CHAPTER_ADVANCED, "前两章 Boss 后切换章节")
		else:
			_assert_equal(flow_result, _run_state.RewardFlowResult.RUN_COMPLETED, "第三章 Boss 后完成本局")

	_assert_equal(_run_state.chapter, 3, "完整路线最终停在第三章")
	_assert_equal(_run_state.run_status, _run_state.RunStatus.COMPLETED, "完整路线进入通关状态")
	_assert_equal(_run_state.battles_won, combat_count, "所有战斗奖励各结算一次")
	_test_failure_and_new_run_reset()
	_run_state.free()

	if _failed:
		quit(1)
		return
	print("smoke_full_run_flow: PASS")
	quit()


# 房间类型直接对应遭遇级别，同一房间种子只选择一个已启用定义。
func _pick_enemy(room: Dictionary, combat_count: int) -> Resource:
	var pool: Resource = load("res://data/encounters/chapter_%d.tres" % _run_state.chapter)
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_state.seed + combat_count * 97
	var enemy: Resource = pool.pick_enemy(room.type, rng)
	_assert_true(enemy != null, "三章每种生成房型都有可用敌人")
	return enemy


# 每场都领取卡牌，只有 Boss 额外领取战利品；两种分支共用统一房间提交顺序。
func _take_rewards(is_boss: bool, combat_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _run_state.seed + combat_count * 1009 + 61
	var cards: Array[Resource] = _reward_service.generate_card_choices(is_boss, rng, _run_state.card_reward_stock)
	_assert_true(not cards.is_empty(), "每场战斗都有卡牌奖励")
	if not cards.is_empty():
		_assert_true(_run_state.claim_reward_card(cards[0].card_id), "领取卡牌后原子扣减本局库存")
	var item_count_before: int = _run_state.owned_item_ids.size()
	if is_boss:
		var items: Array[Resource] = _reward_service.generate_item_choices(true, _run_state.owned_item_ids, rng)
		if not items.is_empty():
			_run_state.add_item(items[0])
		_assert_true(_run_state.owned_item_ids.size() >= item_count_before, "Boss 奖励允许增加一件战利品")
	else:
		_assert_equal(_run_state.owned_item_ids.size(), item_count_before, "小怪胜利不发放战利品")


# 战败不能提交房间；随后新游戏必须覆盖通关、失败和全部成长数据。
func _test_failure_and_new_run_reset() -> void:
	_run_state.start_new_run(9901)
	var first_room: Dictionary = _run_state.map_state.get_attainable_rooms()[0]
	_run_state.map_state.begin_room(first_room.id)
	_run_state.record_battle_health(0)
	_run_state.mark_run_failed()
	_run_state.cancel_current_room()
	_assert_equal(first_room.state, MAP_STATE.RoomState.ATTAINABLE, "战败房间不被误记为完成")
	_assert_equal(_run_state.run_status, _run_state.RunStatus.FAILED, "战败终止当前本局")

	_run_state.start_new_run(9902)
	_assert_equal(_run_state.run_status, _run_state.RunStatus.ACTIVE, "新游戏恢复进行中状态")
	_assert_equal(_run_state.chapter, 1, "新游戏回到第一章")
	_assert_equal(_run_state.player_hp, _run_state.DEFAULT_MAX_HEALTH, "新游戏恢复满生命")
	_assert_equal(_run_state.battles_won, 0, "新游戏清空胜场")
	_assert_equal(_run_state.owned_item_ids.size(), 0, "新游戏清空战利品")
	_assert_equal(_run_state.deck_card_ids.size(), _run_state.DEFAULT_DECK.size(), "新游戏恢复初始牌库")


# 通用相等断言：保留完整流程节点名称，便于定位跨场景状态残留。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言：继续执行剩余章节，以便一次报告完整路线中的多个问题。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
