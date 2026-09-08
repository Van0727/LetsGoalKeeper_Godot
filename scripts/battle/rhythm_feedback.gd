# 战斗节奏反馈控件：绘制向拍点收缩的圆环，并即时显示出牌等级与提前/延后误差。
class_name RhythmFeedback
extends Control

const PERFECT_COLOR := Color(1.0, 0.82, 0.25, 1.0)
const GOOD_COLOR := Color(0.3, 0.9, 0.82, 1.0)
const MISS_COLOR := Color(1.0, 0.42, 0.42, 1.0)

@onready var beat_label: Label = %BeatLabel
@onready var judgement_label: Label = %JudgementLabel

var _beat_progress := 0.0
var _beat_flash := 0.0
var _feedback_tween: Tween


# 初始只显示 BPM 提示，判定文字留空直到玩家首次有效出牌。
func _ready() -> void:
	judgement_label.text = ""
	queue_redraw()


# 脉冲亮度随真实时间衰减，不改变节拍环的逻辑进度。
func _process(delta: float) -> void:
	if _beat_flash <= 0.0:
		return
	_beat_flash = maxf(_beat_flash - delta * 4.0, 0.0)
	queue_redraw()


# 战斗界面每帧传入音频时钟进度，使圆环在下个目标拍点前收缩。
func set_beat_progress(progress: float) -> void:
	_beat_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


# 新拍到达时产生短促亮度脉冲；拍点序号只用于给玩家显示当前小节位置。
func pulse_beat(beat_index: int, beats_per_bar: int) -> void:
	_beat_flash = 1.0
	beat_label.text = "BEAT  %d/%d" % [beat_index % maxi(beats_per_bar, 1) + 1, maxi(beats_per_bar, 1)]
	queue_redraw()


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


# 圆环从外圈向固定目标圈收缩；刚过拍点时闪光补足进度瞬间归零的视觉反馈。
func _draw() -> void:
	var center := Vector2(24.0, size.y * 0.5)
	var target_radius := 7.0
	var moving_radius := lerpf(25.0, target_radius, _beat_progress)
	var base_color := Color(0.45, 0.82, 1.0, 0.65 + _beat_flash * 0.35)
	draw_circle(center, target_radius, Color(0.12, 0.26, 0.36, 0.9), false, 2.0)
	draw_circle(center, moving_radius, base_color, false, 2.5 + _beat_flash * 1.5)
	if _beat_flash > 0.0:
		draw_circle(center, 10.0 + _beat_flash * 8.0, Color(1.0, 0.86, 0.35, _beat_flash * 0.35))
