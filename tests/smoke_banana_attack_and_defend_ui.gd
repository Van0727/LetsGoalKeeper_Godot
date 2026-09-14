# 香蕉＋攻守兼备界面回归：真实手牌出牌后应完成飞球、获得护盾并恢复回合输入。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const BANANA := preload("res://data/items/item_banana.tres")
const ATTACK_AND_DEFEND := preload("res://data/cards/card_attack_and_defend.tres")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	battle.run_state.start_new_run(606)
	_assert_true(battle.run_state.add_item(BANANA), "本局获得香蕉")
	battle.start_new_battle(TURTLE)
	await process_frame
	battle.ball_flight.playback_speed = 1000.0
	var deck: Array[Resource] = [ATTACK_AND_DEFEND]
	battle.deck_state.setup(deck, 606)
	battle.deck_state.draw_cards(1)
	battle._rebuild_hand()
	var timing: Dictionary = battle.rhythm_clock.judge_now()
	_assert_true(battle.try_play_hand_card(0, timing), "香蕉＋攻守兼备进入真实界面结算")
	for _attempt in range(50):
		if not battle._is_presenting_resolution and not battle._input_locked:
			break
		await create_timer(0.1).timeout
	_assert_true(not battle._is_presenting_resolution, "伤害和护盾表现队列完成")
	_assert_true(not battle._input_locked, "结算后解除输入锁")
	_assert_true(not battle.end_turn_button.disabled, "结束回合按钮恢复可用")
	_assert_equal(battle.controller.current_action_context.actual_shot_type, 2, "攻守兼备实际球型为香蕉球")
	# 乌龟在足球命中后反伤1点，先用攻守兼备获得的5点护盾吸收，故最终剩4点。
	_assert_equal(battle.controller.player.shield, 4, "攻守兼备获得护盾后正确吸收乌龟反伤")
	_assert_equal(battle.controller.player_cards_played_this_turn, 1, "核心成功计入一张牌")
	battle.free()
	if _failed:
		quit(1)
		return
	print("smoke_banana_attack_and_defend_ui: PASS")
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
