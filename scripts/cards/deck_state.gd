# 单场战斗牌堆状态：管理抽牌、手牌、弃牌与固定种子洗牌，不操作任何 UI。
class_name DeckState
extends RefCounted

# 三个数组只保存对卡牌定义 Resource 的引用，不修改定义本身。
var draw_pile: Array[Resource] = []
var discard_pile: Array[Resource] = []
var hand: Array[Resource] = []
var hand_limit := 3
# 全裸许可证仅投影本场可玩牌组；替换实例的 ID 映射回原牌，取消勾选可逐张原位恢复。
var _defense_origins: Dictionary = {}

var _rng := RandomNumberGenerator.new()


# 复制本局牌库并使用指定种子洗牌，确保相同种子的牌序可复现。
func setup(deck_definitions: Array[Resource], seed_value: int) -> void:
	draw_pile = deck_definitions.duplicate()
	discard_pile.clear()
	hand.clear()
	_defense_origins.clear()
	hand_limit = 3
	_rng.seed = seed_value
	_shuffle(draw_pile)


# 在抽牌堆、弃牌堆与手牌原位同步防御牌替换；共享卡牌 Resource 和 RunState 原始牌组不改写。
func sync_defense_replacement(enabled: bool, replacement_template: Resource) -> void:
	if enabled and replacement_template == null:
		return
	_sync_pile_defenses(draw_pile, enabled, replacement_template)
	_sync_pile_defenses(discard_pile, enabled, replacement_template)
	_sync_pile_defenses(hand, enabled, replacement_template)


func _sync_pile_defenses(pile: Array[Resource], enabled: bool, replacement_template: Resource) -> void:
	for index in range(pile.size()):
		var current: Resource = pile[index]
		if current == null:
			continue
		var instance_id := current.get_instance_id()
		if enabled:
			if _defense_origins.has(instance_id) or int(current.card_type) != 1:
				continue
			var replacement: Resource = replacement_template.duplicate(true)
			_defense_origins[replacement.get_instance_id()] = current
			pile[index] = replacement
		elif _defense_origins.has(instance_id):
			pile[index] = _defense_origins[instance_id]
			_defense_origins.erase(instance_id)


# 抽取指定数量的卡牌；牌堆不足时自动回洗弃牌堆。
func draw_cards(count: int) -> Array[Resource]:
	var drawn: Array[Resource] = []
	for _draw_index in range(mini(maxi(count, 0), maxi(hand_limit - hand.size(), 0))):
		var card := _draw_one()
		if card == null:
			break
		hand.append(card)
		drawn.append(card)
	return drawn


# 打出指定位置的手牌，移入弃牌堆，并尝试在原位置补一张牌。
func play_card_at(hand_index: int, draw_replacement := true) -> Resource:
	if hand_index < 0 or hand_index >= hand.size():
		return null

	var played_card: Resource = hand.pop_at(hand_index)
	discard_pile.append(played_card)
	if draw_replacement and hand.size() < hand_limit:
		var replacement := _draw_one()
		if replacement != null:
			hand.insert(hand_index, replacement)
	return played_card


# GM 切换蒙眼布时把超额手牌退回抽牌堆，取消后由界面补满；不丢失或复制卡牌。
func set_hand_limit(limit: int) -> void:
	hand_limit = maxi(limit, 1)
	while hand.size() > hand_limit:
		draw_pile.append(hand.pop_back())


# 换牌先抽候选再弃原手牌；仅一张牌且无候选时拒绝，空手可抽一张以兼容停抽组合。
func swap_single_hand_card() -> bool:
	if hand.size() > 1:
		return false
	if draw_pile.is_empty() and discard_pile.is_empty():
		return false
	var replacement := _draw_one()
	if replacement == null:
		return false
	if not hand.is_empty():
		discard_pile.append(hand.pop_back())
	hand.append(replacement)
	return true


# 回合结束时将所有剩余手牌移入弃牌堆。
func discard_hand() -> int:
	var discarded_count := hand.size()
	discard_pile.append_array(hand)
	hand.clear()
	return discarded_count


# 抽取牌堆顶的一张牌；没有任何可用牌时返回空值。
func _draw_one() -> Resource:
	if draw_pile.is_empty():
		_recycle_discard_pile()
	if draw_pile.is_empty():
		return null
	return draw_pile.pop_back()


# 抽牌堆为空时，把弃牌堆整体移回并重新洗牌。
func _recycle_discard_pile() -> void:
	if discard_pile.is_empty():
		return
	draw_pile.assign(discard_pile)
	discard_pile.clear()
	_shuffle(draw_pile)


# 使用当前随机数状态执行 Fisher-Yates 洗牌。
func _shuffle(cards: Array[Resource]) -> void:
	for index in range(cards.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := cards[index]
		cards[index] = cards[swap_index]
		cards[swap_index] = temporary
