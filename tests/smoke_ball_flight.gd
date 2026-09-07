# 足球飞行冒烟测试：验证 Unity 原版时长映射、贝塞尔端点和随机射门的四种表现分支。
extends SceneTree

const BALL_FLIGHT := preload("res://scripts/battle/ball_flight.gd")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")

var _failed := false


# 纯规则测试无需实例化战斗场景，可快速发现弹道数学或时长被误改。
func _initialize() -> void:
	_assert_equal(BALL_FLIGHT.get_shot_duration(CARD_DEFINITION.ShotType.STRAIGHT), 0.5, "直球时长")
	_assert_equal(BALL_FLIGHT.get_shot_duration(CARD_DEFINITION.ShotType.BANANA), 0.75, "香蕉球时长")
	_assert_equal(BALL_FLIGHT.get_shot_duration(CARD_DEFINITION.ShotType.LOB), 1.0, "挑射时长")
	_assert_equal(
		BALL_FLIGHT.get_spin_direction(CARD_DEFINITION.ShotType.STRAIGHT, 0),
		0.0,
		"直球只形变而不自旋"
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
