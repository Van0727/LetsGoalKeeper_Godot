# 奖励界面冒烟测试：覆盖高清类型标签、MSDF 字体隔离、原卡尺寸及动画后发奖流程。
extends SceneTree

const REWARD_SCENE := preload("res://scenes/reward_screen.tscn")
const MAP_STATE := preload("res://scripts/map/map_state.gd")

var _failed := false


# 延迟执行以等待根视口初始化。
func _initialize() -> void:
	call_deferred("_run")


# 使用奖励真实场景完成两步选择，并检查其局部 RunState 变化。
func _run() -> void:
	root.size = Vector2i(360, 640)
	# 奖励场景使用 Autoload；先隔离存档路径并建立新局，避免读取或覆盖玩家正式进度。
	var save_service: Node = root.get_node("SaveService")
	var previous_save_path: String = str(save_service.save_path)
	var test_save_path := "res://tests/.smoke_reward_save_%d.json" % OS.get_process_id()
	save_service.save_path = test_save_path
	root.get_node("RunState").start_new_run(601)
	var screen := REWARD_SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	_assert_equal(screen.phase, screen.Phase.CARD, "奖励先进入卡牌步骤")
	_assert_equal(screen.card_step.modulate, Color.WHITE, "卡牌步骤使用高亮进度胶囊")
	_assert_true(screen.item_step.modulate != Color.WHITE, "未到达的战利品步骤保持降亮")
	_assert_equal(screen.choices.size(), 3, "显示三张卡牌候选")
	_assert_equal(screen.card_views[0].card_definition, screen.choices[0], "奖励卡牌复用战斗卡面并绑定候选定义")
	await process_frame
	for card_view in screen.card_views:
		_assert_equal(card_view.size, Vector2(104, 176), "奖励卡面与原卡尺寸一致")
		_assert_true(card_view.description_label.get_rect().end.y <= card_view.size.y, "卡牌说明位于卡面范围内")
	# 三类标签及未知类别回退必须使用统一高清尺寸，槽位仍保留原来的 50×13。
	var badge_view: BattleCardView = screen.card_views[0]
	for category in [0, 1, 2, -1]:
		var badge_texture: Texture2D = badge_view._get_card_type_badge(category)
		_assert_equal(badge_texture.get_size(), Vector2(200, 52), "类型标签统一 200×52 导入尺寸")
		if "--capture" in OS.get_cmdline_user_args():
			_assert_equal(badge_texture.get_image().save_png("res://output/badge_%d.png" % category), OK, "保存标签回读预览")
	_assert_equal(badge_view._get_card_type_badge(-1), badge_view.SKILL_BADGE, "未知类别安全回退技能标签")
	_assert_equal(badge_view.category_badge.size, Vector2(50, 13), "类型标签显示槽保持不变")
	_assert_equal(badge_view.category_badge.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "高清标签采用线性过滤")
	await _capture("cards", screen)
	_assert_equal(ThemeDB.fallback_font.get("oversampling"), 0.0, "奖励字体不修改全局默认字体")
	var reward_font: Font = screen.card_views[0].description_label.get_theme_font("font")
	_assert_equal(reward_font.get("multichannel_signed_distance_field"), true, "卡牌说明使用距离场字体")
	var cost_font := screen.card_views[0].cost_label.get_theme_font("font") as FontVariation
	_assert_true(is_equal_approx(cost_font.variation_embolden, 1.2), "费用字体保留原有加粗")
	_assert_equal(cost_font.base_font.get("oversampling"), 2.0, "模拟加粗费用使用高采样栅格避免轮廓缺色")
	_assert_equal(screen.item_description_labels[0].get_theme_font("font"), reward_font, "战利品与卡牌共享本页MSDF 字体")
	var map_state = screen.run_state.map_state
	var active_room: Dictionary = map_state.rooms_on_layer(1)[0]
	var connected_room: Dictionary = map_state.room_by_id(active_room.connections[0])
	map_state.begin_room(active_room.id)
	var initial_deck_size: int = screen.run_state.deck_card_ids.size()
	screen._on_confirm_pressed()
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size, "未预选时确认不会发放卡牌")
	screen._on_choice_pressed(0)
	_assert_true(screen.selection_rings[0].visible, "预选卡牌显示金色选择框")
	_assert_true(not screen.selection_rings[1].visible, "未选卡牌不显示选择框")
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size, "预选卡牌时不立即加入牌库")
	_assert_equal(
		screen.choice_buttons[0].pivot_offset,
		Vector2(0.0, screen.choice_buttons[0].size.y * 0.5),
		"左侧卡牌使用左侧中心锚点"
	)
	_assert_equal(screen.choice_buttons[0].pivot_offset_ratio, Vector2.ZERO, "左侧卡牌不叠加比例锚点")
	await create_timer(screen.SELECT_SCALE_DURATION + 0.05).timeout
	_assert_equal(screen.choice_buttons[0].scale, Vector2(1.5, 1.5), "预选卡牌缓动放大至1.5倍")
	await _capture("selected_card", screen)
	# 真实渲染模式逐类验收放大标签，结束后还原候选，避免视觉验收改变正式发奖内容。
	if "--capture" in OS.get_cmdline_user_args():
		var badge_preview: Resource = screen.choices[0].duplicate(true)
		for category in [0, 1, 2]:
			badge_preview.card_type = category
			badge_view.configure(badge_preview, 0)
			await _capture("selected_badge_%d" % category, screen)
		badge_view.configure(screen.choices[0], 0)
	_assert_equal(screen.phase, screen.Phase.CARD, "预选卡牌后停留在卡牌步骤")
	screen._on_choice_pressed(2)
	_assert_equal(
		screen.choice_buttons[2].pivot_offset,
		Vector2(screen.choice_buttons[2].size.x, screen.choice_buttons[2].size.y * 0.5),
		"右侧卡牌使用右侧中心锚点"
	)
	_assert_equal(screen.choice_buttons[2].pivot_offset_ratio, Vector2.ZERO, "右侧卡牌不叠加比例锚点")
	await create_timer(screen.SELECT_SCALE_DURATION + 0.05).timeout
	_assert_equal(screen.choice_buttons[0].scale, Vector2.ONE, "取消选中后旧卡牌缓动缩回原尺寸")
	_assert_equal(screen.choice_buttons[2].scale, Vector2(1.5, 1.5), "右侧卡牌缓动放大至1.5倍")
	screen._on_choice_pressed(1)
	_assert_equal(
		screen.choice_buttons[1].pivot_offset,
		screen.choice_buttons[1].size * 0.5,
		"中间卡牌使用几何中心锚点"
	)
	_assert_equal(screen.choice_buttons[1].pivot_offset_ratio, Vector2.ZERO, "中间卡牌不叠加比例锚点")
	await create_timer(screen.SELECT_SCALE_DURATION + 0.05).timeout
	_assert_equal(screen.choice_buttons[2].scale, Vector2.ONE, "再次切换后右侧卡牌缓动缩回")
	_assert_equal(screen.choice_buttons[1].scale, Vector2(1.5, 1.5), "中间卡牌缓动放大至1.5倍")
	var card_start_y: float = screen.choice_buttons[1].global_position.y
	var left_card_position: Vector2 = screen.choice_buttons[0].global_position
	var right_card_position: Vector2 = screen.choice_buttons[2].global_position
	var selected_card_transform: Transform2D = screen.choice_buttons[1].get_global_transform()
	screen._on_confirm_pressed()
	_assert_equal(screen.confirm_button.self_modulate.a, 0.0, "卡牌确认后确认按钮视觉隐藏")
	_assert_equal(screen.choice_buttons[1].modulate.a, 0.0, "飞出副本出现后原位置卡牌完全移除")
	var flying_card_at_start := screen.get_node_or_null("FlyingReward") as Control
	_assert_equal(flying_card_at_start.get_global_transform(), selected_card_transform, "动画起点对齐点击放大后的完整变换")
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size, "飞出动画结束前不发放卡牌")
	await process_frame
	_assert_equal(screen.choice_buttons[0].global_position, left_card_position, "获得动画期间左侧卡牌不重排")
	_assert_equal(screen.choice_buttons[2].global_position, right_card_position, "获得动画期间右侧卡牌不重排")
	await create_timer(screen.REWARD_RISE_DURATION * 0.75).timeout
	var flying_card := screen.get_node_or_null("FlyingReward") as Control
	_assert_true(flying_card != null and flying_card.global_position.y < card_start_y, "卡牌获得动画先向上抬升")
	await create_timer(screen.REWARD_FLY_DURATION + 0.1).timeout
	_assert_equal(screen.run_state.deck_card_ids.size(), initial_deck_size + 1, "确认后卡牌加入牌库")
	_assert_equal(screen.phase, screen.Phase.ITEM, "卡牌后进入战利品步骤")
	_assert_true(screen.card_step.modulate != Color.WHITE, "已完成的卡牌步骤降亮")
	_assert_equal(screen.item_step.modulate, Color.WHITE, "战利品步骤切换为高亮")
	_assert_equal(screen.confirm_button.self_modulate.a, 1.0, "进入遗物步骤后重新显示确认按钮")
	_assert_equal(screen.choices.size(), 3, "普通战显示三件战利品候选")
	# 遗物描述必须在固定的三等分槽位内换行，不能因长文本挤宽整个奖励行。
	for index in range(screen.choice_buttons.size()):
		var button: Button = screen.choice_buttons[index]
		_assert_equal(button.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "遗物按钮启用智能换行")
		_assert_true(button.clip_text, "遗物按钮限制文本最小宽度")
		_assert_equal(button.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "遗物按钮均分奖励行宽度")
		_assert_true(screen.item_contents[index].visible, "遗物阶段显示图标与文字容器")
		_assert_true(screen.item_icons[index].texture != null, "遗物阶段分配纯色占位图片")
		# 占位图和长文字必须受卡片槽位约束，不能按源图尺寸或内容高度撑破三选一布局。
		_assert_equal(screen.item_icons[index].expand_mode, TextureRect.EXPAND_IGNORE_SIZE, "遗物图标忽略原图尺寸")
		_assert_equal(screen.item_icons[index].custom_minimum_size, Vector2(80, 48), "遗物图标使用固定小尺寸")
		_assert_equal(screen.item_name_labels[index].max_lines_visible, 2, "遗物名称最多显示两行")
		_assert_equal(screen.item_description_labels[index].max_lines_visible, 6, "遗物槽增加至六行摘要")
		_assert_equal(screen.item_name_labels[index].text, screen.choices[index].display_name, "遗物名称由独立标签显示")
		_assert_equal(screen.item_description_labels[index].text, screen.choices[index].description, "遗物描述由独立标签自动换行")
	_assert_equal(active_room.state, MAP_STATE.RoomState.ATTAINABLE, "只领取卡牌时房间尚未完成")
	_assert_equal(connected_room.state, MAP_STATE.RoomState.LOCKED, "奖励未完成时下一层保持锁定")
	# 奖励池耗尽应保留继续入口并隐藏空槽，不展示上一阶段的说明。
	for item in screen._service.get_all_items():
		screen.run_state.owned_item_ids.append(item.id)
	screen._show_item_choices()
	_assert_true(screen.choices.is_empty(), "已拥有全部战利品时奖励池为空")
	_assert_true(not screen.confirm_button.disabled, "池耗尽允许继续")
	for button in screen.choice_buttons:
		_assert_true(not button.visible, "池耗尽隐藏候选槽")
	screen.run_state.owned_item_ids.clear()
	screen._show_item_choices()
	await process_frame
	await process_frame
	for label in screen.item_description_labels:
		_assert_true(label.size.y >= 72, "战利品描述预留六行摘要高度")
		_assert_true(label.get_rect().end.y <= label.get_parent().size.y, "战利品描述位于可见容器范围")
	await _capture("items", screen)
	# 使用独立副本验证长文本和空文本，避免修改共享正式物品资源。
	var original_item: Resource = screen.choices[0]
	var test_item: Resource = original_item.duplicate(true)
	test_item.description = "完整说明边界测试：".repeat(40)
	screen.choices[0] = test_item
	screen._on_choice_pressed(0)
	_assert_equal(screen.reward_detail.text, "%s\n%s" % [test_item.display_name, test_item.description], "详情保留全部长描述")
	_assert_true(screen.reward_detail.scroll_active, "长说明可滚动阅读")
	test_item.description = ""
	screen._on_choice_pressed(0)
	_assert_true(screen.reward_detail.text.ends_with("暂无效果说明"), "空说明有明确回退")
	screen.choices[0] = original_item
	screen._on_choice_pressed(0)
	_assert_equal(screen.reward_detail.text, "%s\n%s" % [original_item.display_name, original_item.description], "切换选择刷新完整说明")
	await create_timer(screen.SELECT_SCALE_DURATION + 0.05).timeout
	await _capture("selected_item", screen)
	_assert_equal(screen.run_state.owned_item_ids.size(), 0, "预选遗物时不立即加入本局")
	await create_timer(screen.SELECT_SCALE_DURATION + 0.05).timeout
	_assert_equal(screen.choice_buttons[0].scale, Vector2(1.5, 1.5), "预选遗物放大1.5倍")
	screen._on_confirm_pressed()
	_assert_equal(screen.confirm_button.self_modulate.a, 0.0, "遗物确认后确认按钮视觉隐藏")
	_assert_equal(screen.run_state.owned_item_ids.size(), 0, "飞出动画结束前不发放遗物")
	await create_timer(screen.REWARD_FLY_DURATION + 0.1).timeout
	_assert_equal(screen.run_state.owned_item_ids.size(), 1, "确认后遗物加入本局")
	_assert_equal(screen.run_state.battles_won, 1, "两步奖励后推进胜场")
	_assert_equal(active_room.state, MAP_STATE.RoomState.VISITED, "两项奖励后房间标记完成")
	_assert_equal(connected_room.state, MAP_STATE.RoomState.ATTAINABLE, "两项奖励后解锁连线房间")
	_assert_equal(map_state.current_room_id, "", "奖励完成后清除进行中房间")
	save_service.save_path = previous_save_path
	if FileAccess.file_exists(test_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_save_path))
	if is_instance_valid(screen):
		screen.free()

	if _failed:
		quit(1)
		return
	print("smoke_reward_screen: PASS")
	quit()


# 可选真实渲染验收：仅在显式传入 --capture 时保存场景截图，无头逻辑测试不读取空纹理。
func _capture(stage: String, screen: Control) -> void:
	if not _capture_requested():
		return
	await RenderingServer.frame_post_draw
	var image := screen.get_viewport().get_texture().get_image()
	_assert_equal(image.save_png("res://output/reward_%s.png" % stage), OK, "奖励界面截图保存")


# 本地截图验收兼容直接参数与 `--` 后用户参数，避免不同 Godot 启动方式漏掉视觉检查。
func _capture_requested() -> bool:
	return "--capture" in OS.get_cmdline_args() or "--capture" in OS.get_cmdline_user_args()


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
