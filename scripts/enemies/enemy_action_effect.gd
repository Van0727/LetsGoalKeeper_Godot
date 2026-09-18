# 怪物行为的结构化效果步骤：类别与效果分离，一次行为可以包含伤害及附带状态。
@tool
class_name EnemyActionEffect
extends Resource

enum Type { DAMAGE, SHIELD, HEAL, WEAKNESS, STRENGTH, DRAIN, BLEED, BLOCK, THORNS, CHARGE }
enum Target { PLAYER, ENEMY }
enum BreakRule { NONE, HITS, DAMAGE }

@export var effect_type := Type.DAMAGE
@export var target := Target.PLAYER
@export var amount := 0
@export var hits := 1
@export var turns := 0
@export var multiplier := 1.0
# 蓄力条件、阈值使用数字枚举；反伤次数复用 hits，禁止解析显示文案决定规则。
@export var break_rule := BreakRule.NONE
@export var threshold := 0
