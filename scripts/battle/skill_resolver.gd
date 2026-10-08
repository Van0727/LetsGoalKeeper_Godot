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
		target_damage_multiplier: float = 1.0,
		effect_multiplier: float = 1.0,
		defer_damage := false,
		rng: RandomNumberGenerator = null
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var points := maxi(combo_count, 0)
	match skill.card_type:
		CARD_DEFINITION.CardType.ATTACK:
			var raw_damage: float = float(skill.base_value * points) * source.strength_multiplier
			var damage: int = maxi(ceili(raw_damage * target_damage_multiplier * effect_multiplier), 0)
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
		CARD_DEFINITION.CardType.DEFENSE, CARD_DEFINITION.CardType.ABILITY:
			# 每层发射一次；手套先锁定释放时护盾再清空，后续反伤或状态变化不改变已锁定伤害。
			var defense: bool = skill.card_type == CARD_DEFINITION.CardType.DEFENSE
			var hits: int = points
			var random := rng if rng != null else RandomNumberGenerator.new()
			var base: float = float(source.shield) if defense else float(skill.base_value) * source.strength_multiplier
			if defense:
				var spent: int = source.clear_shield()
				events.append({"type": "shield_spent", "amount": spent, "target": source, "shield_after": 0})
			for index in range(hits):
				if target.is_dead() or source.is_dead():
					break
				var damage := maxi(ceili(base * target_damage_multiplier * effect_multiplier), 0)
				var shot_type: int = 1 if defense else random.randi_range(1, 3)
				var result: Dictionary = {"absorbed": 0, "health_damage": 0} if defer_damage else target.take_damage(damage)
				events.append({"type": "damage", "amount": damage, "absorbed": result.absorbed,
					"health_damage": result.health_damage, "target": target, "source": source,
					"health_after": target.health, "shield_after": target.shield,
					"damage_tag": "active_skill", "deferred_damage": defer_damage,
					"shot_type": shot_type, "shot_direction": -1 if random.randi_range(0, 1) == 0 else 1,
					"projectile_glove": defense, "hit": index + 1, "hits": hits,
					"attack_delay_beats": 1.0, "multi_hit_interval_beats": 0.5})
	return events
