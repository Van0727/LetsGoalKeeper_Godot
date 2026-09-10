# 可复用暂停层：冻结玩法场景，统一处理继续、设置、返回主菜单和退出确认。
extends CanvasLayer

const SETTINGS_SCREEN := preload("res://scenes/settings_screen.tscn")

enum ConfirmAction { NONE, MAIN_MENU, QUIT_GAME }

@onready var pause_button: Button = %PauseButton
@onready var shade: TextureRect = %Shade
@onready var pause_panel: PanelContainer = %PausePanel
@onready var confirm_panel: PanelContainer = %ConfirmPanel
@onready var confirm_label: Label = %ConfirmLabel

var pending_action := ConfirmAction.NONE
var _settings_overlay
var _external_modal_open := false


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
	# 战斗QTE等外部模态层负责自己的完整生命周期，期间返回键不得在其上方再打开暂停菜单。
	if _external_modal_open:
		return
	if confirm_panel != null and confirm_panel.visible:
		cancel_confirmation()
	elif get_tree().paused:
		close_pause()
	else:
		open_pause()


func _on_settings_pressed() -> void:
	if _settings_overlay != null:
		return
	# 设置页作为暂停层子节点覆盖战斗，避免销毁战斗状态或中断常驻战斗 BGM。
	pause_panel.hide()
	_settings_overlay = SETTINGS_SCREEN.instantiate()
	_settings_overlay.opened_in_pause_overlay = true
	_settings_overlay.overlay_closed.connect(_on_settings_overlay_closed)
	add_child(_settings_overlay)


# 返回战斗时关闭设置覆盖层并直接解除暂停，保留原来的回合、手牌和音乐播放头。
func _on_settings_overlay_closed() -> void:
	_settings_overlay = null
	close_pause()


func _on_confirm_pressed() -> void:
	var action := pending_action
	if action == ConfirmAction.MAIN_MENU:
		# 放弃战斗属于明确 BGM 切换，暂停层保持生效直到切曲音效结束，避免后台战斗继续结算。
		var bgm_service := get_node_or_null("/root/BgmService")
		if bgm_service != null:
			await bgm_service.transition_to_main_bgm()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	elif action == ConfirmAction.QUIT_GAME:
		get_tree().paused = false
		get_tree().quit()


func _on_pause_button_pressed() -> void:
	open_pause()


# 允许宿主界面的临时弹窗隐藏暂停入口并拦截返回键，关闭后恢复正常暂停能力。
func set_external_modal_open(open: bool) -> void:
	_external_modal_open = open
	if open:
		pause_button.hide()
	elif not get_tree().paused:
		pause_button.show()


func _on_resume_pressed() -> void:
	close_pause()


func _on_main_menu_pressed() -> void:
	request_confirmation(ConfirmAction.MAIN_MENU)


func _on_quit_pressed() -> void:
	request_confirmation(ConfirmAction.QUIT_GAME)
