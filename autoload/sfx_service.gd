# 全局交互反馈服务：为空白指针点击播放音效，并为现有、动态 UI 按钮统一提供点击缩放与去重音效。
extends Node

signal click_audio_triggered
signal button_feedback_triggered(button: BaseButton)

const CLICK_STREAM := preload("res://sound/sounds/click.mp3")
const BATTLE_CARD_VIEW_SCRIPT := preload("res://scripts/battle/card_view.gd")

var click_player: AudioStreamPlayer
# `_input` 与 GUI 的 button_down 在同一帧依次分发；按指针按下数保留去重额度，不依赖释放时机。
var _pointer_suppression_frame := -1
var _pointer_button_suppressions := 0
# 每个按钮各自缓存基础缩放和当前 Tween，避免连续点击叠加后永久改变用户在场景中配置的尺寸。
var _button_base_scales: Dictionary = {}
var _button_feedback_tweens: Dictionary = {}


# 常驻播放器进入 SFX 总线；节点监听先建立，再补扫当前场景树，覆盖加载顺序两侧的按钮。
func _ready() -> void:
	# 暂停层仍允许玩家操作按钮和空白区域，因此全局输入监听必须在场景树暂停时继续工作。
	process_mode = Node.PROCESS_MODE_ALWAYS
	click_player = AudioStreamPlayer.new()
	click_player.name = "ClickAudio"
	click_player.stream = CLICK_STREAM
	click_player.bus = &"SFX"
	click_player.max_polyphony = 4
	add_child(click_player)
	get_tree().node_added.connect(_on_node_added)
	_register_buttons_in(get_tree().root)


# 鼠标左键和每个真实触点按下都立即播放；同帧 GUI button_down 消费额度，触屏模拟鼠标副本直接忽略。
func _input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
	var is_pointer_press: bool = (
		(mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed)
		or (touch_event != null and touch_event.pressed)
	)
	if is_pointer_press:
		# 卡牌按下会进入拖拽流程，不属于通用 UI 点击，避免拖牌起手叠加 click 音效。
		if _is_battle_card_press(mouse_event, touch_event):
			return
		_add_pointer_button_suppression()
		_play_click()
		return


# 对外登记接口供测试和特殊运行时控件复用；button_down 与指针按下同帧，重复调用也不会叠加连接。
func register_button(button: BaseButton) -> void:
	if button == null:
		return
	var callback := _on_button_down.bind(button)
	if not button.button_down.is_connected(callback):
		button.button_down.connect(callback)
	var exit_callback := _on_button_tree_exited.bind(button.get_instance_id())
	if not button.tree_exited.is_connected(exit_callback):
		button.tree_exited.connect(exit_callback)


# SceneTree 会报告后续动态节点；只处理按钮，播放器等其他节点没有额外开销。
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		register_button(node)


# 启动时递归覆盖已经进入场景树的按钮，包括 Autoload 就绪前创建的测试控件。
func _register_buttons_in(node: Node) -> void:
	if node is BaseButton:
		register_button(node)
	for child in node.get_children():
		_register_buttons_in(child)


# 按钮缩放不受空白点击音的去重影响：鼠标、触屏、键盘和手柄触发的真实 button_down 都要给出视觉确认。
func _on_button_down(button: BaseButton) -> void:
	_play_button_feedback(button)
	if _pointer_suppression_frame == Engine.get_process_frames() and _pointer_button_suppressions > 0:
		_pointer_button_suppressions -= 1
		return
	_play_click()


# 以按钮现有缩放为基准做“压下—回弹—复位”；中心枢轴不改变静态布局，只保证缩放不会向单侧偏移。
func _play_button_feedback(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button):
		return
	var instance_id := button.get_instance_id()
	var base_scale: Vector2 = _button_base_scales.get(instance_id, button.scale)
	_button_base_scales[instance_id] = base_scale
	button.pivot_offset = button.size * 0.5
	var previous_tween := _button_feedback_tweens.get(instance_id) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	button.scale = base_scale
	var feedback_tween := create_tween().bind_node(button)
	feedback_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	feedback_tween.tween_property(button, "scale", base_scale * 0.92, 0.045)
	feedback_tween.set_ease(Tween.EASE_IN_OUT)
	feedback_tween.tween_property(button, "scale", base_scale * 1.06, 0.075)
	feedback_tween.set_ease(Tween.EASE_IN)
	feedback_tween.tween_property(button, "scale", base_scale, 0.12)
	_button_feedback_tweens[instance_id] = feedback_tween
	button_feedback_triggered.emit(button)


# 动态场景销毁后清理缓存，避免临时按钮和战斗重建持续累积实例 ID。
func _on_button_tree_exited(instance_id: int) -> void:
	_button_base_scales.erase(instance_id)
	_button_feedback_tweens.erase(instance_id)


# 同一帧可接收多个触点；额度逐个匹配随后 GUI 激活，跨帧自动失效。
func _add_pointer_button_suppression() -> void:
	var current_frame := Engine.get_process_frames()
	if current_frame != _pointer_suppression_frame:
		_pointer_suppression_frame = current_frame
		_pointer_button_suppressions = 0
	_pointer_button_suppressions += 1


# 鼠标悬停控件可直接定位到卡牌子树；触摸没有悬停状态，改以触点坐标检查可交互的卡牌矩形。
func _is_battle_card_press(mouse_event: InputEventMouseButton, touch_event: InputEventScreenTouch) -> bool:
	if mouse_event != null:
		var hovered_control := get_viewport().gui_get_hovered_control()
		return _is_in_battle_card_tree(hovered_control)
	if touch_event != null:
		return _has_battle_card_at(get_tree().root, touch_event.position)
	return false


# Viewport 返回的通常是最深层控件；向上追溯即可识别卡面内的任意装饰节点。
func _is_in_battle_card_tree(node: Node) -> bool:
	var current_node := node
	while current_node != null:
		if current_node.get_script() == BATTLE_CARD_VIEW_SCRIPT:
			return true
		current_node = current_node.get_parent()
	return false


# 触屏事件不提供 hovered Control，递归查找卡牌根节点，兼容手指直接按在卡面空白或装饰上。
func _has_battle_card_at(node: Node, pointer_position: Vector2) -> bool:
	if node.get_script() == BATTLE_CARD_VIEW_SCRIPT and node is Control:
		var card := node as Control
		if card.visible and card.get_global_rect().has_point(pointer_position):
			return true
	for child in node.get_children():
		if _has_battle_card_at(child, pointer_position):
			return true
	return false


# 空点击与按钮激活共用播放出口，便于测试确认每次用户操作只输出一次。
func _play_click() -> void:
	click_player.play()
	click_audio_triggered.emit()
