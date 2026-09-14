# 鼓手暴力流测试：覆盖首拍/乐谱倍率、停抽与单手换牌、低血量阈值及骰子两个分支。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const DECK := preload("res://scripts/cards/deck_state.gd")
const CARD := preload("res://scripts/cards/card_definition.gd")
const EFFECT := preload("res://scripts/cards/effect_definition.gd")
const REWARD := preload("res://scripts/rewards/reward_service.gd")
const BIG := preload("res://data/items/item_big_drum_mallet.tres")
const WOLF := preload("res://data/items/item_spiked_drum_mallet.tres")
const BLIND := preload("res://data/items/item_blindfold.tres")
const BLANK := preload("res://data/items/item_blank_score.tres")
const REST := preload("res://data/items/item_rest_score.tres")
const TATTOO := preload("res://data/items/item_tattoo_sticker.tres")
const RACING := preload("res://data/items/item_racing_drumsticks.tres")
const DICE := preload("res://data/items/item_bar_dice.tres")
const STRAIGHT := preload("res://data/cards/card_straight_shot.tres")
const BANANA := preload("res://data/cards/card_double_banana_shot.tres")
const SKILL_CARD := preload("res://data/cards/card_pitch_up.tres")
const SUPER_ATTACK := preload("res://data/skills/skill_super_attack.tres")
const SUPER_DEFENSE := preload("res://data/skills/skill_super_defense.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_and_multipliers()
	_test_wolf_and_blindfold()
	_test_scores()
	_test_tattoo()
	_test_tattoo_order()
	_test_dice()
	if _failed:
		quit(1)
		return
	print("smoke_drummer_violent_items: PASS")
	quit()


# 首拍只触发一次；狼牙鼓槌还翻倍概率与自伤，且不修改共享卡牌定义。
func _test_catalog_and_multipliers() -> void:
	var ids: Array[String] = []
	for item in REWARD.new().get_all_items():
		ids.append(item.item_id)
	for item in [BIG, WOLF, BLIND, BLANK, REST, TATTOO, DICE]:
		_assert_true(item.item_id in ids, "%s登记到GM列表" % item.display_name)
	var battle = _battle(901, [BIG], 200)
	var first_beat := {"grade": 0, "effect_multiplier": 1.0, "beat_index": 0}
	_assert_true(battle.play_card(STRAIGHT, first_beat), "首拍攻击")
	_assert_equal(battle.enemy.health, 188, "大鼓槌首拍6伤害翻倍")
	battle.player.energy = 3
	_assert_true(battle.play_card(STRAIGHT, first_beat), "同回合第二张首拍牌")
	_assert_equal(battle.enemy.health, 182, "同回合大鼓槌不重复触发")
	battle.free()
	var self_card = CARD.new()
	self_card.display_name = "自伤概率测试"
	self_card.cost = 0
	var self_effect = EFFECT.new()
	self_effect.target = EFFECT.Target.SELF
	self_effect.amount = 3
	self_effect.chance_percent = 50
	var self_effects: Array[Resource] = [self_effect]
	self_card.effects = self_effects
	var wolf_battle = _battle(902, [WOLF], 100)
	_assert_true(wolf_battle.play_card(self_card), "狼牙鼓槌自伤牌")
	_assert_equal(wolf_battle.player.health, 94, "概率翻倍至100%且3点自伤翻倍为6")
	_assert_equal(self_effect.chance_percent, 50, "卡牌定义概率保持原值")
	wolf_battle.free()


# 狼牙成功出牌后不补牌；蒙眼布只有一张手牌、三次换牌，失败不扣次数。
func _test_wolf_and_blindfold() -> void:
	var deck = DECK.new()
	var cards: Array[Resource] = [STRAIGHT, STRAIGHT, STRAIGHT, STRAIGHT]
	deck.setup(cards, 903)
	deck.draw_cards(3)
	var battle = _battle(903, [WOLF], 100)
	_assert_true(battle.play_card_from_hand(deck, 0), "狼牙出牌")
	_assert_equal(deck.hand.size(), 2, "狼牙不自动补牌")
	_assert_equal(battle.enemy.health, 88, "狼牙将6点伤害翻倍")
	battle.free()
	deck.setup(cards, 904)
	deck.set_hand_limit(1)
	deck.draw_cards(3)
	_assert_equal(deck.hand.size(), 1, "蒙眼布手牌上限为1")
	var blind_battle = _battle(904, [BLIND], 100)
	_assert_equal(blind_battle.blindfold_charges, 3, "蒙眼布每回合初始3次换牌")
	for index in range(3):
		_assert_true(blind_battle.use_blindfold_swap(deck), "第%d次换牌" % (index + 1))
	_assert_equal(blind_battle.blindfold_charges, 0, "三次换牌后耗尽")
	_assert_true(not blind_battle.use_blindfold_swap(deck), "第四次换牌被拒绝")
	blind_battle.free()
	var single = DECK.new()
	var one_card: Array[Resource] = [STRAIGHT]
	single.setup(one_card, 905)
	single.set_hand_limit(1)
	single.draw_cards(1)
	var no_alternative = _battle(905, [BLIND], 100)
	_assert_true(not no_alternative.use_blindfold_swap(single), "无候选牌时拒绝换牌")
	_assert_equal(no_alternative.blindfold_charges, 3, "换牌失败不扣充能")
	no_alternative.free()


# 乐谱在回合结束时排队，只被下一回合成功打出的首张牌消费；两种计数互斥。
func _test_scores() -> void:
	var blank = _battle(906, [BLANK], 200)
	blank.enemy_intent_damage = 0
	_assert_true(blank.end_player_turn(), "空回合结束")
	_assert_equal(blank.pending_first_card_multiplier, 4.0, "无字乐谱排队四倍")
	blank.player.energy = 0
	_assert_true(not blank.play_card(STRAIGHT), "费用不足不消费乐谱")
	_assert_equal(blank.pending_first_card_multiplier, 4.0, "失败出牌保留四倍")
	blank.player.energy = 3
	_assert_true(blank.play_card(STRAIGHT), "下回合首张攻击")
	_assert_equal(blank.enemy.health, 176, "6点伤害四倍为24")
	_assert_equal(blank.pending_first_card_multiplier, 1.0, "首张牌后倍率清除")
	blank.free()
	var rest = _battle(907, [REST], 200)
	_assert_true(rest.play_card(SKILL_CARD), "本回合只出一张技能")
	rest.enemy_intent_damage = 0
	_assert_true(rest.end_player_turn(), "单牌回合结束")
	_assert_equal(rest.pending_first_card_multiplier, 2.0, "空拍乐谱排队两倍")
	_assert_true(rest.play_card(STRAIGHT), "下一回合首张攻击")
	_assert_equal(rest.enemy.health, 188, "空拍乐谱将6点伤害翻倍")
	rest.free()


# 低于30%才加伤，恰好30%不触发；主动技同样采用向上取整规则。
func _test_tattoo() -> void:
	var boundary = _battle(908, [TATTOO], 200)
	boundary.player.health = 30
	_assert_true(boundary.play_card(STRAIGHT), "30%生命攻击")
	_assert_equal(boundary.enemy.health, 194, "恰好30%不加伤")
	boundary.player.energy = 3
	boundary.player.health = 29
	_assert_true(boundary.play_card(STRAIGHT), "29%生命攻击")
	_assert_equal(boundary.enemy.health, 185, "低于30%时6点变9点")
	boundary.free()
	var skill = _battle(909, [TATTOO], 200)
	skill.player.health = 29
	for index in range(3):
		skill.combo_state.register_card(0)
	_assert_true(skill.play_active_skill(SUPER_ATTACK), "低血量攻击主动技")
	_assert_equal(skill.enemy.health, 155, "30点主动技伤害变45点")
	skill.free()


# 固定加伤先于纹身贴倍率，取得顺序不影响低血量最终伤害。
func _test_tattoo_order() -> void:
	var first = _battle(910, [TATTOO, RACING], 200)
	var second = _battle(911, [RACING, TATTOO], 200)
	for battle in [first, second]:
		battle.player.health = 29
		_assert_true(battle.play_card(STRAIGHT, {"grade": 0, "effect_multiplier": 1.0, "subdivision": 8}), "低血量八分细分射门")
		_assert_equal(battle.enemy.health, 189, "固定加伤后7乘1.5向上取整为11")
		battle.free()


# 固定种子扫描确保骰子两面都有覆盖；增伤只消费下一次对敌伤害的首段。
func _test_dice() -> void:
	var saw_double := false
	var saw_end_turn := false
	for seed_value in range(1, 80):
		var battle = _battle(seed_value, [DICE], 200)
		for index in range(3):
			battle.combo_state.register_card(1)
		_assert_true(battle.play_active_skill(SUPER_DEFENSE, {}, true), "骰子主动技释放")
		if battle.pending_next_damage_multiplier > 1.0 and not saw_double:
			saw_double = true
			_assert_true(battle.play_card(BANANA), "骰子后双段攻击")
			_assert_equal(battle.enemy.health, 191, "仅首段3点翻倍，第二段保持3点")
			_assert_equal(battle.pending_next_damage_multiplier, 1.0, "翻倍仅消费一次")
		if battle.bar_dice_end_turn_pending and not saw_end_turn:
			saw_end_turn = true
			_assert_true(not battle.play_card(STRAIGHT), "骰子待结束时禁止继续出牌")
			_assert_true(battle.resolve_bar_dice_end_turn(), "视觉完成后提交骰子结束回合")
			_assert_equal(battle.turn_number, 2, "骰子直接推进下一回合")
		battle.free()
		if saw_double and saw_end_turn:
			break
	_assert_true(saw_double and saw_end_turn, "固定种子覆盖骰子两种分支")


func _battle(seed_value: int, items: Array[Resource], enemy_health: int):
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(seed_value, null, {}, items)
	battle.enemy.max_health = enemy_health
	battle.enemy.health = enemy_health
	return battle


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
