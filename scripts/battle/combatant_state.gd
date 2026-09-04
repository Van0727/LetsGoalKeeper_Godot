class_name CombatantState
extends RefCounted

var display_name: String
var max_health: int
var health: int
var shield := 0
var max_energy: int
var energy: int
var strength_multiplier := 1.0


func _init(combatant_name := "角色", maximum_health := 1, maximum_energy := 0) -> void:
	display_name = combatant_name
	max_health = maxi(maximum_health, 1)
	health = max_health
	max_energy = maxi(maximum_energy, 0)
	energy = max_energy


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


func heal(raw_amount: int) -> int:
	var previous_health := health
	health = mini(health + maxi(raw_amount, 0), max_health)
	return health - previous_health


func gain_shield(raw_amount: int) -> int:
	var gained := maxi(raw_amount, 0)
	shield += gained
	return gained


func clear_shield() -> int:
	var cleared := shield
	shield = 0
	return cleared


func refill_energy() -> int:
	var restored := max_energy - energy
	energy = max_energy
	return restored


func gain_energy(raw_amount: int) -> int:
	var previous_energy := energy
	energy = mini(energy + maxi(raw_amount, 0), max_energy)
	return energy - previous_energy


func can_spend_energy(cost: int) -> bool:
	return energy >= maxi(cost, 0)


func spend_energy(cost: int) -> bool:
	var safe_cost := maxi(cost, 0)
	if not can_spend_energy(safe_cost):
		return false
	energy -= safe_cost
	return true


func is_dead() -> bool:
	return health <= 0
