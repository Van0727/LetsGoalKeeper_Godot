class_name DraggableCard
extends PanelContainer

signal card_played(card: DraggableCard)

@export var play_zone: Control

var _dragging := false
var _pointer_id := -1
var _drag_offset := Vector2.ZERO
var _home_global_position := Vector2.ZERO
var _return_tween: Tween


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	call_deferred("_remember_home_position")


func _input(event: InputEvent) -> void:
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


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_drag(-1, get_global_mouse_position())
			accept_event()


func _remember_home_position() -> void:
	_home_global_position = global_position


func _start_drag(pointer_id: int, pointer_position: Vector2) -> void:
	if _dragging:
		return
	if _return_tween and _return_tween.is_running():
		_return_tween.kill()

	_dragging = true
	_pointer_id = pointer_id
	_drag_offset = pointer_position - global_position
	z_index = 10


func _move_to_pointer(pointer_position: Vector2) -> void:
	global_position = pointer_position - _drag_offset


func _finish_drag(pointer_position: Vector2) -> void:
	_dragging = false
	_pointer_id = -1
	z_index = 0

	if play_zone and play_zone.get_global_rect().has_point(pointer_position):
		print("card_played")
		card_played.emit(self)

	_return_to_home()


func _return_to_home() -> void:
	_return_tween = create_tween()
	_return_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_return_tween.tween_property(self, "global_position", _home_global_position, 0.25)
