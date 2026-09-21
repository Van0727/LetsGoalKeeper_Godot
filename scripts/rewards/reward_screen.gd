# 战斗奖励界面：普通怪只发放卡牌，Boss 继续发放卡牌与战利品；确认后离屏再入账。
extends Control

const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const ITEM_DEFINITION := preload("res://scripts/items/item_definition.gd")
const NORMAL_ITEM_PLACEHOLDER := preload("res://assets/ui/items/item_placeholder_normal.svg")
const BOSS_ITEM_PLACEHOLDER := preload("res://assets/ui/items/item_placeholder_boss.svg")

enum Phase { CARD, ITEM }

@onready var title_label: Label = %TitleLabel
@onready var subtitle_label: Label = %SubtitleLabel
@onready var run_label: Label = %RunLabel
@onready var card_step: PanelContainer = %CardStep
@onready var item_step: PanelContainer = %ItemStep
@onready var choice_buttons: Array[Button] = [%Choice0, %Choice1, %Choice2]
@onready var selection_rings: Array[Panel] = [%SelectionRing0, %SelectionRing1, %SelectionRing2]
@onready var card_views: Array[BattleCardView] = [%RewardCard0, %RewardCard1, %RewardCard2]
@onready var item_contents: Array[VBoxContainer] = [%ItemContent0, %ItemContent1, %ItemContent2]
@onready var item_icons: Array[TextureRect] = [%ItemIcon0, %ItemIcon1, %ItemIcon2]
@onready var item_name_labels: Array[Label] = [%ItemName0, %ItemName1, %ItemName2]
@onready var item_description_labels: Array[Label] = [%ItemDescription0, %ItemDescription1, %ItemDescription2]
@onready var confirm_button: Button = %ConfirmButton
@onready var reward_detail: RichTextLabel = %RewardDetail

var phase := Phase.CARD
var choices: Array[Resource] = []
var _service := REWARD_SERVICE.new()
var _rng := RandomNumberGenerator.new()
var run_state: Node
var _is_scene_transitioning := false
var _is_reward_animating := false
var _selected_index := -1
var _choice_scale_tweens: Dictionary = {}
# 按原字体共享本页副本，避免每个标签重复建立字形缓存，也不改动全局或战斗字体。
var _reward_font_copies: Dictionary = {}
var _step_active_style: StyleBox
var _step_idle_style: StyleBox

const SELECTED_SCALE := Vector2(1.5, 1.5)
const NORMAL_SCALE := Vector2.ONE
const SELECT_SCALE_DURATION := 0.24
const DESELECT_SCALE_DURATION := 0.2
const REWARD_RISE_DURATION := 0.16
const REWARD_FALL_DURATION := 0.42
const REWARD_FLY_DURATION := REWARD_RISE_DURATION + REWARD_FALL_DURATION
const REWARD_RISE_DISTANCE := 72.0
const REWARD_FONT_MSDF_SIZE := 96


# 奖励随机数由本局seed和已胜场数派生，相同进度可复现同一组候选。
func _ready() -> void:
	run_state = get_node_or_null("/root/RunState")
	# 独立场景回归没有 Autoload 时使用局部新局，保持奖励界面可单独验收。
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
	_rng.seed = run_state.seed + run_state.battles_won * 1009 + 61
	# 保存场景内两种步骤胶囊样式，阶段切换时交换引用，不在运行时重复创建资源。
	_step_active_style = card_step.get_theme_stylebox("panel")
	_step_idle_style = item_step.get_theme_stylebox("panel")
	for button in choice_buttons:
		_prepare_scaled_fonts(button)
	for index in range(choice_buttons.size()):
		choice_buttons[index].pressed.connect(_on_choice_pressed.bind(index))
		# 战斗卡面仅作为奖励视觉复用；输入由外层按钮接管，禁止拖拽和出牌。
		card_views[index].set_interaction_enabled(false)
	confirm_button.pressed.connect(_on_confirm_pressed)
	_show_card_choices()


# 只处理会随奖励槽缩放的文字；领取副本继承字体覆盖，动画中也不会回到低分辨率字形。
func _prepare_scaled_fonts(node: Node) -> void:
	if node is Label:
		var label := node as Label
		label.add_theme_font_override("font", _copy_reward_font(label.get_theme_font("font")))
	for child in node.get_children():
		_prepare_scaled_fonts(child)


# 复制现有字体及回退链；费用的模拟加粗可能产生重叠轮廓，单独保留高采样栅格渲染。
func _copy_reward_font(source: Font) -> Font:
	if _reward_font_copies.has(source):
		return _reward_font_copies[source]
	var copy := source.duplicate() as Font
	_reward_font_copies[source] = copy
	if copy is FontVariation:
		var variation := copy as FontVariation
		var base := variation.base_font if variation.base_font != null else ThemeDB.fallback_font
		if not is_zero_approx(variation.variation_embolden) and (base is FontFile or base is SystemFont):
			# MSDF 不支持重叠轮廓；避免费用数字出现内部缺色，同时不改变原来的粗细。
			variation.base_font = base.duplicate() as Font
			variation.base_font.set("oversampling", 2.0)
		else:
			variation.base_font = _copy_reward_font(base)
	elif copy is FontFile or copy is SystemFont:
		# 距离场覆盖选中放大及缓动超调；提高距离场精度以保留中文笔画，保持原字号和换行。
		copy.set("multichannel_signed_distance_field", true)
		copy.set("msdf_size", REWARD_FONT_MSDF_SIZE)
	var fallbacks: Array[Font] = []
	for fallback in source.fallbacks:
		fallbacks.append(_copy_reward_font(fallback))
	copy.fallbacks = fallbacks
	return copy


# 展示当前战斗级别对应的三张候选卡。
func _show_card_choices() -> void:
	phase = Phase.CARD
	# 普通怪只有一步卡牌奖励，隐藏会误导玩家的战利品进度。
	card_step.get_parent().get_node("Arrow").visible = run_state.pending_reward_is_boss
	item_step.visible = run_state.pending_reward_is_boss
	_refresh_phase_progress()
	title_label.text = "选择卡牌奖励"
	subtitle_label.text = "选择1张加入本局牌库"
	choices = _service.generate_card_choices(run_state.pending_reward_is_boss, _rng)
	_refresh_buttons()


# 展示未拥有战利品；池耗尽时提供明确的继续入口。
func _show_item_choices() -> void:
	phase = Phase.ITEM
	_refresh_phase_progress()
	title_label.text = "选择遗物奖励"
	subtitle_label.text = "选择1件遗物，确认后立即生效"
	choices = _service.generate_item_choices(
		run_state.pending_reward_is_boss,
		run_state.owned_item_ids,
		_rng
	)
	_refresh_buttons()
	if choices.is_empty():
		subtitle_label.text = "该奖励池已没有新的遗物"
		confirm_button.text = "继续下一战"
		confirm_button.disabled = false


# 将候选映射到固定三个槽位；卡牌复用战斗卡面，遗物使用纯色图片占位并单独排版名称与描述。
func _refresh_buttons() -> void:
	# 切换奖励阶段前清理尚未结束的选择动效，避免旧 Tween 回写新阶段卡面。
	for tween_value in _choice_scale_tweens.values():
		var scale_tween := tween_value as Tween
		if scale_tween != null and scale_tween.is_valid():
			scale_tween.kill()
	_choice_scale_tweens.clear()
	_selected_index = -1
	# 每次切换候选清空旧详情；固定高度滚动区避免长描述推动奖励行及确认按钮。
	reward_detail.text = "点击卡牌查看完整说明" if phase == Phase.CARD else "点击战利品查看完整说明"
	reward_detail.scroll_to_line(0)
	confirm_button.self_modulate = Color.WHITE
	confirm_button.text = "确认选择  →"
	confirm_button.disabled = true
	run_label.text = "生命 %d/%d　牌库 %d　战利品 %d" % [
		run_state.player_hp, run_state.max_hp,
		run_state.deck_card_ids.size(), run_state.owned_item_ids.size(),
	]
	for index in range(choice_buttons.size()):
		var button := choice_buttons[index]
		# 只使用绝对枢轴；比例枢轴必须归零，否则两者叠加会把纵向锚点推到底边。
		button.pivot_offset_ratio = Vector2.ZERO
		button.modulate = Color.WHITE
		button.scale = NORMAL_SCALE
		button.z_index = 0
		selection_rings[index].hide()
		button.disabled = false
		if index >= choices.size():
			button.hide()
			continue
		button.show()
		var definition := choices[index]
		if phase == Phase.CARD:
			button.flat = true
			button.text = ""
			item_contents[index].hide()
			card_views[index].show()
			card_views[index].configure(definition, index)
		else:
			button.flat = false
			button.text = ""
			card_views[index].hide()
			item_contents[index].show()
			# 当前没有正式插画时，普通与 Boss 遗物用不同纯色图占位，后续可直接替换为专属图片。
			item_icons[index].texture = BOSS_ITEM_PLACEHOLDER if definition.rarity == ITEM_DEFINITION.Rarity.BOSS else NORMAL_ITEM_PLACEHOLDER
			item_name_labels[index].text = definition.display_name
			item_description_labels[index].text = definition.description


# 首次点击只切换预选项；围绕中心放大且提高绘制层级，避免被左右卡牌遮挡。
func _on_choice_pressed(index: int) -> void:
	if _is_scene_transitioning or _is_reward_animating:
		return
	if index < 0 or index >= choices.size():
		return
	_selected_index = index
	# 不启用 BBCode，配表中的括号等文本按原文显示；空描述给出明确回退。
	var definition := choices[index]
	var description: String = definition.description
	if description.strip_edges().is_empty():
		description = "暂无效果说明"
	reward_detail.text = "%s\n%s" % [definition.display_name, description]
	reward_detail.scroll_to_line(0)
	for button_index in range(choice_buttons.size()):
		var button := choice_buttons[button_index]
		var is_selected := button_index == _selected_index
		# 绝对枢轴固定在左边中心、几何中心、右边中心，三个槽位都不允许使用底边锚点。
		button.pivot_offset_ratio = Vector2.ZERO
		if button_index == 0:
			button.pivot_offset = Vector2(0.0, button.size.y * 0.5)
		elif button_index == choice_buttons.size() - 1:
			button.pivot_offset = Vector2(button.size.x, button.size.y * 0.5)
		else:
			button.pivot_offset = button.size * 0.5
		_animate_choice_scale(
			button_index,
			SELECTED_SCALE if is_selected else NORMAL_SCALE,
			SELECT_SCALE_DURATION if is_selected else DESELECT_SCALE_DURATION
		)
		button.z_index = 1 if is_selected else 0
		selection_rings[button_index].visible = is_selected
		# 未选项轻微降亮，突出当前选择但仍保留内容可读性。
		button.modulate = Color.WHITE if is_selected else Color(0.78, 0.84, 0.9, 1.0)
	confirm_button.disabled = false
	confirm_button.text = "获得这张卡牌  →" if phase == Phase.CARD else "获得这件战利品  →"


# 顶部两步进度与实际奖励阶段保持一致，卡牌领取后明确提示玩家仍需选择战利品。
func _refresh_phase_progress() -> void:
	var card_active := phase == Phase.CARD
	card_step.add_theme_stylebox_override("panel", _step_active_style if card_active else _step_idle_style)
	item_step.add_theme_stylebox_override("panel", _step_idle_style if card_active else _step_active_style)
	card_step.modulate = Color.WHITE if card_active else Color(0.72, 0.78, 0.84, 1.0)
	item_step.modulate = Color(0.72, 0.78, 0.84, 1.0) if card_active else Color.WHITE


# 选中和取消选中都从当前尺寸平滑衔接，并用 Ease Out Back 提供柔和的轻微回弹。
func _animate_choice_scale(index: int, target_scale: Vector2, duration: float) -> void:
	var previous_tween := _choice_scale_tweens.get(index) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	var button := choice_buttons[index]
	var scale_tween := create_tween().bind_node(button)
	scale_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(button, "scale", target_scale, duration)
	_choice_scale_tweens[index] = scale_tween


# 确认时锁定最终缩放，飞出副本始终继承完整的1.5倍选中状态。
func _finish_choice_scale_animations() -> void:
	for index in range(choice_buttons.size()):
		var scale_tween := _choice_scale_tweens.get(index) as Tween
		if scale_tween != null and scale_tween.is_valid():
			scale_tween.kill()
		choice_buttons[index].scale = SELECTED_SCALE if index == _selected_index else NORMAL_SCALE
	_choice_scale_tweens.clear()


# 确认后隐藏按钮并播放上抬下坠动画；动画结束才提交奖励，保持表现与数据顺序一致。
func _on_confirm_pressed() -> void:
	if _is_scene_transitioning or _is_reward_animating:
		return
	if choices.is_empty():
		if phase != Phase.ITEM:
			return
	elif _selected_index < 0 or _selected_index >= choices.size():
		return

	_is_reward_animating = true
	_finish_choice_scale_animations()
	# 视觉隐藏但保留确认按钮的布局占位，避免奖励行因纵向空间变化而跳动。
	confirm_button.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	confirm_button.disabled = true
	for button in choice_buttons:
		button.disabled = true
	if not choices.is_empty():
		await _play_reward_fly_out(choice_buttons[_selected_index])

	if phase == Phase.CARD:
		run_state.add_card(choices[_selected_index].card_id)
		_is_reward_animating = false
		# 只有 Boss 胜利才继续战利品步骤；小怪在卡牌入账后立即原子提交房间。
		if run_state.pending_reward_is_boss:
			_show_item_choices()
			return
		await _complete_reward_flow()
		return

	if not choices.is_empty():
		run_state.add_item(choices[_selected_index])
	await _complete_reward_flow()


# 卡牌单步或 Boss 两步奖励完成后共用同一原子提交出口，避免房间、存档与切曲顺序分叉。
func _complete_reward_flow() -> void:
	# 最后一项奖励提交后禁止重复点击，等待音频过场期间不能再次推进房间。
	_is_reward_animating = false
	_is_scene_transitioning = true
	for button in choice_buttons:
		button.disabled = true
	var flow_result: int = run_state.complete_reward_and_advance()
	run_state.resume_point = run_state.ResumePoint.MAP
	# 奖励、房间完成与可能的章节切换已按固定顺序提交，此处形成新的可恢复安全节点。
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null:
		save_service.save_game(run_state)
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("run", "reward_completed", {
			"chapter": run_state.chapter,
			"battles_won": run_state.battles_won,
			"flow_result": flow_result,
		})
	if flow_result == run_state.RewardFlowResult.NO_MAP:
		var battle_bgm_service := get_node_or_null("/root/BgmService")
		if battle_bgm_service != null:
			await battle_bgm_service.prepare_battle_transition()
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
		return
	# 只有第三章 Boss 完成后进入独立通关页；前两章 Boss 与普通房均继续地图流程。
	if flow_result == run_state.RewardFlowResult.RUN_COMPLETED:
		get_tree().change_scene_to_file("res://scenes/result_screen.tscn")
		return
	# 战斗胜利的奖励结算完成后使用 win 音效；地图显示前才恢复主曲，避免音效后补播。
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		await bgm_service.transition_after_victory_to_main_bgm()
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 使用视觉副本脱离容器先上抬、再加速下坠；布局重排不会改变动画的原始起点。
func _play_reward_fly_out(source: Control) -> void:
	var flying_reward := source.duplicate() as Control
	flying_reward.name = "FlyingReward"
	add_child(flying_reward)
	flying_reward.size = source.size
	flying_reward.pivot_offset = source.pivot_offset
	flying_reward.rotation = source.rotation
	flying_reward.scale = source.scale
	# Control 没有可写的 global_transform；缩放和枢轴就绪后最后对齐全局位置，首帧即可重合。
	flying_reward.global_position = source.global_position
	flying_reward.z_index = 100
	flying_reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 复制出的战斗卡面脚本默认会重新启用全局触摸监听，动画副本必须显式关闭。
	for child in flying_reward.get_children():
		if child is BattleCardView:
			child.set_interaction_enabled(false)
			child.set_process_input(false)
	# modulate 会连同战斗卡面子节点一起变透明；槽位本身仍参与布局，未选奖励不会补位。
	source.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var destination_y := size.y + flying_reward.size.y * flying_reward.scale.y
	var tween := create_tween()
	# 短促上抬用于强调奖励被拾取，随后以加速曲线坠出屏幕。
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		flying_reward,
		"position:y",
		flying_reward.position.y - REWARD_RISE_DISTANCE,
		REWARD_RISE_DURATION
	)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(flying_reward, "position:y", destination_y, REWARD_FALL_DURATION)
	await tween.finished
	flying_reward.queue_free()


# 奖励阶段允许返回主菜单，但不会把未完成奖励误记为完成。
func _on_back_pressed() -> void:
	# 奖励页可能仍在播放上一场战斗曲；返回主菜单前必须通过切曲服务统一收尾。
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		await bgm_service.transition_to_main_bgm()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
