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
# 确认后的异步切曲只允许启动一次；等待期间禁止继续、取消和新的确认覆盖原操作。
var _confirm_in_progress := false


# 暂停层在 SceneTree 暂停时仍接收输入；初始只显示右上角入口。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shade.hide()
	pause_panel.hide()
	confirm_panel.hide()


# Esc、ui_cancel 与移动端返回键复用同一状态转换，确认框优先取消。
func _unhandled_input(event: InputEvent) -> void:
	if is_inside_tree() and event.is_action_pressed("ui_cancel"):
		_handle_back_request()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()


# 打开暂停时冻结当前玩法树；本层因 ALWAYS 模式仍可操作。
func open_pause() -> void:
	if not is_inside_tree() or _confirm_in_progress:
		return
	if get_tree().paused:
		return
	get_tree().paused = true
	shade.show()
	pause_panel.show()
	pause_button.hide()


# 节点离树后的迟到回调直接忽略，不再操作已不存在的 SceneTree。
func close_pause() -> void:
	if not is_inside_tree() or _confirm_in_progress:
		return
	pending_action = ConfirmAction.NONE
	confirm_panel.hide()
	pause_panel.hide()
	shade.hide()
	pause_button.show()
	get_tree().paused = false


# 返回菜单和退出都先进入二次确认，避免移动端返回键或鼠标误触丢失当前流程。
func request_confirmation(action: int) -> void:
	if not is_inside_tree() or _confirm_in_progress:
		return
	pending_action = action
	confirm_label.text = (
		"确定返回主菜单吗？\n当前战斗进度不会保存。"
		if action == ConfirmAction.MAIN_MENU
		else "确定退出游戏吗？\n将从最近的安全节点继续。"
	)
	pause_panel.hide()
	confirm_panel.show()


func cancel_confirmation() -> void:
	if not is_inside_tree() or _confirm_in_progress:
		return
	pending_action = ConfirmAction.NONE
	confirm_panel.hide()
	pause_panel.show()


func _handle_back_request() -> void:
	# 战斗QTE等外部模态层负责自己的完整生命周期，期间返回键不得在其上方再打开暂停菜单。
	if not is_inside_tree() or _external_modal_open or _confirm_in_progress:
		return
	if confirm_panel != null and confirm_panel.visible:
		cancel_confirmation()
	elif get_tree().paused:
		close_pause()
	else:
		open_pause()


func _on_settings_pressed() -> void:
	if not is_inside_tree() or _confirm_in_progress or _settings_overlay != null:
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


# 防止重复确认；等待结束后必须重新验证节点所属树，不能用缓存树切换其他新场景。
func _on_confirm_pressed() -> void:
	if not is_inside_tree() or _confirm_in_progress:
		return
	var action := pending_action
	if action not in [ConfirmAction.MAIN_MENU, ConfirmAction.QUIT_GAME]:
		return
	_confirm_in_progress = true
	if action == ConfirmAction.MAIN_MENU:
		# 放弃战斗属于明确 BGM 切换，暂停层保持生效直到切曲音效结束，避免后台战斗继续结算。
		var bgm_service := get_node_or_null("/root/BgmService")
		if bgm_service != null:
			await bgm_service.transition_to_main_bgm()
		if not is_inside_tree():
			_confirm_in_progress = false
			return
		var tree := get_tree()
		var error := tree.change_scene_to_file("res://scenes/main_menu.tscn")
		if error != OK:
			# 加载失败时保留暂停确认界面并允许重试，避免半完成的返回流程。
			_confirm_in_progress = false
			push_error("返回主菜单失败：%s" % error_string(error))
			return
		# 切场景会立即移除旧场景，此处只能使用切换前取得的树。
		tree.paused = false
	elif action == ConfirmAction.QUIT_GAME:
		get_tree().paused = false
		get_tree().quit()


func _on_pause_button_pressed() -> void:
	open_pause()


# 允许宿主界面的临时弹窗隐藏暂停入口并拦截返回键，关闭后恢复正常暂停能力。
func set_external_modal_open(open: bool) -> void:
	_external_modal_open = open
	if not is_inside_tree():
		return
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
