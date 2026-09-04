# 奖励界面冒烟测试：验证卡牌与战利品必须依次各选一次，完成后才推进下一战。
extends SceneTree

const REWARD_SCENE := preload("res://scenes/reward_screen.tscn")

var _failed := false


# 延迟执行以等待根视口初始化。
func _initialize() -> void:
	call_deferred("_run")


# 使用奖励真实场景完成两步选择，并检查其局部 RunState 变化。
func _run() -> void:
	root.size = Vector2i(360, 640)
	var screen := REWARD_SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	_assert_equal(screen.phase, screen.Phase.CARD, "奖励先进入卡牌步骤")
	_assert_equal(screen.choices.size(), 3, "显示三张卡牌候选")
	var initial_deck_size: int = screen.run_state.deck_card_ids.size()
	screen._on_choice_pressed(0)
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size + 1, "选中卡牌加入牌库")
	_assert_equal(screen.phase, screen.Phase.ITEM, "卡牌后进入战利品步骤")
	_assert_equal(screen.choices.size(), 3, "普通战显示三件战利品候选")
	screen._on_choice_pressed(0)
	_assert_equal(screen.run_state.owned_item_ids.size(), 1, "选中战利品加入本局")
	_assert_equal(screen.run_state.battles_won, 1, "两步奖励后推进胜场")

	if _failed:
		quit(1)
		return
	print("smoke_reward_screen: PASS")
	quit()


# 通用相等断言。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])
