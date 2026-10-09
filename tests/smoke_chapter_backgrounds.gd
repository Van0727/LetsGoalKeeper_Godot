# 章节背景验收：覆盖三章地图/战斗往返、场景重建、未知章节和缺失素材回退；可选真实渲染截图。
extends SceneTree

const THEMES := preload("res://scripts/map/chapter_backgrounds.gd")
const RUN_STATE := preload("res://autoload/run_state.gd")
const OUTPUT := "res://_local_artifacts/chapter_backgrounds/verification"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var capture := "--capture" in OS.get_cmdline_user_args()
	if capture:
		assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK, "无法创建截图目录")
	root.size = Vector2i(360, 640)
	var state = root.get_node_or_null("RunState")
	var owns_state := state == null
	if owns_state:
		state = RUN_STATE.new()
		state.name = "RunState"
		root.add_child(state)
	state.start_new_run(8108)
	for chapter in [1, 2, 3]:
		state.chapter = chapter
		state._regenerate_map()
		# 同一章节按地图→战斗→地图重建场景，确认背景只读取当前章节。
		for view in ["map", "battle", "map"]:
			var screen = load("res://scenes/map_screen.tscn" if view == "map" else "res://scenes/battle.tscn").instantiate()
			root.add_child(screen)
			await process_frame
			if view == "battle":
				screen.start_new_battle(load("res://data/enemies/chapter_one/enemy_street_chicken.tres"))
				assert(screen.stage_lights.material.get_shader_parameter("light_color") == THEMES.get_light_color(chapter))
			else:
				screen.refresh_ui()
			var background: TextureRect = screen.get_node("Background/Stadium" if view == "map" else "Background")
			assert(background.texture == THEMES.get_texture(chapter, view == "map"))
			assert(background.size.x > 0 and background.size.y > 0)
			if capture:
				await process_frame
				await RenderingServer.frame_post_draw
				assert(root.get_texture().get_image().save_png(OUTPUT + "/chapter_%d_%s.png" % [chapter, view]) == OK)
			root.remove_child(screen)
			screen.free()
			await process_frame
	for chapter in [-1, 0, 4, 999]:
		assert(THEMES.get_texture(chapter, false) == THEMES.BATTLE_ORANGE)
		assert(THEMES.get_texture(chapter, true) == THEMES.MAP_ORANGE)
	assert(THEMES.load_or_fallback("res://_local_artifacts/not_a_background.png", THEMES.MAP_ORANGE) == THEMES.MAP_ORANGE)
	assert(THEMES.load_or_fallback("res://scripts/map/chapter_backgrounds.gd", THEMES.MAP_ORANGE) == THEMES.MAP_ORANGE)
	if owns_state:
		state.free()
	print("smoke_chapter_backgrounds: PASS | chapters=3 | map/battle/map | fallback")
	quit()
