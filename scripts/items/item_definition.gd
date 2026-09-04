# 战利品固定定义：保存稳定ID、稀有度和射门伤害修正，不保存是否已拥有。
class_name ItemDefinition
extends Resource

enum Rarity { NORMAL, BOSS }
enum ModifierType { ALL_SHOTS, STRAIGHT, BANANA, LOB, DISABLED }

@export var item_id := ""
@export var display_name := "战利品"
@export_multiline var description := ""
@export var rarity := Rarity.NORMAL
@export var modifier_type := ModifierType.ALL_SHOTS
@export_range(0, 999, 1) var amount := 0
@export var enabled := true


# 将枚举转换为 RunState 的稳定修正键，禁用效果返回空字符串。
func get_modifier_key() -> String:
	match modifier_type:
		ModifierType.ALL_SHOTS: return "all"
		ModifierType.STRAIGHT: return "straight"
		ModifierType.BANANA: return "banana"
		ModifierType.LOB: return "lob"
		_: return ""
