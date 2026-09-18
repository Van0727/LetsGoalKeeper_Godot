# 战斗界面冒烟测试：验证节拍入口、起手、结算锁、回合抽弃牌与胜负界面。
extends SceneTree

const BATTLE_SCENE := preload("res://scenes/battle.tscn")
const CARD_SCENE := preload("res://scenes/card_view.tscn")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")

var _failed := false


# 延迟执行以等待根视口初始化。
func _initialize() -> void:
	call_deferred("_run")


# 实例化真实战斗场景并覆盖阶段 3 的关键交互状态。
func _run() -> void:
	root.size = Vector2i(360, 640)
	var settings_service: Node = root.get_node("SettingsService")
	settings_service.set_metronome_style(settings_service.MetronomeStyle.WAVEFORM)
	var battle_screen := BATTLE_SCENE.instantiate()
	root.add_child(battle_screen)
	# _ready 会等待战斗转场音效；先等其首次建局完成，避免测试手动建局被迟到的初始化覆盖。
	_assert_true(await _wait_until_next_battle(battle_screen, 0, 2.0), "战斗界面异步初始化完成")
	# 显式重置本局，避免本机 user:// 残留存档让玩家以濒死状态进入冒烟测试。
	battle_screen.run_state.start_new_run(7301)
	battle_screen.start_new_battle(TURTLE)
	await process_frame
	# 冒烟测试保留真实动画链路但提高播放速度，避免按正式时长等待。
	battle_screen.ball_flight.playback_speed = 1000.0

	_assert_equal(battle_screen.deck_state.hand.size(), 3, "战斗开始抽三张")
	_assert_equal(battle_screen.hand_layer.get_child_count(), 3, "三张手牌均生成视图")
	_assert_true(
		not battle_screen.get_node("Pitch").get_theme_stylebox("panel") is StyleBoxTexture,
		"敌人区域不再使用遮挡球门的图片底图"
	)
	_assert_true(
		not battle_screen.enemy_display.get_theme_stylebox("panel") is StyleBoxTexture,
		"敌人信息保留头像和数值但不再使用图片面板"
	)
	# 单独实例化射门牌，验证圆角插画已经进入独立画框且不会依赖随机起手。
	var straight_shot_view = CARD_SCENE.instantiate()
	root.add_child(straight_shot_view)
	straight_shot_view.configure(STRAIGHT_SHOT, 0)
	await process_frame
	_assert_true(
		straight_shot_view.illustration_rect.texture == STRAIGHT_SHOT.illustration,
		"射门牌在固定画框中使用专属圆角插画"
	)
	# 卡面允许设计人员在编辑器调整插画槽；验收边界而非锁死旧版像素尺寸。
	_assert_true(
		Rect2(Vector2.ZERO, straight_shot_view.size).encloses(straight_shot_view.illustration_rect.get_rect()),
		"插画槽完整位于卡面边界内"
	)
	_assert_equal(straight_shot_view.size, Vector2(104, 176), "卡牌按参考图使用紧凑的信息区")
	_assert_true(straight_shot_view.editor_preview_definition != null, "卡牌场景保留编辑器预览数据入口")
	_assert_true(not straight_shot_view.editor_reference.visible, "运行时隐藏仅编辑器使用的参考图层")
	_assert_true(straight_shot_view.category_badge.texture == straight_shot_view.ATTACK_BADGE, "攻击牌显示原图 ATTACK 徽章")
	_assert_equal(straight_shot_view.description_label.text, STRAIGHT_SHOT.description, "卡牌底部显示配置说明")
	_assert_equal(
		straight_shot_view._get_card_type_badge(CARD_DEFINITION.CardType.DEFENSE),
		straight_shot_view.DEFENSE_BADGE,
		"防御牌使用独立类别图标"
	)
	_assert_equal(
		straight_shot_view._get_card_type_badge(CARD_DEFINITION.CardType.ABILITY),
		straight_shot_view.SKILL_BADGE,
		"能力牌使用独立类别图标"
	)
	straight_shot_view.queue_free()
	_assert_equal(battle_screen.controller.player.energy, 3, "玩家初始能量")
	_assert_equal(battle_screen.rhythm_clock.bpm, 100.0, "战斗使用基础鼓点的100 BPM配置")
	_assert_true(battle_screen.rhythm_clock.music != null, "战斗已绑定基础鼓点BGM")
	_assert_true(
		battle_screen.rhythm_clock.music.resource_path.ends_with("bg_basicDrum2_bpm100.mp3"),
		"战斗绑定按命名约定标注100 BPM的新BGM"
	)
	_assert_true(battle_screen.rhythm_feedback.visible, "战斗显示节拍反馈控件")
	_assert_true(battle_screen.rhythm_waveform.visible, "战斗中央显示节奏波形")
	_assert_true(not battle_screen.rhythm_feedback._circle_enabled, "默认波形样式不绘制圆圈")
	settings_service.set_metronome_style(settings_service.MetronomeStyle.CIRCLE)
	_assert_true(not battle_screen.rhythm_waveform.visible, "圆圈样式隐藏波形")
	_assert_true(battle_screen.rhythm_feedback._circle_enabled, "圆圈样式启用圆环绘制")
	_assert_true(battle_screen.rhythm_feedback.size.x > 250.0, "放大圆圈控件覆盖中央主要宽度")
	_assert_true(
		absf(battle_screen.rhythm_feedback.get_global_rect().get_center().x - 180.0) < 1.0,
		"放大圆圈控件位于屏幕横向中央"
	)
	settings_service.set_metronome_style(settings_service.MetronomeStyle.WAVEFORM)
	_assert_true(battle_screen.rhythm_waveform.visible, "切回波形后恢复波形显示")
	_assert_true(not battle_screen.rhythm_feedback._circle_enabled, "切回波形后关闭圆环绘制")
	_assert_equal(
		battle_screen.rhythm_waveform.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"节奏波形不拦截卡牌输入"
	)
	_assert_true(battle_screen.rhythm_waveform.size.x > 250.0, "节奏波形覆盖中央主要宽度")
	battle_screen._on_rhythm_beat_reached(0, 0)
	var first_wave_shape: PackedFloat32Array = battle_screen.rhythm_waveform._bar_heights.duplicate()
	_assert_equal(battle_screen.rhythm_waveform._visual_amplitude, 0.0, "拍点从零振幅开始快速起峰")
	battle_screen.rhythm_waveform._process(0.045)
	_assert_true(battle_screen.rhythm_waveform._visual_amplitude > 0.99, "波形在短促起峰后上下完全展开")
	battle_screen.rhythm_waveform._process(0.24)
	var decaying_amplitude: float = battle_screen.rhythm_waveform._visual_amplitude
	_assert_true(decaying_amplitude > 0.0 and decaying_amplitude < 1.0, "波形在两拍之间缓慢衰减")
	battle_screen.rhythm_waveform._process(0.5)
	_assert_equal(battle_screen.rhythm_waveform._visual_amplitude, 0.0, "波形衰减结束后严格归零")
	battle_screen._on_rhythm_beat_reached(1, 0)
	var second_wave_shape: PackedFloat32Array = battle_screen.rhythm_waveform._bar_heights.duplicate()
	battle_screen.rhythm_waveform._process(0.045)
	_assert_true(battle_screen.rhythm_waveform._visual_amplitude > 0.99, "下一拍重新触发完整起峰")
	_assert_true(first_wave_shape != second_wave_shape, "连续拍点会生成不同的波形轮廓")
	_assert_wave_shape_rules(second_wave_shape)
	_assert_true(battle_screen._attack_hit_audio.stream != null, "战斗持有统一命中音效资源")
	_assert_equal(battle_screen._attack_hit_audio.max_polyphony, 8, "多段命中音效支持重叠播放")
	_assert_true(battle_screen._miss_audio.stream != null, "战斗持有Miss提示音效资源")
	_assert_true(
		battle_screen._miss_audio.stream.resource_path.ends_with("sound/sounds/miss.mp3"),
		"Miss播放器绑定指定音效"
	)
	_assert_equal(battle_screen._miss_audio.bus, &"SFX", "Miss音效进入SFX总线")
	battle_screen._on_discipline_card_issued("yellow", 10)
	_assert_true(battle_screen.card_warning_overlay.visible, "黄牌触发可见警告UI")
	_assert_true("10" in battle_screen.card_warning_label.text, "黄牌警告显示本回合出牌数")
	battle_screen._on_discipline_card_issued("red", 20)
	_assert_true(battle_screen.card_warning_overlay.visible, "红牌触发可见警告UI")
	_assert_true("强制结束回合" in battle_screen.card_warning_label.text, "红牌警告说明处罚结果")
	battle_screen.card_warning_overlay.hide()
	var miss_audio_count := [0]
	battle_screen.miss_audio_triggered.connect(func() -> void: miss_audio_count[0] += 1)
	var miss_result := {"grade": battle_screen.rhythm_clock.JudgementGrade.MISS}
	var good_result := {"grade": battle_screen.rhythm_clock.JudgementGrade.GOOD}
	_assert_true(battle_screen._play_miss_audio_if_needed(miss_result, true), "成功出牌且Miss时播放提示音")
	_assert_true(not battle_screen._play_miss_audio_if_needed(good_result, true), "Good出牌不播放Miss提示音")
	_assert_true(not battle_screen._play_miss_audio_if_needed(miss_result, false), "出牌失败不播放Miss提示音")
	_assert_equal(miss_audio_count[0], 1, "不同判定分支只产生一次Miss音效")
	battle_screen._miss_audio.stop()
	# 三段攻击必须逐段调用统一播放器，不能因复用足球节点而吞掉后续触发。
	var impact_audio_count := [0]
	battle_screen.attack_impact_audio_triggered.connect(
		func() -> void: impact_audio_count[0] += 1
	)
	for _hit in range(3):
		battle_screen._play_attack_impact_audio()
	_assert_equal(impact_audio_count[0], 3, "三段攻击产生三次独立命中音效触发")
	battle_screen._attack_hit_audio.stop()
	# 新竖屏布局必须保持敌人在手牌上方、玩家生命栏在手牌下方，防止后续内容撑高造成重叠。
	var enemy_rect: Rect2 = battle_screen.enemy_display.get_global_rect()
	var first_card_rect: Rect2 = battle_screen.hand_layer.get_child(0).get_global_rect()
	var player_rect: Rect2 = battle_screen.player_display.get_global_rect()
	var owned_item_rect: Rect2 = battle_screen.owned_item_icons.get_global_rect()
	_assert_true(enemy_rect.end.y < first_card_rect.position.y, "敌方信息位于手牌上方")
	_assert_true(first_card_rect.end.y < player_rect.position.y, "手牌不遮挡底部玩家生命栏")
	_assert_true(player_rect.end.y <= owned_item_rect.position.y, "战利品图标区位于玩家生命栏下方")
	_assert_true(not battle_screen.owned_item_icons.visible, "未获得战利品时隐藏底部图标区")
	_assert_true(not battle_screen.drag_threshold_guide.visible, "未拖拽时不显示虚线")
	battle_screen._on_card_drag_started(battle_screen.hand_layer.get_child(0))
	_assert_true(battle_screen.drag_threshold_guide.visible, "开始拖拽后显示虚线")
	battle_screen._on_card_drag_moved(battle_screen.hand_layer.get_child(0), Vector2.ZERO, true)
	_assert_true(battle_screen.drag_threshold_guide.prompt_label.visible, "越线后显示松开提示")
	battle_screen._on_card_drag_moved(battle_screen.hand_layer.get_child(0), Vector2.ZERO, false)
	_assert_true(not battle_screen.drag_threshold_guide.prompt_label.visible, "返回线下后隐藏松开提示")
	battle_screen._on_card_drag_finished(battle_screen.hand_layer.get_child(0), false)

	var played: bool = battle_screen.try_play_hand_card(0)
	_assert_true(played, "第一张手牌可以结算")
	_assert_true(not battle_screen.try_play_hand_card(0), "结算帧内拦截重复出牌")
	await _wait_for_resolution(battle_screen)
	_assert_equal(battle_screen.deck_state.hand.size(), 3, "出牌后补回三张")
	_assert_equal(battle_screen.controller.player.energy, 2, "出牌支付一点能量")

	var previous_turn: int = battle_screen.controller.turn_number
	battle_screen._on_end_turn_pressed()
	await process_frame
	_assert_equal(battle_screen.controller.turn_number, previous_turn + 1, "结束回合后推进回合")
	# 数字与阶段拆开显示后，仍须跟随真实回合推进，不出现写死的总回合数。
	_assert_equal(battle_screen.turn_label.text, str(previous_turn + 1), "回合底板同步新回合数字")
	_assert_equal(battle_screen.phase_label.text, battle_screen.controller.get_phase_text(), "顶部阶段同步战斗状态")
	_assert_equal(battle_screen.deck_state.hand.size(), 3, "新回合重新抽三张")
	_assert_equal(battle_screen.controller.player.energy, 3, "新回合回满能量")

	# GM入口使用二级面板；打开时锁住战斗操作，关闭后恢复，不改变战斗状态。
	_assert_true(battle_screen.gm_menu_button.visible, "战斗界面显示GM入口")
	battle_screen._on_gm_menu_pressed()
	_assert_true(battle_screen.gm_overlay.visible, "点击GM入口显示二级面板")
	_assert_true(battle_screen.end_turn_button.disabled, "GM面板打开时锁住结束回合")
	# 战利品页读取完整奖励表；旧式加成及新式触发效果勾选后立即生效，取消即撤销。
	battle_screen._on_gm_items_pressed()
	_assert_true(battle_screen.gm_items_page.visible, "战利品页在GM面板内打开")
	_assert_equal(battle_screen.gm_items_list.get_child_count(), REWARD_SERVICE.new().get_all_items().size(), "GM列出全部普通、Boss和禁用战利品")
	var golden_boot := _find_gm_item_checkbox(battle_screen, "金靴")
	var left_foot := _find_gm_item_checkbox(battle_screen, "黄金左脚")
	var disabled_item := _find_gm_item_checkbox(battle_screen, "角旗杆（未启用）")
	_assert_true(golden_boot != null and left_foot != null and disabled_item != null, "GM显示新旧和禁用奖励名称")
	if golden_boot != null and left_foot != null and disabled_item != null:
		_assert_true(disabled_item.disabled, "禁用占位奖励不能勾选")
		_assert_true(not golden_boot.button_pressed, "未持有奖励初始未勾选")
		golden_boot.button_pressed = true
		_assert_true(4011 in battle_screen.run_state.owned_item_ids, "勾选立即写入本局持有")
		_assert_true(battle_screen.owned_item_icons.visible, "获得战利品后显示底部图标区")
		_assert_equal(battle_screen.owned_item_icons.get_child_count(), 1, "底部只为已持有战利品创建一个图标")
		# 长按图标显示图片、名称和描述，松开后立即隐藏详情浮层。
		var item_press := InputEventMouseButton.new()
		item_press.button_index = MOUSE_BUTTON_LEFT
		item_press.pressed = true
		var held_item_icon := battle_screen.owned_item_icons.get_child(0) as TextureRect
		battle_screen._on_owned_item_icon_gui_input(item_press, held_item_icon, REWARD_SERVICE.new().get_item_by_id(4011))
		_assert_true(battle_screen.item_detail_popup.visible, "按住战利品图标显示详情")
		await create_timer(battle_screen.ITEM_ICON_SCALE_DURATION + 0.05).timeout
		_assert_equal(held_item_icon.scale, Vector2(1.2, 1.2), "按住战利品图标线性放大至1.2倍")
		_assert_equal(battle_screen.item_detail_name.text, "金靴", "详情显示战利品名称")
		_assert_equal(battle_screen.item_detail_description.text, "所有射门伤害+1", "详情显示战利品描述")
		var item_release := InputEventMouseButton.new()
		item_release.button_index = MOUSE_BUTTON_LEFT
		item_release.pressed = false
		battle_screen._on_owned_item_icon_gui_input(item_release, held_item_icon, REWARD_SERVICE.new().get_item_by_id(4011))
		_assert_true(not battle_screen.item_detail_popup.visible, "松开战利品图标隐藏详情")
		await create_timer(battle_screen.ITEM_ICON_SCALE_DURATION + 0.05).timeout
		_assert_equal(held_item_icon.scale, Vector2.ONE, "松开战利品图标线性恢复原大小")
		battle_screen._on_owned_item_icon_mouse_entered(held_item_icon, REWARD_SERVICE.new().get_item_by_id(4011))
		_assert_true(battle_screen.item_detail_popup.visible, "鼠标悬停战利品图标显示详情")
		battle_screen._on_owned_item_icon_mouse_exited(held_item_icon)
		_assert_true(not battle_screen.item_detail_popup.visible, "鼠标移出战利品图标隐藏详情")
		_assert_equal(battle_screen.controller.damage_modifiers.all, 1, "旧式奖励即时增加战斗伤害")
		left_foot.button_pressed = true
		_assert_equal(battle_screen.owned_item_icons.get_child_count(), 2, "多个已持有战利品各显示一个图标")
		_assert_equal(battle_screen.controller.item_runtime.items.size(), 2, "新式奖励即时接入战斗运行时")
		golden_boot.button_pressed = false
		_assert_equal(battle_screen.owned_item_icons.get_child_count(), 1, "取消战利品后同步移除对应图标")
		_assert_equal(battle_screen.controller.damage_modifiers.all, 0, "取消旧式奖励即时撤销加成")
		left_foot.button_pressed = false
		_assert_true(4012 not in battle_screen.run_state.owned_item_ids, "取消新式奖励立即移出本局")
		_assert_equal(battle_screen.controller.item_runtime.items.size(), 0, "取消新式奖励立即停止触发")
		left_foot.button_pressed = true
		battle_screen._on_gm_items_back_pressed()
		battle_screen._on_gm_items_pressed()
		var refreshed_left := _find_gm_item_checkbox(battle_screen, "黄金左脚")
		_assert_true(refreshed_left != null and refreshed_left.button_pressed, "返回后从真实持有状态恢复勾选")
		if refreshed_left != null:
			refreshed_left.button_pressed = false
	battle_screen._on_gm_close_pressed()
	_assert_true(not battle_screen.gm_overlay.visible, "关闭按钮隐藏GM面板")
	_assert_true(not battle_screen.end_turn_button.disabled, "关闭GM面板后恢复战斗输入")
	# GM 卡牌页读取与奖励相同的完整卡牌目录；勾选和取消都只改变指定稳定 ID 的一张牌。
	battle_screen._on_gm_menu_pressed()
	battle_screen._on_gm_cards_pressed()
	_assert_true(battle_screen.gm_cards_page.visible, "卡牌页在GM面板内打开")
	_assert_equal(battle_screen.gm_cards_list.get_child_count(), REWARD_SERVICE.new().get_all_cards().size(), "GM列出全部可获得卡牌")
	var run_up := _find_gm_card_checkbox(battle_screen, "助跑")
	_assert_true(run_up != null and not run_up.button_pressed, "未拥有的卡牌初始未勾选")
	if run_up != null:
		run_up.button_pressed = true
		_assert_true("card_run_up" in battle_screen.run_state.deck_card_ids, "勾选立即加入本局牌库")
		run_up.button_pressed = false
		_assert_true("card_run_up" not in battle_screen.run_state.deck_card_ids, "取消立即移除该张GM卡牌")
	battle_screen._on_gm_close_pressed()

	# 测试玩法的胜利不进入奖励或存档，而是延迟后直接生成下一只固定 100 血怪物。
	battle_screen.run_state.start_test_battle(7302)
	battle_screen.start_new_battle()
	battle_screen.controller.player.health = 67
	var test_battle_generation: int = battle_screen._battle_generation
	_assert_true(battle_screen.controller.debug_force_victory(), "测试玩法可击杀当前怪物")
	_assert_true(await _wait_until_next_battle(battle_screen, test_battle_generation, battle_screen.VICTORY_RESULT_DELAY_SECONDS + 1.0), "测试玩法胜利后完成下一场刷新")
	_assert_equal(battle_screen.controller.enemy.max_health, 100, "测试玩法怪物固定100血")
	_assert_equal(battle_screen.controller.enemy.health, 100, "测试玩法怪物死亡后重新刷出")
	_assert_equal(battle_screen.controller.player.health, 67, "测试玩法刷新怪物时保留玩家当前生命")
	_assert_true(not battle_screen.result_overlay.visible, "测试玩法不会展示通关或奖励结算")
	battle_screen.run_state.start_new_run(7303)
	# 切回正式本局后同步重建控制器，不能继续复用测试玩法刚刷新的战斗实例。
	battle_screen.start_new_battle()

	# 面板内跳过按钮绕过乌龟反伤，直接复用正常胜利与奖励入口。
	battle_screen.controller.player.health = 1
	battle_screen._on_gm_menu_pressed()
	battle_screen._on_gm_skip_pressed()
	_assert_equal(battle_screen.controller.enemy.health, 0, "GM跳过立即消灭敌人")
	_assert_equal(battle_screen.controller.player.health, 1, "GM跳过不触发乌龟反伤")
	_assert_true(not battle_screen.gm_overlay.visible, "GM跳过后关闭二级面板")
	_assert_true(not battle_screen.result_overlay.visible, "怪物死亡后不立即显示胜利结果层")
	_assert_true(battle_screen.end_turn_button.disabled, "胜利后锁定结束回合")
	_assert_true(battle_screen.gm_menu_button.disabled, "胜利后锁定GM入口")
	# 固定计时器到点与协程恢复可能落在同一帧；在有限超时内等待真实 UI 状态，避免把调度顺序误报为失败。
	_assert_true(await _wait_until_visible(battle_screen.result_overlay, battle_screen.VICTORY_RESULT_DELAY_SECONDS + 1.0), "怪物死亡一秒后显示胜利结果层")

	# 重开后把玩家置于濒死状态，验证敌方行动可进入失败结果且不会再抽牌。
	battle_screen.start_new_battle()
	battle_screen.controller.player.health = 1
	battle_screen._on_end_turn_pressed()
	await process_frame
	_assert_equal(battle_screen.controller.phase, battle_screen.controller.Phase.FINISHED, "致命敌方攻击结束战斗")
	_assert_equal(battle_screen.result_title.text, "战斗失败", "失败结果标题")
	_assert_true(battle_screen.result_overlay.visible, "失败后显示结果层")
	_assert_equal(
		battle_screen.run_state.run_status,
		battle_screen.run_state.RunStatus.FAILED,
		"失败后本局状态明确终止"
	)

	if _failed:
		quit(1)
		return
	print("smoke_battle_ui: PASS")
	quit()


# 等待异步表现队列完成，并设置帧数上限避免动画异常时测试永久挂起。
func _wait_for_resolution(battle_screen) -> void:
	for _frame in range(30):
		if not battle_screen._is_presenting_resolution and not battle_screen._input_locked:
			return
		await process_frame
	_assert_true(false, "卡牌动画队列在限定帧数内完成")


# 从真实 GM 行节点查找复选框，避免测试依赖奖励池顺序或滚动位置。
func _find_gm_item_checkbox(battle_screen, display_name: String) -> CheckBox:
	for entry in battle_screen.gm_items_list.get_children():
		for child in entry.get_children():
			if child is CheckBox and child.text == display_name:
				return child
	return null


# 从卡牌 GM 行中定位复选框，避免测试依赖卡牌目录顺序。
func _find_gm_card_checkbox(battle_screen, display_name: String) -> CheckBox:
	for entry in battle_screen.gm_cards_list.get_children():
		for child in entry.get_children():
			if child is CheckBox and child.text == display_name:
				return child
	return null


# 随机轮廓必须保持中部占主导、最高点留在中区，并确保所有竖条高度处于绘制安全范围。
func _assert_wave_shape_rules(heights: PackedFloat32Array) -> void:
	_assert_equal(heights.size(), 72, "随机波形保持固定竖条数量")
	var side_total := 0.0
	var side_count := 0
	var center_total := 0.0
	var center_count := 0
	var highest_index := 0
	for index in range(heights.size()):
		_assert_true(heights[index] >= 0.0 and heights[index] <= 1.0, "随机竖条高度保持在安全范围")
		if heights[index] > heights[highest_index]:
			highest_index = index
		var normalized_x := (float(index) + 0.5) / float(heights.size())
		if normalized_x >= 0.28 and normalized_x <= 0.72:
			center_total += heights[index]
			center_count += 1
		else:
			side_total += heights[index]
			side_count += 1
	_assert_true(center_total / center_count > side_total / side_count, "波形中间区域平均高度高于左右区域")
	var highest_x := (float(highest_index) + 0.5) / float(heights.size())
	_assert_true(highest_x >= 0.28 and highest_x <= 0.72, "波形最高点保持在中间区域")


# 通用相等断言，失败时保留实际值便于定位 UI 状态不同步。
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


# 每帧观察控件状态并设置硬超时；只消除同帧协程恢复竞态，不允许胜利层无限期延迟。
func _wait_until_visible(control: CanvasItem, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while not control.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	return control.visible


# 测试玩法胜利必须等新战斗代次真正建立后才能切回正式局，避免旧异步刷新覆盖下一次胜利。
func _wait_until_next_battle(battle_screen: Control, previous_generation: int, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while battle_screen._battle_generation <= previous_generation and Time.get_ticks_msec() < deadline:
		await process_frame
	return battle_screen._battle_generation > previous_generation
