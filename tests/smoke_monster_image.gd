# 怪物图片接入验收：检查配表图片 ID、编辑器预览、真实战斗头像及缺图回退。
extends SceneTree

const SCENE := preload("res://scenes/battle.tscn")
const CATALOG := preload("res://data/enemies/enemy_catalog.tres")
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(360, 640)
	var chicken: Resource = CATALOG.find_enemy(6001)
	_check(chicken != null and chicken.image_id == 7001, "鸡的配表图片 ID 已导入")
	var texture := ResourceLoader.load("res://assets/ui/enemies/7001.png", "Texture2D") as Texture2D
	_check(texture != null, "正式怪物图片可加载")
	if texture != null:
		_check(texture.get_size() == Vector2(512, 512), "游戏用图片缩至512方形")
		_check(texture.get_image().get_pixel(0, 0).a < 0.01, "图片背景已透明")
	var screen := SCENE.instantiate()
	var preview: TextureRect = screen.get_node("EnemyDisplay/Margin/Content/Portrait")
	_check(preview.texture.resource_path.ends_with("/7001.png"), "战斗场景编辑器预览使用真实图片")
	_check(preview.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "怪物头像使用线性mipmap过滤")
	_check(preview.custom_minimum_size == Vector2.ZERO and preview.expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "编辑器预览头像不锁定尺寸")
	_check(screen.get_node("EnemyDisplay").custom_minimum_size == Vector2.ZERO, "编辑器预览显示框可缩放")
	_check(not screen.get_node("EnemyDisplay/Margin/Content/NameLabel").visible, "编辑器预览不显示旧名称布局")
	root.add_child(screen)
	await process_frame
	screen.start_new_battle(chicken)
	await process_frame
	_check(screen.enemy_display.portrait.texture == texture, "战斗只显示鸡的对应图片")
	_check(screen.enemy_display.portrait.modulate == Color.WHITE, "正式图片不叠加染色")
	var portrait_size: Vector2 = screen.enemy_display.portrait.get_global_rect().size
	_check(portrait_size.x > 0 and portrait_size.y > 0, "战斗图片显示区有尺寸")
	# 截图先记录玩家在场景中保存的尺寸和位置，再单独验证可缩放行为。
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png("res://.godot/monster_image_chicken.png") == OK, "真实战斗截图保存成功")
	# 用户在场景中拖大 EnemyDisplay 后，头像宽高必须跟随变化。
	screen.enemy_display.size += Vector2(42, 28)
	await process_frame
	var resized_size: Vector2 = screen.enemy_display.portrait.get_global_rect().size
	_check(resized_size.x > portrait_size.x and resized_size.y > portrait_size.y, "怪物图片随显示框缩放")
	var turtle: Resource = CATALOG.find_enemy(6002)
	screen.start_new_battle(turtle)
	await process_frame
	_check(screen.enemy_display.portrait.texture.resource_path.ends_with("/enemy_goalkeeper.png"), "未配置图片使用占位图")
	screen.enemy_display.set_enemy_image_id(65535)
	_check(screen.enemy_display.portrait.texture.resource_path.ends_with("/enemy_goalkeeper.png"), "缺失图片安全回退")
	print("smoke_monster_image: %s; portrait=%s" % ["FAIL" if _failed else "PASS", portrait_size])
	screen.free()
	await process_frame
	quit(1 if _failed else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		push_error(label)
