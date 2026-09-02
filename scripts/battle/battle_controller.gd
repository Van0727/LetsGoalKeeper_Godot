class_name BattleController
extends Node

signal log_added(message: String)
signal state_changed
signal battle_finished(victory: bool)

const COMBATANT_STATE := preload("res://scripts/battle/combatant_state.gd")
const PLAYER_MAX_HEALTH := 100
const ENEMY_MAX_HEALTH := 30
const ENEMY_BASE_DAMAGE := 8

enum Phase {
	NOT_STARTED,
	PLAYER_TURN,
	PLAYER_END,
	ENEMY_TURN,
	FINISHED,
}

var player = COMBATANT_STATE.new("玩家", PLAYER_MAX_HEALTH)
var enemy = COMBATANT_STATE.new("企鹅", ENEMY_MAX_HEALTH)
var phase := Phase.NOT_STARTED
var turn_number := 0
var enemy_intent_damage := 0
var seed := 0

var _rng := RandomNumberGenerator.new()


func setup(seed_value := 20260902) -> void:
	seed = seed_value
	_rng.seed = seed
	player = COMBATANT_STATE.new("玩家", PLAYER_MAX_HEALTH)
	enemy = COMBATANT_STATE.new("企鹅", ENEMY_MAX_HEALTH)
	turn_number = 1
	phase = Phase.NOT_STARTED
	_log("战斗开始，seed=%d" % seed)
	_start_player_turn()


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


func player_guard(amount := 6) -> bool:
	if not _can_player_act():
		return false
	var gained := player.gain_shield(amount)
	_log("玩家获得 %d 护盾" % gained)
	state_changed.emit()
	return true


func player_heal(amount := 6) -> bool:
	if not _can_player_act():
		return false
	var healed := player.heal(amount)
	_log("玩家尝试治疗 %d，实际恢复 %d" % [amount, healed])
	state_changed.emit()
	return true


func end_player_turn() -> bool:
	if not _can_player_act():
		return false
	phase = Phase.PLAYER_END
	_log("玩家结束第 %d 回合" % turn_number)
	_execute_enemy_turn()
	return true


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


func _start_player_turn() -> void:
	var cleared_shield := player.clear_shield()
	phase = Phase.PLAYER_TURN
	enemy_intent_damage = _roll_enemy_damage()
	_log("第 %d 回合：玩家行动（清除护盾 %d）" % [turn_number, cleared_shield])
	_log("敌人意图：攻击 %d" % enemy_intent_damage)
	state_changed.emit()


func _execute_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	var cleared_shield := enemy.clear_shield()
	_log("敌人行动（清除护盾 %d）" % cleared_shield)
	var result := player.take_damage(enemy_intent_damage)
	_log("敌人攻击：%d 伤害（护盾吸收 %d，生命损失 %d）" % [
		enemy_intent_damage,
		result.absorbed,
		result.health_damage,
	])
	if player.is_dead():
		_finish_battle(false)
		return
	turn_number += 1
	_start_player_turn()


func _roll_enemy_damage() -> int:
	return maxi(roundi(ENEMY_BASE_DAMAGE * _rng.randf_range(0.8, 1.2)), 0)


func _can_player_act() -> bool:
	if phase == Phase.PLAYER_TURN:
		return true
	_log("当前阶段不能执行玩家行动")
	return false


func _finish_battle(victory: bool) -> void:
	phase = Phase.FINISHED
	enemy_intent_damage = 0
	_log("战斗胜利" if victory else "战斗失败")
	state_changed.emit()
	battle_finished.emit(victory)


func _log(message: String) -> void:
	log_added.emit(message)
