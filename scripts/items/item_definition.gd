# 战利品固定定义：数字 ID 是唯一运行时键；英文 item_id 仅保留给资源文件与旧存档迁移。
class_name ItemDefinition
extends Resource

enum Rarity { NORMAL, BOSS }
enum ModifierType { ALL_SHOTS, STRAIGHT, BANANA, LOB, DISABLED }

@export_range(1, 65535, 1) var id := 1
@export var item_id := ""
@export var display_name := "战利品"
@export_multiline var description := ""
@export var rarity := Rarity.NORMAL
@export var modifier_type := ModifierType.ALL_SHOTS
@export_range(0, 999, 1) var amount := 0
# 游戏历程级最大能量加成由 RunState 汇总并存档；普通战斗触发效果仍放在 effects。
@export_range(0, 99, 1) var run_max_energy_bonus := 0
# 实装状态只控制正常奖励与GM勾选；定义仍保留，供旧存档按数字ID恢复。
@export var enabled := true
# 新奖励品使用效果数组配置；旧奖励品继续走 modifier_type，迁移期间两套数据可以并存。
@export var effects: Array[Resource] = []


# 将枚举转换为 RunState 的稳定修正键，禁用效果返回空字符串。
func get_modifier_key() -> String:
	match modifier_type:
		ModifierType.ALL_SHOTS: return "all"
		ModifierType.STRAIGHT: return "straight"
		ModifierType.BANANA: return "banana"
		ModifierType.LOB: return "lob"
		_: return ""
