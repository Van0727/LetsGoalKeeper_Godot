# 能量战利品冒烟测试：覆盖首回合溢出、周期触发、首牌回能和跨回合剩余能量结转。
extends SceneTree

const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const ITEM_DEFINITION := preload("res://scripts/items/item_definition.gd")
const ITEM_EFFECT := preload("res://scripts/items/item_effect_definition.gd")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const ITEM_RUNTIME := preload("res://scripts/battle/battle_item_runtime.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_startup_battery()
	_test_three_turn_interval()
	_test_first_card_refund()
	_test_energy_carry()
	if _failed:
		quit(1)
		return
	print("smoke_energy_items: PASS")
	quit()


# 首回合临时能量可以超过基础上限，但普通回能不得降低已有溢出。
func _test_startup_battery() -> void:
	var battery := _make_item(4030, ITEM_EFFECT.Trigger.TURN_STARTED, "gain_temporary_energy", 1.0)
	battery.effects[0].maximum_turn = 1
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(1001, null, {}, [battery])
	_assert_equal(battle.player.max_energy, 3, "启动电池不改变基础能量上限")
	_assert_equal(battle.player.energy, 4, "启动电池首回合获得一点临时额外能量")
	_assert_equal(battle.player.gain_energy(1), 0, "普通回能不清除已有临时溢出")
	_assert_equal(battle.player.energy, 4, "临时溢出保持不变")
	battle.free()


# 周期过滤只在第3、6、9等可整除回合生成命令。
func _test_three_turn_interval() -> void:
	var charger := _make_item(4031, ITEM_EFFECT.Trigger.TURN_STARTED, "gain_temporary_energy", 1.0)
	charger.effects[0].turn_interval = 3
	var runtime = ITEM_RUNTIME.new()
	runtime.setup([charger], 1002)
	_assert_equal(runtime.trigger(ITEM_EFFECT.Trigger.TURN_STARTED, {"turn_number": 2}).size(), 0, "第2回合不触发三相充能")
	_assert_equal(runtime.trigger(ITEM_EFFECT.Trigger.TURN_STARTED, {"turn_number": 3}).size(), 1, "第3回合触发三相充能")
	_assert_equal(runtime.trigger(ITEM_EFFECT.Trigger.TURN_STARTED, {"turn_number": 6}).size(), 1, "第6回合再次触发三相充能")


# 每回合仅第一张成功支付费用的牌在完整结算后恢复一点能量。
func _test_first_card_refund() -> void:
	var bracelet := _make_item(4032, ITEM_EFFECT.Trigger.AFTER_CARD_PLAYED, "gain_energy", 1.0)
	bracelet.effects[0].once_per_turn = true
	var card := CARD_DEFINITION.new()
	card.id = 9001
	card.card_id = "test_energy_card"
	card.display_name = "测试能量牌"
	card.cost = 1
	card.card_type = CARD_DEFINITION.CardType.ABILITY
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(1003, null, {}, [bracelet])
	_assert_true(battle.play_card(card), "首张测试牌可打出")
	_assert_equal(battle.player.energy, 3, "首张牌支付一点后返还一点")
	_assert_true(battle.play_card(card), "第二张测试牌可打出")
	_assert_equal(battle.player.energy, 2, "同回合第二张牌不再返还能量")
	battle.free()


# 回合结束记录全部剩余能量，下一回合在基础回满后一次性叠加。
func _test_energy_carry() -> void:
	var badge := _make_item(4033, ITEM_EFFECT.Trigger.TURN_ENDED, "carry_unspent_energy", 0.0)
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(1004, null, {}, [badge])
	battle.player.energy = 2
	_assert_true(battle.end_player_turn(), "可正常结束玩家回合")
	_assert_equal(battle.player.max_energy, 3, "蓄能徽章不改变基础能量上限")
	_assert_equal(battle.player.energy, 5, "剩余两点在下一回合叠加为临时额外能量")
	battle.free()


# 构造最小战利品资源，专注验证战斗框架而不依赖生成资源加载顺序。
func _make_item(id: int, trigger: int, command: String, amount: float) -> Resource:
	var item := ITEM_DEFINITION.new()
	item.id = id
	item.item_id = "test_item_%d" % id
	var effect := ITEM_EFFECT.new()
	effect.trigger = trigger
	effect.operation = ITEM_EFFECT.Operation.EMIT_COMMAND
	effect.target_key = command
	effect.amount = amount
	item.effects.append(effect)
	return item


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
