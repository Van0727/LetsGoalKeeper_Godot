# 地图视觉验收：名称无写入、七层透视与宽屏边界、资源回退、暂停和无地图失败路径。
extends SceneTree

const SCENE := preload("res://scenes/map_screen.tscn")
const GENERATOR := preload("res://scripts/map/map_generator.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(360,640)
	var run = root.get_node("RunState")
	run.start_new_run(777)
	var screen = SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	check(not screen.info_label.visible, "底部状态信息应隐藏")
	var pool: Resource = load("res://data/encounters/chapter_1.tres")
	for room in run.map_state.rooms:
		var button = screen.room_buttons[room.id]
		check(room.enemy_id.is_empty(), "名称预览不能提前写入敌人缓存")
		if room.type != 3:
			var rng := RandomNumberGenerator.new()
			rng.seed = run.seed + room.layer * 1000 + room.index * 100 + 17
			check(button.title_label.text == pool.pick_enemy(room.type,rng).display_name, "地图名称应与战斗敌人一致")
		check(button.position.x >= 0 and button.position.y >= 0, "节点不得越出地图上边界")
	var first: Dictionary = run.map_state.rooms_on_layer(1)[0]
	var boss: Dictionary = run.map_state.rooms_on_layer(run.map_state.layer_count)[0]
	check(screen.room_buttons[first.id].position.y > screen.room_buttons[boss.id].position.y, "路线应由底部向上")
	var pause = screen.get_node("PauseOverlay")
	pause.open_pause()
	check(paused and pause.pause_panel.visible, "暂停入口应工作")
	pause.close_pause()
	check(not paused, "继续应解除暂停")
	# 构造七层合法配置只用于测试，不修改正式章节资源或存档。
	var config: Resource = load("res://data/maps/map_chapter_1.tres").duplicate()
	config.layer_min_rooms.assign([1,2,1,2,1,2,1])
	config.layer_max_rooms.assign([1,2,1,2,1,2,1])
	config.elite_chance_by_layer.assign([0.0,0.0,0.0,0.0,0.0,1.0,0.0])
	config.rest_count_by_layer.assign([0,0,0,0,0,0,0])
	config.max_random_rest_rooms = 0
	config.eligible_rest_layers.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	run.map_state = GENERATOR.new().generate(config,rng)
	screen.refresh_ui()
	await process_frame
	await process_frame
	check(screen.room_buttons.size() == 10, "七层应完整显示10个节点")
	_check_perspective(screen, run.map_state)
	root.size = Vector2i(480,640)
	await process_frame
	await process_frame
	_check_perspective(screen, run.map_state)
	for button in screen.room_buttons.values():
		check(button.position.x + button.size.x <= screen.rows_container.size.x, "宽屏节点不得越界")
	root.size = Vector2i(360,640)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/map-seven-rows.png")
		run.start_new_run(777)
		screen.refresh_ui()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://output/map-current.png")
	# 缺失底板可安全绘制，旧缓存无法加载时使用战斗的乌龟回退。
	var room: Dictionary = run.map_state.rooms[0]
	room.enemy_id = "missing_map_visual_enemy"
	check(screen._opponent_name(room) == "乌龟", "坏缓存应安全回退")
	var button = screen.room_buttons[room.id]
	button.art = {}
	button.queue_redraw()
	await process_frame
	run.map_state = null
	screen.refresh_ui()
	check(screen.missing_overlay.visible, "缺失地图应显示提示")
	screen.free()
	print("smoke_map_visual: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

# 同房型比较大小，避免Boss强调系数掩盖纵深缩放；完整按钮矩形即真实点击范围。
func _check_perspective(screen: Control, state: RefCounted) -> void:
	# 起点改为单节点，横向透视用第二层双节点比较；第一层仍用于尺寸与居中验收。
	var first: Button = screen.room_buttons[state.rooms_on_layer(1)[0].id]
	check(is_equal_approx(first.get_rect().get_center().x, screen.rows_container.size.x * 0.5), "底部单节点必须居中")
	var bottom: Array = state.rooms_on_layer(2)
	var upper: Array = state.rooms_on_layer(6)
	var bottom_left: Button = screen.room_buttons[bottom[0].id]
	var bottom_right: Button = screen.room_buttons[bottom[1].id]
	var upper_left: Button = screen.room_buttons[upper[0].id]
	var upper_right: Button = screen.room_buttons[upper[1].id]
	var bottom_width := bottom_right.get_rect().get_center().x - bottom_left.get_rect().get_center().x
	var upper_width := upper_right.get_rect().get_center().x - upper_left.get_rect().get_center().x
	check(bottom_width > upper_width, "底部双节点间距必须比顶部更宽")
	var far_normal: Button = screen.room_buttons[state.rooms_on_layer(5)[0].id]
	check(first.size.x > far_normal.size.x, "同房型远处节点和底板必须更小")
	for button in screen.room_buttons.values():
		check(button.position.x >= 0 and button.position.y >= 0, "透视后按钮不得越出左上边界")
		check(button.position.y + button.size.y <= screen.rows_container.size.y, "完整点击范围不得超出地图底边")
