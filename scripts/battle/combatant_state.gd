# 战斗角色的纯运行时状态，供玩家和敌人共用，不持有场景节点。
class_name CombatantState
extends RefCounted

enum StrengthStatus {
	NONE,
	STRENGTH,
	WEAKNESS,
}

# 生命、护盾、能量和力量倍率都属于单场战斗临时数据。
var display_name: String
var max_health: int
var health: int
var shield := 0
var max_energy: int
var energy: int
var strength_multiplier := 1.0
var strength_status := StrengthStatus.NONE
var strength_turns := 0


# 创建角色并把生命、能量初始化为各自上限。
func _init(combatant_name := "角色", maximum_health := 1, maximum_energy := 0) -> void:
	display_name = combatant_name
	max_health = maxi(maximum_health, 1)
	health = max_health
	max_energy = maxi(maximum_energy, 0)
	energy = max_energy


# 先用护盾吸收伤害，再扣生命；返回明细供日志和表现层使用。
func take_damage(raw_damage: int) -> Dictionary:
	var damage := maxi(raw_damage, 0)
	var absorbed := mini(shield, damage)
	shield -= absorbed
	var health_damage := mini(health, damage - absorbed)
	health -= health_damage
	return {
		"incoming": damage,
		"absorbed": absorbed,
		"health_damage": health_damage,
		"died": is_dead(),
	}


# 恢复生命但不超过上限，并返回实际恢复量。
func heal(raw_amount: int) -> int:
	var previous_health := health
	health = mini(health + maxi(raw_amount, 0), max_health)
	return health - previous_health


# 增加护盾并返回实际增加量；当前规则不设置护盾上限。
func gain_shield(raw_amount: int) -> int:
	var gained := maxi(raw_amount, 0)
	shield += gained
	return gained


# 清空护盾并返回被清除的数量，用于回合开始日志。
func clear_shield() -> int:
	var cleared := shield
	shield = 0
	return cleared


# 将能量恢复到上限，并返回实际恢复量。
func refill_energy() -> int:
	var restored := max_energy - energy
	energy = max_energy
	return restored


# 恢复能量但不超过上限。
func gain_energy(raw_amount: int) -> int:
	var previous_energy := energy
	energy = mini(energy + maxi(raw_amount, 0), max_energy)
	return energy - previous_energy


# 判断当前能量是否足以支付费用，负费用按零处理。
func can_spend_energy(cost: int) -> bool:
	return energy >= maxi(cost, 0)


# 安全扣除费用；能量不足时保持原值并返回失败。
func spend_energy(cost: int) -> bool:
	var safe_cost := maxi(cost, 0)
	if not can_spend_energy(safe_cost):
		return false
	energy -= safe_cost
	return true


# 施加力量状态；同类状态只增加持续时间，不叠加倍率。
func apply_strength(new_multiplier: float, turns: int) -> int:
	return _apply_strength_status(
		StrengthStatus.STRENGTH,
		maxf(new_multiplier, 1.0),
		turns
	)


# 施加虚弱状态；倍率被限制在 0～1，避免意外把减益变成增益。
func apply_weakness(new_multiplier: float, turns: int) -> int:
	return _apply_strength_status(
		StrengthStatus.WEAKNESS,
		clampf(new_multiplier, 0.0, 1.0),
		turns
	)


# 受影响角色完成自己的回合后调用；持续时间归零时恢复正常伤害。
func advance_strength_turn() -> Dictionary:
	if strength_status == StrengthStatus.NONE:
		return {"expired": false, "remaining_turns": 0, "status": StrengthStatus.NONE}

	var previous_status := strength_status
	strength_turns = maxi(strength_turns - 1, 0)
	var expired := strength_turns == 0
	if expired:
		strength_status = StrengthStatus.NONE
		strength_multiplier = 1.0
	return {
		"expired": expired,
		"remaining_turns": strength_turns,
		"status": previous_status,
	}


# 返回紧凑的中文状态文字，供战斗界面显示。
func get_strength_status_text() -> String:
	match strength_status:
		StrengthStatus.STRENGTH:
			return "力量×%.1f（%d）" % [strength_multiplier, strength_turns]
		StrengthStatus.WEAKNESS:
			return "虚弱×%.1f（%d）" % [strength_multiplier, strength_turns]
		_:
			return "无"


# 切换状态时替换原状态；再次施加同类状态时延长回合数。
func _apply_strength_status(new_status: int, new_multiplier: float, turns: int) -> int:
	var safe_turns := maxi(turns, 0)
	if safe_turns == 0:
		return strength_turns
	if strength_status == new_status:
		strength_turns += safe_turns
	else:
		strength_status = new_status
		strength_multiplier = new_multiplier
		strength_turns = safe_turns
	return strength_turns


# 生命归零即视为死亡。
func is_dead() -> bool:
	return health <= 0
