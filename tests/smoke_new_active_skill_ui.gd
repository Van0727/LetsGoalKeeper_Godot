# 新主动技真实界面验收：成功 QTE 后手套及随机连射均在命中时扣血，防御不主动消耗护盾。
extends SceneTree

const SCENE := preload("res://scenes/battle.tscn")
const ENEMY := preload("res://data/enemies/enemy_turtle.tres")
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var screen = SCENE.instantiate()
	var hurt_sounds := [0]
	screen.enemy_active_skill_hurt_audio_triggered.connect(func() -> void: hurt_sounds[0] += 1)
	root.add_child(screen)
	var ready_deadline := Time.get_ticks_msec() + 5000
	while screen._battle_generation == 0 and Time.get_ticks_msec() < ready_deadline:
		await process_frame
	check(is_equal_approx(screen._get_active_skill_ball_scale(3), 3.2), "三层攻击保留原足球尺寸")
	check(is_equal_approx(screen._get_active_skill_ball_scale(4), 3.2 * 1.2), "四层攻击尺寸增加20%")
	check(is_equal_approx(screen._get_active_skill_ball_scale(5), 3.2 * 1.4), "五层攻击尺寸线性增加40%")
	# 覆盖未满仅边框着色、满额填色及对应图标，验证同类型从不可释放到可释放时样式也刷新。
	for kind in [0, 1, 2]:
		screen._input_locked = false
		screen.controller.combo_state.card_type = kind
		screen.controller.combo_state.count = 1
		screen._update_input_state()
		var style: StyleBoxFlat = screen.skill_button.get_theme_stylebox("disabled")
		check(style.bg_color == screen._skill_button_default_styles.disabled.bg_color, "未满累计保持默认内部底色")
		check(style.border_color == screen.SKILL_TYPE_COLORS[kind].lightened(0.35), "未满累计仅边框显示类型颜色")
		check(screen.get_node("%SkillIcon").texture == screen.SKILL_TYPE_ICONS[kind], "图标随主动技类型变化")
		check(not screen.skill_pulse_ring.visible, "未达到释放条件不播放特效")
		screen.controller.combo_state.count = 3
		screen._update_input_state()
		check(screen.skill_button.get_theme_stylebox("normal").bg_color == screen.SKILL_TYPE_COLORS[kind], "可释放时填充类型色")
		check(screen.skill_pulse_ring.visible, "可释放时显示特效")
		check(screen.skill_pulse_ring._type_color == screen.SKILL_TYPE_COLORS[kind], "特效颜色与类型一致")
		screen._on_rhythm_beat_reached(0, 0)
		screen.skill_pulse_ring._process(0.05)
		check(screen.skill_pulse_ring._visual_amplitude > 0.9, "可释放时拍点触发特效动画")
	screen.controller.combo_state.clear()
	screen._update_input_state()
	check(not screen.skill_pulse_ring.visible, "累计清空后关闭特效")
	check(screen.skill_button.scale == screen._skill_button_base_scale, "关闭后恢复按钮缩放")
	check(screen.skill_button.get_theme_stylebox("disabled").bg_color == screen._skill_button_default_styles.disabled.bg_color, "无累计恢复默认底色")
	for kind in [1, 2]:
		hurt_sounds[0] = 0
		screen.run_state.start_new_run(7100 + kind)
		screen.start_new_battle(ENEMY)
		screen.ball_flight.playback_speed = 2.0
		screen.controller.player.shield = 12
		screen.controller.combo_state.card_type = kind
		screen.controller.combo_state.count = 3
		screen._input_locked = true
		screen._play_active_skill_qte_result(screen._skills_by_type[kind], {"miss": 1})
		check(screen.controller.enemy.health == 50, "发射时生命保持不变")
		await create_timer(0.03).timeout
		check(screen.controller.enemy.health == 50, "飞行中不提前扣血")
		if kind == 1:
			check(screen.ball_flight._glove_projectile.visible, "防御主动技显示手套")
		var deadline := Time.get_ticks_msec() + 4000
		var values: Array[int] = []
		while (screen._input_locked or screen._is_presenting_resolution) and Time.get_ticks_msec() < deadline:
			var hp: int = screen.controller.enemy.health
			if hp < 50 and (values.is_empty() or values[-1] != hp):
				values.append(hp)
			await process_frame
		check(not screen._input_locked, "主动技完成后恢复输入")
		check(screen.controller.enemy.health == (14 if kind == 1 else 32), "主动技最终伤害正确")
		if kind == 2:
			check(values == [44, 38, 32], "随机射门逐颗刷新生命")
		check(screen.controller.player.shield == (0 if kind == 1 else 9), "防御释放清盾，技能保留护盾抵挡反伤")
		check(hurt_sounds[0] == 3, "三段主动技每次真实命中各播放一次怪物受击音")
	screen.free()
	if not failed:
		print("smoke_new_active_skill_ui: PASS")
	quit(1 if failed else 0)

# 保留具体失败场景以便判断命中、显示与输入锁的边界。
func check(value: bool, label: String) -> void:
	if not value:
		failed = true
		push_error(label)
