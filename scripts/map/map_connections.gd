# 地图连线表现层：读取房间按钮位置和 MapState 连接数据，只负责绘制，不修改路线状态。
extends Control

var _room_buttons: Dictionary = {}
var _map_state: RefCounted


# 分辨率或拉伸比例变化时重新读取按钮位置，保持移动端不同纵横比下连线对齐。
func _ready() -> void:
	resized.connect(queue_redraw)


# 接收地图界面已创建的按钮映射；容器完成布局后由调用方触发重绘。
func configure(room_buttons: Dictionary, map_state: RefCounted) -> void:
	_room_buttons = room_buttons
	_map_state = map_state
	queue_redraw()


# 按真实连接从上层按钮底部画到下层按钮顶部，让稀疏路线选择在进入前可见。
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
			var start: Vector2 = canvas_inverse * Vector2(source_rect.get_center().x, source_rect.end.y)
			var finish: Vector2 = canvas_inverse * Vector2(target_rect.get_center().x, target_rect.position.y)
			draw_line(start, finish, Color(0.42, 0.72, 0.75, 0.72), 2.0, true)
