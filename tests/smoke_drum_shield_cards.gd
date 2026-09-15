# 爆裂鼓手与钢铁门神卡牌测试：覆盖多段强化、拍位防御、叠盾、护盾消费及延迟命中。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const DOUBLE_KICK := preload("res://data/cards/card_double_kick_combo.tres")
const RAPID_FILL := preload("res://data/cards/card_rapid_fill.tres")
const SHIELD_BASH := preload("res://data/cards/card_shield_bash.tres")
const GATE_BREAKER := preload("res://data/cards/card_gate_breaker.tres")
const WARMUP := preload("res://data/cards/card_mallet_warmup.tres")
const ACCELERATION := preload("res://data/cards/card_tempo_acceleration.tres")
const PRESSURE := preload("res://data/cards/card_pressure_buildup.tres")
const AFTERSHOCK := preload("res://data/cards/card_aftershock_armor.tres")
const SHED_ARMOR := preload("res://data/cards/card_shed_armor.tres")
const CLOSING := preload("res://data/cards/card_closing_stance.tres")
const CYMBAL := preload("res://data/cards/card_cymbal_block.tres")
const POST := preload("res://data/cards/card_reinforced_post.tres")
const LAYERED := preload("res://data/cards/card_layered_defense.tres")
const PERFECT_BLOCK := preload("res://data/cards/card_perfect_block.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_basic_multihit_and_buffs()
	_test_timing_defenses()
	_test_shield_stacking()
	_test_aftershock_deferred_hits()
	_test_shield_conversion_attacks()
	_test_failure_and_turn_boundaries()
	if _failed:
		quit(1)
		return
	print("smoke_drum_shield_cards: PASS")
	quit()


# 鼓槌预热与节奏加速在下一张攻击边界合并，追加段沿用原牌基础伤害。
func _test_basic_multihit_and_buffs() -> void:
	var battle = _new_battle(1001)
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(WARMUP), "鼓槌预热成功")
	_assert_true(battle.play_card(ACCELERATION), "节奏加速成功")
	battle.player.energy = 3
	events.clear()
	_assert_true(battle.play_card(DOUBLE_KICK), "强化后的双踩连击成功")
	_assert_equal(_damage_amounts(events), [6, 6, 6], "双踩两段加追加一段且每段获得预热加成")
	_assert_equal(_damage_events(events)[0].multi_hit_interval_beats, 0.25, "双踩保留四分之一拍间隔")
	battle.player.energy = 3
	events.clear()
	_assert_true(battle.play_card(RAPID_FILL), "疾速过门成功")
	_assert_equal(_damage_amounts(events), [3, 3, 3, 3], "疾速过门造成四段伤害")
	_assert_equal(_damage_events(events)[0].multi_hit_interval_beats, 0.125, "疾速过门使用八分之一拍间隔")
	battle.free()


# 最后一拍强化收拍护盾；第一拍铜钹格挡只强化下一张攻击的首段。
func _test_timing_defenses() -> void:
	var battle = _new_battle(1002)
	_assert_true(battle.play_card(CLOSING, {"beat_index": 3, "grade": 0, "effect_multiplier": 1.0}), "末拍收拍架势成功")
	_assert_equal(battle.player.shield, 9, "收拍架势在第四拍获得9盾")
	battle.player.energy = 3
	_assert_true(battle.play_card(CYMBAL, {"beat_index": 4, "grade": 0, "effect_multiplier": 1.0}), "第一拍铜钹格挡成功")
	battle.player.energy = 3
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(DOUBLE_KICK), "铜钹后的双踩成功")
	_assert_equal(_damage_amounts(events), [7, 4], "铜钹只为第一段增加3点伤害")
	battle.free()


# 连续叠盾读取出牌前护盾；压力蓄积与Perfect加成共同进入下一张防御翻倍。
func _test_shield_stacking() -> void:
	var battle = _new_battle(1003)
	_assert_true(battle.play_card(LAYERED), "无盾时首次层层设防成功")
	_assert_equal(battle.player.shield, 4, "无盾时只获得基础4盾")
	battle.player.energy = 3
	_assert_true(battle.play_card(LAYERED), "已有盾时再次层层设防成功")
	_assert_equal(battle.player.shield, 11, "已有盾时获得7盾")
	battle.player.energy = 3
	_assert_true(battle.play_card(PRESSURE), "压力蓄积成功")
	battle.player.energy = 3
	_assert_true(battle.play_card(PERFECT_BLOCK, {"grade": 0, "effect_multiplier": 1.0}), "Perfect封堵成功")
	_assert_equal(battle.player.shield, 27, "Perfect的8盾经压力蓄积翻倍为16盾")
	battle.free()


# 余震装甲只在足球真实命中后给盾，发射阶段与重复提交都不能提前或重复获盾。
func _test_aftershock_deferred_hits() -> void:
	var battle = _new_battle(1004)
	_assert_true(battle.play_card(AFTERSHOCK), "余震装甲成功")
	battle.player.energy = 3
	var events: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void: events.append(event))
	_assert_true(battle.play_card(DOUBLE_KICK, {}, true), "余震后的双踩进入延迟命中")
	var damage_events := _damage_events(events)
	_assert_equal(battle.player.shield, 0, "发射时不提前获得护盾")
	_assert_true(battle.commit_deferred_damage(damage_events[0]), "第一段真实命中")
	_assert_equal(battle.player.shield, 2, "第一段命中获得2盾")
	_assert_true(battle.commit_deferred_damage(damage_events[1]), "第二段真实命中")
	_assert_equal(battle.player.shield, 4, "第二段命中累计4盾")
	_assert_true(not battle.commit_deferred_damage(damage_events[1]), "重复命中被拒绝")
	_assert_equal(battle.player.shield, 4, "重复提交不重复获得护盾")
	battle.free()


# 盾牌冲撞读取但不消费护盾；卸甲和城门爆破分别消费部分与全部护盾并转成攻击。
func _test_shield_conversion_attacks() -> void:
	var bash_battle = _new_battle(1005)
	_assert_true(bash_battle.play_card(POST), "盾牌冲撞前加固门柱成功")
	bash_battle.player.energy = 3
	var bash_events: Array[Dictionary] = []
	bash_battle.effect_resolved.connect(func(event: Dictionary) -> void: bash_events.append(event))
	_assert_true(bash_battle.play_card(SHIELD_BASH), "盾牌冲撞成功")
	_assert_equal(_damage_amounts(bash_events), [8], "7盾的一半向下取整追加3点伤害")
	_assert_equal(bash_battle.player.shield, 7, "盾牌冲撞不消费护盾")
	bash_battle.free()

	var shed_battle = _new_battle(1006)
	_assert_true(shed_battle.play_card(POST), "卸甲前加固门柱成功")
	_assert_true(shed_battle.play_card(SHED_ARMOR), "卸甲备战成功")
	_assert_equal(shed_battle.player.shield, 1, "卸甲最多消费6盾")
	shed_battle.player.energy = 3
	var shed_events: Array[Dictionary] = []
	shed_battle.effect_resolved.connect(func(event: Dictionary) -> void: shed_events.append(event))
	_assert_true(shed_battle.play_card(DOUBLE_KICK), "卸甲后的双踩成功")
	_assert_equal(_damage_amounts(shed_events), [7, 7], "消费6盾使多段攻击每段加3")
	shed_battle.free()

	var breaker_battle = _new_battle(1007)
	_assert_true(breaker_battle.play_card(POST), "爆破前加固门柱成功")
	breaker_battle.player.energy = 3
	var breaker_events: Array[Dictionary] = []
	breaker_battle.effect_resolved.connect(func(event: Dictionary) -> void: breaker_events.append(event))
	_assert_true(breaker_battle.play_card(GATE_BREAKER), "城门爆破成功")
	_assert_equal(_damage_amounts(breaker_events), [20], "7盾转化为14点追加伤害")
	_assert_equal(breaker_battle.player.shield, 0, "城门爆破消费全部护盾")
	breaker_battle.free()


# 费用不足不消费待用强化；明确标注本回合的余震状态不会泄漏到下一回合。
func _test_failure_and_turn_boundaries() -> void:
	var battle = _new_battle(1008)
	_assert_true(battle.play_card(ACCELERATION), "边界测试先获得节奏加速")
	battle.player.energy = 0
	_assert_true(not battle.play_card(DOUBLE_KICK), "费用不足的攻击失败")
	_assert_equal(battle.pending_next_attack_extra_hits, 1, "失败攻击不消费追加段")
	battle.player.energy = 3
	_assert_true(battle.play_card(AFTERSHOCK), "边界测试获得余震装甲")
	_assert_true(battle.end_player_turn(), "正常结束玩家回合")
	_assert_equal(battle.pending_turn_multihit_shield_amount, 0, "新回合清除余震状态")
	_assert_equal(battle.pending_next_attack_extra_hits, 1, "未注明本回合的节奏加速跨回合保留")
	battle.free()


func _new_battle(seed_value: int):
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(seed_value)
	battle.enemy.max_health = 1000
	battle.enemy.health = 1000
	return battle


func _damage_events(events: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if event.get("type") == "damage" and event.get("target") != null:
			result.append(event)
	return result


func _damage_amounts(events: Array[Dictionary]) -> Array:
	var result := []
	for event in _damage_events(events):
		result.append(event.amount)
	return result


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
