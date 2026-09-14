# 奖励品效果配置：描述触发时机、过滤条件和数值操作，本身不保存战斗中的计数或待消费状态。
class_name ItemEffectDefinition
extends Resource

# 触发点按战斗结算顺序排列；新增奖励品优先复用这些阶段，避免在控制器中判断具体物品 ID。
enum Trigger {
	BATTLE_STARTED,
	TURN_STARTED,
	BEFORE_CARD_PLAYED,
	AFTER_CARD_PLAYED,
	BEFORE_DAMAGE,
	AFTER_DAMAGE,
	YELLOW_CARD_ISSUED,
	ACTIVE_SKILL_FINISHED,
	TURN_ENDED,
	# 转换球型必须先于随机球路和连续计数，避免奖励品获得顺序影响结果。
	BEFORE_SHOT_RESOLVED,
}

# 首版框架提供通用数值修改和命令出口；复杂效果由命令消费者执行，配置层不直接依赖战斗节点。
enum Operation {
	ADD,
	MULTIPLY,
	SET,
	INCREMENT_COUNTER,
	CLEAR_COUNTER,
	EMIT_COMMAND,
	# 同一张多段牌只更新一次连续计数，随后每段伤害读取同一层数。
	UPDATE_BANANA_STREAK,
	ADD_COUNTER,
}

enum CardFilter { ANY, ATTACK, DEFENSE, ABILITY }
enum ShotFilter { ANY, NONE, STRAIGHT, BANANA, LOB, RANDOM }
enum DirectionFilter { ANY, LEFT, RIGHT }
enum RhythmFilter { ANY, PERFECT, GOOD, MISS }
enum TargetFilter { ANY, ENEMY, SELF }

@export var trigger := Trigger.BEFORE_DAMAGE
@export var operation := Operation.ADD
# target_key 指向触发上下文中的整数或浮点字段；EMIT_COMMAND 时作为稳定命令名。
@export var target_key := "amount"
@export var amount := 0.0
@export_range(0, 100, 1) var chance_percent := 100
@export var card_filter := CardFilter.ANY
@export var shot_filter := ShotFilter.ANY
@export var direction_filter := DirectionFilter.ANY
@export var rhythm_filter := RhythmFilter.ANY
@export var target_filter := TargetFilter.ANY
# “踢出的球”仅包含有效射门；纯技能、治疗、防御不改变连续香蕉球计数。
@export var requires_shot := false
@export var counter_key := ""
@export_range(0, 999, 1) var counter_minimum := 0
@export_range(0, 999, 1) var counter_maximum := 999
@export var once_per_turn := false
