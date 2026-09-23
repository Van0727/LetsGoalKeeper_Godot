# 全局音效服务冒烟测试：验证空白指针点击、现有及动态按钮都播放一次，并过滤同次输入的重复事件。
extends SceneTree

var _failed := false


# 延迟到根视口初始化后执行，避免按钮尚未进入场景树。
func _initialize() -> void:
	call_deferred("_run")


# 通过 BaseButton 的公开 button_down 信号验收全局接入，不依赖具体页面脚本。
func _run() -> void:
	var service := root.get_node_or_null("SfxService")
	_assert_true(service != null, "项目已注册全局SfxService")
	if service == null:
		quit(1)
		return
	var first_button := Button.new()
	root.add_child(first_button)
	await process_frame

	var click_count := [0]
	service.click_audio_triggered.connect(func() -> void: click_count[0] += 1)
	first_button.button_down.emit()
	_assert_equal(click_count[0], 1, "进入场景树的按钮播放一次点击音")

	var dynamic_button := Button.new()
	root.add_child(dynamic_button)
	await process_frame
	dynamic_button.button_down.emit()
	_assert_equal(click_count[0], 2, "运行时动态按钮播放一次点击音")

	# 重复扫描不能给同一按钮叠加连接，否则一次操作会播放多次。
	service.register_button(dynamic_button)
	dynamic_button.button_down.emit()
	_assert_equal(click_count[0], 3, "重复登记仍只播放一次点击音")

	# 空白区域的鼠标按下也属于一次点击；释放只结束去重窗口，不额外播放。
	var empty_press := InputEventMouseButton.new()
	empty_press.button_index = MOUSE_BUTTON_LEFT
	empty_press.pressed = true
	Input.parse_input_event(empty_press)
	await process_frame
	_assert_equal(click_count[0], 4, "鼠标左键空点击播放一次点击音")
	var empty_release := InputEventMouseButton.new()
	empty_release.button_index = MOUSE_BUTTON_LEFT
	empty_release.pressed = false
	Input.parse_input_event(empty_release)
	await process_frame
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	Input.parse_input_event(right_press)
	await process_frame
	_assert_equal(click_count[0], 4, "鼠标右键不属于确认点击，不播放音效")

	# 同一次指针按下按钮时，全局输入已经播放，随后 button_down 信号不得重复叠音。
	var button_press := InputEventMouseButton.new()
	button_press.button_index = MOUSE_BUTTON_LEFT
	button_press.pressed = true
	Input.parse_input_event(button_press)
	first_button.button_down.emit()
	await process_frame
	_assert_equal(click_count[0], 5, "指针点击按钮只播放一次点击音")
	var button_release := InputEventMouseButton.new()
	button_release.button_index = MOUSE_BUTTON_LEFT
	button_release.pressed = false
	Input.parse_input_event(button_release)
	await process_frame

	# 没有指针输入时的 button_down 代表键盘、手柄或代码激活，仍须独立播放。
	first_button.button_down.emit()
	_assert_equal(click_count[0], 6, "非指针激活按钮仍播放点击音")

	var touch_press := InputEventScreenTouch.new()
	touch_press.index = 0
	touch_press.pressed = true
	Input.parse_input_event(touch_press)
	await process_frame
	_assert_equal(click_count[0], 7, "触屏空点击播放一次点击音")
	var touch_release := InputEventScreenTouch.new()
	touch_release.index = 0
	touch_release.pressed = false
	Input.parse_input_event(touch_release)
	await process_frame

	# 触屏产生的模拟鼠标副本不能让同一次触碰双响。
	var touch_with_emulation := InputEventScreenTouch.new()
	touch_with_emulation.index = 1
	touch_with_emulation.pressed = true
	Input.parse_input_event(touch_with_emulation)
	var emulated_mouse := InputEventMouseButton.new()
	emulated_mouse.device = InputEvent.DEVICE_ID_EMULATION
	emulated_mouse.button_index = MOUSE_BUTTON_LEFT
	emulated_mouse.pressed = true
	Input.parse_input_event(emulated_mouse)
	await process_frame
	_assert_equal(click_count[0], 8, "触屏与模拟鼠标副本合计只播放一次")

	# 多个真实触点各自属于一次空点击，不能被全局去重状态吞掉。
	var second_touch := InputEventScreenTouch.new()
	second_touch.index = 2
	second_touch.pressed = true
	Input.parse_input_event(second_touch)
	var third_touch := InputEventScreenTouch.new()
	third_touch.index = 3
	third_touch.pressed = true
	Input.parse_input_event(third_touch)
	await process_frame
	_assert_equal(click_count[0], 10, "同帧两个真实触点分别播放点击音")

	# 指针事件的去重额度只在当前帧有效，不会静音随后帧的键盘或手柄按钮激活。
	first_button.button_down.emit()
	_assert_equal(click_count[0], 11, "触点按住期间后续帧的非指针按钮仍播放")

	# 卡牌起手进入拖拽，不应被全局空点击策略误判为普通 click。
	var battle_card := service.BATTLE_CARD_VIEW_SCRIPT.new() as Control
	battle_card.size = Vector2(100, 160)
	root.add_child(battle_card)
	await process_frame
	var card_press := InputEventMouseButton.new()
	card_press.button_index = MOUSE_BUTTON_LEFT
	card_press.pressed = true
	card_press.position = Vector2(20, 20)
	Input.parse_input_event(card_press)
	await process_frame
	_assert_equal(click_count[0], 11, "点击卡牌不播放全局click音效")
	battle_card.queue_free()

	_assert_true(service.click_player.stream != null, "全局点击播放器绑定音频资源")
	_assert_true(
		service.click_player.stream.resource_path.ends_with("sound/sounds/click.mp3"),
		"全局点击播放器使用 click.mp3"
	)
	_assert_equal(service.click_player.bus, &"SFX", "全局点击音进入 SFX 总线")
	_assert_equal(service.process_mode, Node.PROCESS_MODE_ALWAYS, "暂停期间仍监听按钮和空点击")

	# 点击缩放按场景原始缩放回弹，动态按钮同样通过 SceneTree 自动登记，不依赖页面脚本单独接线。
	var feedback_button := Button.new()
	feedback_button.scale = Vector2(1.25, 0.8)
	root.add_child(feedback_button)
	await process_frame
	var feedback_count := [0]
	service.button_feedback_triggered.connect(func(button: BaseButton) -> void:
		if button == feedback_button:
			feedback_count[0] += 1
	)
	feedback_button.button_down.emit()
	_assert_equal(feedback_count[0], 1, "动态按钮按下时触发全局缩放反馈")
	await process_frame
	_assert_true(not feedback_button.scale.is_equal_approx(Vector2(1.25, 0.8)), "点击过程会暂时改变按钮缩放")
	await create_timer(0.3).timeout
	_assert_true(feedback_button.scale.is_equal_approx(Vector2(1.25, 0.8)), "点击缩放结束后恢复按钮原始尺寸")

	if _failed:
		quit(1)
		return
	print("smoke_sfx_service: PASS")
	quit()


# 通用相等断言保留实际值，便于定位重复连接。
func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		return
	_failed = true
	push_error("%s：期望 %s，实际 %s" % [label, expected, actual])


# 通用布尔断言。
func _assert_true(value: bool, label: String) -> void:
	if value:
		return
	_failed = true
	push_error("%s：条件未满足" % label)
