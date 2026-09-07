# 通用角色显示控件：维护生命、护盾文本和即时颜色反馈，并支持战斗界面的敌我紧凑布局。
class_name CharacterDisplay
extends PanelContainer

enum BattleLayoutRole {
	DEFAULT,
	ENEMY,
	PLAYER_BAR,
}

@onready var name_label: Label = %NameLabel
@onready var portrait: TextureRect = %Portrait
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var shield_label: Label = %ShieldLabel
@onready var feedback_label: Label = %FeedbackLabel

# 缓存基础外观和当前反馈动画，避免连续反馈互相覆盖后残留状态。
var _max_health := 1
var _portrait_tint := Color.WHITE
var _flash_tween: Tween
var _feedback_tween: Tween


# 按战斗位置压缩角色信息：敌人保留头像和全部状态，玩家在底部只显示生命条与数值。
func set_battle_layout_role(role: BattleLayoutRole) -> void:
	var margin := $Margin as MarginContainer
	var content := $Margin/Content as VBoxContainer
	match role:
		BattleLayoutRole.ENEMY:
			custom_minimum_size = Vector2(128, 178)
			var enemy_panel := StyleBoxFlat.new()
			enemy_panel.bg_color = Color(0.04, 0.08, 0.12, 0.32)
			enemy_panel.corner_radius_top_left = 4
			enemy_panel.corner_radius_top_right = 4
			enemy_panel.corner_radius_bottom_left = 4
			enemy_panel.corner_radius_bottom_right = 4
			add_theme_stylebox_override("panel", enemy_panel)
			margin.add_theme_constant_override("margin_left", 4)
			margin.add_theme_constant_override("margin_top", 2)
			margin.add_theme_constant_override("margin_right", 4)
			margin.add_theme_constant_override("margin_bottom", 2)
			content.add_theme_constant_override("separation", 1)
			portrait.custom_minimum_size = Vector2(48, 72)
			feedback_label.custom_minimum_size = Vector2(0, 20)
			name_label.add_theme_font_size_override("font_size", 16)
			health_label.add_theme_font_size_override("font_size", 12)
			shield_label.add_theme_font_size_override("font_size", 13)
			# 敌方生命和护盾放在头像上方，保持与参考图相同的自上而下阅读顺序。
			content.move_child(health_bar, 1)
			content.move_child(health_label, 2)
			content.move_child(shield_label, 3)
			content.move_child(portrait, 4)
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
	name_label.text = display_name
	_max_health = maxi(max_health, 1)
	_portrait_tint = portrait_tint
	portrait.modulate = _portrait_tint
	health_bar.max_value = _max_health
	set_health(_max_health)
	set_shield(0)


# 更新生命条与文本，数值会限制在合法范围内。
func set_health(current_health: int) -> void:
	var safe_health := clampi(current_health, 0, _max_health)
	health_bar.value = safe_health
	health_label.text = "%d / %d" % [safe_health, _max_health]


# 更新护盾显示。
func set_shield(shield: int) -> void:
	shield_label.text = "护盾  %d" % maxi(shield, 0)


# 返回头像的全局中心，供足球表现层把命中位置绑定到实际布局而不是写死坐标。
func get_portrait_global_center() -> Vector2:
	return portrait.get_global_rect().get_center()


# 播放红色受击反馈。
func show_damage(amount: int) -> void:
	_play_feedback("-%d" % amount, Color(1.0, 0.32, 0.28), Color(1.0, 0.35, 0.35))


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
