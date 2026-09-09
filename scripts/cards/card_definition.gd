@tool
# 卡牌固定定义：可由编辑器 CSV 导入器创建，只保存可复用配置，不保存单场战斗运行状态。
class_name CardDefinition
extends Resource

# 卡牌大类用于连击、奖励池和界面样式分类。
enum CardType {
	ATTACK,
	DEFENSE,
	ABILITY,
}

# 射门类型供伤害结算事件和后续表现层选择弹道。
enum ShotType {
	NONE,
	STRAIGHT,
	BANANA,
	LOB,
	RANDOM,
}

# 稀有度用于区分普通奖励与 Boss 奖励。
enum Rarity {
	COMMON,
	BOSS,
}

# 英文稳定 ID 是存档和代码引用键；中文名称只负责显示。
@export var card_id := ""
@export var display_name := ""
@export_multiline var description := ""
@export_range(0, 99, 1) var cost := 1
@export var card_type := CardType.ATTACK
@export var shot_type := ShotType.NONE
# 攻击牌的时间统一以当前战斗 BPM 换算：每段足球从发射到命中使用延迟拍数，
# 多段间隔表示相邻两段的发射间距，因此间隔短于延迟时允许多个足球同时在空中。
@export_range(0.0, 16.0, 0.25, "or_greater") var attack_delay_beats := 1.0
@export_range(0.0, 16.0, 0.0001, "or_greater") var multi_hit_interval_beats := 0.5
@export var rarity := Rarity.COMMON
@export var effects: Array[Resource] = []
