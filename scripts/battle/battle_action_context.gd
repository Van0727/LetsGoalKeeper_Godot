# 单次出牌上下文：在出牌前锁定牌型、实际球路、方向和节拍信息，并贯穿每一段伤害结算。
class_name BattleActionContext
extends RefCounted

var card: Resource
var card_type := 0
var configured_shot_type := 0
var actual_shot_type := 0
# 方向使用玩家视角：-1 为左、1 为右、0 为无方向。
var shot_direction := 0
var rhythm_result: Dictionary = {}
var beat_index := -1
var bar_index := -1
var beat_in_bar := -1
var subdivision := 4
var value_multiplier := 1.0


# 只复制只读输入，避免奖励品修改共享卡牌 Resource 或节奏判定字典。
func setup(card_definition: Resource, timing: Dictionary, beats_per_bar := 4) -> void:
	card = card_definition
	card_type = int(card_definition.card_type) if card_definition != null else 0
	configured_shot_type = int(card_definition.shot_type) if card_definition != null else 0
	actual_shot_type = configured_shot_type
	rhythm_result = timing.duplicate(true)
	beat_index = int(timing.get("beat_index", -1))
	bar_index = int(timing.get("bar_index", -1))
	beat_in_bar = posmod(beat_index, maxi(beats_per_bar, 1)) if beat_index >= 0 else -1
	subdivision = maxi(int(timing.get("subdivision", 4)), 1)


# 触发器使用普通字典读写；最终伤害统一向上取整，保证游戏内不产生小数数值。
func to_trigger_context() -> Dictionary:
	return {
		"card": card,
		"card_type": card_type,
		"shot_type": actual_shot_type,
		"shot_direction": shot_direction,
		"rhythm_grade": int(rhythm_result.get("grade", -1)),
		"beat_index": beat_index,
		"bar_index": bar_index,
		"beat_in_bar": beat_in_bar,
		"subdivision": subdivision,
		"value_multiplier": value_multiplier,
	}

