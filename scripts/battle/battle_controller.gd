# 单场战斗流程控制器：协调回合状态、卡牌结算、敌人行动和胜负信号。
class_name BattleController
extends Node

# 表现层通过信号读取日志和刷新状态，核心结算不等待动画回调。
signal log_added(message: String)
signal state_changed
# 表现层逐条消费结构化事件；事件携带结算后快照，允许界面按动画顺序延迟显示。
signal effect_resolved(event: Dictionary)
signal battle_finished(victory: bool)
# 纪律牌只报告本回合成功出牌数；红牌的实际回合推进由表现层在当前卡牌动画结束后提交。
signal discipline_card_issued(card_color: String, played_count: int)

const COMBATANT_STATE := preload("res://scripts/battle/combatant_state.gd")
const EFFECT_RESOLVER := preload("res://scripts/battle/effect_resolver.gd")
const COMBO_STATE := preload("res://scripts/battle/combo_state.gd")
const SKILL_RESOLVER := preload("res://scripts/battle/skill_resolver.gd")
const BATTLE_ITEM_RUNTIME := preload("res://scripts/battle/battle_item_runtime.gd")
const BATTLE_ACTION_CONTEXT := preload("res://scripts/battle/battle_action_context.gd")
const ITEM_EFFECT := preload("res://scripts/items/item_effect_definition.gd")
const ENEMY_DEFINITION := preload("res://scripts/enemies/enemy_definition.gd")
const ENEMY_ACTION_DEFINITION := preload("res://scripts/enemies/enemy_action_definition.gd")
const ENEMY_ACTION_EFFECT := preload("res://scripts/enemies/enemy_action_effect.gd")
const PLAYER_MAX_HEALTH := 100
const PLAYER_MAX_ENERGY := 3
const ENEMY_MAX_HEALTH := 30
const ENEMY_BASE_DAMAGE := 8
const YELLOW_CARD_THRESHOLD := 5
const RED_CARD_THRESHOLD := 10
const CHUNGHWA_RED_CARD_THRESHOLD := 20
# 特殊战利品统一引用 CSV 数字 ID，避免玩法逻辑依赖英文资源名。
const ITEM_BAR_DICE := 4003
const ITEM_BLANK_SCORE := 4005
const ITEM_BLINDFOLD := 4006
const ITEM_CHUNGHWA_CIGARETTES := 4007
const ITEM_IN_EAR_MONITOR := 4016
const ITEM_REST_SCORE := 4023
const ITEM_RHYTHM_GAME_TROPHY := 4024
const ITEM_SPIKED_DRUM_MALLET := 4026
const ITEM_TATTOO_STICKER := 4027
# 桑巴专属卡统一使用配表数字 ID；英文资源名不参与运行时规则判断。
const CARD_OUTSIDE_CURVE := 1012
const CARD_SAMBA_DUET := 1013
const CARD_SPINNING_HAT_TRICK := 1014
const CARD_CUTBACK_TRIANGLE := 1015
const CARD_CARNIVAL_FINALE := 1016
const CARD_RAINBOW_DRIBBLE := 2011
const CARD_AGILE_SWITCH := 2012
const CARD_CHAIN_FEINT := 2013
const CARD_CARNIVAL_BEAT := 2014
const CARD_MEXICAN_WAVE := 2015
# 爆裂鼓手与钢铁门神卡牌继续使用数字 ID 常量，流派倾向文本只供策划阅读。
const CARD_DOUBLE_KICK_COMBO := 1017
const CARD_RAPID_FILL := 1018
const CARD_SHIELD_BASH := 1019
const CARD_GATE_BREAKER := 1020
const CARD_MALLET_WARMUP := 2016
const CARD_TEMPO_ACCELERATION := 2017
const CARD_PRESSURE_BUILDUP := 2018
const CARD_AFTERSHOCK_ARMOR := 2019
const CARD_SHED_ARMOR := 2020
const CARD_CLOSING_STANCE := 3002
const CARD_CYMBAL_BLOCK := 3003
const CARD_REINFORCED_POST := 3004
const CARD_LAYERED_DEFENSE := 3005
const CARD_PERFECT_BLOCK := 3006

# 战斗阶段限制玩家只能在自己的行动阶段操作。
enum Phase {
	NOT_STARTED,
	PLAYER_TURN,
	PLAYER_END,
	ENEMY_TURN,
	FINISHED,
}

# 玩家、敌人和回合字段都是本场战斗的运行时状态。
var player = COMBATANT_STATE.new("玩家", PLAYER_MAX_HEALTH, PLAYER_MAX_ENERGY)
var enemy = COMBATANT_STATE.new("企鹅", ENEMY_MAX_HEALTH)
var phase := Phase.NOT_STARTED
var turn_number := 0
var enemy_intent_damage := 0
var battle_seed := 0
var damage_modifiers: Dictionary = {}
# 敌人定义与当前行动只在本场战斗中引用，行动序号不会写回 Resource。
var current_enemy_definition: Resource
var current_enemy_action: Resource
var combo_state := COMBO_STATE.new()
var item_runtime := BATTLE_ITEM_RUNTIME.new()
# 最近一次成功提交的出牌上下文供表现、命中和测试读取；每次出牌都会创建新实例。
var current_action_context
var banana_shot_direction := 0
var player_cards_played_this_turn := 0
var red_card_pending := false
# 桑巴状态只属于当前战斗：最近球向跨回合保留，技能计数和“本回合”增益在回合开始清空。
var last_banana_direction := 0
var skill_cards_played_this_turn := 0
var pending_force_attack_banana := false
var pending_next_banana_bonus := 0
var pending_turn_banana_bonus := 0
var pending_turn_banana_extra_hits := 0
var pending_turn_multihit_shield := false
# 鼓手与门神的“下一张”状态允许跨回合等待合法目标；明确写有“本回合”的状态会在回合开始清除。
var pending_multihit_attack_bonus := 0
var pending_next_attack_extra_hits := 0
var pending_first_hit_bonus := 0
var pending_next_defense_shield_multiplier := 1.0
var pending_turn_multihit_shield_amount := 0
# 暴力流物品的充能与待消费倍率只存在于当前战斗；GM 取消对应物品时同步清理。
var blindfold_charges := 0
var pending_first_card_multiplier := 1.0
var pending_first_card_item_id := 0
var pending_next_damage_multiplier := 1.0
var bar_dice_end_turn_pending := false
# 蓄能类战利品在回合结束记录剩余能量，下一回合回满基础上限后作为一次性溢出能量发放。
var pending_carried_energy := 0
# 红牌阈值按本场持有物动态推导；GM 取消后立即恢复默认值，不写入存档。
var red_card_threshold := RED_CARD_THRESHOLD

var _rng := RandomNumberGenerator.new()
# 球路随机流与卡牌概率、敌人行动隔离；固定种子保证相同战局仍可复现。
var _shot_rng := RandomNumberGenerator.new()
var _effect_resolver = EFFECT_RESOLVER.new()
var _skill_resolver = SKILL_RESOLVER.new()
var _enemy_action_index := 0
# 新版架势与蓄力不写回资源；打断条件只统计真实扣盾/扣血，排除格挡和溢出伤害。
var enemy_thorns_amount := 0
var enemy_thorns_remaining := 0
var enemy_charge_rule := 0
var enemy_charge_threshold := 0
var enemy_charge_progress := 0
var enemy_charge_interrupted := false
# 多条件蓄力逐项记录进度；上面的单条件字段继续供旧界面与第一章测试读取。
var enemy_charge_conditions: Array[Dictionary] = []
var _enemy_catalog: Resource


# 用指定种子和可选敌人定义重置战斗及架势/蓄力；不传定义时保留阶段1的企鹅测试行为。
func setup(
		seed_value := 20260902,
		enemy_definition: Resource = null,
		run_damage_modifiers: Dictionary = {},
		item_definitions: Array[Resource] = [],
		run_max_energy_bonus := 0
) -> void:
	battle_seed = seed_value
	_rng.seed = battle_seed
	_shot_rng.seed = battle_seed * 31 + 17
	damage_modifiers = run_damage_modifiers.duplicate()
	player = COMBATANT_STATE.new("玩家", PLAYER_MAX_HEALTH, PLAYER_MAX_ENERGY + maxi(int(run_max_energy_bonus), 0))
	current_enemy_definition = enemy_definition
	if current_enemy_definition == null:
		enemy = COMBATANT_STATE.new("企鹅", ENEMY_MAX_HEALTH)
	else:
		enemy = COMBATANT_STATE.new(
			current_enemy_definition.display_name,
			current_enemy_definition.max_health
		)
	current_enemy_action = null
	_enemy_action_index = 0
	enemy_thorns_amount = 0
	enemy_thorns_remaining = 0
	enemy_charge_rule = 0
	enemy_charge_threshold = 0
	enemy_charge_progress = 0
	enemy_charge_interrupted = false
	enemy_charge_conditions.clear()
	_enemy_catalog = load("res://data/enemies/enemy_catalog.tres") if ResourceLoader.exists("res://data/enemies/enemy_catalog.tres") else null
	enemy.damage_taken.connect(_on_enemy_damage_taken)
	combo_state = COMBO_STATE.new()
	item_runtime.setup(item_definitions, battle_seed + 7919)
	_sync_red_card_threshold()
	current_action_context = null
	banana_shot_direction = 0
	player_cards_played_this_turn = 0
	red_card_pending = false
	last_banana_direction = 0
	skill_cards_played_this_turn = 0
	pending_force_attack_banana = false
	pending_next_banana_bonus = 0
	pending_turn_banana_bonus = 0
	pending_turn_banana_extra_hits = 0
	pending_turn_multihit_shield = false
	pending_multihit_attack_bonus = 0
	pending_next_attack_extra_hits = 0
	pending_first_hit_bonus = 0
	pending_next_defense_shield_multiplier = 1.0
	pending_turn_multihit_shield_amount = 0
	blindfold_charges = 0
	pending_first_card_multiplier = 1.0
	pending_first_card_item_id = 0
	pending_next_damage_multiplier = 1.0
	bar_dice_end_turn_pending = false
	pending_carried_energy = 0
	turn_number = 1
	phase = Phase.NOT_STARTED
	_log("战斗开始，seed=%d" % battle_seed)
	_resolve_item_commands(item_runtime.trigger(ITEM_EFFECT.Trigger.BATTLE_STARTED, _base_item_context()))
	_start_player_turn()


# 早期测试及后续主动技共用的直接攻击接口；伤害标签供熊被动识别。
func player_attack(base_damage := 6, damage_tag := "card") -> bool:
	if not _can_player_act():
		return false
	var final_damage := maxi(roundi(base_damage * player.strength_multiplier), 0)
	final_damage = _apply_enemy_damage_reduction(final_damage, damage_tag)
	var result := enemy.take_damage(final_damage)
	_log("玩家攻击：%d 伤害（护盾吸收 %d，生命损失 %d）" % [
		final_damage,
		result.absorbed,
		result.health_damage,
	])
	var event := {
		"type": "damage",
		"amount": final_damage,
		"absorbed": result.absorbed,
		"health_damage": result.health_damage,
		"target": enemy,
		"source": player,
		"damage_tag": damage_tag,
	}
	effect_resolved.emit(event)
	_resolve_reactive_passive(event)
	if player.is_dead():
		_finish_battle(false)
	elif enemy.is_dead():
		_finish_battle(true)
	else:
		state_changed.emit()
	return true


# GM 跳关直接结束当前敌人，不经过伤害、护盾或受击被动，但复用正常胜利信号。
func debug_force_victory() -> bool:
	if phase == Phase.NOT_STARTED or phase == Phase.FINISHED:
		return false
	enemy.health = 0
	enemy.shield = 0
	_log("GM跳过：立即消灭%s" % enemy.display_name)
	_finish_battle(true)
	return true


# 早期测试保留的直接防御接口。
func player_guard(amount := 6) -> bool:
	if not _can_player_act():
		return false
	var gained := player.gain_shield(amount)
	_log("玩家获得 %d 护盾" % gained)
	state_changed.emit()
	return true


# 早期测试保留的直接治疗接口。
func player_heal(amount := 6) -> bool:
	if not _can_player_act():
		return false
	var healed := player.heal(amount)
	_log("玩家尝试治疗 %d，实际恢复 %d" % [amount, healed])
	state_changed.emit()
	return true


# 检查行动阶段与费用；真实界面可把对敌射门标为待命中，测试和无动画入口默认保持同步结算。
func play_card(
		card: Resource,
		rhythm_result: Dictionary = {},
		defer_enemy_shot_damage := false
) -> bool:
	if not _can_player_act():
		return false
	if card == null:
		_log("无效卡牌")
		return false
	if not player.spend_energy(card.cost):
		_log("能量不足：%s 需要 %d，当前 %d" % [card.display_name, card.cost, player.energy])
		return false

	_log("打出 %s，支付 %d 能量" % [card.display_name, card.cost])
	# 耳返只覆盖本次出牌判定，不修改节拍时钟或传入字典；拍位仍由真实 BGM 时间决定。
	var effective_rhythm_result: Dictionary = rhythm_result.duplicate(true)
	if item_runtime.has_item(ITEM_IN_EAR_MONITOR):
		effective_rhythm_result["grade"] = 0
		effective_rhythm_result["grade_name"] = "Great"
		effective_rhythm_result["effect_multiplier"] = 1.0
		effective_rhythm_result["error_ms"] = 0.0
	current_action_context = BATTLE_ACTION_CONTEXT.new()
	current_action_context.setup(card, effective_rhythm_result)
	var shot_context: Dictionary = current_action_context.to_trigger_context()
	# 彩虹过人只消费下一张攻击牌；费用不足在此之前已返回，不会误消耗待用状态。
	if int(card.card_type) == 0 and pending_force_attack_banana:
		shot_context["shot_type"] = 2
		pending_force_attack_banana = false
	_resolve_item_commands(item_runtime.trigger(ITEM_EFFECT.Trigger.BEFORE_SHOT_RESOLVED, shot_context))
	# 仅标记“非香蕉球被战利品转换”的射门；原生香蕉球仍保留整张牌既有方向规则。
	var converted_banana: bool = int(card.shot_type) != 2 and int(shot_context.get("shot_type", card.shot_type)) == 2
	_resolve_actual_shot(current_action_context, int(shot_context.get("shot_type", card.shot_type)), converted_banana)
	var action_context: Dictionary = current_action_context.to_trigger_context()
	# 上回合乐谱待用倍率只在成功支付费用的首张牌消费，其他物品可再按配置相乘。
	action_context["card_effect_multiplier"] = pending_first_card_multiplier
	pending_first_card_multiplier = 1.0
	pending_first_card_item_id = 0
	_resolve_item_commands(item_runtime.trigger(ITEM_EFFECT.Trigger.BEFORE_CARD_PLAYED, action_context))
	current_action_context.actual_shot_type = int(action_context.get("shot_type", card.shot_type))
	current_action_context.shot_direction = int(action_context.get("shot_direction", 0))
	current_action_context.value_multiplier = float(action_context.get("value_multiplier", 1.0))
	if not effective_rhythm_result.is_empty():
		_log("节奏判定：%s（%+.0fms）" % [
			effective_rhythm_result.get("grade_name", "Miss"),
			float(effective_rhythm_result.get("error_ms", 0.0)),
		])
	var resolved_context: Dictionary = current_action_context.to_trigger_context()
	# 下一次攻击的叠层和倍率在出牌时锁定，整张多段牌共用，不能逐段重复消费。
	resolved_context["attack_bonus"] = float(action_context.get("attack_bonus", 0.0))
	resolved_context["card_effect_multiplier"] = float(action_context.get("card_effect_multiplier", 1.0))
	resolved_context["pending_damage_multiplier"] = pending_next_damage_multiplier
	resolved_context["converted_banana_per_hit"] = converted_banana
	_prepare_samba_attack_context(card, resolved_context)
	_prepare_drum_shield_context(card, resolved_context)
	var events := _effect_resolver.resolve_card(
		card,
		player,
		enemy,
		_rng,
		damage_modifiers,
		effective_rhythm_result,
		defer_enemy_shot_damage,
		item_runtime,
		resolved_context,
		_shot_rng
	)
	pending_next_damage_multiplier = float(resolved_context.get("pending_damage_multiplier", 1.0))
	last_banana_direction = int(resolved_context.get("previous_banana_direction", last_banana_direction))
	for event in events:
		# 方向牌在费用支付和效果成功后才改写本场状态；死亡结算前已发出的球保留原方向快照。
		if event.get("type") == "banana_direction":
			set_banana_shot_direction(int(event.get("direction", 0)))
		_resolve_item_commands(event.get("item_commands", []))
		if not event.get("deferred_damage", false):
			_log_effect_event(event)
		effect_resolved.emit(event)
		if not event.get("deferred_damage", false):
			_resolve_reactive_passive(event)
			_resolve_samba_hit_shield(event)
		if player.is_dead():
			break
	# 人字拖是每张攻击牌独立掷一次的追加打击，不附着在多段射门的每颗球上。
	if not player.is_dead() and not enemy.is_dead() and float(action_context.get("slipper_damage", 0.0)) > 0.0:
		_resolve_slipper_damage(ceili(float(action_context["slipper_damage"])), defer_enemy_shot_damage)
	_apply_samba_skill_rule(card, skill_cards_played_this_turn)
	_apply_drum_shield_card_rule(card, resolved_context)
	if int(card.card_type) == 2:
		skill_cards_played_this_turn += 1
	combo_state.register_card(card.card_type)
	_resolve_item_commands(item_runtime.trigger(
		ITEM_EFFECT.Trigger.AFTER_CARD_PLAYED,
		current_action_context.to_trigger_context()
	))

	# 乌龟反伤导致双方同时死亡时按玩家失败裁定，避免死亡状态继续领奖。
	if player.is_dead():
		_finish_battle(false)
	elif enemy.is_dead():
		_finish_battle(true)
	else:
		# 出牌成功后统计牌型与 Perfect；真实命中仍由受伤信号单独累计。
		_register_charge_card_play(card, effective_rhythm_result)
		_register_successful_card_play()
		state_changed.emit()
	return true


# 攻击牌在整牌结算前锁定方向序列、动态段数和待消费增益，避免延迟命中时读取到后续状态。
func _prepare_samba_attack_context(card: Resource, context: Dictionary) -> void:
	if int(card.card_type) != 0:
		return
	var card_id := int(card.get("id"))
	var shot_type := int(context.get("shot_type", card.shot_type))
	var base_hits := _card_enemy_damage_hits(card)
	context["previous_banana_direction"] = last_banana_direction
	match card_id:
		CARD_OUTSIDE_CURVE:
			context["banana_direction_bonus_mode"] = 1
			context["banana_direction_bonus"] = 3
		CARD_SAMBA_DUET:
			context["shot_direction_sequence"] = [-1, 1]
		CARD_SPINNING_HAT_TRICK:
			var first_direction := int(context.get("shot_direction", 0))
			if first_direction == 0:
				first_direction = -1
			context["shot_direction_sequence"] = [first_direction, -first_direction, first_direction]
		CARD_CUTBACK_TRIANGLE:
			context["banana_direction_bonus_mode"] = 2
			context["banana_direction_bonus"] = 2
		CARD_CARNIVAL_FINALE:
			context["base_hits_override"] = 1 + mini(skill_cards_played_this_turn, 4)
	if shot_type == 2:
		var bonus := pending_next_banana_bonus + pending_turn_banana_bonus
		if bonus > 0:
			context["attack_bonus"] = float(context.get("attack_bonus", 0.0)) + bonus
			pending_next_banana_bonus = 0
			pending_turn_banana_bonus = 0
		if pending_turn_banana_extra_hits > 0:
			context["extra_hits"] = pending_turn_banana_extra_hits
			context["extra_hit_amount"] = 2
			pending_turn_banana_extra_hits = 0
	var resolved_hits := int(context.get("base_hits_override", base_hits)) + int(context.get("extra_hits", 0))
	if pending_turn_multihit_shield and resolved_hits > 1:
		context["samba_shield_per_hit"] = 1
		pending_turn_multihit_shield = false


# 技能牌在自身数值步骤结束后设置后续牌状态；此前技能数用于判定连打和动态上限。
func _apply_samba_skill_rule(card: Resource, previous_skill_count: int) -> void:
	match int(card.get("id")):
		CARD_RAINBOW_DRIBBLE:
			pending_force_attack_banana = true
			pending_next_banana_bonus += 1
		CARD_AGILE_SWITCH:
			set_banana_shot_direction(-banana_shot_direction if banana_shot_direction != 0 else -1)
			pending_turn_banana_bonus += 1
			_log("效果：切换香蕉球方向至%s" % ("左" if banana_shot_direction < 0 else "右"))
			effect_resolved.emit({"type": "banana_direction", "direction": banana_shot_direction})
		CARD_CHAIN_FEINT:
			pending_next_banana_bonus += 2
			if previous_skill_count > 0:
				var restored := player.gain_energy(1)
				_log("效果：连续假动作恢复 %d 能量" % restored)
				effect_resolved.emit({"type": "energy", "amount": restored, "target": player})
		CARD_CARNIVAL_BEAT:
			pending_turn_banana_extra_hits = mini(previous_skill_count + 1, 3)
		CARD_MEXICAN_WAVE:
			pending_turn_multihit_shield = true


# 只统计对敌伤害步骤的原始段数；动态追加段数稍后叠加，非攻击效果不能误触发人浪助威。
func _card_enemy_damage_hits(card: Resource) -> int:
	var total := 0
	for effect in card.effects:
		if int(effect.effect_type) == 0 and int(effect.target) == 1:
			total += int(effect.hits)
	return total


# 人浪助威在真实命中后逐段给盾；延迟伤害由 commit_deferred_damage 在命中帧调用同一入口。
func _resolve_samba_hit_shield(event: Dictionary) -> void:
	if event.get("type") != "damage" or event.get("target") != enemy:
		return
	var hit_context: Dictionary = event.get("item_context", {})
	var amount := int(hit_context.get("samba_shield_per_hit", 0)) + int(hit_context.get("shield_per_hit", 0))
	if amount <= 0:
		return
	var gained := player.gain_shield(amount)
	_log("效果：人浪助威获得 %d 护盾" % gained)
	effect_resolved.emit({"type": "shield", "amount": gained, "target": player})


# 鼓手和门神在结算前消费“下一张”状态，并把护盾读取快照写入整牌上下文。
func _prepare_drum_shield_context(card: Resource, context: Dictionary) -> void:
	var card_id := int(card.get("id"))
	var card_type := int(card.card_type)
	var base_hits := _card_enemy_damage_hits(card)
	var extra_hits := int(context.get("extra_hits", 0))
	if card_type == 0:
		if pending_next_attack_extra_hits > 0:
			extra_hits += pending_next_attack_extra_hits
			context["extra_hit_amount"] = _first_enemy_damage_amount(card)
			pending_next_attack_extra_hits = 0
		context["extra_hits"] = extra_hits
		var total_hits := int(context.get("base_hits_override", base_hits)) + extra_hits
		if pending_multihit_attack_bonus > 0 and total_hits > 1:
			context["attack_bonus"] = float(context.get("attack_bonus", 0.0)) + pending_multihit_attack_bonus
			pending_multihit_attack_bonus = 0
		if pending_first_hit_bonus > 0:
			context["first_hit_bonus"] = pending_first_hit_bonus
			pending_first_hit_bonus = 0
		if pending_turn_multihit_shield_amount > 0 and total_hits > 1:
			context["shield_per_hit"] = pending_turn_multihit_shield_amount
			pending_turn_multihit_shield_amount = 0
		match card_id:
			CARD_SHIELD_BASH:
				context["attack_bonus"] = float(context.get("attack_bonus", 0.0)) + floori(player.shield / 2.0)
			CARD_GATE_BREAKER:
				var spent := player.spend_shield(player.shield)
				context["attack_bonus"] = float(context.get("attack_bonus", 0.0)) + spent * 2
				context["shield_spent"] = spent
				_log("效果：城门爆破消耗 %d 护盾" % spent)
				effect_resolved.emit({"type": "shield_spent", "amount": spent, "target": player, "shield_after": player.shield})
	elif card_type == 1:
		if pending_next_defense_shield_multiplier > 1.0:
			context["shield_multiplier"] = pending_next_defense_shield_multiplier
			pending_next_defense_shield_multiplier = 1.0
		match card_id:
			CARD_CLOSING_STANCE:
				if int(context.get("beat_in_bar", -1)) == 3:
					context["shield_bonus"] = 4
			CARD_LAYERED_DEFENSE:
				if player.shield > 0:
					context["shield_bonus"] = 3
			CARD_PERFECT_BLOCK:
				if int(context.get("rhythm_grade", -1)) == 0:
					context["shield_bonus"] = 3


# 技能和节拍防御在自身结算完成后建立后续状态；卸甲只移除护盾，不触发伤害事件。
func _apply_drum_shield_card_rule(card: Resource, context: Dictionary) -> void:
	match int(card.get("id")):
		CARD_MALLET_WARMUP:
			pending_multihit_attack_bonus += 2
		CARD_TEMPO_ACCELERATION:
			pending_next_attack_extra_hits += 1
		CARD_PRESSURE_BUILDUP:
			pending_next_defense_shield_multiplier *= 2.0
		CARD_AFTERSHOCK_ARMOR:
			pending_turn_multihit_shield_amount = 2
		CARD_SHED_ARMOR:
			var spent := player.spend_shield(6)
			pending_multihit_attack_bonus += floori(spent / 2.0)
			_log("效果：卸甲备战消耗 %d 护盾" % spent)
			effect_resolved.emit({"type": "shield_spent", "amount": spent, "target": player, "shield_after": player.shield})
		CARD_CYMBAL_BLOCK:
			if int(context.get("beat_in_bar", -1)) == 0:
				pending_first_hit_bonus += 3


# 节奏加速追加段沿用原牌第一个对敌伤害步骤的基础值；无伤害攻击安全返回0。
func _first_enemy_damage_amount(card: Resource) -> int:
	for effect in card.effects:
		if int(effect.effect_type) == 0 and int(effect.target) == 1:
			return int(effect.amount)
	return 0


# 追加打击在同步模式即时生效；实战飞球模式排到原球命中后，避免提前击杀目标。
func _resolve_slipper_damage(amount: int, defer_damage := false) -> void:
	if item_runtime.has_item(ITEM_TATTOO_STICKER) and player.health * 100 < player.max_health * 30:
		amount = ceili(amount * 1.5)
	if pending_next_damage_multiplier > 1.0:
		amount = ceili(amount * pending_next_damage_multiplier)
		pending_next_damage_multiplier = 1.0
	var final_damage := _apply_enemy_damage_reduction(maxi(amount, 0), "item")
	if defer_damage:
		effect_resolved.emit({
			"type": "damage", "amount": final_damage, "absorbed": 0,
			"health_damage": 0, "target": enemy, "source": player,
			"damage_tag": "item", "shot_type": 0, "shot_direction": 0,
			"deferred_damage": true,
			"item_context": {"shot_type": 0, "is_enemy_target": true},
		})
		return
	var result: Dictionary = enemy.take_damage(final_damage)
	var event: Dictionary = {
		"type": "damage", "amount": final_damage, "absorbed": result.absorbed,
		"health_damage": result.health_damage, "target": enemy, "source": player,
		"damage_tag": "item", "shot_type": 0, "shot_direction": 0,
		"health_after": enemy.health, "shield_after": enemy.shield,
	}
	_log_effect_event(event)
	effect_resolved.emit(event)
	_resolve_reactive_passive(event)


# 方向牌共用此接口；0 表示未指定，-1/1 分别为玩家视角左/右，跨回合保留并由 setup 重置。
func set_banana_shot_direction(direction: int) -> void:
	banana_shot_direction = signi(direction)


# GM 勾选变化只同步持有定义与旧式加成，不重新 setup 或恢复已失去的战斗生命等临时状态。
func debug_sync_items(item_definitions: Array[Resource], run_damage_modifiers: Dictionary) -> void:
	var had_blindfold := item_runtime.has_item(ITEM_BLINDFOLD)
	item_runtime.sync_items(item_definitions)
	if not item_runtime.has_item(ITEM_BLINDFOLD):
		blindfold_charges = 0
	elif not had_blindfold:
		blindfold_charges = 3
	if pending_first_card_item_id != 0 and not item_runtime.has_item(pending_first_card_item_id):
		pending_first_card_multiplier = 1.0
		pending_first_card_item_id = 0
	if not item_runtime.has_item(ITEM_BAR_DICE):
		pending_next_damage_multiplier = 1.0
		bar_dice_end_turn_pending = false
	_sync_red_card_threshold()
	damage_modifiers = run_damage_modifiers.duplicate()
	state_changed.emit()


# 战利品阈值只影响红牌；移除时若本回合已超过默认阈值，立刻锁定后续出牌。
func _sync_red_card_threshold() -> void:
	red_card_threshold = RED_CARD_THRESHOLD
	for item in item_runtime.items:
		if item != null and item.id == ITEM_CHUNGHWA_CIGARETTES:
			red_card_threshold = CHUNGHWA_RED_CARD_THRESHOLD
			break
	if phase == Phase.PLAYER_TURN and player_cards_played_this_turn >= red_card_threshold and not red_card_pending:
		red_card_pending = true
		discipline_card_issued.emit("red", player_cards_played_this_turn)


# 原生香蕉球仍在出牌前锁定方向；战利品转换的香蕉球仅在有固定方向时锁定，默认逐段判向。
func _resolve_actual_shot(action, configured_type: int, converted_banana := false) -> void:
	action.actual_shot_type = configured_type
	action.shot_direction = 0
	if configured_type == 4:
		match _shot_rng.randi_range(0, 3):
			0: action.actual_shot_type = 1
			1: action.actual_shot_type = 3
			_: action.actual_shot_type = 2
	if action.actual_shot_type == 2:
		if converted_banana:
			action.shot_direction = banana_shot_direction
		else:
			action.shot_direction = banana_shot_direction if banana_shot_direction != 0 else (-1 if _shot_rng.randi_range(0, 1) == 0 else 1)


# 释放与当前连击类型匹配的主动技；结算完成后无论结果都清空类型与点数。
func play_active_skill(skill: Resource, qte_result: Dictionary = {}, defer_turn_end := false) -> bool:
	if not _can_player_act():
		return false
	if skill == null or not combo_state.can_activate():
		_log("连击点不足，主动技需要3点")
		return false
	if skill.card_type != combo_state.card_type:
		_log("主动技类型与当前连击不匹配")
		return false

	var points: int = combo_state.count
	_log("释放%s，消耗%d点连击" % [skill.display_name, points])
	var damage_multiplier := _get_enemy_damage_multiplier("active_skill")
	if item_runtime.has_item(ITEM_TATTOO_STICKER) and player.health * 100 < player.max_health * 30:
		damage_multiplier *= 1.5
	if int(skill.card_type) == 0 and pending_next_damage_multiplier > 1.0:
		damage_multiplier *= pending_next_damage_multiplier
		pending_next_damage_multiplier = 1.0
	# 音游奖杯要求四音全部 Perfect；只翻倍数值，不翻倍强化持续回合或 QTE 次数。
	var perfect_skill_multiplier := 2.0 if item_runtime.has_item(ITEM_RHYTHM_GAME_TROPHY) and int(qte_result.get("perfect", 0)) == 4 and int(qte_result.get("good", 0)) == 0 and int(qte_result.get("miss", 0)) == 0 else 1.0
	var events := _skill_resolver.resolve_skill(
		skill,
		points,
		player,
		enemy,
		damage_multiplier,
		perfect_skill_multiplier
	)
	for event in events:
		_resolve_item_commands(event.get("item_commands", []))
		_log_effect_event(event)
		effect_resolved.emit(event)
		_resolve_reactive_passive(event)
	combo_state.clear()
	_resolve_item_commands(item_runtime.trigger(
		ITEM_EFFECT.Trigger.ACTIVE_SKILL_FINISHED,
		_base_item_context()
	))
	# 酒吧骰子在本次主动技结算后掷骰，增伤只留给后续伤害；结束回合由界面等动画播完再提交。
	if item_runtime.has_item(ITEM_BAR_DICE) and not player.is_dead() and not enemy.is_dead():
		if item_runtime.roll_percent(50):
			pending_next_damage_multiplier = 2.0
		else:
			bar_dice_end_turn_pending = true

	if player.is_dead():
		_finish_battle(false)
	elif enemy.is_dead():
		_finish_battle(true)
	else:
		state_changed.emit()
	if bar_dice_end_turn_pending and not defer_turn_end and phase == Phase.PLAYER_TURN:
		resolve_bar_dice_end_turn()
	return true


# 蒙眼布每回合至多换牌三次；换牌失败不消耗次数。
func use_blindfold_swap(deck_state) -> bool:
	if not _can_player_act() or not item_runtime.has_item(ITEM_BLINDFOLD) or blindfold_charges <= 0:
		return false
	if not deck_state.swap_single_hand_card():
		return false
	blindfold_charges -= 1
	state_changed.emit()
	return true


# 酒吧骰子强制回合结束必须在主动技视觉完成后提交，避免中途清空手牌和目标状态。
func resolve_bar_dice_end_turn() -> bool:
	if not bar_dice_end_turn_pending or phase != Phase.PLAYER_TURN:
		return false
	bar_dice_end_turn_pending = false
	_end_player_turn()
	return true


# QTE失败仍消耗已承诺的主动技连击，但绝不调用效果执行器，避免先写入伤害再回滚。
func consume_failed_active_skill(skill: Resource) -> bool:
	if not _can_player_act():
		return false
	if skill == null or not combo_state.can_activate():
		_log("连击点不足，无法结算失败的主动技")
		return false
	if skill.card_type != combo_state.card_type:
		_log("失败主动技类型与当前连击不匹配")
		return false
	var points: int = combo_state.count
	combo_state.clear()
	_log("%s QTE失败，消耗%d点连击且不生效" % [skill.display_name, points])
	state_changed.emit()
	return true


# 从指定手牌位置出牌；节奏结果与卡牌一并提交，只有结算成功才移动卡牌并补牌。
func play_card_from_hand(
		deck_state,
		hand_index: int,
		rhythm_result: Dictionary = {},
		defer_enemy_shot_damage := false
) -> bool:
	if hand_index < 0 or hand_index >= deck_state.hand.size():
		_log("无效手牌位置")
		return false
	var card: Resource = deck_state.hand[hand_index]
	if not play_card(card, rhythm_result, defer_enemy_shot_damage):
		return false
	# 狼牙鼓槌只取消成功出牌后的自动补牌，不影响回合开始或显式换牌抽取。
	deck_state.play_card_at(hand_index, not item_runtime.has_item(ITEM_SPIKED_DRUM_MALLET))
	return true


# 足球抵达目标拍点时提交单段待命中伤害；护盾、反伤和胜负都从这一帧的真实状态计算。
func commit_deferred_damage(event: Dictionary) -> bool:
	if not event.get("deferred_damage", false):
		return false
	var target = event.get("target")
	if target == null or target.is_dead() or phase == Phase.FINISHED:
		return false
	var result: Dictionary = target.take_damage(int(event.get("amount", 0)))
	event.absorbed = result.absorbed
	event.health_damage = result.health_damage
	event.health_after = target.health
	event.shield_after = target.shield
	event.deferred_damage = false
	var after_context: Dictionary = event.get("item_context", {}).duplicate(true)
	after_context["amount"] = int(event.get("amount", 0))
	after_context["health_damage"] = result.health_damage
	_resolve_item_commands(item_runtime.trigger(ITEM_EFFECT.Trigger.AFTER_DAMAGE, after_context))
	_log_effect_event(event)
	_resolve_reactive_passive(event)
	_resolve_samba_hit_shield(event)
	# 命中造成双方同时死亡时仍按玩家失败裁定，与同步卡牌结算规则一致。
	if player.is_dead():
		_finish_battle(false)
	elif enemy.is_dead():
		_finish_battle(true)
	else:
		state_changed.emit()
	return true


# 结束玩家阶段并立即执行当前敌人行动。
func end_player_turn(rhythm_result: Dictionary = {}, defer_enemy_action := false) -> bool:
	if not _can_player_act():
		return false
	_end_player_turn(rhythm_result, defer_enemy_action)
	return true


# 红牌只允许在当前阈值牌完整表现后消费；普通调用不能绕过待结算状态重复推进回合。
func force_end_turn_for_red_card(defer_enemy_action := false) -> bool:
	if not red_card_pending or phase != Phase.PLAYER_TURN:
		return false
	red_card_pending = false
	_end_player_turn({}, defer_enemy_action)
	return true


func _end_player_turn(rhythm_result: Dictionary = {}, defer_enemy_action := false) -> void:
	phase = Phase.PLAYER_END
	# 乐谱按本回合成功出牌数决定下一回合首张牌倍率，不跨多个空回合叠乘。
	pending_first_card_multiplier = 1.0
	pending_first_card_item_id = 0
	if player_cards_played_this_turn == 0 and item_runtime.has_item(ITEM_BLANK_SCORE):
		pending_first_card_multiplier = 4.0
		pending_first_card_item_id = ITEM_BLANK_SCORE
	elif player_cards_played_this_turn == 1 and item_runtime.has_item(ITEM_REST_SCORE):
		pending_first_card_multiplier = 2.0
		pending_first_card_item_id = ITEM_REST_SCORE
	_log("玩家结束第 %d 回合" % turn_number)
	var end_context: Dictionary = _base_item_context()
	end_context["beat_in_bar"] = int(rhythm_result.get("beat_in_bar", -1))
	end_context["is_last_beat"] = bool(rhythm_result.get("is_last_beat", false))
	_resolve_item_commands(item_runtime.trigger(ITEM_EFFECT.Trigger.TURN_ENDED, end_context))
	# 先结算末拍战利品加盾，再结算流血；流血致死后不能继续执行怪物行动。
	var bleed_event: Dictionary = player.tick_bleed()
	if not bleed_event.is_empty():
		_log("流血结算：生命损失%d，剩余%d回合" % [bleed_event.health_damage, player.bleed_turns])
		effect_resolved.emit(bleed_event)
	if player.is_dead():
		_finish_battle(false)
		return
	_advance_strength_status(player)
	# 战斗界面需要先播放敌方向玩家的足球；前置结算完成后停在玩家结算阶段，命中帧再继续敌人行动。
	if defer_enemy_action:
		state_changed.emit()
		return
	_execute_enemy_turn()


# 只允许从已完成前置结算的玩家结束阶段继续，避免动画回调重复造成敌人多次行动。
func continue_deferred_enemy_turn() -> bool:
	if phase != Phase.PLAYER_END or player.is_dead() or enemy.is_dead():
		return false
	_execute_enemy_turn()
	return true


# 返回供界面显示的中文阶段名称。
func get_phase_text() -> String:
	match phase:
		Phase.PLAYER_TURN:
			return "玩家行动"
		Phase.PLAYER_END:
			return "玩家结算"
		Phase.ENEMY_TURN:
			return "敌人行动"
		Phase.FINISHED:
			return "战斗结束"
		_:
			return "尚未开始"


# 玩家回合开始时清盾、回满基础能量，再发放上回合结转和配表声明的临时溢出能量。
func _start_player_turn() -> void:
	# 每个玩家回合独立计数；黄牌不会跨回合累计，红牌也不能泄漏到下一回合。
	player_cards_played_this_turn = 0
	skill_cards_played_this_turn = 0
	pending_turn_banana_bonus = 0
	pending_turn_banana_extra_hits = 0
	pending_turn_multihit_shield = false
	pending_turn_multihit_shield_amount = 0
	red_card_pending = false
	item_runtime.start_turn()
	blindfold_charges = 3 if item_runtime.has_item(ITEM_BLINDFOLD) else 0
	var cleared_shield := player.clear_shield()
	var restored_energy := player.refill_energy()
	var carried_energy := player.gain_temporary_energy(pending_carried_energy)
	pending_carried_energy = 0
	phase = Phase.PLAYER_TURN
	_resolve_item_commands(item_runtime.trigger(ITEM_EFFECT.Trigger.TURN_STARTED, _base_item_context()))
	_prepare_enemy_intent()
	_log("第 %d 回合：玩家行动（清除护盾 %d，恢复能量 %d，结转能量 %d）" % [turn_number, cleared_shield, restored_energy, carried_energy])
	_log("敌人意图：%s" % get_enemy_intent_text())
	state_changed.emit()


# 执行已经展示的敌方行动；玩家存活时推进回合并生成下一次意图。
func _execute_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	var cleared_shield := enemy.clear_shield()
	# 防御架势在自身下次行动开始时结束，剩余格挡或反伤次数不能跨越该边界。
	enemy.single_block = 0
	enemy_thorns_amount = 0
	enemy_thorns_remaining = 0
	_log("敌人行动（清除护盾 %d）" % cleared_shield)
	_execute_current_enemy_action()
	_advance_strength_status(enemy)
	if player.is_dead():
		_finish_battle(false)
		return
	turn_number += 1
	_start_player_turn()


# 在基础伤害上下 20% 范围内生成敌人最终意图值。
func _roll_enemy_damage() -> int:
	return maxi(roundi(ENEMY_BASE_DAMAGE * _rng.randf_range(0.8, 1.2)), 0)


# 返回包含当前力量/虚弱倍率的最终敌人意图伤害。
func get_enemy_intent_damage() -> int:
	if current_enemy_action != null and not current_enemy_action.effects.is_empty():
		for effect in current_enemy_action.effects:
			if effect.effect_type in [ENEMY_ACTION_EFFECT.Type.DAMAGE, ENEMY_ACTION_EFFECT.Type.DRAIN]:
				return maxi(roundi(effect.amount * enemy.strength_multiplier), 0)
		return 0
	return maxi(roundi(enemy_intent_damage * enemy.strength_multiplier), 0)


# 供表现层判断是否需要发射敌方足球；吸血同样属于直接攻击，纯状态和防御行动不发球。
func enemy_intent_has_direct_attack() -> bool:
	if current_enemy_action == null:
		return true
	if not current_enemy_action.effects.is_empty():
		for effect in current_enemy_action.effects:
			if effect.effect_type in [ENEMY_ACTION_EFFECT.Type.DAMAGE, ENEMY_ACTION_EFFECT.Type.DRAIN]:
				return true
		return false
	return current_enemy_action.action_type in [
		ENEMY_ACTION_DEFINITION.ActionType.ATTACK,
		ENEMY_ACTION_DEFINITION.ActionType.DRAIN,
	]


# 返回当前行动的最终意图文字；非攻击行为直接显示其数据值。
func get_enemy_intent_text() -> String:
	if current_enemy_action == null:
		return "攻击 %d" % get_enemy_intent_damage()
	if not current_enemy_action.effects.is_empty():
		var descriptions: Array[String] = []
		var action_description := _to_player_grade_terms(current_enemy_action.description)
		for effect in current_enemy_action.effects:
			if effect.effect_type in [ENEMY_ACTION_EFFECT.Type.DAMAGE, ENEMY_ACTION_EFFECT.Type.DRAIN]:
				var damage := maxi(roundi(effect.amount * enemy.strength_multiplier), 0)
				descriptions.append("%d×%d伤害%s" % [damage, effect.hits, "并吸血" if effect.effect_type == ENEMY_ACTION_EFFECT.Type.DRAIN else ""])
			elif effect.effect_type == ENEMY_ACTION_EFFECT.Type.BLEED:
				descriptions.append("流血%d点/%d回合" % [effect.amount, effect.turns])
			elif effect.effect_type == ENEMY_ACTION_EFFECT.Type.SHIELD:
				descriptions.append("护盾%d" % effect.amount)
			elif effect.effect_type == ENEMY_ACTION_EFFECT.Type.BLOCK:
				descriptions.append("单次格挡%d" % effect.amount)
			elif effect.effect_type == ENEMY_ACTION_EFFECT.Type.THORNS:
				descriptions.append("反伤%d（最多%d次）" % [effect.amount, effect.hits])
			elif effect.effect_type == ENEMY_ACTION_EFFECT.Type.CHARGE:
				# 多条蓄力效果共享同一行为文案，避免意图面板重复挤占空间。
				if not descriptions.has(action_description):
					descriptions.append(action_description)
			else:
				descriptions.append(action_description)
		var text := "%s·%s：%s" % [["攻击", "防御", "技能"][current_enemy_action.category], current_enemy_action.display_name, "；".join(descriptions)]
		if not enemy_charge_conditions.is_empty():
			var conditions: Array[String] = []
			for condition in enemy_charge_conditions:
				conditions.append("%s %d/%d" % [_charge_rule_name(int(condition.rule)), int(condition.progress), int(condition.threshold)])
			text += "\n%s%s" % [" 或 ".join(conditions), "，已打断" if enemy_charge_interrupted else "可打断"]
		return text
	return _to_player_grade_terms(current_enemy_action.get_intent_text(get_enemy_intent_damage()))


# 配表和规则枚举继续保留内部 Perfect 契约，所有战斗玩家文案统一显示新等级名 Great。
func _to_player_grade_terms(text: String) -> String:
	return text.replace("Perfect", "Great")


# 回合刷新时供真实界面持续显示状态，不能仅依赖会被出牌提示覆盖的日志。
func get_enemy_rules_text() -> String:
	var states: Array[String] = []
	if player.bleed_turns > 0:
		states.append("流血%d点/%d回合" % [player.bleed_amount, player.bleed_turns])
	if enemy.single_block > 0:
		states.append("敌方单次格挡%d" % enemy.single_block)
	if enemy_thorns_remaining > 0:
		states.append("敌方反伤%d×%d" % [enemy_thorns_amount, enemy_thorns_remaining])
	return "　".join(states)


# 为线性敌人顺序取行动，为 Boss 按权重取行动，并仅在此刻结算随机浮动。
func _prepare_enemy_intent() -> void:
	if current_enemy_definition == null or current_enemy_definition.actions.is_empty():
		current_enemy_action = null
		enemy_intent_damage = _roll_enemy_damage()
		return

	if current_enemy_definition.action_mode == ENEMY_DEFINITION.ActionMode.WEIGHTED_RANDOM:
		current_enemy_action = _pick_weighted_action(current_enemy_definition.actions, current_enemy_definition.action_weights)
	else:
		current_enemy_action = current_enemy_definition.actions[
			_enemy_action_index % current_enemy_definition.actions.size()
		]
	if enemy_charge_interrupted and current_enemy_action.interrupted_action_id > 0 and _enemy_catalog != null:
		current_enemy_action = _enemy_catalog.find_action(current_enemy_action.interrupted_action_id)

	var variance: float = current_enemy_action.variance_percent / 100.0
	if variance > 0.0:
		enemy_intent_damage = maxi(roundi(
			current_enemy_action.amount * _rng.randf_range(1.0 - variance, 1.0 + variance)
		), 0)
	else:
		enemy_intent_damage = current_enemy_action.amount


# 新表读取怪物列表对应权重（空值默认每个行为1），旧表读取行动权重；非正权重安全忽略。
func _pick_weighted_action(actions: Array[Resource], configured_weights: Array[int] = []) -> Resource:
	var total_weight := 0
	var weights: Array[int] = []
	for index in range(actions.size()):
		var weight: int = actions[index].weight if configured_weights.is_empty() else (configured_weights[index] if index < configured_weights.size() else 0)
		weights.append(maxi(weight, 0))
		total_weight += weights.back()
	if total_weight <= 0:
		return actions[0]
	var roll := _rng.randi_range(1, total_weight)
	for index in range(actions.size()):
		roll -= weights[index]
		if roll <= 0:
			return actions[index]
	return actions.back()


# 按行动类型执行攻击、防御、治疗、虚弱和吸血；每项都发送同一套表现事件。
func _execute_current_enemy_action() -> void:
	if current_enemy_action == null:
		_execute_enemy_damage(get_enemy_intent_damage(), false)
		return
	if not current_enemy_action.effects.is_empty():
		_execute_table_enemy_action()
		if current_enemy_definition.action_mode == ENEMY_DEFINITION.ActionMode.SEQUENCE:
			_enemy_action_index += 1
		return

	match current_enemy_action.action_type:
		ENEMY_ACTION_DEFINITION.ActionType.ATTACK:
			_execute_enemy_damage(get_enemy_intent_damage(), false)
		ENEMY_ACTION_DEFINITION.ActionType.DRAIN:
			_execute_enemy_damage(get_enemy_intent_damage(), true)
		ENEMY_ACTION_DEFINITION.ActionType.SHIELD:
			var gained := enemy.gain_shield(current_enemy_action.amount)
			_log("%s 获得 %d 护盾" % [enemy.display_name, gained])
			effect_resolved.emit({"type": "shield", "amount": gained, "target": enemy})
		ENEMY_ACTION_DEFINITION.ActionType.HEAL:
			var healed := enemy.heal(current_enemy_action.amount)
			_log("%s 恢复 %d 生命" % [enemy.display_name, healed])
			effect_resolved.emit({"type": "heal", "amount": healed, "target": enemy})
		ENEMY_ACTION_DEFINITION.ActionType.APPLY_WEAKNESS:
			var turns := player.apply_weakness(
				current_enemy_action.multiplier,
				current_enemy_action.amount
			)
			_log("%s 使玩家虚弱，持续 %d 回合" % [enemy.display_name, turns])
			effect_resolved.emit({
				"type": "weakness",
				"multiplier": player.strength_multiplier,
				"turns": turns,
				"target": player,
			})

	if current_enemy_definition.action_mode == ENEMY_DEFINITION.ActionMode.SEQUENCE:
		_enemy_action_index += 1


# 一次只执行选定行为，效果按表中步骤结算；任一方死亡立即停止剩余段数和附带效果。
func _execute_table_enemy_action() -> void:
	var consuming_charge := not enemy_charge_conditions.is_empty()
	# 新一轮蓄力必须清除上一轮进度；一个行为的多条 CHARGE 共同组成或条件。
	for effect in current_enemy_action.effects:
		if effect.effect_type == ENEMY_ACTION_EFFECT.Type.CHARGE:
			_clear_enemy_charge()
			break
	for effect in current_enemy_action.effects:
		if player.is_dead() or enemy.is_dead():
			break
		var recipient = player if effect.target == ENEMY_ACTION_EFFECT.Target.PLAYER else enemy
		match effect.effect_type:
			ENEMY_ACTION_EFFECT.Type.DAMAGE, ENEMY_ACTION_EFFECT.Type.DRAIN:
				for hit in range(effect.hits):
					if player.is_dead():
						break
					_execute_enemy_damage(maxi(roundi(effect.amount * enemy.strength_multiplier), 0), effect.effect_type == ENEMY_ACTION_EFFECT.Type.DRAIN)
			ENEMY_ACTION_EFFECT.Type.SHIELD:
				var gained: int = recipient.gain_shield(effect.amount)
				effect_resolved.emit({"type": "shield", "amount": gained, "target": recipient, "health_after": recipient.health, "shield_after": recipient.shield})
			ENEMY_ACTION_EFFECT.Type.HEAL:
				var healed: int = recipient.heal(effect.amount)
				effect_resolved.emit({"type": "heal", "amount": healed, "target": recipient, "health_after": recipient.health, "shield_after": recipient.shield})
			ENEMY_ACTION_EFFECT.Type.WEAKNESS:
				recipient.apply_weakness(effect.multiplier, effect.turns)
				effect_resolved.emit({"type": "weakness", "target": recipient, "multiplier": recipient.strength_multiplier, "turns": recipient.strength_turns})
			ENEMY_ACTION_EFFECT.Type.STRENGTH:
				recipient.apply_strength(effect.multiplier, effect.turns + 1)
				# 自身技能在行动末尾也推进状态，因此补一回合，保证后续完整享有表中指定回合数。
				effect_resolved.emit({"type": "strength", "target": recipient, "multiplier": recipient.strength_multiplier, "turns": effect.turns})
			ENEMY_ACTION_EFFECT.Type.BLEED:
				recipient.apply_bleed(effect.amount, effect.turns)
				_log("施加流血%d点，持续%d回合" % [effect.amount, effect.turns])
			ENEMY_ACTION_EFFECT.Type.BLOCK:
				recipient.single_block = effect.amount
			ENEMY_ACTION_EFFECT.Type.THORNS:
				enemy_thorns_amount = effect.amount
				enemy_thorns_remaining = effect.hits
			ENEMY_ACTION_EFFECT.Type.CHARGE:
				enemy_charge_conditions.append({"rule": effect.break_rule, "threshold": effect.threshold, "progress": 0, "shot_types": {}})
				if enemy_charge_conditions.size() == 1:
					enemy_charge_rule = effect.break_rule
					enemy_charge_threshold = effect.threshold
	if consuming_charge:
		_clear_enemy_charge()


# 从每段真实受伤入口统计蓄力与有限反伤，避免同步多段在整牌结算后才触发机制。
func _on_enemy_damage_taken(result: Dictionary) -> void:
	var effective_damage := int(result.absorbed) + int(result.health_damage)
	if effective_damage <= 0:
		return
	if not enemy_charge_interrupted:
		for index in range(enemy_charge_conditions.size()):
			var condition: Dictionary = enemy_charge_conditions[index]
			if condition.rule == ENEMY_ACTION_EFFECT.BreakRule.HITS:
				condition.progress += 1
			elif condition.rule == ENEMY_ACTION_EFFECT.BreakRule.DAMAGE:
				condition.progress += effective_damage
			else:
				continue
			enemy_charge_conditions[index] = condition
			_check_charge_break(index)
			if enemy_charge_interrupted:
				break
	if enemy_thorns_remaining > 0 and not player.is_dead():
		enemy_thorns_remaining -= 1
		var reflected: Dictionary = player.take_damage(enemy_thorns_amount)
		_log("架势反伤%d，剩余%d次" % [enemy_thorns_amount, enemy_thorns_remaining])
		effect_resolved.emit({"type": "damage", "amount": enemy_thorns_amount, "absorbed": reflected.absorbed, "health_damage": reflected.health_damage, "target": player, "source": enemy, "damage_tag": "passive", "health_after": player.health, "shield_after": player.shield})


# 仅成功打出的卡牌满足卡牌类打断条件；球型按物品与卡牌规则转换后的实际球型去重。
func _register_charge_card_play(card: Resource, rhythm_result: Dictionary) -> void:
	if enemy_charge_interrupted or enemy_charge_conditions.is_empty():
		return
	var is_attack := int(card.card_type) == 0
	var is_perfect := rhythm_result.has("grade") and int(rhythm_result.grade) == 0
	for index in range(enemy_charge_conditions.size()):
		var condition: Dictionary = enemy_charge_conditions[index]
		match int(condition.rule):
			ENEMY_ACTION_EFFECT.BreakRule.PERFECT_ATTACK:
				if is_attack and is_perfect:
					condition.progress += 1
			ENEMY_ACTION_EFFECT.BreakRule.PERFECT_ANY:
				if is_perfect:
					condition.progress += 1
			ENEMY_ACTION_EFFECT.BreakRule.DISTINCT_SHOT_TYPES:
				if is_attack:
					var shot_types: Dictionary = condition.shot_types
					shot_types[int(current_action_context.actual_shot_type)] = true
					condition.shot_types = shot_types
					condition.progress = shot_types.size()
		enemy_charge_conditions[index] = condition
		_check_charge_break(index)
		if enemy_charge_interrupted:
			break


# 第一条件的镜像字段保持旧存档外的调试接口稳定；达标时立即替换当前预告行为。
func _check_charge_break(index: int) -> void:
	var condition: Dictionary = enemy_charge_conditions[index]
	if index == 0:
		enemy_charge_progress = int(condition.progress)
	if int(condition.progress) < int(condition.threshold) or enemy_charge_interrupted:
		return
	enemy_charge_interrupted = true
	if current_enemy_action != null and current_enemy_action.interrupted_action_id > 0 and _enemy_catalog != null:
		current_enemy_action = _enemy_catalog.find_action(current_enemy_action.interrupted_action_id)
	_log("蓄力已打断，重击改为普通攻击")


func _clear_enemy_charge() -> void:
	enemy_charge_conditions.clear()
	enemy_charge_rule = 0
	enemy_charge_threshold = 0
	enemy_charge_progress = 0
	enemy_charge_interrupted = false


func _charge_rule_name(rule: int) -> String:
	match rule:
		ENEMY_ACTION_EFFECT.BreakRule.HITS: return "有效命中"
		ENEMY_ACTION_EFFECT.BreakRule.DAMAGE: return "有效伤害"
		ENEMY_ACTION_EFFECT.BreakRule.PERFECT_ATTACK: return "Great攻击牌"
		ENEMY_ACTION_EFFECT.BreakRule.DISTINCT_SHOT_TYPES: return "不同球型攻击牌"
		ENEMY_ACTION_EFFECT.BreakRule.PERFECT_ANY: return "Great卡牌"
	return "未知条件"


# 敌人攻击统一结算护盾；吸血只恢复实际造成的生命伤害，不把护盾吸收量算入治疗。
func _execute_enemy_damage(final_damage: int, drain: bool) -> void:
	var result := player.take_damage(final_damage)
	_log("%s%s：%d 伤害（护盾吸收 %d，生命损失 %d）" % [
		enemy.display_name,
		"吸血" if drain else "攻击",
		final_damage,
		result.absorbed,
		result.health_damage,
	])
	var event := {
		"type": "damage",
		"amount": final_damage,
		"absorbed": result.absorbed,
		"health_damage": result.health_damage,
		"target": player,
		"source": enemy,
		"health_after": player.health,
		"shield_after": player.shield,
	}
	effect_resolved.emit(event)
	if drain and result.health_damage > 0:
		var healed := enemy.heal(result.health_damage)
		_log("%s 吸血恢复 %d 生命" % [enemy.display_name, healed])
		effect_resolved.emit({"type": "heal", "amount": healed, "target": enemy})


# 乌龟每次实际收到攻击调用都反伤一次，包括伤害完全被护盾吸收的情况。
func _resolve_reactive_passive(event: Dictionary) -> void:
	if current_enemy_definition == null:
		return
	if current_enemy_definition.passive_type != ENEMY_DEFINITION.PassiveType.THORNS:
		return
	if event.get("type") != "damage" or event.get("target") != enemy:
		return
	if event.get("amount", 0) <= 0 or player.is_dead():
		return
	var thorns_damage := maxi(roundi(current_enemy_definition.passive_value), 0)
	var result := player.take_damage(thorns_damage)
	_log("%s 被动反伤 %d（玩家生命损失 %d）" % [
		enemy.display_name,
		thorns_damage,
		result.health_damage,
	])
	effect_resolved.emit({
		"type": "damage",
		"amount": thorns_damage,
		"absorbed": result.absorbed,
		"health_damage": result.health_damage,
		"target": player,
		"source": enemy,
		"damage_tag": "passive",
		"health_after": player.health,
		"shield_after": player.shield,
	})


# 熊仅削减主动技能标签伤害；普通卡牌和其他伤害来源不受影响。
func _apply_enemy_damage_reduction(damage: int, damage_tag: String) -> int:
	return maxi(roundi(damage * _get_enemy_damage_multiplier(damage_tag)), 0)


# 返回指定伤害标签面对当前敌人时的倍率，供直接攻击与技能执行器共用。
func _get_enemy_damage_multiplier(damage_tag: String) -> float:
	if current_enemy_definition == null:
		return 1.0
	if current_enemy_definition.passive_type != ENEMY_DEFINITION.PassiveType.ACTIVE_SKILL_REDUCTION:
		return 1.0
	if damage_tag != "active_skill":
		return 1.0
	return clampf(current_enemy_definition.passive_value, 0.0, 1.0)


# 推进指定角色的伤害倍率状态，并在持续时间结束时记录恢复日志。
func _advance_strength_status(combatant) -> void:
	var result: Dictionary = combatant.advance_strength_turn()
	if result.expired:
		_log("%s 的力量状态已结束" % combatant.display_name)


# 统一拦截错误阶段的玩家操作并写入日志。
func _can_player_act() -> bool:
	if phase == Phase.PLAYER_TURN and not red_card_pending and not bar_dice_end_turn_pending:
		return true
	if red_card_pending:
		_log("已被出示红牌，必须结束当前回合")
		return false
	_log("当前阶段不能执行玩家行动")
	return false


# 只有完整支付费用并成功结算的牌才计数；阈值使用等号保证每回合各提示一次。
func _register_successful_card_play() -> void:
	player_cards_played_this_turn += 1
	if player_cards_played_this_turn == red_card_threshold:
		red_card_pending = true
		_log("红牌！本回合已打出 %d 张牌，当前卡牌结算后强制结束回合" % player_cards_played_this_turn)
		discipline_card_issued.emit("red", player_cards_played_this_turn)
	elif player_cards_played_this_turn == YELLOW_CARD_THRESHOLD:
		_resolve_item_commands(item_runtime.trigger(
			ITEM_EFFECT.Trigger.YELLOW_CARD_ISSUED,
			_base_item_context()
		))
		_log("黄牌警告！本回合已打出 %d 张牌" % player_cards_played_this_turn)
		discipline_card_issued.emit("yellow", player_cards_played_this_turn)


# 事件字典的 get() 返回 Variant，默认 [] 也是未定型数组；在边界逐项校验，避免把普通 Array
# 传给 Array[Dictionary] 参数而中断卡牌结算。复杂结构命令仍留给具体奖励品接入。
func _resolve_item_commands(raw_commands: Variant) -> void:
	if raw_commands is not Array:
		return
	for entry in raw_commands:
		if entry is not Dictionary:
			continue
		var command: Dictionary = entry
		match String(command.get("command", "")):
			"gain_health":
				player.heal(ceili(float(command.get("amount", 0.0))))
			"gain_energy":
				player.gain_energy(ceili(float(command.get("amount", 0.0))))
			"gain_temporary_energy":
				player.gain_temporary_energy(ceili(float(command.get("amount", 0.0))))
			"carry_unspent_energy":
				pending_carried_energy = maxi(player.energy, 0)
			"gain_shield":
				player.gain_shield(ceili(float(command.get("amount", 0.0))))


# 通用触发上下文只暴露结算所需状态，奖励品不得持有或修改控制器节点本身。
func _base_item_context() -> Dictionary:
	return {
		"turn_number": turn_number,
		"cards_played_this_turn": player_cards_played_this_turn,
		"player_health": player.health,
		"player_max_health": player.max_health,
		"player_energy": player.energy,
		"player_max_energy": player.max_energy,
	}


# 锁定战斗状态、清除意图并广播最终胜负。
func _finish_battle(victory: bool) -> void:
	phase = Phase.FINISHED
	# 怪物死亡或玩家失败即结束本场，清除方向牌效果；下一只怪物仍由 setup 从随机方向开始。
	banana_shot_direction = 0
	enemy_intent_damage = 0
	_log("战斗胜利" if victory else "战斗失败")
	state_changed.emit()
	battle_finished.emit(victory)


# 把结构化效果事件转换为玩家可读的中文战斗日志。
func _log_effect_event(event: Dictionary) -> void:
	match event.type:
		"damage":
			var hit_text := ""
			var hits: int = event.get("hits", 1)
			if hits > 1:
				hit_text = "第%d/%d段：" % [event.get("hit", 1), hits]
			_log("效果：%s%d 伤害（护盾吸收 %d，生命损失 %d）" % [
				hit_text,
				event.amount,
				event.absorbed,
				event.health_damage,
			])
		"shield":
			_log("效果：获得 %d 护盾" % event.amount)
		"heal":
			_log("效果：恢复 %d 生命" % event.amount)
		"energy":
			_log("效果：恢复 %d 能量" % event.amount)
		"strength":
			_log("效果：力量变为 ×%.1f，持续 %d 回合" % [event.multiplier, event.turns])
		"weakness":
			_log("效果：虚弱变为 ×%.1f，持续 %d 回合" % [event.multiplier, event.turns])
		"bgm_pitch":
			if event.get("reset", false):
				_log("效果：BGM 恢复原调")
			else:
				_log("效果：BGM %s 1 个半音" % (
					"升高" if event.get("semitone_delta", 0) > 0 else "降低"
				))
		"banana_direction":
			_log("效果：本场香蕉球改为向%s踢出" % ("左" if int(event.direction) < 0 else "右"))
		"chance":
			_log("效果：概率判定 %d/%d，%s" % [
				event.roll,
				event.chance_percent,
				"触发" if event.succeeded else "未触发",
			])
		"effect_interrupted":
			_log("效果：后续结算已中断")
		_:
			_log("效果暂未支持：%s" % event.get("effect_type", "unknown"))


# 所有战斗日志统一从此信号出口发送给表现层。
func _log(message: String) -> void:
	log_added.emit(message)
