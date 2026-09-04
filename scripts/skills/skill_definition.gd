# 主动技能固定定义：按卡牌类型配置每点连击的基础收益，不保存当前连击状态。
class_name SkillDefinition
extends Resource

@export var skill_id := ""
@export var display_name := "主动技能"
@export_multiline var description := ""
@export var card_type := 0
# 攻击和防御按“基础值×连击点”结算；能力按“基础回合×连击点”结算。
@export_range(0, 999, 1) var base_value := 0
@export_range(0.0, 10.0, 0.05) var multiplier := 1.0
