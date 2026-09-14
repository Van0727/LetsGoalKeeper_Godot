# 奖励品框架冒烟测试：验证过滤、逐段数值修改、回合限次、命令出口与战斗上下文传递。
extends SceneTree

const ITEM_DEFINITION := preload("res://scripts/items/item_definition.gd")
const ITEM_EFFECT := preload("res://scripts/items/item_effect_definition.gd")
const ITEM_RUNTIME := preload("res://scripts/battle/battle_item_runtime.gd")
const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const BANANA_SHOT := preload("res://data/cards/card_double_banana_shot.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var item := ITEM_DEFINITION.new()
	item.item_id = "test_left_banana"
	var bonus := ITEM_EFFECT.new()
	bonus.trigger = ITEM_EFFECT.Trigger.BEFORE_DAMAGE
	bonus.operation = ITEM_EFFECT.Operation.ADD
	bonus.target_key = "amount"
	bonus.amount = 2.0
	bonus.shot_filter = ITEM_EFFECT.ShotFilter.BANANA
	item.effects = [bonus]

	var runtime := ITEM_RUNTIME.new()
	runtime.setup([item], 123)
	var first_hit := {"amount": 3.0, "shot_type": 2}
	runtime.trigger(ITEM_EFFECT.Trigger.BEFORE_DAMAGE, first_hit)
	_assert_equal(first_hit.amount, 5.0, "香蕉球单段获得配置加成")
	var wrong_shot := {"amount": 3.0, "shot_type": 1}
	runtime.trigger(ITEM_EFFECT.Trigger.BEFORE_DAMAGE, wrong_shot)
	_assert_equal(wrong_shot.amount, 3.0, "过滤条件阻止直球获得香蕉加成")
	var once_bonus := ITEM_EFFECT.new()
	once_bonus.trigger = ITEM_EFFECT.Trigger.TURN_STARTED
	once_bonus.operation = ITEM_EFFECT.Operation.EMIT_COMMAND
	once_bonus.target_key = "gain_shield"
	once_bonus.amount = 3.0
	once_bonus.once_per_turn = true
	item.effects.append(once_bonus)
	runtime.setup([item], 123)
	_assert_equal(runtime.trigger(ITEM_EFFECT.Trigger.TURN_STARTED, {}).size(), 1, "每回合限次效果首次生成命令")
	_assert_equal(runtime.trigger(ITEM_EFFECT.Trigger.TURN_STARTED, {}).size(), 0, "每回合限次效果不能重复触发")
	runtime.start_turn()
	_assert_equal(runtime.trigger(ITEM_EFFECT.Trigger.TURN_STARTED, {}).size(), 1, "新回合重置限次标记")

	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(456, null, {}, [item])
	battle.set_banana_shot_direction(-1)
	battle.play_card(BANANA_SHOT, {"grade": 0, "effect_multiplier": 1.0, "beat_index": 0, "bar_index": 0, "subdivision": 8})
	_assert_equal(battle.enemy.health, 20, "两段香蕉球各自增加两点伤害")
	_assert_equal(battle.current_action_context.subdivision, 8, "出牌上下文保留BGM节奏细分")
	_assert_equal(battle.current_action_context.shot_direction, -1, "方向技能接口写入核心出牌上下文")
	battle.free()

	if _failed:
		quit(1)
		return
	print("smoke_item_effect_framework: PASS")
	quit()


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])
