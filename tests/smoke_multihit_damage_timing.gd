# 多段射门命中时序回归：验证出牌阶段不预扣血，每颗足球抵达怪物时才独立扣除该段生命。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const BARRAGE_SHOT := preload("res://data/cards/card_barrage_shot.tres")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")

var _failed := false
var _observed_enemy_health: Array[int] = []
var _observed_health_text: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


# 使用真实战斗场景和四段连续射门，覆盖待命中、逐段刷新与最终结算三个阶段。
func _run() -> void:
	root.size = Vector2i(360, 640)
	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	battle.run_state.start_new_run(9104)
	battle.start_new_battle(TURTLE)
	await process_frame

	# 加速只压缩测试等待时间，不改变四颗球的发射与命中先后顺序。
	battle.ball_flight.playback_speed = 2.0
	var deck: Array[Resource] = [BARRAGE_SHOT]
	battle.deck_state.setup(deck, 9104)
	battle.deck_state.draw_cards(1)
	battle._rebuild_hand()
	var timing := {
		"grade": battle.rhythm_clock.JudgementGrade.PERFECT,
		"effect_multiplier": 1.0,
		"target_time": battle.rhythm_clock.get_music_time(),
		"beat_index": 0,
		"bar_index": 0,
		"subdivision": 8,
	}
	_assert_true(battle.try_play_hand_card(0, timing), "四段射门成功进入表现队列")
	_assert_equal(battle.controller.enemy.health, 50, "出牌后、足球命中前不预扣怪物生命")
	_assert_equal(battle.enemy_health_text.text, "50/50", "命中前血条保持满血")

	for _frame in range(300):
		_capture_visible_enemy_health(battle)
		if not battle._is_presenting_resolution and not battle._input_locked:
			break
		await process_frame
	_capture_visible_enemy_health(battle)

	_assert_true(not battle._is_presenting_resolution, "多段飞球在限定帧数内完成")
	_assert_equal(_observed_enemy_health, [47, 44, 41, 38], "四颗球命中时分别扣除3点生命")
	_assert_equal(_observed_health_text, ["47/50", "44/50", "41/50", "38/50"], "怪物血条随每次命中逐段刷新")
	_assert_equal(battle.controller.enemy.health, 38, "四段命中后总计造成12点伤害")

	battle.free()
	if _failed:
		quit(1)
		return
	print("smoke_multihit_damage_timing: PASS")
	quit()


# 每帧读取玩家真正看到的顶部血条；只记录生命实际变化，忽略支付费用等无伤害刷新。
func _capture_visible_enemy_health(battle) -> void:
	var health: int = battle.controller.enemy.health
	if health >= 50:
		return
	if not _observed_enemy_health.is_empty() and _observed_enemy_health[-1] == health:
		return
	_observed_enemy_health.append(health)
	_observed_health_text.append(battle.enemy_health_text.text)


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
