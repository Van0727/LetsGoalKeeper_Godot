# 卡牌固定定义：只保存可复用的配置数据，不保存单场战斗中的运行状态。
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
@export var rarity := Rarity.COMMON
@export var effects: Array[Resource] = []
