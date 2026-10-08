# 单场战斗连击状态：连续同类卡累积点数，换类重置，并在主动技后清空。
class_name ComboState
extends RefCounted

const EMPTY_TYPE := -1
const SKILL_THRESHOLD := 3

var card_type := EMPTY_TYPE
var count := 0


# 记录成功出牌；同类型蓄力不设玩法上限，换类型从1重新开始，三层仅为释放门槛。
func register_card(new_card_type: int) -> int:
	if card_type == new_card_type:
		count += 1
	else:
		card_type = new_card_type
		count = 1
	return count


# 满三点且存在有效类型时允许释放当前类型主动技。
func can_activate() -> bool:
	return card_type != EMPTY_TYPE and count >= SKILL_THRESHOLD


# 主动技或新房间调用，连击类型与点数必须同时清空。
func clear() -> void:
	card_type = EMPTY_TYPE
	count = 0
