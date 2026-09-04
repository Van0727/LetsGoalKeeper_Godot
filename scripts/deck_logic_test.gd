extends Control

const DECK_STATE := preload("res://scripts/cards/deck_state.gd")
const STRAIGHT_SHOT := preload("res://data/cards/card_straight_shot.tres")
const BANANA_SHOT := preload("res://data/cards/card_banana_shot.tres")
const GLOVES := preload("res://data/cards/card_gloves.tres")
const SPORTS_DRINK := preload("res://data/cards/card_sports_drink.tres")
const TOWEL := preload("res://data/cards/card_towel.tres")
const TEST_SEED := 20260902

@onready var zone_status: Label = %ZoneStatus
@onready var hand_status: Label = %HandStatus
@onready var deck_log: TextEdit = %DeckLog

var _deck = DECK_STATE.new()


func _ready() -> void:
	_reset_deck()


func _on_draw_pressed() -> void:
	var drawn := _deck.draw_cards(3)
	_log("抽取 %d 张：%s" % [drawn.size(), _card_names(drawn)])
	_refresh_status()


func _on_play_pressed() -> void:
	var played := _deck.play_card_at(0)
	if played == null:
		_log("手牌为空，无法出牌")
	else:
		_log("打出 %s，并尝试在原位置补1张" % played.display_name)
	_refresh_status()


func _on_end_turn_pressed() -> void:
	var count := _deck.discard_hand()
	_log("回合结束，弃掉 %d 张手牌" % count)
	_refresh_status()


func _on_reset_pressed() -> void:
	_reset_deck()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _reset_deck() -> void:
	deck_log.clear()
	var definitions: Array[Resource] = [
		STRAIGHT_SHOT,
		STRAIGHT_SHOT,
		BANANA_SHOT,
		BANANA_SHOT,
		GLOVES,
		SPORTS_DRINK,
		TOWEL,
	]
	_deck.setup(definitions, TEST_SEED)
	_log("牌堆已按固定 seed 初始化")
	_refresh_status()


func _refresh_status() -> void:
	zone_status.text = "抽牌堆 %d　弃牌堆 %d　手牌 %d" % [
		_deck.draw_pile.size(),
		_deck.discard_pile.size(),
		_deck.hand.size(),
	]
	hand_status.text = "手牌：%s" % _card_names(_deck.hand)


func _card_names(cards: Array[Resource]) -> String:
	var names: PackedStringArray = []
	for card in cards:
		names.append(card.display_name)
	return "、".join(names) if not names.is_empty() else "无"


func _log(message: String) -> void:
	deck_log.text += message + "\n"
	deck_log.scroll_vertical = deck_log.get_line_count()
