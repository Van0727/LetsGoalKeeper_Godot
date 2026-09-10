# 战斗节奏反馈控件：用图片节点表现向拍点收缩的圆环，并显示出牌等级与时差。
class_name RhythmFeedback
extends Control

const PERFECT_COLOR := Color(1.0, 0.82, 0.25, 1.0)
const GOOD_COLOR := Color(0.3, 0.9, 0.82, 1.0)
const MISS_COLOR := Color(1.0, 0.42, 0.42, 1.0)

@onready var beat_label: Label = %BeatLabel
@onready var judgement_label: Label = %JudgementLabel
@onready var target_ring: TextureRect = %TargetRing
@onready var moving_ring: TextureRect = %MovingRing
@onready var beat_flash: TextureRect = %BeatFlash

var _beat_progress := 0.0
var _beat_flash := 0.0
var _feedback_tween: Tween
var _circle_enabled := true


# 初始只显示 BPM 提示，判定文字留空直到玩家首次有效出牌。
func _ready() -> void:
	judgement_label.text = ""
	_refresh_ring_images()


# 脉冲亮度随真实时间衰减，不改变节拍环的逻辑进度。
func _process(delta: float) -> void:
	if _beat_flash <= 0.0:
		return
	_beat_flash = maxf(_beat_flash - delta * 4.0, 0.0)
	_refresh_ring_images()


# 战斗界面每帧传入音频时钟进度，使圆环在下个目标拍点前收缩。
func set_beat_progress(progress: float) -> void:
	_beat_progress = clampf(progress, 0.0, 1.0)
	_refresh_ring_images()


# 波形样式下只隐藏圆环图片，拍位与判定文字继续提供相同反馈信息。
func set_circle_enabled(enabled: bool) -> void:
	_circle_enabled = enabled
	target_ring.visible = enabled
	moving_ring.visible = enabled
	beat_flash.visible = enabled and _beat_flash > 0.0


# 新拍到达时产生短促亮度脉冲；拍点序号只用于给玩家显示当前小节位置。
func pulse_beat(beat_index: int, beats_per_bar: int) -> void:
	_beat_flash = 1.0
	beat_label.text = "BEAT  %d/%d" % [beat_index % maxi(beats_per_bar, 1) + 1, maxi(beats_per_bar, 1)]
	_refresh_ring_images()


# 松手后显示等级与偏差方向；动画只负责反馈，不推迟或更改已经完成的结算。
func show_judgement(result: Dictionary) -> void:
	var grade_name: String = result.get("grade_name", "Miss")
	var error_ms: float = result.get("error_ms", 0.0)
	var timing_text := "准拍"
	if absf(error_ms) >= 0.5:
		timing_text = "%s %.0fms" % ["晚" if error_ms > 0.0 else "早", absf(error_ms)]
	judgement_label.text = "%s · %s" % [grade_name, timing_text]
	match grade_name:
		"Perfect": judgement_label.modulate = PERFECT_COLOR
		"Good": judgement_label.modulate = GOOD_COLOR
		_: judgement_label.modulate = MISS_COLOR
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	judgement_label.scale = Vector2(1.18, 1.18)
	judgement_label.modulate.a = 1.0
	_feedback_tween = create_tween()
	_feedback_tween.set_parallel(true)
	_feedback_tween.tween_property(judgement_label, "scale", Vector2.ONE, 0.16)
	_feedback_tween.tween_property(judgement_label, "modulate:a", 0.72, 0.7).set_delay(0.8)


# 圆环图片从外圈向固定目标圈收缩；只改变节点矩形和透明度，不再使用自定义绘制。
func _refresh_ring_images() -> void:
	var center := size * 0.5
	var target_radius := 18.0
	var moving_radius := lerpf(42.0, target_radius, _beat_progress)
	_set_centered_square(target_ring, center, target_radius * 2.0)
	_set_centered_square(moving_ring, center, moving_radius * 2.0)
	moving_ring.modulate.a = 0.65 + _beat_flash * 0.35
	var flash_size := (10.0 + _beat_flash * 8.0) * 2.0
	_set_centered_square(beat_flash, center, flash_size)
	beat_flash.modulate.a = _beat_flash * 0.35
	target_ring.visible = _circle_enabled
	moving_ring.visible = _circle_enabled
	beat_flash.visible = _circle_enabled and _beat_flash > 0.0


func _set_centered_square(node: Control, center: Vector2, diameter: float) -> void:
	node.position = center - Vector2.ONE * diameter * 0.5
	node.size = Vector2.ONE * diameter
