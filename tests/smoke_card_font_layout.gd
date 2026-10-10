# 卡牌显示验收：检查中文覆盖、描述适配、类型底色与空插画回退。
extends SceneTree

const CARD_SCENE := preload("res://scenes/card_view.tscn")
const REWARD_SCRIPT := preload("res://scripts/rewards/reward_screen.gd")
var _failed := false


func _initialize() -> void:
	# 验收产物统一存入 Git 忽略目录；新检出项目也须能创建截图目录，失败即终止。
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_local_artifacts/output")) != OK:
		push_error("无法创建本地验收产物目录")
		quit(1)
		return
	call_deferred("_run")


# 使用真实卡面排版，避免只比较字号而遗漏实际折行后的裁切。
func _run() -> void:
	root.size = Vector2i(360, 640)
	var card = CARD_SCENE.instantiate()
	root.add_child(card)
	# 连续无空格文本模拟导出端无法识别词边界：必须折行，不能靠缩成一行通过尺寸检查。
	var unbroken = load("res://data/cards/card_attack_and_defend.tres").duplicate()
	unbroken.description = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	card.configure(unbroken, 0)
	await process_frame
	await process_frame
	if card.description_label.get_line_count() < 2 or card.description_label.get_theme_font_size("normal_font_size") < 8:
		_failed = true
		push_error("无词边界长文未正常折行，或被过度缩小")
	# 三类蒙版颜色、透明度及未知类别回退一致；底色层必须位于文字和插画下方且不拦截输入。
	for type_index in range(3):
		var expected: Color = [Color(1.0, 0.45, 0.08, 0.18), Color(0.15, 0.55, 1.0, 0.18), Color(0.15, 0.85, 0.4, 0.18)][type_index]
		if not card._get_card_type_tint(type_index).is_equal_approx(expected):
			_failed = true
			push_error("类型蒙版颜色不匹配")
	var tint: Panel = card.get_node("Canvas/TypeTint")
	if tint.get_index() != 0 or tint.mouse_filter != Control.MOUSE_FILTER_IGNORE or not card._get_card_type_tint(-1).is_equal_approx(card._get_card_type_tint(2)):
		_failed = true
		push_error("类型蒙版层级、输入或未知类别回退错误")
	# 奖励页使用独立的字体副本，需验证同一批长规则在两条渲染路径下均不越界。
	var reward_fonts := REWARD_SCRIPT.new()
	var normal_font: Font = card.description_label.get_theme_font("normal_font")
	var reward_font := reward_fonts._copy_reward_font(normal_font)
	var count := 0
	for filename in DirAccess.get_files_at("res://data/cards"):
		if not filename.ends_with(".tres"):
			continue
		var definition = load("res://data/cards/" + filename)
		for font in [normal_font, reward_font]:
			card.description_label.add_theme_font_override("normal_font", font)
			card.configure(definition, 0)
			if not card._type_tint_style.bg_color.is_equal_approx(card._get_card_type_tint(definition.card_type)):
				_failed = true
				push_error("复用卡牌时未同步类型底色")
			await process_frame
			await process_frame
			var label: RichTextLabel = card.description_label
			if label.get_theme_font_size("normal_font_size") > 10 or label.get_theme_font_size("normal_font_size") < 1:
				_failed = true
				push_error("%s 说明字号超出有效范围" % filename)
			if label.get_content_height() > label.size.y + 0.5:
				_failed = true
				push_error("%s 说明被裁切：内容 %s / 槽高 %s" % [filename, label.get_content_height(), label.size.y])
		count += 1
	# 人工超长描述必须缩小且不裁切；复用控件显示短文、空文时恢复默认字号。
	var sample = load("res://data/cards/card_attack_and_defend.tres").duplicate()
	for content in ["获得5点护盾；下一次受到伤害时反击。".repeat(8), "获得5点护盾", ""]:
		sample.description = content
		card.configure(sample, 0)
		await process_frame
		await process_frame
		var label: RichTextLabel = card.description_label
		if label.get_content_height() > label.size.y or label.get_content_width() > label.size.x:
			_failed = true
			push_error("长文、短文或空文边界发生裁切")
		if (content.length() > 30 and label.get_theme_font_size("normal_font_size") >= 10) or (content.length() <= 30 and label.get_theme_font_size("normal_font_size") != 10):
			_failed = true
			push_error("描述字号未按内容缩小或恢复")
	# 零尺寸时安全跳过；恢复有效尺寸后 resized 必须重新适配。
	card.description_label.size = Vector2.ZERO
	card._fit_description_font()
	card.description_label.size = Vector2(88, 41)
	# 缺少插画仍能显示文字，说明字体必须随包包含中文。
	card._apply_illustration(null)
	if card.illustration_rect.visible or not card.description_label.get_theme_font("normal_font").has_char("护".unicode_at(0)):
		_failed = true
		push_error("空插画或中文字体回退检查失败")
	card.free()
	reward_fonts.free()
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_comparison()
	if not _failed:
		print("smoke_card_font_layout: PASS (%d cards)" % count)
	quit(1 if _failed else 0)


# 同字号、字重、卡面与缩放下对比两种渲染，不把缩小字号伪装成清晰度提升。
func _capture_comparison() -> void:
	# 使用独立视口，避免桌面工作区宽度限制截断三列预览。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 660)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Control.new()
	viewport.add_child(stage)
	var background := ColorRect.new()
	background.color = Color("101923")
	background.size = Vector2(720, 660)
	stage.add_child(background)
	var paths := ["card_straight_shot", "card_carnival_beat", "card_shot_group"]
	for row in range(2):
		var caption := Label.new()
		caption.text = "MSDF（原渲染）" if row == 0 else "栅格 + Hinting（调整后）"
		caption.position = Vector2(24, 10 + row * 330)
		caption.add_theme_font_size_override("font_size", 20)
		stage.add_child(caption)
		for column in range(paths.size()):
			var preview = CARD_SCENE.instantiate()
			stage.add_child(preview)
			preview.position = Vector2(50 + column * 230, 50 + row * 330)
			preview.scale = Vector2(1.5, 1.5)
			preview.configure(load("res://data/cards/%s.tres" % paths[column]), 0)
			for label in [preview.name_label, preview.description_label]:
				var key := "normal_font" if label is RichTextLabel else "font"
				var font := label.get_theme_font(key).duplicate() as FontVariation
				font.base_font = font.base_font.duplicate() as Font
				font.base_font.set("multichannel_signed_distance_field", row == 0)
				font.base_font.set("msdf_size", 96)
				font.base_font.set("oversampling", 2.0)
				font.base_font.set("hinting", TextServer.HINTING_NORMAL)
				font.base_font.set("force_autohinter", true)
				label.add_theme_font_override(key, font)
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := viewport.get_texture().get_image()
	if screenshot.save_png("res://_local_artifacts/output/font_render_comparison.png") != OK:
		_failed = true
		push_error("字体对比截图保存失败")
	viewport.free()
