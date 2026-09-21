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

# 数字 ID 是运行时玩法判断的正式键；英文稳定 ID 继续兼容资源路径和旧存档。
@export_range(1, 65535, 1) var id := 1
@export var card_id := ""
@export var display_name := ""
@export_multiline var description := ""
# 流派倾向仅供策划和调试界面阅读，战斗程序不得据此判断效果。
@export var archetype_hint := ""
@export_range(0, 99, 1) var cost := 1
# 可选的卡牌专属插画；卡框、文字和交互仍由统一场景负责，旧资源留空即可兼容。
@export var illustration: Texture2D
@export var card_type := CardType.ATTACK
@export var shot_type := ShotType.NONE
# 攻击牌的时间统一以当前战斗 BPM 换算：延迟与多段间隔都支持万分之一拍精度；
# 每段足球从发射到命中使用延迟拍数，相邻两段按间隔发射，因此允许多个足球同时在空中。
@export_range(0.0, 16.0, 0.0001, "or_greater") var attack_delay_beats := 1.0
@export_range(0.0, 16.0, 0.0001, "or_greater") var multi_hit_interval_beats := 0.5
@export var rarity := Rarity.COMMON
# 实装状态只控制新奖励与正常游戏入口；资源仍保留，供旧存档和GM诊断安全读取。
@export var enabled := true
@export var effects: Array[Resource] = []
