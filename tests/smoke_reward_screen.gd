# 奖励界面冒烟测试：验证战斗卡面复用、确认隐藏及飞出动画结束后才发放两类奖励。
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
	_assert_equal(screen.card_views[0].card_definition, screen.choices[0], "奖励卡牌复用战斗卡面并绑定候选定义")
	var map_state = screen.run_state.map_state
	var active_room: Dictionary = map_state.rooms_on_layer(1)[0]
	var connected_room: Dictionary = map_state.room_by_id(active_room.connections[0])
	map_state.begin_room(active_room.id)
	var initial_deck_size: int = screen.run_state.deck_card_ids.size()
	screen._on_confirm_pressed()
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size, "未预选时确认不会发放卡牌")
	screen._on_choice_pressed(0)
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size, "预选卡牌时不立即加入牌库")
	_assert_equal(
		screen.choice_buttons[0].pivot_offset,
		Vector2(0.0, screen.choice_buttons[0].size.y * 0.5),
		"左侧卡牌使用左侧中心锚点"
	)
	_assert_equal(screen.choice_buttons[0].pivot_offset_ratio, Vector2.ZERO, "左侧卡牌不叠加比例锚点")
	await create_timer(screen.SELECT_SCALE_DURATION + 0.05).timeout
	_assert_equal(screen.choice_buttons[0].scale, Vector2(1.5, 1.5), "预选卡牌缓动放大至1.5倍")
	_assert_equal(screen.phase, screen.Phase.CARD, "预选卡牌后停留在卡牌步骤")
	screen._on_choice_pressed(2)
	_assert_equal(
		screen.choice_buttons[2].pivot_offset,
		Vector2(screen.choice_buttons[2].size.x, screen.choice_buttons[2].size.y * 0.5),
		"右侧卡牌使用右侧中心锚点"
	)
	_assert_equal(screen.choice_buttons[2].pivot_offset_ratio, Vector2.ZERO, "右侧卡牌不叠加比例锚点")
	await create_timer(screen.SELECT_SCALE_DURATION + 0.05).timeout
	_assert_equal(screen.choice_buttons[0].scale, Vector2.ONE, "取消选中后旧卡牌缓动缩回原尺寸")
	_assert_equal(screen.choice_buttons[2].scale, Vector2(1.5, 1.5), "右侧卡牌缓动放大至1.5倍")
	screen._on_choice_pressed(1)
	_assert_equal(
		screen.choice_buttons[1].pivot_offset,
		screen.choice_buttons[1].size * 0.5,
		"中间卡牌使用几何中心锚点"
	)
	_assert_equal(screen.choice_buttons[1].pivot_offset_ratio, Vector2.ZERO, "中间卡牌不叠加比例锚点")
	await create_timer(screen.SELECT_SCALE_DURATION + 0.05).timeout
	_assert_equal(screen.choice_buttons[2].scale, Vector2.ONE, "再次切换后右侧卡牌缓动缩回")
	_assert_equal(screen.choice_buttons[1].scale, Vector2(1.5, 1.5), "中间卡牌缓动放大至1.5倍")
	var card_start_y: float = screen.choice_buttons[1].global_position.y
	var left_card_position: Vector2 = screen.choice_buttons[0].global_position
	var right_card_position: Vector2 = screen.choice_buttons[2].global_position
	var selected_card_transform: Transform2D = screen.choice_buttons[1].get_global_transform()
	screen._on_confirm_pressed()
	_assert_equal(screen.confirm_button.self_modulate.a, 0.0, "卡牌确认后确认按钮视觉隐藏")
	_assert_equal(screen.choice_buttons[1].modulate.a, 0.0, "飞出副本出现后原位置卡牌完全移除")
	var flying_card_at_start := screen.get_node_or_null("FlyingReward") as Control
	_assert_equal(flying_card_at_start.get_global_transform(), selected_card_transform, "动画起点对齐点击放大后的完整变换")
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size, "飞出动画结束前不发放卡牌")
	await process_frame
	_assert_equal(screen.choice_buttons[0].global_position, left_card_position, "获得动画期间左侧卡牌不重排")
	_assert_equal(screen.choice_buttons[2].global_position, right_card_position, "获得动画期间右侧卡牌不重排")
	await create_timer(screen.REWARD_RISE_DURATION * 0.75).timeout
	var flying_card := screen.get_node_or_null("FlyingReward") as Control
	_assert_true(flying_card != null and flying_card.global_position.y < card_start_y, "卡牌获得动画先向上抬升")
	await create_timer(screen.REWARD_FLY_DURATION + 0.1).timeout
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size + 1, "确认后卡牌加入牌库")
	_assert_equal(screen.phase, screen.Phase.ITEM, "卡牌后进入战利品步骤")
	_assert_equal(screen.confirm_button.self_modulate.a, 1.0, "进入遗物步骤后重新显示确认按钮")
	_assert_equal(screen.choices.size(), 3, "普通战显示三件战利品候选")
	_assert_equal(active_room.state, MAP_STATE.RoomState.ATTAINABLE, "只领取卡牌时房间尚未完成")
	_assert_equal(connected_room.state, MAP_STATE.RoomState.LOCKED, "奖励未完成时下一层保持锁定")
	screen._on_choice_pressed(0)
	_assert_equal(screen.run_state.owned_item_ids.size(), 0, "预选遗物时不立即加入本局")
	_assert_equal(screen.choice_buttons[0].scale, Vector2(1.5, 1.5), "预选遗物放大1.5倍")
	screen._on_confirm_pressed()
	_assert_equal(screen.confirm_button.self_modulate.a, 0.0, "遗物确认后确认按钮视觉隐藏")
	_assert_equal(screen.run_state.owned_item_ids.size(), 0, "飞出动画结束前不发放遗物")
	await create_timer(screen.REWARD_FLY_DURATION + 0.1).timeout
	_assert_equal(screen.run_state.owned_item_ids.size(), 1, "确认后遗物加入本局")
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


# 通用布尔断言。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
