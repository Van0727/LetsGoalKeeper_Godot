# 通用角色显示控件：维护生命、护盾文本和即时颜色反馈，并支持战斗界面的敌我紧凑布局。
class_name CharacterDisplay
extends PanelContainer

enum BattleLayoutRole {
	DEFAULT,
	ENEMY,
	PLAYER_BAR,
}

const ENEMY_PLACEHOLDER := preload("res://assets/placeholders/enemy_goalkeeper.png")
const MONSTER_BLINK_SHADER := preload("res://shaders/monster_blink.gdshader")

# 单图眨眼区域按图片单独配置；没有配置的怪物保留其他程序动画并安全跳过眨眼。
const ENEMY_BLINK_CONFIG := {
	7001: {
		"left_eye_center": Vector2(0.378, 0.528),
		"right_eye_center": Vector2(0.632, 0.528),
		"eye_radius": Vector2(0.061, 0.066),
	},
}

const RHYTHM_DOWN_SECONDS := 0.075
const RHYTHM_RETURN_SECONDS := 0.24
const ATTACK_WINDUP_SECONDS := 0.12
const ATTACK_RELEASE_SECONDS := 0.10
const ATTACK_RETURN_SECONDS := 0.18
const HIT_SHAKE_SECONDS := 0.055
const SHOT_HIT_SECONDS := 0.09
const SHOT_RECOVER_SECONDS := 0.22
const BLINK_CLOSE_SECONDS := 0.065
const BLINK_HOLD_SECONDS := 0.035
const BLINK_OPEN_SECONDS := 0.085

@onready var name_label: Label = %NameLabel
@onready var portrait_slot: Control = %PortraitSlot
@onready var portrait: TextureRect = %Portrait
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var shield_label: Label = %ShieldLabel
@onready var feedback_label: Label = %FeedbackLabel

# 缓存基础外观和当前反馈动画，避免连续反馈互相覆盖后残留状态。
var _max_health := 1
var _current_health := 1
var _portrait_tint := Color.WHITE
var _flash_tween: Tween
var _feedback_tween: Tween
var _motion_tween: Tween
var _blink_tween: Tween
var _blink_timer: Timer
var _battle_layout_role := BattleLayoutRole.DEFAULT
var _action_animation_active := false
var _portrait_dead := false
var _rhythm_direction := 1.0
# 配表基础倍率与动作形变分属两套变换：基础倍率固定底边，动作只叠加临时形变。
var _portrait_base_scale := Vector2.ONE


# 按战斗位置压缩角色信息：敌方数值交给专用信息层，此控件保留头像与受击反馈。
func set_battle_layout_role(role: BattleLayoutRole) -> void:
	_battle_layout_role = role
	var margin := $Margin as MarginContainer
	var content := $Margin/Content as VBoxContainer
	match role:
		BattleLayoutRole.ENEMY:
			# 战斗场景决定怪物显示框尺寸，头像随编辑器中拖出的框缩放，不再写死宽高。
			custom_minimum_size = Vector2.ZERO
			# 敌人信息直接叠在场景背景上；显式空样式避免移除覆盖后回退到默认深色面板。
			add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			margin.add_theme_constant_override("margin_left", 4)
			margin.add_theme_constant_override("margin_top", 2)
			margin.add_theme_constant_override("margin_right", 4)
			margin.add_theme_constant_override("margin_bottom", 2)
			content.add_theme_constant_override("separation", 1)
			# 槽位参与 VBox 布局，头像作为普通子节点独立缩放，避免 Container 把配表倍率重置为 1。
			portrait_slot.custom_minimum_size = Vector2.ZERO
			portrait_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			feedback_label.custom_minimum_size = Vector2(0, 20)
			name_label.hide()
			health_bar.hide()
			health_label.hide()
			shield_label.hide()
		BattleLayoutRole.PLAYER_BAR:
			custom_minimum_size = Vector2.ZERO
			margin.add_theme_constant_override("margin_left", 0)
			margin.add_theme_constant_override("margin_top", 0)
			margin.add_theme_constant_override("margin_right", 0)
			margin.add_theme_constant_override("margin_bottom", 0)
			content.add_theme_constant_override("separation", 0)
			name_label.hide()
			portrait.hide()
			feedback_label.hide()
			shield_label.hide()
			health_bar.custom_minimum_size = Vector2(0, 16)
			health_label.add_theme_font_size_override("font_size", 11)
		_:
			pass


# 设置角色名称、生命上限和占位头像颜色。
func configure(display_name: String, max_health: int, portrait_tint: Color) -> void:
	reset_portrait_animation()
	name_label.text = display_name
	_max_health = maxi(max_health, 1)
	_current_health = _max_health
	_portrait_tint = portrait_tint
	portrait.modulate = _portrait_tint
	health_bar.max_value = _max_health
	set_health(_max_health)
	set_shield(0)


# 按配表图片 ID 替换头像；正式图片保持原色，缺图时回退占位图与既有染色。
func set_enemy_image_id(image_id: int, battle_image_scale := 1.0) -> void:
	reset_portrait_animation()
	_portrait_base_scale = Vector2.ONE * clampf(battle_image_scale, 0.1, 4.0)
	# Control 自身缩放以底部中心为轴心，使不同体型怪物始终站在同一条底线上。
	portrait.pivot_offset_ratio = Vector2(0.5, 1.0)
	portrait.scale = _portrait_base_scale
	portrait.texture = ENEMY_PLACEHOLDER
	portrait.material = null
	_stop_blink_timer()
	if image_id <= 0:
		portrait.modulate = _portrait_tint
		return
	var image_path := "res://assets/ui/enemies/%d.png" % image_id
	if not ResourceLoader.exists(image_path, "Texture2D"):
		push_warning("怪物图片不存在：%s" % image_path)
		portrait.modulate = _portrait_tint
		return
	var image := ResourceLoader.load(image_path, "Texture2D") as Texture2D
	if image == null:
		push_warning("怪物图片加载失败：%s" % image_path)
		portrait.modulate = _portrait_tint
		return
	portrait.texture = image
	_portrait_tint = Color.WHITE
	portrait.modulate = Color.WHITE
	_configure_blink_material(image_id)


# 更新生命条与文本，数值会限制在合法范围内。
func set_health(current_health: int) -> void:
	var safe_health := clampi(current_health, 0, _max_health)
	_current_health = safe_health
	health_bar.value = safe_health
	health_label.text = "%d / %d" % [safe_health, _max_health]


# 更新护盾显示。
func set_shield(shield: int) -> void:
	shield_label.text = "护盾  %d" % maxi(shield, 0)


# 返回头像的全局中心，供足球表现层把命中位置绑定到实际布局而不是写死坐标。
func get_portrait_global_center() -> Vector2:
	return portrait.get_global_rect().get_center()


# 播放红色受击反馈；射门类型和方向只决定显示动作，不参与伤害与护盾结算。
func show_damage(amount: int, shot_type := 0, shot_direction := 0) -> void:
	_play_feedback("-%d" % amount, Color(1.0, 0.32, 0.28), Color(1.0, 0.35, 0.35))
	if _battle_layout_role != BattleLayoutRole.ENEMY:
		return
	if _current_health <= 0:
		play_death()
	else:
		play_hit(shot_type, shot_direction)


# 播放绿色治疗反馈。
func show_heal(amount: int) -> void:
	_play_feedback("+%d 生命" % amount, Color(0.3, 1.0, 0.5), Color(0.45, 1.0, 0.55))


# 播放蓝色护盾增加反馈。
func show_shield_gain(amount: int) -> void:
	_play_feedback("+%d 护盾" % amount, Color(0.35, 0.75, 1.0), Color(0.45, 0.78, 1.0))


# 播放护盾吸收伤害的反馈。
func show_shield_loss(amount: int) -> void:
	_play_feedback("护盾 -%d" % amount, Color(0.55, 0.82, 1.0), Color(0.45, 0.78, 1.0))


# 统一控制浮字与头像闪色，并在动画结束后恢复基础外观。
func _play_feedback(text: String, text_color: Color, flash_color: Color) -> void:
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	if _feedback_tween and _feedback_tween.is_running():
		_feedback_tween.kill()

	portrait.modulate = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(portrait, "modulate", _portrait_tint, 0.28)

	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", text_color)
	feedback_label.modulate = Color.WHITE
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(0.35)
	_feedback_tween.tween_property(feedback_label, "modulate:a", 0.0, 0.45)


# 每个真实拍点播放一次完整律动；重拍幅度更明显，动作时长短于一拍以避免跨拍累积。
func play_rhythm_beat(beat_index: int, beats_per_bar: int) -> void:
	if _battle_layout_role != BattleLayoutRole.ENEMY or _action_animation_active or _portrait_dead:
		return
	_kill_motion_tween()
	_prepare_portrait_transform()
	var strong_beat := posmod(beat_index, maxi(beats_per_bar, 1)) == 0
	var strength := 1.0 if strong_beat else 0.62
	_rhythm_direction *= -1.0
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(portrait, "offset_transform_position", Vector2(0.0, 2.4 * strength), RHYTHM_DOWN_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2(1.025, 0.965).lerp(Vector2.ONE, 1.0 - strength), RHYTHM_DOWN_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_rotation", deg_to_rad(0.8 * strength * _rhythm_direction), RHYTHM_DOWN_SECONDS)
	_motion_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion_tween.chain().tween_property(portrait, "offset_transform_position", Vector2.ZERO, RHYTHM_RETURN_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2.ONE, RHYTHM_RETURN_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_rotation", 0.0, RHYTHM_RETURN_SECONDS)


# 敌方行动只接管显示层：下压蓄力、向前冲出并回弹，不延迟核心结算。
func play_enemy_attack() -> void:
	if _battle_layout_role != BattleLayoutRole.ENEMY or _portrait_dead:
		return
	_begin_action_animation()
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(portrait, "offset_transform_position", Vector2(0.0, 5.0), ATTACK_WINDUP_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2(1.055, 0.91), ATTACK_WINDUP_SECONDS)
	_motion_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_motion_tween.chain().tween_property(portrait, "offset_transform_position", Vector2(0.0, -8.0), ATTACK_RELEASE_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2(0.96, 1.075), ATTACK_RELEASE_SECONDS)
	_motion_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion_tween.chain().tween_property(portrait, "offset_transform_position", Vector2.ZERO, ATTACK_RETURN_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2.ONE, ATTACK_RETURN_SECONDS)
	_motion_tween.chain().tween_callback(_finish_action_animation)


# 根据实际射门类型选择受力方向；非射门伤害使用轻量通用震动。
func play_hit(shot_type := 0, shot_direction := 0) -> void:
	if _battle_layout_role != BattleLayoutRole.ENEMY or _portrait_dead:
		return
	match shot_type:
		1:
			_play_straight_hit()
		2:
			_play_banana_hit(shot_direction)
		3:
			_play_lob_hit()
		_:
			_play_generic_hit()


# 直球从正面命中后产生短促向上位移，并用纵向拉伸强调冲击方向。
func _play_straight_hit() -> void:
	_begin_action_animation()
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(portrait, "offset_transform_position", Vector2(0.0, -7.0), SHOT_HIT_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2(0.97, 1.055), SHOT_HIT_SECONDS)
	_motion_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion_tween.chain().tween_property(portrait, "offset_transform_position", Vector2.ZERO, SHOT_RECOVER_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2.ONE, SHOT_RECOVER_SECONDS)
	_motion_tween.chain().tween_callback(_finish_action_animation)


# 香蕉球按来球方向的反方向横向击退；左侧来球向右后退，右侧来球向左后退。
func _play_banana_hit(shot_direction: int) -> void:
	_begin_action_animation()
	var safe_direction := signi(shot_direction)
	if safe_direction == 0:
		# 无方向的旧事件仍给出轻微横向反馈，但不修改核心方向状态。
		safe_direction = -1 if _rhythm_direction < 0.0 else 1
	var knockback_x := float(-safe_direction) * 8.0
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(portrait, "offset_transform_position", Vector2(knockback_x, -3.0), SHOT_HIT_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_rotation", deg_to_rad(signf(knockback_x) * 3.0), SHOT_HIT_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2(1.02, 0.98), SHOT_HIT_SECONDS)
	_motion_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion_tween.chain().tween_property(portrait, "offset_transform_position", Vector2.ZERO, SHOT_RECOVER_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_rotation", 0.0, SHOT_RECOVER_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2.ONE, SHOT_RECOVER_SECONDS)
	_motion_tween.chain().tween_callback(_finish_action_animation)


# 挑射从上方落下，怪物短暂压扁并向两侧展开后弹回。
func _play_lob_hit() -> void:
	_begin_action_animation()
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(portrait, "offset_transform_position", Vector2(0.0, 3.0), SHOT_HIT_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2(1.10, 0.78), SHOT_HIT_SECONDS)
	_motion_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion_tween.chain().tween_property(portrait, "offset_transform_position", Vector2.ZERO, SHOT_RECOVER_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2.ONE, SHOT_RECOVER_SECONDS)
	_motion_tween.chain().tween_callback(_finish_action_animation)


# 流血等没有足球方向的伤害只做轻量震动，避免冒充特定射门受力。
func _play_generic_hit() -> void:
	_begin_action_animation()
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(portrait, "offset_transform_position", Vector2(-2.5, 0.8), HIT_SHAKE_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2(1.025, 0.975), HIT_SHAKE_SECONDS)
	_motion_tween.chain().tween_property(portrait, "offset_transform_position", Vector2(1.5, -0.5), HIT_SHAKE_SECONDS)
	_motion_tween.tween_property(portrait, "offset_transform_position", Vector2.ZERO, HIT_SHAKE_SECONDS)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2.ONE, HIT_SHAKE_SECONDS)
	_motion_tween.chain().tween_callback(_finish_action_animation)


# 死亡表现保持在显示层：压扁、下沉并淡出；新战斗 configure 会完整恢复状态。
func play_death() -> void:
	if _battle_layout_role != BattleLayoutRole.ENEMY or _portrait_dead:
		return
	_portrait_dead = true
	_begin_action_animation()
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_motion_tween.tween_property(portrait, "offset_transform_position", Vector2(0.0, 14.0), 0.38)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_scale", Vector2(1.10, 0.72), 0.38)
	_motion_tween.parallel().tween_property(portrait, "offset_transform_rotation", deg_to_rad(4.0), 0.38)
	_motion_tween.parallel().tween_property(portrait, "modulate:a", 0.0, 0.38)


# 切换怪物或开始新战斗时终止旧动画，避免 Tween 的末值污染用户在场景中调整的位置和尺寸。
func reset_portrait_animation() -> void:
	_kill_motion_tween()
	# 受击闪色和反馈位移动画也会持续写入头像属性；换怪时必须一并停止，避免旧怪动画给新图片染色。
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()
	if _feedback_tween and _feedback_tween.is_running():
		_feedback_tween.kill()
	feedback_label.text = " "
	feedback_label.modulate = Color.WHITE
	if _blink_tween and _blink_tween.is_running():
		_blink_tween.kill()
	_action_animation_active = false
	_portrait_dead = false
	_rhythm_direction = 1.0
	_prepare_portrait_transform()
	portrait.offset_transform_position = Vector2.ZERO
	portrait.offset_transform_scale = Vector2.ONE
	portrait.offset_transform_rotation = 0.0
	portrait.modulate = _portrait_tint
	var shader_material := portrait.material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("blink_amount", 0.0)


# 为单张图片创建独立材质，避免多个怪物实例共享眨眼参数。
func _configure_blink_material(image_id: int) -> void:
	if not ENEMY_BLINK_CONFIG.has(image_id):
		return
	var config: Dictionary = ENEMY_BLINK_CONFIG[image_id]
	var shader_material := ShaderMaterial.new()
	shader_material.shader = MONSTER_BLINK_SHADER
	shader_material.set_shader_parameter("left_eye_center", config.left_eye_center)
	shader_material.set_shader_parameter("right_eye_center", config.right_eye_center)
	shader_material.set_shader_parameter("eye_radius", config.eye_radius)
	portrait.material = shader_material
	_start_blink_timer()


# 随机眨眼避免固定周期的机械感；计时器只在配置了眼睛区域的敌人上运行。
func _start_blink_timer() -> void:
	if _blink_timer == null:
		_blink_timer = Timer.new()
		_blink_timer.one_shot = true
		_blink_timer.timeout.connect(_play_blink)
		add_child(_blink_timer)
	_schedule_next_blink()


func _schedule_next_blink() -> void:
	if _blink_timer == null or portrait.material == null or _portrait_dead:
		return
	_blink_timer.start(randf_range(2.4, 4.8))


func _stop_blink_timer() -> void:
	if _blink_timer != null:
		_blink_timer.stop()


# 眨眼仅修改材质参数，不与位置、缩放和受击闪色争用同一属性。
func _play_blink() -> void:
	var shader_material := portrait.material as ShaderMaterial
	if shader_material == null or _portrait_dead:
		return
	if _blink_tween and _blink_tween.is_running():
		_blink_tween.kill()
	_blink_tween = create_tween()
	_blink_tween.tween_property(shader_material, "shader_parameter/blink_amount", 1.0, BLINK_CLOSE_SECONDS)
	_blink_tween.tween_interval(BLINK_HOLD_SECONDS)
	_blink_tween.tween_property(shader_material, "shader_parameter/blink_amount", 0.0, BLINK_OPEN_SECONDS)
	_blink_tween.tween_callback(_schedule_next_blink)


func _prepare_portrait_transform() -> void:
	portrait.offset_transform_enabled = true
	portrait.offset_transform_visual_only = true
	portrait.offset_transform_pivot_ratio = Vector2(0.5, 0.78)


func _begin_action_animation() -> void:
	_kill_motion_tween()
	_action_animation_active = true
	_prepare_portrait_transform()


func _finish_action_animation() -> void:
	portrait.offset_transform_position = Vector2.ZERO
	portrait.offset_transform_scale = Vector2.ONE
	portrait.offset_transform_rotation = 0.0
	_action_animation_active = false


func _kill_motion_tween() -> void:
	if _motion_tween and _motion_tween.is_running():
		_motion_tween.kill()
