# 单个卡牌效果的固定定义；多个效果按卡牌数组顺序依次执行。
class_name EffectDefinition
extends Resource

# 通用效果类型，避免为每张卡牌创建独立脚本。
enum EffectType {
	DAMAGE,
	SHIELD,
	HEAL,
	ENERGY,
	APPLY_STRENGTH,
	APPLY_WEAKNESS,
}

# 效果目标相对于出牌者确定。
enum Target {
	SELF,
	ENEMY,
}

@export var effect_type := EffectType.DAMAGE
@export var target := Target.ENEMY
# amount 是基础值；hits 控制多段次数；amount_per_energy 读取费用支付后的剩余能量。
@export_range(0, 999, 1) var amount := 0
@export_range(1, 99, 1) var hits := 1
@export_range(0, 999, 1) var amount_per_energy := 0
# 概率判定成功后可选择中断整张卡的后续效果，例如爆炸球自爆。
@export_range(0, 100, 1) var chance_percent := 100
@export var interrupt_on_success := false
