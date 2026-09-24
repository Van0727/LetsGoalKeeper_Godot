# 精英奖励流程回归：验证精英胜利标记两步奖励，并在卡牌后进入普通品级奖励品选择。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const REWARD_SCENE := preload("res://scenes/reward_screen.tscn")
const MAP_STATE := preload("res://scripts/map/map_state.gd")
const ELITE_ENEMY := preload("res://data/enemies/enemy_bear.tres")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var run_state: Node = root.get_node("RunState")
	run_state.start_new_run(9301)
	_assert_true(_select_elite_room(run_state), "测试本局存在可用于奖励分级的精英房")

	var battle := BATTLE_SCENE.instantiate()
	root.add_child(battle)
	await process_frame
	battle.start_new_battle(ELITE_ENEMY)
	await process_frame
	_assert_true(battle.controller.debug_force_victory(), "精英怪通过统一死亡出口结束战斗")
	_assert_true(await _wait_until_visible(battle.result_overlay, 2.0), "精英胜利结果层在限定时间内显示")
	_assert_equal(battle.reward_stat_label.text, "✦  2 项奖励", "精英胜利预告卡牌与奖励品两项奖励")
	_assert_true(run_state.pending_reward_is_boss, "精英胜利保留第二步奖励品标记")
	battle.free()

	var reward := REWARD_SCENE.instantiate()
	root.add_child(reward)
	await process_frame
	_assert_true(reward.item_step.visible, "精英奖励页显示奖励品步骤")
	reward._on_choice_pressed(0)
	reward._on_confirm_pressed()
	await create_timer(reward.REWARD_FLY_DURATION + 0.2).timeout
	_assert_equal(reward.phase, reward.Phase.ITEM, "领取精英卡牌后进入奖励品选择")
	_assert_true(not reward.choices.is_empty(), "精英奖励品池提供可选奖励")
	for item in reward.choices:
		_assert_equal(item.rarity, 0, "精英使用普通品级奖励品池")

	reward.free()
	if _failed:
		quit(1)
		return
	print("smoke_elite_item_reward: PASS")
	quit()


# 直接选中生成地图中的精英房，保留真实房型供奖励页区分精英与 Boss 奖励池。
func _select_elite_room(run_state: Node) -> bool:
	for room in run_state.map_state.rooms:
		if int(room.get("type", MAP_STATE.RoomType.NORMAL)) == MAP_STATE.RoomType.ELITE:
			run_state.map_state.current_room_id = str(room.id)
			return true
	return false


func _wait_until_visible(control: CanvasItem, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while not control.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	return control.visible


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
