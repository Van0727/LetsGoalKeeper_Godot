# 敌人固定定义：保存稳定 ID、房间级别、行动模式和少量明确的特殊被动配置。
class_name EnemyDefinition
extends Resource

enum Tier {
	NORMAL,
	ELITE,
	BOSS,
}

enum ActionMode {
	SEQUENCE,
	WEIGHTED_RANDOM,
}

enum PassiveType {
	NONE,
	THORNS,
	ACTIVE_SKILL_REDUCTION,
}

@export var enemy_id := ""
@export var display_name := "敌人"
@export var tier := Tier.NORMAL
@export_range(1, 9999, 1) var max_health := 1
@export var action_mode := ActionMode.SEQUENCE
@export var actions: Array[Resource] = []
@export var passive_type := PassiveType.NONE
# 反伤被动按整数使用，主动技减伤按 0～1 比例使用。
@export_range(0.0, 999.0, 0.05) var passive_value := 0.0
@export_multiline var passive_description := ""
# Unity 中生命为 6 的占位敌人保持禁用，防止误入正式遭遇池。
@export var encounter_enabled := true
@export_multiline var migration_note := ""


# 返回房间级别短文本，供调试界面和错误日志使用。
func get_tier_text() -> String:
	match tier:
		Tier.ELITE:
			return "精英"
		Tier.BOSS:
			return "Boss"
		_:
			return "普通"
