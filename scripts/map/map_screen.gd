# 路线地图界面：按 RunState 地图状态生成三层房间按钮，只允许进入可进房间。
extends Control

const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const MAP_STATE := preload("res://scripts/map/map_state.gd")
const ROOM_NAMES := ["普通", "精英", "Boss", "休息"]
const ROOM_COLORS := {
	0: Color(0.88, 0.96, 1.0),
	1: Color(1.0, 0.82, 0.45),
	2: Color(1.0, 0.55, 0.5),
	3: Color(0.6, 0.95, 0.75),
}
const VISITED_COLOR := Color(0.55, 0.85, 0.9)
const LOCKED_COLOR := Color(0.4, 0.45, 0.48)
const BUTTON_SIZE := Vector2(96, 54)

@onready var title_label: Label = %TitleLabel
@onready var background: ColorRect = $Background
@onready var rows_container: VBoxContainer = %RowsContainer
@onready var connections_layer: Control = %ConnectionsLayer
@onready var info_label: Label = %InfoLabel
@onready var completed_overlay: ColorRect = %CompletedOverlay
@onready var missing_overlay: ColorRect = %MissingOverlay

# 房间ID到按钮视图的映射，供测试与刷新检查可进/锁定/已完成状态。
var room_buttons := {}
var run_state: Node


# 绑定本局状态并重建地图行；独立场景测试没有 Autoload 时创建局部状态。
func _ready() -> void:
	run_state = get_node_or_null("/root/RunState")
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
	refresh_ui()


# 依据当前地图状态重建全部房间按钮与完结提示；战斗/休息返回本场景时自动调用。
func refresh_ui() -> void:
	if run_state.map_state == null:
		completed_overlay.hide()
		missing_overlay.show()
		return
	missing_overlay.hide()
	var config: Resource = load("res://data/maps/map_chapter_%d.tres" % run_state.chapter)
	background.color = config.map_background_color
	title_label.text = "第 %d 章 · %s" % [run_state.chapter, config.chapter_name]
	_rebuild_rows()
	_update_info()
	completed_overlay.visible = run_state.map_state.boss_visited()


# 清除旧按钮并按层重建；第1层可进，其余状态由 MapState 决定。
func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	room_buttons.clear()
	var state = run_state.map_state
	for layer in range(1, state.layer_count + 1):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		rows_container.add_child(row)
		for room in state.rooms_on_layer(layer):
			var button := Button.new()
			button.custom_minimum_size = BUTTON_SIZE
			button.text = ("✓" if room.state == MAP_STATE.RoomState.VISITED else "") + ROOM_NAMES[room.type]
			button.add_theme_font_size_override("font_size", 17 if room.type == MAP_STATE.RoomType.BOSS else 15)
			button.pressed.connect(_on_room_button_pressed.bind(room.id))
			row.add_child(button)
			room_buttons[room.id] = button
			_apply_room_button_visual(button, room)
		# 层与层之间用向下箭头提示只能前进，不能返回同层其他路线。
		if layer < state.layer_count:
			var arrow := Label.new()
			arrow.text = "↓"
			arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			arrow.add_theme_color_override("font_color", Color(0.5, 0.62, 0.66))
			rows_container.add_child(arrow)
	# 容器布局在当前帧末完成，延迟后再读取按钮全局位置绘制真实稀疏连线。
	call_deferred("_refresh_connections")


# 将按钮映射与纯逻辑地图交给独立绘图层，地图状态本身不持有任何 UI 引用。
func _refresh_connections() -> void:
	if run_state.map_state == null:
		return
	connections_layer.configure(room_buttons, run_state.map_state)


# 按房间状态上色：可进高亮房型色，已完成偏蓝，锁定置灰且禁用。
func _apply_room_button_visual(button: Button, room: Dictionary) -> void:
	var color: Color
	match room.state:
		MAP_STATE.RoomState.ATTAINABLE:
			color = ROOM_COLORS.get(room.type, Color.WHITE)
		MAP_STATE.RoomState.VISITED:
			color = VISITED_COLOR
		_:
			color = LOCKED_COLOR
	button.disabled = room.state != MAP_STATE.RoomState.ATTAINABLE
	button.add_theme_color_override("font_color", color)
	button.tooltip_text = "%s（seed 房间 %s）" % [ROOM_NAMES[room.type], room.id]


# 汇总本局生命、牌库与剩余可进房间数，方便快速判断是否适合继续推进。
func _update_info() -> void:
	var state = run_state.map_state
	var attainable = state.get_attainable_rooms().size()
	info_label.text = "生命 %d/%d　牌库 %d　可进 %d　seed %d" % [
		run_state.player_hp, run_state.max_hp,
		run_state.deck_card_ids.size(), attainable, run_state.seed,
	]


# 开始所选房间：只登记进行中房间，完成状态由奖励或休息结算提交。
func _on_room_button_pressed(room_id: String) -> void:
	var state = run_state.map_state
	if state == null:
		return
	var room: Dictionary = state.begin_room(room_id)
	if room.is_empty():
		refresh_ui()
		return
	if room.type == MAP_STATE.RoomType.REST:
		get_tree().change_scene_to_file("res://scenes/rest_room.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/battle.tscn")


# 返回主菜单放弃当前路线；地图进度保留在 RunState，重新开始新局才重置。
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
