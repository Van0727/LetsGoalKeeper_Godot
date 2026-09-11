@tool
# 单个卡牌效果的固定定义；支持编辑器 CSV 导入，多个效果按卡牌数组顺序依次执行。
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
	BGM_PITCH_UP,
	BGM_PITCH_DOWN,
	BGM_PITCH_RESET,
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
# multiplier 用于力量和虚弱等倍率状态，具体持续回合由 amount 表示。
@export_range(0.0, 10.0, 0.05) var multiplier := 1.0
# 概率判定成功后可选择中断整张卡的后续效果，例如爆炸球自爆。
@export_range(0, 100, 1) var chance_percent := 100
@export var interrupt_on_success := false
