# 单场战斗流程控制器：协调回合状态、卡牌结算、敌人行动和胜负信号。
class_name BattleController
extends Node

# 表现层通过信号读取日志和刷新状态，核心结算不等待动画回调。
signal log_added(message: String)
signal state_changed
signal battle_finished(victory: bool)

const COMBATANT_STATE := preload("res://scripts/battle/combatant_state.gd")
const EFFECT_RESOLVER := preload("res://scripts/battle/effect_resolver.gd")
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

var _rng := RandomNumberGenerator.new()
var _effect_resolver = EFFECT_RESOLVER.new()


# 用指定种子重置战斗，保证敌人意图和概率卡牌结果可复现。
func setup(seed_value := 20260902) -> void:
	battle_seed = seed_value
	_rng.seed = battle_seed
	player = COMBATANT_STATE.new("玩家", PLAYER_MAX_HEALTH, PLAYER_MAX_ENERGY)
	enemy = COMBATANT_STATE.new("企鹅", ENEMY_MAX_HEALTH)
	turn_number = 1
	phase = Phase.NOT_STARTED
	_log("战斗开始，seed=%d" % battle_seed)
	_start_player_turn()


# 早期测试保留的直接攻击接口，正式卡牌统一走 play_card。
func player_attack(base_damage := 6) -> bool:
	if not _can_player_act():
		return false
	var final_damage := maxi(roundi(base_damage * player.strength_multiplier), 0)
	var result := enemy.take_damage(final_damage)
	_log("玩家攻击：%d 伤害（护盾吸收 %d，生命损失 %d）" % [
		final_damage,
		result.absorbed,
		result.health_damage,
	])
	if enemy.is_dead():
		_finish_battle(true)
	else:
		state_changed.emit()
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


# 检查行动阶段与费用，支付成功后按顺序结算整张卡牌。
func play_card(card: Resource) -> bool:
	if not _can_player_act():
		return false
	if card == null:
		_log("无效卡牌")
		return false
	if not player.spend_energy(card.cost):
		_log("能量不足：%s 需要 %d，当前 %d" % [card.display_name, card.cost, player.energy])
		return false

	_log("打出 %s，支付 %d 能量" % [card.display_name, card.cost])
	var events := _effect_resolver.resolve_card(card, player, enemy, _rng)
	for event in events:
		_log_effect_event(event)

	if enemy.is_dead():
		_finish_battle(true)
	elif player.is_dead():
		_finish_battle(false)
	else:
		state_changed.emit()
	return true


# 从指定手牌位置出牌；只有结算成功才移动卡牌并补牌。
func play_card_from_hand(deck_state, hand_index: int) -> bool:
	if hand_index < 0 or hand_index >= deck_state.hand.size():
		_log("无效手牌位置")
		return false
	var card: Resource = deck_state.hand[hand_index]
	if not play_card(card):
		return false
	deck_state.play_card_at(hand_index)
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


# 玩家回合开始时清盾、回满能量并生成本回合敌人意图。
func _start_player_turn() -> void:
	var cleared_shield := player.clear_shield()
	var restored_energy := player.refill_energy()
	phase = Phase.PLAYER_TURN
	enemy_intent_damage = _roll_enemy_damage()
	_log("第 %d 回合：玩家行动（清除护盾 %d，恢复能量 %d）" % [turn_number, cleared_shield, restored_energy])
	_log("敌人意图：攻击 %d" % get_enemy_intent_damage())
	state_changed.emit()


# 执行敌方攻击；玩家存活时推进回合并重新进入玩家阶段。
func _execute_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	var cleared_shield := enemy.clear_shield()
	_log("敌人行动（清除护盾 %d）" % cleared_shield)
	var final_damage := get_enemy_intent_damage()
	var result := player.take_damage(final_damage)
	_log("敌人攻击：%d 伤害（护盾吸收 %d，生命损失 %d）" % [
		final_damage,
		result.absorbed,
		result.health_damage,
	])
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
			if event.hits > 1:
				hit_text = "第%d/%d段：" % [event.hit, event.hits]
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
