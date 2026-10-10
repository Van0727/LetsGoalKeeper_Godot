# 手机战斗布局验收：覆盖基准、长屏、宽屏和恢复尺寸，防止操作区悬在上半屏。
extends SceneTree

const BATTLE := preload("res://scenes/battle.tscn")
const BOTTOM_NODES := ["HandLayer", "Footer", "PlayerStatus", "EnergyPanel", "DragThresholdGuide", "RhythmAccentWaveform", "StatusLabel", "ItemDetailPopup"]
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


# 使用真实战斗场景，按根控件尺寸模拟浏览器可用视口；尺寸恢复用于检查重复调整的累计误差。
func _run() -> void:
	var battle := BATTLE.instantiate()
	root.add_child(battle)
	# 战斗启动含转场音效等待，完成后再检查和释放，避免悬挂的初始化协程。
	await create_timer(2.0).timeout
	battle.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	battle.size = Vector2(360, 640)
	await process_frame
	var baseline := {}
	for node_name in BOTTOM_NODES + ["RhythmWaveform", "RhythmFeedback"]:
		baseline[node_name] = battle.get_node(node_name).position.y
	for target in [Vector2(360, 640), Vector2(360, 780), Vector2(360, 900), Vector2(480, 640), Vector2(360, 640)]:
		battle.size = target
		await process_frame
		for node_name in BOTTOM_NODES + ["RhythmWaveform", "RhythmFeedback"]:
			var control := battle.get_node(node_name) as Control
			var fraction := 1.0 if node_name in BOTTOM_NODES else 0.5
			var expected: float = baseline[node_name] + (target.y - 640.0) * fraction
			_check(absf(control.position.y - expected) < 0.1, "%s 在 %s 未正确跟随锚点" % [node_name, target])
		for node_name in ["HandLayer", "PlayerStatus", "OwnedItemBar"]:
			var control := battle.get_node(node_name) as Control
			_check(control.position.y >= 0 and control.position.y + control.size.y <= target.y + 0.5, "%s 在 %s 垂直越界" % [node_name, target])
		_check(battle.get_node("HandLayer").position.y >= battle.get_node("RhythmFeedback").position.y + battle.get_node("RhythmFeedback").size.y, "手牌与节拍区重叠")
		_check(battle.get_node("Background").size.is_equal_approx(target), "背景未覆盖视口")
	battle.free()
	# 主菜单入口也应跟随底边；校验长屏后恢复基准，避免按钮偏移累积。
	var menu := load("res://scenes/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	await process_frame
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	menu.size = Vector2(360, 640)
	await process_frame
	var menu_baseline := {}
	for node_name in ["StartButton", "ContinueButton", "TestBattleButton"]:
		menu_baseline[node_name] = menu.get_node(node_name).position.y
	for height in [780.0, 900.0, 640.0]:
		menu.size = Vector2(360, height)
		await process_frame
		for node_name in menu_baseline:
			var control := menu.get_node(node_name) as Control
			_check(absf(control.position.y - menu_baseline[node_name] - height + 640.0) < 0.1, "菜单按钮未跟随底边：%s" % node_name)
	menu.free()
	await process_frame
	if not _failed:
		print("smoke_mobile_battle_layout: PASS")
	quit(1 if _failed else 0)


# 失败时保留具体节点和目标尺寸，便于复现布局回归。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
