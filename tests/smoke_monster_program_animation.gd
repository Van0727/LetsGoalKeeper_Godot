# 怪物程序动画冒烟测试：验证单图怪物的节奏律动、眨眼材质、攻击、受击、死亡和重置边界。
extends SceneTree

const DISPLAY_SCENE := preload("res://scenes/character_display.tscn")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var display := DISPLAY_SCENE.instantiate() as CharacterDisplay
	root.add_child(display)
	display.size = Vector2(213, 184)
	display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.ENEMY)
	display.configure("动画测试怪物", 20, Color.WHITE)
	display.set_enemy_image_id(7001)
	await process_frame

	_check(display.portrait.material is ShaderMaterial, "配置眼睛区域的怪物创建独立眨眼材质")
	display.play_rhythm_beat(0, 4)
	# 头部无窗口运行时按实际帧推进 Tween，避免无渲染负载下短计时器先于空闲 Tween 返回。
	for frame in range(8):
		await process_frame
	_check(display.portrait.offset_transform_scale != Vector2.ONE, "重拍触发节奏律动")
	await create_timer(0.34).timeout
	_check(display.portrait.offset_transform_position.is_equal_approx(Vector2.ZERO), "律动结束恢复位置")

	display.play_enemy_attack()
	await create_timer(0.16).timeout
	_check(display.portrait.offset_transform_position.y < 0.0, "敌方攻击完成蓄力后向前冲出")
	await create_timer(0.28).timeout
	_check(display.portrait.offset_transform_scale.is_equal_approx(Vector2.ONE), "攻击结束恢复缩放")

	# 自定义步进精确检查各球型的第一段受力，不依赖无窗口运行时的帧间隔。
	display.set_health(12)
	display.show_damage(2, 1, 0)
	(display.get("_motion_tween") as Tween).custom_step(0.06)
	_check(display.portrait.offset_transform_position.y < 0.0, "直球命中向上击退")
	display.reset_portrait_animation()

	display.show_damage(2, 2, -1)
	(display.get("_motion_tween") as Tween).custom_step(0.06)
	_check(display.portrait.offset_transform_position.x > 0.0, "左侧香蕉球命中向右后击退")
	display.reset_portrait_animation()

	display.show_damage(2, 2, 1)
	(display.get("_motion_tween") as Tween).custom_step(0.06)
	_check(display.portrait.offset_transform_position.x < 0.0, "右侧香蕉球命中向左后击退")
	display.reset_portrait_animation()

	display.show_damage(2, 3, 0)
	(display.get("_motion_tween") as Tween).custom_step(0.06)
	_check(display.portrait.offset_transform_scale.x > 1.0 and display.portrait.offset_transform_scale.y < 1.0, "挑射命中压扁怪物")
	display.reset_portrait_animation()

	display.show_damage(2)
	(display.get("_motion_tween") as Tween).custom_step(0.04)
	_check(absf(display.portrait.offset_transform_position.x) <= 2.5, "非射门伤害使用轻量通用反馈")
	display.reset_portrait_animation()

	display.set_health(0)
	display.show_damage(12, 1, 0)
	await create_timer(0.20).timeout
	_check(display.portrait.modulate.a < 1.0, "生命归零触发下沉淡出")
	display.configure("下一只怪物", 20, Color.WHITE)
	_check(display.portrait.modulate == Color.WHITE, "切换战斗恢复头像颜色")
	_check(display.portrait.offset_transform_scale == Vector2.ONE, "切换战斗恢复头像变换")

	display.set_enemy_image_id(0)
	_check(display.portrait.material == null, "未配置眼睛区域的怪物安全关闭眨眼")
	display.queue_free()
	await process_frame
	print("smoke_monster_program_animation: %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)
