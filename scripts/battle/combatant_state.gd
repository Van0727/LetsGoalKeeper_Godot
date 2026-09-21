# 战斗角色的纯运行时状态，供玩家和敌人共用，不持有场景节点。
class_name CombatantState
extends RefCounted

# 在每段真实伤害后立即通知战斗核心，保证同步多段、延迟飞球和主动技使用相同机制。
signal damage_taken(result: Dictionary)

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
# 流血与格挡均为单场临时状态；流血不叠加伤害，格挡只消费一次正数攻击。
var bleed_amount := 0
var bleed_turns := 0
var single_block := 0


# 创建角色并把生命、能量初始化为各自上限。
func _init(combatant_name := "角色", maximum_health := 1, maximum_energy := 0) -> void:
	display_name = combatant_name
	max_health = maxi(maximum_health, 1)
	health = max_health
	max_energy = maxi(maximum_energy, 0)
	energy = max_energy


# 先消费单次格挡，再由护盾吸收、最后扣生命；致死或溢出伤害必须把生命固定在 0，
# 以便死亡判定、事件快照和血条显示读取到同一份合法状态。
func take_damage(raw_damage: int) -> Dictionary:
	var damage := maxi(raw_damage, 0)
	var blocked := 0
	if damage > 0 and single_block > 0:
		blocked = mini(damage, single_block)
		damage -= blocked
		single_block = 0
	var absorbed := mini(shield, damage)
	shield -= absorbed
	var health_damage := mini(maxi(health, 0), damage - absorbed)
	health = maxi(health - health_damage, 0)
	var result := {
		"incoming": damage,
		"blocked": blocked,
		"absorbed": absorbed,
		"health_damage": health_damage,
		"died": is_dead(),
	}
	damage_taken.emit(result)
	return result


# 重复流血分别保留较高伤害与较长时间；无效参数不能覆盖合法状态。
func apply_bleed(amount: int, turns: int) -> void:
	if amount <= 0 or turns <= 0:
		return
	bleed_amount = maxi(bleed_amount, amount)
	bleed_turns = maxi(bleed_turns, turns)


# 自身回合结束时结算一次流血，护盾可以吸收；流血不消耗单次攻击格挡。
func tick_bleed() -> Dictionary:
	if bleed_turns <= 0 or is_dead():
		return {}
	var saved_block := single_block
	single_block = 0
	var amount := bleed_amount
	var result := take_damage(amount)
	single_block = saved_block
	bleed_turns -= 1
	if bleed_turns == 0:
		bleed_amount = 0
	return {"type": "damage", "amount": amount, "absorbed": result.absorbed,
		"health_damage": result.health_damage, "damage_tag": "bleed", "target": self,
		"health_after": health, "shield_after": shield}


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


# 主动消耗护盾时不触发受伤或反伤；返回实际消耗量，避免需求超过现有护盾时出现负值。
func spend_shield(raw_amount: int) -> int:
	var spent := mini(shield, maxi(raw_amount, 0))
	shield -= spent
	return spent


# 清空护盾并返回被清除的数量，用于回合开始日志。
func clear_shield() -> int:
	var cleared := shield
	shield = 0
	return cleared


# 将能量恢复到基础上限；上一回合未消费的临时溢出能量在此被清除。
func refill_energy() -> int:
	var restored := maxi(max_energy - energy, 0)
	energy = max_energy
	return restored


# 恢复能量但不超过基础上限；已有临时溢出时不能因普通回能反而降低当前能量。
func gain_energy(raw_amount: int) -> int:
	var previous_energy := energy
	energy = mini(energy + maxi(raw_amount, 0), maxi(max_energy, energy))
	return energy - previous_energy


# 临时额外能量允许超过基础上限，只在当前玩家回合可用，下一次 refill_energy 时清除。
func gain_temporary_energy(raw_amount: int) -> int:
	var gained := maxi(raw_amount, 0)
	energy += gained
	return gained


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
