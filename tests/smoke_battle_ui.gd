# 阶段 3 战斗界面冒烟测试：验证起手、结算锁、回合抽弃牌与胜负界面。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")

var _failed := false


# 延迟执行以等待根视口初始化。
func _initialize() -> void:
	call_deferred("_run")


# 实例化真实战斗场景并覆盖阶段 3 的关键交互状态。
func _run() -> void:
	root.size = Vector2i(360, 640)
	var battle_screen := BATTLE_SCENE.instantiate()
	root.add_child(battle_screen)
	await process_frame

	_assert_equal(battle_screen.deck_state.hand.size(), 3, "战斗开始抽三张")
	_assert_equal(battle_screen.hand_layer.get_child_count(), 3, "三张手牌均生成视图")
	_assert_equal(battle_screen.controller.player.energy, 3, "玩家初始能量")

	var played: bool = battle_screen.try_play_hand_card(0)
	_assert_true(played, "第一张手牌可以结算")
	_assert_true(not battle_screen.try_play_hand_card(0), "结算帧内拦截重复出牌")
	await process_frame
	_assert_equal(battle_screen.deck_state.hand.size(), 3, "出牌后补回三张")
	_assert_equal(battle_screen.controller.player.energy, 2, "出牌支付一点能量")

	var previous_turn: int = battle_screen.controller.turn_number
	battle_screen._on_end_turn_pressed()
	await process_frame
	_assert_equal(battle_screen.controller.turn_number, previous_turn + 1, "结束回合后推进回合")
	_assert_equal(battle_screen.deck_state.hand.size(), 3, "新回合重新抽三张")
	_assert_equal(battle_screen.controller.player.energy, 3, "新回合回满能量")

	# GM跳过绕过乌龟反伤，直接复用正常胜利与奖励入口。
	battle_screen.controller.player.health = 1
	battle_screen._on_gm_skip_pressed()
	_assert_equal(battle_screen.controller.enemy.health, 0, "GM跳过立即消灭敌人")
	_assert_equal(battle_screen.controller.player.health, 1, "GM跳过不触发乌龟反伤")
	_assert_true(battle_screen.result_overlay.visible, "胜利后显示结果层")
	_assert_true(battle_screen.end_turn_button.disabled, "胜利后锁定结束回合")
	_assert_true(battle_screen.gm_skip_button.disabled, "胜利后锁定GM跳过")

	# 重开后把玩家置于濒死状态，验证敌方行动可进入失败结果且不会再抽牌。
	battle_screen.start_new_battle()
	battle_screen.controller.player.health = 1
	battle_screen._on_end_turn_pressed()
	await process_frame
	_assert_equal(battle_screen.controller.phase, battle_screen.controller.Phase.FINISHED, "致命敌方攻击结束战斗")
	_assert_equal(battle_screen.result_title.text, "战斗失败", "失败结果标题")
	_assert_true(battle_screen.result_overlay.visible, "失败后显示结果层")
	_assert_equal(
		battle_screen.run_state.run_status,
		battle_screen.run_state.RunStatus.FAILED,
		"失败后本局状态明确终止"
	)

	if _failed:
		quit(1)
		return
	print("smoke_battle_ui: PASS")
	quit()


# 通用相等断言，失败时保留实际值便于定位 UI 状态不同步。
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
