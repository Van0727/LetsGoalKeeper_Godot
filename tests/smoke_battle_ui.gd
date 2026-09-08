# 战斗界面冒烟测试：验证节拍入口、起手、结算锁、回合抽弃牌与胜负界面。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")

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
	# 显式重置本局，避免本机 user:// 残留存档让玩家以濒死状态进入冒烟测试。
	battle_screen.run_state.start_new_run(7301)
	battle_screen.start_new_battle(TURTLE)
	await process_frame
	# 冒烟测试保留真实动画链路但提高播放速度，避免按正式时长等待。
	battle_screen.ball_flight.playback_speed = 1000.0

	_assert_equal(battle_screen.deck_state.hand.size(), 3, "战斗开始抽三张")
	_assert_equal(battle_screen.hand_layer.get_child_count(), 3, "三张手牌均生成视图")
	_assert_equal(battle_screen.controller.player.energy, 3, "玩家初始能量")
	_assert_equal(battle_screen.rhythm_clock.bpm, 100.0, "战斗使用基础鼓点的100 BPM配置")
	_assert_true(battle_screen.rhythm_clock.music != null, "战斗已绑定基础鼓点BGM")
	_assert_true(battle_screen.rhythm_feedback.visible, "战斗显示节拍反馈控件")
	# 新竖屏布局必须保持敌人在手牌上方、玩家生命栏在手牌下方，防止后续内容撑高造成重叠。
	var enemy_rect: Rect2 = battle_screen.enemy_display.get_global_rect()
	var first_card_rect: Rect2 = battle_screen.hand_layer.get_child(0).get_global_rect()
	var player_rect: Rect2 = battle_screen.player_display.get_global_rect()
	_assert_true(enemy_rect.end.y < first_card_rect.position.y, "敌方信息位于手牌上方")
	_assert_true(first_card_rect.end.y < player_rect.position.y, "手牌不遮挡底部玩家生命栏")
	_assert_true(not battle_screen.drag_threshold_guide.visible, "未拖拽时不显示虚线")
	battle_screen._on_card_drag_started(battle_screen.hand_layer.get_child(0))
	_assert_true(battle_screen.drag_threshold_guide.visible, "开始拖拽后显示虚线")
	battle_screen._on_card_drag_moved(battle_screen.hand_layer.get_child(0), Vector2.ZERO, true)
	_assert_true(battle_screen.drag_threshold_guide.prompt_label.visible, "越线后显示松开提示")
	battle_screen._on_card_drag_moved(battle_screen.hand_layer.get_child(0), Vector2.ZERO, false)
	_assert_true(not battle_screen.drag_threshold_guide.prompt_label.visible, "返回线下后隐藏松开提示")
	battle_screen._on_card_drag_finished(battle_screen.hand_layer.get_child(0), false)

	var played: bool = battle_screen.try_play_hand_card(0)
	_assert_true(played, "第一张手牌可以结算")
	_assert_true(not battle_screen.try_play_hand_card(0), "结算帧内拦截重复出牌")
	await _wait_for_resolution(battle_screen)
	_assert_equal(battle_screen.deck_state.hand.size(), 3, "出牌后补回三张")
	_assert_equal(battle_screen.controller.player.energy, 2, "出牌支付一点能量")

	var previous_turn: int = battle_screen.controller.turn_number
	battle_screen._on_end_turn_pressed()
	await process_frame
	_assert_equal(battle_screen.controller.turn_number, previous_turn + 1, "结束回合后推进回合")
	_assert_equal(battle_screen.deck_state.hand.size(), 3, "新回合重新抽三张")
	_assert_equal(battle_screen.controller.player.energy, 3, "新回合回满能量")

	# GM入口使用二级面板；打开时锁住战斗操作，关闭后恢复，不改变战斗状态。
	_assert_true(battle_screen.gm_menu_button.visible, "战斗界面显示GM入口")
	battle_screen._on_gm_menu_pressed()
	_assert_true(battle_screen.gm_overlay.visible, "点击GM入口显示二级面板")
	_assert_true(battle_screen.end_turn_button.disabled, "GM面板打开时锁住结束回合")
	battle_screen._on_gm_close_pressed()
	_assert_true(not battle_screen.gm_overlay.visible, "关闭按钮隐藏GM面板")
	_assert_true(not battle_screen.end_turn_button.disabled, "关闭GM面板后恢复战斗输入")

	# 面板内跳过按钮绕过乌龟反伤，直接复用正常胜利与奖励入口。
	battle_screen.controller.player.health = 1
	battle_screen._on_gm_menu_pressed()
	battle_screen._on_gm_skip_pressed()
	_assert_equal(battle_screen.controller.enemy.health, 0, "GM跳过立即消灭敌人")
	_assert_equal(battle_screen.controller.player.health, 1, "GM跳过不触发乌龟反伤")
	_assert_true(not battle_screen.gm_overlay.visible, "GM跳过后关闭二级面板")
	_assert_true(battle_screen.result_overlay.visible, "胜利后显示结果层")
	_assert_true(battle_screen.end_turn_button.disabled, "胜利后锁定结束回合")
	_assert_true(battle_screen.gm_menu_button.disabled, "胜利后锁定GM入口")

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


# 等待异步表现队列完成，并设置帧数上限避免动画异常时测试永久挂起。
func _wait_for_resolution(battle_screen) -> void:
	for _frame in range(30):
		if not battle_screen._is_presenting_resolution and not battle_screen._input_locked:
			return
		await process_frame
	_assert_true(false, "卡牌动画队列在限定帧数内完成")


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
