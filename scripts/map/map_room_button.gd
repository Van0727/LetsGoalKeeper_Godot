# 舞台地图节点：代码绘制统一底座和状态光圈，只显示房型头像，不修改玩法状态。
extends Button

signal pulse_transform_changed
const MAP_STATE := preload("res://scripts/map/map_state.gd")
var _pulse_tween: Tween

var kind := 0
var status := 0
var art: Dictionary = {}
var title_label: Label

# 名称仅作为 Tooltip 数据源保留，地图节点本身只显示头像和状态底座。
func configure(room: Dictionary, title: String, textures: Dictionary) -> void:
	kind = room.type
	status = room.state
	art = textures
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(key, StyleBoxEmpty.new())
	title_label = Label.new()
	title_label.name = "OpponentName"
	title_label.text = title
	title_label.hide()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_label)
	resized.connect(_layout_node)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	_layout_node()

# 圆盘中心用于连线，名称不参与中心计算。
func node_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.43)

# 节点缩放仍围绕圆台中心进行，隐藏名称后不再预留或布局名称牌区域。
func _layout_node() -> void:
	pivot_offset = node_center()

# 每拍重建短动画，圆台与头像一起缩放；绑定节点保证暂停与释放时停止。
func pulse(peak: float) -> void:
	if disabled:
		stop_pulse()
		return
	if _pulse_tween != null:
		_pulse_tween.kill()
	_pulse_tween = create_tween().bind_node(self)
	_pulse_tween.set_trans(Tween.TRANS_SINE)
	_pulse_tween.set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_method(_set_pulse_scale, scale.x, peak, 0.16)
	_pulse_tween.set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_method(_set_pulse_scale, peak, 1.0, 0.34)

# 进入房间或刷新界面时恢复静止尺寸，避免过场残留放大状态。
func stop_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	_set_pulse_scale(1.0)

func _set_pulse_scale(value: float) -> void:
	scale = Vector2.ONE * value
	pulse_transform_changed.emit()

# 底座承担图标与舞台的视觉过渡；状态通过光圈和整体亮度表达，避免头像像贴纸悬浮。
func _draw() -> void:
	var side := size.y * 0.88
	var boss := kind == MAP_STATE.RoomType.BOSS
	var locked := status == MAP_STATE.RoomState.LOCKED
	var visited := status == MAP_STATE.RoomState.VISITED
	var accent := _accent_color()
	var center := node_center()
	var radius := side * (0.33 if boss else 0.31)
	var state_alpha := 0.42 if locked else (0.62 if visited else 1.0)
	# 接触阴影、暗色圆台与双层描边把图标固定在舞台节点上。
	draw_ellipse(center + Vector2(0, radius * 0.34), radius * 1.18, radius * 0.54, Color(0, 0, 0, 0.42), true, -1.0, true)
	draw_circle(center, radius * 1.18, Color(0.012, 0.018, 0.045, 0.94))
	draw_circle(center, radius, Color(0.045, 0.06, 0.12, 0.98))
	draw_arc(center, radius * 1.08, 0, TAU, 48, Color(accent, state_alpha), 2.4, true)
	if status == MAP_STATE.RoomState.ATTAINABLE:
		draw_arc(center, radius * 1.28, -PI * 0.82, PI * 0.18, 28, Color(accent.lightened(0.2), 0.72), 2.0, true)
	var tint := Color(0.48, 0.52, 0.6, 0.78) if locked else (Color(0.7, 0.72, 0.78, 0.82) if visited else Color.WHITE)
	# 普通与精英房使用各自的通用剪影；实际怪物身份仍由名称和遭遇规划器表达。
	if boss:
		_paint("boss", side * 0.7, tint)
	elif kind == MAP_STATE.RoomType.REST:
		_paint("heart", side * 0.66, tint)
	else:
		var monster_key := "elite" if kind == MAP_STATE.RoomType.ELITE else "monster"
		_paint(monster_key, side * 0.66, tint)
	if has_focus() or (not disabled and is_hovered()):
		draw_arc(center, radius * 1.34, 0, TAU, 48, Color(1.0, 0.84, 0.42), 1.8, true)
	if visited:
		draw_circle(center + Vector2(radius * 0.78, -radius * 0.78), 3.2, Color(0.42, 0.9, 0.78))

# 图标保持自身比例并收在圆台内部；资源缺失时仍保留底座和完整输入区域。
func _paint(key: String, side: float, tint: Color) -> void:
	var texture: Texture2D = art.get(key)
	if texture == null:
		return
	var factor := side / maxf(texture.get_width(), texture.get_height())
	var fitted := Vector2(texture.get_size()) * factor
	var icon_offset := Vector2(0, -2)
	draw_texture_rect(texture, Rect2(node_center() + icon_offset - fitted * 0.5, fitted), false, tint)


# 房型强调色只服务于节点底座，实际图标配色保持美术资源本身的辨识度。
func _accent_color() -> Color:
	match kind:
		MAP_STATE.RoomType.ELITE:
			return Color(1.0, 0.3, 0.2)
		MAP_STATE.RoomType.BOSS:
			return Color(1.0, 0.68, 0.2)
		MAP_STATE.RoomType.REST:
			return Color(0.25, 0.9, 0.72)
		_:
			return Color(0.2, 0.78, 0.95)

# 项目盾牌占位图仅为菱形，因此由 UI 绘制紫色盾牌和五角星，不新增或覆盖美术图片。
func _draw_shield(radius: float) -> void:
	var points := PackedVector2Array()
	for p in [Vector2(-0.9,-0.9), Vector2(0,-1.1), Vector2(0.9,-0.9), Vector2(0.75,0.35), Vector2(0,1), Vector2(-0.75,0.35)]:
		points.append(node_center() + p * radius)
	draw_colored_polygon(points, Color(0.62, 0.12, 0.92))
	points.append(points[0])
	draw_polyline(points, Color(0.9, 0.65, 1), 1.5, true)
	var star := PackedVector2Array()
	for i in range(10):
		star.append(node_center() + Vector2.from_angle(-PI * 0.5 + i * PI / 5) * radius * (0.62 if i % 2 == 0 else 0.28))
	draw_colored_polygon(star, Color.WHITE)
