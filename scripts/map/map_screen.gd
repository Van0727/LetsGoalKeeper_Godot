# 球场地图界面：使用素材表现真实路线，不改变地图生成规则或存档。
extends Control
# 可选关卡每拍最大倍率：1.0 不放大，1.10 表示放大 10%；基础透视尺寸保持不变。
@export_range(1.0, 1.3, 0.01) var selectable_pulse_scale := 1.06
# 各房间整套界面相对原透视尺寸的倍率，Boss 保留原有强调系数后再放大。
@export_range(0.5, 3.0, 0.05) var monster_ui_scale := 1.2
@export_range(0.5, 3.0, 0.05) var boss_ui_scale := 2.0
@export_range(0.5, 3.0, 0.05) var rest_ui_scale := 1.2
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const MAP_STATE := preload("res://scripts/map/map_state.gd")
const ROOM_BUTTON := preload("res://scripts/map/map_room_button.gd")
const ART_PATHS := {
"base":"res://assets/ui/map/enemy_node_base_v2.png",
"boss_base":"res://assets/ui/map/boss_node_base_v2.png",
"name":"res://assets/ui/map/enemy_nameplate_v2.png",
"boss_name":"res://assets/ui/map/boss_nameplate_v2.png",
"boss":"res://assets/ui/map/boss_icon_v2.png",
"ball":"res://assets/ui/game_ball.png",
"shield":"res://assets/placeholders/icon_shield.png",
"heart":"res://assets/placeholders/icon_health.png",
}
@onready var title_label: Label = %TitleLabel
@onready var rows_container: Control = %RowsContainer
@onready var connections_layer: Control = %ConnectionsLayer
@onready var info_label: Label = %InfoLabel
@onready var completed_overlay: ColorRect = %CompletedOverlay
@onready var missing_overlay: ColorRect = %MissingOverlay
var room_buttons := {}
var artwork: Dictionary = {}
var run_state: Node
var _is_scene_transitioning := false

# 素材缺失保留空纹理，由按钮安全回退。
func _ready() -> void:
	for key in ART_PATHS:
		artwork[key] = load(ART_PATHS[key]) if ResourceLoader.exists(ART_PATHS[key]) else null
	run_state = get_node_or_null("/root/RunState")
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
	rows_container.resized.connect(_layout_rooms)
	_style_header()
	refresh_ui()
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		bgm_service.main_beat_reached.connect(_on_main_beat_reached)

# 与封面共用音乐节拍，每一拍只让当前可选节点脉动；无音乐时保持静止。
func _on_main_beat_reached(_beat_index: int) -> void:
	if _is_scene_transitioning or get_tree().paused or run_state.map_state == null:
		return
	for button in room_buttons.values():
		if not button.disabled:
			button.pulse(selectable_pulse_scale)

# 战斗与休息返回时只重建表现，未结算的房间不能解锁后续路线。
func refresh_ui() -> void:
	if run_state.map_state == null:
		completed_overlay.hide()
		missing_overlay.show()
		return
	missing_overlay.hide()
	var config: Resource = load("res://data/maps/map_chapter_%d.tres" % run_state.chapter)
	title_label.text = "第 %d 章 · %s" % [run_state.chapter, config.chapter_name if config != null else "路线地图"]
	for child in rows_container.get_children():
		child.stop_pulse()
		rows_container.remove_child(child)
		child.queue_free()
	room_buttons.clear()
	for room in run_state.map_state.rooms:
		var button := ROOM_BUTTON.new()
		rows_container.add_child(button)
		button.disabled = room.state != MAP_STATE.RoomState.ATTAINABLE
		button.configure(room, _opponent_name(room), artwork)
		button.tooltip_text = button.title_label.text
		button.pressed.connect(_on_room_button_pressed.bind(room.id))
		button.pulse_transform_changed.connect(connections_layer.queue_redraw)
		room_buttons[room.id] = button
	_layout_rooms()
	info_label.hide()
	completed_overlay.visible = run_state.map_state.boss_visited()

# 第一层位于下方、Boss 位于球门；层数和数量完全来自真实状态。
# 透视按层纵深渐变：近端分支更宽、节点更大，远端向球场中心收拢，不改变真实连线和点击规则。
func _layout_rooms() -> void:
	if run_state == null or run_state.map_state == null:
		return
	var state = run_state.map_state
	var spacing: float = rows_container.size.y * 0.8 / maxf(state.layer_count - 1, 1)
	for layer in range(1, state.layer_count + 1):
		var rooms: Array = state.rooms_on_layer(layer)
		var depth := float(layer - 1) / maxf(state.layer_count - 1, 1)
		var half_spread := lerpf(0.25, 0.15, depth)
		var perspective_scale := lerpf(1.08, 0.82, depth)
		for i in range(rooms.size()):
			var button: Button = room_buttons.get(rooms[i].id)
			if button == null:
				continue
			var side := minf(64, spacing * 0.88) * perspective_scale * (1.35 if rooms[i].type == MAP_STATE.RoomType.BOSS else 1.0)
			side = minf(side, rows_container.size.x / maxf(rooms.size(), 1) * 0.8)
			var ui_scale: float = boss_ui_scale if rooms[i].type == MAP_STATE.RoomType.BOSS else (rest_ui_scale if rooms[i].type == MAP_STATE.RoomType.REST else monster_ui_scale)
			side *= ui_scale
			button.size = Vector2(side, side)
			# 名称字号同步放大，避免仅扩大名字底板而文字仍停留在旧尺寸。
			button.title_label.add_theme_font_size_override("font_size", roundi(10 * ui_scale))
			var x := rows_container.size.x * (0.5 if rooms.size() == 1 else (0.5 - half_spread + 2 * half_spread * i / maxf(rooms.size() - 1, 1)))
			var y := rows_container.size.y * 0.92 - (layer - 1) * spacing
			# 放大的 Boss 向球门上移，名字不压住下一层；底部节点完整点击范围收在容器内。
			if rooms[i].type == MAP_STATE.RoomType.BOSS:
				y -= side * 0.2
			button.position = Vector2(x - side * 0.5, clampf(y - side * 0.43, 0.0, maxf(rows_container.size.y - side, 0.0)))
	call_deferred("_refresh_connections")

func _refresh_connections() -> void:
	if run_state.map_state != null:
		connections_layer.configure(room_buttons, run_state.map_state)

# 名称预览沿用战斗派生种子，不消费全局随机数或提前写 enemy_id。
func _opponent_name(room: Dictionary) -> String:
	if room.type == MAP_STATE.RoomType.REST:
		return "休息"
	var cached: String = room.get("enemy_id", "")
	if not cached.is_empty():
		var path := "res://data/enemies/%s.tres" % cached
		return str(load(path).display_name) if ResourceLoader.exists(path) else "乌龟"
	var pool_path := "res://data/encounters/chapter_%d.tres" % run_state.chapter
	if not ResourceLoader.exists(pool_path):
		return "乌龟"
	var pool: Resource = load(pool_path)
	var rng := RandomNumberGenerator.new()
	rng.seed = run_state.seed + room.layer * 1000 + room.index * 100 + 17
	var enemy: Resource = pool.pick_enemy(room.type, rng)
	return str(enemy.display_name) if enemy != null else "乌龟"

# 返回按钮仅在地图实例内调整外观；暂停按钮保留通用图片样式。
func _style_header() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.04, 0.12, 0.95)
	style.border_color = Color(0.05, 0.55, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	var back: Button = $Header/BackButton
	back.text = "❮ 返回"
	back.add_theme_font_size_override("font_size", 13)
	for key in ["normal", "hover", "pressed"]:
		back.add_theme_stylebox_override(key, style)
	# 暂停按钮沿用通用场景的 pause 图片，避免地图初始化覆盖统一外观。

# 开始所选房间：只登记进行中房间，完成状态由奖励或休息结算提交。
func _on_room_button_pressed(room_id: String) -> void:
	if _is_scene_transitioning:
		return
	var state = run_state.map_state
	if state == null:
		return
	var room: Dictionary = state.begin_room(room_id)
	if room.is_empty():
		refresh_ui()
		return
	_is_scene_transitioning = true
	for button in room_buttons.values():
		button.disabled = true
		button.stop_pulse()
	# 进入内容场景前保存进行中房间，强制关闭后会回到同一安全入口而不会重掷路线。
	var save_service := get_node_or_null("/root/SaveService")
	run_state.resume_point = (
		run_state.ResumePoint.REST
		if room.type == MAP_STATE.RoomType.REST
		else run_state.ResumePoint.BATTLE
	)
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("run", "room_entered", {
			"chapter": run_state.chapter,
			"room_id": room.id,
			"room_type": room.type,
		})
	if save_service != null:
		save_service.save_game(run_state)
	if room.type == MAP_STATE.RoomType.REST:
		get_tree().change_scene_to_file("res://scenes/rest_room.tscn")
	else:
		# 战斗过场必须在地图仍可见时完成，按钮随即锁定，防止重复点击同一关卡。
		_is_scene_transitioning = true
		for button in room_buttons.values():
			button.disabled = true
		var bgm_service := get_node_or_null("/root/BgmService")
		if bgm_service != null:
			await bgm_service.prepare_battle_transition()
		get_tree().change_scene_to_file("res://scenes/battle.tscn")


# 返回主菜单放弃当前路线；地图进度保留在 RunState，重新开始新局才重置。
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
