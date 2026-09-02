class_name CharacterDisplay
extends PanelContainer

@onready var name_label: Label = %NameLabel
@onready var portrait: TextureRect = %Portrait
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var shield_label: Label = %ShieldLabel
@onready var feedback_label: Label = %FeedbackLabel

var _max_health := 1
var _portrait_tint := Color.WHITE
var _flash_tween: Tween
var _feedback_tween: Tween


func configure(display_name: String, max_health: int, portrait_tint: Color) -> void:
	name_label.text = display_name
	_max_health = maxi(max_health, 1)
	_portrait_tint = portrait_tint
	portrait.modulate = _portrait_tint
	health_bar.max_value = _max_health
	set_health(_max_health)
	set_shield(0)


func set_health(current_health: int) -> void:
	var safe_health := clampi(current_health, 0, _max_health)
	health_bar.value = safe_health
	health_label.text = "%d / %d" % [safe_health, _max_health]


func set_shield(shield: int) -> void:
	shield_label.text = "护盾  %d" % maxi(shield, 0)


func show_damage(amount: int) -> void:
	_play_feedback("-%d" % amount, Color(1.0, 0.32, 0.28), Color(1.0, 0.35, 0.35))


func show_heal(amount: int) -> void:
	_play_feedback("+%d 生命" % amount, Color(0.3, 1.0, 0.5), Color(0.45, 1.0, 0.55))


func show_shield_gain(amount: int) -> void:
	_play_feedback("+%d 护盾" % amount, Color(0.35, 0.75, 1.0), Color(0.45, 0.78, 1.0))


func show_shield_loss(amount: int) -> void:
	_play_feedback("护盾 -%d" % amount, Color(0.55, 0.82, 1.0), Color(0.45, 0.78, 1.0))


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
