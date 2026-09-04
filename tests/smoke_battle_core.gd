extends SceneTree

const COMBATANT_STATE := preload("res://scripts/battle/combatant_state.gd")
const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const DECK_STATE := preload("res://scripts/cards/deck_state.gd")
const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const BANANA_SHOT := preload("res://data/cards/card_banana_shot.tres")
const LOB_SHOT := preload("res://data/cards/card_lob_shot.tres")
const BARRAGE_SHOT := preload("res://data/cards/card_barrage_shot.tres")
const ATTACK_AND_DEFEND := preload("res://data/cards/card_attack_and_defend.tres")
const EXPLOSION_BALL := preload("res://data/cards/card_explosion_ball.tres")
const ENERGY_SHOT := preload("res://data/cards/card_energy_shot.tres")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const SPORTS_DRINK := preload("res://data/cards/card_sports_drink.tres")
const TOWEL := preload("res://data/cards/card_towel.tres")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const EFFECT_DEFINITION := preload("res://scripts/cards/effect_definition.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_damage_shield_and_healing()
	_test_turn_flow_and_victory()
	_test_player_defeat()
	_test_card_costs_and_effects()
	_test_shot_types_multi_hit_and_multi_effect()
	_test_probability_branch_and_interrupt()
	_test_remaining_energy_damage()
	_test_effect_order()
	_test_deterministic_seed()

	if _failed:
		quit(1)
		return
	print("smoke_battle_core: PASS")
	quit()


func _test_damage_shield_and_healing() -> void:
	var combatant = COMBATANT_STATE.new("测试角色", 10)
	combatant.gain_shield(5)
	var first_hit: Dictionary = combatant.take_damage(3)
	_assert_equal(first_hit.absorbed, 3, "伤害小于护盾时吸收量")
	_assert_equal(combatant.shield, 2, "伤害小于护盾时剩余护盾")
	_assert_equal(combatant.health, 10, "伤害小于护盾时生命")

	combatant.take_damage(2)
	_assert_equal(combatant.shield, 0, "伤害等于护盾时剩余护盾")
	_assert_equal(combatant.health, 10, "伤害等于护盾时生命")

	var third_hit: Dictionary = combatant.take_damage(4)
	_assert_equal(third_hit.health_damage, 4, "伤害大于护盾时生命损失")
	_assert_equal(combatant.heal(20), 4, "治疗返回实际恢复量")
	_assert_equal(combatant.health, 10, "治疗不超过最大生命")


func _test_turn_flow_and_victory() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(42)
	_assert_equal(battle.phase, battle.Phase.PLAYER_TURN, "战斗开始阶段")
	battle.player_guard(6)
	battle.end_player_turn()
	_assert_equal(battle.turn_number, 2, "敌人行动后进入下一回合")
	_assert_equal(battle.player.shield, 0, "玩家新回合清空护盾")
	battle.player_attack(999)
	_assert_equal(battle.phase, battle.Phase.FINISHED, "敌人死亡后结束战斗")
	_assert_equal(battle.enemy.health, 0, "致命伤害不会产生负生命")
	battle.free()


func _test_deterministic_seed() -> void:
	var first = BATTLE_CONTROLLER.new()
	var second = BATTLE_CONTROLLER.new()
	root.add_child(first)
	root.add_child(second)
	first.setup(12345)
	second.setup(12345)

	for turn in range(5):
		_assert_equal(first.enemy_intent_damage, second.enemy_intent_damage, "固定 seed 的第 %d 次意图" % turn)
		first.end_player_turn()
		second.end_player_turn()

	first.free()
	second.free()

	var first_explosion = BATTLE_CONTROLLER.new()
	var second_explosion = BATTLE_CONTROLLER.new()
	root.add_child(first_explosion)
	root.add_child(second_explosion)
	first_explosion.setup(24680)
	second_explosion.setup(24680)
	first_explosion.play_card(EXPLOSION_BALL)
	second_explosion.play_card(EXPLOSION_BALL)
	_assert_equal(first_explosion.player.health, second_explosion.player.health, "固定 seed 的爆炸球自伤结果")
	_assert_equal(first_explosion.enemy.health, second_explosion.enemy.health, "固定 seed 的爆炸球攻击结果")
	first_explosion.free()
	second_explosion.free()


func _test_effect_order() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(5)
	battle.player.health = 99

	var heal_effect = EFFECT_DEFINITION.new()
	heal_effect.effect_type = EFFECT_DEFINITION.EffectType.HEAL
	heal_effect.target = EFFECT_DEFINITION.Target.SELF
	heal_effect.amount = 6
	var self_damage_effect = EFFECT_DEFINITION.new()
	self_damage_effect.effect_type = EFFECT_DEFINITION.EffectType.DAMAGE
	self_damage_effect.target = EFFECT_DEFINITION.Target.SELF
	self_damage_effect.amount = 3
	var ordered_card = CARD_DEFINITION.new()
	ordered_card.display_name = "顺序测试"
	ordered_card.cost = 0
	var ordered_effects: Array[Resource] = [heal_effect, self_damage_effect]
	ordered_card.effects = ordered_effects

	battle.play_card(ordered_card)
	_assert_equal(battle.player.health, 97, "效果按数组顺序先治疗再自伤")
	battle.free()


func _test_shot_types_multi_hit_and_multi_effect() -> void:
	var resolver = preload("res://scripts/battle/effect_resolver.gd").new()
	var source = COMBATANT_STATE.new("测试射手", 20, 10)
	var target = COMBATANT_STATE.new("测试门将", 40)

	var banana_events: Array[Dictionary] = resolver.resolve_card(BANANA_SHOT, source, target)
	_assert_equal(banana_events.size(), 1, "香蕉球产生一次伤害事件")
	_assert_equal(banana_events[0].shot_type, BANANA_SHOT.ShotType.BANANA, "香蕉球事件保留弹道类型")

	var lob_events: Array[Dictionary] = resolver.resolve_card(LOB_SHOT, source, target)
	_assert_equal(lob_events[0].shot_type, LOB_SHOT.ShotType.LOB, "挑射事件保留弹道类型")

	target.shield = 4
	var barrage_events: Array[Dictionary] = resolver.resolve_card(BARRAGE_SHOT, source, target)
	_assert_equal(barrage_events.size(), 3, "连续射门逐段产生伤害事件")
	_assert_equal(barrage_events[0].absorbed, 3, "第一段伤害消耗护盾")
	_assert_equal(barrage_events[1].absorbed, 1, "第二段伤害消耗剩余护盾")
	_assert_equal(barrage_events[2].health_damage, 3, "第三段伤害作用于生命")
	var lethal_target = COMBATANT_STATE.new("低生命目标", 4)
	var lethal_events: Array[Dictionary] = resolver.resolve_card(BARRAGE_SHOT, source, lethal_target)
	_assert_equal(lethal_events.size(), 2, "多段攻击在目标死亡后停止后续段数")

	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(101)
	_assert_true(battle.play_card(ATTACK_AND_DEFEND), "可打出多效果卡牌")
	_assert_equal(battle.enemy.health, 25, "多效果卡牌先造成伤害")
	_assert_equal(battle.player.shield, 5, "多效果卡牌再获得护盾")
	battle.free()


func _test_probability_branch_and_interrupt() -> void:
	var resolver = preload("res://scripts/battle/effect_resolver.gd").new()
	var success_rng := _find_rng_for_chance_result(true)
	var success_source = COMBATANT_STATE.new("爆炸触发者", 20, 3)
	var success_target = COMBATANT_STATE.new("未受攻击目标", 20)
	var success_events: Array[Dictionary] = resolver.resolve_card(
		EXPLOSION_BALL,
		success_source,
		success_target,
		success_rng
	)
	_assert_true(success_events[0].succeeded, "爆炸球成功分支触发")
	_assert_equal(success_source.health, 17, "爆炸球触发时对自身造成3点伤害")
	_assert_equal(success_target.health, 20, "爆炸球触发后中断敌方伤害")
	_assert_equal(success_events[-1].type, "effect_interrupted", "爆炸球记录中断事件")

	var failure_rng := _find_rng_for_chance_result(false)
	var failure_source = COMBATANT_STATE.new("安全射手", 20, 3)
	var failure_target = COMBATANT_STATE.new("受攻击目标", 20)
	var failure_events: Array[Dictionary] = resolver.resolve_card(
		EXPLOSION_BALL,
		failure_source,
		failure_target,
		failure_rng
	)
	_assert_true(not failure_events[0].succeeded, "爆炸球失败分支未触发")
	_assert_equal(failure_source.health, 20, "爆炸球未触发时不造成自伤")
	_assert_equal(failure_target.health, 8, "爆炸球未触发时造成12点伤害")
	_assert_equal(failure_events.size(), 2, "爆炸球未触发时继续后续效果")


func _find_rng_for_chance_result(expected_success: bool) -> RandomNumberGenerator:
	for candidate_seed in range(1, 1000):
		var probe := RandomNumberGenerator.new()
		probe.seed = candidate_seed
		if (probe.randi_range(1, 100) <= 50) == expected_success:
			var result := RandomNumberGenerator.new()
			result.seed = candidate_seed
			return result
	return RandomNumberGenerator.new()


func _test_remaining_energy_damage() -> void:
	var full_energy_battle = BATTLE_CONTROLLER.new()
	root.add_child(full_energy_battle)
	full_energy_battle.setup(303)
	_assert_true(full_energy_battle.play_card(ENERGY_SHOT), "满能量时可打出能量射门")
	_assert_equal(full_energy_battle.player.energy, 2, "能量射门先支付1点费用")
	_assert_equal(full_energy_battle.enemy.health, 20, "剩余2点能量时造成10点伤害")
	full_energy_battle.free()

	var last_energy_battle = BATTLE_CONTROLLER.new()
	root.add_child(last_energy_battle)
	last_energy_battle.setup(304)
	last_energy_battle.player.energy = 1
	_assert_true(last_energy_battle.play_card(ENERGY_SHOT), "最后1点能量可打出能量射门")
	_assert_equal(last_energy_battle.player.energy, 0, "最后1点能量被支付")
	_assert_equal(last_energy_battle.enemy.health, 24, "无剩余能量时只造成6点基础伤害")
	last_energy_battle.free()


func _test_player_defeat() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(7)
	battle.player.take_damage(99)
	battle.end_player_turn()
	_assert_equal(battle.phase, battle.Phase.FINISHED, "玩家死亡后结束战斗")
	_assert_equal(battle.player.health, 0, "敌人致命攻击后玩家生命")
	battle.free()


func _test_card_costs_and_effects() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(88)
	battle.player.take_damage(10)

	_assert_true(battle.play_card(STRAIGHT_SHOT), "能量充足时可打攻击牌")
	_assert_equal(battle.player.energy, 2, "攻击牌支付能量")
	_assert_equal(battle.enemy.health, 24, "攻击效果造成伤害")
	_assert_true(battle.play_card(GLOVES), "能量充足时可打防御牌")
	_assert_equal(battle.player.shield, 6, "防御效果增加护盾")
	_assert_true(battle.play_card(SPORTS_DRINK), "能量充足时可打治疗牌")
	_assert_equal(battle.player.health, 96, "治疗效果不超过最大生命")
	_assert_true(not battle.play_card(STRAIGHT_SHOT), "能量不足时拒绝出牌")
	_assert_equal(battle.enemy.health, 24, "能量不足不结算效果")

	battle.end_player_turn()
	_assert_equal(battle.player.energy, 3, "新玩家回合恢复满能量")
	_assert_true(battle.play_card(TOWEL), "可打出回能牌")
	_assert_equal(battle.player.energy, 3, "回能牌费用和效果依次结算且不超过上限")

	var deck = DECK_STATE.new()
	var cards: Array[Resource] = [STRAIGHT_SHOT, GLOVES, SPORTS_DRINK, TOWEL]
	deck.setup(cards, 17)
	deck.draw_cards(3)
	battle.player.energy = 0
	var hand_before: Array[Resource] = deck.hand.duplicate()
	_assert_true(not battle.play_card_from_hand(deck, 0), "费用不足时手牌出牌失败")
	_assert_equal(deck.hand, hand_before, "费用不足不移动手牌")
	battle.player.energy = 3
	_assert_true(battle.play_card_from_hand(deck, 0), "费用充足时从手牌出牌")
	_assert_equal(deck.discard_pile.size(), 1, "成功出牌后进入弃牌堆")
	battle.free()


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
