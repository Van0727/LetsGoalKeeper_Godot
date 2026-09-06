# 可玩战斗界面：连接战斗核心、牌堆和拖拽输入，并维护竖屏球场式信息布局与即时反馈。
extends Control

const BATTLE_CONTROLLER := preload("res://scripts/battle/battle_controller.gd")
const DECK_STATE := preload("res://scripts/cards/deck_state.gd")
const REWARD_SERVICE := preload("res://scripts/rewards/reward_service.gd")
const RUN_STATE_SCRIPT := preload("res://autoload/run_state.gd")
const CARD_VIEW_SCENE := preload("res://scenes/card_view.tscn")
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
@onready var play_zone: PanelContainer = %PlayZone
@onready var play_zone_label: Label = %PlayZoneLabel
@onready var ball_label: Label = %BallLabel
@onready var shot_type_label: Label = %ShotTypeLabel
@onready var ball_timer: Timer = %BallTimer
@onready var turn_label: Label = %TurnLabel
@onready var intent_label: Label = %IntentLabel
@onready var energy_label: Label = %EnergyLabel
@onready var status_label: Label = %StatusLabel
@onready var hand_layer: Control = %HandLayer
@onready var pile_label: Label = %PileLabel
@onready var skill_button: Button = %SkillButton
@onready var end_turn_button: Button = %EndTurnButton
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
var _skills_by_type := {
	0: SUPER_ATTACK,
	1: SUPER_DEFENSE,
	2: SUPER_ABILITY,
}


# 初始化信号和一场固定种子的可玩战斗，便于复现输入与结算问题。
func _ready() -> void:
	run_state = get_node_or_null("/root/RunState")
	# 独立场景测试没有 Autoload 时创建局部状态，正式游戏始终使用全局实例。
	if run_state == null:
		run_state = RUN_STATE_SCRIPT.new()
		add_child(run_state)
	_apply_chapter_theme()
	controller.log_added.connect(_on_log_added)
	controller.state_changed.connect(_refresh_all)
	controller.effect_resolved.connect(_on_effect_resolved)
	controller.battle_finished.connect(_on_battle_finished)
	ball_timer.timeout.connect(_hide_ball_feedback)
	# 参考布局把敌人作为上方视觉焦点，玩家状态则压缩到底部生命栏。
	enemy_display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.ENEMY)
	player_display.set_battle_layout_role(CharacterDisplay.BattleLayoutRole.PLAYER_BAR)
	start_new_battle()


# 战斗背景固定为参考界面的蓝灰球场色，避免章节色把上下信息区切成不同底色。
func _apply_chapter_theme() -> void:
	background.color = Color(0.17, 0.29, 0.45, 1.0)


# 使用本局牌库和房间敌人重置战斗：路线地图进入的房间按房型从章节池选敌。
func start_new_battle(enemy_definition: Resource = null) -> void:
	result_overlay.hide()
	ball_label.hide()
	shot_type_label.hide()
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


# 尝试打出指定手牌；锁在核心结算与手牌重建完成前，拦截同帧重复输入。
func try_play_hand_card(hand_index: int) -> bool:
	if _input_locked or controller.phase != BATTLE_CONTROLLER.Phase.PLAYER_TURN:
		return false
	if hand_index < 0 or hand_index >= deck_state.hand.size():
		return false

	_input_locked = true
	_update_input_state()
	var played := controller.play_card_from_hand(deck_state, hand_index)
	if not played:
		_input_locked = false
		status_label.text = "无法打出这张牌，请检查能量"
		_update_input_state()
		return false

	status_label.text = "卡牌已结算"
	call_deferred("_finish_resolution")
	return true


# 出牌信号携带卡牌运行视图，稳定索引用于定位对应手牌定义。
func _on_card_played(card_view: DraggableCard) -> void:
	if card_view is BattleCardView:
		try_play_hand_card(card_view.hand_index)


# 拖拽开始时高亮有效区域，让鼠标与触摸获得一致的落点提示。
func _on_card_drag_started(_card_view: DraggableCard) -> void:
	play_zone.modulate = Color(1.18, 1.18, 0.72, 1.0)
	play_zone_label.text = "松开以出牌"


# 无效释放后恢复提示，卡牌自身负责回弹到手牌位置。
func _on_card_drag_finished(_card_view: DraggableCard, valid_drop: bool) -> void:
	play_zone.modulate = Color.WHITE
	play_zone_label.text = "出牌区"
	if not valid_drop:
		status_label.text = "未进入出牌区，卡牌已返回手牌"


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


# GM 调试按钮立即结束当前关卡；控制器负责绕过护盾和反伤并广播正常胜利。
func _on_gm_skip_pressed() -> void:
	if _input_locked:
		return
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
		card_view.play_zone = play_zone
		card_view.card_played.connect(_on_card_played)
		card_view.drag_started.connect(_on_card_drag_started)
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


# 费用不足的卡牌保持可见但禁止拖拽；结算和结束状态统一锁住所有操作。
func _update_input_state() -> void:
	var can_act := not _input_locked and controller.phase == BATTLE_CONTROLLER.Phase.PLAYER_TURN
	end_turn_button.disabled = not can_act
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


# 把结构化效果事件分派到对应角色显示，并为射门显示短暂静态足球占位。
func _on_effect_resolved(event: Dictionary) -> void:
	var target = event.get("target")
	var display: CharacterDisplay = player_display if target == controller.player else enemy_display
	match event.get("type", ""):
		"damage":
			display.set_health(target.health)
			display.set_shield(target.shield)
			if event.get("health_damage", 0) > 0:
				display.show_damage(event.health_damage)
			elif event.get("absorbed", 0) > 0:
				display.show_shield_loss(event.absorbed)
			if target == controller.enemy:
				_show_shot_type(event.get("shot_type", 0))
		"heal":
			display.set_health(target.health)
			display.show_heal(event.amount)
		"shield":
			display.set_shield(target.shield)
			display.show_shield_gain(event.amount)


# 将射门枚举转成阶段 3 的文字表现，足球只做显隐占位且不阻塞数值结算。
func _show_shot_type(shot_type: int) -> void:
	var names := ["射门", "直球", "香蕉球", "挑射", "随机射门"]
	var safe_index := clampi(shot_type, 0, names.size() - 1)
	ball_label.show()
	shot_type_label.text = names[safe_index]
	shot_type_label.show()
	ball_timer.start()


# 隐藏静态足球反馈，不参与结算时序。
func _hide_ball_feedback() -> void:
	ball_label.hide()
	shot_type_label.hide()


# 保留最近一条核心日志作为紧凑状态提示，便于解释无效操作与随机分支。
func _on_log_added(message: String) -> void:
	status_label.text = message
	var diagnostics := get_node_or_null("/root/DiagnosticsService")
	if diagnostics != null:
		diagnostics.record("battle", "message", {"message": message})


# 胜负确定后锁定输入并显示独立结果层，避免重复出牌或结束回合。
func _on_battle_finished(victory: bool) -> void:
	_input_locked = true
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
