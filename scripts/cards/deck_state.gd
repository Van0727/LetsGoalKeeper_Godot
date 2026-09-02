class_name DeckState
extends RefCounted

var draw_pile: Array[Resource] = []
var discard_pile: Array[Resource] = []
var hand: Array[Resource] = []

var _rng := RandomNumberGenerator.new()


func setup(deck_definitions: Array[Resource], seed: int) -> void:
	draw_pile = deck_definitions.duplicate()
	discard_pile.clear()
	hand.clear()
	_rng.seed = seed
	_shuffle(draw_pile)


func draw_cards(count: int) -> Array[Resource]:
	var drawn: Array[Resource] = []
	for _draw_index in range(maxi(count, 0)):
		var card := _draw_one()
		if card == null:
			break
		hand.append(card)
		drawn.append(card)
	return drawn


func play_card_at(hand_index: int) -> Resource:
	if hand_index < 0 or hand_index >= hand.size():
		return null

	var played_card: Resource = hand.pop_at(hand_index)
	discard_pile.append(played_card)
	var replacement := _draw_one()
	if replacement != null:
		hand.insert(hand_index, replacement)
	return played_card


func discard_hand() -> int:
	var discarded_count := hand.size()
	discard_pile.append_array(hand)
	hand.clear()
	return discarded_count


func _draw_one() -> Resource:
	if draw_pile.is_empty():
		_recycle_discard_pile()
	if draw_pile.is_empty():
		return null
	return draw_pile.pop_back()


func _recycle_discard_pile() -> void:
	if discard_pile.is_empty():
		return
	draw_pile.assign(discard_pile)
	discard_pile.clear()
	_shuffle(draw_pile)


func _shuffle(cards: Array[Resource]) -> void:
	for index in range(cards.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		var temporary := cards[index]
		cards[index] = cards[swap_index]
		cards[swap_index] = temporary
