# 阶段8章节推进冒烟测试：验证 Boss 奖励后切章、状态保留和第三章通关边界。
extends SceneTree

const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const MAP_STATE := preload("res://scripts/map/map_state.gd")

var _failed := false


# 延迟执行，确保资源和场景树已完成初始化。
func _initialize() -> void:
	call_deferred("_run")


# 连续结算三章 Boss，并确认不会生成不存在的第四章。
func _run() -> void:
	var run_state = RUN_STATE_SCRIPT.new()
	root.add_child(run_state)
	run_state.start_new_run(808)
	run_state.player_hp = 73
	var initial_deck: Array[String] = run_state.deck_card_ids.duplicate()

	for expected_chapter in [2, 3]:
		_enter_current_boss(run_state)
		var old_map = run_state.map_state
		var result: int = run_state.complete_reward_and_advance()
		_assert_equal(result, run_state.RewardFlowResult.CHAPTER_ADVANCED, "Boss后进入第%d章" % expected_chapter)
		_assert_equal(run_state.chapter, expected_chapter, "当前章节更新为%d" % expected_chapter)
		_assert_true(run_state.map_state != old_map, "第%d章重新生成地图" % expected_chapter)
		_assert_equal(run_state.run_status, run_state.RunStatus.ACTIVE, "切章后对局保持进行中")
		_assert_equal(run_state.player_hp, 73, "切章保留玩家生命")
		_assert_equal(run_state.deck_card_ids, initial_deck, "切章保留本局牌库")

	_enter_current_boss(run_state)
	var final_map = run_state.map_state
	var final_result: int = run_state.complete_reward_and_advance()
	_assert_equal(final_result, run_state.RewardFlowResult.RUN_COMPLETED, "第三章Boss后返回通关结果")
	_assert_equal(run_state.chapter, 3, "通关后不生成第四章")
	_assert_equal(run_state.run_status, run_state.RunStatus.COMPLETED, "本局标记为已通关")
	_assert_true(run_state.map_state == final_map and run_state.map_state.boss_visited(), "保留第三章完成地图用于结算")
	_assert_equal(run_state.battles_won, 3, "三次Boss奖励均计入胜场")
	run_state.free()

	if _failed:
		quit(1)
		return
	print("smoke_chapter_progression: PASS")
	quit()


# 走完前两层并进入当前章 Boss；普通房只推进路线，不模拟其奖励数值。
func _enter_current_boss(run_state: Node) -> void:
	for layer in [1, 2]:
		var room: Dictionary = run_state.map_state.get_attainable_rooms()[0]
		_assert_equal(room.layer, layer, "按顺序进入第%d层" % layer)
		run_state.map_state.begin_room(room.id)
		run_state.map_state.complete_current_room()
	var boss: Dictionary = run_state.map_state.get_attainable_rooms()[0]
	_assert_equal(boss.type, MAP_STATE.RoomType.BOSS, "最终层为Boss房")
	run_state.map_state.begin_room(boss.id)
	run_state.pending_reward_is_boss = true


# 通用相等断言，失败时输出章节推进节点。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言，允许一次运行列出全部状态契约问题。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
