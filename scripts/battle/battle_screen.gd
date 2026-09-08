# 可玩战斗界面：连接战斗核心、牌堆和拖拽输入，并按射门动画顺序呈现竖屏战斗反馈。
extends Control

signal attack_impact_audio_triggered

const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const DECK_STATE := preload("res://scripts/cards/deck_state.gd")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const CARD_VIEW_SCENE := preload("res://scenes/card_view.tscn")
const BALL_FLIGHT_SCENE := preload("res://scenes/ball_flight.tscn")
const HIT_AUDIO_STREAM := preload("res://sound/sounds/hit.mp3")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")
const BEAR := preload("res://data/enemies/enemy_bear.tres")
const TRAINING_BOSS := preload("res://data/enemies/enemy_training_raccoon_boss.tres")
const SUPER_ATTACK := preload("res://data/skills/skill_super_attack.tres")
const SUPER_DEFENSE := preload("res://data/skills/skill_super_defense.tres")
const SUPER_ABILITY := preload("res://data/skills/skill_super_ability.tres")

const STARTING_HAND_SIZE := 3
const CARD_SIZE := Vector2(104, 146)
const CARD_GAP := 6.0
const REST_ROOM_TYPE := 3

@onready var controller: BattleController = %BattleController
@onready var background: ColorRect = $Background
@onready var player_display: CharacterDisplay = %PlayerDisplay
@onready var enemy_display: CharacterDisplay = %EnemyDisplay
# 使用基础控件类型避免新增脚本的全局类缓存尚未刷新时阻塞战斗场景解析。
@onready var drag_threshold_guide: Control = %DragThresholdGuide
# 使用基础节点类型避免首次导入时全局类缓存尚未登记 BallFlight 而阻塞战斗场景解析。
@onready var ball_flight: Node2D = %BallFlight
# 节拍时钟和反馈控件使用基础类型，避免首次导入新增全局类时出现脚本缓存顺序问题。
@onready var rhythm_clock: Node = %RhythmClock
@onready var rhythm_feedback: Control = %RhythmFeedback
@onready var shot_type_label: Label = %ShotTypeLabel
@onready var turn_label: Label = %TurnLabel
@onready var intent_label: Label = %IntentLabel
@onready var energy_label: Label = %EnergyLabel
@onready var status_label: Label = %StatusLabel
@onready var hand_layer: Control = %HandLayer
@onready var pile_label: Label = %PileLabel
@onready var skill_button: Button = %SkillButton
@onready var end_turn_button: Button = %EndTurnButton
@onready var gm_menu_button: Button = %GMMenuButton
@onready var gm_overlay: ColorRect = %GMOverlay
@onready var gm_skip_button: Button = %GMSkipButton
@onready var result_overlay: ColorRect = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var result_detail: Label = %ResultDetail
@onready var result_action_button: Button = %RestartButton

var deck_state := DECK_STATE.new()
var _input_locked := false
var _enemy_index := 0
var _enemy_sequence: Array[Resource] = [TURTLE, BEAR, TRAINING_BOSS]
var _last_victory := false
var _reward_service := REWARD_SERVICE.new()
var run_state: Node
# 卡牌结算期间核心仍同步计算；这里缓存逐段事件并按足球命中顺序更新可见状态。
var _is_presenting_resolution := false
var _gm_menu_open := false
var _pending_effect_events: Array[Dictionary] = []
var _pending_battle_result = null
# 当前出牌对应的音频拍点；所有分段发射和命中都从同一锚点计算，避免逐帧计时累积漂移。
var _resolution_beat_anchor_time := 0.0
var _visual_rng := RandomNumberGenerator.new()
# 实战命中音统一由常驻播放器输出；多声部允许攻击间隔短于音效长度时每段仍清晰触发。
var _attack_hit_audio: AudioStreamPlayer
var _skills_by_type := {
	0: SUPER_ATTACK,
	1: SUPER_DEFENSE,
	2: SUPER_ABILITY,
}


# 初始化信号和一场固定种子的可玩战斗，便于复现输入与结算问题。
func _ready() -> void:
	_attack_hit_audio = AudioStreamPlayer.new()
	_attack_hit_audio.name = "AttackHitAudio"
	_attack_hit_audio.stream = HIT_AUDIO_STREAM
	_attack_hit_audio.bus = &"SFX"
	_attack_hit_audio.max_polyphony = 8
	add_child(_attack_hit_audio)
	run_state = get_node_or_null("/root/RunState")
	# 独立场景测试没有 Autoload 时创建局部状态，正式游戏始终使用全局实例。
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
	_apply_chapter_theme()
	controller.log_added.connect(_on_log_added)
	controller.state_changed.connect(_on_state_changed)
	controller.effect_resolved.connect(_on_effect_resolved)
	controller.battle_finished.connect(_on_battle_finished)
	ball_flight.shot_started.connect(_on_shot_started)
	rhythm_clock.beat_reached.connect(_on_rhythm_beat_reached)
	# 参考布局把敌人作为上方视觉焦点，玩家状态则压缩到底部生命栏。
	enemy_display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.ENEMY)
	player_display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.PLAYER_BAR)
	start_new_battle()


# 节拍圆环每帧读取音频时钟，仅作为视觉提示；松手判定不会依赖这段 UI 更新。
func _process(_delta: float) -> void:
	if rhythm_clock != null and rhythm_feedback != null:
		rhythm_feedback.set_beat_progress(rhythm_clock.get_beat_progress())


# 战斗背景固定为参考界面的蓝灰球场色，避免章节色把上下信息区切成不同底色。
func _apply_chapter_theme() -> void:
	background.color = Color(0.17, 0.29, 0.45, 1.0)


# 使用本局牌库和房间敌人重置战斗：路线地图进入的房间按房型从章节池选敌。
func start_new_battle(enemy_definition: Resource = null) -> void:
	result_overlay.hide()
	gm_overlay.hide()
	_gm_menu_open = false
	ball_flight.hide()
	shot_type_label.hide()
	_pending_effect_events.clear()
	_pending_battle_result = null
	_is_presenting_resolution = false
	rhythm_clock.start_music()
	status_label.text = "拖动卡牌到绿色区域出牌"
	_input_locked = true
	var starting_deck: Array[Resource] = []
	for card_id in run_state.deck_card_ids:
		var card := _reward_service.get_card_by_id(card_id)
		if card != null:
			starting_deck.append(card)
	var selected_enemy := enemy_definition
	var current_room: Dictionary = run_state.get_current_room()
	if selected_enemy == null and not current_room.is_empty():
		# 正式地图流程：休息房不应进入战斗，普通/精英/Boss 房型与遭遇池 Tier 序号一致。
		if current_room.type != REST_ROOM_TYPE:
			selected_enemy = _select_room_enemy(current_room)
	if selected_enemy == null:
		# 保留阶段 4 演示入口：没有地图房间上下文（测试直连）时按胜场循环展示三类敌人。
		_enemy_index = run_state.battles_won % _enemy_sequence.size()
		selected_enemy = _enemy_sequence[_enemy_index]
	var current_seed: int = run_state.seed + run_state.battles_won * 101
	# 表现随机数使用独立种子，避免弹道左右选择改变战斗数值的确定性。
	_visual_rng.seed = current_seed * 31 + 7
	deck_state.setup(starting_deck, current_seed)
	controller.setup(current_seed, selected_enemy, run_state.damage_modifiers)
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("battle", "started", {
			"seed": current_seed,
			"chapter": run_state.chapter,
			"enemy_id": selected_enemy.enemy_id,
		})
	controller.player.max_health = run_state.max_hp
	controller.player.health = clampi(run_state.player_hp, 1, run_state.max_hp)
	player_display.configure(controller.player.display_name, controller.player.max_health, Color(0.45, 0.75, 1.0))
	enemy_display.configure(controller.enemy.display_name, controller.enemy.max_health, Color(1.0, 0.55, 0.42))
	deck_state.draw_cards(STARTING_HAND_SIZE)
	_input_locked = false
	_rebuild_hand()
	_refresh_all()
	if not selected_enemy.passive_description.is_empty():
		status_label.text = "%s被动：%s" % [selected_enemy.display_name, selected_enemy.passive_description]


# 尝试打出指定手牌；可选节奏上下文让自动测试和非拖拽入口继续使用完整基础伤害。
func try_play_hand_card(hand_index: int, rhythm_result: Dictionary = {}) -> bool:
	if _input_locked or controller.phase != BATTLE_CONTROLLER.Phase.PLAYER_TURN:
		return false
	if hand_index < 0 or hand_index >= deck_state.hand.size():
		return false

	_input_locked = true
	_is_presenting_resolution = true
	_pending_effect_events.clear()
	_pending_battle_result = null
	var timing_result := rhythm_result
	if timing_result.is_empty():
		timing_result = rhythm_clock.judge_at(rhythm_clock.get_music_time())
	_resolution_beat_anchor_time = float(timing_result.get("target_time", rhythm_clock.get_music_time()))
	_update_input_state()
	# 实战界面只在足球抵达目标拍点时提交伤害；出牌阶段仍立即支付费用并移入弃牌堆。
	var played := controller.play_card_from_hand(deck_state, hand_index, rhythm_result, true)
	if not played:
		_is_presenting_resolution = false
		_input_locked = false
		status_label.text = "无法打出这张牌，请检查能量"
		_update_input_state()
		return false

	status_label.text = "正在结算卡牌效果"
	call_deferred("_play_pending_resolution")
	return true


# 有效松手时立即采样音频播放头；判定结果先反馈给玩家，再作为只读上下文提交结算。
func _on_card_played(card_view: DraggableCard) -> void:
	if card_view is BattleCardView:
		var rhythm_result: Dictionary = rhythm_clock.judge_now()
		rhythm_feedback.show_judgement(rhythm_result)
		try_play_hand_card(card_view.hand_index, rhythm_result)


# 拖拽开始时只显示横向虚线；尚未越线前不显示释放提示。
func _on_card_drag_started(_card_view: DraggableCard) -> void:
	drag_threshold_guide.begin_drag()


# 拖动过程中实时同步越线状态，使鼠标和触摸都在有效释放前得到明确提示。
func _on_card_drag_moved(
	_card_view: DraggableCard,
	_pointer_position: Vector2,
	valid_drop: bool
) -> void:
	drag_threshold_guide.set_qualified(valid_drop)


# 松手后隐藏整条引导；无效释放由卡牌自身负责回弹到原位置。
func _on_card_drag_finished(_card_view: DraggableCard, valid_drop: bool) -> void:
	drag_threshold_guide.end_drag()
	if not valid_drop:
		status_label.text = "未越过出牌线，卡牌已返回手牌"


# 音频跨过新拍点时触发一次表现脉冲，并显示当前小节内的拍位。
func _on_rhythm_beat_reached(beat_index: int, _bar_index: int) -> void:
	rhythm_feedback.pulse_beat(beat_index, rhythm_clock.beats_per_bar)


# 结束回合先弃掉剩余手牌，再执行敌人行动；存活时进入新回合并重新抽三张。
func _on_end_turn_pressed() -> void:
	if _input_locked or controller.phase != BATTLE_CONTROLLER.Phase.PLAYER_TURN:
		return
	_input_locked = true
	_update_input_state()
	var discarded := deck_state.discard_hand()
	status_label.text = "弃掉 %d 张手牌，敌人行动" % discarded
	controller.end_player_turn()
	if controller.phase == BATTLE_CONTROLLER.Phase.PLAYER_TURN:
		deck_state.draw_cards(STARTING_HAND_SIZE)
	call_deferred("_finish_resolution")


# 释放当前卡牌类型对应的主动技，结算帧内与卡牌共用同一输入锁。
func _on_skill_pressed() -> void:
	if _input_locked:
		return
	var skill: Resource = _get_current_skill()
	if skill == null:
		return
	_input_locked = true
	_update_input_state()
	if not controller.play_active_skill(skill):
		_input_locked = false
		_update_input_state()
		return
	status_label.text = "%s已结算" % skill.display_name
	call_deferred("_finish_resolution")


# 按当前章节遭遇池和房间房型确定敌人；同房间首次选择后缓存敌人ID，保证可复现。
func _select_room_enemy(room: Dictionary) -> Resource:
	var cached_id: String = run_state.map_state.get_enemy_id(room.id)
	if not cached_id.is_empty():
		var cached_path := "res://data/enemies/%s.tres" % cached_id
		if ResourceLoader.exists(cached_path):
			return load(cached_path)
		_record_missing_encounter("enemy", {"enemy_id": cached_id})
		return TURTLE
	var pool_path := "res://data/encounters/chapter_%d.tres" % run_state.chapter
	if not ResourceLoader.exists(pool_path):
		push_error("找不到章节遭遇池：%s，回退到乌龟" % pool_path)
		_record_missing_encounter("encounter_pool", {"chapter": run_state.chapter})
		return TURTLE
	var pool: Resource = load(pool_path)
	var rng := RandomNumberGenerator.new()
	# 敌人随机数由本局seed与房间位置共同派生，同一局内重进同一房间会得到同一个敌人。
	rng.seed = run_state.seed + room.layer * 1000 + room.index * 100 + 17
	var enemy: Resource = pool.pick_enemy(room.type, rng)
	if enemy == null:
		push_error("第%d章%s房间遭遇池为空，回退到乌龟" % [run_state.chapter, room.type])
		_record_missing_encounter("enemy_pool_entry", {
			"chapter": run_state.chapter,
			"room_type": room.type,
		})
		return TURTLE
	run_state.map_state.set_enemy_id(room.id, enemy.enemy_id)
	return enemy


# 遭遇资源异常只记录稳定 ID、章节和房型，绝不导出本机资源绝对路径。
func _record_missing_encounter(resource_type: String, fields: Dictionary) -> void:
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics == null:
		return
	var details := fields.duplicate(true)
	details["resource_type"] = resource_type
	diagnostics.record("resource", "missing", details)


# 仅在玩家可操作时打开 GM 二级面板；面板期间暂停卡牌、技能和回合输入。
func _on_gm_menu_pressed() -> void:
	if _input_locked or controller.phase != BATTLE_CONTROLLER.Phase.PLAYER_TURN:
		return
	_gm_menu_open = true
	gm_overlay.show()
	_update_input_state()


# 关闭 GM 面板并恢复此前的战斗输入状态，不改变任何核心数值。
func _on_gm_close_pressed() -> void:
	_gm_menu_open = false
	gm_overlay.hide()
	_update_input_state()


# GM 跳过从二级面板进入统一胜利出口；控制器负责绕过护盾和反伤。
func _on_gm_skip_pressed() -> void:
	if _input_locked:
		return
	_gm_menu_open = false
	gm_overlay.hide()
	_input_locked = true
	_update_input_state()
	if not controller.debug_force_victory():
		_input_locked = false
		_update_input_state()


# 核心结算后的下一帧才恢复输入，确保一次指针释放最多触发一张牌。
func _finish_resolution() -> void:
	_rebuild_hand()
	_input_locked = controller.phase == BATTLE_CONTROLLER.Phase.FINISHED
	_refresh_all()


# 核心状态变化发生在同一帧时先保持当前血条，等待各段动画命中后再逐步更新。
func _on_state_changed() -> void:
	if _is_presenting_resolution:
		return
	_refresh_all()


# 依据当前手牌创建横向卡牌视图；界面节点是运行实例，不修改卡牌 Resource。
func _rebuild_hand() -> void:
	for child in hand_layer.get_children():
		child.queue_free()

	var hand_width := deck_state.hand.size() * CARD_SIZE.x
	if deck_state.hand.size() > 1:
		hand_width += (deck_state.hand.size() - 1) * CARD_GAP
	var start_x := (hand_layer.size.x - hand_width) * 0.5
	for index in range(deck_state.hand.size()):
		var card_view: BattleCardView = CARD_VIEW_SCENE.instantiate()
		hand_layer.add_child(card_view)
		card_view.position = Vector2(start_x + index * (CARD_SIZE.x + CARD_GAP), 0)
		card_view.size = CARD_SIZE
		# 阈值采用全局坐标，释放指针高于虚线才允许结算；无需可见圆形落点。
		card_view.drop_threshold_y = drag_threshold_guide.global_position.y
		card_view.card_played.connect(_on_card_played)
		card_view.drag_started.connect(_on_card_drag_started)
		card_view.drag_moved.connect(_on_card_drag_moved)
		card_view.drag_finished.connect(_on_card_drag_finished)
		card_view.configure(deck_state.hand[index], index)
	_update_input_state()


# 同步双方生命、护盾、能量、回合、意图以及牌堆计数。
func _refresh_all() -> void:
	player_display.set_health(controller.player.health)
	player_display.set_shield(controller.player.shield)
	enemy_display.set_health(controller.enemy.health)
	enemy_display.set_shield(controller.enemy.shield)
	turn_label.text = "第 %d 回合 · %s" % [controller.turn_number, controller.get_phase_text()]
	intent_label.text = "意图：%s" % controller.get_enemy_intent_text()
	energy_label.text = "能量  %d / %d" % [controller.player.energy, controller.player.max_energy]
	pile_label.text = "抽牌 %d　弃牌 %d" % [deck_state.draw_pile.size(), deck_state.discard_pile.size()]
	_update_input_state()


# 费用不足的卡牌保持可见但禁止拖拽；结算、结束和 GM 面板统一锁住战斗操作。
func _update_input_state() -> void:
	var can_act := (
		not _input_locked
		and not _gm_menu_open
		and controller.phase == BATTLE_CONTROLLER.Phase.PLAYER_TURN
	)
	end_turn_button.disabled = not can_act
	gm_menu_button.disabled = (
		_input_locked
		or _gm_menu_open
		or controller.phase == BATTLE_CONTROLLER.Phase.FINISHED
	)
	gm_skip_button.disabled = _input_locked or controller.phase == BATTLE_CONTROLLER.Phase.FINISHED
	var current_skill := _get_current_skill()
	var combo_count: int = controller.combo_state.count
	if current_skill == null:
		skill_button.text = "连击 0/3"
	else:
		skill_button.text = "%s %d/3" % [current_skill.display_name, combo_count]
	skill_button.disabled = not can_act or not controller.combo_state.can_activate()
	for child in hand_layer.get_children():
		if child is BattleCardView:
			var affordable: bool = controller.player.can_spend_energy(child.card_definition.cost)
			child.set_interaction_enabled(can_act and affordable)
			child.modulate = Color.WHITE if can_act and affordable else Color(0.55, 0.55, 0.55, 0.82)


# 根据当前连击类型取得三种主动技能之一；无连击时不提供技能。
func _get_current_skill() -> Resource:
	return _skills_by_type.get(controller.combo_state.card_type)


# 卡牌结算期间只入队；其他来源的事件仍即时反馈，保持结束回合等既有流程响应速度。
func _on_effect_resolved(event: Dictionary) -> void:
	if _is_presenting_resolution:
		_pending_effect_events.append(event)
		return
	_apply_effect_feedback(event)


# 按核心事件顺序播放；连续攻击按配置的发射间隔并发飞行，每一段命中时才刷新对应快照。
func _play_pending_resolution() -> void:
	var event_index := 0
	while event_index < _pending_effect_events.size():
		var event := _pending_effect_events[event_index]
		if _is_enemy_shot_event(event):
			var shot_events: Array[Dictionary] = []
			while event_index < _pending_effect_events.size() and _is_enemy_shot_event(_pending_effect_events[event_index]):
				shot_events.append(_pending_effect_events[event_index])
				event_index += 1
			await _play_shot_group(shot_events)
			continue
		_apply_effect_feedback(event)
		event_index += 1
	_pending_effect_events.clear()
	_is_presenting_resolution = false
	if _pending_battle_result != null:
		var victory: bool = _pending_battle_result
		_pending_battle_result = null
		_finalize_battle_result(victory)
		return
	status_label.text = "卡牌已结算"
	_finish_resolution()


# 仅把带弹道的对敌伤害纳入飞球队列；自伤和非攻击效果仍保持即时、严格的数组顺序。
func _is_enemy_shot_event(event: Dictionary) -> bool:
	return (
		event.get("type", "") == "damage"
		and event.get("target") == controller.enemy
		and event.get("shot_type", 0) != 0
	)


# 相邻段从出牌时刻起按固定拍数错开发射；每个实例独立飞行，全部命中后才继续后续效果。
func _play_shot_group(events: Array[Dictionary]) -> void:
	var completion := {"remaining": events.size()}
	for index in range(events.size()):
		var event := events[index]
		var interval_beats: float = float(event.get("multi_hit_interval_beats", 0.5))
		var launch_music_time: float = _resolution_beat_anchor_time + rhythm_clock.beats_to_seconds(
			interval_beats * index
		)
		await _wait_for_shot_launch(launch_music_time)
		var flight := ball_flight if index == 0 else BALL_FLIGHT_SCENE.instantiate()
		if index > 0:
			add_child(flight)
			flight.playback_speed = ball_flight.playback_speed
			flight.shot_started.connect(_on_shot_started)
		_play_shot_event(flight, event, launch_music_time, completion, index > 0)
	while completion.remaining > 0:
		await get_tree().process_frame
	shot_type_label.hide()


# 正式播放等待音频时间轴到达发射点；高速冒烟测试继续按压缩后的画面时间执行。
func _wait_for_shot_launch(target_music_time: float) -> void:
	if ball_flight.playback_speed > 1.0:
		var remaining := maxf(target_music_time - rhythm_clock.get_music_time(), 0.0)
		if remaining > 0.0:
			await get_tree().create_timer(remaining / ball_flight.playback_speed).timeout
		return
	while rhythm_clock.get_music_time() < target_music_time:
		await get_tree().process_frame


# 单段协程在命中后应用该段生命快照；临时实例完成后立即释放，常驻首实例供下次复用。
func _play_shot_event(
		flight: Node2D,
		event: Dictionary,
		launch_music_time: float,
		completion: Dictionary,
		free_after: bool
) -> void:
	var flight_seconds: float = rhythm_clock.beats_to_seconds(float(event.get("attack_delay_beats", 1.0)))
	var hit_music_time: float = launch_music_time + flight_seconds
	var visual_state := {"finished": false}
	_play_shot_visual(
		flight,
		event,
		flight_seconds,
		launch_music_time,
		hit_music_time,
		visual_state
	)
	# 命中任务只等待 BGM 时间轴；动画完成信号不会阻塞音效、扣血或受击反馈。
	await _wait_for_shot_launch(hit_music_time)
	_play_attack_impact_audio()
	flight.notify_impact()
	var damage_committed := controller.commit_deferred_damage(event)
	if damage_committed:
		_apply_effect_feedback(event)
	# 临时足球仍由自己的动画生命周期清理，但这段等待发生在命中效果全部触发之后。
	while not visual_state.finished:
		await get_tree().process_frame
	completion.remaining -= 1
	if free_after:
		flight.queue_free()


# 每一段到达目标拍点都独立触发一次；不读取动画完成状态，也不复用临时足球的播放器。
func _play_attack_impact_audio() -> void:
	_attack_hit_audio.play()
	attack_impact_audio_triggered.emit()


# 足球动画作为纯视觉协程运行；最后一个参数关闭动画结束时的自动命中音。
func _play_shot_visual(
		flight: Node2D,
		event: Dictionary,
		flight_seconds: float,
		launch_music_time: float,
		hit_music_time: float,
		visual_state: Dictionary
) -> void:
	await flight.play_shot(
		event.get("shot_type", 0),
		_get_player_shot_origin(),
		enemy_display.get_portrait_global_center(),
		_visual_rng,
		false,
		flight_seconds,
		rhythm_clock,
		launch_music_time,
		hit_music_time,
		false
	)
	visual_state.finished = true


# 玩家当前仅显示底部状态条，足球从状态条上沿中央发出，避免依赖隐藏头像的位置。
func _get_player_shot_origin() -> Vector2:
	var player_rect := player_display.get_global_rect()
	return Vector2(player_rect.get_center().x, player_rect.position.y - 8.0)


# 使用事件中的结算后快照更新血条，保证多段攻击不会在第一球时直接显示最终血量。
func _apply_effect_feedback(event: Dictionary) -> void:
	var target = event.get("target")
	var display: CharacterDisplay = player_display if target == controller.player else enemy_display
	match event.get("type", ""):
		"damage":
			display.set_health(event.get("health_after", target.health))
			display.set_shield(event.get("shield_after", target.shield))
			if event.get("health_damage", 0) > 0:
				display.show_damage(event.health_damage)
			elif event.get("absorbed", 0) > 0:
				display.show_shield_loss(event.absorbed)
		"heal":
			display.set_health(event.get("health_after", target.health))
			display.show_heal(event.amount)
		"shield":
			display.set_shield(event.get("shield_after", target.shield))
			display.show_shield_gain(event.amount)


# 足球组件已解析 RANDOM 的实际弹道，此处仅同步显示本次真实射门类型。
func _on_shot_started(shot_type: int) -> void:
	var names := ["射门", "直球", "香蕉球", "挑射", "随机射门"]
	var safe_index := clampi(shot_type, 0, names.size() - 1)
	shot_type_label.text = names[safe_index]
	shot_type_label.show()


# 保留最近一条核心日志作为紧凑状态提示，便于解释无效操作与随机分支。
func _on_log_added(message: String) -> void:
	status_label.text = message
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("battle", "message", {"message": message})


# 胜负确定后锁定输入并显示独立结果层，避免重复出牌或结束回合。
func _on_battle_finished(victory: bool) -> void:
	_input_locked = true
	if _is_presenting_resolution:
		_pending_battle_result = victory
		_update_input_state()
		return
	_finalize_battle_result(victory)


# 动画队列结束后再提交并展示胜负，防止足球尚未命中时结果层提前遮住战场。
func _finalize_battle_result(victory: bool) -> void:
	_gm_menu_open = false
	gm_overlay.hide()
	rhythm_clock.stop_music()
	_last_victory = victory
	run_state.record_battle_health(controller.player.health)
	# 失败不提交房间完成，清除进行中上下文；胜利则保留到两步奖励全部领取后再提交。
	if not victory:
		run_state.mark_run_failed()
		run_state.cancel_current_room()
	_update_input_state()
	result_title.text = "战斗胜利" if victory else "战斗失败"
	result_detail.text = "选择卡牌和战利品后返回路线地图。" if victory else "本局失败：返回主菜单后可开始新的一局。"
	result_action_button.text = "领取奖励" if victory else "返回主菜单"
	if victory:
		run_state.pending_reward_is_boss = (
			controller.current_enemy_definition != null
			and controller.current_enemy_definition.tier == 2
		)
		run_state.resume_point = run_state.ResumePoint.REWARD
	# 胜负与跨房间生命确定后立即保存；胜利档保留当前房间，等待奖励完成再提交。
	var save_service := get_node_or_null("/root/SaveService")
	if save_service != null:
		save_service.save_game(run_state)
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("battle", "finished", {
			"victory": victory,
			"player_hp": run_state.player_hp,
			"chapter": run_state.chapter,
		})
	result_overlay.show()


# 胜利进入两步奖励，失败进入独立结算页展示本局摘要。
func _on_restart_pressed() -> void:
	if _last_victory:
		get_tree().change_scene_to_file("res://scenes/reward_screen.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/result_screen.tscn")


# 主动退出战斗视为放弃当前尝试，不得让尚未完成的房间继续占用流程状态。
func _on_back_pressed() -> void:
	run_state.cancel_current_room()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
