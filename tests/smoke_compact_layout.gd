# 小屏布局冒烟测试：确保全部游戏与测试场景在 360×640 基准视口内不越界。
extends SceneTree

const TARGET_SIZE := Vector2(360, 640)
const TEST_SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/settings_screen.tscn",
	"res://scenes/pause_overlay.tscn",
	"res://scenes/card_drag_test.tscn",
	"res://scenes/character_feedback_test.tscn",
	"res://scenes/battle_logic_test.tscn",
	"res://scenes/deck_logic_test.tscn",
	"res://scenes/battle.tscn",
	"res://scenes/reward_screen.tscn",
	"res://scenes/map_screen.tscn",
	"res://scenes/rest_room.tscn",
	"res://scenes/result_screen.tscn",
]

var _failed := false


# 延迟运行以确保根视口可设置尺寸。
func _initialize() -> void:
	call_deferred("_run")


# 逐个实例化场景，等待一次布局更新后递归检查可见控件。
func _run() -> void:
	root.size = Vector2i(TARGET_SIZE)

	for scene_path in TEST_SCENES:
		var packed_scene: PackedScene = load(scene_path)
		var scene := packed_scene.instantiate()
		root.add_child(scene)
		await process_frame
		_check_control_tree(scene, scene_path)
		scene.free()

	if _failed:
		quit(1)
		return

	print("smoke_compact_layout: PASS (360x640)")
	quit()


# 检查当前控件矩形，并递归检查全部子节点。
func _check_control_tree(node: Node, scene_path: String) -> void:
	if node is Control and node.visible:
		var control := node as Control
		var rect: Rect2 = control.get_global_rect()
		var bottom_right: Vector2 = rect.position + rect.size
		var inside: bool = (
			rect.position.x >= -0.5
			and rect.position.y >= -0.5
			and bottom_right.x <= TARGET_SIZE.x + 0.5
			and bottom_right.y <= TARGET_SIZE.y + 0.5
		)
		if not inside:
			_failed = true
			push_error("%s: %s 越界，矩形为 %s" % [scene_path, node.get_path(), rect])

	for child in node.get_children():
		_check_control_tree(child, scene_path)
