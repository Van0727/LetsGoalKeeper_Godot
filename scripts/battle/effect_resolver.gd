class_name EffectResolver
extends RefCounted

const EFFECT_DEFINITION := preload("res://scripts/cards/effect_definition.gd")


func resolve_card(card: Resource, source, opponent) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for effect in card.effects:
		var recipient = source if effect.target == EFFECT_DEFINITION.Target.SELF else opponent
		match effect.effect_type:
			EFFECT_DEFINITION.EffectType.DAMAGE:
				_resolve_damage(effect, source, recipient, events)
			EFFECT_DEFINITION.EffectType.SHIELD:
				var gained: int = recipient.gain_shield(effect.amount)
				events.append({"type": "shield", "amount": gained, "target": recipient})
			EFFECT_DEFINITION.EffectType.HEAL:
				var healed: int = recipient.heal(effect.amount)
				events.append({"type": "heal", "amount": healed, "target": recipient})
			EFFECT_DEFINITION.EffectType.ENERGY:
				var restored: int = recipient.gain_energy(effect.amount)
				events.append({"type": "energy", "amount": restored, "target": recipient})
			_:
				events.append({"type": "unsupported", "effect_type": effect.effect_type})

		if opponent.is_dead() or source.is_dead():
			break
	return events


func _resolve_damage(effect: Resource, source, recipient, events: Array[Dictionary]) -> void:
	for hit_index in range(effect.hits):
		var damage := maxi(roundi(effect.amount * source.strength_multiplier), 0)
		var result: Dictionary = recipient.take_damage(damage)
		events.append({
			"type": "damage",
			"amount": damage,
			"absorbed": result.absorbed,
			"health_damage": result.health_damage,
			"hit": hit_index + 1,
			"target": recipient,
		})
		if recipient.is_dead():
			break
