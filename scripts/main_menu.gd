# 主菜单：提供本局入口，并让封面 Logo、怪物与足球平滑跟随主 BGM 拍点呼吸，足球同时持续旋转。
extends Control

const CARD_DRAG_TEST_SCENE := preload("res://scenes/card_drag_test.tscn")
const CHARACTER_FEEDBACK_TEST_SCENE := preload("res://scenes/character_feedback_test.tscn")
const BATTLE_LOGIC_TEST_SCENE := preload("res://scenes/battle_logic_test.tscn")
const DECK_LOGIC_TEST_SCENE := preload("res://scenes/deck_logic_test.tscn")
# 三张透明切图在 941×1672 原封面中的像素区域；运行时按 Background 的 Cover 规则换算以避免错位。
const LOGO_SOURCE_RECT := Rect2(107.0, 61.0, 768.0, 440.0)
const ENEMY_SOURCE_RECT := Rect2(321.0, 603.0, 298.0, 156.0)
const BALL_SOURCE_RECT := Rect2(305.0, 1002.0, 333.0, 322.0)
const BALL_ROTATION_SPEED := TAU / 1
const LOGO_PULSE_SCALE := 1.08
const ENEMY_PULSE_SCALE := 1.2
const BALL_PULSE_SCALE := 1.2
const BUTTON_PULSE_SCALE := 1.05
# 怪物透明像素的视觉重心约位于高度 60%，用它缩放可避免主体上下漂移形成抖动感。
const ENEMY_PIVOT_RATIO := Vector2(0.5, 0.6)

@onready var start_button: Button = %StartButton
@onready var continue_button: Button = %ContinueButton
@onready var background: TextureRect = %Background
@onready var game_logo: TextureRect = %GameLogo
@onready var game_enemy: TextureRect = %GameEnemy
@onready var game_ball: TextureRect = %GameBall

var _logo_pulse_tween: Tween
var _enemy_pulse_tween: Tween
var _ball_pulse_tween: Tween
var _start_button_pulse_tween: Tween
var _continue_button_pulse_tween: Tween


# 主菜单每次进入都根据本局状态刷新继续按钮；状态文字和设置入口不再占用封面空间。
func _ready() -> void:
	_sync_cover_art_transforms()
	background.resized.connect(_sync_cover_art_transforms)
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null and bgm_service.has_signal("main_beat_reached"):
		bgm_service.main_beat_reached.connect(_on_main_beat_reached)
	refresh_continue_availability()


# 足球使用独立旋转角度，缩放脉冲只改变 scale，两种动画可以稳定叠加。
func _process(delta: float) -> void:
	game_ball.rotation = wrapf(game_ball.rotation + BALL_ROTATION_SPEED * delta, 0.0, TAU)


# 三张切图统一按封面像素坐标定位；缩放轴心随尺寸同步，避免近似锚点造成 Logo 抖动和重影。
func _sync_cover_art_transforms() -> void:
	_sync_art_to_cover(game_logo, LOGO_SOURCE_RECT)
	_sync_art_to_cover(game_enemy, ENEMY_SOURCE_RECT, ENEMY_PIVOT_RATIO)
	_sync_art_to_cover(game_ball, BALL_SOURCE_RECT)


# 复刻 TextureRect 的 Keep Aspect Covered 规则；可选轴心比例用于匹配不对称切图的视觉重心。
func _sync_art_to_cover(
	control: Control,
	source_rect: Rect2,
	pivot_ratio: Vector2 = Vector2(0.5, 0.5)
) -> void:
	if background.texture == null:
		return
	var texture_size := background.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var cover_scale := maxf(background.size.x / texture_size.x, background.size.y / texture_size.y)
	var displayed_size := texture_size * cover_scale
	var cover_origin := background.position + (background.size - displayed_size) * 0.5
	control.position = cover_origin + source_rect.position * cover_scale
	control.size = source_rect.size * cover_scale
	control.pivot_offset = control.size * pivot_ratio


# 四拍循环：足球每拍、怪物仅第 1 拍、Logo 与两个入口按钮仅第 2 和第 4 拍触发。
func _on_main_beat_reached(_beat_index: int) -> void:
	var beat_number := posmod(_beat_index, 4) + 1
	_ball_pulse_tween = _restart_pulse(game_ball, _ball_pulse_tween, BALL_PULSE_SCALE)
	match beat_number:
		1:
			_enemy_pulse_tween = _restart_pulse(
				game_enemy,
				_enemy_pulse_tween,
				ENEMY_PULSE_SCALE
			)
		2, 4:
			_logo_pulse_tween = _restart_pulse(game_logo, _logo_pulse_tween, LOGO_PULSE_SCALE)
			_start_button_pulse_tween = _restart_pulse(
				start_button,
				_start_button_pulse_tween,
				BUTTON_PULSE_SCALE
			)
			_continue_button_pulse_tween = _restart_pulse(
				continue_button,
				_continue_button_pulse_tween,
				BUTTON_PULSE_SCALE
			)


# 只中断本拍再次触发的对象；跳过的拍数不会破坏其他对象尚未结束的回落动画。
func _restart_pulse(control: Control, current_tween: Tween, peak_scale: float) -> Tween:
	if current_tween != null and current_tween.is_valid():
		current_tween.kill()
	return _create_pulse_tween(control, peak_scale)


# 每个对象使用独立 Tween，放大与回落总时长短于 110 BPM 单拍间隔，低帧率下也能自然接续。
func _create_pulse_tween(control: Control, peak_scale: float) -> Tween:
	var pulse_tween := create_tween().bind_node(control)
	pulse_tween.set_trans(Tween.TRANS_SINE)
	pulse_tween.set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(control, "scale", Vector2.ONE * peak_scale, 0.16)
	pulse_tween.set_ease(Tween.EASE_IN_OUT)
	pulse_tween.tween_property(control, "scale", Vector2.ONE, 0.34)
	return pulse_tween


# 主菜单不再显示本局状态文字，仅按存档状态控制继续按钮是否可用。
func refresh_continue_availability() -> void:
	var run_state := get_node("/root/RunState")
	continue_button.disabled = (
		run_state.is_placeholder_run
		or run_state.run_status != run_state.RunStatus.ACTIVE
		or run_state.map_state == null
	)


# 开始新游戏：使用随机种子彻底重置本局并进入第 1 章路线地图。
func _on_start_button_pressed() -> void:
	var run_state := get_node("/root/RunState")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	run_state.start_new_run(rng.randi())
	_record_diagnostic("new_run", {"seed": run_state.seed})
	_save_run()
	get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 继续按钮再次从磁盘恢复，确保入口不依赖当前进程中可能过期的临时状态。
func _on_continue_button_pressed() -> void:
	var run_state := get_node("/root/RunState")
	var save_service := get_node_or_null("/root/SaveService")
	if save_service == null or not save_service.load_game(run_state):
		refresh_continue_availability()
		return
	if run_state.run_status != run_state.RunStatus.ACTIVE or run_state.map_state == null:
		refresh_continue_availability()
		return
	# 安全节点决定恢复目标：胜利后直接领奖，已进入的房间回到对应内容，其他情况回地图。
	match run_state.resume_point:
		run_state.ResumePoint.BATTLE:
			# 继续战斗也复用地图入口的过场顺序，禁止战斗场景加载后才补播切曲音效。
			continue_button.disabled = true
			var bgm_service := get_node_or_null("/root/BgmService")
			if bgm_service != null:
				await bgm_service.prepare_battle_transition()
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
		run_state.ResumePoint.REWARD:
			get_tree().change_scene_to_file("res://scenes/reward_screen.tscn")
		run_state.ResumePoint.REST:
			get_tree().change_scene_to_file("res://scenes/rest_room.tscn")
		_:
			get_tree().change_scene_to_file("res://scenes/map_screen.tscn")


# 新游戏建立完整地图后立即覆盖旧档，保证强制关闭也不会回到上一局。
func _save_run() -> void:
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null:
		save_service.save_game(get_node("/root/RunState"))


# 隐藏的诊断入口仍可导出文件，但主菜单不再显示状态文字。
func _on_export_diagnostics_pressed() -> void:
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics == null:
		return
	diagnostics.export_logs()


func _record_diagnostic(event_name: String, fields: Dictionary) -> void:
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("run", event_name, fields)


# 主菜单没有未提交进度，移动端返回键可直接退出；玩法场景则由暂停层二次确认。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


# 保留阶段 2 的牌堆逻辑测试入口，方便后续回归抽弃牌规则。
func _on_deck_logic_button_pressed() -> void:
	get_tree().change_scene_to_packed(DECK_LOGIC_TEST_SCENE)


# 进入战斗结算与卡牌效果测试。
func _on_battle_logic_button_pressed() -> void:
	get_tree().change_scene_to_packed(BATTLE_LOGIC_TEST_SCENE)


# 进入角色受击、治疗和护盾反馈测试。
func _on_character_feedback_button_pressed() -> void:
	get_tree().change_scene_to_packed(CHARACTER_FEEDBACK_TEST_SCENE)


# 进入鼠标与触摸统一拖拽测试。
func _on_card_drag_button_pressed() -> void:
	get_tree().change_scene_to_packed(CARD_DRAG_TEST_SCENE)
