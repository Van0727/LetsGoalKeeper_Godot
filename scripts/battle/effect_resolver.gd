# 卡牌效果执行器：只负责按数据结算并产出事件，不依赖动画或 UI。
class_name EffectResolver
extends RefCounted

const EFFECT_DEFINITION := preload("res://scripts/cards/effect_definition.gd")

# 直接调用且未注入战斗随机数时使用的后备随机数生成器。
var _fallback_rng := RandomNumberGenerator.new()


# 按数组顺序执行卡牌效果；概率失败会跳过当前效果，中断标记会终止后续效果。
func resolve_card(
		card: Resource,
		source,
		opponent,
		rng: RandomNumberGenerator = null,
		damage_modifiers: Dictionary = {},
		rhythm_result: Dictionary = {}
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	# 节奏倍率只作用于对手受到的直接伤害；自伤、治疗、护盾和状态保持卡牌原始规则。
	var rhythm_multiplier := clampf(
		float(rhythm_result.get("effect_multiplier", 1.0)),
		0.0,
		10.0
	)
	for effect in card.effects:
		# 概率事件保留掷骰明细，确保日志、测试和以后回放都能解释结果。
		var chance := clampi(effect.chance_percent, 0, 100)
		if chance < 100:
			var active_rng := rng if rng != null else _fallback_rng
			var roll := active_rng.randi_range(1, 100)
			var succeeded := roll <= chance
			events.append({
				"type": "chance",
				"chance_percent": chance,
				"roll": roll,
				"succeeded": succeeded,
			})
			if not succeeded:
				continue

		var recipient = source if effect.target == EFFECT_DEFINITION.Target.SELF else opponent
		match effect.effect_type:
			EFFECT_DEFINITION.EffectType.DAMAGE:
				var applied_rhythm_multiplier := rhythm_multiplier if recipient == opponent else 1.0
				_resolve_damage(
					effect,
					card.shot_type,
					source,
					recipient,
					events,
					damage_modifiers,
					applied_rhythm_multiplier
				)
			EFFECT_DEFINITION.EffectType.SHIELD:
				var gained: int = recipient.gain_shield(effect.amount)
				events.append({
					"type": "shield",
					"amount": gained,
					"target": recipient,
					"health_after": recipient.health,
					"shield_after": recipient.shield,
				})
			EFFECT_DEFINITION.EffectType.HEAL:
				var healed: int = recipient.heal(effect.amount)
				events.append({
					"type": "heal",
					"amount": healed,
					"target": recipient,
					"health_after": recipient.health,
					"shield_after": recipient.shield,
				})
			EFFECT_DEFINITION.EffectType.ENERGY:
				var restored: int = recipient.gain_energy(effect.amount)
				events.append({"type": "energy", "amount": restored, "target": recipient})
			EFFECT_DEFINITION.EffectType.APPLY_STRENGTH:
				var strength_turns: int = recipient.apply_strength(effect.multiplier, effect.amount)
				events.append({
					"type": "strength",
					"multiplier": recipient.strength_multiplier,
					"turns": strength_turns,
					"target": recipient,
				})
			EFFECT_DEFINITION.EffectType.APPLY_WEAKNESS:
				var weakness_turns: int = recipient.apply_weakness(effect.multiplier, effect.amount)
				events.append({
					"type": "weakness",
					"multiplier": recipient.strength_multiplier,
					"turns": weakness_turns,
					"target": recipient,
				})
			_:
				events.append({"type": "unsupported", "effect_type": effect.effect_type})

		# 中断发生在当前效果成功结算之后，例如爆炸球先自伤再取消攻击。
		if effect.interrupt_on_success:
			events.append({"type": "effect_interrupted"})
			break
		if opponent.is_dead() or source.is_dead():
			break
	return events


# 逐段结算伤害；每一段独立消耗护盾，目标死亡后立即停止剩余段数。
func _resolve_damage(
		effect: Resource,
		shot_type: int,
		source,
		recipient,
		events: Array[Dictionary],
		damage_modifiers: Dictionary,
		rhythm_multiplier: float
) -> void:
	for hit_index in range(effect.hits):
		# 能量加成读取费用支付后的运行时能量，不回写 EffectDefinition。
		var energy_bonus: int = source.energy * effect.amount_per_energy
		var item_bonus := _get_shot_damage_bonus(shot_type, damage_modifiers)
		var scaled_amount: int = effect.amount + energy_bonus + item_bonus
		var damage := maxi(roundi(
			scaled_amount * source.strength_multiplier * rhythm_multiplier
		), 0)
		var result: Dictionary = recipient.take_damage(damage)
		events.append({
			"type": "damage",
			"amount": damage,
			"base_amount": effect.amount,
			"energy_bonus": energy_bonus,
			"item_bonus": item_bonus,
			"rhythm_multiplier": rhythm_multiplier,
			"absorbed": result.absorbed,
			"health_damage": result.health_damage,
			"hit": hit_index + 1,
			"hits": effect.hits,
			"shot_type": shot_type,
			"target": recipient,
			"health_after": recipient.health,
			"shield_after": recipient.shield,
		})
		if recipient.is_dead():
			break


# 汇总所有射门加成与当前弹道专属加成；非射门效果不会获得战利品伤害。
func _get_shot_damage_bonus(shot_type: int, damage_modifiers: Dictionary) -> int:
	if shot_type == 0:
		return 0
	var bonus: int = damage_modifiers.get("all", 0)
	match shot_type:
		1: bonus += damage_modifiers.get("straight", 0)
		2: bonus += damage_modifiers.get("banana", 0)
		3: bonus += damage_modifiers.get("lob", 0)
	return bonus
