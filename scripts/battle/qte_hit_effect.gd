# QTE判定瞬时特效：由战斗根节点承载，最后一音关闭弹窗后仍独立播完；不接收输入、不参与结算。
extends Node2D

const DURATION := 0.34
var age := 0.0
var effect_color := Color.WHITE
var missed := false

# 参数只记录当次判定的颜色与结果，后续主动技切换类型不回染尚未结束的特效。
func configure(color: Color, is_miss: bool) -> void:
	effect_color = color
	missed = is_miss
	queue_redraw()

func _process(delta: float) -> void:
	age += maxf(delta, 0.0)
	if age >= DURATION:
		queue_free()
	else:
		queue_redraw()

# 成功为扩散双环、中心闪光和八向火花；Miss收缩暗环，避免失败也像成功爆发。
func _draw() -> void:
	var progress := clampf(age / DURATION, 0.0, 1.0)
	var fade := 1.0 - progress
	if missed:
		draw_arc(Vector2.ZERO, lerpf(25, 12, progress), 0, TAU, 64, Color(effect_color.darkened(0.55), fade * 0.8), 4, true)
		return
	var radius := lerpf(18, 48, progress)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 80, Color(effect_color, fade * 0.85), 5 * fade + 1, true)
	draw_arc(Vector2.ZERO, radius * 0.77, 0, TAU, 80, Color(effect_color.lightened(0.25), fade), 2, true)
	var flash := maxf(1.0 - progress * 4.0, 0.0)
	draw_circle(Vector2.ZERO, 16 * flash, Color(effect_color.lightened(0.35), flash * 0.8), true, -1, true)
	for index in range(8):
		var direction := Vector2.from_angle(TAU * index / 8.0 + PI * 0.125)
		draw_line(direction * (radius + 3), direction * (radius + 3 + 12 * fade), Color(effect_color.lightened(0.15), fade), 3 * fade + 1, true)
