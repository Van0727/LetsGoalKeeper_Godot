# 启动场景入口：桌面端直接进入主菜单；Web 端先等待一次用户手势，以满足浏览器音频解锁要求。
extends Node

const MAIN_MENU_SCENE := preload("res://scenes/main_menu.tscn")

var _web_start_confirmed := false


# Web 浏览器禁止无手势自动播放，因此保留启动页直到点击、触摸或按键；其他平台沿用原来的无感启动。
func _ready() -> void:
	if OS.has_feature("web"):
		_create_web_start_button()
		return
	get_tree().call_deferred("change_scene_to_packed", MAIN_MENU_SCENE)


# 全屏按钮既给出明确提示，也保证鼠标和触摸事件由同一个原生用户手势解锁音频上下文。
func _create_web_start_button() -> void:
	var start_button := Button.new()
	start_button.name = "WebAudioStartButton"
	start_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start_button.text = "点击开始\nCLICK TO START"
	start_button.add_theme_font_size_override("font_size", 28)
	start_button.pressed.connect(_confirm_web_start)
	add_child(start_button)


# 键盘和手柄同样属于浏览器认可的用户交互，避免只能用指针进入游戏。
func _input(event: InputEvent) -> void:
	if not OS.has_feature("web") or _web_start_confirmed:
		return
	var key_event := event as InputEventKey
	var joypad_event := event as InputEventJoypadButton
	if (
		(key_event != null and key_event.pressed and not key_event.echo)
		or (joypad_event != null and joypad_event.pressed)
	):
		_confirm_web_start()


# 音频必须在当前输入回调中重新发起播放，随后再切场景，防止启动时被拦截的静音状态延续。
func _confirm_web_start() -> void:
	if _web_start_confirmed:
		return
	_web_start_confirmed = true
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		bgm_service.resume_after_web_user_gesture()
	get_tree().change_scene_to_packed(MAIN_MENU_SCENE)
