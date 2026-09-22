# 地图节点组合已有底板、图标和名字；原生按钮负责输入和锁定，不修改玩法状态。
extends Button

signal pulse_transform_changed
const MAP_STATE := preload("res://scripts/map/map_state.gd")
var _pulse_tween: Tween

var kind := 0
var status := 0
var art: Dictionary = {}
var title_label: Label

# 名字单独布局，禁用状态不隐藏路线信息。
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
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_font_size_override("font_size", 10)
	add_child(title_label)
	resized.connect(_layout_name)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	_layout_name()

# 圆盘中心用于连线，名称不参与中心计算。
func node_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.43)

func _layout_name() -> void:
	pivot_offset = node_center()
	title_label.position = Vector2(2, size.y * 0.76)
	title_label.size = Vector2(size.x - 4, size.y * 0.24)

# 每拍重建短动画，底板、图标与名字一起缩放；绑定节点保证暂停与释放时停止。
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

# 锁定略降亮度；已完成使用独立小标记，保持图片原色和正常线性过滤。
func _draw() -> void:
	var side := size.y * 0.9
	var boss := kind == 2
	var tint := Color(0.72, 0.78, 0.87) if disabled else Color.WHITE
	_paint("boss_base" if boss else "base", side, tint)
	# 普通与精英房使用各自的通用剪影；实际怪物身份仍由名称和遭遇规划器表达。
	if boss:
		_paint("boss", side * 0.78, tint)
	elif kind == 3:
		_paint("heart", side * 1.2, tint)
	else:
		# 保留用户已调整的1.2倍怪物图标尺寸。
		var monster_key := "elite" if kind == MAP_STATE.RoomType.ELITE else "monster"
		_paint(monster_key, side * 1.2, tint)
	var plate: Texture2D = art.get("boss_name" if boss else "name")
	if plate != null:
		draw_texture_rect(plate, Rect2(0, size.y * 0.75, size.x, size.y * 0.25), false)
	if has_focus() or (not disabled and is_hovered()):
		draw_arc(node_center(), side * 0.43, 0, TAU, 48, Color(0.3, 1, 1), 1.3, true)
	if status == 2:
		draw_circle(node_center() + Vector2(side * 0.28, -side * 0.28), 3, Color(0.35, 1, 0.8))

# 图标保持自身比例；缺失底板时回退圆盘，名字和输入仍可使用。
func _paint(key: String, side: float, tint: Color) -> void:
	var texture: Texture2D = art.get(key)
	if texture == null:
		if key in ["base", "boss_base"]:
			draw_circle(node_center(), side * 0.4, Color(0.02, 0.08, 0.18))
		return
	var factor := side / maxf(texture.get_width(), texture.get_height())
	var fitted := Vector2(texture.get_size()) * factor
	# 两类怪物剪影统一上移10像素，对齐底座视觉重心，不改变连线中心和其他房型图标。
	var icon_offset := Vector2(0, -10) if key in ["monster", "elite"] else Vector2.ZERO
	draw_texture_rect(texture, Rect2(node_center() + icon_offset - fitted * 0.5, fitted), false, tint)

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
