# 地图连线表现层：使用暖色节拍轨道连接舞台节点，只负责绘制，不修改路线状态。
extends Control

const MAP_STATE := preload("res://scripts/map/map_state.gd")

var _room_buttons: Dictionary = {}
var _map_state: RefCounted


# 分辨率或拉伸比例变化时重新读取按钮位置，保持移动端不同纵横比下连线对齐。
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)


# 接收地图界面已创建的按钮映射；容器完成布局后由调用方触发重绘。
func configure(room_buttons: Dictionary, map_state: RefCounted) -> void:
	_room_buttons = room_buttons
	_map_state = map_state
	queue_redraw()


# 按真实稀疏路线连接圆盘边缘；锁定路线压暗，可进入或已走通路线使用暖白橙光。
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
			var target_room: Dictionary = _map_state.room_by_id(target_id)
			# 只有从已访问房间通向当前可进入或已访问房间的真实行进路径才发光；
			# 避免目标被另一分支解锁时，把已锁死的来源路线误显示为可走。
			var route_open: bool = (
				room.state == MAP_STATE.RoomState.VISITED
				and target_room.get("state", MAP_STATE.RoomState.LOCKED) in [
					MAP_STATE.RoomState.ATTAINABLE,
					MAP_STATE.RoomState.VISITED,
				]
			)
			var route_color := Color(1.0, 0.72, 0.36, 0.95) if route_open else Color(0.34, 0.38, 0.48, 0.52)
			# 深色宽底线把路线从舞台背景中托起，细暖色线保持参考图的节拍轨道质感。
			draw_line(start, finish, Color(0.015, 0.02, 0.05, 0.82), 6.0, true)
			draw_line(start, finish, route_color, 2.4, true)
			draw_circle(start, 2.6, route_color)
			draw_circle(finish, 2.6, route_color)
