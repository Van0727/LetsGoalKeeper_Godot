@tool
# 敌人固定定义：保存数字ID、房间级别、行为列表及兼容旧资源的被动；不保存战斗临时状态。
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
# 数字 ID 是新配表查找键；enemy_id 仅保留为旧存档迁移键和资源名。
@export var id := 0
# 图片 ID 对应 assets/ui/enemies 下的同名 PNG；0 表示沿用通用占位图。
@export var image_id := 0
# 战斗头像的基础视觉倍率；只影响战斗表现，不改变地图图标、数值或存档。
@export var battle_image_scale := 1.0
@export var chapter := 1
@export var action_ids: Array[int] = []
@export var action_weights: Array[int] = []
@export var display_name := "敌人"
@export var tier := Tier.NORMAL
@export_range(1, 9999, 1) var max_health := 1
@export var action_mode := ActionMode.SEQUENCE
@export var actions: Array[Resource] = []
@export var passive_type := PassiveType.NONE
# 反伤被动按整数使用，主动技减伤按 0～1 比例使用。
@export_range(0.0, 999.0, 0.05) var passive_value := 0.0
@export_multiline var passive_description := ""
# 禁用项保留ID和目录记录，但不得进入正式遭遇池。
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
