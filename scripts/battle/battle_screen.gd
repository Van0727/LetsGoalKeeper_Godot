# 可玩战斗界面：连接战斗核心、牌堆和拖拽输入，并按射门动画顺序呈现竖屏战斗反馈。
extends Control

signal attack_impact_audio_triggered
signal miss_audio_triggered
signal judgement_audio_triggered(grade_name: String, effects_finished_time: float, target_beat_time: float, played_time: float)
signal game_win_audio_triggered(death_time: float, target_beat_time: float, played_time: float)
signal active_skill_ball_launched(hit_target: bool, end_position: Vector2)
signal active_skill_effect_committed(elapsed_music_seconds: float)
signal screen_shake_started(duration: float, amplitude: float)

const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const DECK_STATE := preload("res://scripts/cards/deck_state.gd")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const ITEM_DEFINITION := preload("res://scripts/items/item_definition.gd")
const NORMAL_ITEM_PLACEHOLDER := preload("res://assets/ui/items/item_placeholder_normal.svg")
const BOSS_ITEM_PLACEHOLDER := preload("res://assets/ui/items/item_placeholder_boss.svg")
const CARD_VIEW_SCENE := preload("res://scenes/card_view.tscn")
const BALL_FLIGHT_SCENE := preload("res://scenes/ball_flight.tscn")
const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")
const BARE_CHESTED := preload("res://data/cards/card_bare_chested.tres")
# 战斗 UI 与 GM 面板只读数字战利品 ID；英文资源名不参与运行时判断。
const NUDE_LICENSE_ID := 4020
const BLINDFOLD_ID := 4006
const IN_EAR_MONITOR_ID := 4016
const HIT_AUDIO_STREAM := preload("res://sound/sounds/hit.mp3")
const MISS_AUDIO_STREAM := preload("res://sound/sounds/miss.mp3")
const GOOD_AUDIO_STREAM := preload("res://sound/sounds/good.mp3")
const GREAT_AUDIO_STREAM := preload("res://sound/sounds/great.mp3")
const TAKE_DAMAGE_AUDIO_STREAM := preload("res://sound/sounds/takedamage.mp3")
const HIT_SHIELD_AUDIO_STREAM := preload("res://sound/sounds/hitshield.mp3")
const SHIELD_AUDIO_STREAM := preload("res://sound/sounds/shield.mp3")
const TURTLE := preload("res://data/enemies/enemy_turtle.tres")
const BEAR := preload("res://data/enemies/enemy_bear.tres")
const TRAINING_BOSS := preload("res://data/enemies/enemy_training_raccoon_boss.tres")
const ENEMY_CATALOG := preload("res://data/enemies/enemy_catalog.tres")
const ENCOUNTER_PLANNER := preload("res://scripts/enemies/encounter_planner.gd")
const SUPER_ATTACK := preload("res://data/skills/skill_super_attack.tres")
const SUPER_DEFENSE := preload("res://data/skills/skill_super_defense.tres")
const SUPER_ABILITY := preload("res://data/skills/skill_super_ability.tres")

const STARTING_HAND_SIZE := 3
# 参考设计图的三张手牌维持 104 宽横排；缩短卡身以避免底部信息区压迫战斗画面。
const CARD_SIZE := Vector2(104, 176)
const CARD_GAP := 6.0
const REST_ROOM_TYPE := 3
const ACTIVE_SKILL_FLIGHT_BEATS := 1.0
const ACTIVE_SKILL_BALL_SCALE := 3.2
const PERFECT_SHAKE_SECONDS := 0.5
const PARTIAL_SHAKE_SECONDS := 0.2
const PERFECT_SHAKE_AMPLITUDE := 18.0
const PARTIAL_SHAKE_AMPLITUDE := 6.0
const VICTORY_RESULT_DELAY_SECONDS := 1.0
const TEST_ENEMY_MAX_HEALTH := 100
const ITEM_ICON_SELECTED_SCALE := Vector2(1.2, 1.2)
const ITEM_ICON_NORMAL_SCALE := Vector2.ONE
const ITEM_ICON_SCALE_DURATION := 0.12

@onready var controller: BattleController = %BattleController
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var background: TextureRect = $Background
# 六束舞台灯光作为背景子层，随背景缩放且不遮挡角色、卡牌或输入。
@onready var stage_lights: Control = $Background/StageLights
@onready var player_display: CharacterDisplay = %PlayerDisplay
# 底部角色 HUD 只读取控制器已结算的状态，和隐藏的 CharacterDisplay 表现层不共享布局职责。
@onready var player_health_bar: ProgressBar = %PlayerHealthBar
@onready var player_health_label: Label = %PlayerHealthLabel
@onready var player_shield_bar: ProgressBar = %PlayerShieldBar
@onready var player_shield_label: Label = %PlayerShieldLabel
@onready var strength_status_label: Label = %StrengthStatus
@onready var bleed_status_label: Label = %BleedStatus
@onready var block_status_label: Label = %BlockStatus
@onready var owned_item_icons: HFlowContainer = %OwnedItemIcons
@onready var item_detail_popup: PanelContainer = %ItemDetailPopup
@onready var item_detail_icon: TextureRect = %Icon
@onready var item_detail_name: Label = %Name
@onready var item_detail_description: Label = %Description
@onready var enemy_display: CharacterDisplay = %EnemyDisplay
# 怪物信息层仅展示控制器已经结算出的生命和当前意图，不自行推算战斗规则。
@onready var enemy_health_fill_clip: Control = %EnemyHealthFillClip
@onready var enemy_health_text: Label = %EnemyHealthText
@onready var behavior_attack: TextureRect = %BehaviorAttack
@onready var behavior_defense: TextureRect = %BehaviorDefense
@onready var behavior_skill: TextureRect = %BehaviorSkill
@onready var behavior_value: Label = %BehaviorValue
@onready var talking_text: Label = %TalkingText
# 使用基础控件类型避免新增脚本的全局类缓存尚未刷新时阻塞战斗场景解析。
@onready var drag_threshold_guide: Control = %DragThresholdGuide
# 使用基础节点类型避免首次导入时全局类缓存尚未登记 BallFlight 而阻塞战斗场景解析。
@onready var ball_flight: Node2D = %BallFlight
# 节拍时钟和反馈控件使用基础类型，避免首次导入新增全局类时出现脚本缓存顺序问题。
@onready var rhythm_clock: Node = %RhythmClock
@onready var rhythm_feedback: Control = %RhythmFeedback
# 中央波形只响应拍点信号，避免拍内进度形成持续呼吸动画。
@onready var rhythm_waveform: Control = %RhythmWaveform
@onready var rhythm_accent_waveform: Control = %RhythmAccentWaveform
@onready var turn_label: Label = %TurnLabel
@onready var phase_label: Label = %PhaseLabel
@onready var intent_label: Label = %IntentLabel
@onready var monster_rules_label: Label = %MonsterRulesLabel
@onready var energy_label: Label = %EnergyLabel
@onready var status_label: Label = %StatusLabel
@onready var bgm_calibration_toggle: Button = %BgmCalibrationToggle
@onready var bgm_calibration_panel: PanelContainer = %BgmCalibrationPanel
@onready var calibration_value_label: Label = %CalibrationValueLabel
@onready var card_warning_overlay: PanelContainer = %CardWarningOverlay
@onready var card_warning_label: Label = %CardWarningLabel
@onready var hand_layer: Control = %HandLayer
@onready var draw_pile_count: Label = %DrawPileCount
@onready var discard_pile_count: Label = %DiscardPileCount
@onready var skill_button: Button = %SkillButton
@onready var skill_count_label: Label = %SkillCountLabel
@onready var skill_pulse_ring: Node = %SkillPulseRing
@onready var qte_popup: Control = %QTEPopup
@onready var end_turn_button: Button = %EndTurnButton
@onready var gm_menu_button: Button = %GMMenuButton
@onready var gm_overlay: TextureRect = %GMOverlay
@onready var gm_skip_button: Button = %GMSkipButton
@onready var gm_items_button: Button = %GMItemsButton
@onready var gm_items_page: VBoxContainer = %GMItemsPage
@onready var gm_items_list: VBoxContainer = %GMItemsList
@onready var gm_cards_button: Button = %GMCardsButton
@onready var gm_cards_page: VBoxContainer = %GMCardsPage
@onready var gm_cards_list: VBoxContainer = %GMCardsList
@onready var gm_hint: Label = $GMOverlay/Center/Panel/Content/Hint
@onready var result_overlay: TextureRect = %ResultOverlay
@onready var result_panel: PanelContainer = $ResultOverlay/ResultCenter/ResultPanel
@onready var result_kicker: Label = %ResultKicker
@onready var victory_mark: Label = %VictoryMark
@onready var result_title: Label = %ResultTitle
@onready var result_detail: Label = %ResultDetail
@onready var health_stat_label: Label = %HealthStatLabel
@onready var reward_stat_label: Label = %RewardStatLabel
@onready var result_action_button: Button = %RestartButton

var deck_state := DECK_STATE.new()
var _input_locked := false
var _enemy_index := 0
var _enemy_sequence: Array[Resource] = [TURTLE, BEAR, TRAINING_BOSS]
var _last_victory := false
var _reward_service := REWARD_SERVICE.new()
var run_state: Node
# 已显示的持有ID用于避免每次生命刷新都重复创建图标；GM即时增删和下一战切换仍会触发重建。
var _displayed_owned_item_ids: Array[int] = []
# 当前悬停或按住的图标独占详情浮层；每个图标的 Tween 独立缓存，避免快速切换时缩放互相覆盖。
var _selected_item_icon: TextureRect
var _item_icon_scale_tweens: Dictionary = {}
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
# 测试玩法可临时试听偏移；只有按保存后才更新 SettingsService 的逐曲记录。
var _saved_bgm_offset_ms := 0
var _calibration_status := ""
var _visual_rng := RandomNumberGenerator.new()
# 实战命中音统一由常驻播放器输出；多声部允许攻击间隔短于音效长度时每段仍清晰触发。
var _attack_hit_audio: AudioStreamPlayer
# Miss 提示使用独立播放器，避免与足球命中音共用播放头而相互截断。
var _miss_audio: AudioStreamPlayer
# Good 与 Great 在卡牌成功提交时立刻播放，分别持有播放头以与评级文字同步。
var _good_audio: AudioStreamPlayer
var _great_audio: AudioStreamPlayer
# 受伤与命中护甲按结算结果区分；多段攻击允许短间隔叠音，避免后一次覆盖前一次反馈。
var _take_damage_audio: AudioStreamPlayer
var _hit_shield_audio: AudioStreamPlayer
# 玩家和怪物共用获得护盾音；只在护盾数值实际增加时触发。
var _shield_audio: AudioStreamPlayer
# 怪物死亡提示由全局 BGM 服务跨场景播放；这里只保留防重调度标记。
var _game_win_audio_scheduled := false
var _skills_by_type := {
	0: SUPER_ATTACK,
	1: SUPER_DEFENSE,
	2: SUPER_ABILITY,
}
var _pending_active_skill: Resource
var _card_warning_tween: Tween
# 连击按钮保留场景中可编辑的基础缩放；每拍只围绕该基准做短促回弹。
var _skill_button_base_scale := Vector2.ONE
var _skill_button_pulse_tween: Tween


# 初始化信号和一场固定种子的可玩战斗，便于复现输入与结算问题。
func _ready() -> void:
	_skill_button_base_scale = skill_button.scale
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
	_good_audio = AudioStreamPlayer.new()
	_good_audio.name = "GoodAudio"
	_good_audio.stream = GOOD_AUDIO_STREAM
	_good_audio.bus = &"SFX"
	_good_audio.max_polyphony = 2
	add_child(_good_audio)
	_great_audio = AudioStreamPlayer.new()
	_great_audio.name = "GreatAudio"
	_great_audio.stream = GREAT_AUDIO_STREAM
	_great_audio.bus = &"SFX"
	_great_audio.max_polyphony = 2
	add_child(_great_audio)
	_take_damage_audio = AudioStreamPlayer.new()
	_take_damage_audio.name = "TakeDamageAudio"
	_take_damage_audio.stream = TAKE_DAMAGE_AUDIO_STREAM
	_take_damage_audio.bus = &"SFX"
	_take_damage_audio.max_polyphony = 4
	add_child(_take_damage_audio)
	_hit_shield_audio = AudioStreamPlayer.new()
	_hit_shield_audio.name = "HitShieldAudio"
	_hit_shield_audio.stream = HIT_SHIELD_AUDIO_STREAM
	_hit_shield_audio.bus = &"SFX"
	_hit_shield_audio.max_polyphony = 4
	add_child(_hit_shield_audio)
	_shield_audio = AudioStreamPlayer.new()
	_shield_audio.name = "ShieldAudio"
	_shield_audio.stream = SHIELD_AUDIO_STREAM
	_shield_audio.bus = &"SFX"
	_shield_audio.max_polyphony = 4
	add_child(_shield_audio)
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
	rhythm_clock.beat_reached.connect(_on_rhythm_beat_reached)
	qte_popup.qte_finished.connect(_on_qte_finished)
	# 参考布局把敌人作为上方视觉焦点，玩家状态则压缩到底部生命栏。
	enemy_display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.ENEMY)
	player_display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.PLAYER_BAR)
	# 玩家 CharacterDisplay 保留给受击反馈与足球命中坐标，实际底部信息由专用 HUD 承担。
	player_display.hide()
	# 地图入口通常已完成过场；直接打开战斗场景时由服务补做，保证战斗第一拍不与切曲音效重叠。
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		await bgm_service.consume_battle_transition()
	start_new_battle()


# 音符、装饰波形与舞台灯共用连续音频时钟；只更新表现，不影响松手判定或战斗状态。
func _process(_delta: float) -> void:
	if rhythm_clock != null and rhythm_feedback != null:
		var music_time: float = rhythm_clock.get_music_time()
		stage_lights.set_music_timing(music_time, rhythm_clock.get_beat_duration(), rhythm_clock.first_beat_offset)
		rhythm_feedback.set_music_timing(music_time, rhythm_clock.get_beat_duration(), rhythm_clock.first_beat_offset, rhythm_clock.beats_per_bar)
		# 装饰波形与扩散圈共用同一音频时间，保持暂停、循环和模式切换后的相位一致。
		rhythm_accent_waveform.set_music_timing(music_time, rhythm_clock.get_beat_duration(), rhythm_clock.first_beat_offset)


# 圆圈节奏条和波形严格互斥；独立场景默认圆圈，已保存的合法波形偏好继续有效。
func _apply_metronome_style() -> void:
	var settings_service := get_node_or_null("/root/SettingsService")
	var use_circle := true
	if settings_service != null:
		use_circle = int(settings_service.metronome_style) == int(settings_service.MetronomeStyle.CIRCLE)
	rhythm_feedback.set_circle_enabled(use_circle)
	rhythm_waveform.visible = not use_circle
	rhythm_accent_waveform.visible = use_circle


# 战斗背景直接使用完整图片；保持白色调制可避免运行时染色破坏原始美术。
func _apply_chapter_theme() -> void:
	background.self_modulate = Color.WHITE


# 正式配表仍使用内部 Perfect 规则名；战斗中的所有玩家可见说明统一显示 Great。
func _to_player_grade_terms(text: String) -> String:
	return text.replace("Perfect", "Great")


# 使用本局牌库和房间敌人重置战斗：路线地图进入的房间按房型从章节池选敌。
func start_new_battle(enemy_definition: Resource = null) -> void:
	_battle_generation += 1
	_game_win_audio_scheduled = false
	result_overlay.hide()
	_victory_result_delay_pending = false
	gm_overlay.hide()
	_gm_menu_open = false
	_show_gm_tools_page()
	ball_flight.hide()
	_pending_effect_events.clear()
	_pending_battle_result = null
	_is_presenting_resolution = false
	card_warning_overlay.hide()
	_setup_bgm_calibration()
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
	# 测试玩法复制训练敌人定义后覆写生命，绝不修改磁盘资源；每次击杀都会重新创建这只 100 血敌人。
	if run_state.is_test_battle:
		selected_enemy = _create_test_enemy()
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
	# 从 RunState 原始牌组生成本场可玩投影，读档不需要额外保存替换来源。
	deck_state.sync_defense_replacement(NUDE_LICENSE_ID in run_state.owned_item_ids, BARE_CHESTED)
	deck_state.set_hand_limit(1 if BLINDFOLD_ID in run_state.owned_item_ids else STARTING_HAND_SIZE)
	controller.setup(
		current_seed,
		selected_enemy,
		run_state.damage_modifiers,
		REWARD_SERVICE.new().get_items_by_ids(run_state.owned_item_ids),
		run_state.run_max_energy_bonus
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
	# 怪物图片由配表 ID 指定；每场战斗重设以免复用界面时显示上一只怪物。
	enemy_display.set_enemy_image_id(selected_enemy.image_id, selected_enemy.battle_image_scale)
	deck_state.draw_cards(STARTING_HAND_SIZE)
	_input_locked = false
	_rebuild_hand()
	_refresh_all()
	if not selected_enemy.passive_description.is_empty():
		status_label.text = "%s被动：%s" % [selected_enemy.display_name, _to_player_grade_terms(selected_enemy.passive_description)]


# 战斗启动时按当前曲目读取已保存的设备校准；测试玩法仅保留小按钮，面板默认收起。
func _setup_bgm_calibration() -> void:
	bgm_calibration_toggle.visible = run_state.is_test_battle and rhythm_clock.music != null
	bgm_calibration_panel.hide()
	bgm_calibration_toggle.text = "校准"
	_saved_bgm_offset_ms = 0
	_calibration_status = ""
	var settings_service := get_node_or_null("/root/SettingsService")
	if settings_service != null and rhythm_clock.music != null:
		_saved_bgm_offset_ms = settings_service.get_bgm_offset_ms(rhythm_clock.music.resource_path)
	rhythm_clock.set_calibration_offset_ms(float(_saved_bgm_offset_ms))
	_refresh_bgm_calibration_label()


# 展开和收起只改变控件可见性；当前试听值与保存状态在本场战斗中继续保留。
func _on_calibration_toggle_pressed() -> void:
	if not bgm_calibration_toggle.visible:
		return
	bgm_calibration_panel.visible = not bgm_calibration_panel.visible
	bgm_calibration_toggle.text = "收起" if bgm_calibration_panel.visible else "校准"


# 每按一次只移动 1 ms，现场立即试听；上下限与持久化校验一致，防止误触后难以恢复。
func _change_bgm_calibration(delta_ms: int) -> void:
	if not bgm_calibration_panel.visible:
		return
	var settings_service := get_node_or_null("/root/SettingsService")
	var limit := int(settings_service.MAX_BGM_OFFSET_MS) if settings_service != null else 500
	rhythm_clock.set_calibration_offset_ms(float(clampi(
		roundi(rhythm_clock.calibration_offset_ms) + delta_ms, -limit, limit
	)))
	_calibration_status = ""
	_refresh_bgm_calibration_label()


func _on_calibration_minus_pressed() -> void:
	_change_bgm_calibration(-1)


func _on_calibration_plus_pressed() -> void:
	_change_bgm_calibration(1)


# 失败时保留当前试听值供重试，但下次进场仍以最后成功保存的值为准。
func _on_calibration_save_pressed() -> void:
	if not bgm_calibration_panel.visible or rhythm_clock.music == null:
		return
	var settings_service := get_node_or_null("/root/SettingsService")
	if settings_service == null:
		_calibration_status = "保存失败"
	else:
		var offset_ms := roundi(rhythm_clock.calibration_offset_ms)
		if settings_service.save_bgm_offset_ms(rhythm_clock.music.resource_path, offset_ms):
			_saved_bgm_offset_ms = offset_ms
			_calibration_status = "已保存"
		else:
			_calibration_status = "保存失败"
	_refresh_bgm_calibration_label()


func _refresh_bgm_calibration_label() -> void:
	var offset_ms := roundi(rhythm_clock.calibration_offset_ms)
	var marker := " *" if offset_ms != _saved_bgm_offset_ms else ""
	var status := " · %s" % _calibration_status if not _calibration_status.is_empty() else ""
	calibration_value_label.text = "偏移 %+d ms%s%s" % [offset_ms, marker, status]


# 使用训练敌人的完整行动配置保证测试战斗仍覆盖真实敌方回合；duplicate 避免把 100 血写回共享资源。
func _create_test_enemy() -> Resource:
	var test_enemy := TURTLE.duplicate(true)
	test_enemy.id = 6098
	test_enemy.max_health = TEST_ENEMY_MAX_HEALTH
	test_enemy.display_name = "测试怪物"
	return test_enemy


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

	_show_successful_card_judgement(timing_result)
	status_label.text = "正在结算卡牌效果"
	call_deferred("_play_pending_resolution")
	return true


# 有效松手时立即采样音频播放头；评级只在卡牌成功提交后反馈，避免无效操作误触发 GOOD/GREAT。
func _on_card_played(card_view: DraggableCard) -> void:
	if card_view is BattleCardView:
		var rhythm_result: Dictionary = rhythm_clock.judge_now()
		# 耳返改变本次出牌的判定反馈与伤害，不改 BGM 拍位或实际音频时间。
		if controller.item_runtime.has_item(IN_EAR_MONITOR_ID):
			rhythm_result["grade"] = rhythm_clock.JudgementGrade.PERFECT
			rhythm_result["grade_name"] = "Great"
			rhythm_result["effect_multiplier"] = 1.0
			rhythm_result["error_ms"] = 0.0
		var played := try_play_hand_card(card_view.hand_index, rhythm_result)
		_play_miss_audio_if_needed(rhythm_result, played)


# 只有卡牌成功提交且等级确认为 Miss 才播放，避免无效拖拽或费用失败产生错误反馈。
func _play_miss_audio_if_needed(rhythm_result: Dictionary, played: bool) -> bool:
	if not played or int(rhythm_result.get("grade", -1)) != rhythm_clock.JudgementGrade.MISS:
		return false
	_miss_audio.play()
	miss_audio_triggered.emit()
	return true


# 成功打出时同步显示评级并播放 GOOD/GREAT 音效；不再等待飞球命中或下一拍，数值结算仍走原队列。
func _show_successful_card_judgement(timing_result: Dictionary) -> void:
	rhythm_feedback.show_judgement(timing_result)
	var grade := int(timing_result.get("grade", -1))
	if grade not in [rhythm_clock.JudgementGrade.PERFECT, rhythm_clock.JudgementGrade.GOOD]:
		return
	var grade_name := "Great" if grade == rhythm_clock.JudgementGrade.PERFECT else "Good"
	var player := _great_audio if grade == rhythm_clock.JudgementGrade.PERFECT else _good_audio
	# 节拍时钟以基础 Node 声明，显式标注音频时间类型以兼容 GDScript 静态推断。
	var card_played_time: float = rhythm_clock.get_music_time()
	player.play()
	# 保留既有信号参数数量以兼容监听方；三个时间均表示本次成功出牌的即时触发时刻。
	judgement_audio_triggered.emit(grade_name, card_played_time, card_played_time, card_played_time)


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
	# 怪物待机只由真实音乐拍点驱动，暂停或切曲时不会继续运行独立循环。
	enemy_display.play_rhythm_beat(beat_index, rhythm_clock.beats_per_bar)
	if rhythm_waveform != null:
		rhythm_waveform.pulse_beat()
	if not skill_button.disabled:
		skill_pulse_ring.call("pulse_beat")
		_pulse_skill_button()


# 连击可释放时按真实拍点做一次缩放回弹；Tween 被下一拍替换，避免快节奏下叠加成永久放大。
func _pulse_skill_button() -> void:
	if _skill_button_pulse_tween != null and _skill_button_pulse_tween.is_valid():
		_skill_button_pulse_tween.kill()
	skill_button.scale = _skill_button_base_scale
	_skill_button_pulse_tween = create_tween().bind_node(skill_button)
	_skill_button_pulse_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_skill_button_pulse_tween.tween_property(skill_button, "scale", _skill_button_base_scale * 1.11, 0.07)
	_skill_button_pulse_tween.set_ease(Tween.EASE_IN)
	_skill_button_pulse_tween.tween_property(skill_button, "scale", _skill_button_base_scale, 0.18)


# 结束回合先弃掉剩余手牌，再执行敌人行动；存活时进入新回合并重新抽三张。
func _on_end_turn_pressed() -> void:
	if _input_locked or controller.phase != BATTLE_CONTROLLER.Phase.PLAYER_TURN:
		return
	_input_locked = true
	_update_input_state()
	var discarded := deck_state.discard_hand()
	status_label.text = "弃掉 %d 张手牌，敌人行动" % discarded
	# 结束回合按钮即时采样 BGM 拍位，回转鼓组不依赖上一次出牌时的拍位。
	var end_timing: Dictionary = rhythm_clock.judge_now()
	end_timing["is_last_beat"] = int(end_timing.get("beat_in_bar", -1)) == rhythm_clock.beats_per_bar - 1
	_resolve_enemy_turn_with_ball(end_timing, false, discarded)


# 先完成回合末流血等前置结算；直接攻击意图等待足球命中玩家后才真正执行伤害与附带效果。
func _resolve_enemy_turn_with_ball(end_timing: Dictionary, forced_by_red_card: bool, discarded: int) -> void:
	var started := (
		controller.force_end_turn_for_red_card(true)
		if forced_by_red_card
		else controller.end_player_turn(end_timing, true)
	)
	if not started:
		_finish_resolution()
		return
	if controller.phase == BATTLE_CONTROLLER.Phase.PLAYER_END:
		if controller.enemy_intent_has_direct_attack():
			enemy_display.play_enemy_attack()
			await _play_enemy_attack_ball()
		controller.continue_deferred_enemy_turn()
	if controller.phase == BATTLE_CONTROLLER.Phase.PLAYER_TURN:
		deck_state.draw_cards(STARTING_HAND_SIZE)
	if forced_by_red_card:
		status_label.text = "红牌：弃掉 %d 张手牌并强制结束回合" % discarded
		_fade_card_warning(0.65)
	call_deferred("_finish_resolution")


# 敌方统一使用直球表现；球抵达玩家生命栏中心后才返回，调用方随后提交敌人行动。
func _play_enemy_attack_ball() -> void:
	var launch_music_time: float = rhythm_clock.get_music_time()
	var flight_seconds: float = rhythm_clock.beats_to_seconds(1.0)
	var hit_music_time: float = launch_music_time + flight_seconds
	var player_target := player_display.get_global_rect().get_center()
	var visual_state := {"finished": false}
	_play_enemy_attack_ball_visual(
		enemy_display.get_portrait_global_center(),
		player_target,
		flight_seconds,
		launch_music_time,
		hit_music_time,
		visual_state
	)
	await _wait_for_shot_launch(hit_music_time)
	_play_attack_impact_audio()
	ball_flight.notify_impact()
	while not bool(visual_state.finished):
		await get_tree().process_frame


# 敌人飞球只负责表现，关闭组件自动命中音，伤害提交由命中等待结束后的统一入口负责。
func _play_enemy_attack_ball_visual(
		start_position: Vector2,
		end_position: Vector2,
		flight_seconds: float,
		launch_music_time: float,
		hit_music_time: float,
		visual_state: Dictionary
) -> void:
	await ball_flight.play_shot(
		CARD_DEFINITION.ShotType.STRAIGHT,
		start_position,
		end_position,
		_visual_rng,
		false,
		flight_seconds,
		rhythm_clock,
		launch_music_time,
		hit_music_time,
		false
	)
	visual_state.finished = true


# 主动技先打开战斗内嵌QTE弹窗；QTE完成前只锁输入，不提前消耗连击点或修改战斗数值。
func _on_skill_pressed() -> void:
	if _input_locked:
		return
	if controller.item_runtime.has_item(BLINDFOLD_ID):
		if controller.use_blindfold_swap(deck_state):
			_rebuild_hand()
			_refresh_all()
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
		if not controller.play_active_skill(skill, result, true):
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
	# 骰子强制结束必须等主动技球与反馈播完，再弃手牌并抽下一回合手牌。
	if controller.bar_dice_end_turn_pending:
		deck_state.discard_hand()
		if controller.resolve_bar_dice_end_turn() and controller.phase == BATTLE_CONTROLLER.Phase.PLAYER_TURN:
			deck_state.draw_cards(STARTING_HAND_SIZE)
	if hit_target:
		status_label.text = "%s已结算 · Great %d · Good %d · Miss %d" % [
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
		var cached_enemy: Resource = ENEMY_CATALOG.resolve_cached_id(cached_id)
		if cached_enemy != null:
			run_state.map_state.set_enemy_id(room.id, str(cached_enemy.id))
			return cached_enemy
		_record_missing_encounter("enemy", {"enemy_id": cached_id})
		return TURTLE
	var pool_path := "res://data/encounters/chapter_%d.tres" % run_state.chapter
	if not ResourceLoader.exists(pool_path):
		push_error("找不到章节遭遇池：%s，回退到乌龟" % pool_path)
		_record_missing_encounter("encounter_pool", {"chapter": run_state.chapter})
		return TURTLE
	var pool: Resource = load(pool_path)
	# 全图规划同时保证同行不重复、相邻层真实连线不重复，且与地图名称预览使用同一结果。
	var plan: Dictionary = ENCOUNTER_PLANNER.plan(run_state.map_state, pool, ENEMY_CATALOG, run_state.seed)
	var enemy: Resource = plan.get(room.id)
	if enemy == null:
		# 无解时保留原本的单房间确定性降级，避免内容配置错误导致无法进战。
		var rng := RandomNumberGenerator.new()
		rng.seed = run_state.seed + room.layer * 1000 + room.index * 100 + 17
		enemy = pool.pick_enemy(room.type, rng)
	if enemy == null:
		push_error("第%d章%s房间遭遇池为空，回退到乌龟" % [run_state.chapter, room.type])
		_record_missing_encounter("enemy_pool_entry", {
			"chapter": run_state.chapter,
			"room_type": room.type,
		})
		return TURTLE
	# 旧章节资源通过白名单补充数字ID，新表资源直接使用数字目录；英文名不再参与正式查找。
	if enemy.id <= 0:
		enemy = ENEMY_CATALOG.resolve_cached_id(enemy.enemy_id)
	if enemy == null:
		return TURTLE
	run_state.map_state.set_enemy_id(room.id, str(enemy.id))
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


# GM 卡牌页与战利品页使用相同的即时勾选语义；新增卡牌会重建本场牌堆，确保可立刻抽到。
func _on_gm_cards_pressed() -> void:
	if not _gm_menu_open or _input_locked:
		return
	gm_hint.hide()
	gm_skip_button.hide()
	gm_items_button.hide()
	gm_cards_button.hide()
	gm_cards_page.show()
	_rebuild_gm_cards_list()


func _on_gm_items_back_pressed() -> void:
	_show_gm_tools_page()


# 返回工具主页只改变显示，不操作战斗数值或战利品持有状态。
func _show_gm_tools_page() -> void:
	gm_items_page.hide()
	gm_cards_page.hide()
	gm_hint.show()
	gm_skip_button.show()
	gm_items_button.show()
	gm_cards_button.show()


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
		checkbox.set_pressed_no_signal(item.id in run_state.owned_item_ids)
		checkbox.toggled.connect(_on_gm_item_toggled.bind(item, checkbox))
		entry.add_child(checkbox)
		var effect_label := Label.new()
		var item_description := _to_player_grade_terms(item.description)
		effect_label.text = item_description if item.enabled else "%s（未实装，不可勾选）" % item_description
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_label.custom_minimum_size = Vector2(270.0, 0.0)
		effect_label.add_theme_font_size_override("font_size", 12)
		entry.add_child(effect_label)


# 勾选只调用本局唯一持有接口；成功后立即同步当前战斗，不重新创建控制器或重置生命。
func _on_gm_item_toggled(checked: bool, item: Resource, checkbox: CheckBox) -> void:
	if not _gm_menu_open or not gm_items_page.visible or _input_locked or not item.enabled:
		checkbox.set_pressed_no_signal(item.id in run_state.owned_item_ids)
		return
	var had_blindfold: bool = BLINDFOLD_ID in run_state.owned_item_ids
	var changed: bool = run_state.add_item(item) if checked else run_state.remove_item(item)
	if not changed:
		checkbox.set_pressed_no_signal(item.id in run_state.owned_item_ids)
		return
	controller.debug_sync_items(
		_reward_service.get_items_by_ids(run_state.owned_item_ids),
		run_state.damage_modifiers
	)
	deck_state.sync_defense_replacement(NUDE_LICENSE_ID in run_state.owned_item_ids, BARE_CHESTED)
	deck_state.set_hand_limit(1 if BLINDFOLD_ID in run_state.owned_item_ids else STARTING_HAND_SIZE)
	# 只有解除蒙眼布上限才补回常规手牌；切换其他GM物品不能绕过狼牙鼓槌停抽。
	if had_blindfold and deck_state.hand_limit == STARTING_HAND_SIZE:
		deck_state.draw_cards(STARTING_HAND_SIZE)
	_rebuild_hand()
	_refresh_all()


# GM 卡牌选择按稳定 ID 增删一张；重复卡牌是正式奖励允许的牌库形态，因此取消时只移除一张。
func _rebuild_gm_cards_list() -> void:
	for child in gm_cards_list.get_children():
		gm_cards_list.remove_child(child)
		child.queue_free()
	for card in _reward_service.get_all_cards():
		var entry := VBoxContainer.new()
		entry.custom_minimum_size = Vector2(270.0, 0.0)
		gm_cards_list.add_child(entry)
		var checkbox := CheckBox.new()
		checkbox.text = card.display_name
		checkbox.set_pressed_no_signal(card.card_id in run_state.deck_card_ids)
		checkbox.disabled = not card.enabled
		checkbox.toggled.connect(_on_gm_card_toggled.bind(card, checkbox))
		entry.add_child(checkbox)
		var description := Label.new()
		var card_description := _to_player_grade_terms(card.description)
		description.text = card_description if card.enabled else "%s（未实装，不可勾选）" % card_description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size = Vector2(270.0, 0.0)
		description.add_theme_font_size_override("font_size", 12)
		entry.add_child(description)


func _on_gm_card_toggled(checked: bool, card: Resource, checkbox: CheckBox) -> void:
	if not _gm_menu_open or not gm_cards_page.visible or _input_locked or not card.enabled:
		checkbox.set_pressed_no_signal(card.card_id in run_state.deck_card_ids)
		return
	var changed: bool = run_state.add_card(card.card_id) if checked else _remove_gm_card(card.card_id)
	if not changed:
		checkbox.set_pressed_no_signal(card.card_id in run_state.deck_card_ids)
		return
	# 牌库重建只影响未打出的抽弃牌，不重置角色、敌人、回合或已持有战利品。
	_rebuild_deck_after_gm_card_change()


func _remove_gm_card(card_id: String) -> bool:
	var index: int = run_state.deck_card_ids.find(card_id)
	if index < 0:
		return false
	run_state.deck_card_ids.remove_at(index)
	run_state.run_changed.emit()
	return true


func _rebuild_deck_after_gm_card_change() -> void:
	var cards: Array[Resource] = []
	for card_id in run_state.deck_card_ids:
		var definition := _reward_service.get_card_by_id(card_id)
		if definition != null:
			cards.append(definition)
	deck_state.setup(cards, controller.battle_seed)
	deck_state.sync_defense_replacement(NUDE_LICENSE_ID in run_state.owned_item_ids, BARE_CHESTED)
	deck_state.set_hand_limit(1 if BLINDFOLD_ID in run_state.owned_item_ids else STARTING_HAND_SIZE)
	deck_state.draw_cards(STARTING_HAND_SIZE)
	_rebuild_hand()
	_refresh_all()


# 关闭 GM 面板并恢复此前的战斗输入状态，不改变任何核心数值。
func _on_gm_close_pressed() -> void:
	_gm_menu_open = false
	gm_overlay.hide()
	_show_gm_tools_page()
	_update_input_state()
	# GM 取消一条中华时可能已超过默认红牌阈值，关闭菜单后立即推进该回合。
	if controller.red_card_pending and not _is_presenting_resolution:
		_force_end_turn_after_red_card()


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


# 同步双方生命、护盾、状态、能量、回合、意图、牌堆计数与底部已获战利品图标。
func _refresh_all() -> void:
	player_display.set_health(controller.player.health)
	player_display.set_shield(controller.player.shield)
	_refresh_player_hud()
	enemy_display.set_health(controller.enemy.health)
	enemy_display.set_shield(controller.enemy.shield)
	_refresh_monster_info()
	# 当前玩法没有固定总回合数；独立底板只显示真实回合，行动阶段保留在顶部文字区。
	turn_label.text = str(controller.turn_number)
	phase_label.text = controller.get_phase_text()
	var full_intent: String = controller.get_enemy_intent_text()
	# 顶栏只显示类别与名称，完整数值、打断进度和临时状态在头像左侧换行显示，避免撑出360视口。
	var table_action: bool = controller.current_enemy_action != null and not controller.current_enemy_action.effects.is_empty()
	intent_label.text = full_intent.get_slice("：", 0) if table_action else "意图：%s" % full_intent
	intent_label.tooltip_text = full_intent
	monster_rules_label.text = full_intent + "\n\n" + controller.get_enemy_rules_text()
	monster_rules_label.visible = table_action or not controller.get_enemy_rules_text().is_empty()
	# 费用面板由独立背景、闪电与动态数字组成；临时费用允许超过上限，保留实际数值。
	energy_label.text = "%d/%d" % [controller.player.energy, controller.player.max_energy]
	# 抽牌与弃牌分别显示，玩家无需在一段紧凑文字中辨认两个会频繁变化的数字。
	draw_pile_count.text = str(deck_state.draw_pile.size())
	discard_pile_count.text = str(deck_state.discard_pile.size())
	_refresh_owned_item_icons()
	_update_input_state()


# 底部 HUD 的护盾容量至少显示 20，超过时随实际值扩展；增益与减益直接读取本场角色状态。
func _refresh_player_hud() -> void:
	var player := controller.player
	var max_health := maxi(player.max_health, 1)
	player_health_bar.max_value = max_health
	player_health_bar.value = clampi(player.health, 0, max_health)
	player_health_label.text = "%d/%d" % [player.health, max_health]
	var shield_capacity := maxi(20, player.shield)
	player_shield_bar.max_value = shield_capacity
	player_shield_bar.value = clampi(player.shield, 0, shield_capacity)
	player_shield_label.text = "%d/%d" % [player.shield, shield_capacity]
	strength_status_label.visible = player.strength_status != CombatantState.StrengthStatus.NONE
	if strength_status_label.visible:
		strength_status_label.text = ("↑" if player.strength_status == CombatantState.StrengthStatus.STRENGTH else "↓") + str(player.strength_turns)
	bleed_status_label.visible = player.bleed_turns > 0
	if bleed_status_label.visible:
		bleed_status_label.text = "✦%d/%d" % [player.bleed_amount, player.bleed_turns]
	block_status_label.visible = player.single_block > 0
	if block_status_label.visible:
		block_status_label.text = "◆%d" % player.single_block


# 按真实生命比例裁切红色切图；无有效行为时使用控制器的默认攻击意图。
func _refresh_monster_info() -> void:
	var max_health: int = maxi(controller.enemy.max_health, 1)
	var health: int = clampi(controller.enemy.health, 0, max_health)
	_set_monster_health_display(health)
	var action: Resource = controller.current_enemy_action
	var category := 0
	if action != null:
		if not action.effects.is_empty():
			category = clampi(action.category, 0, 2)
		elif action.action_type == 1:
			category = 1
		elif action.action_type != 0 and action.action_type != 4:
			category = 2
	# 意图栏只保留当前类别图标，容器自动回收隐藏图标的宽度。
	behavior_attack.visible = category == 0
	behavior_defense.visible = category == 1
	behavior_skill.visible = category == 2
	var amount := controller.get_enemy_intent_damage() if category == 0 else (int(action.amount) if action != null else 0)
	behavior_value.text = str(amount) if amount > 0 else ""
	var full_intent: String = controller.get_enemy_intent_text()
	# 气泡只放行动短名；过长名称截断，完整规则仍可通过提示查看。
	var action_name: String = str(action.display_name) if action != null else "攻击"
	talking_text.text = action_name.substr(0, 7) + "…" if action_name.length() > 8 else action_name
	talking_text.tooltip_text = full_intent


# 底部只显示战利品图片、不显示名称；正式图片缺失时按品级回退，容器按可用宽度自动换行。
func _refresh_owned_item_icons() -> void:
	var current_item_ids: Array[int] = []
	if run_state != null:
		for item_id in run_state.owned_item_ids:
			current_item_ids.append(int(item_id))
	if current_item_ids == _displayed_owned_item_ids:
		return
	_hide_owned_item_detail()
	for child in owned_item_icons.get_children():
		owned_item_icons.remove_child(child)
		child.queue_free()
	_item_icon_scale_tweens.clear()
	_displayed_owned_item_ids = current_item_ids
	if current_item_ids.is_empty():
		owned_item_icons.hide()
		return
	for item in _reward_service.get_items_by_ids(current_item_ids):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(16.0, 16.0)
		icon.pivot_offset = icon.custom_minimum_size * 0.5
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = _get_item_icon(item)
		# 正方形素材在固定槽位内保持原比例，避免奖励页、底栏和详情弹窗出现拉伸。
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 图标必须接收按住事件；它位于底部空白区，不会遮挡手牌拖拽输入。
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.gui_input.connect(_on_owned_item_icon_gui_input.bind(icon, item))
		icon.mouse_entered.connect(_on_owned_item_icon_mouse_entered.bind(icon, item))
		icon.mouse_exited.connect(_on_owned_item_icon_mouse_exited.bind(icon))
		owned_item_icons.add_child(icon)
	owned_item_icons.visible = owned_item_icons.get_child_count() > 0


# 图标按住时显示完整战利品信息；鼠标与触屏都在松开时关闭，避免详情残留在战斗操作区。
func _on_owned_item_icon_gui_input(event: InputEvent, icon: TextureRect, item: Resource) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_select_owned_item_icon(icon, item)
		else:
			_hide_owned_item_detail()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_select_owned_item_icon(icon, item)
		else:
			_hide_owned_item_detail()


# 鼠标悬停可直接查看详情；触屏不会触发这两个信号，仍只使用按住语义。
func _on_owned_item_icon_mouse_entered(icon: TextureRect, item: Resource) -> void:
	_select_owned_item_icon(icon, item)


func _on_owned_item_icon_mouse_exited(icon: TextureRect) -> void:
	if icon == _selected_item_icon:
		_hide_owned_item_detail()


# 详情浮层只在按住期间存在，释放发生在图标外部时也由全局输入路径兜底关闭。
func _input(event: InputEvent) -> void:
	if not item_detail_popup.visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_hide_owned_item_detail()
	elif event is InputEventScreenTouch and not event.pressed:
		_hide_owned_item_detail()


# 详情内容复用战利品选择页的品级色块；后续替换正式插画时只需在此替换纹理来源。
func _select_owned_item_icon(icon: TextureRect, item: Resource) -> void:
	if item == null:
		_hide_owned_item_detail()
		return
	if _selected_item_icon != null and _selected_item_icon != icon:
		_animate_owned_item_icon_scale(_selected_item_icon, ITEM_ICON_NORMAL_SCALE)
	_selected_item_icon = icon
	_animate_owned_item_icon_scale(icon, ITEM_ICON_SELECTED_SCALE)
	item_detail_icon.texture = _get_item_icon(item)
	item_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_detail_name.text = item.display_name
	item_detail_description.text = _to_player_grade_terms(item.description)
	item_detail_popup.show()


# 战斗内两个图标入口复用同一纹理选择，缺失图片不会影响旧档恢复或禁用战利品调试。
func _get_item_icon(item: Resource) -> Texture2D:
	if item != null and item.icon != null:
		return item.icon
	return BOSS_ITEM_PLACEHOLDER if item != null and item.rarity == ITEM_DEFINITION.Rarity.BOSS else NORMAL_ITEM_PLACEHOLDER


func _hide_owned_item_detail() -> void:
	item_detail_popup.hide()
	if _selected_item_icon != null:
		_animate_owned_item_icon_scale(_selected_item_icon, ITEM_ICON_NORMAL_SCALE)
		_selected_item_icon = null


# 每个图标仅保留一个线性缩放 Tween；中途切换时从当前尺寸接续，避免残留在放大状态。
func _animate_owned_item_icon_scale(icon: TextureRect, target_scale: Vector2) -> void:
	if icon == null or not is_instance_valid(icon):
		return
	var previous_tween := _item_icon_scale_tweens.get(icon) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	var scale_tween := create_tween().bind_node(icon)
	scale_tween.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	scale_tween.tween_property(icon, "scale", target_scale, ITEM_ICON_SCALE_DURATION)
	_item_icon_scale_tweens[icon] = scale_tween


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
	if controller.item_runtime.has_item(BLINDFOLD_ID):
		# 图标与数字独立排版；按钮本体只保留点击和圆形底板，蒙眼布状态用提示说明语义。
		skill_count_label.text = "%d/3" % controller.blindfold_charges
		skill_button.tooltip_text = "换牌 %d/3" % controller.blindfold_charges
		skill_button.disabled = not can_act or controller.blindfold_charges <= 0
	elif current_skill == null:
		skill_count_label.text = "0/3"
		skill_button.tooltip_text = "连击 0/3"
	else:
		skill_count_label.text = "%d/3" % combo_count
		skill_button.tooltip_text = "%s %d/3" % [current_skill.display_name, combo_count]
	if not controller.item_runtime.has_item(BLINDFOLD_ID):
		skill_button.disabled = not can_act or not controller.combo_state.can_activate()
	# 波形环严格复用最终禁用状态，蒙眼布的换牌入口不会误显示为连击已准备。
	skill_pulse_ring.call("set_skill_ready", not skill_button.disabled)
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
		# 非足球的追加打击同样等待前序飞球命中，再提交核心伤害并刷新血条。
		if bool(event.get("deferred_damage", false)):
			if controller.commit_deferred_damage(event):
				_apply_effect_feedback(event)
			event_index += 1
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
	# 红牌与手动结束回合复用同一敌方飞球和命中结算入口，避免两套时序产生差异。
	_resolve_enemy_turn_with_ball({}, true, discarded)


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
		_play_shot_event(flight, event, launch_music_time, completion, index > 0)
	while completion.remaining > 0:
		await get_tree().process_frame


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
			var health_after: int = int(event.get("health_after", target.health))
			var health_damage: int = int(event.get("health_damage", 0))
			var absorbed: int = int(event.get("absorbed", 0))
			display.set_health(health_after)
			# 战斗表现期间全量状态刷新会被抑制；顶部怪物血条必须在每颗球命中时读取该段快照，
			# 否则虽然核心已经逐段扣血，玩家仍只会在整张牌结束后看到最终生命。
			if target == controller.enemy:
				_set_monster_health_display(health_after)
			display.set_shield(event.get("shield_after", target.shield))
			# 受击类音效只服务玩家：怪物受伤或护甲吸收仍保留画面反馈，但不额外播音。
			if target == controller.player and absorbed > 0:
				_hit_shield_audio.play()
			if target == controller.player and health_damage > 0:
				_take_damage_audio.play()
			if health_damage > 0:
				# 射门事件携带真实弹道和方向，显示层据此选择击退或压扁动作。
				display.show_damage(
					health_damage,
					int(event.get("shot_type", 0)),
					int(event.get("shot_direction", 0))
				)
			elif absorbed > 0:
				display.show_shield_loss(absorbed)
		"heal":
			display.set_health(event.get("health_after", target.health))
			display.show_heal(event.amount)
		"shield":
			display.set_shield(event.get("shield_after", target.shield))
			var shield_gained: int = int(event.get("amount", 0))
			if shield_gained > 0:
				_shield_audio.play()
				display.show_shield_gain(shield_gained)
		"shield_spent":
			# 主动卸甲不是受伤，但仍即时刷新护盾条并复用护盾损失表现。
			display.set_shield(event.get("shield_after", target.shield))
			display.show_shield_loss(event.amount)
		"bgm_pitch":
			# 音频节点由跨场景服务唯一持有；卡牌事件只描述升降或复原意图。
			var bgm_service := get_node_or_null("/root/BgmService")
			if bgm_service == null:
				return
			if event.get("reset", false):
				bgm_service.reset_battle_pitch()
			else:
				bgm_service.shift_battle_pitch(int(event.get("semitone_delta", 0)))
	if target == controller.player:
		# 多段命中期间全量刷新被抑制，玩家专用 HUD 必须跟随每段结算后的快照立即刷新。
		_refresh_player_hud()


# 只刷新玩家可见的顶部怪物生命，不读取控制器的未来状态，保证并发多段按命中顺序显示。
func _set_monster_health_display(current_health: int) -> void:
	var max_health: int = maxi(controller.enemy.max_health, 1)
	var safe_health := clampi(current_health, 0, max_health)
	enemy_health_fill_clip.size.x = 123.0 * float(safe_health) / float(max_health)
	enemy_health_text.text = "%d/%d" % [safe_health, max_health]


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
	if victory:
		_schedule_game_win_audio(_battle_generation)
	if _is_presenting_resolution:
		_pending_battle_result = victory
		_update_input_state()
		return
	_finalize_battle_result(victory)


# 胜利信号即怪物死亡时刻；沿连续 BGM 时间轴等待下一整数拍，新战斗或停曲会取消旧任务。
func _schedule_game_win_audio(battle_generation: int) -> void:
	if _game_win_audio_scheduled:
		return
	_game_win_audio_scheduled = true
	var death_time: float = rhythm_clock.get_music_time()
	var target_beat_time: float = rhythm_clock.get_next_beat_time(death_time)
	while (
		is_inside_tree()
		and battle_generation == _battle_generation
		and rhythm_clock.is_music_playing()
		and rhythm_clock.get_music_time() < target_beat_time
	):
		await get_tree().process_frame
	if not is_inside_tree() or battle_generation != _battle_generation or not rhythm_clock.is_music_playing():
		return
	var bgm_service := get_node_or_null("/root/BgmService")
	if bgm_service != null:
		bgm_service.play_game_win_sfx()
	game_win_audio_triggered.emit(death_time, target_beat_time, rhythm_clock.get_music_time())


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
		# 测试玩法的击杀不产生胜利、奖励、存档或路线推进；保留玩家当前生命并刷新下一只固定 100 血怪物。
		if run_state.is_test_battle:
			run_state.record_battle_health(controller.player.health)
			start_new_battle()
			return
	_gm_menu_open = false
	gm_overlay.hide()
	# 胜利后的奖励页继续沿用战斗曲；只有后续触发实际 BGM 切换时，常驻服务才会停止它。
	if not victory:
		rhythm_clock.stop_music()
	_last_victory = victory
	run_state.record_battle_health(controller.player.health)
	# 失败不提交房间完成；胜利保留到普通怪卡牌或精英/Boss 两步奖励领取后再提交。
	if not victory:
		run_state.mark_run_failed()
		run_state.cancel_current_room()
	_update_input_state()
	# 结算层继续保留战斗舞台作为背景；标题、徽记与摘要共同说明结果，避免只靠按钮颜色区分胜负。
	var is_boss_victory: bool = (
		victory
		and controller.current_enemy_definition != null
		and controller.current_enemy_definition.tier == 2
	)
	var has_item_reward: bool = (
		victory
		and controller.current_enemy_definition != null
		and controller.current_enemy_definition.tier >= 1
	)
	result_kicker.text = "STAGE CLEAR  •  LIVE COMPLETE" if victory else "RUN ENDED  •  GOAL LOST"
	victory_mark.text = "✦  V  ✦" if victory else "—  ×  —"
	result_title.text = "战斗胜利" if victory else "战斗失败"
	result_detail.text = "节拍仍在继续，领取本场奖励后返回路线地图。" if victory else "球门失守，本局已经结束；整顿阵容后再来一场。"
	health_stat_label.text = "♥  %d / %d" % [run_state.player_hp, run_state.max_hp]
	reward_stat_label.text = ("✦  2 项奖励" if has_item_reward else "✦  1 项卡牌奖励") if victory else "本局已结算"
	result_action_button.text = "领取奖励  →" if victory else "查看本局结算  →"
	if victory:
		# 沿用旧存档字段承载“存在奖励品步骤”；奖励页再依据当前房间区分精英普通池与 Boss 稀有池。
		run_state.pending_reward_is_boss = has_item_reward
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
	_play_result_entrance()
	_victory_result_delay_pending = false


# 结果面板以短促上浮进入，动效只影响表现层，不延迟存档与奖励状态提交。
func _play_result_entrance() -> void:
	result_panel.pivot_offset = result_panel.size * 0.5
	result_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	result_panel.scale = Vector2(0.94, 0.94)
	var tween := create_tween().bind_node(result_panel).set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(result_panel, "scale", Vector2.ONE, 0.28)
	tween.tween_property(result_panel, "modulate:a", 1.0, 0.18)


# 胜利进入奖励页（普通怪一步、精英/Boss 两步），失败进入独立结算页。
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
