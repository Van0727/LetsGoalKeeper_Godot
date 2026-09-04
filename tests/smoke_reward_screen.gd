# 奖励界面冒烟测试：验证两项奖励完成后才提交房间完成并推进路线。
extends SceneTree

const REWARD_SCENE := preload("res://scenes/reward_screen.tscn")
const MAP_STATE := preload("res://scripts/map/map_state.gd")

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
	var map_state = screen.run_state.map_state
	var active_room: Dictionary = map_state.rooms_on_layer(1)[0]
	var connected_room: Dictionary = map_state.room_by_id(active_room.connections[0])
	map_state.begin_room(active_room.id)
	var initial_deck_size: int = screen.run_state.deck_card_ids.size()
	screen._on_choice_pressed(0)
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size + 1, "选中卡牌加入牌库")
	_assert_equal(screen.phase, screen.Phase.ITEM, "卡牌后进入战利品步骤")
	_assert_equal(screen.choices.size(), 3, "普通战显示三件战利品候选")
	_assert_equal(active_room.state, MAP_STATE.RoomState.ATTAINABLE, "只领取卡牌时房间尚未完成")
	_assert_equal(connected_room.state, MAP_STATE.RoomState.LOCKED, "奖励未完成时下一层保持锁定")
	screen._on_choice_pressed(0)
	_assert_equal(screen.run_state.owned_item_ids.size(), 1, "选中战利品加入本局")
	_assert_equal(screen.run_state.battles_won, 1, "两步奖励后推进胜场")
	_assert_equal(active_room.state, MAP_STATE.RoomState.VISITED, "两项奖励后房间标记完成")
	_assert_equal(connected_room.state, MAP_STATE.RoomState.ATTAINABLE, "两项奖励后解锁连线房间")
	_assert_equal(map_state.current_room_id, "", "奖励完成后清除进行中房间")

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
