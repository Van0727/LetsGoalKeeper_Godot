# 敌人行动固定定义：描述单次攻击、防御、治疗、虚弱或吸血行为及其意图文字。
class_name EnemyActionDefinition
extends Resource

enum ActionType {
	ATTACK,
	SHIELD,
	HEAL,
	APPLY_WEAKNESS,
	DRAIN,
}

@export var action_id := ""
@export var display_name := "行动"
@export var action_type := ActionType.ATTACK
@export_range(0, 999, 1) var amount := 0
# 攻击类行动在选定意图时只随机一次，界面显示随机后的最终值。
@export_range(0, 100, 1) var variance_percent := 0
# 虚弱用 amount 表示持续回合，multiplier 表示伤害倍率。
@export_range(0.0, 10.0, 0.05) var multiplier := 1.0
@export_range(1, 100, 1) var weight := 1


# 返回带最终数值的意图文字，避免界面重复推导行动规则。
func get_intent_text(resolved_amount: int) -> String:
	match action_type:
		ActionType.ATTACK:
			return "%s %d" % [display_name, resolved_amount]
		ActionType.SHIELD:
			return "%s %d" % [display_name, amount]
		ActionType.HEAL:
			return "%s %d" % [display_name, amount]
		ActionType.APPLY_WEAKNESS:
			return "%s %d回合" % [display_name, amount]
		ActionType.DRAIN:
			return "%s %d" % [display_name, resolved_amount]
		_:
			return display_name
