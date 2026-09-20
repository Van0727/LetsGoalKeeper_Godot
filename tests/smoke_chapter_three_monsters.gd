# 第三章怪物验收：七只进入章节池，固定行为、有限反伤及多条件蓄力分别走成功与未打断路径。
extends SceneTree

const BATTLE := preload("res://scripts/battle/battle_controller.gd")
const CATALOG := preload("res://data/enemies/enemy_catalog.tres")
const POOL := preload("res://data/encounters/chapter_3.tres")
const ATTACK := preload("res://data/cards/card_straight_shot.tres")
const LOB := preload("res://data/cards/card_lob_shot.tres")
const DEFENSE := preload("res://data/cards/card_gloves.tres")
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pool_and_simple_actions()
	_test_leopard()
	_test_bear()
	_test_falcon()
	_test_mantis()
	print("smoke_chapter_three_monsters: %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _battle(id: int) -> Node:
	var battle = BATTLE.new()
	root.add_child(battle)
	battle.setup(920, CATALOG.find_enemy(id))
	return battle


func _test_pool_and_simple_actions() -> void:
	_check(POOL.enemies.size() == 7, "第三章遭遇池完整")
	var counts := [0, 0, 0]
	for definition in POOL.enemies:
		counts[definition.tier] += 1
		_check(CATALOG.find_enemy(definition.id) != null, "遭遇池数字ID可查")
	_check(counts == [4, 2, 1], "第三章4小怪2精英1Boss")
	var robot = _battle(6008)
	robot.end_player_turn()
	_check(robot.player.health == 90 and robot.current_enemy_action.id == 20, "机器人首击与固定顺序")
	robot.end_player_turn()
	_check(robot.enemy.shield == 12 and robot.current_enemy_action.id == 21, "机器人护盾")
	robot.end_player_turn()
	_check(robot.player.health == 78 and robot.current_enemy_action.id == 19, "机器人三段连发")
	robot.free()
	var hedgehog = _battle(6031)
	hedgehog.end_player_turn()
	hedgehog.end_player_turn()
	_check(hedgehog.enemy.shield == 8 and hedgehog.enemy_thorns_remaining == 1, "刺猬防御含一次反伤")
	hedgehog.player_attack(9)
	_check(hedgehog.enemy_thorns_remaining == 0, "刺猬反伤次数耗尽")
	hedgehog.free()


func _test_leopard() -> void:
	var battle = _battle(6009)
	battle.end_player_turn()
	battle.end_player_turn()
	_check(battle.enemy_charge_conditions.size() == 2 and battle.current_enemy_action.id == 24, "猎豹双条件蓄力")
	battle._register_charge_card_play(DEFENSE, {"grade": 0})
	_check(not battle.enemy_charge_interrupted, "Perfect防御牌不能打断猎豹")
	battle._register_charge_card_play(ATTACK, {})
	_check(not battle.enemy_charge_interrupted, "无节奏结果不能当作Perfect")
	_check(battle.play_card(ATTACK, {"grade": 0}), "猎豹窗口内正常支付并打出攻击牌")
	_check(battle.current_enemy_action.id == 25, "Perfect攻击牌打断猎豹")
	battle.free()
	battle = _battle(6009)
	battle.end_player_turn()
	battle.end_player_turn()
	battle.player_attack(16)
	_check(battle.current_enemy_action.id == 25, "有效伤害路径打断猎豹")
	battle.free()


func _test_bear() -> void:
	var battle = _battle(6015)
	for turn in range(3):
		battle.end_player_turn()
	_check(battle.current_enemy_action.id == 31 and battle.enemy_charge_threshold == 24, "熊重炮打断窗口")
	battle.player_attack(24)
	_check(battle.current_enemy_action.id == 32, "熊达标改弱攻击")
	battle.free()


func _test_falcon() -> void:
	var battle = _battle(6041)
	battle.end_player_turn()
	battle.end_player_turn()
	_check(battle.play_card(ATTACK), "猎鹰窗口内打出直球")
	_check(battle.play_card(ATTACK), "猎鹰窗口内重复直球")
	_check(not battle.enemy_charge_interrupted, "同球型重复不增加猎鹰进度")
	_check(battle.play_card(LOB), "猎鹰窗口内打出挑射")
	_check(battle.current_enemy_action.id == 44, "第二种球型打断猎鹰")
	battle.free()
	battle = _battle(6041)
	battle.end_player_turn()
	battle.end_player_turn()
	battle.player_attack(22)
	_check(battle.current_enemy_action.id == 44, "猎鹰伤害替代路径")
	battle.free()


func _test_mantis() -> void:
	var battle = _battle(6023)
	for turn in range(4):
		battle.end_player_turn()
	_check(battle.enemy_charge_conditions.size() == 3 and battle.current_enemy_action.id == 37, "螳螂三条件蓄力")
	battle._register_charge_card_play(DEFENSE, {"grade": 0})
	battle._register_charge_card_play(DEFENSE, {"grade": 0})
	_check(battle.current_enemy_action.id == 38, "两张Perfect防御牌打断螳螂")
	battle.free()
	battle = _battle(6023)
	for turn in range(4):
		battle.end_player_turn()
	battle.player_attack(30)
	_check(battle.current_enemy_action.id == 38, "螳螂有效伤害路径")
	battle.free()
	battle = _battle(6023)
	for turn in range(4):
		battle.end_player_turn()
	for hit in range(6):
		battle.player_attack(1)
	_check(battle.current_enemy_action.id == 38, "螳螂六次命中路径")
	battle.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)
