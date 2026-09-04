class_name EffectResolver
extends RefCounted

const EFFECT_DEFINITION := preload("res://scripts/cards/effect_definition.gd")

var _fallback_rng := RandomNumberGenerator.new()


func resolve_card(
		card: Resource,
		source,
		opponent,
		rng: RandomNumberGenerator = null
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for effect in card.effects:
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
				_resolve_damage(effect, card.shot_type, source, recipient, events)
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

		if effect.interrupt_on_success:
			events.append({"type": "effect_interrupted"})
			break
		if opponent.is_dead() or source.is_dead():
			break
	return events


func _resolve_damage(
		effect: Resource,
		shot_type: int,
		source,
		recipient,
		events: Array[Dictionary]
) -> void:
	for hit_index in range(effect.hits):
		var damage := maxi(roundi(effect.amount * source.strength_multiplier), 0)
		var result: Dictionary = recipient.take_damage(damage)
		events.append({
			"type": "damage",
			"amount": damage,
			"absorbed": result.absorbed,
			"health_damage": result.health_damage,
			"hit": hit_index + 1,
			"hits": effect.hits,
			"shot_type": shot_type,
			"target": recipient,
		})
		if recipient.is_dead():
			break
