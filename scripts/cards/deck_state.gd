# 单场战斗牌堆状态：管理抽牌、手牌、弃牌与固定种子洗牌，不操作任何 UI。
class_name DeckState
extends RefCounted

# 三个数组只保存对卡牌定义 Resource 的引用，不修改定义本身。
var draw_pile: Array[Resource] = []
var discard_pile: Array[Resource] = []
var hand: Array[Resource] = []

var _rng := RandomNumberGenerator.new()


# 复制本局牌库并使用指定种子洗牌，确保相同种子的牌序可复现。
func setup(deck_definitions: Array[Resource], seed_value: int) -> void:
	draw_pile = deck_definitions.duplicate()
	discard_pile.clear()
	hand.clear()
	_rng.seed = seed_value
	_shuffle(draw_pile)


# 抽取指定数量的卡牌；牌堆不足时自动回洗弃牌堆。
func draw_cards(count: int) -> Array[Resource]:
	var drawn: Array[Resource] = []
	for _draw_index in range(maxi(count, 0)):
		var card := _draw_one()
		if card == null:
			break
		hand.append(card)
		drawn.append(card)
	return drawn


# 打出指定位置的手牌，移入弃牌堆，并尝试在原位置补一张牌。
func play_card_at(hand_index: int) -> Resource:
	if hand_index < 0 or hand_index >= hand.size():
		return null

	var played_card: Resource = hand.pop_at(hand_index)
	discard_pile.append(played_card)
	var replacement := _draw_one()
	if replacement != null:
		hand.insert(hand_index, replacement)
	return played_card


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
