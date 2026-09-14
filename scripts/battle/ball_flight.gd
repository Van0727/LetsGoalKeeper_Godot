# 足球飞行表现组件：复刻 Unity 原版的弹道与形变，并在起脚、命中帧播放对应音效，不参与伤害计算。
class_name BallFlight
extends Node2D

signal shot_started(actual_shot_type: int)
# 命中信号在飞行动画完成、战斗界面刷新受击反馈之前发出，供后续震屏或粒子效果复用。
signal shot_impacted

const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const BALL_TEXTURE := preload("res://assets/football.png")
const BALL_SHADER := preload("res://shaders/ball_texture.gdshader")
const BASE_BALL_SCALE := Vector2(0.32, 0.32)
const STRAIGHT_DURATION := 0.5
const BANANA_DURATION := 0.75
const LOB_DURATION := 1.0
const SPINS_PER_SECOND := 3.0
const BALL_DIAMETER := 134.0
const MESH_SEGMENTS := 12
const BANANA_BEND_PIXELS := 30.0

@onready var deform_pivot: Node2D = $DeformPivot
@onready var ball_slices: Node2D = $DeformPivot/BallSlices
@onready var kick_audio: AudioStreamPlayer = $KickAudio
@onready var hit_audio: AudioStreamPlayer = $HitAudio

# 测试可提高播放速度，但正式场景保持 1.0，确保时长与 Unity 原版一致。
var playback_speed := 1.0
var last_actual_shot_type := CARD_DEFINITION.ShotType.NONE
var last_banana_direction := 0

var _start_position := Vector2.ZERO
var _control_position := Vector2.ZERO
var _end_position := Vector2.ZERO
var _ball_material: ShaderMaterial
var _texture_angle := 0.0:
	set(value):
		_texture_angle = value
		if is_instance_valid(_ball_material):
			_ball_material.set_shader_parameter("texture_angle", _texture_angle)
var _path_progress := 0.0:
	set(value):
		_path_progress = value
		global_position = sample_quadratic_bezier(
			_start_position,
			_control_position,
			_end_position,
			_path_progress
		)


# 每个足球实例持有独立材质，确保并发或多段射门时纹理角度互不干扰。
func _ready() -> void:
	_ball_material = ShaderMaterial.new()
	_ball_material.shader = BALL_SHADER
	_ball_material.set_shader_parameter("ball_texture", BALL_TEXTURE)
	_ball_material.set_shader_parameter("texture_angle", 0.0)
	_build_ball_mesh(0)


# 播放一次射门并等待足球抵达目标；实战使用已解析球型与方向，独立调用时保留视觉随机回退。
func play_shot(
		shot_type: int,
		start_position: Vector2,
		end_position: Vector2,
		rng: RandomNumberGenerator,
		super_shot := false,
		flight_duration_seconds := -1.0,
		timing_clock = null,
		launch_music_time := -1.0,
		hit_music_time := -1.0,
		play_impact_on_animation_end := true,
		super_scale_multiplier := 2.0,
		banana_direction_override := 0
) -> void:
	var visual_rng := rng if rng != null else RandomNumberGenerator.new()
	var resolved := _resolve_visual_shot(shot_type, visual_rng, banana_direction_override)
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
	_texture_angle = 0.0
	_build_ball_mesh(last_banana_direction if last_actual_shot_type == CARD_DEFINITION.ShotType.BANANA else 0)
	var active_super_scale := super_scale_multiplier if super_shot else 1.0
	deform_pivot.scale = BASE_BALL_SCALE * active_super_scale
	# 起脚音必须与足球出现和 shot_started 同帧发生，不能等待伤害结算或下一次音频拍点。
	kick_audio.play()
	shot_started.emit(last_actual_shot_type)

	# 负值保留旧调用方的球种默认时长；攻击卡传入按 BPM 换算后的配置时长。
	var configured_duration := (
		get_shot_duration(last_actual_shot_type)
		if flight_duration_seconds < 0.0
		else flight_duration_seconds
	)
	var duration := maxf(configured_duration, 0.001) / maxf(playback_speed, 0.01)
	var spin_direction := get_spin_direction(last_actual_shot_type, last_banana_direction)
	_play_scale_animation(last_actual_shot_type, duration, super_shot, super_scale_multiplier)
	if timing_clock != null and is_equal_approx(playback_speed, 1.0) and hit_music_time >= 0.0:
		await _play_music_synced_motion(
			timing_clock,
			launch_music_time,
			hit_music_time,
			configured_duration,
			spin_direction
		)
	else:
		var motion_tween := create_tween().set_parallel(true)
		motion_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		motion_tween.tween_property(self, "_path_progress", 1.0, duration)
		if not is_zero_approx(spin_direction):
			motion_tween.tween_property(
				self,
				"_texture_angle",
				TAU * SPINS_PER_SECOND * configured_duration * spin_direction,
				duration
			)
		await motion_tween.finished
	# 独立预览仍可在动画结束时自动播放；实战由音频时间轴在目标拍点主动调用。
	if play_impact_on_animation_end:
		play_impact_feedback()
	visible = false


# 命中音与命中信号可由战斗时间轴独立触发，不要求足球动画已经播放完成。
func play_impact_feedback() -> void:
	hit_audio.play()
	shot_impacted.emit()


# 实战使用统一多声部播放器发声时，足球只广播命中时刻，避免每个临时实例管理音频生命周期。
func notify_impact() -> void:
	shot_impacted.emit()


# 正式战斗每帧直接读取 BGM 播放头；掉帧后会跳到正确进度，并在目标音频拍点立即命中。
func _play_music_synced_motion(
		timing_clock,
		launch_music_time: float,
		hit_music_time: float,
		configured_duration: float,
		spin_direction: float
) -> void:
	var time_span := maxf(hit_music_time - launch_music_time, 0.001)
	while timing_clock.get_music_time() < hit_music_time:
		var linear_progress := clampf(
			(timing_clock.get_music_time() - launch_music_time) / time_span,
			0.0,
			1.0
		)
		# 与原 Tween 的 Sine Ease-In 曲线一致，仅替换时间来源。
		_path_progress = 1.0 - cos(linear_progress * PI * 0.5)
		_texture_angle = (
			TAU * SPINS_PER_SECOND * configured_duration * spin_direction * linear_progress
		)
		await get_tree().process_frame
	_path_progress = 1.0


# 返回各弹道的标准时长，供表现队列和测试共享同一份规则。
static func get_shot_duration(shot_type: int) -> float:
	match shot_type:
		CARD_DEFINITION.ShotType.BANANA:
			return BANANA_DURATION
		CARD_DEFINITION.ShotType.LOB:
			return LOB_DURATION
		_:
			return STRAIGHT_DURATION


# 直球只旋转内层纹理、外层形变轴保持水平；左右香蕉球采用相反侧旋，挑射保留向前旋转。
static func get_spin_direction(shot_type: int, banana_direction: int) -> float:
	match shot_type:
		CARD_DEFINITION.ShotType.STRAIGHT:
			return 1.0
		CARD_DEFINITION.ShotType.BANANA:
			return -1.0 if banana_direction < 0 else 1.0
		CARD_DEFINITION.ShotType.LOB:
			return 1.0
		_:
			return 0.0


# 所有压扁形变保持 X+Y=2：一轴减少多少，另一轴就增加多少，避免视觉面积剧烈波动。
static func get_deform_ratio(shot_type: int) -> Vector2:
	match shot_type:
		CARD_DEFINITION.ShotType.STRAIGHT:
			return _balanced_ratio(0.7)
		CARD_DEFINITION.ShotType.BANANA:
			return _balanced_ratio(0.8)
		_:
			return Vector2.ONE


# 根据指定 X 比例计算守恒的 Y 比例，后续新增形变统一通过这里生成。
static func _balanced_ratio(x_ratio: float) -> Vector2:
	var safe_x := clampf(x_ratio, 0.1, 1.9)
	return Vector2(safe_x, 2.0 - safe_x)


# 月牙弯曲在上下边缘归零、球心达到最大值；方向参数保证左右效果严格镜像。
static func sample_banana_bend(normalized_y: float, direction: int) -> float:
	var centered_y := clampf(normalized_y, 0.0, 1.0) * 2.0 - 1.0
	var center_weight := 1.0 - centered_y * centered_y
	return BANANA_BEND_PIXELS * center_weight * signi(direction)


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


# RANDOM 等概率映射到直球、挑射、左香蕉和右香蕉；普通香蕉优先服从核心方向，未指定时才随机。
func _resolve_visual_shot(
		shot_type: int,
		rng: RandomNumberGenerator,
		banana_direction_override := 0
) -> Dictionary:
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
			# 核心上下文指定方向时表现必须服从；0 才保留旧版随机方向。
			"banana_direction": signi(banana_direction_override) if banana_direction_override != 0 else (-1 if rng.randi_range(0, 1) == 0 else 1),
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


# 直球和香蕉球使用守恒比例全程压扁；挑射的等比缩放属于远近变化，不计入形变守恒。
func _play_scale_animation(
		shot_type: int,
		duration: float,
		super_shot: bool,
		super_scale_multiplier := 2.0
) -> void:
	var base_scale := BASE_BALL_SCALE * (super_scale_multiplier if super_shot else 1.0)
	match shot_type:
		CARD_DEFINITION.ShotType.BANANA:
			var banana_scale_tween := create_tween()
			banana_scale_tween.tween_property(
				deform_pivot,
				"scale",
				base_scale * get_deform_ratio(shot_type),
				minf(0.1 / maxf(playback_speed, 0.01), duration)
			)
		CARD_DEFINITION.ShotType.LOB:
			var lob_scale_tween := create_tween()
			lob_scale_tween.tween_property(deform_pivot, "scale", base_scale * 2.0, duration * 0.85)
			lob_scale_tween.tween_property(deform_pivot, "scale", base_scale, duration * 0.15)
		_:
			var straight_scale_tween := create_tween()
			straight_scale_tween.tween_property(
				deform_pivot,
				"scale",
				base_scale * get_deform_ratio(shot_type),
				minf(0.12 / maxf(playback_speed, 0.01), duration)
			)


# 生成多条连续横向网格片；香蕉球只移动各切片边界，纹理旋转不会改变月牙外轮廓。
func _build_ball_mesh(banana_direction: int) -> void:
	for child in ball_slices.get_children():
		child.free()
	for row in range(MESH_SEGMENTS):
		var top_ratio := float(row) / float(MESH_SEGMENTS)
		var bottom_ratio := float(row + 1) / float(MESH_SEGMENTS)
		var top_y := (top_ratio - 0.5) * BALL_DIAMETER
		var bottom_y := (bottom_ratio - 0.5) * BALL_DIAMETER
		var top_bend := sample_banana_bend(top_ratio, banana_direction)
		var bottom_bend := sample_banana_bend(bottom_ratio, banana_direction)
		var half_size := BALL_DIAMETER * 0.5
		var slice := Polygon2D.new()
		slice.polygon = PackedVector2Array([
			Vector2(-half_size + top_bend, top_y),
			Vector2(half_size + top_bend, top_y),
			Vector2(half_size + bottom_bend, bottom_y),
			Vector2(-half_size + bottom_bend, bottom_y),
		])
		# Polygon2D 使用纹理像素坐标；所有切片共享整球 UV，旋转后花纹仍连续。
		slice.uv = PackedVector2Array([
			Vector2(0.0, top_ratio * BALL_DIAMETER),
			Vector2(BALL_DIAMETER, top_ratio * BALL_DIAMETER),
			Vector2(BALL_DIAMETER, bottom_ratio * BALL_DIAMETER),
			Vector2(0.0, bottom_ratio * BALL_DIAMETER),
		])
		slice.texture = BALL_TEXTURE
		slice.material = _ball_material
		ball_slices.add_child(slice)
