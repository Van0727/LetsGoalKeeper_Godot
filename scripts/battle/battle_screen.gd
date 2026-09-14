# 可玩战斗界面：连接战斗核心、牌堆和拖拽输入，并按射门动画顺序呈现竖屏战斗反馈。
extends Control

signal attack_impact_audio_triggered
signal miss_audio_triggered
signal active_skill_ball_launched(hit_target: bool, end_position: Vector2)
signal active_skill_effect_committed(elapsed_music_seconds: float)
signal screen_shake_started(duration: float, amplitude: float)

const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const DECK_STATE := preload("res://scripts/cards/deck_state.gd")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const CARD_VIEW_SCENE := preload("res://scenes/card_view.tscn")
const BALL_FLIGHT_SCENE := preload("res://scenes/ball_flight.tscn")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const HIT_AUDIO_STREAM := preload("res://sound/sounds/hit.mp3")
const MISS_AUDIO_STREAM := preload("res://sound/sounds/miss.mp3")
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
const ACTIVE_SKILL_FLIGHT_BEATS := 1.0
const ACTIVE_SKILL_BALL_SCALE := 3.2
const PERFECT_SHAKE_SECONDS := 0.5
const PARTIAL_SHAKE_SECONDS := 0.2
const PERFECT_SHAKE_AMPLITUDE := 18.0
const PARTIAL_SHAKE_AMPLITUDE := 6.0
const VICTORY_RESULT_DELAY_SECONDS := 1.0

@onready var controller: BattleController = %BattleController
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var background: TextureRect = $Background
@onready var player_display: CharacterDisplay = %PlayerDisplay
@onready var enemy_display: CharacterDisplay = %EnemyDisplay
# 使用基础控件类型避免新增脚本的全局类缓存尚未刷新时阻塞战斗场景解析。
@onready var drag_threshold_guide: Control = %DragThresholdGuide
# 使用基础节点类型避免首次导入时全局类缓存尚未登记 BallFlight 而阻塞战斗场景解析。
@onready var ball_flight: Node2D = %BallFlight
# 节拍时钟和反馈控件使用基础类型，避免首次导入新增全局类时出现脚本缓存顺序问题。
@onready var rhythm_clock: Node = %RhythmClock
@onready var rhythm_feedback: Control = %RhythmFeedback
# 中央波形只响应拍点信号，避免拍内进度形成持续呼吸动画。
@onready var rhythm_waveform: Control = %RhythmWaveform
@onready var shot_type_label: Label = %ShotTypeLabel
@onready var turn_label: Label = %TurnLabel
@onready var intent_label: Label = %IntentLabel
@onready var energy_label: Label = %EnergyLabel
@onready var status_label: Label = %StatusLabel
@onready var card_warning_overlay: PanelContainer = %CardWarningOverlay
@onready var card_warning_label: Label = %CardWarningLabel
@onready var hand_layer: Control = %HandLayer
@onready var pile_label: Label = %PileLabel
@onready var skill_button: Button = %SkillButton
@onready var qte_popup: Control = %QTEPopup
@onready var end_turn_button: Button = %EndTurnButton
@onready var gm_menu_button: Button = %GMMenuButton
@onready var gm_overlay: TextureRect = %GMOverlay
@onready var gm_skip_button: Button = %GMSkipButton
@onready var gm_items_button: Button = %GMItemsButton
@onready var gm_items_page: VBoxContainer = %GMItemsPage
@onready var gm_items_list: VBoxContainer = %GMItemsList
@onready var gm_hint: Label = $GMOverlay/Center/Panel/Content/Hint
@onready var result_overlay: TextureRect = %ResultOverlay
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
# 怪物死亡后保持战斗锁定一秒再展示胜利层；标记同时阻止重复信号启动多个结算协程。
var _victory_result_delay_pending := false
var _battle_generation := 0
# 当前出牌对应的音频拍点；所有分段发射和命中都从同一锚点计算，避免逐帧计时累积漂移。
var _resolution_beat_anchor_time := 0.0
var _visual_rng := RandomNumberGenerator.new()
# 实战命中音统一由常驻播放器输出；多声部允许攻击间隔短于音效长度时每段仍清晰触发。
var _attack_hit_audio: AudioStreamPlayer
# Miss 提示使用独立播放器，避免与足球命中音共用播放头而相互截断。
var _miss_audio: AudioStreamPlayer
var _skills_by_type := {
	0: SUPER_ATTACK,
	1: SUPER_DEFENSE,
	2: SUPER_ABILITY,
}
var _pending_active_skill: Resource
var _card_warning_tween: Tween


# 初始化信号和一场固定种子的可玩战斗，便于复现输入与结算问题。
func _ready() -> void:
	_attack_hit_audio = AudioStreamPlayer.new()
	_attack_hit_audio.name = "AttackHitAudio"
	_attack_hit_audio.stream = HIT_AUDIO_STREAM
	_attack_hit_audio.bus = &"SFX"
	_attack_hit_audio.max_polyphony = 8
	add_child(_attack_hit_audio)
	_miss_audio = AudioStreamPlayer.new()
	_miss_audio.name = "MissAudio"
	_miss_audio.stream = MISS_AUDIO_STREAM
	_miss_audio.bus = &"SFX"
	_miss_audio.max_polyphony = 2
	add_child(_miss_audio)
	run_state = get_node_or_null("/root/RunState")
	# 独立场景测试没有 Autoload 时创建局部状态，正式游戏始终使用全局实例。
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
	_apply_chapter_theme()
	var settings_service := get_node_or_null("/root/SettingsService")
	if settings_service != null:
		settings_service.settings_changed.connect(_apply_metronome_style)
	_apply_metronome_style()
	controller.log_added.connect(_on_log_added)
	controller.state_changed.connect(_on_state_changed)
	controller.effect_resolved.connect(_on_effect_resolved)
	controller.discipline_card_issued.connect(_on_discipline_card_issued)
	controller.battle_finished.connect(_on_battle_finished)
	ball_flight.shot_started.connect(_on_shot_started)
	rhythm_clock.beat_reached.connect(_on_rhythm_beat_reached)
	qte_popup.qte_finished.connect(_on_qte_finished)
	# 参考布局把敌人作为上方视觉焦点，玩家状态则压缩到底部生命栏。
	enemy_display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.ENEMY)
	player_display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.PLAYER_BAR)
	# 地图入口通常已完成过场；直接打开战斗场景时由服务补做，保证战斗第一拍不与切曲音效重叠。
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		await bgm_service.consume_battle_transition()
	start_new_battle()


# 节拍圆环每帧读取音频时钟，仅作为视觉提示；松手判定不会依赖这段 UI 更新。
func _process(_delta: float) -> void:
	if rhythm_clock != null and rhythm_feedback != null:
		rhythm_feedback.set_beat_progress(rhythm_clock.get_beat_progress())


# 圆圈和波形复用中央区域且严格互斥；缺少设置服务的独立场景测试默认展示波形。
func _apply_metronome_style() -> void:
	var settings_service := get_node_or_null("/root/SettingsService")
	var use_circle := false
	if settings_service != null:
		use_circle = int(settings_service.metronome_style) == int(settings_service.MetronomeStyle.CIRCLE)
	rhythm_feedback.set_circle_enabled(use_circle)
	rhythm_waveform.visible = not use_circle


# 战斗背景直接使用完整图片；保持白色调制可避免运行时染色破坏原始美术。
func _apply_chapter_theme() -> void:
	background.self_modulate = Color.WHITE


# 使用本局牌库和房间敌人重置战斗：路线地图进入的房间按房型从章节池选敌。
func start_new_battle(enemy_definition: Resource = null) -> void:
	_battle_generation += 1
	result_overlay.hide()
	_victory_result_delay_pending = false
	gm_overlay.hide()
	_gm_menu_open = false
	_show_gm_tools_page()
	ball_flight.hide()
	shot_type_label.hide()
	_pending_effect_events.clear()
	_pending_battle_result = null
	_is_presenting_resolution = false
	card_warning_overlay.hide()
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		rhythm_clock.start_music_with_player(bgm_service.start_battle_bgm(rhythm_clock.music))
	else:
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
	# 表现随机数仍独立于核心球路随机流；实际球型与方向由控制器先锁定并写入事件。
	_visual_rng.seed = current_seed * 31 + 7
	deck_state.setup(starting_deck, current_seed)
	controller.setup(
		current_seed,
		selected_enemy,
		run_state.damage_modifiers,
		REWARD_SERVICE.new().get_items_by_ids(run_state.owned_item_ids)
	)
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
		var played := try_play_hand_card(card_view.hand_index, rhythm_result)
		_play_miss_audio_if_needed(rhythm_result, played)


# 只有卡牌成功提交且等级确认为 Miss 才播放，避免无效拖拽或费用失败产生错误反馈。
func _play_miss_audio_if_needed(rhythm_result: Dictionary, played: bool) -> bool:
	if not played or int(rhythm_result.get("grade", -1)) != rhythm_clock.JudgementGrade.MISS:
		return false
	_miss_audio.play()
	miss_audio_triggered.emit()
	return true


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
	if rhythm_waveform != null:
		rhythm_waveform.pulse_beat()


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


# 主动技先打开战斗内嵌QTE弹窗；QTE完成前只锁输入，不提前消耗连击点或修改战斗数值。
func _on_skill_pressed() -> void:
	if _input_locked:
		return
	var skill: Resource = _get_current_skill()
	if skill == null:
		return
	_input_locked = true
	_update_input_state()
	_pending_active_skill = skill
	var qte_seed: int = run_state.seed + controller.turn_number * 1009 + controller.combo_state.count
	var waveform_center_y: float = rhythm_waveform.get_global_rect().get_center().y
	if not qte_popup.start_qte(rhythm_clock, qte_seed, waveform_center_y):
		_pending_active_skill = null
		_input_locked = false
		_update_input_state()
		return
	pause_overlay.set_external_modal_open(true)
	status_label.text = "%s：完成4次QTE" % skill.display_name


# QTE结束同帧关闭遮罩并发射超级足球；效果只允许在一拍后的命中点提交。
func _on_qte_finished(result: Dictionary) -> void:
	pause_overlay.set_external_modal_open(false)
	var skill := _pending_active_skill
	_pending_active_skill = null
	if skill == null:
		_input_locked = false
		_update_input_state()
		return
	_play_active_skill_qte_result(skill, result)


# 四次及以上Miss时随机踢飞并只消费连击；其余结果命中后按Miss数选择震屏强度。
func _play_active_skill_qte_result(skill: Resource, result: Dictionary) -> void:
	var miss_count := int(result.get("miss", 0))
	var hit_target := miss_count < 4
	var launch_music_time: float = rhythm_clock.get_music_time()
	var flight_seconds: float = rhythm_clock.beats_to_seconds(ACTIVE_SKILL_FLIGHT_BEATS)
	var hit_music_time := launch_music_time + flight_seconds
	var end_position := enemy_display.get_portrait_global_center()
	if not hit_target:
		end_position = _get_missed_active_skill_end_position()
	var visual_state := {"finished": false}
	_play_active_skill_ball_visual(
		end_position,
		flight_seconds,
		launch_music_time,
		hit_music_time,
		visual_state
	)
	active_skill_ball_launched.emit(hit_target, end_position)
	await _wait_for_shot_launch(hit_music_time)
	if hit_target:
		_play_attack_impact_audio()
		ball_flight.notify_impact()
		# 控制器在真实命中拍点才修改生命、护盾或强化，QTE飞行期间核心状态保持不变。
		if not controller.play_active_skill(skill):
			await _wait_for_active_skill_visual(visual_state)
			_input_locked = false
			_update_input_state()
			return
		active_skill_effect_committed.emit(rhythm_clock.get_music_time() - launch_music_time)
		var shake_config := _get_active_skill_shake_config(miss_count)
		await _shake_battle(shake_config.x, shake_config.y)
	else:
		controller.consume_failed_active_skill(skill)
		rhythm_feedback.show_judgement({
			"grade": rhythm_clock.JudgementGrade.MISS,
			"grade_name": "Miss",
			"error_ms": 0.0,
		})
		status_label.text = "%s QTE失败 · Miss %d" % [skill.display_name, miss_count]
	await _wait_for_active_skill_visual(visual_state)
	if hit_target:
		status_label.text = "%s已结算 · P%d G%d M%d" % [
			skill.display_name,
			int(result.get("perfect", 0)),
			int(result.get("good", 0)),
			miss_count,
		]
	call_deferred("_finish_resolution")


# 失败球终点必须完全落在左右屏幕外；方向由独立表现随机数决定，不影响战斗数值随机序列。
func _get_missed_active_skill_end_position() -> Vector2:
	var side := -1.0 if _visual_rng.randi_range(0, 1) == 0 else 1.0
	return Vector2(size.x * 0.5 + side * (size.x + 180.0), size.y * 0.18)


# 零Miss使用夸张震屏；一至三次Miss使用短促小震屏，失败分支不会调用本函数。
func _get_active_skill_shake_config(miss_count: int) -> Vector2:
	if miss_count == 0:
		return Vector2(PERFECT_SHAKE_SECONDS, PERFECT_SHAKE_AMPLITUDE)
	return Vector2(PARTIAL_SHAKE_SECONDS, PARTIAL_SHAKE_AMPLITUDE)


# 超级足球使用普通直球纹理与旋转，但放大到3.2倍并严格绑定一拍音乐时间轴。
func _play_active_skill_ball_visual(
		end_position: Vector2,
		flight_seconds: float,
		launch_music_time: float,
		hit_music_time: float,
		visual_state: Dictionary
) -> void:
	await ball_flight.play_shot(
		CARD_DEFINITION.ShotType.STRAIGHT,
		_get_player_shot_origin(),
		end_position,
		_visual_rng,
		true,
		flight_seconds,
		rhythm_clock,
		launch_music_time,
		hit_music_time,
		false,
		ACTIVE_SKILL_BALL_SCALE
	)
	visual_state.finished = true


# 视觉协程通常与音乐命中同时结束；独立等待可覆盖掉帧，避免下一次操作复用仍显示的足球。
func _wait_for_active_skill_visual(visual_state: Dictionary) -> void:
	while not bool(visual_state.finished):
		await get_tree().process_frame


# 命中震屏使用确定性随机源逐帧偏移整个战斗画面，结束或异常退出前始终恢复原位置。
func _shake_battle(duration: float, amplitude: float) -> void:
	var original_position := position
	var elapsed := 0.0
	screen_shake_started.emit(duration, amplitude)
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		position = original_position + Vector2(
			_visual_rng.randf_range(-amplitude, amplitude),
			_visual_rng.randf_range(-amplitude, amplitude)
		)
	position = original_position


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
	_show_gm_tools_page()
	gm_overlay.show()
	_update_input_state()


# GM 战利品页每次打开都从 RunState 真实持有列表重建，避免上次关闭后的旧勾选残留。
func _on_gm_items_pressed() -> void:
	if not _gm_menu_open or _input_locked:
		return
	gm_hint.hide()
	gm_skip_button.hide()
	gm_items_button.hide()
	gm_items_page.show()
	_rebuild_gm_items_list()


func _on_gm_items_back_pressed() -> void:
	_show_gm_tools_page()


# 返回工具主页只改变显示，不操作战斗数值或战利品持有状态。
func _show_gm_tools_page() -> void:
	gm_items_page.hide()
	gm_hint.show()
	gm_skip_button.show()
	gm_items_button.show()


# 按完整奖励目录生成可滚动的复选框和配置说明；禁用占位物可查看但不可勾选。
func _rebuild_gm_items_list() -> void:
	for child in gm_items_list.get_children():
		gm_items_list.remove_child(child)
		child.queue_free()
	for item in _reward_service.get_all_items():
		var entry := VBoxContainer.new()
		entry.custom_minimum_size = Vector2(270.0, 0.0)
		gm_items_list.add_child(entry)
		var checkbox := CheckBox.new()
		checkbox.text = item.display_name
		checkbox.disabled = not item.enabled
		checkbox.set_pressed_no_signal(item.item_id in run_state.owned_item_ids)
		checkbox.toggled.connect(_on_gm_item_toggled.bind(item, checkbox))
		entry.add_child(checkbox)
		var effect_label := Label.new()
		effect_label.text = item.description if item.enabled else "%s（未启用，不可勾选）" % item.description
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_label.custom_minimum_size = Vector2(270.0, 0.0)
		effect_label.add_theme_font_size_override("font_size", 12)
		entry.add_child(effect_label)


# 勾选只调用本局唯一持有接口；成功后立即同步当前战斗，不重新创建控制器或重置生命。
func _on_gm_item_toggled(checked: bool, item: Resource, checkbox: CheckBox) -> void:
	if not _gm_menu_open or not gm_items_page.visible or _input_locked or not item.enabled:
		checkbox.set_pressed_no_signal(item.item_id in run_state.owned_item_ids)
		return
	var changed: bool = run_state.add_item(item) if checked else run_state.remove_item(item)
	if not changed:
		checkbox.set_pressed_no_signal(item.item_id in run_state.owned_item_ids)
		return
	controller.debug_sync_items(
		_reward_service.get_items_by_ids(run_state.owned_item_ids),
		run_state.damage_modifiers
	)
	_refresh_all()


# 关闭 GM 面板并恢复此前的战斗输入状态，不改变任何核心数值。
func _on_gm_close_pressed() -> void:
	_gm_menu_open = false
	gm_overlay.hide()
	_show_gm_tools_page()
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
	if controller.red_card_pending:
		_force_end_turn_after_red_card()
		return
	status_label.text = "卡牌已结算"
	_finish_resolution()


# 红牌等待当前牌的所有飞行与反馈完成后再弃牌、推进敌方行动，避免动画引用过期状态。
func _force_end_turn_after_red_card() -> void:
	var discarded := deck_state.discard_hand()
	if not controller.force_end_turn_for_red_card():
		_finish_resolution()
		return
	if controller.phase == BATTLE_CONTROLLER.Phase.PLAYER_TURN:
		deck_state.draw_cards(STARTING_HAND_SIZE)
	status_label.text = "红牌：弃掉 %d 张手牌并强制结束回合" % discarded
	_fade_card_warning(0.65)
	call_deferred("_finish_resolution")


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
		false,
		2.0,
		int(event.get("shot_direction", 0))
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
		"bgm_pitch":
			# 音频节点由跨场景服务唯一持有；卡牌事件只描述升降或复原意图。
			var bgm_service := get_node_or_null("/root/BgmService")
			if bgm_service == null:
				return
			if event.get("reset", false):
				bgm_service.reset_battle_pitch()
			else:
				bgm_service.shift_battle_pitch(int(event.get("semitone_delta", 0)))


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


# 黄牌短暂警告，红牌保持到强制回合推进完成；重复动画会先终止旧 Tween，避免透明度竞争。
func _on_discipline_card_issued(card_color: String, played_count: int) -> void:
	if _card_warning_tween != null:
		_card_warning_tween.kill()
	card_warning_overlay.show()
	card_warning_overlay.modulate = Color.WHITE
	if card_color == "red":
		card_warning_overlay.self_modulate = Color(0.72, 0.08, 0.06, 0.96)
		card_warning_label.text = "红牌！\n本回合第 %d 张牌\n结算后强制结束回合" % played_count
	else:
		card_warning_overlay.self_modulate = Color(0.95, 0.72, 0.08, 0.96)
		card_warning_label.text = "黄牌警告！\n本回合已打出 %d 张牌" % played_count
	# 红牌持续显示至当前卡牌完整结算，黄牌则只做短暂警告且不阻塞操作。
	if card_color != "red":
		_fade_card_warning(0.65)


func _fade_card_warning(delay_seconds: float) -> void:
	if _card_warning_tween != null:
		_card_warning_tween.kill()
	_card_warning_tween = create_tween()
	_card_warning_tween.tween_interval(delay_seconds)
	_card_warning_tween.tween_property(card_warning_overlay, "modulate:a", 0.0, 0.25)
	_card_warning_tween.tween_callback(card_warning_overlay.hide)


# 胜负确定后锁定输入并显示独立结果层，避免重复出牌或结束回合。
func _on_battle_finished(victory: bool) -> void:
	_input_locked = true
	if _is_presenting_resolution:
		_pending_battle_result = victory
		_update_input_state()
		return
	_finalize_battle_result(victory)


# 怪物死亡后额外等待一秒再提交胜利界面；玩家失败仍立即结算，且等待标记阻止重复保存。
func _finalize_battle_result(victory: bool) -> void:
	if victory:
		if _victory_result_delay_pending:
			return
		_victory_result_delay_pending = true
		var delayed_generation := _battle_generation
		_update_input_state()
		await get_tree().create_timer(VICTORY_RESULT_DELAY_SECONDS).timeout
		# 调试入口或测试若在等待期启动了新战斗，旧协程不得覆盖新一场的状态和存档。
		if delayed_generation != _battle_generation:
			return
	_gm_menu_open = false
	gm_overlay.hide()
	# 胜利后的奖励页继续沿用战斗曲；只有后续触发实际 BGM 切换时，常驻服务才会停止它。
	if not victory:
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
	_victory_result_delay_pending = false


# 胜利进入两步奖励，失败进入独立结算页展示本局摘要。
func _on_restart_pressed() -> void:
	if _last_victory:
		get_tree().change_scene_to_file("res://scenes/reward_screen.tscn")
		return
	# 失败离开战斗时才触发切曲；常驻服务会停止战斗曲并启动主曲后再进入结算页。
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		await bgm_service.transition_to_main_bgm()
	get_tree().change_scene_to_file("res://scenes/result_screen.tscn")


# 主动退出战斗视为放弃当前尝试，不得让尚未完成的房间继续占用流程状态。
func _on_back_pressed() -> void:
	run_state.cancel_current_room()
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		await bgm_service.transition_to_main_bgm()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
