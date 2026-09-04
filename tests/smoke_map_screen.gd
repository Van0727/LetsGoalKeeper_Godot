# 阶段 7 地图与休息房界面冒烟测试：验证三态按钮、整条路线走到 Boss、以及20点治疗。
extends SceneTree

const MAP_SCENE := preload("res://scenes/map_screen.tscn")
const REST_SCENE := preload("res://scenes/rest_room.tscn")
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")

var _failed := false
var run_state: Node


# 延迟执行并准备真实 Autoload 或本地兜底 RunState。
func _initialize() -> void:
	call_deferred("_run")


# 覆盖地图按钮状态、整局流转与休息房治疗边界。
func _run() -> void:
	root.size = Vector2i(360, 640)
	run_state = root.get_node_or_null("/root/RunState")
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		root.add_child(run_state)
	run_state.start_new_run(777)

	var map_screen := MAP_SCENE.instantiate()
	root.add_child(map_screen)
	await process_frame
	var state = run_state.map_state
	_assert_equal(map_screen.room_buttons.size(), state.rooms.size(), "地图为每个房间生成按钮")
	_assert_equal(_enabled_button_count(map_screen), state.get_attainable_rooms().size(), "只有可进房间可点击")
	_assert_true(not map_screen.completed_overlay.visible, "开局不显示完成层")

	# 完整走一遍：第1层任一房间 → 第2层任一房间 → Boss。
	var boss_id: String = state.rooms_on_layer(3)[0].id
	var layer1_first: Dictionary = state.rooms_on_layer(1)[0]
	state.enter_room(layer1_first.id)
	map_screen.refresh_ui()
	_assert_equal(_enabled_button_count(map_screen), state.rooms_on_layer(2).size(), "进入第1层后第2层解锁")
	_assert_true(map_screen.room_buttons[boss_id].disabled, "未进入第2层前Boss按钮不可用")
	_assert_true(not map_screen.completed_overlay.visible, "Boss未进入不显示完成层")

	var layer2_first: Dictionary = state.rooms_on_layer(2)[0]
	state.enter_room(layer2_first.id)
	map_screen.refresh_ui()
	_assert_true(not map_screen.room_buttons[boss_id].disabled, "进入第2层后Boss按钮可用")
	state.enter_room(state.rooms_on_layer(3)[0].id)
	map_screen.refresh_ui()
	_assert_true(map_screen.completed_overlay.visible, "Boss完成后地图显示本章完成")
	map_screen.free()

	# 休息房治疗：只能一次，且不能超过最大生命。
	run_state.start_new_run(778)
	run_state.player_hp = 70
	var rest_screen := REST_SCENE.instantiate()
	root.add_child(rest_screen)
	await process_frame
	_assert_equal(rest_screen.heal_button.text, "治疗 20 点", "休息房治疗按钮文案")
	rest_screen._on_heal_pressed()
	_assert_equal(run_state.player_hp, 90, "休息房恢复20点生命")
	_assert_true(rest_screen.heal_button.disabled, "治疗按钮只能使用一次")
	rest_screen._on_heal_pressed()
	_assert_equal(run_state.player_hp, 90, "第二次治疗不生效")
	rest_screen.free()

	if _failed:
		quit(1)
		return
	print("smoke_map_screen: PASS")
	quit()


# 统计当前启用（可进）的房间按钮数量。
func _enabled_button_count(map_screen) -> int:
	var count := 0
	for button in map_screen.room_buttons.values():
		if not button.disabled:
			count += 1
	return count


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
