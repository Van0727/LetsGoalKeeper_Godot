# 香蕉球方向牌专项测试：验证费用、左右覆盖、跨回合保持、战利品判向和新战斗重置。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const LEFT_CARD := preload("res://data/cards/card_banana_left.tres")
const RIGHT_CARD := preload("res://data/cards/card_banana_right.tres")
const BANANA_SHOT := preload("res://data/cards/card_banana_shot.tres")
const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const GOLDEN_LEFT := preload("res://data/items/item_golden_left_foot.tres")
const GOLDEN_RIGHT := preload("res://data/items/item_golden_right_foot.tres")
const BANANA_ITEM := preload("res://data/items/item_banana.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(411, null, {}, [GOLDEN_LEFT, GOLDEN_RIGHT, BANANA_ITEM])
	battle.enemy.max_health = 1000
	battle.enemy.health = 1000
	_assert_equal(LEFT_CARD.cost, 1, "偏左牌费用为1")
	_assert_equal(RIGHT_CARD.cost, 1, "偏右牌费用为1")
	battle.player.energy = 0
	_assert_true(not battle.play_card(LEFT_CARD), "费用不足时方向牌失败")
	_assert_equal(battle.banana_shot_direction, 0, "失败出牌不改方向")
	battle.player.energy = 3
	_assert_true(battle.play_card(LEFT_CARD), "偏左牌成功出牌")
	_assert_equal(battle.player.energy, 2, "偏左牌消耗1能量")
	_assert_equal(battle.banana_shot_direction, -1, "偏左牌设置既有方向状态")
	_assert_true(battle.play_card(BANANA_SHOT), "原生香蕉球成功出牌")
	_assert_equal(battle.current_action_context.shot_direction, -1, "原生香蕉球向左")
	_assert_equal(battle.enemy.health, 992, "黄金左脚仅对左侧球加伤")
	battle.end_player_turn()
	_assert_equal(battle.banana_shot_direction, -1, "方向跨玩家回合保留")
	_assert_true(battle.play_card(STRAIGHT_SHOT), "直球被香蕉战利品转换")
	_assert_equal(battle.current_action_context.actual_shot_type, 2, "战利品转换为香蕉球")
	_assert_equal(battle.current_action_context.shot_direction, -1, "转换球服从固定向左")
	battle.player.energy = 3
	_assert_true(battle.play_card(RIGHT_CARD), "偏右牌覆盖偏左牌")
	_assert_equal(battle.banana_shot_direction, 1, "后出牌将方向改为右")
	_assert_true(battle.play_card(BANANA_SHOT), "右侧香蕉球成功出牌")
	_assert_equal(battle.current_action_context.shot_direction, 1, "原生香蕉球向右")
	_assert_true(battle.debug_force_victory(), "怪物死亡结束当前战斗")
	_assert_equal(battle.banana_shot_direction, 0, "怪物死亡立即清除方向牌效果")
	battle.setup(412, null, {}, [GOLDEN_LEFT, GOLDEN_RIGHT, BANANA_ITEM])
	_assert_equal(battle.banana_shot_direction, 0, "下一场怪物战斗重置方向")
	battle.free()
	if _failed:
		quit(1)
		return
	print("smoke_banana_direction_cards: PASS")
	quit()


func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])
