# 第一章真实场景验收：地图选择与数字缓存、旧存档迁移、长意图布局和延迟命中后的实时打断显示。
extends SceneTree

const SCENE := preload("res://scenes/battle.tscn")
const CATALOG := preload("res://data/enemies/enemy_catalog.tres")
const GROUP := preload("res://data/cards/card_shot_group.tres")
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var run := root.get_node("RunState")
	run.start_new_run(918)
	var screen := SCENE.instantiate()
	root.add_child(screen)
	var limit := Time.get_ticks_msec() + 5000
	while screen.controller.phase == screen.controller.Phase.NOT_STARTED and Time.get_ticks_msec() < limit:
		await process_frame
	_check(screen.controller.phase == screen.controller.Phase.PLAYER_TURN, "真实场景完成初始化")
	var room: Dictionary = run.map_state.rooms_on_layer(1)[0]
	var selected: Resource = screen._select_room_enemy(room)
	_check(selected.id in [6001, 6002, 6003], "地图普通房选择新版小怪")
	_check(run.map_state.get_enemy_id(room.id) == str(selected.id), "正式缓存使用数字字符串")
	_check(screen._select_room_enemy(room).id == selected.id, "重进房间不重掷")
	run.map_state.set_enemy_id(room.id, "enemy_turtle")
	_check(screen._select_room_enemy(room).id == 6110 and run.map_state.get_enemy_id(room.id) == "6110", "真实战斗入口迁移旧缓存")
	run.map_state.set_enemy_id(room.id, "65535")
	_check(screen._select_room_enemy(room) != null, "无效缓存安全回退")
	# 逐个实例化第一章定义，验证真实显示生命和行为意图。
	for definition in CATALOG.enemies:
		if definition.chapter != 1:
			continue
		screen.start_new_battle(definition)
		await process_frame
		_check(screen.controller.enemy.max_health == definition.max_health, "真实场景生命来自配表")
		# 第一章普通小怪分别读取7001～7003；精英与Boss尚未配置时继续安全回退占位图。
		if definition.id in [6001, 6002, 6003]:
			var expected_image_id: int = 7000 + int(definition.id) - 6000
			_check(screen.enemy_display.portrait.texture.resource_path.ends_with("/%d.png" % expected_image_id), "%s读取配表图片" % definition.display_name)
			_check(screen.enemy_display.portrait.modulate == Color.WHITE, "%s的正式怪物图片保持原色" % definition.display_name)
		else:
			_check(screen.enemy_display.portrait.texture.resource_path.ends_with("/enemy_goalkeeper.png"), "未配置图片时回退占位图")
		_check(screen.monster_rules_label.visible, "新版行为完整意图可见")
		_check(screen.intent_label.get_global_rect().end.x <= 360.1, "顶栏意图不越界")
		_check(screen.monster_rules_label.get_global_rect().end.x <= screen.enemy_display.get_global_rect().position.x, "意图详情不覆盖敌方信息")
		_check(screen.monster_rules_label.get_line_count() * 17 <= screen.monster_rules_label.size.y, "意图详情行数可容纳")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/monster_%d.png" % definition.id)
		var state_turns := 2 if definition.id in [6001, 6011] else (3 if definition.id == 6021 else 1)
		for turn in range(state_turns):
			screen.controller.end_player_turn()
		await process_frame
		_check(screen.monster_rules_label.get_line_count() * 17 <= screen.monster_rules_label.size.y, "流血/格挡/反伤/蓄力组合文案可容纳")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/monster_%d_state.png" % definition.id)
	screen.start_new_battle(CATALOG.find_enemy(6011))
	screen.controller.end_player_turn()
	screen.controller.end_player_turn()
	screen._refresh_all()
	var events: Array[Dictionary] = []
	screen.controller.effect_resolved.connect(func(event: Dictionary) -> void:
		if event.get("deferred_damage", false):
			events.append(event)
	)
	# 测试只提交真实伤害核心，不启动飞球协程，避免人为手动命中与动画再次提交同一事件。
	screen.controller.effect_resolved.disconnect(screen._on_effect_resolved)
	screen.controller.play_card(GROUP, {}, true)
	_check("0/3" in screen.monster_rules_label.text, "出牌时未提前打断")
	for event in events:
		screen.controller.commit_deferred_damage(event)
	_check("已打断" in screen.monster_rules_label.text and "失衡冲撞" in screen.intent_label.text, "真实命中后界面立即更新替代行为")
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/monster_charge_interrupted.png")
	screen.free()
	await process_frame
	print("smoke_chapter_one_monster_ui: %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)
