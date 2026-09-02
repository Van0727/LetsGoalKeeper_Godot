extends SceneTree

const COMBATANT_STATE := preload("res://scripts/battle/combatant_state.gd")
const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_damage_shield_and_healing()
	_test_turn_flow_and_victory()
	_test_player_defeat()
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


func _test_player_defeat() -> void:
	var battle = BATTLE_CONTROLLER.new()
	root.add_child(battle)
	battle.setup(7)
	battle.player.take_damage(99)
	battle.end_player_turn()
	_assert_equal(battle.phase, battle.Phase.FINISHED, "玩家死亡后结束战斗")
	_assert_equal(battle.player.health, 0, "敌人致命攻击后玩家生命")
	battle.free()


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])
