extends SceneTree

const DECK_STATE := preload("res://scripts/cards/deck_state.gd")
const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const BANANA_SHOT := preload("res://data/cards/card_banana_shot.tres")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const SPORTS_DRINK := preload("res://data/cards/card_sports_drink.tres")
const TOWEL := preload("res://data/cards/card_towel.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_card_definitions()
	_test_draw_play_discard_and_recycle()
	_test_deterministic_shuffle()

	if _failed:
		quit(1)
		return
	print("smoke_deck_state: PASS")
	quit()


func _test_card_definitions() -> void:
	_assert_equal(STRAIGHT_SHOT.card_id, "card_straight_shot", "直球稳定ID")
	_assert_equal(STRAIGHT_SHOT.cost, 1, "直球费用")
	_assert_equal(STRAIGHT_SHOT.effects[0].amount, 6, "直球伤害")
	_assert_equal(GLOVES.effects[0].amount, 6, "手套护盾")
	_assert_equal(SPORTS_DRINK.effects[0].amount, 6, "佳得乐治疗")
	_assert_equal(TOWEL.effects[0].amount, 2, "毛巾恢复能量")


func _test_draw_play_discard_and_recycle() -> void:
	var deck = DECK_STATE.new()
	var definitions: Array[Resource] = [STRAIGHT_SHOT, BANANA_SHOT, GLOVES, SPORTS_DRINK]
	deck.setup(definitions, 99)
	_assert_equal(deck.draw_cards(3).size(), 3, "回合开始抽牌数")
	_assert_equal(deck.hand.size(), 3, "抽牌后手牌数")
	var original_cost: int = deck.hand[1].cost
	var expected_replacement: Resource = deck.draw_pile.back()
	var played: Resource = deck.play_card_at(1)
	_assert_true(played != null, "合法手牌可打出")
	_assert_equal(deck.hand.size(), 3, "出牌后补回原手牌数")
	_assert_true(deck.hand[1] == expected_replacement, "补牌放回打出位置")
	_assert_equal(deck.discard_pile.size(), 1, "打出的牌进入弃牌堆")
	_assert_equal(played.cost, original_cost, "出牌不修改卡牌定义")
	_assert_equal(deck.discard_hand(), 3, "回合结束弃掉全部手牌")
	_assert_equal(deck.hand.size(), 0, "回合结束后手牌清空")
	_assert_equal(deck.draw_cards(3).size(), 3, "抽牌堆空时回洗弃牌堆")


func _test_deterministic_shuffle() -> void:
	var definitions: Array[Resource] = [STRAIGHT_SHOT, BANANA_SHOT, GLOVES, SPORTS_DRINK]
	var first = DECK_STATE.new()
	var second = DECK_STATE.new()
	first.setup(definitions, 12345)
	second.setup(definitions, 12345)
	var first_ids := _card_ids(first.draw_cards(4))
	var second_ids := _card_ids(second.draw_cards(4))
	_assert_equal(first_ids, second_ids, "固定 seed 的洗牌顺序")


func _card_ids(cards: Array[Resource]) -> PackedStringArray:
	var ids: PackedStringArray = []
	for card in cards:
		ids.append(card.card_id)
	return ids


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
