# 舞台灯光验收：拍首快速到位及余拍保持、独立动停、停拍上限、跳帧/回退、暂停和失败回退。
extends SceneTree

const BATTLE := preload("res://scenes/battle.tscn")
var _failed := false

func _initialize() -> void:
	call_deferred("_run")

# 不修改正式设置；注入音乐时刻检查确定性状态，并保存真实 GPU 渲染截图供目视验收。
func _run() -> void:
	root.size = Vector2i(360, 640)
	root.get_node("RunState").start_new_run(7302)
	var battle: Control = BATTLE.instantiate()
	root.add_child(battle)
	var deadline := Time.get_ticks_msec() + 5000
	while battle.hand_layer.get_child_count() == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	_assert(battle.hand_layer.get_child_count() > 0, "真实战斗完成手牌入场")
	await create_timer(0.35).timeout
	battle.set_process(false)
	var lights: Control = battle.stage_lights
	_assert(lights.LAMP_PIXELS.size() == 6, "左右各三个灯光原点")
	_assert(lights.mouse_filter == Control.MOUSE_FILTER_IGNORE, "灯光不拦截交互")
	_assert(battle.background.texture.get_size() == Vector2(941, 1672), "背景尺寸和资源正确")
	lights.set_music_timing(0.0, 0.6, 0.025)
	_assert(lights.get_light_state().pulse == 0.0, "前奏不闪拍")
	lights.set_music_timing(0.625, 0.6, 0.025)
	var first: Dictionary = lights.get_light_state()
	_assert(is_equal_approx(first.pulse, 1.0), "拍点提亮")
	await _capture("beat_360")
	# 固定种子跨大量拍验收约束；概率只统计未被强制覆盖的决策，不能把总体移动率误当 50%。
	lights.reset_motion(7302)
	var previous_stops := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var free_decisions := 0
	var free_moves := 0
	var forced_moves := 0
	var independent := false
	for beat in range(512):
		lights.set_music_timing(0.025 + (beat + 0.05) * 0.6, 0.6, 0.025)
		var early: Dictionary = lights.get_light_state()
		lights.set_music_timing(0.025 + (beat + 0.25) * 0.6, 0.6, 0.025)
		var arrived: Dictionary = lights.get_light_state()
		lights.set_music_timing(0.025 + (beat + 0.8) * 0.6, 0.6, 0.025)
		var late: Dictionary = lights.get_light_state()
		_assert(arrived.angles == late.angles, "四分之一拍到位后余拍角度保持")
		_assert(early.moving == late.moving, "同拍重复采样不重新抽签")
		for index in range(6):
			if previous_stops[index] == 2:
				_assert(early.moving[index] == 1, "连续停两拍后强制移动")
				forced_moves += 1
			else:
				free_decisions += 1
				free_moves += early.moving[index]
			_assert(late.stop_counts[index] <= 2, "不存在连续三拍停住")
			if early.moving[index] == 0:
				_assert(early.angles[index] == late.angles[index], "停拍角度严格保持")
			else:
				_assert(absf(early.angles[index] - late.angles[index]) > 0.05, "移动拍有明显扫动")
			_assert(absf(late.angles[index]) >= 0.099 and absf(late.angles[index]) <= 0.541, "角度在安全朝内范围")
			independent = independent or early.moving[index] != early.moving[0]
		previous_stops = late.stop_counts
	var ratio := float(free_moves) / free_decisions
	_assert(ratio > 0.45 and ratio < 0.55, "自由决策移动率接近一半")
	_assert(forced_moves > 0 and independent, "覆盖强制移动且各灯决策独立")
	print("stage_lights random: free_move_ratio=", ratio, " forced_moves=", forced_moves)
	var sequential: Dictionary = lights.get_light_state()
	lights.reset_motion(7302)
	lights.set_music_timing(0.025 + 511.8 * 0.6, 0.6, 0.025)
	_assert(lights.get_light_state() == sequential, "跳帧补拍与逐拍推进一致")
	# 回退重放和循环连续拍衔接，不因四拍小节归零或帧率差异重新抽签。
	lights.set_music_timing(1.525, 0.6, 0.025)
	var rewind: Dictionary = lights.get_light_state()
	lights.reset_motion(7302)
	lights.set_music_timing(1.525, 0.6, 0.025)
	_assert(lights.get_light_state() == rewind, "时间回退按相同种子复现")
	await _capture("between_360")
	for boundary in [1.0, 2.0, 3.0, 4.0, 32.0]:
		lights.set_music_timing(0.025 + (boundary - 0.0001) * 0.6, 0.6, 0.025)
		var before: PackedFloat32Array = lights.get_light_state().angles
		lights.set_music_timing(0.025 + (boundary + 0.0001) * 0.6, 0.6, 0.025)
		for index in range(6):
			_assert(absf(lights.get_light_state().angles[index] - before[index]) < 0.0001, "随机动停拍点与循环边界连续")
	var frozen: Dictionary = lights.get_light_state()
	paused = true
	await process_frame
	await process_frame
	_assert(lights.get_light_state() == frozen, "暂停冻结灯光")
	paused = false
	for duration in [0.0, -1.0, NAN]:
		lights.set_music_timing(1.0, duration, 0.025)
		_assert(lights.get_light_state().pulse == 0.0, "非法速度恢复弱光")
		_assert(lights.get_light_state().angles == frozen.angles, "错误输入冻结角度不扰乱随机状态")
		for angle in lights.get_light_state().angles:
			_assert(is_finite(angle), "失败路径不产生非有限角度")
	lights.set_music_timing(INF, 0.6, 0.025)
	_assert(lights.get_light_state().pulse == 0.0, "非法音乐时间安全回退")
	root.size = Vector2i(480, 640)
	await process_frame
	_assert(lights.get_global_rect() == battle.background.get_global_rect(), "宽屏灯光与背景范围相同")
	lights.set_music_timing(0.625, 0.6, 0.025)
	await _capture("beat_480")
	battle.queue_free()
	await process_frame
	print("smoke_stage_lights: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)

func _capture(stage: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	_assert(root.get_texture().get_image().save_png("res://output/stage_lights_%s.png" % stage) == OK, "截图保存")

func _assert(condition: bool, description: String) -> void:
	if not condition:
		_failed = true
		push_error(description)
