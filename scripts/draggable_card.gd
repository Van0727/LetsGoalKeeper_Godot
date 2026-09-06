# 可拖拽卡牌控件：统一处理鼠标和单指触摸，并支持矩形落点或横向阈值两种出牌判定。
class_name DraggableCard
extends PanelContainer

# 拖拽生命周期供战斗界面高亮出牌区；只有在有效区域释放才发送成功信号。
signal drag_started(card: DraggableCard)
signal drag_moved(card: DraggableCard, pointer_position: Vector2, valid_drop: bool)
signal drag_finished(card: DraggableCard, valid_drop: bool)
signal card_played(card: DraggableCard)

@export var play_zone: Control
# 战斗界面使用全局 Y 坐标作为出牌阈值；负值表示继续使用传统矩形出牌区。
@export var drop_threshold_y := -1.0

var _dragging := false
var _pointer_id := -1
var _drag_offset := Vector2.ZERO
var _home_global_position := Vector2.ZERO
var _return_tween: Tween
var _interaction_enabled := true


# 缓存场景中的出牌区，并在布局稳定后记录卡牌初始位置。
func _ready() -> void:
	gui_input.connect(_on_gui_input)
	call_deferred("_remember_home_position")


# 触摸事件由全局输入处理，以便手指移出卡牌矩形后仍能继续拖拽和释放。
func _input(event: InputEvent) -> void:
	if not _interaction_enabled:
		return
	if not _dragging:
		if event is InputEventScreenTouch and event.pressed:
			if get_global_rect().has_point(event.position):
				_start_drag(event.index, event.position)
		return

	if event is InputEventMouseMotion and _pointer_id == -1:
		_move_to_pointer(event.position)
	elif event is InputEventMouseButton and _pointer_id == -1:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_drag(event.position)
	elif event is InputEventScreenDrag and event.index == _pointer_id:
		_move_to_pointer(event.position)
	elif event is InputEventScreenTouch and event.index == _pointer_id:
		if not event.pressed:
			_finish_drag(event.position)


# 鼠标按键由控件输入处理，避免点到卡牌外部时错误起拖。
func _on_gui_input(event: InputEvent) -> void:
	if not _interaction_enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_drag(-1, get_global_mouse_position())
			accept_event()


# 布局完成后记录回弹目标位置。
func _remember_home_position() -> void:
	_home_global_position = global_position


# 开始一次指定指针的拖拽，并取消尚未完成的回弹动画。
func _start_drag(pointer_id: int, pointer_position: Vector2) -> void:
	if _dragging or not _interaction_enabled:
		return
	if _return_tween and _return_tween.is_running():
		_return_tween.kill()

	_dragging = true
	_pointer_id = pointer_id
	_drag_offset = pointer_position - global_position
	z_index = 10
	drag_started.emit(self)


# 保持按下点与卡牌左上角的偏移，避免起拖时发生跳动。
func _move_to_pointer(pointer_position: Vector2) -> void:
	global_position = pointer_position - _drag_offset
	drag_moved.emit(self, pointer_position, _is_valid_drop(pointer_position))


# 有效释放时出牌，无效释放时回到初始位置。
func _finish_drag(pointer_position: Vector2) -> void:
	_dragging = false
	_pointer_id = -1
	z_index = 0

	var valid_drop := _is_valid_drop(pointer_position)
	drag_finished.emit(self, valid_drop)
	if valid_drop:
		print("card_played")
		card_played.emit(self)
	else:
		_return_to_home()


# 战斗卡牌以“指针高于虚线”为有效出牌，其他测试和复用场景仍可使用矩形落点。
func _is_valid_drop(pointer_position: Vector2) -> bool:
	if drop_threshold_y >= 0.0:
		return pointer_position.y <= drop_threshold_y
	return play_zone != null and play_zone.get_global_rect().has_point(pointer_position)


# 结算期间关闭鼠标和触摸输入；若正在拖拽则安全回到手牌位置。
func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	if enabled or not _dragging:
		return
	_dragging = false
	_pointer_id = -1
	z_index = 0
	drag_finished.emit(self, false)
	_return_to_home()


# 供战斗界面判断卡牌是否可操作，不暴露内部拖拽状态。
func is_interaction_enabled() -> bool:
	return _interaction_enabled


# 使用短 Tween 平滑回到手牌位置。
func _return_to_home() -> void:
	_return_tween = create_tween()
	_return_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_return_tween.tween_property(self, "global_position", _home_global_position, 0.25)
