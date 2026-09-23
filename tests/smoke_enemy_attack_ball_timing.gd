# 敌人飞球伤害时序回归：验证结束回合后先播放敌方足球，命中玩家前不扣血，命中后才执行攻击。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	battle.run_state.start_new_run(9201)
	battle.start_new_battle(TURTLE)
	await process_frame

	# 固定乌龟的攻击行动，排除随机抽到防御导致本测试没有足球。
	battle.controller.current_enemy_action = TURTLE.actions[0]
	battle.controller.enemy_intent_damage = TURTLE.actions[0].amount
	battle.ball_flight.playback_speed = 2.0
	var health_before: int = battle.controller.player.health

	battle._on_end_turn_pressed()
	_assert_equal(battle.controller.phase, battle.controller.Phase.PLAYER_END, "敌人攻击在飞球期间停留于玩家结算阶段")
	_assert_equal(battle.controller.player.health, health_before, "足球发射时不提前扣除玩家生命")
	for _frame in range(3):
		await process_frame
	_assert_equal(battle.controller.player.health, health_before, "足球尚未抵达时玩家生命保持不变")

	for _frame in range(300):
		if not battle._input_locked:
			break
		await process_frame
	_assert_true(not battle._input_locked, "敌方飞球与回合推进在限定帧数内完成")
	_assert_equal(battle.controller.player.health, health_before - 3, "足球命中后才结算乌龟3点攻击伤害")
	_assert_equal(battle.controller.phase, battle.controller.Phase.PLAYER_TURN, "命中结算完成后进入下一玩家回合")

	battle.free()
	if _failed:
		quit(1)
		return
	print("smoke_enemy_attack_ball_timing: PASS")
	quit()


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
