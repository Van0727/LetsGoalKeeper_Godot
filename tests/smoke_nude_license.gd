# 全裸许可证测试：验证三牌堆等量替换、GM 反复勾选恢复来源，以及赤膊费用和能量效果。
extends SceneTree

const DECK := preload("res://scripts/cards/deck_state.gd")
const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const ATTACK := preload("res://data/cards/card_straight_shot.tres")
const BARE := preload("res://data/cards/card_bare_chested.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var deck = DECK.new()
	var cards: Array[Resource] = [GLOVES, ATTACK, GLOVES]
	deck.setup(cards, 100)
	deck.draw_cards(1)
	deck.discard_pile.append(deck.draw_pile.pop_back())
	deck.sync_defense_replacement(true, BARE)
	_assert_equal(_count_card_id(deck, "card_bare_chested"), 2, "三牌堆合计两张防御牌全部替换")
	_assert_equal(_count_card_id(deck, "card_gloves"), 0, "持有时原防御牌不在可玩牌堆")
	deck.sync_defense_replacement(true, BARE)
	_assert_equal(_count_card_id(deck, "card_bare_chested"), 2, "重复同步不重复替换")
	deck.sync_defense_replacement(false, BARE)
	_assert_equal(_count_card_id(deck, "card_gloves"), 2, "取消后原位恢复两张防御牌")
	deck.sync_defense_replacement(true, BARE)
	_assert_equal(_count_card_id(deck, "card_bare_chested"), 2, "再次勾选仍可替换")
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(101)
	battle.player.energy = 1
	_assert_true(battle.play_card(BARE), "赤膊1能量可打出")
	_assert_equal(battle.player.energy, 2, "赤膊支付1后获得2能量")
	_assert_equal(int(BARE.card_type), 1, "赤膊仍是防御牌")
	battle.free()
	if _failed:
		quit(1)
		return
	print("smoke_nude_license: PASS")
	quit()


func _count_card_id(deck, card_id: String) -> int:
	var count := 0
	for pile in [deck.draw_pile, deck.discard_pile, deck.hand]:
		for card in pile:
			if card.card_id == card_id:
				count += 1
	return count


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


func _assert_true(condition: bool, label: String) -> void:
	if condition:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
