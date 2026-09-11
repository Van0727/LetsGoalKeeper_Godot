# 回合纪律牌专项测试：独立验证计数、黄红牌阈值、输入封锁、强制结束与回合重置。
extends SceneTree

const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(20260911)
	var free_card = CARD_DEFINITION.new()
	free_card.display_name = "纪律测试牌"
	free_card.cost = 0
	free_card.card_type = CARD_DEFINITION.CardType.ABILITY
	var costly_card = CARD_DEFINITION.new()
	costly_card.display_name = "费用失败牌"
	costly_card.cost = 4
	_assert_true(not battle.play_card(costly_card), "失败出牌不被接受")
	_assert_equal(battle.player_cards_played_this_turn, 0, "失败出牌不计数")
	var issued: Array[String] = []
	battle.discipline_card_issued.connect(func(color: String, _count: int) -> void: issued.append(color))
	for _index in range(10):
		_assert_true(battle.play_card(free_card), "黄牌前成功出牌")
	_assert_equal(issued, ["yellow"], "第10张触发一次黄牌")
	for _index in range(10):
		_assert_true(battle.play_card(free_card), "红牌前成功出牌")
	_assert_equal(issued, ["yellow", "red"], "第20张触发一次红牌")
	_assert_true(battle.red_card_pending, "红牌锁定等待当前牌表现完成")
	_assert_true(not battle.play_card(free_card), "红牌后拒绝第21张牌")
	var old_turn: int = battle.turn_number
	_assert_true(battle.force_end_turn_for_red_card(), "红牌可强制结束回合")
	_assert_equal(battle.turn_number, old_turn + 1, "敌方行动后进入下一回合")
	_assert_equal(battle.player_cards_played_this_turn, 0, "新回合计数清零")
	battle.free()
	if _failed:
		quit(1)
		return
	print("smoke_discipline_cards: PASS")
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
