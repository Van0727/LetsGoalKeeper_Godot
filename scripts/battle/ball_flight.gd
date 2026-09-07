# 足球飞行表现组件：复刻 Unity 原版的贝塞尔弹道、旋转、挤压和挑射缩放，不参与伤害计算。
class_name BallFlight
extends Node2D

signal shot_started(actual_shot_type: int)

const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const BASE_BALL_SCALE := Vector2(0.32, 0.32)
const STRAIGHT_DURATION := 0.5
const BANANA_DURATION := 0.75
const LOB_DURATION := 1.0
const SPINS_PER_SECOND := 3.0

@onready var deform_pivot: Node2D = $DeformPivot
@onready var ball_sprite: Sprite2D = $DeformPivot/BallSprite

# 测试可提高播放速度，但正式场景保持 1.0，确保时长与 Unity 原版一致。
var playback_speed := 1.0
var last_actual_shot_type := CARD_DEFINITION.ShotType.NONE
var last_banana_direction := 0

var _start_position := Vector2.ZERO
var _control_position := Vector2.ZERO
var _end_position := Vector2.ZERO
var _path_progress := 0.0:
	set(value):
		_path_progress = value
		global_position = sample_quadratic_bezier(
			_start_position,
			_control_position,
			_end_position,
			_path_progress
		)


# 播放一次射门并等待足球抵达目标；随机射门只影响表现，不消耗战斗核心随机数。
func play_shot(
		shot_type: int,
		start_position: Vector2,
		end_position: Vector2,
		rng: RandomNumberGenerator,
		super_shot := false
) -> void:
	var visual_rng := rng if rng != null else RandomNumberGenerator.new()
	var resolved := _resolve_visual_shot(shot_type, visual_rng)
	last_actual_shot_type = resolved.shot_type
	last_banana_direction = resolved.banana_direction
	_start_position = start_position
	_end_position = end_position
	_control_position = _build_control_point(
		last_actual_shot_type,
		last_banana_direction,
		start_position,
		end_position,
		visual_rng
	)
	_path_progress = 0.0
	visible = true
	ball_sprite.rotation = 0.0
	deform_pivot.scale = BASE_BALL_SCALE * (2.0 if super_shot else 1.0)
	shot_started.emit(last_actual_shot_type)

	var duration := get_shot_duration(last_actual_shot_type) / maxf(playback_speed, 0.01)
	var motion_tween := create_tween().set_parallel(true)
	motion_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	motion_tween.tween_property(self, "_path_progress", 1.0, duration)
	var spin_direction := get_spin_direction(last_actual_shot_type, last_banana_direction)
	if not is_zero_approx(spin_direction):
		motion_tween.tween_property(
			ball_sprite,
			"rotation",
			TAU * SPINS_PER_SECOND * get_shot_duration(last_actual_shot_type) * spin_direction,
			duration
		)
	_play_scale_animation(last_actual_shot_type, duration, super_shot)
	await motion_tween.finished
	visible = false


# 返回各弹道的标准时长，供表现队列和测试共享同一份规则。
static func get_shot_duration(shot_type: int) -> float:
	match shot_type:
		CARD_DEFINITION.ShotType.BANANA:
			return BANANA_DURATION
		CARD_DEFINITION.ShotType.LOB:
			return LOB_DURATION
		_:
			return STRAIGHT_DURATION


# 直球不自旋；左右香蕉球采用相反侧旋，挑射保留原版向前旋转。
static func get_spin_direction(shot_type: int, banana_direction: int) -> float:
	match shot_type:
		CARD_DEFINITION.ShotType.BANANA:
			return -1.0 if banana_direction < 0 else 1.0
		CARD_DEFINITION.ShotType.LOB:
			return 1.0
		_:
			return 0.0


# 二次贝塞尔采样保持为纯函数，便于验证起点、终点和曲线路径边界。
static func sample_quadratic_bezier(
		start_position: Vector2,
		control_position: Vector2,
		end_position: Vector2,
		t: float
) -> Vector2:
	var safe_t := clampf(t, 0.0, 1.0)
	var inverse := 1.0 - safe_t
	return (
		inverse * inverse * start_position
		+ 2.0 * inverse * safe_t * control_position
		+ safe_t * safe_t * end_position
	)


# RANDOM 等概率映射到直球、挑射、左香蕉和右香蕉；普通香蕉独立随机左右方向。
func _resolve_visual_shot(shot_type: int, rng: RandomNumberGenerator) -> Dictionary:
	if shot_type == CARD_DEFINITION.ShotType.RANDOM:
		match rng.randi_range(0, 3):
			0:
				return {"shot_type": CARD_DEFINITION.ShotType.STRAIGHT, "banana_direction": 0}
			1:
				return {"shot_type": CARD_DEFINITION.ShotType.LOB, "banana_direction": 0}
			2:
				return {"shot_type": CARD_DEFINITION.ShotType.BANANA, "banana_direction": -1}
			_:
				return {"shot_type": CARD_DEFINITION.ShotType.BANANA, "banana_direction": 1}
	if shot_type == CARD_DEFINITION.ShotType.BANANA:
		return {
			"shot_type": shot_type,
			"banana_direction": -1 if rng.randi_range(0, 1) == 0 else 1,
		}
	return {"shot_type": shot_type, "banana_direction": 0}


# 将 Unity 世界坐标中的控制点幅度换算成屏幕比例，保留直球轻偏、香蕉大弧和挑射高弧。
func _build_control_point(
		shot_type: int,
		banana_direction: int,
		start_position: Vector2,
		end_position: Vector2,
		rng: RandomNumberGenerator
) -> Vector2:
	var midpoint := (start_position + end_position) * 0.5
	var travel_height := absf(end_position.y - start_position.y)
	match shot_type:
		CARD_DEFINITION.ShotType.BANANA:
			var side_offset := rng.randf_range(travel_height * 0.38, travel_height * 0.62)
			return midpoint + Vector2(side_offset * banana_direction, -travel_height * 0.18)
		CARD_DEFINITION.ShotType.LOB:
			return midpoint + Vector2(
				rng.randf_range(-travel_height * 0.20, travel_height * 0.20),
				-travel_height * 0.30
			)
		_:
			return midpoint + Vector2(
				rng.randf_range(-travel_height * 0.12, travel_height * 0.12),
				-travel_height * 0.10
			)


# 直球只做一次挤压再恢复且不旋转；香蕉球保持圆形侧旋；挑射放大后在落点前恢复。
func _play_scale_animation(shot_type: int, duration: float, super_shot: bool) -> void:
	var base_scale := BASE_BALL_SCALE * (2.0 if super_shot else 1.0)
	match shot_type:
		CARD_DEFINITION.ShotType.BANANA:
			# 侧旋时保持圆形，避免非等比缩放轴与球面旋转叠加成“旋转的扁饼”。
			deform_pivot.scale = base_scale
		CARD_DEFINITION.ShotType.LOB:
			var lob_scale_tween := create_tween()
			lob_scale_tween.tween_property(deform_pivot, "scale", base_scale * 2.0, duration * 0.85)
			lob_scale_tween.tween_property(deform_pivot, "scale", base_scale, duration * 0.15)
		_:
			var straight_scale_tween := create_tween()
			straight_scale_tween.tween_property(
				deform_pivot,
				"scale",
				base_scale * Vector2(0.7, 1.3),
				minf(0.12 / maxf(playback_speed, 0.01), duration * 0.5)
			)
			straight_scale_tween.tween_property(
				deform_pivot,
				"scale",
				base_scale,
				minf(0.13 / maxf(playback_speed, 0.01), duration * 0.5)
			)
