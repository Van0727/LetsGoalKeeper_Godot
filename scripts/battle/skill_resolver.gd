# 主动技能执行器：按定义和连击点结算三类技能，并产出与卡牌一致的表现事件。
class_name SkillResolver
extends RefCounted

const CARD_DEFINITION := preload("res://scripts/cards/card_definition.gd")


# 伤害倍率由战斗控制器根据敌人被动注入，执行器本身不依赖具体敌人 ID。
func resolve_skill(
		skill: Resource,
		combo_count: int,
		source,
		target,
		target_damage_multiplier: float = 1.0
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var points := maxi(combo_count, 0)
	match skill.card_type:
		CARD_DEFINITION.CardType.ATTACK:
			var raw_damage: float = float(skill.base_value * points) * source.strength_multiplier
			var damage: int = maxi(roundi(raw_damage * target_damage_multiplier), 0)
			var result: Dictionary = target.take_damage(damage)
			events.append({
				"type": "damage",
				"amount": damage,
				"absorbed": result.absorbed,
				"health_damage": result.health_damage,
				"target": target,
				"source": source,
				"damage_tag": "active_skill",
			})
		CARD_DEFINITION.CardType.DEFENSE:
			var gained: int = source.gain_shield(skill.base_value * points)
			events.append({"type": "shield", "amount": gained, "target": source})
		CARD_DEFINITION.CardType.ABILITY:
			var turns: int = source.apply_strength(skill.multiplier, skill.base_value * points)
			events.append({
				"type": "strength",
				"multiplier": source.strength_multiplier,
				"turns": turns,
				"target": source,
			})
	return events
