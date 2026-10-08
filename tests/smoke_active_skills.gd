# 阶段 5 主动技冒烟测试：验证连击切换、三类技能、消耗清空和熊的技能减伤标签。
extends SceneTree

const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const COMBO_STATE := preload("res://scripts/battle/combo_state.gd")
const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const TOWEL := preload("res://data/cards/card_towel.tres")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")
const BEAR := preload("res://data/enemies/enemy_bear.tres")
const SUPER_ATTACK := preload("res://data/skills/skill_super_attack.tres")
const SUPER_DEFENSE := preload("res://data/skills/skill_super_defense.tres")
const SUPER_ABILITY := preload("res://data/skills/skill_super_ability.tres")

var _failed := false


# 延迟执行以等待场景树初始化。
func _initialize() -> void:
	call_deferred("_run")


# 执行连击与三个技能类型的完整验收。
func _run() -> void:
	_test_combo_switch_and_cap()
	_test_super_attack_and_bear_reduction()
	_test_super_defense()
	_test_super_ability()
	_test_failed_qte_consumes_without_effect()
	_test_new_battle_clears_combo()
	_test_deferred_skill_hits()

	if _failed:
		quit(1)
		return
	print("smoke_active_skills: PASS")
	quit()


# 同类型可超过释放门槛继续积累，换类型后改为新类型的1点。
func _test_combo_switch_and_cap() -> void:
	var combo = COMBO_STATE.new()
	combo.register_card(STRAIGHT_SHOT.card_type)
	combo.register_card(STRAIGHT_SHOT.card_type)
	combo.register_card(STRAIGHT_SHOT.card_type)
	combo.register_card(STRAIGHT_SHOT.card_type)
	_assert_equal(combo.count, 4, "第四张同类牌继续增加蓄力")
	for index in range(96):
		combo.register_card(STRAIGHT_SHOT.card_type)
	_assert_equal(combo.count, 100, "高层蓄力不封顶")
	_assert_true(combo.can_activate(), "三点连击允许主动技")
	combo.register_card(GLOVES.card_type)
	_assert_equal(combo.card_type, GLOVES.card_type, "换卡牌类型同步切换技能类型")
	_assert_equal(combo.count, 1, "换类型后连击重置为1")


# 三张攻击牌产生30点主动技伤害，熊按被动把该伤害减为15。
func _test_super_attack_and_bear_reduction() -> void:
	var battle = _create_battle(201, BEAR)
	for _index in range(3):
		battle.play_card(STRAIGHT_SHOT)
	_assert_equal(battle.combo_state.count, 3, "三张攻击牌积累三点攻击连击")
	_assert_true(battle.play_active_skill(SUPER_ATTACK), "超级攻击释放成功")
	_assert_equal(battle.enemy.health, 117, "熊承受卡牌18和减半后的主动技15伤害")
	_assert_equal(battle.combo_state.count, 0, "主动技后连击点清空")
	_assert_equal(battle.combo_state.card_type, COMBO_STATE.EMPTY_TYPE, "主动技后连击类型清空")
	battle.setup(212, TURTLE)
	battle.enemy.health = 100
	battle.enemy.max_health = 100
	battle.combo_state.card_type = 0
	battle.combo_state.count = 5
	battle.play_active_skill(SUPER_ATTACK)
	_assert_equal(battle.enemy.health, 50, "五层攻击造成50基础伤害")
	battle.free()


# 三层防御主动技锁定18护盾后清空，逐只发射手套直至击杀。
func _test_super_defense() -> void:
	var battle = _create_battle(202, TURTLE)
	for _index in range(3):
		battle.play_card(GLOVES)
	_assert_true(battle.play_active_skill(SUPER_DEFENSE), "超级防御释放成功")
	_assert_equal(battle.enemy.health, 0, "三只手套各18伤害击杀50血怪物")
	_assert_equal(battle.player.shield, 0, "释放防御主动技清空护盾")
	battle.free()


# 三点技能连击产生三段基础6伤害，不再施加力量。
func _test_super_ability() -> void:
	var battle = _create_battle(203, TURTLE)
	for _index in range(3):
		battle.play_card(TOWEL)
	_assert_true(battle.play_active_skill(SUPER_ABILITY), "超级能力释放成功")
	_assert_equal(battle.enemy.health, 32, "三次随机射门各造成6点伤害")
	_assert_equal(battle.player.strength_multiplier, 1.0, "技能主动技不再施加力量")
	battle.free()


# 四次以上Miss的失败QTE只消耗连击，不得对敌人造成伤害或给玩家添加主动技收益。
func _test_failed_qte_consumes_without_effect() -> void:
	var battle = _create_battle(206, TURTLE)
	for _index in range(3):
		battle.play_card(STRAIGHT_SHOT)
	var health_before: int = battle.enemy.health
	_assert_true(battle.consume_failed_active_skill(SUPER_ATTACK), "失败QTE可以消费已准备的主动技")
	_assert_equal(battle.enemy.health, health_before, "失败QTE不造成主动技伤害")
	_assert_equal(battle.combo_state.count, 0, "失败QTE仍清空连击点")
	_assert_equal(battle.combo_state.card_type, COMBO_STATE.EMPTY_TYPE, "失败QTE仍清空连击类型")
	battle.free()


# setup 代表进入新房间，必须彻底清除上一场的连击类型与点数。
func _test_new_battle_clears_combo() -> void:
	var battle = _create_battle(204, TURTLE)
	battle.play_card(STRAIGHT_SHOT)
	battle.setup(205, TURTLE)
	_assert_equal(battle.combo_state.count, 0, "新战斗清空连击点")
	_assert_equal(battle.combo_state.card_type, COMBO_STATE.EMPTY_TYPE, "新战斗清空连击类型")
	battle.free()


# 创建并挂入场景树，保证信号与控制器生命周期和真实战斗一致。
func _test_deferred_skill_hits() -> void:
	var battle = _create_battle(207, TURTLE)
	var queued: Array[Dictionary] = []
	battle.effect_resolved.connect(func(event: Dictionary) -> void:
		if event.get("deferred_damage", false):
			queued.append(event))
	battle.combo_state.card_type = 2
	battle.combo_state.count = 3
	_assert_true(battle.play_active_skill(SUPER_ABILITY, {}, true, true), "随机连射进入命中队列")
	_assert_equal(queued.size(), 3, "累计三次生成三颗独立足球")
	_assert_equal(battle.enemy.health, 50, "发射阶段不扣血")
	_assert_true(not battle.play_active_skill(SUPER_ABILITY), "释放后不能重复使用累计")
	for index in range(queued.size()):
		_assert_true(int(queued[index].shot_type) in [1, 2, 3], "每颗球路合法")
		_assert_true(battle.commit_deferred_damage(queued[index]), "逐颗命中提交")
		_assert_equal(battle.enemy.health, 50 - 6 * (index + 1), "每颗命中独立扣6血")
	_assert_true(not battle.commit_deferred_damage(queued[0]), "重复命中被拒绝")
	battle.setup(208, TURTLE)
	queued.clear()
	battle.combo_state.card_type = 1
	battle.combo_state.count = 3
	battle.play_active_skill(SUPER_DEFENSE, {}, true, true)
	_assert_equal(queued[0].amount, 0, "零护盾手套伤害为零")
	battle.commit_deferred_damage(queued[0])
	_assert_equal(battle.enemy.health, 50, "零伤手套不扣血")
	battle.setup(210, TURTLE)
	queued.clear()
	battle.player.shield = 4
	battle.combo_state.card_type = 1
	battle.combo_state.count = 5
	battle.play_active_skill(SUPER_DEFENSE, {}, true, true)
	_assert_equal(queued.size(), 5, "五层蓄力发射五只手套")
	_assert_equal(battle.player.shield, 0, "发射前清空护盾")
	for event in queued:
		_assert_equal(event.amount, 4, "所有手套锁定释放时护盾值")
		battle.commit_deferred_damage(event)
	_assert_equal(battle.enemy.health, 30, "五只手套各造成4伤害")
	battle.setup(211, TURTLE)
	queued.clear()
	battle.combo_state.card_type = 2
	battle.combo_state.count = 5
	battle.play_active_skill(SUPER_ABILITY, {}, true, true)
	_assert_equal(queued.size(), 5, "五层技能发射五颗随机球")
	battle.setup(209, TURTLE)
	queued.clear()
	battle.enemy.health = 5
	battle.combo_state.card_type = 2
	battle.combo_state.count = 3
	battle.play_active_skill(SUPER_ABILITY, {}, true, true)
	battle.commit_deferred_damage(queued[0])
	_assert_equal(battle.enemy.health, 0, "途中击杀生命不低于零")
	_assert_true(not battle.commit_deferred_damage(queued[1]), "死亡后的后续球不重复结算")
	battle.free()


# 创建真实战斗控制器供主动技数值和时序验收。
func _create_battle(seed_value: int, enemy_definition: Resource):
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(seed_value, enemy_definition)
	return battle


# 通用相等断言。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
