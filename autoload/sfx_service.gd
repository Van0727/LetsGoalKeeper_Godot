# 全局音效服务：为空白指针点击及现有、动态按钮统一播放点击音，并避免同次按钮点击叠音。
extends Node

signal click_audio_triggered

const CLICK_STREAM := preload("res://sound/sounds/click.mp3")

var click_player: AudioStreamPlayer
# `_input` 与 GUI 的 button_down 在同一帧依次分发；按指针按下数保留去重额度，不依赖释放时机。
var _pointer_suppression_frame := -1
var _pointer_button_suppressions := 0


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


# 指针按钮已由全局按下事件发声；键盘和手柄产生的独立 button_down 则在这里播放。
func _on_button_down(_button: BaseButton) -> void:
	if _pointer_suppression_frame == Engine.get_process_frames() and _pointer_button_suppressions > 0:
		_pointer_button_suppressions -= 1
		return
	_play_click()


# 同一帧可接收多个触点；额度逐个匹配随后 GUI 激活，跨帧自动失效。
func _add_pointer_button_suppression() -> void:
	var current_frame := Engine.get_process_frames()
	if current_frame != _pointer_suppression_frame:
		_pointer_suppression_frame = current_frame
		_pointer_button_suppressions = 0
	_pointer_button_suppressions += 1


# 空点击与按钮激活共用播放出口，便于测试确认每次用户操作只输出一次。
func _play_click() -> void:
	click_player.play()
	click_audio_triggered.emit()
