# 足球飞行冒烟测试：验证起脚/命中音效、弹道时长、守恒压扁、月牙网格、旋转和贝塞尔端点。
extends SceneTree

const BALL_FLIGHT := preload("res://scripts/battle/ball_flight.gd")
const BALL_SCENE := preload("res://scenes/ball_flight.tscn")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")

var _failed := false


# 同时验证弹道纯规则与运行节点的最终形变，避免时长、旋转或缩放规则被误改。
func _initialize() -> void:
	_assert_equal(BALL_FLIGHT.get_shot_duration(CARD_DEFINITION.ShotType.STRAIGHT), 0.5, "直球时长")
	_assert_equal(BALL_FLIGHT.get_shot_duration(CARD_DEFINITION.ShotType.BANANA), 0.75, "香蕉球时长")
	_assert_equal(BALL_FLIGHT.get_shot_duration(CARD_DEFINITION.ShotType.LOB), 1.0, "挑射时长")
	_assert_equal(
		BALL_FLIGHT.get_spin_direction(CARD_DEFINITION.ShotType.STRAIGHT, 0),
		1.0,
		"直球启用内层纹理旋转"
	)
	_assert_equal(
		BALL_FLIGHT.get_spin_direction(CARD_DEFINITION.ShotType.BANANA, -1),
		-1.0,
		"左香蕉球采用左侧旋"
	)
	_assert_equal(
		BALL_FLIGHT.get_spin_direction(CARD_DEFINITION.ShotType.BANANA, 1),
		1.0,
		"右香蕉球采用右侧旋"
	)
	_assert_equal(
		BALL_FLIGHT.get_deform_ratio(CARD_DEFINITION.ShotType.STRAIGHT),
		Vector2(0.7, 1.3),
		"直球形变遵守X减Y增"
	)
	_assert_equal(
		BALL_FLIGHT.get_deform_ratio(CARD_DEFINITION.ShotType.BANANA),
		Vector2(0.8, 1.2),
		"香蕉球形变遵守X减Y增"
	)
	_assert_equal(BALL_FLIGHT.sample_banana_bend(0.0, -1), 0.0, "左月牙顶部不偏移")
	_assert_equal(BALL_FLIGHT.sample_banana_bend(0.5, -1), -30.0, "左月牙中心向左外弯")
	_assert_equal(BALL_FLIGHT.sample_banana_bend(0.5, 1), 30.0, "右月牙中心向右外弯")
	_assert_equal(BALL_FLIGHT.sample_banana_bend(1.0, 1), 0.0, "右月牙底部不偏移")
	var ball = BALL_SCENE.instantiate()
	root.add_child(ball)
	await process_frame
	_assert_equal(ball.rotation, 0.0, "弹道节点不旋转")
	_assert_equal(ball.get_node("DeformPivot").rotation, 0.0, "直球形变轴保持水平")
	_assert_equal(ball.get_node("DeformPivot/BallSlices").get_child_count(), 12, "足球由十二条连续网格片组成")
	_assert_true(ball.kick_audio.stream != null, "足球起飞播放器已绑定kick音效")
	_assert_true(ball.hit_audio.stream != null, "足球命中播放器已绑定hit音效")
	var impact_count := [0]
	ball.shot_impacted.connect(func() -> void: impact_count[0] += 1)
	await ball.play_shot(
		CARD_DEFINITION.ShotType.STRAIGHT,
		Vector2(180.0, 560.0),
		Vector2(180.0, 120.0),
		null
	)
	_assert_true(
		ball.get_node("DeformPivot").scale.is_equal_approx(Vector2(0.224, 0.416)),
		"直球飞行结束保持0.7乘1.3形变"
	)
	_assert_equal(impact_count[0], 1, "每次足球抵达目标只发送一次命中信号")
	# 测试结束前主动停止仍在播放的命中音，避免无窗口运行退出时保留音频播放实例。
	ball.kick_audio.stop()
	ball.hit_audio.stop()
	ball.free()
	await process_frame
	var start := Vector2(180.0, 566.0)
	var control := Vector2(80.0, 260.0)
	var end := Vector2(180.0, 170.0)
	_assert_equal(BALL_FLIGHT.sample_quadratic_bezier(start, control, end, 0.0), start, "贝塞尔起点")
	_assert_equal(BALL_FLIGHT.sample_quadratic_bezier(start, control, end, 1.0), end, "贝塞尔终点")
	_assert_equal(
		BALL_FLIGHT.sample_quadratic_bezier(start, control, end, 0.5),
		Vector2(130.0, 314.0),
		"贝塞尔中点"
	)
	if _failed:
		quit(1)
		return
	print("smoke_ball_flight: PASS")
	quit()


# 通用相等断言，错误时显示实际弹道数据。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言，供浮点近似和几何关系测试使用。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
