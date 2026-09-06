# 可复用暂停层：冻结玩法场景，统一处理继续、设置、返回主菜单和退出确认。
extends CanvasLayer

enum ConfirmAction { NONE, MAIN_MENU, QUIT_GAME }

@onready var pause_button: Button = %PauseButton
@onready var shade: ColorRect = %Shade
@onready var pause_panel: PanelContainer = %PausePanel
@onready var confirm_panel: PanelContainer = %ConfirmPanel
@onready var confirm_label: Label = %ConfirmLabel

var pending_action := ConfirmAction.NONE


# 暂停层在 SceneTree 暂停时仍接收输入；初始只显示右上角入口。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shade.hide()
	pause_panel.hide()
	confirm_panel.hide()


# Esc、ui_cancel 与移动端返回键复用同一状态转换，确认框优先取消。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_back_request()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()


# 打开暂停时冻结当前玩法树；本层因 ALWAYS 模式仍可操作。
func open_pause() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	shade.show()
	pause_panel.show()
	pause_button.hide()


func close_pause() -> void:
	pending_action = ConfirmAction.NONE
	confirm_panel.hide()
	pause_panel.hide()
	shade.hide()
	pause_button.show()
	get_tree().paused = false


# 返回菜单和退出都先进入二次确认，避免移动端返回键或鼠标误触丢失当前流程。
func request_confirmation(action: int) -> void:
	pending_action = action
	confirm_label.text = (
		"确定返回主菜单吗？\n当前战斗进度不会保存。"
		if action == ConfirmAction.MAIN_MENU
		else "确定退出游戏吗？\n将从最近的安全节点继续。"
	)
	pause_panel.hide()
	confirm_panel.show()


func cancel_confirmation() -> void:
	pending_action = ConfirmAction.NONE
	confirm_panel.hide()
	pause_panel.show()


func _handle_back_request() -> void:
	if confirm_panel != null and confirm_panel.visible:
		cancel_confirmation()
	elif get_tree().paused:
		close_pause()
	else:
		open_pause()


func _on_settings_pressed() -> void:
	var settings_service := get_node_or_null("/root/SettingsService")
	if settings_service != null:
		settings_service.settings_return_scene = get_tree().current_scene.scene_file_path
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/settings_screen.tscn")


func _on_confirm_pressed() -> void:
	var action := pending_action
	get_tree().paused = false
	if action == ConfirmAction.MAIN_MENU:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif action == ConfirmAction.QUIT_GAME:
		get_tree().quit()


func _on_pause_button_pressed() -> void:
	open_pause()


func _on_resume_pressed() -> void:
	close_pause()


func _on_main_menu_pressed() -> void:
	request_confirmation(ConfirmAction.MAIN_MENU)


func _on_quit_pressed() -> void:
	request_confirmation(ConfirmAction.QUIT_GAME)
