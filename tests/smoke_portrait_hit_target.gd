# 怪物主体命中点回归：透明留白、等比居中、体型倍率、空图回退及真实Boss/普通怪飞球目标。
extends SceneTree
var _failed := false
func _initialize() -> void:
	call_deferred("_run")
func _check(value: bool, label: String) -> void:
	if not value:
		_failed = true
		push_error(label)
func _run() -> void:
	root.size = Vector2i(360, 640)
	var display := preload("res://scenes/character_display.tscn").instantiate() as CharacterDisplay
	root.add_child(display)
	await process_frame
	var image := Image.create(100, 100, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(20, 60, 60, 30), Color.WHITE)
	display.portrait.texture = ImageTexture.create_from_image(image)
	display._cache_portrait_body_center()
	display.portrait.size = Vector2(200, 100)
	display.portrait.pivot_offset_ratio = Vector2(0.5, 1.0)
	display.portrait.scale = Vector2(2.5, 2.5)
	var expected := display.portrait.get_global_transform() * Vector2(100, 75)
	_check(display.get_portrait_global_center().is_equal_approx(expected), "留白图在非正方形槽中等比居中且按2.5倍缩放命中主体")
	image.fill(Color.TRANSPARENT)
	display.portrait.texture = ImageTexture.create_from_image(image)
	display._cache_portrait_body_center()
	_check(display._portrait_body_center_ratio == Vector2(0.5, 0.5), "全透明图回退中心")
	display.portrait.texture = null
	display._cache_portrait_body_center()
	_check(display.get_portrait_global_center().is_equal_approx(display.portrait.get_global_transform() * (display.portrait.size * 0.5)), "空纹理回退中心")
	display.set_enemy_image_id(0)
	_check(display.portrait.texture != null, "无图片ID使用占位图")
	display.free()
	var screen := preload("res://scenes/battle.tscn").instantiate() as Control
	root.add_child(screen)
	var deadline := Time.get_ticks_msec() + 5000
	while screen._battle_generation == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	var catalog := preload("res://data/enemies/enemy_catalog.tres")
	for id in [6001, 6002, 6003, 6011, 6012, 6021]:
		screen.start_new_battle(catalog.find_enemy(id))
		await process_frame
		await process_frame
		var portrait: TextureRect = screen.enemy_display.portrait
		var target: Vector2 = screen.enemy_display.get_portrait_global_center()
		_check(target.y > 100.0 and target.y < 280.0, "怪物%d命中点位于舞台身体区域" % id)
		if id == 6021:
			_check(target.y > portrait.get_global_rect().get_center().y + 50.0, "Boss命中点避开上半张透明留白")
		# 真实飞球入口连续发射三个球，检查终点统一绑定主体而非透明画布中心。
		for shot_type in [1, 2, 3]:
			var state := {"finished": false}
			screen.ball_flight.playback_speed = 1000.0
			screen._play_shot_visual(screen.ball_flight, {"shot_type": shot_type}, 0.1, -1.0, -1.0, state)
			_check(screen.ball_flight._end_position.is_equal_approx(target), "怪物%d球型%d目标绑定主体" % [id, shot_type])
			while not state.finished:
				await process_frame
		if "--capture" in OS.get_cmdline_user_args() and id == 6021:
			var output := "res://_local_artifacts/boss_hit"
			_check(DirAccess.make_dir_recursive_absolute(output) == OK, "创建命中截图目录")
			screen.ball_flight.visible = true
			screen.ball_flight.global_position = target
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(output + "/boss_hit.png") == OK, "保存Boss命中点截图")
	screen.free()
	await process_frame
	print("smoke_portrait_hit_target: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
