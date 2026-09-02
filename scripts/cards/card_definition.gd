class_name CardDefinition
extends Resource

enum CardType {
	ATTACK,
	DEFENSE,
	ABILITY,
}

enum ShotType {
	NONE,
	STRAIGHT,
	BANANA,
	LOB,
	RANDOM,
}

enum Rarity {
	COMMON,
	BOSS,
}

@export var card_id := ""
@export var display_name := ""
@export_multiline var description := ""
@export_range(0, 99, 1) var cost := 1
@export var card_type := CardType.ATTACK
@export var shot_type := ShotType.NONE
@export var rarity := Rarity.COMMON
@export var effects: Array[Resource] = []
