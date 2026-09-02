class_name EffectDefinition
extends Resource

enum EffectType {
	DAMAGE,
	SHIELD,
	HEAL,
	ENERGY,
	APPLY_STRENGTH,
	APPLY_WEAKNESS,
}

enum Target {
	SELF,
	ENEMY,
}

@export var effect_type := EffectType.DAMAGE
@export var target := Target.ENEMY
@export_range(0, 999, 1) var amount := 0
@export_range(1, 99, 1) var hits := 1
