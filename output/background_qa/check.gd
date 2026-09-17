# 舞台背景临时验收：真实场景渲染、宽屏边界及空纹理恢复，不修改存档。
extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(360, 640)
	var screen = load("res://scenes/battle.tscn").instantiate()
	root.add_child(screen)
	await create_timer(2.0).timeout
	var bg: TextureRect = screen.get_node("Background")
	assert(bg.texture.resource_path == "res://assets/ui/backgrounds/battle_stage_background_v1.png")
	assert(bg.texture.get_size() == Vector2(941, 1672))
	assert(bg.size == Vector2(360, 640))
	assert(bg.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/background_qa/battle_360x640.png")
	root.size = Vector2i(480, 640)
	await process_frame
	await process_frame
	assert(bg.size == Vector2(480, 640))
	assert(bg.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/background_qa/battle_480x640.png")
	# 缺失纹理不应阻断战斗；恢复后保持相同引用。
	var original = bg.texture
	bg.texture = null
	await process_frame
	assert(is_instance_valid(screen.controller))
	bg.texture = original
	assert(bg.texture != null)
	print("background_qa: PASS")
	quit()
