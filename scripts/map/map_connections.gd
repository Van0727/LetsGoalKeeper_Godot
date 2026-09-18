# 地图连线表现层：读取房间按钮位置和 MapState 连接数据，只负责绘制，不修改路线状态。
extends Control

var _room_buttons: Dictionary = {}
var _map_state: RefCounted
var route_texture: Texture2D


# 分辨率或拉伸比例变化时重新读取按钮位置，保持移动端不同纵横比下连线对齐。
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var path := "res://assets/ui/map/route_line_v2.png"
	route_texture = load(path) if ResourceLoader.exists(path) else null
	resized.connect(queue_redraw)


# 接收地图界面已创建的按钮映射；容器完成布局后由调用方触发重绘。
func configure(room_buttons: Dictionary, map_state: RefCounted) -> void:
	_room_buttons = room_buttons
	_map_state = map_state
	queue_redraw()


# 按真实稀疏路线连接圆盘边缘；竖线纹理旋转拉长，缺失时回退普通线。
func _draw() -> void:
	if _map_state == null:
		return
	var canvas_inverse: Transform2D = get_global_transform_with_canvas().affine_inverse()
	for room in _map_state.rooms:
		var source_button: Button = _room_buttons.get(room.id)
		if source_button == null:
			continue
		for target_id in room.connections:
			var target_button: Button = _room_buttons.get(target_id)
			if target_button == null:
				continue
			var source_rect := source_button.get_global_rect()
			var target_rect := target_button.get_global_rect()
			# 中心使用完整变换，包含围绕圆盘中心的节拍缩放；端点随圆盘边缘同步移动。
			var start: Vector2 = canvas_inverse * source_button.get_global_transform_with_canvas() * source_button.node_center()
			var finish: Vector2 = canvas_inverse * target_button.get_global_transform_with_canvas() * target_button.node_center()
			var direction := (finish - start).normalized()
			start += direction * source_rect.size.y * 0.3
			finish -= direction * target_rect.size.y * 0.3
			if route_texture != null:
				draw_set_transform(start, direction.angle() - PI * 0.5)
				draw_texture_rect(route_texture, Rect2(-3, 0, 6, start.distance_to(finish)), false)
				draw_set_transform(Vector2.ZERO)
			else:
				draw_line(start, finish, Color(0.3, 0.95, 1), 2, true)
			draw_circle(start, 2, Color(0.75, 1, 1))
			draw_circle(finish, 2, Color(0.75, 1, 1))
