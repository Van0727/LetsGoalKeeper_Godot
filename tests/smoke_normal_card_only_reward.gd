# 小怪单步奖励冒烟测试：验证卡牌入账后直接提交房间，不生成或发放战利品。
extends SceneTree

const REWARD_SCENE := preload("res://scenes/reward_screen.tscn")
const MAP_STATE := preload("res://scripts/map/map_state.gd")

var _failed := false


# 延迟到视口和 Autoload 就绪后，通过真实奖励界面执行一次小怪结算。
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var save_service: Node = root.get_node("SaveService")
	var previous_save_path: String = str(save_service.save_path)
	var test_save_path := "res://tests/.smoke_normal_reward_save_%d.json" % OS.get_process_id()
	save_service.save_path = test_save_path
	var run_state: Node = root.get_node("RunState")
	run_state.start_new_run(1601)
	var room: Dictionary = run_state.map_state.rooms_on_layer(1)[0]
	_assert_true(room.type != MAP_STATE.RoomType.BOSS, "测试房间为非 Boss 战斗")
	run_state.map_state.begin_room(room.id)
	var initial_deck_size: int = run_state.deck_card_ids.size()
	var initial_item_count: int = run_state.owned_item_ids.size()
	var screen := REWARD_SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	_assert_true(not screen.item_step.visible, "小怪奖励页隐藏战利品步骤")
	screen._on_choice_pressed(0)
	screen._on_confirm_pressed()
	await create_timer(screen.REWARD_FLY_DURATION + 0.2).timeout
	_assert_equal(run_state.deck_card_ids.size(), initial_deck_size + 1, "小怪胜利发放一张卡牌")
	_assert_equal(run_state.owned_item_ids.size(), initial_item_count, "小怪胜利不发放战利品")
	_assert_equal(run_state.battles_won, 1, "卡牌领取后直接推进胜场")
	_assert_equal(room.state, MAP_STATE.RoomState.VISITED, "卡牌领取后直接完成房间")
	_assert_equal(run_state.map_state.current_room_id, "", "单步奖励完成后清除进行中房间")
	save_service.save_path = previous_save_path
	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))
	if is_instance_valid(screen):
		screen.free()
	if _failed:
		quit(1)
		return
	print("smoke_normal_card_only_reward: PASS")
	quit()


# 通用相等断言，保留期望值与实际值便于定位奖励边界。
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
