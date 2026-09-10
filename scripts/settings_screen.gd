# 设置界面：编辑音量、语言、窗口模式与节拍器样式，改动即时生效并持久化。
extends Control

signal overlay_closed

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var language_option: OptionButton = %LanguageOption
@onready var window_option: OptionButton = %WindowOption
@onready var circle_metronome_check: CheckBox = %CircleMetronomeCheck
@onready var waveform_metronome_check: CheckBox = %WaveformMetronomeCheck
@onready var status_label: Label = %StatusLabel
@onready var back_button: Button = $Margin/Layout/BackButton

var settings_service: Node
var _loading_ui := false
var opened_in_pause_overlay := false


# 从全局服务填充控件；界面初始化期间屏蔽信号，避免打开设置就重复写盘。
func _ready() -> void:
	# 嵌入战斗暂停层时仍需接收返回按钮，且不会因暂停树而停掉界面输入。
	if opened_in_pause_overlay:
		process_mode = Node.PROCESS_MODE_ALWAYS
		back_button.text = "返回战斗"
	settings_service = get_node("/root/SettingsService")
	_loading_ui = true
	language_option.add_item("简体中文")
	language_option.set_item_metadata(0, "zh_CN")
	language_option.add_item("English")
	language_option.set_item_metadata(1, "en")
	window_option.add_item("窗口模式")
	window_option.add_item("全屏模式")
	master_slider.value = settings_service.master_volume * 100.0
	music_slider.value = settings_service.music_volume * 100.0
	sfx_slider.value = settings_service.sfx_volume * 100.0
	_select_language(settings_service.language)
	window_option.select(settings_service.window_mode)
	circle_metronome_check.button_pressed = (
		settings_service.metronome_style == settings_service.MetronomeStyle.CIRCLE
	)
	waveform_metronome_check.button_pressed = (
		settings_service.metronome_style == settings_service.MetronomeStyle.WAVEFORM
	)
	_loading_ui = false


# 任一音量滑块变化时整体提交三个值，避免服务与界面局部状态不同步。
func _on_volume_changed(_value: float) -> void:
	if _loading_ui:
		return
	settings_service.set_audio_volumes(
		master_slider.value / 100.0,
		music_slider.value / 100.0,
		sfx_slider.value / 100.0
	)
	_save_and_report()


func _on_language_selected(index: int) -> void:
	if _loading_ui:
		return
	settings_service.set_language(str(language_option.get_item_metadata(index)))
	_save_and_report()


func _on_window_selected(index: int) -> void:
	if _loading_ui:
		return
	settings_service.set_window_mode(index)
	_save_and_report()


# 两个 CheckBox 共享 ButtonGroup，因此一次只能保留一个选中项；点击后立即保存稳定枚举值。
func _on_circle_metronome_pressed() -> void:
	if _loading_ui:
		return
	settings_service.set_metronome_style(settings_service.MetronomeStyle.CIRCLE)
	_save_and_report()


func _on_waveform_metronome_pressed() -> void:
	if _loading_ui:
		return
	settings_service.set_metronome_style(settings_service.MetronomeStyle.WAVEFORM)
	_save_and_report()


# 返回来源场景前再次保存；主菜单进入时来源为空，暂停菜单进入时回到原玩法场景。
func _on_back_pressed() -> void:
	settings_service.save_settings()
	if opened_in_pause_overlay:
		overlay_closed.emit()
		queue_free()
		return
	var return_scene: String = settings_service.take_settings_return_scene("res://scenes/main_menu.tscn")
	get_tree().change_scene_to_file(return_scene)


# 移动端系统返回键与界面返回按钮保持一致，并保存最后一次设置。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		_on_back_pressed()


func _select_language(locale: String) -> void:
	for index in range(language_option.item_count):
		if language_option.get_item_metadata(index) == locale:
			language_option.select(index)
			return
	language_option.select(0)


func _save_and_report() -> void:
	status_label.text = "设置已保存" if settings_service.save_settings() else "设置保存失败"
