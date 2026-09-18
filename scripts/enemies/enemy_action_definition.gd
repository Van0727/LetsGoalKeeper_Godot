@tool
# 敌人行为固定定义：新版按攻击、防御、技能分类及结构化步骤结算，旧资源保留原行动字段。
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
# 新版行为按三类归属，效果数组按顺序执行；空效果数组兼容旧版资源。
enum Category { ATTACK, DEFENSE, SKILL }
@export var id := 0
@export var category := Category.ATTACK
@export_multiline var description := ""
@export var effects: Array[Resource] = []
# 蓄力失败只替换当前行为，不改变固定列表的推进位置。
@export var interrupted_action_id := 0
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
	if not effects.is_empty():
		return "%s·%s：%s" % [["攻击", "防御", "技能"][category], display_name, description]
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
