# 旧版敌人兼容冒烟测试：验证旧行动、被动和确定性，并验证新版第一章遭遇池的级别覆盖。
extends SceneTree

const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")
const BEAR := preload("res://data/enemies/enemy_bear.tres")
const PENGUIN := preload("res://data/enemies/enemy_penguin.tres")
const TRAINING_BOSS := preload("res://data/enemies/enemy_training_raccoon_boss.tres")
const CHAPTER_ONE := preload("res://data/encounters/chapter_1.tres")

var _failed := false


# 延迟执行以等待场景树初始化。
func _initialize() -> void:
	call_deferred("_run")


# 顺序执行阶段 4 的核心行为验收。
func _run() -> void:
	_test_turtle_sequence_and_thorns()
	_test_simultaneous_death_ruling()
	_test_bear_active_skill_reduction()
	_test_penguin_drain_and_weakness()
	_test_weighted_boss_is_deterministic()
	_test_chapter_one_encounter_pool()

	if _failed:
		quit(1)
		return
	print("smoke_enemy_actions: PASS")
	quit()


# 乌龟依次攻击和防御，每次被命中都触发一次反伤。
func _test_turtle_sequence_and_thorns() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(101, TURTLE)
	_assert_equal(battle.enemy.max_health, 50, "乌龟生命来自数据")
	var intent_damage := battle.get_enemy_intent_damage()
	battle.player_attack(6)
	_assert_equal(battle.player.health, 99, "乌龟受到攻击后反伤1")
	battle.end_player_turn()
	_assert_equal(battle.player.health, 99 - intent_damage, "攻击意图与实际伤害一致")
	_assert_true("缩壳" in battle.get_enemy_intent_text(), "乌龟下一行动为缩壳")
	battle.end_player_turn()
	_assert_equal(battle.enemy.shield, 6, "乌龟缩壳获得6护盾")
	battle.free()


# 乌龟被击杀时仍先反伤；双方同时死亡按玩家失败结算。
func _test_simultaneous_death_ruling() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	# Dictionary 以引用方式跨闭包保存信号结果，避免局部布尔值按值捕获。
	var result := {"victory": true}
	battle.battle_finished.connect(func(victory: bool) -> void: result.victory = victory)
	battle.setup(102, TURTLE)
	battle.player.health = 1
	battle.enemy.health = 1
	battle.player_attack(6)
	_assert_true(battle.player.is_dead() and battle.enemy.is_dead(), "反伤可造成双方同时死亡")
	_assert_true(not result.victory, "双方同时死亡裁定玩家失败")
	battle.free()


# 熊只对主动技能标签减伤，普通直接攻击保持原值。
func _test_bear_active_skill_reduction() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(103, BEAR)
	battle.player_attack(20, "active_skill")
	_assert_equal(battle.enemy.health, 140, "熊将主动技能伤害减半")
	battle.player_attack(20, "card")
	_assert_equal(battle.enemy.health, 120, "熊不削减普通卡牌伤害")
	battle.free()


# 企鹅的吸血只计算穿透护盾的生命伤害，第三个行动施加虚弱。
func _test_penguin_drain_and_weakness() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(104, PENGUIN)
	battle.enemy.health = 1
	battle.player.shield = 3
	battle.end_player_turn()
	_assert_true(battle.enemy.health > 1, "企鹅吸血恢复实际生命伤害")
	battle.end_player_turn()
	battle.end_player_turn()
	_assert_equal(battle.player.strength_status, battle.player.StrengthStatus.WEAKNESS, "企鹅第三行动施加虚弱")
	_assert_equal(battle.player.strength_turns, 2, "企鹅虚弱持续两回合")
	battle.free()


# 两场同种子 Boss 战必须产生完全一致的加权行动和最终随机数。
func _test_weighted_boss_is_deterministic() -> void:
	var first = BATTLE_CONTROLLER.new()
	var second = BATTLE_CONTROLLER.new()
	root.add_child(first)
	root.add_child(second)
	first.setup(105, TRAINING_BOSS)
	second.setup(105, TRAINING_BOSS)
	for turn in range(4):
		_assert_equal(first.get_enemy_intent_text(), second.get_enemy_intent_text(), "Boss第%d次确定性意图" % turn)
		first.end_player_turn()
		second.end_player_turn()
	first.free()
	second.free()


# 第一章已改为三种小怪、两种精英和大象Boss；旧资源机制由上面的兼容测试继续覆盖。
func _test_chapter_one_encounter_pool() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 106
	_assert_true(CHAPTER_ONE.pick_enemy(PENGUIN.Tier.NORMAL, rng).id in [6001, 6002, 6003], "普通池选择第一章小怪")
	_assert_true(CHAPTER_ONE.pick_enemy(BEAR.Tier.ELITE, rng).id in [6011, 6012], "精英池选择第一章精英")
	_assert_equal(CHAPTER_ONE.pick_enemy(TRAINING_BOSS.Tier.BOSS, rng).id, 6021, "Boss池选择新版大象")


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
