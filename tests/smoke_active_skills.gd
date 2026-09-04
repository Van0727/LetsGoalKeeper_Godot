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
	_test_new_battle_clears_combo()

	if _failed:
		quit(1)
		return
	print("smoke_active_skills: PASS")
	quit()


# 同类型累积到3点封顶，换类型后改为新类型的1点。
func _test_combo_switch_and_cap() -> void:
	var combo = COMBO_STATE.new()
	combo.register_card(STRAIGHT_SHOT.card_type)
	combo.register_card(STRAIGHT_SHOT.card_type)
	combo.register_card(STRAIGHT_SHOT.card_type)
	combo.register_card(STRAIGHT_SHOT.card_type)
	_assert_equal(combo.count, 3, "连击点上限为3")
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
	battle.free()


# 三张防御牌后，超级防御按每点6额外获得18护盾。
func _test_super_defense() -> void:
	var battle = _create_battle(202, TURTLE)
	for _index in range(3):
		battle.play_card(GLOVES)
	_assert_true(battle.play_active_skill(SUPER_DEFENSE), "超级防御释放成功")
	_assert_equal(battle.player.shield, 36, "普通防御与超级防御护盾叠加")
	battle.free()


# 能力连击释放后获得1.5倍力量，持续回合等于三点连击。
func _test_super_ability() -> void:
	var battle = _create_battle(203, TURTLE)
	for _index in range(3):
		battle.play_card(TOWEL)
	_assert_true(battle.play_active_skill(SUPER_ABILITY), "超级能力释放成功")
	_assert_equal(battle.player.strength_multiplier, 1.5, "超级能力力量倍率")
	_assert_equal(battle.player.strength_turns, 3, "超级能力持续三回合")
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
