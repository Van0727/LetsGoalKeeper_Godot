# 单场战斗流程控制器：协调回合状态、卡牌结算、敌人行动和胜负信号。
class_name BattleController
extends Node

# 表现层通过信号读取日志和刷新状态，核心结算不等待动画回调。
signal log_added(message: String)
signal state_changed
# 表现层逐条消费结构化事件；事件携带结算后快照，允许界面按动画顺序延迟显示。
signal effect_resolved(event: Dictionary)
signal battle_finished(victory: bool)

const COMBATANT_STATE := preload("res://scripts/battle/combatant_state.gd")
const EFFECT_RESOLVER := preload("res://scripts/battle/effect_resolver.gd")
const COMBO_STATE := preload("res://scripts/battle/combo_state.gd")
const SKILL_RESOLVER := preload("res://scripts/battle/skill_resolver.gd")
const ENEMY_DEFINITION := preload("res://scripts/enemies/enemy_definition.gd")
const ENEMY_ACTION_DEFINITION := preload("res://scripts/enemies/enemy_action_definition.gd")
const PLAYER_MAX_HEALTH := 100
const PLAYER_MAX_ENERGY := 3
const ENEMY_MAX_HEALTH := 30
const ENEMY_BASE_DAMAGE := 8

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

var _rng := RandomNumberGenerator.new()
var _effect_resolver = EFFECT_RESOLVER.new()
var _skill_resolver = SKILL_RESOLVER.new()
var _enemy_action_index := 0


# 用指定种子和可选敌人定义重置战斗；不传定义时保留阶段 1 的企鹅测试行为。
func setup(seed_value := 20260902, enemy_definition: Resource = null, run_damage_modifiers: Dictionary = {}) -> void:
	battle_seed = seed_value
	_rng.seed = battle_seed
	damage_modifiers = run_damage_modifiers.duplicate()
	player = COMBATANT_STATE.new("玩家", PLAYER_MAX_HEALTH, PLAYER_MAX_ENERGY)
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
	combo_state = COMBO_STATE.new()
	turn_number = 1
	phase = Phase.NOT_STARTED
	_log("战斗开始，seed=%d" % battle_seed)
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
	if not rhythm_result.is_empty():
		_log("节奏判定：%s（%+.0fms）" % [
			rhythm_result.get("grade_name", "Miss"),
			float(rhythm_result.get("error_ms", 0.0)),
		])
	var events := _effect_resolver.resolve_card(
		card,
		player,
		enemy,
		_rng,
		damage_modifiers,
		rhythm_result,
		defer_enemy_shot_damage
	)
	for event in events:
		if not event.get("deferred_damage", false):
			_log_effect_event(event)
		effect_resolved.emit(event)
		if not event.get("deferred_damage", false):
			_resolve_reactive_passive(event)
		if player.is_dead():
			break
	combo_state.register_card(card.card_type)

	# 乌龟反伤导致双方同时死亡时按玩家失败裁定，避免死亡状态继续领奖。
	if player.is_dead():
		_finish_battle(false)
	elif enemy.is_dead():
		_finish_battle(true)
	else:
		state_changed.emit()
	return true


# 释放与当前连击类型匹配的主动技；结算完成后无论结果都清空类型与点数。
func play_active_skill(skill: Resource) -> bool:
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
	var events := _skill_resolver.resolve_skill(
		skill,
		points,
		player,
		enemy,
		damage_multiplier
	)
	for event in events:
		_log_effect_event(event)
		effect_resolved.emit(event)
		_resolve_reactive_passive(event)
	combo_state.clear()

	if player.is_dead():
		_finish_battle(false)
	elif enemy.is_dead():
		_finish_battle(true)
	else:
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
	deck_state.play_card_at(hand_index)
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
	_log_effect_event(event)
	_resolve_reactive_passive(event)
	# 命中造成双方同时死亡时仍按玩家失败裁定，与同步卡牌结算规则一致。
	if player.is_dead():
		_finish_battle(false)
	elif enemy.is_dead():
		_finish_battle(true)
	else:
		state_changed.emit()
	return true


# 结束玩家阶段并立即执行当前敌人行动。
func end_player_turn() -> bool:
	if not _can_player_act():
		return false
	phase = Phase.PLAYER_END
	_log("玩家结束第 %d 回合" % turn_number)
	_advance_strength_status(player)
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


# 玩家回合开始时清盾、回满能量并选定一次敌人行动及其最终随机值。
func _start_player_turn() -> void:
	var cleared_shield := player.clear_shield()
	var restored_energy := player.refill_energy()
	phase = Phase.PLAYER_TURN
	_prepare_enemy_intent()
	_log("第 %d 回合：玩家行动（清除护盾 %d，恢复能量 %d）" % [turn_number, cleared_shield, restored_energy])
	_log("敌人意图：%s" % get_enemy_intent_text())
	state_changed.emit()


# 执行已经展示的敌方行动；玩家存活时推进回合并生成下一次意图。
func _execute_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	var cleared_shield := enemy.clear_shield()
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
	return maxi(roundi(enemy_intent_damage * enemy.strength_multiplier), 0)


# 返回当前行动的最终意图文字；非攻击行为直接显示其数据值。
func get_enemy_intent_text() -> String:
	if current_enemy_action == null:
		return "攻击 %d" % get_enemy_intent_damage()
	return current_enemy_action.get_intent_text(get_enemy_intent_damage())


# 为线性敌人顺序取行动，为 Boss 按权重取行动，并仅在此刻结算随机浮动。
func _prepare_enemy_intent() -> void:
	if current_enemy_definition == null or current_enemy_definition.actions.is_empty():
		current_enemy_action = null
		enemy_intent_damage = _roll_enemy_damage()
		return

	if current_enemy_definition.action_mode == ENEMY_DEFINITION.ActionMode.WEIGHTED_RANDOM:
		current_enemy_action = _pick_weighted_action(current_enemy_definition.actions)
	else:
		current_enemy_action = current_enemy_definition.actions[
			_enemy_action_index % current_enemy_definition.actions.size()
		]

	var variance: float = current_enemy_action.variance_percent / 100.0
	if variance > 0.0:
		enemy_intent_damage = maxi(roundi(
			current_enemy_action.amount * _rng.randf_range(1.0 - variance, 1.0 + variance)
		), 0)
	else:
		enemy_intent_damage = current_enemy_action.amount


# 权重选择只读取定义；非正权重会被忽略，全部无效时安全回退第一项。
func _pick_weighted_action(actions: Array[Resource]) -> Resource:
	var total_weight := 0
	for action in actions:
		total_weight += maxi(action.weight, 0)
	if total_weight <= 0:
		return actions[0]
	var roll := _rng.randi_range(1, total_weight)
	for action in actions:
		roll -= maxi(action.weight, 0)
		if roll <= 0:
			return action
	return actions.back()


# 按行动类型执行攻击、防御、治疗、虚弱和吸血；每项都发送同一套表现事件。
func _execute_current_enemy_action() -> void:
	if current_enemy_action == null:
		_execute_enemy_damage(get_enemy_intent_damage(), false)
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
	if phase == Phase.PLAYER_TURN:
		return true
	_log("当前阶段不能执行玩家行动")
	return false


# 锁定战斗状态、清除意图并广播最终胜负。
func _finish_battle(victory: bool) -> void:
	phase = Phase.FINISHED
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
